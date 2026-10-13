import 'package:dan_player/app_preference.dart';
import 'dart:math' as math;
import 'dart:io';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/component/folder_actions.dart';
import 'package:dan_player/component/anchored_menu_action.dart';
import 'package:dan_player/folder_note_preferences.dart';
import 'package:dan_player/component/music_grid.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/folder_tree_pane.dart';
import 'package:dan_player/component/playlist_tree_item.dart';
import 'package:dan_player/component/multi_selection_lifecycle.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/library/audio_folder_sort.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/folder_tree.dart';
import 'package:dan_player/page/audio_sort_methods.dart';
import 'package:dan_player/page/page_scaffold.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as path;

import 'package:desktop_lyric/ui_language.dart';
import 'package:desktop_lyric/font_policy.dart';

class FoldersPage extends StatefulWidget {
  const FoldersPage(
      {super.key,
      this.dataDirectory,
      this.initialFolderPath,
      this.playbackService,
      this.loadArtwork,
      this.sortLargeFolder});
  final Directory? dataDirectory;
  final String? initialFolderPath;
  final PlaybackService? playbackService;
  final AudioArtworkLoader? loadArtwork;

  /// Optional controlled worker for isolated ownership tests.
  final FolderTreeSongSorter? sortLargeFolder;
  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  late final Future<Directory> _data = widget.dataDirectory == null
      ? getAppDataDir()
      : Future.value(widget.dataDirectory);
  final _selection = MultiSelectController<Audio>();
  final _scroll = ScrollController();
  final Set<String> _expanded = {};
  FolderTree? _tree;
  List<AudioFolder>? _sourceFolders;
  List<String> _scanRoots = const [];
  int _revision = -1;
  int _folderSort = -1;
  SortOrder? _folderOrder;
  int _songSort = -1;
  SortOrder? _songOrder;
  Map<String, List<Audio>> _songs = const {};
  List<Audio> _allSongs = const [];
  List<AudioFolder> _allFolders = const [];
  String? _revealedPath;
  final _sortedFolders = <String>{};
  final _sortingFolders = <String>{};
  final _pendingSorts = <String, int>{};
  int _sortGeneration = 0, _nextSortTicket = 0;
  bool _sortWorkerActive = false;

