import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/google_account_profile.dart';
import '../widgets/gallery_photo.dart';

enum CaptureMode { photo, video }

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.controller,
    required this.onOpenGallery,
    required this.onOpenSettings,
  });

  final AppController controller;
  final VoidCallback onOpenGallery;
  final VoidCallback onOpenSettings;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = const [];
  CaptureMode _mode = CaptureMode.photo;
  bool _cameraLoading = true;
  bool _captureBusy = false;
  bool _isRecording = false;
  bool _flashAvailable = false;
  bool _torchEnabled = false;
  bool _signingIn = false;
  String? _cameraError;
  String? _selectedCameraName;
  int _cameraIndex = 0;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_isRecording) unawaited(_stopRecording());
      unawaited(_cameraController?.dispose());
      _cameraController = null;
      _torchEnabled = false;
    } else if (state == AppLifecycleState.resumed &&
        _cameraController == null) {
      unawaited(_initializeCamera(cameraName: _selectedCameraName));
    }
  }

  Future<void> _initializeCamera({int? index, String? cameraName}) async {
    if (mounted) {
      setState(() {
        _cameraLoading = true;
        _cameraError = null;
        _flashAvailable = false;
        _torchEnabled = false;
      });
    }
    try {
      await _cameraController?.dispose();
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw CameraException('NoCamera', 'Камера не найдена.');
      }

      if (cameraName != null) {
        final selected = _cameras.indexWhere(
          (camera) => camera.name == cameraName,
        );
        _cameraIndex = selected >= 0 ? selected : 0;
      } else if (index == null) {
        final backCamera = _cameras.indexWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
        );
        _cameraIndex = backCamera >= 0 ? backCamera : 0;
      } else {
        _cameraIndex = index.clamp(0, _cameras.length - 1);
      }

      final description = _cameras[_cameraIndex];
      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize();

      var flashAvailable =
          !Platform.isWindows &&
          description.lensDirection == CameraLensDirection.back;
      if (flashAvailable) {
        try {
          await controller.setFlashMode(FlashMode.off);
        } catch (_) {
          flashAvailable = false;
        }
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _selectedCameraName = description.name;
        _cameraLoading = false;
        _flashAvailable = flashAvailable;
      });
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraLoading = false;
        _cameraError = _cameraErrorText(error);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cameraLoading = false;
        _cameraError = 'Не удалось открыть камеру: $error';
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _captureBusy || _isRecording || _cameraLoading) {
      return;
    }
    final next = (_cameraIndex + 1) % _cameras.length;
    await _initializeCamera(index: next);
  }

  Future<void> _selectWindowsCamera() async {
    if (!Platform.isWindows ||
        _cameras.length < 2 ||
        _captureBusy ||
        _isRecording ||
        _cameraLoading) {
      return;
    }

    final cameras = List<CameraDescription>.unmodifiable(_cameras);
    final selectedName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Выберите камеру'),
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        content: SizedBox(
          width: 420,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: cameras.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final camera = cameras[index];
                final selected = camera.name == _selectedCameraName;
                return ListTile(
                  selected: selected,
                  selectedTileColor: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  leading: const Icon(Icons.videocam_outlined),
                  title: Text(
                    _cameraDisplayName(camera, index),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('Камера ${index + 1}'),
                  trailing: selected
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(dialogContext).pop(camera.name),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );

    if (!mounted ||
        selectedName == null ||
        selectedName == _selectedCameraName) {
      return;
    }
    await _initializeCamera(cameraName: selectedName);
  }

  Future<void> _toggleTorch() async {
    final controller = _cameraController;
    if (controller == null || !_flashAvailable || _captureBusy) return;
    final next = !_torchEnabled;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchEnabled = next);
    } on CameraException catch (error) {
      _showCameraMessage(_cameraErrorText(error));
    }
  }

  Future<void> _capture() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _captureBusy) {
      return;
    }

    if (_mode == CaptureMode.video) {
      if (_isRecording) {
        await _stopRecording();
      } else {
        await _startRecording();
      }
      return;
    }

    setState(() => _captureBusy = true);
    try {
      final file = await controller.takePicture();
      await widget.controller.enqueueFile(
        file.path,
        displayName: _captureName('jpg'),
      );
    } on CameraException catch (error) {
      _showCameraMessage(_cameraErrorText(error));
    } finally {
      if (mounted) setState(() => _captureBusy = false);
    }
  }

  Future<void> _startRecording() async {
    final controller = _cameraController;
    if (controller == null) return;
    setState(() => _captureBusy = true);
    try {
      await controller.startVideoRecording();
      _recordingSeconds = 0;
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordingSeconds++);
      });
      setState(() => _isRecording = true);
    } on CameraException catch (error) {
      _showCameraMessage(_cameraErrorText(error));
    } finally {
      if (mounted) setState(() => _captureBusy = false);
    }
  }

  Future<void> _stopRecording() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isRecordingVideo) return;
    _recordingTimer?.cancel();
    if (mounted) {
      setState(() {
        _captureBusy = true;
        _isRecording = false;
      });
    }
    try {
      final file = await controller.stopVideoRecording();
      await widget.controller.enqueueFile(
        file.path,
        displayName: _captureName('mp4'),
      );
    } on CameraException catch (error) {
      _showCameraMessage(_cameraErrorText(error));
    } finally {
      if (mounted) setState(() => _captureBusy = false);
    }
  }

  Future<void> _connectGoogle() async {
    if (_signingIn) return;
    setState(() => _signingIn = true);
    await widget.controller.connectGoogle();
    if (mounted) setState(() => _signingIn = false);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          return Stack(
            fit: StackFit.expand,
            children: [
              _CameraViewport(
                controller: _cameraController,
                loading: _cameraLoading,
                error: _cameraError,
                onRetry: _initializeCamera,
              ),
              const IgnorePointer(child: _CameraGradient()),
              SafeArea(
                child: Stack(
                  children: [
                    Positioned(
                      left: 16,
                      right: 12,
                      top: 12,
                      child: Row(
                        children: [
                          const _MiniBrand(),
                          const Spacer(),
                          _GlassButton(
                            tooltip: 'Настройки',
                            onPressed: widget.onOpenSettings,
                            icon: Icons.settings_outlined,
                          ),
                          const SizedBox(width: 8),
                          _AccountControl(
                            signedIn: widget.controller.isSignedIn,
                            signingIn: _signingIn,
                            profile: widget.controller.accountProfile,
                            onSignIn: _connectGoogle,
                            onSignOut: () =>
                                unawaited(widget.controller.disconnectGoogle()),
                          ),
                        ],
                      ),
                    ),
                    if (_flashAvailable)
                      Positioned(
                        left: 16,
                        top: compact ? 74 : 78,
                        child: _GlassButton(
                          tooltip: _torchEnabled
                              ? 'Выключить фонарик'
                              : 'Включить фонарик',
                          onPressed: _toggleTorch,
                          icon: _torchEnabled
                              ? Icons.flashlight_on_rounded
                              : Icons.flashlight_off_rounded,
                          active: _torchEnabled,
                        ),
                      ),
                    if (_isRecording)
                      Positioned(
                        top: compact ? 76 : 80,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _RecordingBadge(seconds: _recordingSeconds),
                        ),
                      ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 18,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ModeSwitch(
                            mode: _mode,
                            enabled: !_isRecording && !_captureBusy,
                            onChanged: (value) => setState(() => _mode = value),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _LatestPhotoButton(
                                controller: widget.controller,
                                onPressed: _captureBusy || _isRecording
                                    ? null
                                    : widget.onOpenGallery,
                              ),
                              const SizedBox(width: 26),
                              _CaptureButton(
                                mode: _mode,
                                busy: _captureBusy,
                                recording: _isRecording,
                                onPressed: _capture,
                              ),
                              const SizedBox(width: 26),
                              _cameraControl(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCameraMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _cameraControl() {
    if (Platform.isWindows && _cameras.length < 2) {
      return const SizedBox(width: 50, height: 50);
    }

    final enabled =
        _cameras.length > 1 &&
        !_captureBusy &&
        !_isRecording &&
        !_cameraLoading;
    return _GlassButton(
      tooltip: Platform.isWindows ? 'Выбрать камеру' : 'Сменить камеру',
      onPressed: enabled
          ? (Platform.isWindows ? _selectWindowsCamera : _switchCamera)
          : null,
      icon: Platform.isWindows
          ? Icons.video_camera_front_outlined
          : Icons.cameraswitch_rounded,
      size: 50,
    );
  }

  String _cameraDisplayName(CameraDescription camera, int index) {
    var name = camera.name.trim();
    if (Platform.isWindows && name.endsWith('>')) {
      final deviceIdStart = name.lastIndexOf(' <');
      if (deviceIdStart > 0) {
        name = name.substring(0, deviceIdStart).trim();
      }
    }
    return name.isEmpty ? 'Камера ${index + 1}' : name;
  }

  String _captureName(String extension) {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'camera_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.$extension';
  }

  String _cameraErrorText(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'Разрешите доступ к камере в настройках системы.';
      case 'AudioAccessDenied':
      case 'AudioAccessDeniedWithoutPrompt':
      case 'AudioAccessRestricted':
        return 'Разрешите доступ к микрофону для записи видео.';
      case 'NoCamera':
        return 'Камера не найдена.';
      default:
        return error.description ?? 'Камера сейчас недоступна.';
    }
  }
}

class _CameraViewport extends StatelessWidget {
  const _CameraViewport({
    required this.controller,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final CameraController? controller;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (error != null || controller == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 48),
              const SizedBox(height: 14),
              Text(error ?? 'Камера недоступна.', textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = controller!.value.previewSize;
        if (previewSize == null) return CameraPreview(controller!);
        final portrait = constraints.maxHeight > constraints.maxWidth;
        final width = portrait ? previewSize.height : previewSize.width;
        final height = portrait ? previewSize.width : previewSize.height;
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: width,
              height: height,
              child: CameraPreview(controller!),
            ),
          ),
        );
      },
    );
  }
}

class _CameraGradient extends StatelessWidget {
  const _CameraGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB0000000), Color(0x08000000), Color(0xC7000000)],
          stops: [0, .48, 1],
        ),
      ),
    );
  }
}

