import 'package:dan_player/app_settings.dart';
import 'package:dan_player/background_image_store.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/component/artwork_backdrop.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Owns only a background layer. Changing its source must never remount the
/// page, restart playback, blur text/cover art, or affect native hit testing.
class SceneBackground extends StatelessWidget {
  const SceneBackground({
    super.key,
    required this.scene,
    this.preferences,
    this.status,
    this.hidden,
  });

  final BackgroundScene scene;
  final ValueListenable<BackgroundPreferences>? preferences;
  final WindowBackdropStatus? status;
  final ValueListenable<bool>? hidden;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<BackgroundPreferences>(
        valueListenable: preferences ?? AppSettings.instance.backgrounds,
        builder: (context, preferences, _) {
          final appearance = preferences.forScene(scene);
          Widget layer(WindowBackdropStatus status) =>
              ValueListenableBuilder<bool>(
                valueListenable: hidden ?? DesktopIntegration.instance.isHidden,
                builder: (context, hidden, _) {
                  Widget render(bool playing) => BackgroundLayer(
                        appearance: appearance,
                        status: status,
                        neutralFallback: scene == BackgroundScene.main,
                        isPlaying: playing,
                        isVisible: !hidden,
                        hidden:
                            this.hidden ?? DesktopIntegration.instance.isHidden,
                      );
                  if (!appearance.motion || !appearance.source.usesImage) {
                    return render(false);
                  }
                  return PlaybackReadyBuilder(
                    waitingBuilder: (_) => render(false),
                    readyBuilder: (_) {
                      final playback = PlayService.instance.playbackService;
                      return StreamBuilder<PlayerState>(
                        stream: playback.playerStateStream,
                        initialData: playback.playerState,
                        builder: (_, state) =>
                            render(state.data == PlayerState.playing),
                      );
                    },
                  );
                },
              );
          if (status != null) return layer(status!);
          return ValueListenableBuilder<WindowBackdropStatus>(
            valueListenable: WindowBackdropService.instance,
            builder: (_, value, __) => layer(value),
          );
        },
      );
}

/// Render-only seam for deterministic tests without a player or desktop HWND.
class BackgroundLayer extends StatelessWidget {
  const BackgroundLayer({
    super.key,
    required this.appearance,
    required this.status,
    this.neutralFallback = false,
    this.artworkKey,
    this.loadArtwork,
    this.loadCustomImage,
    this.isPlaying = false,
    this.isVisible = true,
    this.hidden,
  });

  final BackgroundAppearance appearance;
  final WindowBackdropStatus status;
  final bool neutralFallback;
  final Object? artworkKey;
  final Future<ImageProvider?> Function()? loadArtwork;
  final Future<ImageProvider?> Function(String)? loadCustomImage;
  final bool isPlaying;
  final bool isVisible;
  final ValueListenable<bool>? hidden;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highContrast =
        MediaQuery.highContrastOf(context) || status.reason == 'high_contrast';
    final neutral = theme.brightness == Brightness.dark
        ? const Color(0xFF202020)
        : const Color(0xFFF3F3F3);
    final fallback = neutralFallback
        ? (status.fallbackColor ?? neutral)
        : theme.colorScheme.surface;
    final source = highContrast ? BackgroundSource.solid : appearance.source;
    Widget background;
    switch (source) {
      case BackgroundSource.solid:
        background = ColoredBox(color: fallback);
      case BackgroundSource.desktop:
        background = ColoredBox(
          // The same single veil spans title/nav/margins (or all of mini).
          // No per-frame DWM calls and no wallpaper snapshots.
          color: status.available
              ? neutral.withValues(alpha: appearance.opacity.clamp(.25, .95))
              : fallback,
        );
      case BackgroundSource.artwork:
        background = loadArtwork != null
            ? _artwork(artworkKey ?? loadArtwork!, loadArtwork!)
            : _CurrentArtworkBackground(
                appearance: appearance,
                isPlaying: isPlaying,
                isVisible: isVisible,
                hidden: hidden,
              );
      case BackgroundSource.customImage:
        final id = appearance.customImageId;
        background = !isBackgroundImageId(id)
            ? ColoredBox(color: fallback)
            : _artwork(
                ('custom-background', id),
                () =>
                    loadCustomImage?.call(id!) ??
                    BackgroundImageStore.instance.imageFor(id),
                displaySized: true,
              );
    }
    return IgnorePointer(child: ExcludeSemantics(child: background));
  }

  Widget _artwork(Object key, Future<ImageProvider?> Function() load,
          {bool displaySized = false}) =>
      ArtworkBackdrop(
        artworkKey: key,
        loadArtwork: load,
        blur: appearance.blur,
        opacity: appearance.opacity,
        motion: appearance.motion,
        isPlaying: isPlaying,
        isVisible: isVisible,
        displaySized: displaySized,
        hidden: hidden,
        child: const SizedBox.expand(),
      );
}

class _CurrentArtworkBackground extends StatelessWidget {
  const _CurrentArtworkBackground({
    required this.appearance,
    required this.isPlaying,
    required this.isVisible,
    this.hidden,
  });
  final BackgroundAppearance appearance;
  final bool isPlaying;
  final bool isVisible;
  final ValueListenable<bool>? hidden;

  @override
  Widget build(BuildContext context) => PlaybackReadyBuilder(
        waitingBuilder: (context) =>
            ColoredBox(color: Theme.of(context).colorScheme.surface),
        readyBuilder: _buildReady,
      );

  Widget _buildReady(BuildContext context) {
    // The gate subscribes to startup completion without creating a player.
    final playback = PlayService.instance.playbackService;
    return ListenableBuilder(
      listenable: Listenable.merge([playback, AudioLibrary.changes]),
      builder: (context, _) {
        final audio = playback.nowPlaying;
        return ArtworkBackdrop(
          artworkKey: (
            audio?.path,
            audio?.modified,
            audio?.artworkUrl,
            AudioLibrary.revision
          ),
          // Background-only sampling. Visible artwork keeps its DPR-aware
          // full-quality request and is never filtered through this layer.
          loadArtwork: () => audio == null
              ? Future<ImageProvider?>.value()
              : audio.artworkForSize(const ArtworkSize(512, 512)),
          blur: appearance.blur,
          opacity: appearance.opacity,
          motion: appearance.motion,
          isPlaying: isPlaying,
          isVisible: isVisible,
          hidden: hidden,
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
