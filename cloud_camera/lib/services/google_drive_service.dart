import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart'
    as cross_platform_google;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as google_auth;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/drive_config.dart';
import '../models/google_account_profile.dart';
import '../models/remote_media.dart';
import '../models/upload_job.dart';
import 'windows_credential_store.dart';

class GoogleDrivePermissionException implements Exception {
  const GoogleDrivePermissionException();

  static const message =
      'Google не предоставил доступ к Drive. Нажмите «Войти» и разрешите '
      'Cloud Camera создавать файлы на Google Drive.';

  @override
  String toString() => message;
}

class GoogleDriveService {
  GoogleDriveService({WindowsCredentialStore? windowsCredentialStore})
    : _windowsCredentialStore =
          windowsCredentialStore ?? WindowsCredentialStore();

  static const _desktopClientId = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_ID',
  );
  static const _desktopClientSecret = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_SECRET',
  );
  static const _androidServerClientId = String.fromEnvironment(
    'GOOGLE_ANDROID_SERVER_CLIENT_ID',
  );
  static const _scopes = <String>[
    'openid',
    'profile',
    'email',
    drive.DriveApi.driveFileScope,
  ];

  final WindowsCredentialStore _windowsCredentialStore;
  cross_platform_google.GoogleSignIn? _mobileGoogleSignIn;
  http.Client? _mobileClient;
  google_auth.AutoRefreshingAuthClient? _desktopClient;
  DriveConfig _config = DriveConfig.empty;
  GoogleAccountProfile? _profile;
  bool _signedIn = false;
  String? _folderId;
  Future<String>? _folderLookup;

  bool get isConfigured {
    if (Platform.isAndroid) return _androidServerClientId.trim().isNotEmpty;
    if (Platform.isWindows) {
      return _desktopClientId.trim().isNotEmpty &&
          _desktopClientSecret.trim().isNotEmpty;
    }
    return false;
  }

  bool get isSignedIn => _signedIn;
  GoogleAccountProfile? get profile => _profile;

  void configure(DriveConfig config) {
    _config = config;
    _folderId = null;
    _folderLookup = null;
    if (Platform.isAndroid && isConfigured && _mobileGoogleSignIn == null) {
      _mobileGoogleSignIn = cross_platform_google.GoogleSignIn(
        params: const cross_platform_google.GoogleSignInParams(
          clientId: _androidServerClientId,
          scopes: _scopes,
        ),
      );
    }
  }

  Future<bool> restoreSession() async {
    if (!isConfigured) return false;
    try {
      if (Platform.isAndroid) {
        final credentials = await _mobileGoogleSignIn?.lightweightSignIn();
        if (credentials == null) return false;
        _mobileClient = await _mobileGoogleSignIn?.authenticatedClient;
        if (_mobileClient == null) return false;
      } else if (Platform.isWindows) {
        final refreshToken = _windowsCredentialStore.readRefreshToken();
        if (refreshToken == null || refreshToken.isEmpty) return false;
        _desktopClient = await google_auth.clientViaRefreshToken(
          _desktopOAuthClient,
          refreshToken,
          _scopes,
        );
      } else {
        return false;
      }
      await _verifyDriveAccess();
      _signedIn = true;
      await _loadProfile();
      return true;
    } catch (error) {
      if (_requiresFreshAuthorization(error)) {
        await _discardCurrentAuthorization();
      } else {
        _clearClients();
      }
      return false;
    }
  }

  Future<bool> signIn() async {
    if (!isConfigured) {
      throw StateError(
        Platform.isAndroid
            ? 'Android-вход Google не настроен в этой сборке.'
            : 'Google OAuth не настроен в этой сборке.',
      );
    }

    String? newDesktopRefreshToken;
    try {
      if (Platform.isAndroid) {
        final credentials = await _mobileGoogleSignIn!.signIn();
        if (credentials == null) return false;
        _mobileClient = await _mobileGoogleSignIn!.authenticatedClient;
        if (_mobileClient == null) return false;
      } else if (Platform.isWindows) {
        final client = await google_auth.clientViaUserConsent(
          _desktopOAuthClient,
          _scopes,
          (authorizationUrl) {
            final original = Uri.parse(authorizationUrl);
            final consentUrl = original.replace(
              queryParameters: {
                ...original.queryParameters,
                'access_type': 'offline',
                'include_granted_scopes': 'true',
                'prompt': 'consent select_account',
              },
            );
            unawaited(
              launchUrl(consentUrl, mode: LaunchMode.externalApplication),
            );
          },
          customPostAuthPage: _postAuthPage,
        );
        newDesktopRefreshToken = client.credentials.refreshToken;
        if (newDesktopRefreshToken == null || newDesktopRefreshToken.isEmpty) {
          client.close();
          throw StateError('Google не вернул refresh-токен. Повторите вход.');
        }
        _desktopClient = client;
      } else {
        throw UnsupportedError('Эта платформа пока не поддерживается.');
      }

      await _verifyDriveAccess();
      if (newDesktopRefreshToken != null) {
        _windowsCredentialStore.saveRefreshToken(newDesktopRefreshToken);
      }
      _signedIn = true;
      await _loadProfile();
      return true;
    } catch (error) {
      if (_requiresFreshAuthorization(error)) {
        await _discardCurrentAuthorization(
          refreshToken: newDesktopRefreshToken,
        );
        if (error is! GoogleDrivePermissionException &&
            _isInsufficientScope(error)) {
          throw const GoogleDrivePermissionException();
        }
      } else {
        _clearClients();
      }
      rethrow;
    }
  }

  Future<void> signOut() => _discardCurrentAuthorization();

  Future<drive.File> upload(
    UploadJob job, {
    required void Function(double value) onProgress,
  }) async {
    try {
      return await _uploadFile(job, onProgress: onProgress);
    } catch (error, stackTrace) {
      await _rethrowAuthorizedOperationError(error, stackTrace);
    }
  }

  Future<List<RemoteMedia>> listMedia() async {
    try {
      final api = drive.DriveApi(await _authenticatedClient());
      final folderId = await _ensureFolder(api);
      final escapedFolderId = folderId.replaceAll("'", "\\'");
      final result = <RemoteMedia>[];
      String? pageToken;

      do {
        final page = await api.files.list(
          q: "'$escapedFolderId' in parents and trashed = false",
          spaces: 'drive',
          orderBy: 'createdTime desc',
          pageSize: 1000,
          pageToken: pageToken,
          $fields:
              'nextPageToken,files(id,name,mimeType,size,createdTime,'
              'thumbnailLink,webViewLink,appProperties)',
        );
        for (final file in page.files ?? const <drive.File>[]) {
          final item = _remoteMediaFromFile(file);
          if (item?.isImage == true) result.add(item!);
        }
        pageToken = page.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);

      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return List.unmodifiable(result);
    } catch (error, stackTrace) {
      await _rethrowAuthorizedOperationError(error, stackTrace);
    }
  }

  Future<Uint8List> downloadThumbnail(
    String fileId, {
    String? thumbnailLink,
  }) async {
    final link = thumbnailLink?.trim();
    if (link != null && link.isNotEmpty) {
      try {
        final response = await (await _authenticatedClient()).get(
          Uri.parse(link),
        );
        if (response.statusCode == HttpStatus.ok) return response.bodyBytes;
      } catch (_) {
        // Thumbnail URLs are short-lived. The Drive download below is a safe
        // fallback both for expired links and transient thumbnail failures.
      }
    }
    return downloadFile(fileId);
  }

  Future<Uint8List> downloadFile(String fileId) async {
    try {
      final response = await drive.DriveApi(await _authenticatedClient()).files
          .get(fileId, downloadOptions: drive.DownloadOptions.fullMedia);
      final media = response as drive.Media;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in media.stream) {
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } catch (error, stackTrace) {
      await _rethrowAuthorizedOperationError(error, stackTrace);
    }
  }

  Future<void> trashFile(String fileId) async {
    try {
      final metadata = drive.File()..trashed = true;
      await drive.DriveApi(await _authenticatedClient()).files
          .update(metadata, fileId, $fields: 'id,trashed');
    } catch (error, stackTrace) {
      await _rethrowAuthorizedOperationError(error, stackTrace);
    }
  }

  RemoteMedia remoteMediaFromUpload(drive.File file, UploadJob job) {
    final item = _remoteMediaFromFile(
      file,
      fallbackQueueId: job.id,
      fallbackName: job.name,
      fallbackMimeType: job.mimeType,
      fallbackSize: job.size,
      fallbackCreatedAt: job.createdAt,
    );
    if (item == null) {
      throw StateError('Google Drive не вернул идентификатор файла.');
    }
    return item;
  }

  Future<drive.File> _uploadFile(
    UploadJob job, {
    required void Function(double value) onProgress,
  }) async {
    final api = drive.DriveApi(await _authenticatedClient());
    final folderId = await _ensureFolder(api);
    final existing = await _findExistingUpload(api, folderId, job.id);
    if (existing != null) {
      onProgress(1);
      return existing;
    }
    final localFile = File(job.localPath);
    if (!await localFile.exists()) {
      throw StateError('Локальная копия файла не найдена.');
    }

    final metadata = drive.File()
      ..name = job.name
      ..parents = [folderId]
      ..appProperties = {
        'source': 'cloud-camera',
        'capturedAt': job.createdAt.toIso8601String(),
        'queueId': job.id,
      };

    final media = drive.Media(
      _progressStream(localFile, job.size, onProgress),
      job.size,
      contentType: job.mimeType,
    );

    return api.files.create(
      metadata,
      uploadMedia: media,
      uploadOptions: drive.ResumableUploadOptions(
        chunkSize: 4 * 1024 * 1024,
        numberOfAttempts: 5,
      ),
      $fields:
          'id,name,mimeType,size,createdTime,thumbnailLink,webViewLink,'
          'appProperties',
    );
  }

  RemoteMedia? _remoteMediaFromFile(
    drive.File file, {
    String? fallbackQueueId,
    String? fallbackName,
    String? fallbackMimeType,
    int? fallbackSize,
    DateTime? fallbackCreatedAt,
  }) {
    final id = file.id;
    if (id == null || id.isEmpty) return null;

    final capturedAt = DateTime.tryParse(
      file.appProperties?['capturedAt'] ?? '',
    );
    return RemoteMedia(
      id: id,
      queueId: file.appProperties?['queueId'] ?? fallbackQueueId,
      name: file.name ?? fallbackName ?? 'photo',
      mimeType: file.mimeType ?? fallbackMimeType ?? 'application/octet-stream',
      size: int.tryParse(file.size ?? '') ?? fallbackSize,
      createdAt:
          capturedAt?.toUtc() ??
          file.createdTime?.toUtc() ??
          fallbackCreatedAt?.toUtc() ??
          DateTime.now().toUtc(),
      thumbnailLink: file.thumbnailLink,
      webViewLink: file.webViewLink,
    );
  }

  Future<Never> _rethrowAuthorizedOperationError(
    Object error,
    StackTrace stackTrace,
  ) async {
    if (_requiresFreshAuthorization(error)) {
      await _discardCurrentAuthorization();
      if (_isInsufficientScope(error)) {
        Error.throwWithStackTrace(
          const GoogleDrivePermissionException(),
          stackTrace,
        );
      }
    }
    Error.throwWithStackTrace(error, stackTrace);
  }

  google_auth.ClientId get _desktopOAuthClient => google_auth.ClientId(
    _desktopClientId.trim(),
    _desktopClientSecret.trim(),
  );

  http.Client? get _activeClient => Platform.isWindows
      ? _desktopClient
      : (Platform.isAndroid ? _mobileClient : null);

  Future<void> _verifyDriveAccess() async {
    final client = _activeClient;
    if (client == null) {
      throw StateError('Клиент Google не создан.');
    }
    try {
      await drive.DriveApi(client).files
          .list(spaces: 'drive', pageSize: 1, $fields: 'files(id)');
    } catch (error) {
      if (_isInsufficientScope(error)) {
        throw const GoogleDrivePermissionException();
      }
      rethrow;
    }
  }

  Future<void> _discardCurrentAuthorization({String? refreshToken}) async {
    if (Platform.isAndroid) {
      try {
        await _mobileGoogleSignIn?.signOut();
      } catch (_) {
        // Local sign-out must still work while offline.
      }
    } else if (Platform.isWindows) {
      final token = refreshToken ?? _windowsCredentialStore.readRefreshToken();
      if (token != null && token.isNotEmpty) {
        try {
          await http.post(
            Uri.parse('https://oauth2.googleapis.com/revoke'),
            headers: const {
              'content-type': 'application/x-www-form-urlencoded',
            },
            body: {'token': token},
          );
        } catch (_) {
          // Local sign-out must still work while offline.
        }
      }
      _windowsCredentialStore.deleteRefreshToken();
    }
    _clearClients();
  }

  bool _requiresFreshAuthorization(Object error) {
    if (error is GoogleDrivePermissionException) return true;
    final text = error.toString().toLowerCase();
    return text.contains('insufficient_scope') ||
        text.contains('invalid_grant') ||
        text.contains('invalid credentials') ||
        text.contains('status: 401');
  }

  bool _isInsufficientScope(Object error) =>
      error.toString().toLowerCase().contains('insufficient_scope');

  Future<http.Client> _authenticatedClient() async {
    if (!_signedIn || _activeClient == null) {
      final restored = await restoreSession();
      if (!restored) {
        throw StateError('Войдите в Google, чтобы сохранять снимки в облаке.');
      }
    }
    final client = _activeClient;
    if (client == null) {
      _signedIn = false;
      throw StateError('Сеанс Google истёк. Выполните вход ещё раз.');
    }
    return client;
  }

  Future<void> _loadProfile() async {
    try {
      final response = await _activeClient?.get(
        Uri.parse('https://openidconnect.googleapis.com/v1/userinfo'),
      );
      if (response?.statusCode != 200) return;
      final data = Map<String, dynamic>.from(
        jsonDecode(response!.body) as Map<dynamic, dynamic>,
      );
      _profile = GoogleAccountProfile(
        name: data['name'] as String? ?? '',
        email: data['email'] as String? ?? '',
        pictureUrl: data['picture'] as String?,
      );
    } catch (_) {
      // The account remains usable even if the optional avatar request fails.
    }
  }

  void _clearClients() {
    _mobileClient?.close();
    _desktopClient?.close();
    _mobileClient = null;
    _desktopClient = null;
    _signedIn = false;
    _profile = null;
    _folderId = null;
    _folderLookup = null;
  }

  Future<String> _ensureFolder(drive.DriveApi api) async {
    if (_folderId != null) return _folderId!;
    if (_folderLookup != null) return _folderLookup!;

    final lookup = _findOrCreateFolder(api);
    _folderLookup = lookup;
    try {
      final id = await lookup;
      _folderId = id;
      return id;
    } finally {
      _folderLookup = null;
    }
  }

  Future<String> _findOrCreateFolder(drive.DriveApi api) async {
    final folderName = _config.folderName.trim().isEmpty
        ? 'Cloud Camera'
        : _config.folderName.trim();
    final escapedName = folderName.replaceAll("'", "\\'");
    final existing = await api.files.list(
      q:
          "name = '$escapedName' and "
          "mimeType = 'application/vnd.google-apps.folder' and trashed = false",
      spaces: 'drive',
      pageSize: 1,
      $fields: 'files(id,name)',
    );
    final existingId = existing.files?.firstOrNull?.id;
    if (existingId != null) return existingId;

    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder';
    final created = await api.files.create(folder, $fields: 'id');
    if (created.id == null) {
      throw StateError('Google Drive не вернул идентификатор папки.');
    }
    return created.id!;
  }

  Future<drive.File?> _findExistingUpload(
    drive.DriveApi api,
    String folderId,
    String queueId,
  ) async {
    final escapedQueueId = queueId.replaceAll("'", "\\'");
    final result = await api.files.list(
      q:
          "'$folderId' in parents and trashed = false and "
          "appProperties has { key = 'queueId' and value = '$escapedQueueId' }",
      pageSize: 1,
      $fields:
          'files(id,name,mimeType,size,createdTime,thumbnailLink,webViewLink,'
          'appProperties)',
    );
    return result.files?.firstOrNull;
  }

  Stream<List<int>> _progressStream(
    File file,
    int total,
    void Function(double value) onProgress,
  ) async* {
    var sent = 0;
    await for (final chunk in file.openRead()) {
      sent += chunk.length;
      onProgress(total == 0 ? 1 : (sent / total).clamp(0, 1));
      yield chunk;
    }
  }

  static const _postAuthPage = '''
<!doctype html><html lang="ru"><head><meta charset="utf-8"><title>Cloud Camera</title></head>
<body style="font-family:system-ui;background:#07121f;color:#eef8ff;display:grid;place-items:center;min-height:100vh;margin:0">
<main style="text-align:center"><h1>Google Drive подключён</h1><p>Можно закрыть это окно и вернуться в Cloud Camera.</p></main>
</body></html>
''';
}
