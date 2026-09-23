import 'dart:math' as math;

import 'package:dan_player/component/full_width_spectrum.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The complete artwork/effect envelope stays inside its existing layout cell.
/// On smaller cells the artwork yields room to the bars, never nearby content.
@immutable
class CoverSpectrumGeometry {
  const CoverSpectrumGeometry(this.size, this.coverRect);
  final Size size;
  final Rect coverRect;

  factory CoverSpectrumGeometry.fit(Size available, {required bool enabled}) {
    final maximum = enabled ? 476.0 : 400.0;
    final width = available.width.isFinite ? available.width : maximum;
    final height = available.height.isFinite ? available.height : maximum;
    final side = math.min(maximum, math.min(width, height)).clamp(0.0, maximum);
    final extent = enabled
        ? math.min(34.0, side * .075) + math.min(4.0, side * .012)
        : 0.0;
    return CoverSpectrumGeometry(Size.square(side),
        Rect.fromLTWH(extent, extent, side - extent * 2, side - extent * 2));
  }
}

class CoverSpectrumFrame extends StatelessWidget {
  const CoverSpectrumFrame({
    super.key,
    required this.enabled,
    required this.coverBuilder,
    required this.spectrumBuilder,
  });
  final bool enabled;
  final Widget Function(double size) coverBuilder;
  final Widget Function(Size size, Rect coverRect) spectrumBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final geometry =
              CoverSpectrumGeometry.fit(constraints.biggest, enabled: enabled);
          if (geometry.size.isEmpty) return const SizedBox.shrink();
          return Center(
            child: SizedBox.fromSize(
              size: geometry.size,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  if (enabled)
                    Positioned.fill(
                        key: const ValueKey('lyric-cover-spectrum'),
                        child:
                            spectrumBuilder(geometry.size, geometry.coverRect)),
                  Positioned.fromRect(
                      key: const ValueKey('lyric-cover-artwork'),
                      rect: geometry.coverRect,
                      child: coverBuilder(geometry.coverRect.width)),
                ],
              ),
            ),
          );
        },
      );
}

class LyricCoverSpectrum extends StatelessWidget {
  const LyricCoverSpectrum({
    super.key,
    required this.coverBuilder,
    this.coverVisible,
    this.activeCoverGeneration,
    this.coverGeneration = 0,
  });
  final Widget Function(double size) coverBuilder;
  final ValueListenable<bool>? coverVisible;
  final ValueListenable<int>? activeCoverGeneration;
  final int coverGeneration;

  bool _active(RenderingPreferences preferences) =>
      lyricSpectrumVisibleAt(preferences, LyricSpectrumPlacement.cover,
          coverVisible: (coverVisible?.value ?? true) &&
              (activeCoverGeneration == null ||
                  activeCoverGeneration!.value == coverGeneration));

  @override
  Widget build(BuildContext context) {
    final preferences = RenderingPreferencesScope.of(context);
    final enabled = preferences.lyricSpectrum &&
        preferences.lyricSpectrumPlacement == LyricSpectrumPlacement.cover;
    return CoverSpectrumFrame(
      enabled: enabled,
      coverBuilder: coverBuilder,
      spectrumBuilder: (size, coverRect) {
        final playback = PlayService.instance.playbackService;
        return FullWidthSpectrumView(
          height: size.height,
          coverRect: coverRect,
          maximumBars: preferences.spectrumDensity.maximumBars,
          samples: playback.frequencySpectrumStream,
          readLevels: () => playback.frequencySpectrumLevels,
          hidden: DesktopIntegration.instance.isHidden,
          activity: Listenable.merge([coverVisible, activeCoverGeneration]),
          shouldListen: _active,
        );
      },
    );
  }
}
