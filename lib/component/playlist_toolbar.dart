import 'dart:math' as math;

import 'package:dan_player/component/app_playback_mode_controls.dart';
import 'package:dan_player/component/app_action_icon.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/audio_sort_options.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

enum PlaylistSortMode {
  // Keep these first eight names/order: they are persisted by older releases.
  custom(null, null),
  nameAscending(AudioSortField.name, SortDirection.ascending),
  nameDescending(AudioSortField.name, SortDirection.descending),
  artist(AudioSortField.artist, SortDirection.ascending),
  album(AudioSortField.album, SortDirection.ascending),
  newest(AudioSortField.added, SortDirection.descending),
  modified(AudioSortField.modified, SortDirection.descending),
  songCount(null, SortDirection.descending),
  artistDescending(AudioSortField.artist, SortDirection.descending),
  albumDescending(AudioSortField.album, SortDirection.descending),
  oldest(AudioSortField.added, SortDirection.ascending),
  modifiedAscending(AudioSortField.modified, SortDirection.ascending),
  songCountAscending(null, SortDirection.ascending),
  composer(AudioSortField.composer, SortDirection.ascending),
  composerDescending(AudioSortField.composer, SortDirection.descending),
  duration(AudioSortField.duration, SortDirection.ascending),
  durationDescending(AudioSortField.duration, SortDirection.descending),
  track(AudioSortField.track, SortDirection.ascending),
  trackDescending(AudioSortField.track, SortDirection.descending),
  albumArtist(AudioSortField.albumArtist, SortDirection.ascending),
  albumArtistDescending(AudioSortField.albumArtist, SortDirection.descending),
  bitrate(AudioSortField.bitrate, SortDirection.ascending),
  bitrateDescending(AudioSortField.bitrate, SortDirection.descending),
  sampleRate(AudioSortField.sampleRate, SortDirection.ascending),
  sampleRateDescending(AudioSortField.sampleRate, SortDirection.descending),
  fileSize(AudioSortField.fileSize, SortDirection.ascending),
  fileSizeDescending(AudioSortField.fileSize, SortDirection.descending),
  format(AudioSortField.format, SortDirection.ascending),
  formatDescending(AudioSortField.format, SortDirection.descending),
  language(AudioSortField.language, SortDirection.ascending),
  languageDescending(AudioSortField.language, SortDirection.descending),
  source(AudioSortField.source, SortDirection.ascending),
  sourceDescending(AudioSortField.source, SortDirection.descending);

  const PlaylistSortMode(this.audioField, this.direction);

  final AudioSortField? audioField;
  final SortDirection? direction;

  String get methodLabel =>
      audioField?.label ?? (this == custom ? '自定义' : '歌曲数量');

  PlaylistSortMode get baseMode {
    if (this == custom) return custom;
    if (audioField == null) return songCount;
    return values.firstWhere((mode) => mode.audioField == audioField);
  }

  PlaylistSortMode withDirection(SortDirection direction) {
    if (this == custom) return custom;
    return values.firstWhere(
        (mode) => mode.audioField == audioField && mode.direction == direction);
  }

  bool get isSongOnly =>
      audioField != null &&
      audioField != AudioSortField.name &&
      audioField != AudioSortField.added &&
      audioField != AudioSortField.modified;

  String get label => switch (this) {
        custom => '自定义',
        nameAscending => '名称升序',
        nameDescending => '名称降序',
        artist => '艺术家',
        album => '专辑',
        newest => '最新添加',
        modified => '最近修改',
        songCount => '歌曲数量',
        oldest => '最早添加',
        modifiedAscending => '最早修改',
        songCountAscending => '歌曲数量升序',
        _ => '$methodLabel${direction!.label}',
      };
}

enum _PlaylistToolbarAction {
  create,
  addSongs,
  select,
  rename,
  editSongs,
  changeCover,
  resetCover,
  albums,
  help,
  importM3u,
  exportM3u,
  importCue,
  smartPlaylists,
  trash,
  presentation,
}

