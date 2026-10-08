import 'package:cloud_camera/models/gallery_item.dart';
import 'package:cloud_camera/models/remote_media.dart';
import 'package:cloud_camera/models/upload_job.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildGalleryItems', () {
    test('deduplicates an uploaded local photo by queue id', () {
      final local = _job(
        id: 'queue-1',
        state: UploadState.uploading,
        progress: .4,
        createdAt: DateTime.utc(2026, 10, 8, 10),
      );
      final remote = _remote(
        id: 'drive-1',
        queueId: local.id,
        name: 'remote-name.jpg',
        createdAt: DateTime.utc(2026, 10, 8, 11),
      );

      final items = buildGalleryItems([local], [remote]);

      expect(items, hasLength(1));
      expect(items.single.localJobId, local.id);
      expect(items.single.driveFileId, remote.id);
      expect(items.single.name, remote.name);
      expect(items.single.state, UploadState.uploading);
      expect(items.single.progress, .4);
      expect(items.single.createdAt, local.createdAt);
    });

    test('uses drive file id before queue id when both can match', () {
      final local = _job(
        id: 'queue-1',
        driveFileId: 'drive-explicit',
        state: UploadState.uploaded,
      );
      final explicitRemote = _remote(
        id: 'drive-explicit',
        queueId: 'another-queue',
        name: 'explicit.jpg',
      );
      final queueRemote = _remote(
        id: 'drive-queue-match',
        queueId: local.id,
        name: 'queue-match.jpg',
      );

      final items = buildGalleryItems([local], [queueRemote, explicitRemote]);

      final localItem = items.singleWhere(
        (item) => item.localJobId == local.id,
      );
      expect(localItem.driveFileId, explicitRemote.id);
      expect(localItem.name, explicitRemote.name);
      expect(
        items.where((item) => item.driveFileId == queueRemote.id),
        hasLength(1),
      );
    });

    test('does not deduplicate different photos with the same filename', () {
      final local = _job(id: 'queue-1', name: 'photo.jpg');
      final remote = _remote(id: 'drive-1', name: 'photo.jpg');

      final items = buildGalleryItems([local], [remote]);

      expect(items, hasLength(2));
      expect(items.map((item) => item.id), containsAll(['queue-1', 'drive-1']));
    });

    test('keeps widget ids unique for duplicate remote queue ids', () {
      final first = _remote(id: 'drive-1', queueId: 'same-queue');
      final second = _remote(id: 'drive-2', queueId: 'same-queue');

      final items = buildGalleryItems(const [], [first, second]);

      expect(items, hasLength(2));
      expect(items.map((item) => item.id).toSet(), hasLength(2));
      expect(
        items.map((item) => item.driveFileId),
        containsAll(['drive-1', 'drive-2']),
      );
    });

    test('marks a remote-only photo as uploaded', () {
      final remote = _remote(
        id: 'drive-1',
        queueId: 'old-queue-id',
        thumbnailLink: 'https://example.test/thumbnail',
      );

      final item = buildGalleryItems(const [], [remote]).single;

      expect(item.state, UploadState.uploaded);
      expect(item.progress, 1);
      expect(item.isRemoteOnly, isTrue);
      expect(item.thumbnailLink, remote.thumbnailLink);
    });

    test('keeps only images and sorts newest first', () {
      final olderLocal = _job(
        id: 'local-old',
        createdAt: DateTime.utc(2026, 10, 7),
      );
      final newerRemote = _remote(
        id: 'remote-new',
        createdAt: DateTime.utc(2026, 10, 8),
      );
      final video = _remote(
        id: 'remote-video',
        mimeType: 'video/mp4',
        createdAt: DateTime.utc(2026, 10, 9),
      );

      final items = buildGalleryItems([olderLocal], [newerRemote, video]);

      expect(items.map((item) => item.id), ['remote-new', 'local-old']);
      expect(items.every((item) => item.isImage), isTrue);
    });

    test('returns an unmodifiable result', () {
      final items = buildGalleryItems([_job(id: 'local-1')], const []);

      expect(() => items.clear(), throwsUnsupportedError);
    });
  });
}

UploadJob _job({
  required String id,
  String name = 'photo.jpg',
  String mimeType = 'image/jpeg',
  DateTime? createdAt,
  UploadState state = UploadState.queued,
  double progress = 0,
  String? driveFileId,
}) {
  return UploadJob(
    id: id,
    localPath: 'C:/outbox/$id.jpg',
    name: name,
    mimeType: mimeType,
    size: 1024,
    createdAt: createdAt ?? DateTime.utc(2026, 10, 8),
    state: state,
    progress: progress,
    driveFileId: driveFileId,
  );
}

RemoteMedia _remote({
  required String id,
  String? queueId,
  String name = 'photo.jpg',
  String mimeType = 'image/jpeg',
  DateTime? createdAt,
  String? thumbnailLink,
}) {
  return RemoteMedia(
    id: id,
    queueId: queueId,
    name: name,
    mimeType: mimeType,
    size: 2048,
    createdAt: createdAt ?? DateTime.utc(2026, 10, 8),
    thumbnailLink: thumbnailLink,
  );
}
