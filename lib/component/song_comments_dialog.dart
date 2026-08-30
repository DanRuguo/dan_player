import 'package:dan_player/component/app_presentation.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/song_comment_match_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/song_comment_association.dart';
import 'package:dan_player/online/song_comments.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Calling this entry point is the only application action that starts loading
/// comments. The captured platform ID is independent of later playback changes.
Future<void> showSongCommentsDialog(
  BuildContext context,
  Audio audio, {
  SongCommentsService? service,
  SongCommentCandidateSearch? candidateSearch,
}) async {
  await showAppDialog<void>(
    context: context,
    builder: (_) => SongCommentsDialog(
      audio: audio,
      service: service,
      candidateSearch: candidateSearch,
    ),
  );
}

class SongCommentsDialog extends StatefulWidget {
  const SongCommentsDialog({
    super.key,
    required this.audio,
    this.service,
    this.candidateSearch,
  });
  final Audio audio;
  final SongCommentsService? service;
  final SongCommentCandidateSearch? candidateSearch;

  @override
  State<SongCommentsDialog> createState() => _SongCommentsDialogState();
}

class _CommentTab {
  final comments = <SongComment>[];
  final scroll = _CommentScrollController();
  int nextPage = 0;
  int? total;
  bool loaded = false;
  bool loading = false;
  bool hasMore = true;
  bool reachedLimit = false;
  bool repeatedPage = false;
  String Function()? error;
}

/// SelectableText owns nested scrollables, so a shared PageStorage key can be
/// overwritten by their zero offsets. Keep only this list's offset, and restore
/// it when its position is created (before paint, without a post-frame jump).
class _CommentScrollController extends ScrollController {
  _CommentScrollController() : super(keepScrollOffset: false);
  double _savedOffset = 0;

  @override
  void detach(ScrollPosition position) {
    if (position.hasPixels) _savedOffset = position.pixels;
    super.detach(position);
  }

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics,
          ScrollContext context, ScrollPosition? oldPosition) =>
      ScrollPositionWithSingleContext(
        physics: physics,
        context: context,
        initialPixels: _savedOffset,
        keepScrollOffset: false,
        oldPosition: oldPosition,
      );
}

class _SongCommentsDialogState extends State<SongCommentsDialog> {
  late Map<SongCommentSort, _CommentTab> _tabs;
  SongCommentSort _sort = SongCommentSort.hot;
  SongCommentsTarget? _target;
  String? _unavailable;
  SongCommentsCancellation? _request;
  int _generation = 0;
  bool _closed = false;
  bool _associationBusy = false;
  String Function()? _associationError;

  SongCommentsService get _service =>
      widget.service ?? SongCommentsService.instance;
  _CommentTab get _tab => _tabs[_sort]!;

  @override
  void initState() {
    super.initState();
    _configure();
  }

  void _configure() {
    _target = SongCommentsService.targetFor(widget.audio);
    _unavailable = SongCommentsService.unavailableReason(widget.audio);
    _tabs = {for (final sort in SongCommentSort.values) sort: _CommentTab()};
    if (_target != null) unawaited(_load());
  }

  void _disposeTabs() {
    for (final tab in _tabs.values) {
      tab.scroll.dispose();
    }
  }