/// Compact, descriptor-only playlist actions. No playback/library singleton is
/// initialized here; the owner supplies actions and the current editing policy.
///
/// Place in a bounded-width header region. Controls wrap at narrow widths while
/// keeping touch targets at least 44 logical pixels; text is never down-scaled.
class PlaylistToolbar extends StatefulWidget {
  const PlaylistToolbar({
    super.key,
    required this.isRoot,
    this.selecting = false,
    this.selectedCount = 0,
    required this.hasItems,
    required this.canPlay,
    this.editingEnabled = true,
    this.sortMode = PlaylistSortMode.custom,
    this.gridView = false,
    this.view,
    this.onViewChanged,
    required this.onCreate,
    this.onAddSongs,
    required this.onStartSelection,
    required this.onEndSelection,
    required this.onSelectAll,
    required this.onRemoveSelected,
    required this.onSortChanged,
    this.onToggleView,
    this.onRename,
    this.onEditSongs,
    this.onChangeCover,
    this.onResetCover,
    this.onOpenAlbums,
    this.albumCount = 0,
    this.onHelp,
    this.onImportM3u,
    this.onExportM3u,
    this.onImportCue,
    this.onOpenSmartPlaylists,
    this.onTrash,
    this.onPresentation,
    this.selectionTools,
    this.playbackService,
    this.alignment = WrapAlignment.end,
  })  : assert(selectedCount >= 0),
        assert(albumCount >= 0);

  final bool isRoot;
  final bool selecting;
  final int selectedCount;
  final bool hasItems;
  final bool canPlay;
  final bool editingEnabled;
  final PlaylistSortMode sortMode;
  final bool gridView;
  final PlaylistViewMode? view;
  final ValueChanged<PlaylistViewMode>? onViewChanged;
  final VoidCallback onCreate;
  final VoidCallback? onAddSongs;
  final VoidCallback onStartSelection;
  final VoidCallback onEndSelection;
  final VoidCallback onSelectAll;
  final VoidCallback onRemoveSelected;
  final ValueChanged<PlaylistSortMode> onSortChanged;
  final VoidCallback? onToggleView;
  final VoidCallback? onRename;
  final VoidCallback? onEditSongs;
  final VoidCallback? onChangeCover;
  final VoidCallback? onResetCover;
  final VoidCallback? onOpenAlbums;
  final int albumCount;
  final VoidCallback? onHelp;
  final VoidCallback? onImportM3u;
  final VoidCallback? onExportM3u;
  final VoidCallback? onImportCue;
  final VoidCallback? onOpenSmartPlaylists;
  final VoidCallback? onTrash, onPresentation;
  final Widget? selectionTools;
  final PlaybackService? playbackService;
  final WrapAlignment alignment;

  @override
  State<PlaylistToolbar> createState() => _PlaylistToolbarState();
}

