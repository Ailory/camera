import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models/drive_config.dart';
import 'models/gallery_item.dart';
import 'models/google_account_profile.dart';
import 'models/remote_media.dart';
import 'models/upload_job.dart';
import 'services/google_drive_service.dart';
import 'services/queue_store.dart';
import 'services/settings_store.dart';

enum _UploadAttemptResult { success, retryableFailure, needsUserAction }

class AppController extends ChangeNotifier {
  AppController({
    QueueStore? queueStore,
    SettingsStore? settingsStore,
    GoogleDriveService? driveService,
  }) : _queueStore = queueStore ?? QueueStore(),
       _settingsStore = settingsStore ?? SettingsStore(),
       _driveService = driveService ?? GoogleDriveService();

  final QueueStore _queueStore;
  final SettingsStore _settingsStore;
  final GoogleDriveService _driveService;

  DriveConfig _config = DriveConfig.empty;
  bool _initialized = false;
  bool _processing = false;
  bool _uploadRecentlyCompleted = false;
  bool _galleryLoading = false;
  String? _message;
  List<RemoteMedia> _remoteMedia = const [];
  final Set<String> _deletingGalleryItems = <String>{};
  final Map<String, Future<Uint8List>> _thumbnailRequests = {};
  final Map<String, Future<Uint8List>> _photoRequests = {};
  int _galleryRequestSerial = 0;
  int _galleryMutationVersion = 0;
  Timer? _retryTimer;
  Timer? _completionTimer;

  bool get initialized => _initialized;
  bool get isProcessing => _processing;
  bool get isConfigured => _driveService.isConfigured;
  bool get isSignedIn => _driveService.isSignedIn;
  GoogleAccountProfile? get accountProfile => _driveService.profile;
  DriveConfig get config => _config;
  String? get message => _message;
  List<UploadJob> get jobs => _queueStore.jobs;
  List<GalleryItem> get galleryItems => buildGalleryItems(jobs, _remoteMedia);
  GalleryItem? get latestPhoto {
    final items = galleryItems;
    return items.isEmpty ? null : items.first;
  }

  bool get galleryLoading => _galleryLoading;
  bool get uploadRecentlyCompleted => _uploadRecentlyCompleted;
  bool get hasUploadError => jobs.any((job) => job.state == UploadState.failed);
  double get uploadProgress =>
      jobs
          .where((job) => job.state == UploadState.uploading)
          .map((job) => job.progress)
          .firstOrNull ??
      0;

  int get pendingCount => jobs
      .where(
        (job) =>
            job.state == UploadState.queued ||
            job.state == UploadState.uploading ||
            job.state == UploadState.failed,
      )
      .length;