  @override
  void dispose() {
    ++_sortGeneration;
    _pendingSorts.clear();
    _selection.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _project(List<SortMethodDesc<Audio>> songMethods) {
    final library = AudioLibrary.instance;
    final folderPref = AppPreference.instance.foldersPagePref;
    final songPref = AppPreference.instance.folderDetailPagePref;
    final sourceChanged = _tree == null ||
        !identical(_sourceFolders, library.folders) ||
        _revision != AudioLibrary.sortRevision;
    final roots = sourceChanged ? library.scanRoots : _scanRoots;
    final folderSort = folderPref.sortMethod.clamp(0, 2);
    final songSort =
        songPref.sortMethod >= 0 && songPref.sortMethod < songMethods.length
            ? songPref.sortMethod
            : 0;
    final changed = sourceChanged ||
        _folderSort != folderSort ||
        _folderOrder != folderPref.sortOrder;
    if (changed) {
      _sourceFolders = library.folders;
      _scanRoots = roots;
      _revision = AudioLibrary.sortRevision;
      _folderSort = folderSort;
      _folderOrder = folderPref.sortOrder;
      _tree = FolderTree.project(
          folders: library.folders,
          scanRoots: roots,
          field: AudioFolderSortField.values[folderSort],
          direction: folderPref.sortOrder == SortOrder.ascending
              ? SortDirection.ascending
              : SortDirection.descending);
      _expanded.removeWhere((id) => !_tree!.byId.containsKey(id));
      _allFolders =
          _tree!.byId.values.map((node) => node.folder).toList(growable: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _selection.retainCurrentItems(
              AudioLibrary.instance.folders.expand((folder) => folder.audios));
        }
      });
    }
    if (changed || _songSort != songSort || _songOrder != songPref.sortOrder) {
      ++_sortGeneration;
      _pendingSorts.clear();
      _sortingFolders.clear();
      _sortedFolders.clear();
      _songSort = songSort;
      _songOrder = songPref.sortOrder;
      _songs = {
        for (final node in _tree!.byId.values) node.id: node.folder.audios,
      };
      _allSongs = FolderTreeAudioList(_songs.values);
    }
    if (_revealedPath != widget.initialFolderPath &&
        widget.initialFolderPath != null &&
        _tree!.byId.containsKey(folderTreePathId(widget.initialFolderPath!))) {
      _revealedPath = widget.initialFolderPath;
      _expanded.addAll(_tree!.ancestorsOf(widget.initialFolderPath!));
    }
    final visible = {
      for (final section in _tree!.visibleSections(_expanded))
        if (section.songs) section.node.id,
    };
    _pendingSorts.removeWhere((id, _) => !visible.contains(id));
    _sortingFolders.removeWhere((id) => !visible.contains(id));
    for (final id in visible) {
      if (_sortedFolders.contains(id) || _pendingSorts.containsKey(id)) {
        continue;
      }
      final source = _tree!.byId[id]!.folder.audios;
      if (source.length <= 512) {
        final sorted = List<Audio>.of(source)
          ..letSort(songMethods[songSort], songPref.sortOrder);
        _songs = {..._songs, id: sorted};
        _sortedFolders.add(id);
      } else {
        _sortingFolders.add(id);
        _pendingSorts[id] = ++_nextSortTicket;
      }
    }
    if (_pendingSorts.isNotEmpty && !_sortWorkerActive) {
      _sortWorkerActive = true;
      // Let the bounded loading slot paint before starting the worker.
      WidgetsBinding.instance.addPostFrameCallback((_) => _sortNext());
    }
  }

  Future<void> _sortNext() async {
    while (mounted && _pendingSorts.isNotEmpty) {
      final id = _pendingSorts.keys.first;
      final ticket = _pendingSorts[id]!;
      final generation = _sortGeneration;
      final source = _tree!.byId[id]!.folder.audios;
      final method = audioSortMethods(AudioSortProfile.folder)[_songSort]
          as AudioSortMethodDesc;
      final direction = _songOrder == SortOrder.ascending
          ? SortDirection.ascending
          : SortDirection.descending;
      bool current() =>
          mounted &&
          generation == _sortGeneration &&
          _pendingSorts[id] == ticket &&
          _expanded.contains(id);
      List<Audio> sorted;
      try {
        sorted = await (widget.sortLargeFolder ?? sortFolderTreeSongs)(
            source, method.field, direction);
      } catch (_) {
        if (!current()) continue;
        // Unsendable third-party Audio subclasses must retain the same sort
        // capability; normal indexed Audio data uses the background path.
        sorted = List<Audio>.of(source)..letSort(method, _songOrder!);
      }
      if (!current()) continue;
      setState(() {
        _songs = {..._songs, id: sorted};
        _sortedFolders.add(id);
        _pendingSorts.remove(id);
        _sortingFolders.remove(id);
      });
    }
    _sortWorkerActive = false;
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return FutureBuilder<Directory>(
        future: _data,
        builder: (context, data) => ListenableBuilder(
            listenable: AudioLibrary.changes,
            builder: (context, _) {
              final songMethods = audioSortMethods(AudioSortProfile.folder);
              _project(songMethods);
              final tree = _tree!;
              final folderPref = AppPreference.instance.foldersPagePref;
              final songPref = AppPreference.instance.folderDetailPagePref;
              final folderMethods = [
                SortMethodDesc<AudioFolder>(
                    icon: Symbols.title,
                    name: ui('路径'),
                    method: (list, order) => sortAudioFoldersInPlace(
                        list, AudioFolderSortField.path,
                        direction: order == SortOrder.ascending
                            ? SortDirection.ascending
                            : SortDirection.descending)),
                SortMethodDesc<AudioFolder>(
                    icon: Symbols.edit,
                    name: ui('修改日期'),
                    method: (list, order) => sortAudioFoldersInPlace(
                        list, AudioFolderSortField.modified,
                        direction: order == SortOrder.ascending
                            ? SortDirection.ascending
                            : SortDirection.descending)),
                SortMethodDesc<AudioFolder>(
                    icon: Symbols.music_note,
                    name: ui('歌曲数量'),
                    method: (list, order) => sortAudioFoldersInPlace(
                        list, AudioFolderSortField.songCount,
                        direction: order == SortOrder.ascending
                            ? SortDirection.ascending
                            : SortDirection.descending)),
              ];
              final visibleSongs = FolderTreeAudioList([
                for (final section in tree.visibleSections(_expanded))
                  if (section.songs &&
                      !_sortingFolders.contains(section.node.id))
                    _songs[section.node.id]!,
              ]);
              final actions = <Widget>[
                _FolderSortControl(
                    label: ui('文件夹排序'),
                    child: SortMethodComboBox<AudioFolder>(
                        contentList: _allFolders,
                        sortMethods: folderMethods,
                        currSortMethod: folderMethods[_folderSort],
                        setSortMethod: (method) => setState(() {
                              folderPref.sortMethod =
                                  folderMethods.indexOf(method);
                            }),
                        sortOrder: folderPref.sortOrder,
                        setSortOrder: (order) =>
                            setState(() => folderPref.sortOrder = order),
                        scopeId: 'folder-tree-folders')),
                _FolderSortControl(
                    label: ui('歌曲排序'),
                    child: SortMethodComboBox<Audio>(
                        contentList: _allSongs,
                        sortMethods: songMethods,
                        currSortMethod: songMethods[_songSort],
                        setSortMethod: (method) => setState(() {
                              songPref.sortMethod = songMethods.indexOf(method);
                            }),
                        sortOrder: songPref.sortOrder,
                        setSortOrder: (order) =>
                            setState(() => songPref.sortOrder = order),
                        scopeId: 'folder-tree-songs')),
              ];
              return SelectionPageLifecycle(
                  onLeave: _selection.exitMultiSelect,
                  child: ListenableBuilder(
                      listenable: _selection,
                      builder: (context, _) => PageScaffold(
                            title: ui("文件夹"),
                            subtitle: ui("{0} 个文件夹", [tree.byId.length]),
                            actions: const [],
                            responsiveActions: _selection.enableMultiSelectView
                                ? AudioMultiSelectionActions(
                                    controller: _selection,
                                    contentList: visibleSongs)
                                : Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 12,
                                    runSpacing: 8,
                                    children: actions),
                            body: FolderTreePane(
                              tree: tree,
                              expanded: _expanded,
                              songsByFolder: _songs,
                              sortingFolders: _sortingFolders,
                              controller: _scroll,
                              hidden: DesktopIntegration.instance.isHidden,
                              footer: data.data == null
                                  ? const SizedBox.shrink()
                                  : PlayerDataFolderTile(directory: data.data!),
                              folderBuilder: (context, node) => AudioFolderTile(
                                  audioFolder: node.folder,
                                  treeRow: true,
                                  depth: node.depth,
                                  branchSongCount: node.songCount,
                                  branchModified: node.modified,
                                  includesSubfolders: node.children.isNotEmpty,
                                  expanded: _expanded.contains(node.id),
                                  onToggle: node.canExpand
                                      ? () => setState(() {
                                            _expanded.contains(node.id)
                                                ? _expanded.remove(node.id)
                                                : _expanded.add(node.id);
                                          })
                                      : null),
                              songBuilder: _song,
                            ),
                          )));
            }));
  }

  Widget _song(BuildContext context, FolderTreeNode node, Audio audio,
          int index, double coverSize) =>
      AudioTile(
        key: ValueKey('folder-tree-song-${audio.path}'),
        audioIndex: index,
        playlist: _songs[node.id]!,
        multiSelectController: _selection,
        playbackService: widget.playbackService,
        presentationBuilder:
            (context, _, activate, secondary, longPress, action) {
          final scheme = Theme.of(context).colorScheme;
          return PlaylistTreeItem(
            key: ValueKey('folder-tree-cover-${audio.path}'),
            title: audio.displayTitle,
            coverSize: coverSize,
            playlist: false,
            selected: _selection.selected.contains(audio),
            onTap: activate,
            onSecondaryTapDown: secondary,
            onLongPress: longPress,
            cover: ClipRRect(
              borderRadius: AppShape.smallRadius,
              child: AudioArtwork(
                audio: audio,
                size: coverSize,
                loadArtwork: widget.loadArtwork,
                animateFirstFrame: true,
                loading: ColoredBox(color: scheme.surfaceContainerHighest),
                placeholder: ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(Symbols.music_note, color: scheme.primary)),
              ),
            ),
          );
        },
      );
}