class _PlaylistToolbarState extends State<PlaylistToolbar>
    with WidgetsBindingObserver {
  int _modeEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(PlaylistToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isRoot != widget.isRoot ||
        oldWidget.selecting != widget.selecting) {
      _modeEpoch++;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _reduceMotion {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        features.disableAnimations ||
        features.reduceMotion ||
        !TickerMode.valuesOf(context).enabled;
  }

  List<_ToolbarMenuItem<_PlaylistToolbarAction>?> _moreItems() => [
        if (widget.onTrash != null)
          _ToolbarMenuItem(
              value: _PlaylistToolbarAction.trash,
              label: ui('歌单回收站'),
              icon: Icons.restore_from_trash,
              onSelected: widget.onTrash),
        if (widget.onPresentation != null)
          _ToolbarMenuItem(
              value: _PlaylistToolbarAction.presentation,
              label: ui('此歌单的视图与列'),
              icon: Icons.view_column_outlined,
              onSelected: widget.onPresentation),
        if (widget.onImportM3u != null)
          _ToolbarMenuItem(
              value: _PlaylistToolbarAction.importM3u,
              key: const ValueKey('playlist-import-m3u'),
              label: ui('导入 M3U8 歌单'),
              icon: Icons.file_open_outlined,
              onSelected: widget.editingEnabled ? widget.onImportM3u : null),
        if (widget.onImportCue != null)
          _ToolbarMenuItem(
              value: _PlaylistToolbarAction.importCue,
              key: const ValueKey('playlist-import-cue'),
              label: ui('导入 CUE 分轨'),
              icon: Icons.album_outlined,
              onSelected: widget.editingEnabled ? widget.onImportCue : null),
        if (widget.onOpenSmartPlaylists != null)
          _ToolbarMenuItem(
              value: _PlaylistToolbarAction.smartPlaylists,
              key: const ValueKey('playlist-smart-playlists'),
              label: ui('智能歌单'),
              icon: Icons.auto_awesome_outlined,
              onSelected: widget.onOpenSmartPlaylists),
        if (widget.onExportM3u != null)
          _ToolbarMenuItem(
              value: _PlaylistToolbarAction.exportM3u,
              key: const ValueKey('playlist-export-m3u'),
              label: ui('导出 M3U8 歌单'),
              icon: Icons.file_download_outlined,
              onSelected: widget.canPlay ? widget.onExportM3u : null),
        _ToolbarMenuItem(
          value: _PlaylistToolbarAction.select,
          key: const ValueKey('playlist-start-selection'),
          label: ui("多选"),
          icon: Icons.checklist,
          onSelected: widget.editingEnabled && widget.hasItems
              ? widget.onStartSelection
              : null,
        ),
        if (!widget.isRoot &&
            (widget.onRename != null ||
                widget.onEditSongs != null ||
                widget.onChangeCover != null ||
                widget.onResetCover != null)) ...[
          null,
          if (widget.onRename != null)
            _ToolbarMenuItem(
              value: _PlaylistToolbarAction.rename,
              label: ui("重命名"),
              icon: Icons.edit_outlined,
              onSelected: widget.editingEnabled ? widget.onRename : null,
            ),
          if (widget.onEditSongs != null)
            _ToolbarMenuItem(
              value: _PlaylistToolbarAction.editSongs,
              label: ui("更改所选歌曲"),
              icon: Icons.playlist_add_check,
              onSelected: widget.editingEnabled ? widget.onEditSongs : null,
            ),
          if (widget.onChangeCover != null)
            _ToolbarMenuItem(
              value: _PlaylistToolbarAction.changeCover,
              label: ui("更改歌单封面"),
              icon: Icons.image_outlined,
              onSelected: widget.editingEnabled ? widget.onChangeCover : null,
            ),
          if (widget.onResetCover != null)
            _ToolbarMenuItem(
              value: _PlaylistToolbarAction.resetCover,
              label: ui("恢复默认封面"),
              icon: Icons.hide_image_outlined,
              onSelected: widget.editingEnabled ? widget.onResetCover : null,
            ),
        ],
        if (widget.isRoot && widget.onOpenAlbums != null) ...[
          null,
          _ToolbarMenuItem(
            value: _PlaylistToolbarAction.albums,
            key: const ValueKey('playlist-open-albums'),
            label: ui("浏览全部专辑 · {0}", [widget.albumCount]),
            icon: Icons.album_outlined,
            onSelected: widget.onOpenAlbums,
          ),
        ],
        if (widget.onHelp != null) ...[
          null,
          _ToolbarMenuItem(
            value: _PlaylistToolbarAction.help,
            key: const ValueKey('playlist-help'),
            label: ui("操作说明"),
            icon: Icons.help_outline,
            onSelected: widget.onHelp,
          ),
        ],
      ];

  List<Widget> _normalActions(bool reduced, double maxWidth) {
    final epoch = _modeEpoch;
    bool isCurrentMode() => mounted && !widget.selecting && _modeEpoch == epoch;
    return [
      if (!widget.isRoot)
        AppPlaybackModeControls(playbackService: widget.playbackService),
      if (widget.isRoot)
        _ToolbarActionButton(
          key: const ValueKey('playlist-create'),
          label: ui("新建歌单"),
          icon: Icons.add,
          primary: true,
          reduced: reduced,
          maxWidth: maxWidth,
          onPressed: widget.editingEnabled ? widget.onCreate : null,
        )
      else ...[
        _ToolbarMenu<_PlaylistToolbarAction>(
          key: const ValueKey('playlist-add-menu'),
          label: ui("添加"),
          tooltip: ui("添加歌曲或子歌单"),
          icon: Icons.add,
          reduced: reduced,
          maxWidth: maxWidth,
          isCurrentMode: isCurrentMode,
          enabled: widget.editingEnabled,
          items: [
            if (widget.onAddSongs != null)
              _ToolbarMenuItem(
                value: _PlaylistToolbarAction.addSongs,
                key: const ValueKey('playlist-add-songs'),
                label: ui("添加歌曲"),
                icon: Icons.music_note_outlined,
                onSelected: widget.editingEnabled ? widget.onAddSongs : null,
              ),
            _ToolbarMenuItem(
              value: _PlaylistToolbarAction.create,
              key: const ValueKey('playlist-create'),
              label: ui("新建子歌单"),
              icon: Icons.create_new_folder_outlined,
              onSelected: widget.editingEnabled ? widget.onCreate : null,
            ),
          ],
        ),
      ],
      AppSortButton<PlaylistSortMode>(
        key: const ValueKey('playlist-sort'),
        value: widget.sortMode.baseMode,
        direction: widget.sortMode.direction,
        maxWidth: maxWidth,
        scopeId: (widget.isRoot, epoch),
        isCurrent: isCurrentMode,
        enabled: widget.editingEnabled && widget.hasItems,
        options: [
          for (final mode in PlaylistSortMode.values)
            if (mode == mode.baseMode && (!widget.isRoot || !mode.isSongOnly))
              AppSortOption(
                value: mode,
                key: ValueKey('playlist-sort-${mode.name}'),
                label: mode.methodLabel,
                icon: _sortIcon(mode),
                group: mode == PlaylistSortMode.custom
                    ? ui("原始顺序")
                    : mode.audioField?.group ?? ui("歌单信息"),
              ),
        ],
        onChanged: (mode) => widget.onSortChanged(mode ==
                PlaylistSortMode.custom
            ? mode
            : mode.withDirection(widget.sortMode.direction ?? mode.direction!)),
        onDirectionChanged: (direction) =>
            widget.onSortChanged(widget.sortMode.withDirection(direction)),
        helpText: widget.sortMode == PlaylistSortMode.custom
            ? ui("自定义顺序支持歌曲与子歌单混排。其他排序不覆盖自定义顺序。")
            : [
                audioSortMissingValueNote,
                if (widget.sortMode.isSongOnly) ui("子歌单没有歌曲专属字段，保留原次序并排在最后。"),
                if (widget.sortMode.audioField?.note != null)
                  widget.sortMode.audioField!.note!,
              ].join('\n'),
      ),
      if (widget.onViewChanged != null)
        AppSegmentedControl<PlaylistViewMode>(
          key: const ValueKey('playlist-view-selector'),
          semanticLabel: ui('歌单视图'),
          showLabels: widget.isRoot,
          value: widget.view ?? PlaylistViewMode.list,
          maxWidth: maxWidth,
          options: [
            AppSegmentOption(
                value: PlaylistViewMode.list,
                label: ui('列表'),
                icon: Icons.view_list_outlined,
                key: const ValueKey('playlist-view-list')),
            AppSegmentOption(
                value: PlaylistViewMode.grid,
                label: ui('方形网格'),
                icon: Icons.grid_view_outlined,
                key: const ValueKey('playlist-view-grid')),
            AppSegmentOption(
                value: PlaylistViewMode.circular,
                label: ui('圆形封面'),
                icon: Icons.album_outlined,
                key: const ValueKey('playlist-view-circular')),
          ],
          onChanged: (value) {
            if (isCurrentMode()) widget.onViewChanged?.call(value);
          },
        )
      else
        IconButton(
          key: const ValueKey('playlist-view-toggle'),
          tooltip: widget.gridView ? ui("切换列表视图") : ui("切换网格视图"),
          onPressed: widget.onToggleView,
          style: _controlStyle(context, reduced: reduced, iconOnly: true),
          icon: reduced
              ? Icon(widget.gridView
                  ? Icons.view_list_outlined
                  : Icons.grid_view_outlined)
              : AnimatedSwitcher(
                  duration: AppMotion.quick,
                  switchInCurve: AppMotion.standardCurve,
                  switchOutCurve: AppMotion.standardCurve,
                  child: Icon(
                    widget.gridView
                        ? Icons.view_list_outlined
                        : Icons.grid_view_outlined,
                    key: ValueKey(widget.gridView),
                  ),
                ),
        ),
      _ToolbarMenu<_PlaylistToolbarAction>(
        key: const ValueKey('playlist-current-settings'),
        tooltip: ui("更多"),
        icon: AppActionGlyph.moreHorizontal.icon,
        reduced: reduced,
        maxWidth: maxWidth,
        isCurrentMode: isCurrentMode,
        items: _moreItems(),
      ),
    ];
  }

  List<Widget> _selectionActions(bool reduced, double maxWidth) => [
        if (widget.selectionTools != null) widget.selectionTools!,
        _ToolbarActionButton(
          key: const ValueKey('playlist-remove-selected'),
          label: ui("移除所选（{0}）", [widget.selectedCount]),
          icon: Icons.delete_outline,
          primary: true,
          destructive: true,
          reduced: reduced,
          maxWidth: maxWidth,
          onPressed: widget.editingEnabled && widget.selectedCount > 0
              ? widget.onRemoveSelected
              : null,
        ),
        _ToolbarActionButton(
          key: const ValueKey('playlist-select-all'),
          label: ui("全选当前层"),
          icon: Icons.select_all,
          reduced: reduced,
          maxWidth: maxWidth,
          onPressed: widget.editingEnabled && widget.hasItems
              ? widget.onSelectAll
              : null,
        ),
        _ToolbarActionButton(
          key: const ValueKey('playlist-end-selection'),
          label: ui("退出多选"),
          icon: Icons.close,
          reduced: reduced,
          maxWidth: maxWidth,
          onPressed: widget.onEndSelection,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final reduced = _reduceMotion;
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final modeKey = ValueKey((
          'playlist-toolbar-mode',
          widget.selecting
              ? 'selection'
              : widget.isRoot
                  ? 'root'
                  : 'detail',
        ));
        final content = Wrap(
          key: modeKey,
          alignment: widget.alignment,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: widget.selecting
              ? _selectionActions(reduced, maxWidth)
              : _normalActions(reduced, maxWidth),
        );
        // Removing the switcher on a live reduced-motion change also finishes
        // an already-running transition; outgoing controls never stay faded.
        if (reduced) return content;
        return AnimatedSwitcher(
          key: const ValueKey('playlist-toolbar-switcher'),
          duration: AppMotion.standard,
          switchInCurve: AppMotion.standardCurve,
          switchOutCurve: AppMotion.standardCurve,
          layoutBuilder: (current, previous) => Stack(
            alignment: widget.alignment == WrapAlignment.start
                ? AlignmentDirectional.centerStart
                : AlignmentDirectional.centerEnd,
            children: [...previous, if (current != null) current],
          ),
          transitionBuilder: (child, animation) {
            final outgoing = child.key != modeKey;
            return ExcludeFocus(
              excluding: outgoing,
              child: IgnorePointer(
                ignoring: outgoing,
                child: ExcludeSemantics(
                  excluding: outgoing,
                  child: FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: animation.drive(Tween(
                        begin: const Offset(0, .05),
                        end: Offset.zero,
                      )),
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          },
          child: content,
        );
      },
    );
  }
}

IconData _sortIcon(PlaylistSortMode mode) => mode.audioField != null
    ? audioSortIcon(mode.audioField!)
    : mode == PlaylistSortMode.custom
        ? AppActionGlyph.reorder.icon
        : Icons.queue_music;

ButtonStyle _controlStyle(BuildContext context,
        {required bool reduced,
        bool primary = false,
        bool destructive = false,
        bool iconOnly = false}) =>
    appToolbarControlStyle(context,
        reduced: reduced,
        primary: primary,
        destructive: destructive,
        iconOnly: iconOnly);

class _ToolbarActionButton extends StatelessWidget {
  const _ToolbarActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.reduced,
    required this.maxWidth,
    this.onPressed,
    this.primary = false,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final bool reduced;
  final double maxWidth;
  final VoidCallback? onPressed;
  final bool primary;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final style = _controlStyle(context,
        reduced: reduced, primary: primary, destructive: destructive);
    final child = _ButtonLabel(label: label, icon: icon);
    return Tooltip(
      message: label,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: primary
            ? FilledButton(onPressed: onPressed, style: style, child: child)
            : OutlinedButton(onPressed: onPressed, style: style, child: child),
      ),
    );
  }
}

class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel({required this.label, required this.icon, this.trailing});

  final String label;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AppToolbarLabel(label: label, icon: icon, trailing: trailing);
  }
}

