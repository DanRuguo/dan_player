import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

/// A view of the transport's already determined occurrences. Tapping locates
/// the original editable row; previewing never asks transport to advance.
class QueueUpcomingPreview extends StatelessWidget {
  const QueueUpcomingPreview(
      {super.key, required this.playbackService, required this.onLocate});
  final PlaybackService playbackService;
  final ValueChanged<int> onLocate;

  Listenable get _changes => Listenable.merge([
        playbackService,
        playbackService.playlist,
        playbackService.resolvingAudioPath,
        playbackService.playMode,
        playbackService.shuffle,
        playbackService.stopAfterCurrent,
        playbackService.queueStopBoundary,
        playbackService.segmentLoop
      ]);

  Future<void> _showAll(BuildContext context) => showAppDialog<void>(
      context: context,
      builder: (context) => ListenableBuilder(
          listenable: _changes,
          builder: (context, _) {
            UiLanguageScope.watch(context);
            final items = playbackService.automaticQueuePreview(limit: 10);
            final scheme = Theme.of(context).colorScheme;
            return AlertDialog(
                key: const ValueKey('queue-upcoming-dialog'),
                scrollable: true,
                title: AppDialogTitle(ui('接下来'),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(ui('{0} 首歌曲', [items.length]),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: scheme.primary)),
                    )),
                content: SizedBox(
                    width: 480,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(ui('仅显示已确定的自动播放顺序，点击歌曲可定位到队列。'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 16),
                          if (items.isEmpty)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 24),
                                child: Text(ui('当前没有已确定的待播歌曲。'),
                                    textAlign: TextAlign.center)),
                          for (var i = 0; i < items.length; i++)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: _detailRow(context, items[i], i)),
                        ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(ui('关闭')))
                ]);
          }));

  Widget _detailRow(BuildContext context,
      ({int index, int occurrenceId, Audio audio}) item, int position) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = position == 0 ? scheme.primary : scheme.onSurface;
    return Semantics(
        label: ui('第 {0} 项 · 定位到队列', [position + 1]),
        child: Tooltip(
            message: '${item.audio.displayTitle}\n${item.audio.artist}',
            child: Material(
                color: position == 0
                    ? scheme.primaryContainer.withValues(alpha: .38)
                    : scheme.surfaceContainerLow,
                shape: AppShape.control,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                    key: ValueKey('queue-upcoming-${item.occurrenceId}'),
                    onTap: () {
                      Navigator.of(context).pop();
                      onLocate(item.occurrenceId);
                    },
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        child: Row(children: [
                          ExcludeSemantics(
                              child: SizedBox(
                                  width: 24,
                                  child: Text('${position + 1}',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(color: foreground)))),
                          const SizedBox(width: 10),
                          ExcludeSemantics(
                              child: ClipRRect(
                                  borderRadius: AppShape.smallRadius,
                                  child: SizedBox.square(
                                      dimension: 40,
                                      child: AudioArtwork(
                                          audio: item.audio,
                                          size: 40,
                                          animateFirstFrame: true,
                                          loading: const SizedBox.expand(),
                                          placeholder: ColoredBox(
                                              color: scheme
                                                  .surfaceContainerHighest,
                                              child: Icon(
                                                  Icons.music_note_rounded,
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                  size: 22)))))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                Text(item.audio.displayTitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(color: foreground)),
                                if (item.audio.artist.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(item.audio.artist,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: scheme.onSurfaceVariant)),
                                ],
                              ])),
                        ]))))));
  }

  Widget _row(BuildContext context,
      ({int index, int occurrenceId, Audio audio}) item, int position) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = position == 0 ? scheme.primary : scheme.onSurface;
    return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Semantics(
            label: ui('第 {0} 项 · 定位到队列', [position + 1]),
            child: Tooltip(
                message: '${item.audio.displayTitle}\n${item.audio.artist}',
                child: Material(
                    color: position == 0
                        ? scheme.primaryContainer.withValues(alpha: .22)
                        : scheme.surfaceContainerLow.withValues(alpha: .14),
                    shape: AppShape.control,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                        key: ValueKey('queue-upcoming-${item.occurrenceId}'),
                        onTap: () => onLocate(item.occurrenceId),
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                child: Row(children: [
                                  ExcludeSemantics(
                                      child: SizedBox(
                                          width: 18,
                                          child: Text('${position + 1}',
                                              textAlign: TextAlign.center,
                                              style: theme.textTheme.labelLarge
                                                  ?.copyWith(
                                                      color: foreground)))),
                                  const SizedBox(width: 8),
                                  ExcludeSemantics(
                                      child: ClipRRect(
                                          borderRadius: AppShape.smallRadius,
                                          child: SizedBox.square(
                                              dimension: 32,
                                              child: AudioArtwork(
                                                  audio: item.audio,
                                                  size: 32,
                                                  animateFirstFrame: true,
                                                  loading:
                                                      const SizedBox.expand(),
                                                  placeholder: ColoredBox(
                                                      color: scheme
                                                          .surfaceContainerHighest,
                                                      child: Icon(
                                                          Icons
                                                              .music_note_rounded,
                                                          color: scheme
                                                              .onSurfaceVariant,
                                                          size: 18)))))),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(item.audio.displayTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(color: foreground)),
                                        if (item.audio.artist.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(item.audio.artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                      color: scheme
                                                          .onSurfaceVariant)),
                                        ],
                                      ])),
                                ]))))))));
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
        listenable: _changes,
        builder: (context, _) {
          final items = playbackService.automaticQueuePreview(limit: 10);
          return Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(ui('接下来'),
                              style: Theme.of(context).textTheme.titleSmall),
                          if (items.length > 4)
                            TextButton(
                                key: const ValueKey('queue-upcoming-all'),
                                onPressed: () => _showAll(context),
                                child: Text(ui('查看全部 {0} 项', [items.length]))),
                        ]),
                    if (items.isEmpty)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(ui('当前没有已确定的待播歌曲。'),
                              style: Theme.of(context).textTheme.bodySmall)),
                    if (items.isNotEmpty)
                      LayoutBuilder(builder: (context, constraints) {
                        final fontSize =
                            Theme.of(context).textTheme.titleSmall?.fontSize ??
                                14;
                        final textScale =
                            MediaQuery.textScalerOf(context).scale(fontSize) /
                                fontSize;
                        // Reserve useful title/artist space beside the cover.
                        // Large text raises the column threshold without an
                        // intrinsic measurement of every track label.
                        final minimumCardWidth =
                            300 * textScale.clamp(1.0, 1.8);
                        final twoColumns = items.length > 1 &&
                            constraints.maxWidth >= minimumCardWidth * 2 + 8;
                        final cardWidth = twoColumns
                            ? (constraints.maxWidth - 8) / 2
                            : constraints.maxWidth;
                        return Wrap(spacing: 8, children: [
                          for (var i = 0; i < items.length && i < 4; i++)
                            SizedBox(
                                width: cardWidth,
                                child: _row(context, items[i], i)),
                        ]);
                      }),
                  ]));
        });
  }
}
