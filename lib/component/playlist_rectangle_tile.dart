import 'dart:io';

import 'package:dan_player/component/app_item_ink_well.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/artwork_handoff.dart';
import 'package:dan_player/component/category_pointer_glow.dart';
import 'package:dan_player/component/cover_caption_colors.dart';
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:flutter/material.dart';

/// A title-only cover surface. The browser/AudioTile retain ownership of menus,
/// playback and relationship IDs. Menus open on secondary click.
class PlaylistRectangleTile extends StatefulWidget {
  const PlaylistRectangleTile({
    super.key,
    required this.title,
    this.showTitle = true,
    this.audio,
    this.imagePath,
    this.revision,
    this.loadArtwork = true,
    required this.onTap,
    required this.onSecondaryTapDown,
    required this.onLongPress,
    required this.contentWrapper,
    this.selected = false,
    this.artworkWrapper,
  });

  final String title;
  final bool showTitle;
  final Audio? audio;
  final String? imagePath;
  final Object? revision;
  final bool loadArtwork, selected;
  final VoidCallback onTap, onLongPress;
  final GestureTapDownCallback onSecondaryTapDown;
  final Widget Function(Widget) contentWrapper;
  final Widget Function(Widget)? artworkWrapper;

  @override
  State<PlaylistRectangleTile> createState() => _PlaylistRectangleTileState();
}

class _PlaylistRectangleTileState extends State<PlaylistRectangleTile> {
  Object? _request;
  Future<ImageProvider?>? _image;
  int? _coverGeneration;

  Widget _wrapArtwork(Widget child) =>
      widget.artworkWrapper?.call(child) ?? child;

  @override
  void initState() {
    super.initState();
    CoverCache.instance.changes.addListener(_coverChanged);
  }

  void _coverChanged() {
    final audio = widget.audio;
    if (!mounted || audio == null) return;
    final generation = CoverCache.instance.generationFor(audio.localFilePath);
    if (generation == _coverGeneration) return;
    setState(() {
      _coverGeneration = generation;
      _request = null;
    });
  }

  @override
  void dispose() {
    CoverCache.instance.changes.removeListener(_coverChanged);
    super.dispose();
  }

  Future<ImageProvider?> _load(ArtworkSize target) async {
    final customPath = widget.imagePath;
    if (customPath != null && customPath.isNotEmpty) {
      final image = ArtworkImageProvider(FileImage(File(customPath)), target,
          revision: widget.revision);
      var failed = false;
      await precacheImage(image, context, onError: (_, __) => failed = true);
      if (!failed) return image;
    }
    return widget.loadArtwork ? widget.audio?.artworkForSize(target) : null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final scheme = Theme.of(context).colorScheme;
        final target = ArtworkSize.forDisplay(
            logicalWidth: box.maxWidth,
            logicalHeight: box.maxHeight,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context));
        final audio = widget.audio;
        _coverGeneration = audio == null
            ? null
            : CoverCache.instance.generationFor(audio.localFilePath);
        final request = (
          widget.imagePath,
          widget.revision,
          widget.loadArtwork,
          audio?.path,
          audio?.modified,
          audio?.coverFingerprint,
          audio?.artworkUrl,
          _coverGeneration ?? 0,
          target,
        );
        if (_request != request) {
          _request = request;
          _image = _load(target);
        }
        final aspect = box.maxWidth / box.maxHeight;
        final placeholder = ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: Center(
              child: Icon(Icons.album_outlined,
                  size: box.maxWidth.clamp(48, 128) * .5,
                  color: scheme.primary)),
        );
        final interaction = Material(
          color: Colors.transparent,
          child: AppItemInkWell(
            onTap: widget.onTap,
            onSecondaryTapDown: widget.onSecondaryTapDown,
            onLongPress: widget.onLongPress,
            child: const SizedBox.expand(),
          ),
        );
        return ClipRect(
            child: RepaintBoundary(
                child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<ImageProvider?>(
                future: _image,
                builder: (context, snapshot) {
                  final provider = snapshot.data;
                  return Stack(fit: StackFit.expand, children: [
                    _wrapArtwork(ArtworkHandoff(
                        artworkKey: request,
                        loadArtwork: () => _image!,
                        placeholder: placeholder,
                        imageBuilder: (image) => Image(
                            image: image,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, __, ___) => placeholder))),
                    Positioned(
                        left: 4,
                        right: 4,
                        bottom: 5,
                        child: AnimatedSwitcher(
                            duration: (!AppMotion.enabled(context, MotionKind.layout))
                                ? Duration.zero
                                : AppMotion.standard,
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            child: !widget.showTitle
                                ? const SizedBox.shrink()
                                : FutureBuilder<CoverCaptionColors>(
                                    key: const ValueKey('visible-caption'),
                                    initialData: provider == null
                                        ? null
                                        : CoverCaptionCache.cached(
                                            provider, aspect),
                                    future: provider == null
                                        ? null
                                        : CoverCaptionCache.resolve(
                                            provider, aspect),
                                    builder: (context, colors) => AnimatedDefaultTextStyle(
                                        duration: (!AppMotion.enabled(context, MotionKind.layout))
                                            ? Duration.zero
                                            : AppMotion.standard,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium!
                                            .copyWith(
                                                color: provider == null
                                                    ? scheme.onSurface
                                                    : (CoverCaptionCache.cached(provider, aspect) ?? colors.data ?? CoverCaptionColors.fallback)
                                                        .foreground,
                                                height: 1.3,
                                                fontWeight: FontWeight.w600),
                                        child: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center))))),
                  ]);
                }),
            widget.contentWrapper(
                CategoryPointerGlow(circle: false, child: interaction)),
            if (widget.selected)
              IgnorePointer(
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          border:
                              Border.all(color: scheme.primary, width: 3)))),
          ],
        )));
      });
}
