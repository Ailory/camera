import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/gallery_item.dart';
import '../widgets/gallery_photo.dart';
import 'photo_viewer_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({
    super.key,
    required this.controller,
    required this.onBack,
  });

  final AppController controller;
  final VoidCallback onBack;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refreshGallery());
  }

  Future<void> _importPhotos() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (result.isEmpty) return;
      for (final selected in result) {
        if (selected.path == null) continue;
        await widget.controller.enqueueFile(
          selected.path!,
          displayName: selected.name,
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _openPhoto(GalleryItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) =>
            PhotoViewerScreen(controller: widget.controller, item: item),
      ),
    );
  }

  Future<void> _deletePhoto(GalleryItem item) async {
    if (!item.canDelete || widget.controller.isDeletingGalleryItem(item)) {
      return;
    }
    final confirmed = await confirmPhotoDeletion(context, item);
    if (!confirmed || !mounted) return;
    await widget.controller.deleteGalleryItem(item);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.controller.galleryItems;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            _GalleryHeader(
              loading: widget.controller.galleryLoading,
              importing: _importing,
              onBack: widget.onBack,
              onImport: _importPhotos,
              onRefresh: widget.controller.refreshGallery,
            ),
            if (widget.controller.galleryLoading && items.isNotEmpty)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: items.isEmpty
                  ? _EmptyGallery(
                      loading: widget.controller.galleryLoading,
                      signedIn: widget.controller.isSignedIn,
                      importing: _importing,
                      onImport: _importPhotos,
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = math.max(
                          2,
                          math.min(6, (constraints.maxWidth / 190).floor()),
                        );
                        return RefreshIndicator(
                          onRefresh: widget.controller.refreshGallery,
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                            physics: const AlwaysScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  childAspectRatio: 1,
                                ),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return _GalleryTile(
                                key: ValueKey(item.id),
                                controller: widget.controller,
                                item: item,
                                onOpen: () => _openPhoto(item),
                                onDelete: () => _deletePhoto(item),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryHeader extends StatelessWidget {
  const _GalleryHeader({
    required this.loading,
    required this.importing,
    required this.onBack,
    required this.onImport,
    required this.onRefresh,
  });

  final bool loading;
  final bool importing;
  final VoidCallback onBack;
  final VoidCallback onImport;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Назад к камере',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Фото',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: 'Добавить фото',
            onPressed: importing ? null : onImport,
            icon: importing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate_outlined),
          ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: loading ? null : () => unawaited(onRefresh()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery({
    required this.loading,
    required this.signedIn,
    required this.importing,
    required this.onImport,
  });

  final bool loading;
  final bool signedIn;
  final bool importing;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 58,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 18),
              Text(
                'Здесь появятся ваши фото',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                signedIn
                    ? 'Сделайте снимок камерой или добавьте готовое фото.'
                    : 'Сделайте снимок или войдите в Google на экране камеры, чтобы увидеть фото из облака.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.tonalIcon(
                onPressed: importing ? null : onImport,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Добавить фото'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    super.key,
    required this.controller,
    required this.item,
    required this.onOpen,
    required this.onDelete,
  });

  final AppController controller;
  final GalleryItem item;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final deleting = controller.isDeletingGalleryItem(item);
    return Semantics(
      button: true,
      label: 'Открыть фото ${item.name}',
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: deleting ? null : onOpen,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GalleryPhotoImage(controller: controller, item: item),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x52000000), Colors.transparent],
                    stops: [0, .42],
                  ),
                ),
              ),
              Positioned(
                right: 7,
                top: 7,
                child: _TileDeleteButton(
                  enabled: item.canDelete && !deleting,
                  onPressed: onDelete,
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: PhotoUploadBadge(
                  item: item,
                  signedIn: controller.isSignedIn,
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
      ),
    );
  }
}

class _TileDeleteButton extends StatelessWidget {
  const _TileDeleteButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: enabled ? 'Удалить фото' : 'Дождитесь сохранения фото',
      child: Material(
        color: Colors.black.withValues(alpha: .54),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onPressed : null,
          child: SizedBox.square(
            dimension: 34,
            child: Icon(
              Icons.delete_outline_rounded,
              size: 19,
              color: enabled ? Colors.white : Colors.white54,
            ),
          ),
        ),
      ),
    );
  }
}
