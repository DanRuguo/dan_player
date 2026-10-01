import 'dart:math' as math;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// One fixed-layout surface is used for both the scaled preview and PNG capture.
/// Export never substitutes an ellipsized or accessibility-scaled text layout.
class LyricShareCard extends StatelessWidget {
  const LyricShareCard({
    super.key,
    required this.title,
    required this.artist,
    required this.album,
    required this.lines,
    this.showSongInfo = true,
    this.artwork,
  });

  static const width = 540.0;
  static const maximumHeight = 960.0;
  static const pixelRatio = 2.0;
  static const maximumCharacters = 4096;
  static const _padding = 40.0;
  static const _lineGap = 18.0;
  final String title, artist, album;
  final List<String> lines;
  final bool showSongInfo;
  final ImageProvider? artwork;

  static TextStyle get _lyricStyle =>
      danCjkTextStyle(fontSize: 28, fontWeight: FontWeight.w500)
          .copyWith(inherit: false, height: 1.4);
  static TextStyle get _titleStyle =>
      danCjkTextStyle(fontSize: 20, fontWeight: FontWeight.w600)
          .copyWith(inherit: false);
  static TextStyle get _artistStyle =>
      danCjkTextStyle(fontSize: 16).copyWith(inherit: false);
  static TextStyle get _albumStyle =>
      danCjkTextStyle(fontSize: 14).copyWith(inherit: false);
  static TextStyle get _footerStyle =>
      danCjkTextStyle(fontSize: 12).copyWith(inherit: false);

  static double _textHeight(
      String text, TextStyle style, double width, TextDirection direction) {
    final painter = TextPainter(
        text: TextSpan(text: text, style: style), textDirection: direction);
    try {
      painter.layout(maxWidth: width);
      return painter.height;
    } finally {
      painter.dispose();
    }
  }

  /// Null means the complete content cannot fit the bounded export surface.
  /// Bound the input before TextPainter so a malformed enormous line cannot
  /// cause an unbounded layout or allocate an enormous image.
  double? measuredHeight(TextDirection direction) {
    if (lines.isEmpty || lines.length > 4) return null;
    final characters = lines.fold<int>(0, (sum, line) => sum + line.length) +
        (showSongInfo ? title.length + artist.length + album.length : 0);
    if (characters > maximumCharacters) return null;
    const bodyWidth = width - _padding * 2;
    var height = _padding * 2 +
        30 +
        _textHeight('Dan Player', _footerStyle, bodyWidth, direction);
    if (showSongInfo) {
      const metadataWidth = bodyWidth - 76;
      var metadataHeight =
          _textHeight(title, _titleStyle, metadataWidth, direction);
      if (artist.isNotEmpty) {
        metadataHeight +=
            8 + _textHeight(artist, _artistStyle, metadataWidth, direction);
      }
      if (album.isNotEmpty) {
        metadataHeight +=
            4 + _textHeight(album, _albumStyle, metadataWidth, direction);
      }
      height += math.max(60, metadataHeight) + 32;
    }
    for (var i = 0; i < lines.length; i++) {
      height += _textHeight(lines[i], _lyricStyle, bodyWidth, direction);
      if (i > 0) height += _lineGap;
    }
    height = math.max(280, height.ceilToDouble());
    return height <= maximumHeight ? height : null;
  }

  @override
  Widget build(BuildContext context) {
    final height = measuredHeight(Directionality.of(context));
    if (height == null) {
      throw StateError('LyricShareCard requires complete bounded content');
    }
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.primaryContainer,
      child:
          Icon(Symbols.music_note, size: 30, color: scheme.onPrimaryContainer),
    );
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: AppShape.surfaceRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.surfaceContainerLow, scheme.surface],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(_padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showSongInfo) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    SizedBox.square(
                      dimension: 60,
                      child: ClipRRect(
                        borderRadius: AppShape.smallRadius,
                        child: artwork == null
                            ? placeholder
                            : Image(
                                image: artwork!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => placeholder,
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title,
                            key: const ValueKey('lyric-share-card-title'),
                            textScaler: TextScaler.noScaling,
                            style:
                                _titleStyle.copyWith(color: scheme.onSurface)),
                        if (artist.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(artist,
                              textScaler: TextScaler.noScaling,
                              style: _artistStyle.copyWith(
                                  color: scheme.onSurfaceVariant)),
                        ],
                        if (album.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(album,
                              textScaler: TextScaler.noScaling,
                              style: _albumStyle.copyWith(
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ],
                    )),
                  ]),
                  const SizedBox(height: 32),
                ],
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0) const SizedBox(height: _lineGap),
                  Text(lines[i],
                      key: ValueKey('lyric-share-card-line-$i'),
                      textScaler: TextScaler.noScaling,
                      style: _lyricStyle.copyWith(color: scheme.onSurface)),
                ],
                const Spacer(),
                const SizedBox(height: 30),
                Text('Dan Player',
                    textScaler: TextScaler.noScaling,
                    style: _footerStyle.copyWith(color: scheme.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
