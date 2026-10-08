import 'package:cloud_camera/app.dart';
import 'package:cloud_camera/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the startup state while data loads', (tester) async {
    await tester.pumpWidget(CloudCameraApp(controller: AppController()));

    expect(find.text('Подготавливаем камеру…'), findsOneWidget);
  });
}
