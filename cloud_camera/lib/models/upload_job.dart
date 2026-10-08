enum UploadState { queued, uploading, uploaded, failed }

class UploadJob {
  const UploadJob({
    required this.id,
    required this.localPath,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.createdAt,
    required this.state,
    this.progress = 0,
    this.error,
    this.driveFileId,
    this.thumbnailLink,
    this.webViewLink,
  });

  final String id;
  final String localPath;
  final String name;
  final String mimeType;
  final int size;
  final DateTime createdAt;
  final UploadState state;
  final double progress;
  final String? error;
  final String? driveFileId;
  final String? thumbnailLink;
  final String? webViewLink;

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');

  UploadJob copyWith({
    UploadState? state,
    double? progress,
    String? error,
    bool clearError = false,
    String? driveFileId,
    String? thumbnailLink,
    String? webViewLink,
  }) {
    return UploadJob(
      id: id,
      localPath: localPath,
      name: name,
      mimeType: mimeType,
      size: size,
      createdAt: createdAt,
      state: state ?? this.state,
      progress: progress ?? this.progress,
      error: clearError ? null : (error ?? this.error),
      driveFileId: driveFileId ?? this.driveFileId,
      thumbnailLink: thumbnailLink ?? this.thumbnailLink,
      webViewLink: webViewLink ?? this.webViewLink,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'localPath': localPath,
    'name': name,
    'mimeType': mimeType,
    'size': size,
    'createdAt': createdAt.toIso8601String(),
    'state': state.name,
    'progress': progress,
    'error': error,
    'driveFileId': driveFileId,
    'thumbnailLink': thumbnailLink,
    'webViewLink': webViewLink,
  };

  factory UploadJob.fromJson(Map<String, Object?> json) {
    final savedState = UploadState.values.firstWhere(
      (value) => value.name == json['state'],
      orElse: () => UploadState.queued,
    );
    return UploadJob(
      id: json['id']! as String,
      localPath: json['localPath']! as String,
      name: json['name']! as String,
      mimeType: json['mimeType']! as String,
      size: (json['size']! as num).toInt(),
      createdAt: DateTime.parse(json['createdAt']! as String),
      state: savedState == UploadState.uploading
          ? UploadState.queued
          : savedState,
      progress: savedState == UploadState.uploaded
          ? 1
          : ((json['progress'] as num?)?.toDouble() ?? 0),
      error: json['error'] as String?,
      driveFileId: json['driveFileId'] as String?,
      thumbnailLink: json['thumbnailLink'] as String?,
      webViewLink: json['webViewLink'] as String?,
    );
  }
}
