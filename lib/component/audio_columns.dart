import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Only library-style hosts opt in. Playlist relationship rows stay unchanged.
class AudioColumnsScope extends InheritedWidget {
  const AudioColumnsScope(
      {super.key, required this.enabled, required super.child});
  final bool enabled;
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AudioColumnsScope>()
          ?.enabled ??
      false;
  static bool fits(BuildContext context, double width) =>
      width >=
      700 * math.max(1, MediaQuery.textScalerOf(context).scale(14) / 14);
  @override
  bool updateShouldNotify(AudioColumnsScope oldWidget) =>
      enabled != oldWidget.enabled;
}

/// Shared proportions keep the header and recycled song rows aligned.
class AudioColumnFields extends StatelessWidget {
  const AudioColumnFields(
      {super.key,
      required this.title,
      required this.composer,
      required this.album,
      this.titleColor,
      this.metadataColor,
      this.heading = false});
  final String title, composer, album;
  final Color? titleColor, metadataColor;
  final bool heading;
  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    Widget field(String value, Color? color) => Tooltip(
          message: value,
          child: Text(value,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: (heading
                      ? theme.textTheme.labelLarge!
                      : theme.textTheme.bodyMedium!)
                  .copyWith(
                      color: color,
                      fontSize: heading ? 13 : 14,
                      fontWeight: heading ? FontWeight.w600 : null)),
        );
    Widget gap() => SizedBox(
        width: 16,
        child: heading
            ? Center(
                child: Container(
                    width: 1,
                    height: 14,
                    color: theme.colorScheme.primary.withValues(alpha: .14)))
            : null);
    return Row(children: [
      Expanded(flex: 5, child: field(title, titleColor)),
      gap(),
      Expanded(flex: 3, child: field(composer, metadataColor)),
      gap(),
      Expanded(flex: 4, child: field(album, metadataColor)),
    ]);
  }
}

class AudioColumnsHeader extends StatelessWidget {
  const AudioColumnsHeader({super.key, this.reorder = false});
  final bool reorder;
  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
        header: true,
        child: Container(
          key: const ValueKey('audio-columns-header'),
          margin: const EdgeInsets.only(top: 4, bottom: 8),
          padding: EdgeInsets.fromLTRB(8, 10, reorder ? 52 : 8, 10),
          decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: .24),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.primary.withValues(alpha: .12))),
          child: Row(children: [
            SizedBox(
                width: 64,
                child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SizedBox(
                        width: 48,
                        child: Icon(Icons.library_music_outlined,
                            size: 19, color: scheme.primary)))),
            Expanded(
                child: AudioColumnFields(
                    title: ui("歌名"),
                    composer: ui("作曲家"),
                    album: ui("专辑"),
                    heading: true,
                    titleColor: scheme.primary,
                    metadataColor: scheme.primary)),
            const SizedBox(width: 8),
            SizedBox(
                width: 64,
                child: Text(ui("时长"),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge!.copyWith(
                        color: scheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600))),
            const SizedBox(width: 52),
          ]),
        ));
  }
}