  Future<void> initialize() async {
    try {
      _config = await _settingsStore.load();
      await _queueStore.load();
      _driveService.configure(_config);
      if (_driveService.isConfigured) {
        try {
          await _driveService.restoreSession();
        } catch (_) {
          // A stale token should not prevent the camera from opening.
        }
      }
      _initialized = true;
      notifyListeners();
      if (isSignedIn) {
        unawaited(_refreshGallery(showErrors: false));
        unawaited(_retryFailedThenProcess());
      }
    } catch (error) {
      _message = _friendlyError(error);
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> saveConfig(DriveConfig config) async {
    _config = config.copyWith(
      folderName: config.folderName.trim().isEmpty
          ? 'Cloud Camera'
          : config.folderName.trim(),
    );
    await _settingsStore.save(_config);
    _driveService.configure(_config);
    _clearRemoteGallery();
    notifyListeners();
    if (isSignedIn) unawaited(_refreshGallery(showErrors: true));
  }

  Future<bool> connectGoogle() async {
    try {
      _message = null;
      notifyListeners();
      final connected = await _driveService.signIn();
      if (!connected) {
        _message = 'Вход отменён.';
        notifyListeners();
        return false;
      }
      _message = 'Google Drive подключён.';
      notifyListeners();
      unawaited(_refreshGallery(showErrors: true));
      unawaited(_retryFailedThenProcess());
      return true;
    } catch (error) {
      _message = _friendlyError(error);
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnectGoogle() async {
    await _driveService.signOut();
    _clearRemoteGallery();
    _message = 'Аккаунт Google отключён.';
    notifyListeners();
  }

  Future<void> refreshGallery() => _refreshGallery(showErrors: true);

  Future<Uint8List> loadThumbnail(GalleryItem item) async {
    final localFile = _existingLocalFile(item);
    if (localFile != null) return localFile.readAsBytes();

    final fileId = item.driveFileId;
    if (fileId == null || fileId.isEmpty) {
      throw StateError('Фото больше не доступно на устройстве.');
    }
    final cached = _thumbnailRequests[fileId];
    if (cached != null) return cached;

    late final Future<Uint8List> request;
    request = _driveService
        .downloadThumbnail(fileId, thumbnailLink: item.thumbnailLink)
        .catchError((Object error, StackTrace stackTrace) {
          if (identical(_thumbnailRequests[fileId], request)) {
            _thumbnailRequests.remove(fileId);
          }
          Error.throwWithStackTrace(error, stackTrace);
        });
    _thumbnailRequests[fileId] = request;
    while (_thumbnailRequests.length > 24) {
      _thumbnailRequests.remove(_thumbnailRequests.keys.first);
    }
    return request;
  }

  Future<Uint8List> loadPhoto(GalleryItem item) async {
    final localFile = _existingLocalFile(item);
    if (localFile != null) return localFile.readAsBytes();

    final fileId = item.driveFileId;
    if (fileId == null || fileId.isEmpty) {
      throw StateError('Фото больше не доступно на устройстве.');
    }
    final activeRequest = _photoRequests[fileId];
    if (activeRequest != null) return activeRequest;

    final request = _driveService.downloadFile(fileId);
    _photoRequests[fileId] = request;
    request.then<void>(
      (_) => _photoRequests.remove(fileId),
      onError: (_, _) => _photoRequests.remove(fileId),
    );
    return request;
  }

  bool isDeletingGalleryItem(GalleryItem item) =>
      _deletingGalleryItems.contains(_galleryItemKey(item));

  Future<bool> deleteGalleryItem(GalleryItem item) async {
    final key = _galleryItemKey(item);
    if (_deletingGalleryItems.contains(key)) return false;

    final localJob = item.localJobId == null
        ? null
        : jobs.where((job) => job.id == item.localJobId).firstOrNull;
    if (item.isUploading || localJob?.state == UploadState.uploading) {
      _message = 'Дождитесь сохранения фото, затем удалите его.';
      notifyListeners();
      return false;
    }

    _deletingGalleryItems.add(key);
    _galleryMutationVersion++;
    notifyListeners();
    try {
      final driveFileId = item.driveFileId;
      if (driveFileId != null && driveFileId.isNotEmpty) {
        await _driveService.trashFile(driveFileId);
      }
      if (item.localJobId case final localJobId?) {
        await _queueStore.remove(localJobId);
      }
      if (driveFileId != null) {
        _remoteMedia = List.unmodifiable(
          _remoteMedia.where((media) => media.id != driveFileId),
        );
        _thumbnailRequests.remove(driveFileId);
        _photoRequests.remove(driveFileId);
      }
      _message = driveFileId == null
          ? 'Фото удалено.'
          : 'Фото перемещено в корзину Google Drive.';
      return true;
    } catch (error) {
      _message = _friendlyError(error);
      return false;
    } finally {
      _deletingGalleryItems.remove(key);
      notifyListeners();
    }
  }

  Future<UploadJob?> enqueueFile(String path, {String? displayName}) async {
    try {
      final job = await _queueStore.enqueue(path, displayName: displayName);
      _message = isSignedIn
          ? null
          : 'Войдите в Google, чтобы включить облачное сохранение.';
      notifyListeners();
      if (isSignedIn) unawaited(processQueue());
      return job;
    } catch (error) {
      _message = _friendlyError(error);
      notifyListeners();
      return null;
    }
  }

  Future<void> processQueue() async {
    if (_processing || !isSignedIn) return;
    _processing = true;
    notifyListeners();
    try {
      while (true) {
        final next = jobs
            .where((job) => job.state == UploadState.queued)
            .firstOrNull;
        if (next == null) break;
        final result = await _uploadOne(next);
        if (result != _UploadAttemptResult.success) {
          if (result == _UploadAttemptResult.retryableFailure) {
            _scheduleRetry();
          } else {
            _retryTimer?.cancel();
          }
          break;
        }
      }
    } finally {
      _processing = false;
      notifyListeners();
    }
  }

  Future<_UploadAttemptResult> _uploadOne(UploadJob original) async {
    var current = original.copyWith(
      state: UploadState.uploading,
      progress: 0,
      clearError: true,
    );
    var lastReportedProgress = 0.0;
    var lastProgressUpdate = DateTime.now();
    await _queueStore.replace(current);
    notifyListeners();

    try {
      final uploadedFile = await _driveService.upload(
        current,
        onProgress: (progress) {
          final now = DateTime.now();
          if (progress < 1 &&
              progress - lastReportedProgress < .02 &&
              now.difference(lastProgressUpdate) <
                  const Duration(milliseconds: 100)) {
            return;
          }
          lastReportedProgress = progress;
          lastProgressUpdate = now;
          current = current.copyWith(progress: progress);
          _queueStore.replaceInMemory(current);
          notifyListeners();
        },
      );
      final remote = _driveService.remoteMediaFromUpload(uploadedFile, current);
      current = current.copyWith(
        state: UploadState.uploaded,
        progress: 1,
        driveFileId: remote.id,
        thumbnailLink: remote.thumbnailLink,
        webViewLink: remote.webViewLink,
        clearError: true,
      );
      await _queueStore.replace(current);
      _upsertRemoteMedia(remote);
      notifyListeners();
      try {
        await _queueStore.remove(current.id);
      } catch (_) {
        // The cloud upload is already complete; a local cleanup failure must
        // never turn it back into a retry and create a duplicate.
      }
      _showCompletionBriefly();
      notifyListeners();
      return _UploadAttemptResult.success;
    } catch (error) {
      final message = _friendlyError(error);
      current = current.copyWith(state: UploadState.failed, error: message);
      await _queueStore.replace(current);
      _message = message;
      notifyListeners();
      return _uploadNeedsUserAction(error)
          ? _UploadAttemptResult.needsUserAction
          : _UploadAttemptResult.retryableFailure;
    }
  }

  Future<void> _retryFailedThenProcess() async {
    final failed = jobs
        .where((job) => job.state == UploadState.failed)
        .toList(growable: false);
    for (final job in failed) {
      if (await File(job.localPath).exists()) {
        await _queueStore.replace(
          job.copyWith(
            state: UploadState.queued,
            progress: 0,
            clearError: true,
          ),
        );
      } else {
        await _queueStore.remove(job.id);
      }
    }
    notifyListeners();
    await processQueue();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 30), () {
      if (isSignedIn) unawaited(_retryFailedThenProcess());
    });
  }

  void _showCompletionBriefly() {
    _completionTimer?.cancel();
    _uploadRecentlyCompleted = true;
    _completionTimer = Timer(const Duration(seconds: 2), () {
      _uploadRecentlyCompleted = false;
      notifyListeners();
    });
  }

  Future<void> _refreshGallery({required bool showErrors}) async {
    if (!isSignedIn) {
      _clearRemoteGallery();
      notifyListeners();
      return;
    }

    final requestSerial = ++_galleryRequestSerial;
    final mutationVersion = _galleryMutationVersion;
    _galleryLoading = true;
    notifyListeners();
    try {
      final media = await _driveService.listMedia();
      if (requestSerial != _galleryRequestSerial ||
          mutationVersion != _galleryMutationVersion ||
          !isSignedIn) {
        return;
      }
      _remoteMedia = media;
    } catch (error) {
      if (requestSerial != _galleryRequestSerial) return;
      if (!isSignedIn) _clearRemoteGallery(invalidateRequest: false);
      if (showErrors) _message = _friendlyError(error);
    } finally {
      if (requestSerial == _galleryRequestSerial) {
        _galleryLoading = false;
        notifyListeners();
      }
    }
  }

  File? _existingLocalFile(GalleryItem item) {
    final path = item.localPath;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  String _galleryItemKey(GalleryItem item) =>
      item.driveFileId ?? item.localJobId ?? item.id;

  void _upsertRemoteMedia(RemoteMedia media) {
    final updated =
        _remoteMedia
            .where(
              (item) =>
                  item.id != media.id &&
                  (media.queueId == null || item.queueId != media.queueId),
            )
            .toList()
          ..add(media)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _remoteMedia = List.unmodifiable(updated);
    _galleryMutationVersion++;
  }

  void _clearRemoteGallery({bool invalidateRequest = true}) {
    if (invalidateRequest) _galleryRequestSerial++;
    _galleryMutationVersion++;
    _galleryLoading = false;
    _remoteMedia = const [];
    _thumbnailRequests.clear();
    _photoRequests.clear();
  }

  void clearMessage() {
    _message = null;
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _completionTimer?.cancel();
    super.dispose();
  }

  String _friendlyError(Object error) {
    final text = error.toString().replaceFirst(
      RegExp(r'^(Exception|StateError|ArgumentError):\s*'),
      '',
    );
    if (text.contains('SocketException') || text.contains('ClientException')) {
      return 'Нет соединения с интернетом. Отправка продолжится автоматически.';
    }
    if (error is GoogleDrivePermissionException ||
        text.contains('insufficient_scope')) {
      return GoogleDrivePermissionException.message;
    }
    if (text.contains('invalid_grant') || text.contains('401')) {
      return 'Сеанс Google истёк. Выполните вход ещё раз.';
    }
    if (text.contains('accessNotConfigured') ||
        text.contains('SERVICE_DISABLED')) {
      return 'Google Drive API не включён для проекта приложения.';
    }
    return text;
  }

  bool _uploadNeedsUserAction(Object error) {
    final text = error.toString().toLowerCase();
    return error is GoogleDrivePermissionException ||
        text.contains('insufficient_scope') ||
        text.contains('invalid_grant') ||
        text.contains('status: 401') ||
        text.contains('accessnotconfigured') ||
        text.contains('service_disabled');
  }
}
