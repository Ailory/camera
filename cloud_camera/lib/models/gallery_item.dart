import 'remote_media.dart';
import 'upload_job.dart';

class GalleryItem {
  const GalleryItem({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.createdAt,
    required this.state,
    required this.progress,
    this.localJobId,
    this.queueId,
    this.localPath,
    this.driveFileId,
    this.size,
    this.error,
    this.thumbnailLink,
    this.webViewLink,
  });

  final String id;
  final String? localJobId;
  final String? queueId;
  final String? localPath;
  final String? driveFileId;
  final String name;
  final String mimeType;
  final int? size;
  final DateTime createdAt;
  final UploadState state;
  final double progress;
  final String? error;
  final String? thumbnailLink;
  final String? webViewLink;

  bool get isImage => mimeType.startsWith('image/');
  bool get hasLocalCopy => localPath != null;
  bool get isUploading => state == UploadState.uploading;
  bool get isRemoteOnly => driveFileId != null && localJobId == null;
  bool get canDelete => !isUploading;

  factory GalleryItem.fromUploadJob(UploadJob job, {RemoteMedia? remote}) {
    return GalleryItem(
      id: job.id,
      localJobId: job.id,
      queueId: job.id,
      localPath: job.localPath,
      driveFileId: remote?.id ?? job.driveFileId,
      name: remote?.name ?? job.name,
      mimeType: remote?.mimeType ?? job.mimeType,
      size: remote?.size ?? job.size,
      createdAt: job.createdAt,
      state: job.state,
      progress: job.progress,
      error: job.error,
      thumbnailLink: remote?.thumbnailLink ?? job.thumbnailLink,
      webViewLink: remote?.webViewLink ?? job.webViewLink,
    );
  }

  factory GalleryItem.fromRemoteMedia(RemoteMedia remote, {String? itemId}) {
    return GalleryItem(
      id: itemId ?? remote.queueId ?? remote.id,
      queueId: remote.queueId,
      driveFileId: remote.id,
      name: remote.name,
      mimeType: remote.mimeType,
      size: remote.size,
      createdAt: remote.createdAt,
      state: UploadState.uploaded,
      progress: 1,
      thumbnailLink: remote.thumbnailLink,
      webViewLink: remote.webViewLink,
    );
  }
}

List<GalleryItem> buildGalleryItems(
  Iterable<UploadJob> localJobs,
  Iterable<RemoteMedia> remoteItems,
) {
  final remotePhotos = remoteItems.where((item) => item.isImage).toList();
  final remoteById = <String, RemoteMedia>{
    for (final item in remotePhotos) item.id: item,
  };
  final remoteByQueueId = <String, RemoteMedia>{
    for (final item in remotePhotos)
      if (item.queueId != null) item.queueId!: item,
  };
  final matchedRemoteIds = <String>{};
  final usedItemIds = <String>{};
  final result = <GalleryItem>[];

  for (final job in localJobs.where((item) => item.isImage)) {
    final remote = job.driveFileId == null
        ? remoteByQueueId[job.id]
        : remoteById[job.driveFileId!] ?? remoteByQueueId[job.id];
    if (remote != null) matchedRemoteIds.add(remote.id);
    final item = GalleryItem.fromUploadJob(job, remote: remote);
    usedItemIds.add(item.id);
    result.add(item);
  }

  for (final remote in remotePhotos) {
    if (!matchedRemoteIds.contains(remote.id)) {
      final preferredId = remote.queueId ?? remote.id;
      final itemId = usedItemIds.add(preferredId)
          ? preferredId
          : 'drive:${remote.id}';
      usedItemIds.add(itemId);
      result.add(GalleryItem.fromRemoteMedia(remote, itemId: itemId));
    }
  }

  result.sort((a, b) {
    final byDate = b.createdAt.compareTo(a.createdAt);
    return byDate != 0 ? byDate : b.id.compareTo(a.id);
  });
  return List.unmodifiable(result);
}
