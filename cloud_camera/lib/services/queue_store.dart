import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/upload_job.dart';

class QueueStore {
  static const _jobsKey = 'cloud_camera.upload_jobs.v1';

  final List<UploadJob> _jobs = [];

  List<UploadJob> get jobs => List.unmodifiable(_jobs);

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_jobsKey);
    _jobs.clear();
    if (raw == null || raw.isEmpty) return;

    final data = jsonDecode(raw) as List<dynamic>;
    for (final item in data) {
      try {
        _jobs.add(
          UploadJob.fromJson(
            Map<String, Object?>.from(item as Map<dynamic, dynamic>),
          ),
        );
      } catch (_) {
        // Skip one damaged record and keep the rest of the queue usable.
      }
    }
    _jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<UploadJob> enqueue(String sourcePath, {String? displayName}) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw StateError('Файл больше недоступен на устройстве.');
    }

    final now = DateTime.now().toUtc();
    final random = Random.secure().nextInt(0x7fffffff);
    final id = '${now.microsecondsSinceEpoch}-${random.toRadixString(16)}';
    final supportDirectory = await getApplicationSupportDirectory();
    final outbox = Directory(p.join(supportDirectory.path, 'outbox'));
    await outbox.create(recursive: true);

    final originalName = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : p.basename(source.path);
    final extension = p.extension(originalName);
    final storedFile = File(p.join(outbox.path, '$id$extension'));
    await source.copy(storedFile.path);

    final stat = await storedFile.stat();
    final mimeType = lookupMimeType(originalName) ?? 'application/octet-stream';
    final job = UploadJob(
      id: id,
      localPath: storedFile.path,
      name: originalName,
      mimeType: mimeType,
      size: stat.size,
      createdAt: now,
      state: UploadState.queued,
    );
    _jobs.insert(0, job);
    await persist();
    return job;
  }

  Future<void> replace(UploadJob job) async {
    replaceInMemory(job);
    await persist();
  }

  void replaceInMemory(UploadJob job) {
    final index = _jobs.indexWhere((item) => item.id == job.id);
    if (index == -1) return;
    _jobs[index] = job;
  }

  Future<void> remove(String id) async {
    final index = _jobs.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final job = _jobs.removeAt(index);
    try {
      await persist();
    } catch (_) {
      _jobs.insert(index, job);
      rethrow;
    }

    try {
      final localFile = File(job.localPath);
      if (await localFile.exists()) await localFile.delete();
    } catch (_) {
      // The record has already been removed durably. A leftover cache file is
      // preferable to making the photo reappear or reporting a false failure.
    }
  }

  Future<void> deleteLocalCopy(UploadJob job) async {
    final localFile = File(job.localPath);
    if (await localFile.exists()) await localFile.delete();
  }

  Future<void> persist() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _jobsKey,
      jsonEncode(_jobs.map((item) => item.toJson()).toList()),
    );
  }
}
