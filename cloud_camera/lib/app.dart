import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'screens/camera_screen.dart';
import 'screens/gallery_screen.dart';
import 'screens/settings_screen.dart';

class CloudCameraApp extends StatelessWidget {
  const CloudCameraApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF07131F);
    const cyan = Color(0xFF5DE2E7);
    const coral = Color(0xFFFF8A73);
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: cyan,
          brightness: Brightness.dark,
          surface: const Color(0xFF0D1B29),
          error: coral,
        ).copyWith(
          primary: cyan,
          secondary: const Color(0xFF94B7FF),
          tertiary: coral,
          surfaceContainer: const Color(0xFF122334),
          surfaceContainerHigh: const Color(0xFF192D40),
          outline: const Color(0xFF4D6477),
        );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cloud Camera',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: ink,
        fontFamily: 'Segoe UI',
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: const Color(0xFFE9F3FA),
          displayColor: const Color(0xFFF8FCFF),
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Color(0xFF102131),
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
            side: BorderSide(color: Color(0xFF223A4D)),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF1C3447),
          contentTextStyle: TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
      home: HomeShell(controller: controller),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  _HomeView _view = _HomeView.camera;
  String? _shownMessage;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        _showMessageIfNeeded();
        if (!widget.controller.initialized) {
          return const _LoadingScreen();
        }

        return PopScope(
          canPop: _view == _HomeView.camera,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _view != _HomeView.camera) {
              setState(() => _view = _HomeView.camera);
            }
          },
          child: Scaffold(
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: switch (_view) {
                _HomeView.camera => CameraScreen(
                  key: const ValueKey('camera'),
                  controller: widget.controller,
                  onOpenGallery: () =>
                      setState(() => _view = _HomeView.gallery),
                  onOpenSettings: () =>
                      setState(() => _view = _HomeView.settings),
                ),
                _HomeView.gallery => GalleryScreen(
                  key: const ValueKey('gallery'),
                  controller: widget.controller,
                  onBack: () => setState(() => _view = _HomeView.camera),
                ),
                _HomeView.settings => SettingsScreen(
                  key: const ValueKey('settings'),
                  controller: widget.controller,
                  onBack: () => setState(() => _view = _HomeView.camera),
                ),
              },
            ),
          ),
        );
      },
    );
  }

  void _showMessageIfNeeded() {
    final message = widget.controller.message;
    if (message == null || message == _shownMessage) return;
    _shownMessage = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      if (widget.controller.message == message) {
        widget.controller.clearMessage();
      }
      _shownMessage = null;
    });
  }
}

enum _HomeView { camera, gallery, settings }

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Cloud Camera',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .34),
          gradient: const LinearGradient(
            colors: [Color(0xFF61F0E6), Color(0xFF5C8BFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Icon(
          Icons.camera_rounded,
          color: const Color(0xFF06121C),
          size: size * .52,
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(),
            SizedBox(height: 22),
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('Подготавливаем камеру…'),
          ],
        ),
      ),
    );
  }
}
