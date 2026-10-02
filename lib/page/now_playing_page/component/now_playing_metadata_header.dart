import 'dart:math' as math;

import 'package:dan_player/component/overflow_marquee_text.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

const _titleStyle = TextStyle(fontWeight: FontWeight.w600, fontSize: 24);
const _metadataChrome = 19.0;
const _metadataDivider = 21.0;

Size _measureHeaderText(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
      text: TextSpan(
          text: text.replaceAll(RegExp(r'[\r\n]+'), ' '),
          style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1)
    ..layout();
  final size = painter.size;
  painter.dispose();
  return size;
}

({double inside, double after}) _headerSpacing(
    BuildContext context, String title) {
  final previous =
      _measureHeaderText(context, title, _titleStyle.copyWith(fontSize: 20));
  final current = _measureHeaderText(context, title, _titleStyle);
  final budget = math.max(0.0, 16 - (current.height - previous.height));
  final inside = math.min(4.0, budget);
  return (inside: inside, after: budget - inside);
}

/// Spend the original 16px spacing budget on the larger title before taking
/// space from the cover. At extreme text scales the measured title takes priority.
double nowPlayingMetadataCoverGap(BuildContext context, String title) =>
    _headerSpacing(context, title).after;

/// The existing two-line header, with a clear title/metadata hierarchy.
class NowPlayingMetadataHeader extends StatelessWidget {
  const NowPlayingMetadataHeader({
    super.key,
    required this.title,
    required this.artist,
    required this.album,
    this.hidden,
  });
  final String title, artist, album;
  final ValueListenable<bool>? hidden;

  Widget _metadata(
      BuildContext context, String text, String label, IconData icon,
      {required double width}) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: width,
      child: Tooltip(
        message: '${ui(label)}: $text',
        child: Row(children: [
          if (width >= _metadataChrome) ...[
            Icon(icon, size: 14, color: color.withValues(alpha: .72)),
            const SizedBox(width: 5),
          ],
          Expanded(
            child: OverflowMarqueeText(text,
                hidden: hidden,
                style: TextStyle(color: color.withValues(alpha: .88))),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final color = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        OverflowMarqueeText(title,
            key: const ValueKey('now-playing-metadata-title'),
            hidden: hidden,
            style: _titleStyle.copyWith(color: color)),
        SizedBox(height: _headerSpacing(context, title).inside),
        LayoutBuilder(builder: (context, constraints) {
          final hasArtist = artist.trim().isNotEmpty;
          final hasAlbum = album.trim().isNotEmpty;
          final style = TextStyle(color: color.withValues(alpha: .88));
          final artistText = hasArtist
              ? _measureHeaderText(context, artist, style).width.ceilToDouble()
              : 0.0;
          final albumText = hasAlbum
              ? _measureHeaderText(context, album, style).width.ceilToDouble()
              : 0.0;
          final naturalArtist = hasArtist ? artistText + _metadataChrome : 0.0;
          final naturalAlbum = hasAlbum ? albumText + _metadataChrome : 0.0;
          final maximum = constraints.maxWidth;
          final divider =
              hasArtist && hasAlbum && maximum >= 59 ? _metadataDivider : 0.0;
          final available = math.max(0.0, maximum - divider);
          var artistWidth = math.min(naturalArtist, available);
          var albumWidth = math.min(naturalAlbum, available);
          if (hasArtist &&
              hasAlbum &&
              naturalArtist + naturalAlbum > available) {
            if (available < _metadataChrome * 2) {
              artistWidth = albumWidth = available / 2;
            } else {
              final textBudget = available - _metadataChrome * 2;
              final half = textBudget / 2;
              final artistShare = artistText <= half
                  ? artistText
                  : albumText <= half
                      ? textBudget - albumText
                      : textBudget * artistText / (artistText + albumText);
              artistWidth = _metadataChrome + artistShare;
              albumWidth = available - artistWidth;
            }
          }
          return Row(children: [
            if (hasArtist)
              _metadata(context, artist, '歌手', Symbols.artist,
                  width: artistWidth),
            if (divider > 0)
              SizedBox(
                  width: divider,
                  height: 12,
                  child: VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: color.withValues(alpha: .3))),
            if (hasAlbum)
              _metadata(context, album, '专辑', Symbols.album, width: albumWidth),
          ]);
        }),
      ],
    );
  }
}