class _MiniBrand extends StatelessWidget {
  const _MiniBrand();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF61F0E6), Color(0xFF5C8BFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(Icons.camera_rounded, color: Color(0xFF06121C)),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.active = false,
    this.size = 42,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? Theme.of(context).colorScheme.primary
            : Colors.black.withValues(alpha: .46),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Icon(
              icon,
              size: size * .48,
              color: active ? const Color(0xFF06121C) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _LatestPhotoButton extends StatelessWidget {
  const _LatestPhotoButton({required this.controller, required this.onPressed});

  final AppController controller;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final item = controller.latestPhoto;
    return Tooltip(
      message: 'Открыть фото',
      child: Semantics(
        button: true,
        label: 'Открыть фото',
        child: Material(
          color: Colors.black.withValues(alpha: .46),
          borderRadius: BorderRadius.circular(15),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 50,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item == null)
                    const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.white,
                      size: 25,
                    )
                  else
                    GalleryPhotoImage(
                      key: ValueKey('latest-${item.id}'),
                      controller: controller,
                      item: item,
                      cacheWidth: 160,
                    ),
                  if (item != null)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: PhotoUploadBadge(
                        item: item,
                        signedIn: controller.isSignedIn,
                        size: 22,
                        iconSize: 12,
                      ),
                    ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .75),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountControl extends StatelessWidget {
  const _AccountControl({
    required this.signedIn,
    required this.signingIn,
    required this.profile,
    required this.onSignIn,
    required this.onSignOut,
  });

  final bool signedIn;
  final bool signingIn;
  final GoogleAccountProfile? profile;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    if (!signedIn) {
      return FilledButton(
        onPressed: signingIn ? null : onSignIn,
        style: FilledButton.styleFrom(
          minimumSize: const Size(74, 42),
          padding: const EdgeInsets.symmetric(horizontal: 15),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF101820),
        ),
        child: signingIn
            ? const SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Войти'),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Аккаунт Google',
      offset: const Offset(0, 48),
      onSelected: (value) {
        if (value == 'logout') onSignOut();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile?.name.trim().isNotEmpty == true
                      ? profile!.name
                      : 'Google аккаунт',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (profile?.email.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(
                    profile!.email,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 20),
              SizedBox(width: 11),
              Text('Выйти'),
            ],
          ),
        ),
      ],
      child: Container(
        width: 42,
        height: 42,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundImage: profile?.pictureUrl != null
              ? NetworkImage(profile!.pictureUrl!)
              : null,
          child: Text(
            profile?.initials ?? 'G',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final CaptureMode mode;
  final bool enabled;
  final ValueChanged<CaptureMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .48),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeItem(
            text: 'Фото',
            selected: mode == CaptureMode.photo,
            onTap: enabled ? () => onChanged(CaptureMode.photo) : null,
          ),
          _ModeItem(
            text: 'Видео',
            selected: mode == CaptureMode.video,
            onTap: enabled ? () => onChanged(CaptureMode.video) : null,
          ),
        ],
      ),
    );
  }
}

