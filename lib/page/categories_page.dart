import 'dart:async';

import 'package:dan_player/component/app_content_scrollbar.dart';
import 'dart:math' as math;

import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/music_grid.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/page_scaffold.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:dan_player/component/category_labels.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({
    super.key,
    this.initialCategory = MusicCategoryKind.artist,
    this.audios,
    this.onOpenGroup,
    this.classificationScanner,
  });

  final MusicCategoryKind initialCategory;
  final List<Audio>? audios;
  final ValueChanged<MusicCategoryGroup>? onOpenGroup;
  final MusicClassificationScanner? classificationScanner;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final _search = TextEditingController();
  late MusicCategoryKind _kind = widget.initialCategory;
  MusicCategories? _snapshot;
  MusicClassificationSnapshot _classifications =
      const MusicClassificationSnapshot.empty();
  int _scanGeneration = 0;
  bool _classifying = false;
  bool _classificationsReady = false;
  String _query = '';

  List<Audio> get _audios =>
      widget.audios ?? AudioLibrary.instance.audioCollection;

  @override
  void initState() {
    super.initState();
    AudioLibrary.changes.addListener(_refresh);
    _scanClassificationsIfNeeded();
  }

  void _refresh() {
    if (!mounted) return;
    setState(_invalidateClassifications);
    _scanClassificationsIfNeeded();
  }

  void _invalidateClassifications() {
    _scanGeneration++;
    _snapshot = null;
    _classifications = const MusicClassificationSnapshot.empty();
    _classifying = false;
    _classificationsReady = false;
  }

  void _scanClassificationsIfNeeded() {
    if (_classifying || _classificationsReady) return;
    if (_kind != MusicCategoryKind.language &&
        _kind != MusicCategoryKind.composer) {
      return;
    }
    _classifying = true;
    final generation = ++_scanGeneration;
    final audios = List<Audio>.of(_audios);
    unawaited(() async {
      try {
        final classifications = await (widget.classificationScanner ??
                MusicClassificationScanner.shared)
            .scan(audios,
                isCancelled: () => !mounted || generation != _scanGeneration);
        if (!mounted || generation != _scanGeneration) return;
        setState(() {
          _classifications = classifications;
          _snapshot = null;
          _classifying = false;
          _classificationsReady = true;
        });
      } on LibraryScanCancelled {
        // A newer library revision or a disposed page owns the next result.
      } catch (_) {
        if (!mounted || generation != _scanGeneration) return;
        setState(() => _classifying = false);
      }
    }());
  }

  @override
  void didUpdateWidget(CategoriesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _invalidateClassifications();
    if (oldWidget.initialCategory != widget.initialCategory) {
      _kind = widget.initialCategory;
      _query = '';
      _search.clear();
    }
    _scanClassificationsIfNeeded();
  }

  void _chooseKind(MusicCategoryKind kind) {
    if (_kind == kind) return;
    setState(() {
      _kind = kind;
      _query = '';
      _search.clear();
    });
    _scanClassificationsIfNeeded();
  }

  void _open(MusicCategoryGroup group) {
    if (widget.onOpenGroup != null) {
      widget.onOpenGroup!(group);
    } else {
      context.push(group.location, extra: group);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final categories = _snapshot ??=
        MusicCategories(_audios, classifications: _classifications);
    final groups = categories.groups(_kind);
    final visible = groups
        .where((group) =>
            group.matches(_query) ||
            categoryDisplayTitle(group)
                .toLowerCase()
                .contains(_query.trim().toLowerCase()))
        .toList();
    final missingComposers = _kind == MusicCategoryKind.composer &&
        groups.isNotEmpty &&
        groups.every((group) => group.isUnknown);
    final unread =
        _audios.any((audio) => audio.isLocal && !audio.classificationTagsRead);
    final note = missingComposers
        ? _classifying
            ? ui("正在只读检查本地歌词中的作曲信息；无作曲署名时会回退到参与创作的艺术家。")
            : unread
                ? ui("部分本地分类标签尚未读取，可刷新乐库尝试补全；作曲信息与参与创作的艺术家均缺失的歌曲保留在“未知作曲家”中。")
                : ui("未找到作曲信息或参与创作的艺术家；歌曲保留在“未知作曲家”中。")
        : switch (_kind) {
            MusicCategoryKind.language => _classifying
                ? ui("正在只读检查本地歌词；语言优先使用标签，其次参考歌词及标题、作曲/参与创作艺术家等元数据推断。")
                : ui(
                    "语言优先使用标签，其次参考歌词及标题、作曲/参与创作艺术家等元数据推断；推断不等于音频识别，无法确认的歌曲归入“未识别”。"),
            MusicCategoryKind.composer =>
              ui("作曲家采用宽口径：优先使用作曲标签、歌词署名，缺失时回退到参与创作的艺术家；回退结果会单独标注。"),
            MusicCategoryKind.format => ui("仅按本地文件扩展名分类；联网歌曲或无扩展名文件归入“未知格式”。"),
            _ => null,
          };
    return PageScaffold(
      title: ui("分类"),
      subtitle: ui("{0} 首歌曲 · {1} {2}",
          [_audios.length, groups.length, ui(_kind.countLabel)]),
      actions: const [],
      responsiveActions: _CategorySelector(
        selected: _kind,
        onSelected: _chooseKind,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: TextField(
              key: const ValueKey('category-search'),
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: _kind == MusicCategoryKind.album
                    ? ui("搜索专辑或专辑艺术家")
                    : ui("搜索{0}", [ui(_kind.label)]),
                prefixIcon: const Icon(Icons.search),
                border: AppShape.inputBorder,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: ui("清除分类搜索"),
                        onPressed: () => setState(() {
                          _query = '';
                          _search.clear();
                        }),
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        groups.isEmpty
                            ? ui("总乐库还没有歌曲。添加本地音乐或将联网歌曲加入总乐库后即可分类浏览。")
                            : ui("未找到匹配的分类"),
                        textAlign: TextAlign.center),
                  ))
                : AppContentScrollbar(
                    builder: (context, controller) => CustomScrollView(
                      controller: controller,
                      key: PageStorageKey('music-categories-${_kind.name}'),
                      slivers: [
                        if (note != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: Text(note,
                                  key: const ValueKey('category-explanation'),
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant)),
                            ),
                          ),
                        _CategoryGrid(groups: visible, onOpen: _open),
                        const SliverPadding(
                            padding: EdgeInsets.only(bottom: 96)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    AudioLibrary.changes.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }
}

/// The portrait cards share one virtualized viewport with the explanation.
/// Keys are group identities, so a search/revision does not reload other art.
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.groups, required this.onOpen});

  final List<MusicCategoryGroup> groups;
  final ValueChanged<MusicCategoryGroup> onOpen;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final titleHeight = musicGridLineHeight(context) * 2;
    final metadataHeight = musicGridLineHeight(context, fontSize: 13);
    final hasSubtitle = groups.any((group) => group.subtitle != null);
    final hasEvidence = groups.any((group) => group.evidenceSummary.isNotEmpty);
    final indices = <Key, int>{
      for (var index = 0; index < groups.length; index++)
        ValueKey(('category-group', groups[index].id)): index,
    };
    return SliverLayoutBuilder(builder: (context, constraints) {
      const spacing = 12.0;
      final columns =
          math.max(1, ((constraints.crossAxisExtent + spacing) / 172).floor());
      final width =
          (constraints.crossAxisExtent - spacing * (columns - 1)) / columns;
      final coverSize = math.min(112.0, math.max(48.0, width - 24));
      final height = 16 +
          coverSize +
          8 +
          titleHeight +
          4 +
          metadataHeight +
          (hasSubtitle ? metadataHeight : 0) +
          (hasEvidence ? metadataHeight : 0);
      return SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: height,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
        ),
        itemCount: groups.length,
        findChildIndexCallback: (key) => indices[key],
        itemBuilder: (context, index) {
          final group = groups[index];
          final description = [
            categoryDisplayTitle(group),
            if (group.subtitle != null) group.subtitle!,
            ui("{0} 首 · {1}",
                [group.audios.length, categorySourceSummary(group)]),
            if (group.evidenceSummary.isNotEmpty)
              categoryEvidenceSummary(group),
          ].join(' · ');
          return AppEntrance(
            key: ValueKey(('category-group', group.id)),
            identity: ('category-group', group.id),
            order: index,
            child: Tooltip(
              message: description,
              child: Material(
                color: Colors.transparent,
                shape: AppShape.control,
                child: InkWell(
                  key: ValueKey(('category-card', group.id)),
                  borderRadius: AppShape.controlRadius,
                  onTap: () => onOpen(group),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        ClipOval(
                          key: ValueKey(('category-cover', group.id)),
                          child: AudioArtwork(
                            audio: group.audios.first,
                            size: coverSize,
                            placeholder: ColoredBox(
                              color: scheme.surfaceContainerHighest,
                              child: Center(
                                child: Icon(categoryIcon(group.kind),
                                    size: coverSize * .45,
                                    color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: titleHeight,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Text(categoryDisplayTitle(group),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: musicGridTitleStyle.copyWith(
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                        if (hasSubtitle)
                          SizedBox(
                            height: metadataHeight,
                            child: Text(group.subtitle ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13,
                                    height: 1.25,
                                    color: scheme.onSurfaceVariant)),
                          ),
                        const SizedBox(height: 4),
                        Text(
                            ui("{0} 首 · {1}", [
                              group.audios.length,
                              categorySourceSummary(group)
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                height: 1.25,
                                color: scheme.onSurfaceVariant)),
                        if (hasEvidence)
                          Text(categoryEvidenceSummary(group),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  height: 1.25,
                                  color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }
}

IconData categoryIcon(MusicCategoryKind kind) => switch (kind) {
      MusicCategoryKind.artist => Icons.person_outline,
      MusicCategoryKind.album => Icons.album_outlined,
      MusicCategoryKind.composer => Icons.music_note_outlined,
      MusicCategoryKind.language => Icons.language,
      MusicCategoryKind.format => Icons.audio_file_outlined,
      MusicCategoryKind.source => Icons.cloud_outlined,
    };

class _CategorySelector extends StatefulWidget {
  const _CategorySelector({required this.selected, required this.onSelected});

  final MusicCategoryKind selected;
  final ValueChanged<MusicCategoryKind> onSelected;

  @override
  State<_CategorySelector> createState() => _CategorySelectorState();
}

class _CategorySelectorState extends State<_CategorySelector> {
  final _scroll = ScrollController();
  final _chipKeys = {
    for (final kind in MusicCategoryKind.values) kind: GlobalKey(),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _revealSelected();
  }

  @override
  void didUpdateWidget(covariant _CategorySelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent can change the rail's width without changing selection.
    _revealSelected();
  }

  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selectedContext = _chipKeys[widget.selected]!.currentContext;
      if (selectedContext != null) {
        Scrollable.ensureVisible(selectedContext, alignment: .5);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Scrollbar(
        controller: _scroll,
        thumbVisibility: true,
        interactive: true,
        child: SingleChildScrollView(
          key: const ValueKey('category-kind-scroll'),
          controller: _scroll,
          primary: false,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final kind in MusicCategoryKind.values) ...[
                if (kind != MusicCategoryKind.values.first)
                  const SizedBox(width: 8),
                ConstrainedBox(
                  key: _chipKeys[kind],
                  constraints: const BoxConstraints(minHeight: 44),
                  child: ChoiceChip(
                    key: ValueKey('category-kind-${kind.name}'),
                    avatar: Icon(categoryIcon(kind), size: 18),
                    label: Text(ui(kind.label)),
                    selected: widget.selected == kind,
                    showCheckmark: false,
                    visualDensity: VisualDensity.standard,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    shape: AppShape.control,
                    onSelected: (_) => widget.onSelected(kind),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }
}
