import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/gallery_item.dart';
import '../widgets/gallery_photo.dart';

class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.controller,
    required this.item,
  });

  final AppController controller;
  final GalleryItem item;

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late Future<Uint8List> _photo;

  @override
  void initState() {
    super.initState();
    _photo = widget.controller.loadPhoto(widget.item);
  }

  GalleryItem? get _currentItem {
    for (final item in widget.controller.galleryItems) {
      if (item.id == widget.item.id) return item;
    }
    return null;
  }

  void _retry() {
    final item = _currentItem ?? widget.item;
    setState(() => _photo = widget.controller.loadPhoto(item));
  }

  Future<void> _deletePhoto(GalleryItem item) async {
    if (!item.canDelete || widget.controller.isDeletingGalleryItem(item)) {
      return;
    }
    final confirmed = await confirmPhotoDeletion(context, item);
    if (!confirmed || !mounted) return;
    final deleted = await widget.controller.deleteGalleryItem(item);
    if (deleted && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final item = _currentItem ?? widget.item;
        final deleted = _currentItem == null;
        final deleting =
            !deleted && widget.controller.isDeletingGalleryItem(item);

        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _FullPhoto(future: _photo, onRetry: _retry),
                const IgnorePointer(child: _ViewerGradient()),
                Positioned(
                  left: 8,
                  right: 8,
                  top: 8,
                  child: Row(
                    children: [
                      _ViewerButton(
                        tooltip: 'Назад',
                        icon: Icons.arrow_back_rounded,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _ViewerButton(
                        tooltip: item.canDelete
                            ? 'Удалить фото'
                            : 'Дождитесь сохранения фото',
                        icon: Icons.delete_outline_rounded,
                        onPressed: item.canDelete && !deleting && !deleted
                            ? () => unawaited(_deletePhoto(item))
                            : null,
                      ),
                    ],
                  ),
                ),
                if (!deleted)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 16,
                    child: Center(
                      child: PhotoUploadBadge(
                        item: item,
                        signedIn: widget.controller.isSignedIn,
                      ),
                    ),
                  ),
                if (deleting)
                  ColoredBox(
                    color: Colors.black.withValues(alpha: .52),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FullPhoto extends StatelessWidget {
  const _FullPhoto({required this.future, required this.onRetry});

  final Future<Uint8List> future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          return InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            boundaryMargin: const EdgeInsets.all(80),
            child: Center(
              child: Image.memory(
                snapshot.data!,
                fit: BoxFit.contain,
                cacheWidth: 4096,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _PhotoLoadError(onRetry: onRetry),
              ),
            ),
          );
        }
        if (snapshot.hasError) return _PhotoLoadError(onRetry: onRetry);
        return const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.5,
          ),
        );
      },
    );
  }
}

class _PhotoLoadError extends StatelessWidget {
  const _PhotoLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            color: Colors.white70,
            size: 48,
          ),
          const SizedBox(height: 14),
          const Text(
            'Не удалось открыть фото',
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}

class _ViewerGradient extends StatelessWidget {
  const _ViewerGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xA6000000), Colors.transparent, Color(0x70000000)],
          stops: [0, .22, 1],
        ),
      ),
    );
  }
}

class _ViewerButton extends StatelessWidget {
  const _ViewerButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: .48),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white38,
      ),
      icon: Icon(icon),
    );
  }
}

Future<bool> confirmPhotoDeletion(
  BuildContext context,
  GalleryItem item,
) async {
  final storedInDrive = item.driveFileId != null;
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Удалить фото?'),
          content: Text(
            storedInDrive
                ? 'Фото будет перемещено в корзину Google Drive.'
                : 'Фото будет удалено из приложения, отправка отменится.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Удалить'),
            ),
          ],
        ),
      ) ??
      false;
}
