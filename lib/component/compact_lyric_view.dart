import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/window_chrome_theme.dart';
import 'package:dan_player/lyric/compact_lyric_frame.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Uses a future already owned by LyricService. This widget never loads a source
/// or creates a player, timer, position subscription or network request.
class CompactLyricView extends StatefulWidget {
  const CompactLyricView({
    super.key,
    required this.trackIdentity,
    this.lyricFuture,
    this.position = 0,
  });

  final Object? trackIdentity;
  final Future<Lyric?>? lyricFuture;
  final double position;

  @override
  State<CompactLyricView> createState() => _CompactLyricViewState();
}

class _CompactLyricViewState extends State<CompactLyricView>
    with WidgetsBindingObserver {
  Lyric? _lyric;
  CompactLyricTimeline? _timeline;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(CompactLyricView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackIdentity != widget.trackIdentity ||
        !identical(oldWidget.lyricFuture, widget.lyricFuture)) {
      _lyric = null;
      _timeline = null;
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _reduced {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        features.disableAnimations ||
        features.reduceMotion ||
        !TickerMode.valuesOf(context).enabled;
  }

  CompactLyricFrame _resolve(AsyncSnapshot<Lyric?> snapshot) {
    if (widget.trackIdentity == null) return CompactLyricFrame.idle;
    if (widget.lyricFuture == null) return CompactLyricFrame.unavailable;
    if (snapshot.connectionState != ConnectionState.done) {
      return CompactLyricFrame.loading;
    }
    if (snapshot.hasError) return CompactLyricFrame.failed;
    final value = snapshot.data;
    if (value == null) return CompactLyricFrame.unavailable;
    if (!identical(_lyric, value)) {
      _lyric = value;
      _timeline = CompactLyricTimeline(value);
    }
    final milliseconds = widget.position * 1000;
    return _timeline!.at(Duration(
      milliseconds:
          milliseconds.isFinite && milliseconds > 0 ? milliseconds.round() : 0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return FutureBuilder<Lyric?>(
      // Replacing the key clears the previous snapshot immediately, including
      // when only the source changes for the same track. FutureBuilder itself
      // drops an old future's late success/error after replacement/disposal.
      key: ValueKey((widget.trackIdentity, widget.lyricFuture)),
      future: widget.trackIdentity == null ? null : widget.lyricFuture,
      builder: (context, snapshot) {
        final frame = _resolve(snapshot);
        // Only application-owned status text is translated. Actual lyric
        // content stays byte-for-byte unchanged even when it happens to equal
        // a catalog key such as “播放”.
        final primary = frame.status == CompactLyricStatus.active
            ? frame.primary
            : ui(frame.primary);
        final secondary =
            frame.secondaryKind == CompactLyricSecondary.information
                ? ui(frame.secondary)
                : frame.secondary;
        final displaySecondary = frame.secondary.isEmpty
            ? ''
            : frame.secondaryKind == CompactLyricSecondary.nextLine
                ? ui('下一句 · {0}', [frame.secondary])
                : secondary;
        final secondaryLabel = switch (frame.secondaryKind) {
          CompactLyricSecondary.translation => ui('译文'),
          CompactLyricSecondary.nextLine => ui('下一句'),
          CompactLyricSecondary.firstLine => ui('首句'),
          _ => '',
        };
        final fullText = secondary.isEmpty
            ? primary
            : '$primary\n${secondaryLabel.isEmpty ? '' : '$secondaryLabel：'}$secondary';
        final scheme = Theme.of(context).colorScheme;
        final highContrast =
            (MediaQuery.maybeHighContrastOf(context) ?? false) ||
                context
                        .dependOnInheritedWidgetOfExactType<WindowChromeTheme>()
                        ?.foreground !=
                    null;
        final textScaler = MediaQuery.textScalerOf(context);
        final primaryHeight = textScaler.scale(16) * 1.2;
        final secondaryHeight = textScaler.scale(13) * 1.2;
        final content = Semantics(
          key: ValueKey(frame.identity),
          label: frame.status == CompactLyricStatus.active
              ? ui("当前歌词：{0}", [fullText])
              : fullText,
          child: ExcludeSemantics(
            child: Tooltip(
              message: fullText,
              excludeFromSemantics: true,
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: primaryHeight,
                      child: Text(
                        key: const ValueKey('compact-lyric-primary'),
                        primary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: 16,
                          height: 1.2,
                          fontWeight: frame.status == CompactLyricStatus.active
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: secondaryHeight,
                      child: Text(
                        key: const ValueKey('compact-lyric-secondary'),
                        displaySecondary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant
                              .withValues(alpha: highContrast ? 1 : .72),
                          fontSize: 13,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        if (_reduced) return content;
        return AnimatedSwitcher(
          key: const ValueKey('compact-lyric-switcher'),
          duration: AppMotion.quick,
          switchInCurve: Curves.linear,
          switchOutCurve: Curves.linear,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.center,
            children: [...previous, if (current != null) current],
          ),
          transitionBuilder: (child, animation) => IgnorePointer(
            ignoring: child.key != content.key,
            child: ExcludeSemantics(
              excluding: child.key != content.key,
              // Fade through an empty midpoint so dense lyrics never paint
              // over each other when a line or loading status changes.
              child: FadeTransition(
                opacity: animation.drive(CurveTween(
                    curve: const Interval(.5, 1, curve: Curves.easeOutCubic))),
                child: child,
              ),
            ),
          ),
          child: content,
        );
      },
    );
  }
}
