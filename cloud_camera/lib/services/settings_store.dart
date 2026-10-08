import 'package:shared_preferences/shared_preferences.dart';

import '../models/drive_config.dart';

class SettingsStore {
  static const _folderKey = 'cloud_camera.drive_folder';

  Future<DriveConfig> load() async {
    final preferences = await SharedPreferences.getInstance();
    return DriveConfig(
      folderName: preferences.getString(_folderKey) ?? 'Cloud Camera',
    );
  }

  Future<void> save(DriveConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _folderKey,
      config.folderName.trim().isEmpty
          ? 'Cloud Camera'
          : config.folderName.trim(),
    );
  }
}
