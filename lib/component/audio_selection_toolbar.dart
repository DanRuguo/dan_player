import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/local_lyric_batch_dialog.dart';
import 'package:dan_player/component/personal_library_dialog.dart';
import 'dart:async';

import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/playlist_destination_dialog.dart';
import 'package:dan_player/component/playlist_exchange_dialog.dart';
import 'package:dan_player/component/batch_audio_metadata_dialog.dart';
import 'package:dan_player/component/cover_repair_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

typedef SelectedAudioAction = FutureOr<void> Function(List<Audio> audios);
typedef SelectedAudioCommitAction = FutureOr<bool> Function(List<Audio> audios);

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
    this.onPlayCommitted,
    this.onAddToPlaylist,
    this.onExport,
    this.onAddToPlaylistCommitted,
    this.onExportCommitted,
    this.onCommitted,
    this.isActionCurrent,
    this.includeRangeActions = false,
    this.onSelectBetween,
    this.onSelectAbove,
    this.onSelectBelow,
  });

  final List<Audio> selected;
  final bool hasItems;
  final bool allVisibleSelected;
  final VoidCallback onToggleAll;
  final VoidCallback onInvert;
  final VoidCallback onExit;
  final int hiddenSelectionCount;
  final SelectedAudioAction? onPlay;
  final SelectedAudioCommitAction? onPlayCommitted;
  final SelectedAudioAction? onAddToPlaylist;
  final SelectedAudioAction? onExport;
  final SelectedAudioCommitAction? onAddToPlaylistCommitted, onExportCommitted;
  final VoidCallback? onCommitted;
  final bool Function()? isActionCurrent;
  final bool includeRangeActions;
  final VoidCallback? onSelectBetween, onSelectAbove, onSelectBelow;

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
                  if (isActionCurrent?.call() == false) return;
                  if (onPlayCommitted != null || onPlay == null) {
                    unawaited(_runCommittedAction(
                        context,
                        onPlayCommitted ??
                            (items) => PlayService.instance.playbackService
                                .playQueue(0, items),
                        snapshot,
                        onCommitted: onCommitted,
                        isCurrent: isActionCurrent));
                  } else if (onPlay != null) {
                    unawaited(_runSelectedAction(context, onPlay!, snapshot));
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
          onAddToPlaylistCommitted: onAddToPlaylistCommitted,
          onExportCommitted: onExportCommitted,
          onCommitted: onCommitted,
          isActionCurrent: isActionCurrent,
          includeRangeActions: includeRangeActions,
          onSelectBetween: onSelectBetween,
          onSelectAbove: onSelectAbove,
          onSelectBelow: onSelectBelow,
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
    this.onAddToPlaylistCommitted,
    this.onExportCommitted,
    this.onCommitted,
    this.isActionCurrent,
    this.includeRangeActions = false,
    this.onSelectBetween,
    this.onSelectAbove,
    this.onSelectBelow,
  });

  final List<Audio> selected;
  final SelectedAudioAction? onAddToPlaylist;
  final SelectedAudioAction? onExport;
  final VoidCallback? onInvert;
  final SelectedAudioCommitAction? onAddToPlaylistCommitted, onExportCommitted;
  final VoidCallback? onCommitted;
  final bool Function()? isActionCurrent;
  final bool includeRangeActions;
  final VoidCallback? onSelectBetween, onSelectAbove, onSelectBelow;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    bool current() =>
        context.mounted &&
        identical(context.widget, this) &&
        (isActionCurrent?.call() ?? true);
    Widget item(
            String id, String label, IconData icon, SelectedAudioAction? action,
            {SelectedAudioCommitAction? commit, bool enabled = true}) =>
        MenuItemButton(
          key: ValueKey('audio-selection-$id'),
          onPressed: !enabled || selected.isEmpty
              ? null
              : () {
                  if (!current()) return;
                  final snapshot = List<Audio>.of(selected);
                  if (commit != null) {
                    unawaited(_runCommittedAction(context, commit, snapshot,
                        onCommitted: onCommitted, isCurrent: isActionCurrent));
                  } else {
                    unawaited(_runSelectedAction(context, action!, snapshot));
                  }
                },
          leadingIcon: Icon(icon),
          child: _selectionMenuLabel(context, label),
        );

    return AppMenuAnchor(
      crossAxisUnconstrained: false,
      reservedPadding: _selectionMenuPadding(context),
      menuChildren: [
        item('shuffle', '随机播放所选', Symbols.shuffle, null,
            commit: (audios) => PlayService.instance.playbackService
                .shuffleAndPlayQueue(audios)),
        item('next', '下一批播放', Symbols.playlist_play, null,
            commit: (audios) => _enqueue(context, audios, next: true)),
        item('append', '加入播放队尾', Symbols.queue_music, null,
            commit: (audios) => _enqueue(context, audios, next: false)),
        const Divider(),
        item('playlist', '加入歌单…', Symbols.playlist_add, onAddToPlaylist,
            commit: onAddToPlaylistCommitted ??
                (onAddToPlaylist == null
                    ? (audios) => showAddAudiosToPlaylistDialog(context, audios)
                    : null)),
        item('export', '导出所选为 M3U8…', Symbols.file_export, onExport,
            commit: onExportCommitted ??
                (onExport == null
                    ? (audios) => exportM3uPlaylist(context, audios)
                    : null)),
        item('copy-info', '复制曲目信息', Symbols.content_copy, null,
            commit: (audios) async {
          await Clipboard.setData(
              ClipboardData(text: selectedTrackInfo(audios)));
          if (context.mounted) {
            _notice(context, ui('已复制 {0} 首歌曲的信息', [audios.length]));
          }
          return true;
        }),
        item('copy-paths', '复制本地文件路径', Symbols.folder_copy, null,
            commit: (audios) async {
          final paths = selectedLocalPaths(audios);
          await Clipboard.setData(ClipboardData(text: paths.join('\r\n')));
          if (context.mounted) {
            _notice(context, ui('已复制 {0} 个本地文件路径', [paths.length]));
          }
          return true;
        }, enabled: selected.any((audio) => !audio.isOnline)),
        item('personal-tags', '个人评分与标签', Symbols.star, null,
            commit: (audios) => showPersonalTrackEditor(context, audios)),
        item('local-lyrics', '批量关联本地歌词', Symbols.lyrics, null,
            commit: (audios) => showLocalLyricBatch(context, audios)),
        item('edit-tags', '批量编辑标签', Symbols.edit_note, null,
            commit: (audios) => showBatchAudioMetadataDialog(context, audios)),
        item('reread-covers', '重新读取封面', Symbols.image_search, null,
            commit: (audios) => showCoverRepairDialog(context, audios)),
        if (includeRangeActions) ...[
          const Divider(),
          ...selectionRangeMenuItems(context,
              onBetween: onSelectBetween,
              onAbove: onSelectAbove,
              onBelow: onSelectBelow,
              isCurrent: current),
        ],
        if (onInvert != null) ...[
          const Divider(),
          MenuItemButton(
            key: const ValueKey('audio-selection-invert'),
            onPressed: () {
              if (current()) onInvert!();
            },
            leadingIcon: const Icon(Symbols.select_check_box),
            child: _selectionMenuLabel(context, '反选当前列表'),
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

Future<void> _runCommittedAction(
    BuildContext context, SelectedAudioCommitAction action, List<Audio> audios,
    {VoidCallback? onCommitted, bool Function()? isCurrent}) async {
  try {
    final committed = await action(audios);
    if (committed && context.mounted && (isCurrent?.call() ?? true)) {
      onCommitted?.call();
    }
  } catch (_) {
    if (context.mounted) {
      _notice(context, ui('处理所选歌曲失败，请重试'), kind: AppNoticeKind.error);
    }
  }
}

bool _enqueue(BuildContext context, List<Audio> audios, {required bool next}) {
  final added =
      PlayService.instance.playbackService.enqueueAudios(audios, next: next);
  _notice(context,
      added ? ui('已加入播放队列：{0} 首', [audios.length]) : ui('歌曲正在加载，请稍后重试'),
      kind: added ? AppNoticeKind.success : AppNoticeKind.warning);
  return added;
}

List<Widget> selectionRangeMenuItems(BuildContext context,
        {VoidCallback? onBetween,
        VoidCallback? onAbove,
        VoidCallback? onBelow,
        bool autofocusFirst = false,
        bool Function()? isCurrent}) =>
    [
      for (final entry in [
        ('between', '选中两项之间（含两端）', Symbols.select_all, onBetween),
        ('above', '选中此项及上方全部', Symbols.arrow_upward, onAbove),
        ('below', '选中此项及下方全部', Symbols.arrow_downward, onBelow),
      ])
        MenuItemButton(
            key: ValueKey('multi-selection-range-${entry.$1}'),
            autofocus: autofocusFirst &&
                entry.$1 ==
                    (onBetween != null
                        ? 'between'
                        : onAbove != null
                            ? 'above'
                            : 'below'),
            onPressed: entry.$4 == null
                ? null
                : () {
                    if (isCurrent?.call() ?? true) entry.$4!();
                  },
            leadingIcon: Icon(entry.$3),
            child: _selectionMenuLabel(context, entry.$2)),
    ];

EdgeInsets _selectionMenuPadding(BuildContext context) {
  final media = MediaQuery.of(context);
  return media.padding + media.viewInsets + const EdgeInsets.all(8);
}

Widget _selectionMenuLabel(BuildContext context, String label) =>
    ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth:
                (MediaQuery.sizeOf(context).width - 96).clamp(48.0, 216.0)),
        child: Text(ui(label), softWrap: true));

class SelectionRangeMenuButton extends StatelessWidget {
  const SelectionRangeMenuButton(
      {super.key, this.onBetween, this.onAbove, this.onBelow});
  final VoidCallback? onBetween, onAbove, onBelow;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AppMenuAnchor(
        crossAxisUnconstrained: false,
        reservedPadding: _selectionMenuPadding(context),
        menuChildren: selectionRangeMenuItems(context,
            autofocusFirst: true,
            onBetween: onBetween,
            onAbove: onAbove,
            onBelow: onBelow,
            isCurrent: () =>
                context.mounted && identical(context.widget, this)),
        builder: (context, controller, _) => FilledButton.tonal(
            key: const ValueKey('multi-selection-range-menu'),
            onPressed: onBetween == null && onAbove == null && onBelow == null
                ? null
                : () =>
                    controller.isOpen ? controller.close() : controller.open(),
            style: appToolbarControlStyle(context, primary: true, tonal: true),
            child:
                AppToolbarLabel(label: ui('范围选择'), icon: Symbols.select_all)));
  }
}

void _notice(BuildContext context, String text,
        {AppNoticeKind kind = AppNoticeKind.success}) =>
    showAppNotice(text, context: context, kind: kind);
