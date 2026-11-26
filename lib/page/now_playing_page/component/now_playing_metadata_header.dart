import 'dart:math' as math;
import 'package:dan_player/component/app_motion.dart';
import 'package:desktop_lyric/component/text_pixel_snap.dart';
import 'package:desktop_lyric/font_policy.dart';

import 'package:dan_player/component/overflow_marquee_text.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

const _titleStyle = TextStyle(fontWeight: FontWeight.w600, fontSize: 24);
const _metadataChrome = 19.0;
const _metadataDivider = 21.0;

const _headerMeasureCacheCapacity = 32;
final _headerMeasureCache = <Object, Size>{};

/// Clears the bounded header text layout cache (for isolated tests).
@visibleForTesting
void clearNowPlayingMetadataHeaderMeasureCache() => _headerMeasureCache.clear();

@visibleForTesting
int get nowPlayingMetadataHeaderMeasureCacheLength =>
    _headerMeasureCache.length;

Size _measureHeaderText(BuildContext context, String text, TextStyle style) {
  final singleLine = text.replaceAll(RegExp(r'[\r\n]+'), ' ');
  final merged = DefaultTextStyle.of(context).style.merge(style);
  final policy = AppFontScope.of(context);
  final direction = Directionality.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  final locale = Localizations.maybeLocaleOf(context);
  final key = (
    singleLine,
    merged.fontSize,
    merged.fontWeight,
    merged.fontStyle,
    merged.fontFamily,
    merged.height,
    merged.letterSpacing,
    merged.wordSpacing,
    policy,
    direction,
    scaler,
    locale,
  );
  final cached = _headerMeasureCache.remove(key);
  if (cached != null) {
    _headerMeasureCache[key] = cached;
    return cached;
  }
  final painter = TextPainter(
      text: appFontSpan(singleLine, style: merged, policy: policy),
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
      maxLines: 1)
    ..layout();
  final size = painter.size;
  painter.dispose();
  if (_headerMeasureCache.length >= _headerMeasureCacheCapacity) {
    _headerMeasureCache.remove(_headerMeasureCache.keys.first);
  }
  _headerMeasureCache[key] = size;
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
        _MetadataFieldTransition(
          identity: title,
          hidden: hidden,
          child: OverflowMarqueeText(title,
              key: const ValueKey('now-playing-metadata-title'),
              hidden: hidden,
              style: _titleStyle.copyWith(color: color)),
        ),
        SizedBox(height: _headerSpacing(context, title).inside),
        _MetadataFieldTransition(
          identity: (artist, album),
          hidden: hidden,
          child: LayoutBuilder(builder: (context, constraints) {
            final hasArtist = artist.trim().isNotEmpty;
            final hasAlbum = album.trim().isNotEmpty;
            final style = TextStyle(color: color.withValues(alpha: .88));
            final artistText = hasArtist
                ? _measureHeaderText(context, artist, style)
                    .width
                    .ceilToDouble()
                : 0.0;
            final albumText = hasAlbum
                ? _measureHeaderText(context, album, style).width.ceilToDouble()
                : 0.0;
            final naturalArtist =
                hasArtist ? artistText + _metadataChrome : 0.0;
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
                _metadata(context, album, '专辑', Symbols.album,
                    width: albumWidth),
            ]);
          }),
        ),
      ],
    );
  }
}

/// Smooth single-child entrance on metadata field change without duplicating
/// child keys or running when hidden / reduced motion is active.
class _MetadataFieldTransition extends StatefulWidget {
  const _MetadataFieldTransition({
    required this.identity,
    required this.child,
    this.hidden,
  });

  final Object identity;
  final Widget child;
  final ValueListenable<bool>? hidden;

  @override
  State<_MetadataFieldTransition> createState() =>
      _MetadataFieldTransitionState();
}

class _MetadataFieldTransitionState extends State<_MetadataFieldTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.emphasized,
    value: 1,
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: .28,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    widget.hidden?.addListener(_handleHidden);
  }

  void _handleHidden() {
    if (widget.hidden?.value == true && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  bool _canAnimate(BuildContext context) {
    if (widget.hidden?.value == true) return false;
    if (!TickerMode.valuesOf(context).enabled) return false;
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    if (features.disableAnimations || features.reduceMotion) return false;
    return AppMotion.enabled(context, MotionKind.transitions);
  }

  @override
  void didUpdateWidget(covariant _MetadataFieldTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hidden, widget.hidden)) {
      oldWidget.hidden?.removeListener(_handleHidden);
      widget.hidden?.addListener(_handleHidden);
    }
    if (oldWidget.identity != widget.identity) {
      if (_canAnimate(context)) {
        _controller.forward(from: 0);
      } else {
        _controller.stop();
        _controller.value = 1;
      }
    } else if (!_canAnimate(context) && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    widget.hidden?.removeListener(_handleHidden);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return FadeTransition(
      opacity: _opacity,
      alwaysIncludeSemantics: true,
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final offset = _controller.value >= 1
              ? Offset.zero
              : snapOffsetToPhysicalPixel(
                  Offset(
                    (1 - Curves.easeOutCubic.transform(_controller.value)) * 6,
                    0,
                  ),
                  dpr,
                );
          return Transform.translate(offset: offset, child: child);
        },
      ),
    );
  }
}
