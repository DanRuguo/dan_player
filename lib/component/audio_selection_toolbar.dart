import 'dart:async';

import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/playlist_destination_dialog.dart';
import 'package:dan_player/component/playlist_exchange_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

typedef SelectedAudioAction = FutureOr<void> Function(List<Audio> audios);

/// [selected] is already ordered by the visible list. Playlist callers may
/// supply repeated occurrences; this component deliberately does not dedupe.
class AudioSelectionToolbar extends StatelessWidget {
  const AudioSelectionToolbar({
    super.key,
    required this.selected,
    required this.hasItems,
    required this.allVisibleSelected,
    required this.onToggleAll,
    required this.onInvert,
    required this.onExit,
    this.hiddenSelectionCount = 0,
    this.onPlay,
    this.onAddToPlaylist,
    this.onExport,
  });

  final List<Audio> selected;
  final bool hasItems;
  final bool allVisibleSelected;
  final VoidCallback onToggleAll;
  final VoidCallback onInvert;
  final VoidCallback onExit;
  final int hiddenSelectionCount;
  final SelectedAudioAction? onPlay;
  final SelectedAudioAction? onAddToPlaylist;
  final SelectedAudioAction? onExport;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Wrap(
      key: const ValueKey('audio-selection-toolbar'),
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Tooltip(
            message: hiddenSelectionCount > 0
                ? ui('另有 {0} 首被筛选隐藏；操作仅作用于当前可见所选', [hiddenSelectionCount])
                : ui('按当前显示顺序处理所选歌曲'),
            child: Text(
                hiddenSelectionCount > 0
                    ? ui('当前已选 {0} 首 · 隐藏 {1} 首',
                        [selected.length, hiddenSelectionCount])
                    : ui('已选 {0} 首', [selected.length]),
                key: const ValueKey('audio-selection-count'),
                style: Theme.of(context).textTheme.labelLarge),
          ),
        ),
        FilledButton(
          key: const ValueKey('audio-selection-play'),
          onPressed: selected.isEmpty
              ? null
              : () {
                  final snapshot = List<Audio>.of(selected);
                  if (onPlay != null) {
                    unawaited(_runSelectedAction(context, onPlay!, snapshot));
                  } else {
                    PlayService.instance.playbackService.play(0, snapshot);
                  }
                },
          style: appToolbarControlStyle(context, primary: true),
          child: AppToolbarLabel(label: ui('播放所选'), icon: Symbols.play_arrow),
        ),
        AudioSelectionMenu(
          selected: selected,
          onAddToPlaylist: onAddToPlaylist,
          onExport: onExport,
          onInvert: hasItems ? onInvert : null,
        ),
        IconButton.filledTonal(
          key: const ValueKey('audio-selection-toggle-all'),
          tooltip: allVisibleSelected ? ui('取消全选') : ui('全选'),
          onPressed: hasItems ? onToggleAll : null,
          style: appToolbarControlStyle(context,
              primary: true, tonal: true, iconOnly: true),
          icon:
              Icon(allVisibleSelected ? Symbols.deselect : Symbols.select_all),
        ),
        IconButton(
          key: const ValueKey('audio-selection-exit'),
          tooltip: ui('退出多选'),
          onPressed: onExit,
          style: appToolbarControlStyle(context, iconOnly: true),
          icon: const Icon(Symbols.close),
        ),
      ],
    );
  }
}

/// Compact extra actions can also be embedded in occurrence-based playlists.
class AudioSelectionMenu extends StatelessWidget {
  const AudioSelectionMenu({
    super.key,
    required this.selected,
    this.onAddToPlaylist,
    this.onExport,
    this.onInvert,
  });

  final List<Audio> selected;
  final SelectedAudioAction? onAddToPlaylist;
  final SelectedAudioAction? onExport;
  final VoidCallback? onInvert;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    Widget item(
            String id, String label, IconData icon, SelectedAudioAction action,
            {bool enabled = true}) =>
        MenuItemButton(
          key: ValueKey('audio-selection-$id'),
          onPressed: !enabled || selected.isEmpty
              ? null
              : () => unawaited(_runSelectedAction(
                  context, action, List<Audio>.of(selected))),
          leadingIcon: Icon(icon),
          child: Text(ui(label)),
        );

    return MenuAnchor(
      menuChildren: [
        item(
            'shuffle',
            '随机播放所选',
            Symbols.shuffle,
            (audios) =>
                PlayService.instance.playbackService.shuffleAndPlay(audios)),
        item('next', '下一批播放', Symbols.playlist_play,
            (audios) => _enqueue(context, audios, next: true)),
        item('append', '加入播放队尾', Symbols.queue_music,
            (audios) => _enqueue(context, audios, next: false)),
        const Divider(),
        item(
            'playlist',
            '加入歌单…',
            Symbols.playlist_add,
            onAddToPlaylist ??
                (audios) => showAddAudiosToPlaylistDialog(context, audios)),
        item('export', '导出所选为 M3U8…', Symbols.file_export,
            onExport ?? (audios) => exportM3uPlaylist(context, audios)),
        item('copy-info', '复制曲目信息', Symbols.content_copy, (audios) async {
          await Clipboard.setData(
              ClipboardData(text: selectedTrackInfo(audios)));
          if (context.mounted) {
            _notice(context, ui('已复制 {0} 首歌曲的信息', [audios.length]));
          }
        }),
        item('copy-paths', '复制本地文件路径', Symbols.folder_copy, (audios) async {
          final paths = selectedLocalPaths(audios);
          await Clipboard.setData(ClipboardData(text: paths.join('\r\n')));
          if (context.mounted) {
            _notice(context, ui('已复制 {0} 个本地文件路径', [paths.length]));
          }
        }, enabled: selected.any((audio) => !audio.isOnline)),
        if (onInvert != null) ...[
          const Divider(),
          MenuItemButton(
            key: const ValueKey('audio-selection-invert'),
            onPressed: onInvert,
            leadingIcon: const Icon(Symbols.select_check_box),
            child: Text(ui('反选当前列表')),
          ),
        ],
      ],
      builder: (context, controller, _) => OutlinedButton(
        key: const ValueKey('audio-selection-more'),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        style: appToolbarControlStyle(context),
        child: AppToolbarLabel(label: ui('更多'), icon: Symbols.more_horiz),
      ),
    );
  }
}

String selectedTrackInfo(Iterable<Audio> audios) => audios
    .map((audio) => [audio.title, audio.artist]
        .where((part) => part.trim().isNotEmpty)
        .join(' — '))
    .join('\r\n');

List<String> selectedLocalPaths(Iterable<Audio> audios) => [
      for (final audio in audios)
        if (!audio.isOnline) audio.localFilePath
    ];

Future<void> _runSelectedAction(BuildContext context,
    SelectedAudioAction action, List<Audio> audios) async {
  try {
    await action(audios);
  } catch (_) {
    if (context.mounted) {
      _notice(context, ui('处理所选歌曲失败，请重试'), kind: AppNoticeKind.error);
    }
  }
}

void _enqueue(BuildContext context, List<Audio> audios, {required bool next}) {
  final added =
      PlayService.instance.playbackService.enqueueAudios(audios, next: next);
  _notice(context,
      added ? ui('已加入播放队列：{0} 首', [audios.length]) : ui('歌曲正在加载，请稍后重试'),
      kind: added ? AppNoticeKind.success : AppNoticeKind.warning);
}

void _notice(BuildContext context, String text,
        {AppNoticeKind kind = AppNoticeKind.success}) =>
    showTextOnSnackBar(text, context: context, kind: kind);
