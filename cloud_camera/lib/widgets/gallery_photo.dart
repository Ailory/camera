import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/gallery_item.dart';
import '../models/upload_job.dart';

class GalleryPhotoImage extends StatefulWidget {
  const GalleryPhotoImage({
    super.key,
    required this.controller,
    required this.item,
    this.fit = BoxFit.cover,
    this.cacheWidth = 640,
  });

  final AppController controller;
  final GalleryItem item;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  State<GalleryPhotoImage> createState() => _GalleryPhotoImageState();
}

class _GalleryPhotoImageState extends State<GalleryPhotoImage> {
  Future<Uint8List>? _remoteImage;

  @override
  void initState() {
    super.initState();
    _prepareRemoteImage();
  }

  @override
  void didUpdateWidget(covariant GalleryPhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.localPath != widget.item.localPath ||
        oldWidget.item.driveFileId != widget.item.driveFileId ||
        oldWidget.item.thumbnailLink != widget.item.thumbnailLink) {
      _prepareRemoteImage();
    }
  }

  void _prepareRemoteImage() {
    final path = widget.item.localPath;
    if (path != null && File(path).existsSync()) {
      _remoteImage = null;
      return;
    }
    _remoteImage = widget.controller.loadThumbnail(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.item.localPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: widget.fit,
        cacheWidth: widget.cacheWidth,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const GalleryImagePlaceholder(),
      );
    }

    final image = _remoteImage;
    if (image == null) return const GalleryImagePlaceholder();
    return FutureBuilder<Uint8List>(
      future: image,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          return Image.memory(
            snapshot.data!,
            fit: widget.fit,
            cacheWidth: widget.cacheWidth,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const GalleryImagePlaceholder(),
          );
        }
        if (snapshot.hasError) return const GalleryImagePlaceholder();
        return const GalleryImagePlaceholder(loading: true);
      },
    );
  }
}

class GalleryImagePlaceholder extends StatelessWidget {
  const GalleryImagePlaceholder({super.key, this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Center(
        child: loading
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.image_not_supported_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
      ),
    );
  }
}

class PhotoUploadBadge extends StatelessWidget {
  const PhotoUploadBadge({
    super.key,
    required this.item,
    required this.signedIn,
    this.size = 34,
    this.iconSize = 18,
  });

  final GalleryItem item;
  final bool signedIn;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final (tooltip, child) = switch (item.state) {
      UploadState.uploading => (
        'Сохраняется в Google Drive',
        SizedBox.square(
          dimension: iconSize,
          child: CircularProgressIndicator(
            value: item.progress > 0 && item.progress < 1
                ? item.progress
                : null,
            color: Colors.white,
            strokeWidth: size < 28 ? 1.8 : 2,
          ),
        ),
      ),
      UploadState.uploaded => (
        'Сохранено в Google Drive',
        Icon(Icons.cloud_done_rounded, size: iconSize),
      ),
      UploadState.failed => (
        'Не удалось сохранить фото',
        Icon(
          Icons.sync_problem_rounded,
          size: iconSize,
          color: Theme.of(context).colorScheme.error,
        ),
      ),
      UploadState.queued => (
        signedIn ? 'Фото скоро сохранится' : 'Войдите для сохранения',
        Icon(
          signedIn ? Icons.cloud_upload_outlined : Icons.cloud_off_rounded,
          size: iconSize,
        ),
      ),
    };

    return Tooltip(
      message: tooltip,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .66),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: .18)),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