  void _reconfigure() {
    if (!mounted || _closed) return;
    _cancel();
    _disposeTabs();
    setState(() {
      _target = SongCommentsService.targetFor(widget.audio);
      _unavailable = SongCommentsService.unavailableReason(widget.audio);
      _tabs = {for (final sort in SongCommentSort.values) sort: _CommentTab()};
      _sort = SongCommentSort.hot;
      _associationError = null;
    });
    if (_target != null) unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant SongCommentsDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_target != SongCommentsService.targetFor(widget.audio) ||
        oldWidget.service != widget.service ||
        _unavailable != SongCommentsService.unavailableReason(widget.audio)) {
      _cancel();
      _disposeTabs();
      _configure();
    }
  }

  Future<void> _chooseAssociation() async {
    if (_closed || _associationBusy || !widget.audio.isLocal) return;
    final selected = await showSongCommentMatchDialog(
      context,
      localAudio: widget.audio,
      search: widget.candidateSearch,
      commentsService: _service,
    );
    if (!mounted || _closed || selected == null) return;
    await _updateAssociation(
      () => SongCommentAssociationStore.instance
          .setIndependent(widget.audio, selected),
    );
  }

  Future<void> _followLyric() => _updateAssociation(
        () => SongCommentAssociationStore.instance.followLyric(widget.audio),
      );

  Future<void> _removeAssociation() => _updateAssociation(
        () => SongCommentAssociationStore.instance.remove(widget.audio),
      );

  Future<void> _updateAssociation(Future<void> Function() update) async {
    if (_closed || _associationBusy || !widget.audio.isLocal) return;
    setState(() {
      _associationBusy = true;
      _associationError = null;
    });
    try {
      await update();
      if (mounted && !_closed) _reconfigure();
    } catch (error) {
      if (mounted && !_closed) {
        setState(() => _associationError = () => ui("评论关联保存失败：{0}", [error]));
      }
    } finally {
      if (mounted && !_closed) setState(() => _associationBusy = false);
    }
  }

  void _cancel() {
    _generation++;
    _request?.cancel();
    _request = null;
  }

  void _close() {
    _closed = true;
    _cancel();
  }

  void _dismiss() {
    // Protect the route underneath even if two inputs reach the captured
    // callback before the exit animation installs its IgnorePointer.
    if (_closed) return;
    _close();
    Navigator.of(context).pop();
  }

  void _select(SongCommentSort sort) {
    if (_closed || sort == _sort) return;
    _cancel();
    setState(() {
      _tab.loading = false;
      _sort = sort;
    });
    if (!_tab.loaded) unawaited(_load());
  }

  Future<void> _load() async {
    final target = _target;
    final tab = _tab;
    if (_closed || target == null || tab.loading || !tab.hasMore) return;
    final sort = _sort;
    _cancel();
    final generation = _generation;
    final cancellation = SongCommentsCancellation();
    _request = cancellation;
    setState(() {
      tab.loading = true;
      tab.error = null;
    });
    bool current() =>
        mounted &&
        !_closed &&
        generation == _generation &&
        target == _target &&
        sort == _sort;
    try {
      final result = await _service.loadPage(
        target: target,
        sort: sort,
        page: tab.nextPage,
        cancellation: cancellation,
      );
      if (!current()) return;
      final seen = tab.comments.map((comment) => comment.id).toSet();
      final incoming =
          result.comments.where((comment) => seen.add(comment.id)).toList();
      setState(() {
        tab.comments.addAll(incoming);
        tab.loaded = true;
        tab.total = result.reportedTotal;
        tab.nextPage = result.page + 1;
        tab.repeatedPage = result.comments.isNotEmpty && incoming.isEmpty;
        tab.hasMore = result.hasMore && !tab.repeatedPage;
        tab.reachedLimit = result.reachedLimit;
      });
    } on SongCommentsCancelled {
      // Route/tab/source changes intentionally ignore the cancelled response.
    } catch (error) {
      if (current()) {
        // Keep an unformatted UI message, so a cached failure follows a later
        // language change without issuing another network request.
        setState(() => tab.error = () => error is SongCommentsException
            ? ui(error.message)
            : ui("评论加载失败，请检查网络后重试。"));
      }
    } finally {
      if (current()) {
        setState(() => tab.loading = false);
        _request = null;
      }
    }
  }

  @override
  void dispose() {
    _close();
    _disposeTabs();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final tab = _tab;
    final media = MediaQuery.of(context);
    final availableHeight =
        math.max(0.0, media.size.height - media.viewInsets.vertical - 32);
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _close();
      },
      child: Dialog(
        key: const ValueKey('song-comments-dialog'),
        insetPadding: const EdgeInsets.all(16),
        shape: AppShape.surface,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 720,
          height: math.min(availableHeight, 720),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: AppDialogTitle(
                ui("歌曲评论"),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
                trailing: IconButton(
                  key: const ValueKey('song-comments-close'),
                  tooltip: ui("关闭评论"),
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  onPressed: _dismiss,
                  icon: const Icon(Symbols.close),
                ),
              ),
            ),
            if (_target != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(children: [
                  for (final sort in SongCommentSort.values) ...[
                    if (sort.index != 0) const SizedBox(width: 8),
                    Expanded(
                        child: Semantics(
                      selected: _sort == sort,
                      child: TextButton(
                        key: ValueKey('song-comments-${sort.name}'),
                        onPressed: () => _select(sort),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          visualDensity: VisualDensity.standard,
                          shape: AppShape.control,
                          foregroundColor: _sort == sort
                              ? scheme.onSecondaryContainer
                              : scheme.onSurface,
                          backgroundColor: _sort == sort
                              ? scheme.secondaryContainer
                              : Colors.transparent,
                        ),
                        child: Text(ui(sort.label)),
                      ),
                    )),
                  ],
                ]),
              ),
            if (widget.audio.isLocal) _associationPanel(context),
            Expanded(
                child: ListView.builder(
              key: PageStorageKey(
                  'song-comments-list-${_target?.identity ?? 'unavailable'}-${_sort.name}'),
              controller: tab.scroll,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              scrollCacheExtent: const ScrollCacheExtent.pixels(160),
              itemCount: tab.comments.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) return _intro(context, tab);
                if (index == tab.comments.length + 1) {
                  return _footer(context, tab);
                }
                return _CommentCard(comment: tab.comments[index - 1]);
              },
            )),
          ]),
        ),
      ),
    );
  }

  Widget _intro(BuildContext context, _CommentTab tab) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText('${widget.audio.title} · ${widget.audio.artist}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(_target == null
              ? ui("只按你确认的平台歌曲 ID 关联，不会仅凭同名歌曲自动猜测。")
              : ui("来源：{0} · 只读 · 按平台歌曲 ID 精确匹配", [ui(_target!.sourceLabel)])),
          if (_target != null) ...[
            const SizedBox(height: 4),
            Text(ui("评论由平台用户发表；不加载头像、图片或音频。"),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (tab.loaded) ...[
              const SizedBox(height: 6),
              Text(ui("已显示 {0} 条{1}", [
                tab.comments.length,
                tab.total == null ? '' : ui(' · 平台统计 {0} 条', [tab.total])
              ])),
            ],
          ],
        ]),
      );

  Widget _associationPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final store = SongCommentAssociationStore.instance;
    final association = store.associationFor(widget.audio);
    final lyricIdentity = store.lyricIdentityFor(widget.audio);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: AppShape.controlRadius,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              association == null
                  ? ui("评论来源：尚未关联")
                  : ui("评论来源：{0}{1}", [
                      ui(association.mode.label),
                      _target == null ? '' : ' · ${ui(_target!.sourceLabel)}'
                    ]),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                key: const ValueKey('song-comments-choose-association'),
                onPressed: _associationBusy ? null : _chooseAssociation,
                icon: const Icon(Symbols.search),
                label: Text(ui("选择关联歌曲")),
              ),
              Tooltip(
                message: lyricIdentity == null
                    ? ui("当前歌词不是带平台 ID 的 QQ音乐或网易云来源")
                    : ui("评论来源会随以后选择的联网歌词变化"),
                child: OutlinedButton.icon(
                  key: const ValueKey('song-comments-follow-lyric'),
                  onPressed: _associationBusy || lyricIdentity == null
                      ? null
                      : _followLyric,
                  icon: const Icon(Symbols.lyrics),
                  label: Text(ui("跟随联网歌词")),
                ),
              ),
              if (association != null)
                TextButton.icon(
                  key: const ValueKey('song-comments-remove-association'),
                  onPressed: _associationBusy ? null : _removeAssociation,
                  icon: const Icon(Symbols.link_off),
                  label: Text(ui("解除关联")),
                ),
            ]),
            if (_associationError != null) ...[
              const SizedBox(height: 8),
              Text(_associationError!(), style: TextStyle(color: scheme.error)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context, _CommentTab tab) {
    // unavailableReason returns application-owned fixed source keys, not tags.
    if (_unavailable != null) return Text(ui(_unavailable!));
    if (tab.loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              Text(ui("正在加载评论…"))
            ]),
      );
    }
    if (tab.error != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
            liveRegion: true,
            child: Text(tab.error!(),
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          key: const ValueKey('song-comments-retry'),
          style: FilledButton.styleFrom(
              minimumSize: const Size(44, 44),
              visualDensity: VisualDensity.standard,
              shape: AppShape.control),
          onPressed: _load,
          icon: const Icon(Symbols.refresh),
          label: Text(ui("重试")),
        ),
      ]);
    }
    if (tab.comments.isEmpty) return Text(ui("平台暂未返回这首歌曲的评论。"));
    if (tab.repeatedPage) return Text(ui("平台返回了重复页面，已停止继续请求。"));
    if (tab.reachedLimit) return Text(ui("已达到本次每个分类最多 10 页（200 条）的读取上限。"));
    if (!tab.hasMore) return Text(ui("已显示平台返回的全部评论。"));
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const ValueKey('song-comments-load-more'),
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(44, 44),
            visualDensity: VisualDensity.standard,
            shape: AppShape.control),
        onPressed: _load,
        icon: const Icon(Symbols.expand_more),
        label: Text(ui("加载更多")),
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({required this.comment});
  final SongComment comment;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final when = comment.publishedAt;
    final date = when == null
        ? null
        : '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
    return Padding(
      key: ValueKey('song-comment-${comment.id}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
            borderRadius: AppShape.controlRadius,
            color: scheme.surfaceContainerLow,
            border: Border.all(color: scheme.outlineVariant)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(comment.author,
                style: TextStyle(
                    color: scheme.onSurface, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(spacing: 12, runSpacing: 4, children: [
              if (date != null)
                Text(date, style: TextStyle(color: scheme.onSurfaceVariant)),
              Text(ui("{0} 赞", [comment.likeCount]),
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 10),
            SelectableText(comment.content),
            for (final reply in comment.replies) ...[
              const SizedBox(height: 10),
              SelectableText(
                  ui("引用 / 回复 · {0}\n{1}", [reply.author, reply.content]),
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ]),
        ),
      ),
    );
  }
}