class _FolderSortControl extends StatelessWidget {
  const _FolderSortControl({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [Text(label), child]);
}

extension on List<Audio> {
  void letSort(SortMethodDesc<Audio> method, SortOrder order) =>
      method.method(this, order);
}

String folderDisplayName(String value) {
  if (value.trim().isEmpty) return ui("未命名文件夹");
  final normalized = path.windows.normalize(value);
  final name = path.windows.basename(normalized);
  return name.isEmpty ? normalized : name;
}

double folderTileExtent(BuildContext context) =>
    math.max(88, musicGridLineHeight(context) * 3 + 24);

class AudioFolderTile extends StatelessWidget {
  final AudioFolder audioFolder;
  const AudioFolderTile({
    super.key,
    required this.audioFolder,
    this.notes,
    this.saveNotes,
    this.onToggle,
    this.expanded = false,
    this.depth = 0,
    this.branchSongCount,
    this.branchModified,
    this.includesSubfolders = false,
    this.treeRow = false,
  });
  final ValueNotifier<FolderNotePreferences>? notes;
  final Future<void> Function(FolderNotePreferences)? saveNotes;
  final VoidCallback? onToggle;
  final bool expanded;
  final int depth;
  final int? branchSongCount, branchModified;
  final bool includesSubfolders;
  final bool treeRow;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final normalized = path.windows.normalize(audioFolder.path);
    final timestamp = branchModified ?? audioFolder.modified;
    final modified = timestamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)
            .toIso8601String()
            .substring(0, 10)
        : ui("未知日期");
    final summary = ui(
        includesSubfolders ? "{0} 首歌曲（含子文件夹） · 修改于 {1}" : "{0} 首歌曲 · 修改于 {1}",
        [branchSongCount ?? audioFolder.audios.length, modified]);
    return Semantics(
        expanded: onToggle == null ? null : expanded,
        child: ValueListenableBuilder<FolderNotePreferences>(
            valueListenable: notes ?? AppSettings.instance.folderNotes,
            builder: (context, preferences, _) => FolderActions(
                directory: Directory(audioFolder.path),
                notes: notes,
                saveNotes: saveNotes,
                builder: (context, menu) => _FolderTileTooltip(
                      name: preferences.noteFor(audioFolder.path) ??
                          folderDisplayName(audioFolder.path),
                      folderPath: normalized,
                      summary: '${ui('音乐文件夹')} · $summary',
                      textInset: onToggle != null || treeRow ? 176 : 140,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Material(
                          color: scheme.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                              borderRadius: AppShape.controlRadius,
                              side: BorderSide(
                                  color: scheme.outlineVariant
                                      .withValues(alpha: .6))),
                          child: InkWell(
                            key: ValueKey('folder-open-${audioFolder.path}'),
                            borderRadius: AppShape.controlRadius,
                            onTap: onToggle ?? (treeRow ? null : menu.open),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Row(children: [
                                if (onToggle != null) ...[
                                  IconButton(
                                    key: ValueKey(
                                        'folder-tree-toggle-${folderTreePathId(audioFolder.path)}'),
                                    tooltip: ui(expanded ? '折叠文件夹' : '展开文件夹'),
                                    onPressed: onToggle,
                                    constraints: const BoxConstraints.tightFor(
                                        width: 32, height: 40),
                                    padding: EdgeInsets.zero,
                                    icon: AnimatedRotation(
                                        turns: expanded ? .25 : 0,
                                        duration:
                                            appToolbarReduceMotion(context)
                                                ? Duration.zero
                                                : AppMotion.quick,
                                        child: const Icon(Symbols.chevron_right,
                                            size: 20)),
                                  ),
                                  const SizedBox(width: 4),
                                ] else if (treeRow)
                                  const SizedBox(
                                      width: folderTreeToggleSlotWidth),
                                Container(
                                    key: ValueKey(
                                        'folder-artwork-${audioFolder.path}'),
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                        color: scheme.primaryContainer,
                                        borderRadius: AppShape.smallRadius),
                                    child: Icon(Symbols.folder_open,
                                        color: scheme.onPrimaryContainer)),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(
                                          preferences
                                                  .noteFor(audioFolder.path) ??
                                              folderDisplayName(
                                                  audioFolder.path),
                                          key: ValueKey(
                                              'folder-name-${audioFolder.path}'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 16,
                                              height: 1.25,
                                              fontWeight: FontWeight.w600,
                                              color: scheme.onSurface)),
                                      Text(normalized,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 14,
                                              height: 1.25,
                                              color: scheme.onSurfaceVariant)),
                                      Text('${ui('音乐文件夹')} · $summary',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 14,
                                              height: 1.25,
                                              color: scheme.primary)),
                                    ])),
                                const SizedBox(width: 8),
                                Builder(
                                    builder: (actionContext) => IconButton(
                                        tooltip: ui('更多'),
                                        onPressed: () => toggleMenuAtAction(
                                            menu, context, actionContext),
                                        icon: Icon(Symbols.more_horiz,
                                            size: 20,
                                            color: scheme.onSurfaceVariant))),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ))));
  }
}

