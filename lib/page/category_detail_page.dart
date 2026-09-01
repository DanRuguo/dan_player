import 'dart:async';

import 'package:dan_player/component/app_content_scrollbar.dart';

import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/audio_sort_options.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/playlist_destination_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/page_scaffold.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:dan_player/component/category_labels.dart';

typedef CategoryTrackBuilder = Widget Function(
    BuildContext context, Audio audio, VoidCallback play);

class CategoryDetailPage extends StatefulWidget {
  const CategoryDetailPage({
    super.key,
    required this.kind,
    required this.groupId,
    this.initialGroup,
    this.audios,
    this.onPlay,
    this.onAddToPlaylist,
    this.trackBuilder,
    this.classificationScanner,
  });

  final MusicCategoryKind kind;
  final String groupId;
  final MusicCategoryGroup? initialGroup;
  final List<Audio>? audios;
  final void Function(int index, List<Audio> queue)? onPlay;
  final FutureOr<void> Function(List<Audio> audios)? onAddToPlaylist;
  final CategoryTrackBuilder? trackBuilder;
  final MusicClassificationScanner? classificationScanner;

  @override
  State<CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends State<CategoryDetailPage> {
  final _selection = MultiSelectController<Audio>();
  final _search = TextEditingController();
  MusicCategories? _snapshot;
  MusicClassificationSnapshot _classifications =
      const MusicClassificationSnapshot.empty();
  int _scanGeneration = 0;
  late int _classificationRevision;
  bool _classifying = false;
  bool _allowInitialGroup = true;
  String _query = '';
  late AudioSortField _sort = widget.kind == MusicCategoryKind.album
      ? AudioSortField.track
      : AudioSortField.original;
  SortDirection _direction = SortDirection.ascending;

  @override
  void initState() {
    super.initState();
    _classificationRevision = AudioLibrary.classificationRevision;
    AudioLibrary.changes.addListener(_refresh);
    _scanClassifications();
  }

  void _refresh() {
    if (!mounted) return;
    final revision = AudioLibrary.classificationRevision;
    if (revision == _classificationRevision) {
      setState(() => _snapshot = null);
      return;
    }
    _classificationRevision = revision;
    setState(() {
      _invalidateClassifications();
      _allowInitialGroup = false;
    });
    _scanClassifications();
  }

  void _invalidateClassifications() {
    _scanGeneration++;
    _snapshot = null;
    _classifications = const MusicClassificationSnapshot.empty();
    _classifying = false;
  }

  void _scanClassifications() {
    if (widget.kind != MusicCategoryKind.language &&
        widget.kind != MusicCategoryKind.composer) {
      return;
    }
    _classifying = true;
    final generation = ++_scanGeneration;
    final audios =
        List<Audio>.of(widget.audios ?? AudioLibrary.instance.audioCollection);
    unawaited(() async {
      try {
        final classifications = await (widget.classificationScanner ??
                MusicClassificationScanner.shared)
            .scan(audios,
                includeComposer: widget.kind == MusicCategoryKind.composer,
                isCancelled: () => !mounted || generation != _scanGeneration);
        if (!mounted || generation != _scanGeneration) return;
        setState(() {
          _classifications = classifications;
          _snapshot = null;
          _classifying = false;
        });
      } on LibraryScanCancelled {
        // Superseded revisions and disposed detail pages ignore stale results.
      } catch (_) {
        if (!mounted || generation != _scanGeneration) return;
        setState(() => _classifying = false);
      }
    }());
  }

  @override
  void didUpdateWidget(CategoryDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final navigationChanged =
        oldWidget.groupId != widget.groupId || oldWidget.kind != widget.kind;
    final classificationInputsChanged = navigationChanged ||
        !identical(oldWidget.audios, widget.audios) ||
        !identical(
            oldWidget.classificationScanner, widget.classificationScanner) ||
        !identical(oldWidget.initialGroup, widget.initialGroup);
    // A parent/theme rebuild must retain the completed classification scan.
    // Otherwise the detail route rereads lyric evidence despite unchanged
    // audio and can accumulate needless native/file work during UI updates.
    if (!classificationInputsChanged) return;
    _invalidateClassifications();
    if (navigationChanged) {
      _query = '';
      _search.clear();
      _selection.selected.clear();
      _selection.enableMultiSelectView = false;
      _allowInitialGroup = true;
      _sort = widget.kind == MusicCategoryKind.album
          ? AudioSortField.track
          : AudioSortField.original;
      _direction = SortDirection.ascending;
    }
    _scanClassifications();
  }

  MusicCategoryGroup? get _group {
    final snapshot = _snapshot ??= MusicCategories(
        widget.audios ?? AudioLibrary.instance.audioCollection,
        classifications: _classifications);
    final live = snapshot.find(widget.kind, widget.groupId);
    if (live != null) {
      _allowInitialGroup = false;
      return live;
    }
    // A song opened from an unindexed search result can still be viewed once.
    // After a library update, removed groups never resurrect stale snapshots.
    final initial = widget.initialGroup;
    return widget.audios == null &&
            _allowInitialGroup &&
            initial?.id == widget.groupId &&
            initial?.kind == widget.kind
        ? initial
        : null;
  }

  List<Audio> _visibleTracks(MusicCategoryGroup group) {
    final query = _query.trim().toLowerCase();
    final entries = group.audios.where((audio) {
      return query.isEmpty ||
          [audio.displayTitle, audio.artist, audio.album, audio.composer ?? '']
              .any((value) => value.toLowerCase().contains(query));
    });
    return sortedAudios(entries, _sort, direction: _direction);
  }

  void _play(int index, List<Audio> queue) {
    if (queue.isEmpty || index < 0 || index >= queue.length) return;
    final snapshot = List<Audio>.of(queue);
    if (widget.onPlay != null) {
      widget.onPlay!(index, snapshot);
    } else {
      PlayService.instance.playbackService.play(index, snapshot);
    }
  }

  Future<void> _add(List<Audio> queue) async {
    if (queue.isEmpty) return;
    final snapshot = List<Audio>.of(queue);
    if (widget.onAddToPlaylist != null) {
      await widget.onAddToPlaylist!(snapshot);
    } else {
      await showAddAudiosToPlaylistDialog(context, snapshot);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final group = _group;
    if (group == null) {
      return PageScaffold(
        title: ui(widget.kind.label),
        actions: const [],
        body: Center(
            child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
              _classifying
                  ? ui("正在只读检查本地歌词中的分类信息…")
                  : ui("此分类已不存在或标签已更新，请返回分类页重新选择。"),
              textAlign: TextAlign.center),
        )),
      );
    }
    final queue = _visibleTracks(group);
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) {
        final selecting = _selection.enableMultiSelectView;
        final selected = queue.where(_selection.selected.contains).toList();
        final addQueue = selecting ? selected : queue;
        return PageScaffold(
          title: ui(widget.kind.label),
          subtitle: ui("{0} 首 · {1}",
              [group.audios.length, categorySourceSummary(group)]),
          actions: const [],
          responsiveActions: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!selecting)
                FilledButton(
                  key: const ValueKey('category-play-all'),
                  onPressed: queue.isEmpty ? null : () => _play(0, queue),
                  style: _actionStyle(context, primary: true),
                  child: AppToolbarLabel(
                      label: ui("播放全部"), icon: Icons.play_arrow),
                ),
              if (selecting) ...[
                TextButton(
                  onPressed: () => _selection.selectAll(queue),
                  style: _actionStyle(context),
                  child: Text(ui("全选"),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                TextButton(
                  onPressed: () {
                    _selection.clear();
                    _selection.useMultiSelectView(false);
                  },
                  style: _actionStyle(context),
                  child: Text(ui("退出多选"),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
              OutlinedButton(
                key: const ValueKey('category-add-playlist'),
                onPressed:
                    addQueue.isEmpty ? null : () => unawaited(_add(addQueue)),
                style: _actionStyle(context),
                child: AppToolbarLabel(
                    icon: Icons.playlist_add,
                    label: selecting
                        ? ui("加入歌单 ({0})", [selected.length])
                        : ui("加入歌单")),
              ),
              if (!selecting)
                AppSortButton<AudioSortField>(
                  key: const ValueKey('category-track-sort'),
                  value: _sort,
                  scopeId: (widget.kind, widget.groupId),
                  direction:
                      _sort == AudioSortField.original ? null : _direction,
                  onChanged: (value) => setState(() => _sort = value),
                  onDirectionChanged: (value) =>
                      setState(() => _direction = value),
                  options: [
                    for (final sort in AudioSortField.values)
                      AppSortOption(
                        key: ValueKey('category-sort-${switch (sort) {
                          AudioSortField.original => 'library',
                          AudioSortField.name => 'title',
                          _ => sort.name,
                        }}'),
                        value: sort,
                        label: sort.label,
                        icon: audioSortIcon(sort),
                        group: sort.group,
                      ),
                  ],
                  helpText: _sort == AudioSortField.original
                      ? _sort.note
                      : [
                          audioSortMissingValueNote,
                          if (_sort.note != null) _sort.note!
                        ].join('\n'),
                ),
            ],
          ),
          body: AppContentScrollbar(
            builder: (context, controller) => ListView.builder(
              controller: controller,
              key: PageStorageKey(('category-tracks', group.id)),
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: queue.length + 2 + (queue.isEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tooltip(
                            message: categoryDisplayTitle(group),
                            child: Text(categoryDisplayTitle(group),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w600))),
                        if (group.subtitle != null)
                          Text(group.subtitle!,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (group.evidenceSummary.isNotEmpty)
                          Text(ui("分类依据：{0}", [categoryEvidenceSummary(group)]),
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                        Text(ui("分类仅用于浏览，不移动文件或更改标签。"),
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  );
                }
                if (index == 1) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    child: TextField(
                      key: const ValueKey('category-track-search'),
                      controller: _search,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: ui("在此分类中搜索歌曲"),
                        prefixIcon: const Icon(Icons.search),
                        border: AppShape.inputBorder,
                      ),
                    ),
                  );
                }
                if (queue.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child:
                        Text(ui("此分类中未找到匹配的歌曲"), textAlign: TextAlign.center),
                  );
                }
                final audioIndex = index - 2;
                final audio = queue[audioIndex];
                return KeyedSubtree(
                  key:
                      ValueKey(('category-audio', group.id, audio, audioIndex)),
                  child: widget.trackBuilder?.call(
                          context, audio, () => _play(audioIndex, queue)) ??
                      Material(
                        type: MaterialType.transparency,
                        child: AudioTile(
                          audioIndex: audioIndex,
                          playlist: queue,
                          multiSelectController: _selection,
                        ),
                      ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    AudioLibrary.changes.removeListener(_refresh);
    _search.dispose();
    _selection.dispose();
    super.dispose();
  }
}

ButtonStyle _actionStyle(BuildContext context, {bool primary = false}) =>
    appToolbarControlStyle(context, primary: primary);