class _ModeItem extends StatelessWidget {
  const _ModeItem({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: selected ? const Color(0xFF101820) : Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({
    required this.mode,
    required this.busy,
    required this.recording,
    required this.onPressed,
  });

  final CaptureMode mode;
  final bool busy;
  final bool recording;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = recording
        ? Theme.of(context).colorScheme.error
        : Colors.white;
    return Semantics(
      button: true,
      label: mode == CaptureMode.photo
          ? 'Сделать фото'
          : (recording ? 'Остановить запись' : 'Начать запись'),
      child: InkResponse(
        onTap: busy ? null : onPressed,
        radius: 48,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
            border: Border.all(color: Colors.white, width: 4),
          ),
          padding: const EdgeInsets.all(6),
          child: DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(
                      color: Color(0xFF101820),
                      strokeWidth: 2.5,
                    ),
                  )
                : Icon(
                    recording ? Icons.stop_rounded : null,
                    color: const Color(0xFF101820),
                    size: 30,
                  ),
          ),
        ),
      ),
    );
  }
}

class _RecordingBadge extends StatelessWidget {
  const _RecordingBadge({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD73E4F),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fiber_manual_record, size: 14),
          const SizedBox(width: 6),
          Text('$minutes:${remainder.toString().padLeft(2, '0')}'),
        ],
      ),
    );
  }
}
