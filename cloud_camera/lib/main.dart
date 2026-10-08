import 'package:flutter/material.dart';

import 'app.dart';
import 'app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  runApp(CloudCameraApp(controller: controller));
  await controller.initialize();
}
