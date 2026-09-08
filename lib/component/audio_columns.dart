import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/personal_library.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Only library-style hosts opt in. Playlist relationship rows stay unchanged.
class AudioColumnsScope extends InheritedWidget {
  const AudioColumnsScope(
      {super.key,
      required this.enabled,
      this.configuration,
      required super.child});
  final bool enabled;
  final Map<String, dynamic>? configuration;
  static Map<String, dynamic>? configOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AudioColumnsScope>()
      ?.configuration;
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
      enabled != oldWidget.enabled || configuration != oldWidget.configuration;
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
      this.audio,
      this.heading = false});
  final String title, composer, album;
  final Audio? audio;
  final Color? titleColor, metadataColor;
  final bool heading;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
      valueListenable: PersonalLibrary.changes,
      builder: (context, _, __) => _buildFields(context));

  Widget _buildFields(BuildContext context) {
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
    final config = AudioColumnsScope.configOf(context);
    if (config?['columns'] is List) {
      final widths =
          config?['widths'] is Map ? config!['widths'] as Map : const {};
      final personal =
          audio == null ? null : PersonalLibrary.latest[audio!.stableTrackId];
      final values = <String, String>{
        'artist': audio?.artist ?? composer,
        'album': album,
        'track': audio?.track.toString() ?? '',
        'tags': personal?.tags.join(', ') ?? '',
        'rating': personal?.rating == null ? '—' : '★' * personal!.rating!
      };
      const labels = {
        'artist': '艺术家',
        'album': '专辑',
        'track': '轨号',
        'tags': '个人标签',
        'rating': '个人评分'
      };
      return Row(children: [
        Expanded(flex: 280, child: field(title, titleColor)),
        for (final key in (config!['columns'] as List)
            .where((k) => labels.containsKey(k))) ...[
          gap(),
          Expanded(
              flex: (widths[key] is num && (widths[key] as num).isFinite
                  ? (widths[key] as num).round().clamp(80, 320)
                  : 160),
              child: field(
                  heading ? ui(labels[key]!) : values[key]!, metadataColor))
        ]
      ]);
    }
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
