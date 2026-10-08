class RemoteMedia {
  const RemoteMedia({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.createdAt,
    this.queueId,
    this.size,
    this.thumbnailLink,
    this.webViewLink,
  });

  final String id;
  final String? queueId;
  final String name;
  final String mimeType;
  final int? size;
  final DateTime createdAt;
  final String? thumbnailLink;
  final String? webViewLink;

  bool get isImage => mimeType.startsWith('image/');
}