class _ToolbarMenuItem<T> {
  const _ToolbarMenuItem({
    required this.value,
    required this.label,
    required this.icon,
    this.key,
    this.checked = false,
    this.onSelected,
  });

  final T value;
  final String label;
  final IconData icon;
  final Key? key;
  final bool checked;
  final VoidCallback? onSelected;
}

class _ToolbarMenu<T> extends StatefulWidget {
  const _ToolbarMenu({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.reduced,
    required this.maxWidth,
    required this.items,
    required this.isCurrentMode,
    this.label,
    this.enabled = true,
  });

  final String tooltip;
  final String? label;
  final IconData icon;
  final bool reduced;
  final double maxWidth;
  final bool enabled;
  final List<_ToolbarMenuItem<T>?> items;
  final bool Function() isCurrentMode;

  @override
  State<_ToolbarMenu<T>> createState() => _ToolbarMenuState<T>();
}

class _ToolbarMenuState<T> extends State<_ToolbarMenu<T>> {
  final _anchor = GlobalKey();
  bool _open = false;
  RelativeRect? _lastPosition;

  RelativeRect _position(BuildContext _, BoxConstraints constraints) {
    if (!mounted) return _lastPosition ?? RelativeRect.fill;
    final button = _anchor.currentContext?.findRenderObject();
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (button is! RenderBox ||
        overlay is! RenderBox ||
        !button.attached ||
        !overlay.attached) {
      return _lastPosition ?? RelativeRect.fill;
    }
    final bottomLeft = button.localToGlobal(Offset(0, button.size.height + 6),
        ancestor: overlay);
    _lastPosition = RelativeRect.fromRect(
      Rect.fromLTWH(bottomLeft.dx, bottomLeft.dy, button.size.width, 0),
      Offset.zero & overlay.size,
    );
    return _lastPosition!;
  }