class PlayerDataFolderTile extends StatelessWidget {
  const PlayerDataFolderTile(
      {super.key, required this.directory, this.notes, this.saveNotes});
  final Directory directory;
  final ValueNotifier<FolderNotePreferences>? notes;
  final Future<void> Function(FolderNotePreferences)? saveNotes;
  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<FolderNotePreferences>(
        valueListenable: notes ?? AppSettings.instance.folderNotes,
        builder: (context, preferences, _) => FolderActions(
            directory: directory,
            isPlayerData: true,
            notes: notes,
            saveNotes: saveNotes,
            builder: (context, menu) => _FolderTileTooltip(
                name: preferences.noteFor(directory.path) ??
                    folderDisplayName(directory.path),
                folderPath: directory.path,
                summary: ui('缓存文件夹'),
                textInset: 132,
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Material(
                        color: scheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                            borderRadius: AppShape.controlRadius,
                            side: BorderSide(
                                color: scheme.outlineVariant
                                    .withValues(alpha: .6))),
                        child: InkWell(
                            borderRadius: AppShape.controlRadius,
                            onTap: menu.open,
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                child: Row(children: [
                                  Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                          color: scheme.primaryContainer,
                                          borderRadius: AppShape.smallRadius),
                                      child: Icon(Symbols.database,
                                          color: scheme.onPrimaryContainer)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(
                                            preferences
                                                    .noteFor(directory.path) ??
                                                folderDisplayName(
                                                    directory.path),
                                            key: ValueKey(
                                                'folder-name-${directory.path}'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 16,
                                                height: 1.25,
                                                fontWeight: FontWeight.w600,
                                                color: scheme.onSurface)),
                                        Text(directory.path,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 14,
                                                height: 1.25,
                                                color:
                                                    scheme.onSurfaceVariant)),
                                        Text(ui('缓存文件夹'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 14,
                                                height: 1.25,
                                                color: scheme.primary)),
                                      ])),
                                  Builder(
                                      builder: (actionContext) => IconButton(
                                          tooltip: ui('更多'),
                                          onPressed: () => toggleMenuAtAction(
                                              menu, context, actionContext),
                                          icon:
                                              const Icon(Symbols.more_horiz))),
                                ]))))))));
  }
}

