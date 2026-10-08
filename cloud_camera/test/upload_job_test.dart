import 'package:cloud_camera/models/upload_job.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UploadJob persistence', () {
    test('an interrupted upload returns to the queue after restart', () {
      final original = UploadJob(
        id: 'job-1',
        localPath: 'C:/temp/photo.jpg',
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        size: 1024,
        createdAt: DateTime.utc(2026, 10, 8),
        state: UploadState.uploading,
        progress: .75,
      );

      final restored = UploadJob.fromJson(original.toJson());

      expect(restored.state, UploadState.queued);
      expect(restored.name, original.name);
      expect(restored.size, original.size);
    });

    test('restores a queue record written before gallery metadata existed', () {
      final restored = UploadJob.fromJson({
        'id': 'legacy-job',
        'localPath': 'C:/temp/legacy.jpg',
        'name': 'legacy.jpg',
        'mimeType': 'image/jpeg',
        'size': 2048,
        'createdAt': '2026-10-08T12:30:00.000Z',
        'state': 'queued',
      });

      expect(restored.id, 'legacy-job');
      expect(restored.state, UploadState.queued);
      expect(restored.progress, 0);
      expect(restored.driveFileId, isNull);
      expect(restored.thumbnailLink, isNull);
      expect(restored.webViewLink, isNull);
    });

    test('round-trips Drive metadata used by the gallery', () {
      final original = UploadJob(
        id: 'job-with-drive-file',
        localPath: 'C:/temp/photo.jpg',
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        size: 4096,
        createdAt: DateTime.utc(2026, 10, 8),
        state: UploadState.uploaded,
        driveFileId: 'drive-file-1',
        thumbnailLink: 'https://example.test/thumbnail',
        webViewLink: 'https://example.test/view',
      );

      final restored = UploadJob.fromJson(original.toJson());

      expect(restored.state, UploadState.uploaded);
      expect(restored.progress, 1);
      expect(restored.driveFileId, original.driveFileId);
      expect(restored.thumbnailLink, original.thumbnailLink);
      expect(restored.webViewLink, original.webViewLink);
    });
  });
}
