class DriveConfig {
  const DriveConfig({required this.folderName});

  static const empty = DriveConfig(folderName: 'Cloud Camera');

  final String folderName;

  DriveConfig copyWith({String? folderName}) {
    return DriveConfig(folderName: folderName ?? this.folderName);
  }
}