  Future<void> _show() async {
    if (_open || !widget.enabled || !widget.isCurrentMode()) return;
    final scheme = Theme.of(context).colorScheme;
    final menuWidth =
        math.max(44.0, math.min(340.0, MediaQuery.sizeOf(context).width - 32));
    setState(() => _open = true);
    T? result;
    try {
      result = await showMenu<T>(
        context: context,
        positionBuilder: _position,
        shape: AppShape.control,
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shadowColor: scheme.shadow.withValues(alpha: .18),
        elevation: 4,
        requestFocus: true,
        constraints: BoxConstraints(maxWidth: menuWidth),
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
        popUpAnimationStyle: widget.reduced
            ? AnimationStyle.noAnimation
            : const AnimationStyle(
                duration: AppMotion.quick,
                reverseDuration: AppMotion.quick,
                curve: AppMotion.standardCurve,
                reverseCurve: Curves.easeInCubic,
              ),
        items: [
          for (final item in widget.items)
            if (item == null)
              const PopupMenuDivider(height: 10)
            else
              PopupMenuItem<T>(
                key: item.key,
                value: item.value,
                enabled: item.onSelected != null,
                height: 48,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(item.icon,
                        size: 20,
                        color: item.onSelected == null
                            ? scheme.onSurface.withValues(alpha: .38)
                            : scheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(item.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            semanticsLabel: item.label)),
                    if (item.checked) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check, size: 18, color: scheme.primary),
                    ],
                  ],
                ),
              ),
        ],
      );
    } finally {
      // Native focus/navigation failures must not permanently lock this menu.
      if (mounted) setState(() => _open = false);
    }
    if (!mounted) return;
    if (result == null || !widget.enabled || !widget.isCurrentMode()) return;
    // Read the current items, not the opening snapshot: a read-only/busy policy
    // change while the menu is open must not dispatch an obsolete action.
    for (final item in widget.items) {
      if (item?.value == result) {
        item?.onSelected?.call();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ConstrainedBox(
      key: _anchor,
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: widget.label == null
          ? IconButton(
              tooltip: widget.tooltip,
              onPressed: widget.enabled ? _show : null,
              style: _controlStyle(context,
                  reduced: widget.reduced, iconOnly: true),
              icon: Icon(widget.icon),
            )
          : Tooltip(
              message: widget.tooltip,
              child: OutlinedButton(
                onPressed: widget.enabled ? _show : null,
                style: _controlStyle(context, reduced: widget.reduced),
                child: _ButtonLabel(
                  label: widget.label!,
                  icon: widget.icon,
                  trailing: AnimatedRotation(
                    turns: _open ? .5 : 0,
                    duration: widget.reduced ? Duration.zero : AppMotion.quick,
                    curve: AppMotion.standardCurve,
                    child: const Icon(Icons.expand_more, size: 18),
                  ),
                ),
              ),
            ),
    );
  }
}