/// Keep one full description for compact cards, without competing path and
/// summary bubbles while the visible labels already have enough room.
class _FolderTileTooltip extends StatefulWidget {
  const _FolderTileTooltip({
    required this.name,
    required this.folderPath,
    required this.summary,
    required this.textInset,
    required this.child,
  });

  final String name, folderPath, summary;
  final double textInset;
  final Widget child;

  @override
  State<_FolderTileTooltip> createState() => _FolderTileTooltipState();
}

class _FolderTileTooltipState extends State<_FolderTileTooltip> {
  (
    AppFontPolicy,
    TextStyle,
    TextScaler,
    Locale?,
    TextDirection,
    bool,
    String,
    String,
    String
  )? _measuredInputs;
  final List<({double width, bool multiline})?> _naturalWidths =
      List.filled(3, null);

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, bounds) {
      // The icon, menu and optional tree toggle keep their existing fixed slots.
      // A long path alone does not enable a tooltip in an ordinary-width card.
      final textWidth = math.max(0.0, bounds.maxWidth - widget.textInset);
      if (!textWidth.isFinite || textWidth > 180 * scaler.scale(14) / 14) {
        return widget.child;
      }
      final policy = AppFontScope.of(context);
      final defaults = Theme.of(context).textTheme.bodyMedium!;
      final direction = Directionality.of(context);
      final locale = Localizations.maybeLocaleOf(context);
      final bold = MediaQuery.boldTextOf(context);
      final inputs = (
        policy,
        defaults,
        scaler,
        locale,
        direction,
        bold,
        widget.name,
        widget.folderPath,
        widget.summary
      );
      if (_measuredInputs != inputs) {
        _measuredInputs = inputs;
        _naturalWidths.fillRange(0, _naturalWidths.length, null);
      }
      // Natural widths are independent of the card width. Keep only the three
      // current labels' numeric results, and measure later labels lazily just
      // as before. Resize/parent rebuilds need no repeated paragraph shaping.
      TextPainter? painter;
      bool overflows(int index, String value, TextStyle style) {
        var measured = _naturalWidths[index];
        if (measured == null) {
          if (bold) {
            style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
          }
          final text = painter ??= TextPainter(
              textDirection: direction,
              textScaler: scaler,
              locale: locale,
              maxLines: 1);
          text.text = appFontSpan(value, style: style, policy: policy);
          text.layout();
          measured = (width: text.width, multiline: text.didExceedMaxLines);
          _naturalWidths[index] = measured;
        }
        return measured.multiline || measured.width > textWidth + .5;
      }

      final truncated = overflows(
              0,
              widget.name,
              defaults.copyWith(
                  fontSize: 16, height: 1.25, fontWeight: FontWeight.w600)) ||
          overflows(1, widget.folderPath,
              defaults.copyWith(fontSize: 14, height: 1.25)) ||
          overflows(
              2, widget.summary, defaults.copyWith(fontSize: 14, height: 1.25));
      painter?.dispose();
      if (!truncated) return widget.child;
      return Tooltip(
          triggerMode: TooltipTriggerMode.manual,
          excludeFromSemantics: true,
          message: '${widget.name}\n${widget.folderPath}\n${widget.summary}',
          child: widget.child);
    });
  }
}
