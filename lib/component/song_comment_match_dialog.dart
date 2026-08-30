import 'package:dan_player/component/app_presentation.dart';
import 'dart:async';

import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/online/song_comments.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

typedef SongCommentCandidateSearch = Future<OnlineSearchResponse> Function(
    String query);

Future<Audio?> showSongCommentMatchDialog(
  BuildContext context, {
  required Audio localAudio,
  SongCommentCandidateSearch? search,
  SongCommentsService? commentsService,
}) =>
    showAppDialog<Audio>(
      context: context,
      builder: (_) => SongCommentMatchDialog(
        localAudio: localAudio,
        search: search,
        commentsService: commentsService,
      ),
    );

class SongCommentMatchDialog extends StatefulWidget {
  const SongCommentMatchDialog({
    super.key,
    required this.localAudio,
    this.search,
    this.commentsService,
  });

  final Audio localAudio;
  final SongCommentCandidateSearch? search;
  final SongCommentsService? commentsService;

  @override
  State<SongCommentMatchDialog> createState() => _SongCommentMatchDialogState();
}

class _SongCommentMatchDialogState extends State<SongCommentMatchDialog> {
  late final TextEditingController _query;
  List<Audio> _results = const [];
  Audio? _selected;
  SongComment? _preview;
  SongCommentsCancellation? _previewCancellation;
  String Function()? _searchError;
  String? _partialFailure;
  String Function()? _previewError;
  bool _searching = false;
  bool _previewing = false;
  bool _closed = false;
  int _searchGeneration = 0;
  int _previewGeneration = 0;

  SongCommentsService get _comments =>
      widget.commentsService ?? SongCommentsService.instance;

  @override
  void initState() {
    super.initState();
    final composer = widget.localAudio.composer?.trim() ?? '';
    final artist = widget.localAudio.artist.trim();
    final taggedTitle = widget.localAudio.title.trim();
    final searchTitle =
        taggedTitle.isNotEmpty && taggedTitle.toUpperCase() != 'UNKNOWN'
            ? taggedTitle
            : widget.localAudio.fileNameTitle;
    _query = TextEditingController(
      text: [
        searchTitle,
        if (composer.isNotEmpty)
          composer
        else if (artist.isNotEmpty && artist.toUpperCase() != 'UNKNOWN')
          artist,
      ].join(' '),
    );
    unawaited(_search());
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (_closed || _searching || query.isEmpty) return;
    final generation = ++_searchGeneration;
    _cancelPreview();
    setState(() {
      _searching = true;
      _searchError = null;
      _partialFailure = null;
      _results = const [];
      _selected = null;
      _preview = null;
    });
    try {
      final result = await (widget.search ??
          (value) =>
              OnlineMusicService.instance.search(value, limit: 30))(query);
      if (!_isCurrentSearch(generation)) return;
      setState(() {
        final ranked = result.tracks
            .where((audio) => SongCommentsService.targetFor(audio) != null)
            .indexed
            .map((entry) => (
                  audio: entry.$2,
                  index: entry.$1,
                  score: computeSongMatchScore(
                    widget.localAudio,
                    entry.$2.title,
                    entry.$2.artist,
                    entry.$2.album,
                  ),
                ))
            .toList()
          ..sort((left, right) {
            final score = right.score.compareTo(left.score);
            return score != 0 ? score : left.index.compareTo(right.index);
          });
        _results = ranked.map((entry) => entry.audio).toList(growable: false);
        _partialFailure =
            result.failures.isEmpty ? null : result.failures.values.join('；');
      });
    } catch (error) {
      if (!_isCurrentSearch(generation)) return;
      setState(() => _searchError = () =>
          error is OnlineMusicException ? error.message : ui("搜索失败，请检查网络后重试。"));
    } finally {
      if (_isCurrentSearch(generation)) {
        setState(() => _searching = false);
      }
    }
  }

  bool _isCurrentSearch(int generation) =>
      mounted && !_closed && generation == _searchGeneration;

  void _cancelPreview() {
    _previewGeneration++;
    _previewCancellation?.cancel();
    _previewCancellation = null;
  }

  Future<void> _select(Audio audio) async {
    if (_closed || _selected?.path == audio.path) return;
    _cancelPreview();
    final generation = _previewGeneration;
    final cancellation = SongCommentsCancellation();
    _previewCancellation = cancellation;
    setState(() {
      _selected = audio;
      _preview = null;
      _previewError = null;
      _previewing = true;
    });
    final target = SongCommentsService.targetFor(audio);
    if (target == null) {
      setState(() {
        _previewing = false;
        _previewError = () => ui("该候选缺少可核实的平台歌曲 ID。");
      });
      return;
    }
    try {
      final page = await _comments.loadPage(
        target: target,
        sort: SongCommentSort.hot,
        page: 0,
        cancellation: cancellation,
      );
      if (!_isCurrentPreview(generation, audio)) return;
      setState(
          () => _preview = page.comments.isEmpty ? null : page.comments.first);
    } on SongCommentsCancelled {
      // A new selection or a closed dialog intentionally drops the preview.
    } catch (error) {
      if (!_isCurrentPreview(generation, audio)) return;
      setState(() => _previewError = () => error is SongCommentsException
          ? ui(error.message)
          : ui("评论预览暂时不可用；仍可按平台 ID 关联。"));
    } finally {
      if (_isCurrentPreview(generation, audio)) {
        setState(() => _previewing = false);
        _previewCancellation = null;
      }
    }
  }

  bool _isCurrentPreview(int generation, Audio audio) =>
      mounted &&
      !_closed &&
      generation == _previewGeneration &&
      _selected?.path == audio.path;

  void _close() {
    if (_closed) return;
    _closed = true;
    _searchGeneration++;
    _cancelPreview();
  }

  @override
  void dispose() {
    _close();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return PopScope<Audio>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _close();
      },
      child: Dialog(
        key: const ValueKey('song-comment-match-dialog'),
        shape: AppShape.surface,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                    child: CustomScrollView(
                  key: const ValueKey('song-comment-match-scroll'),
                  slivers: [
                    SliverToBoxAdapter(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppDialogTitle(ui("为本地歌曲关联评论"),
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          ui("只保存所选平台与歌曲 ID，不登录平台，也不会修改歌词或本地音频标签。"),
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('song-comment-match-query'),
                              controller: _query,
                              enabled: !_searching,
                              onSubmitted: (_) => _search(),
                              decoration: InputDecoration(
                                labelText: ui("歌曲名 / 作曲家或演唱者"),
                                border: AppShape.inputBorder,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            key: const ValueKey('song-comment-match-search'),
                            tooltip: ui("搜索候选"),
                            onPressed: _searching ? null : _search,
                            icon: const Icon(Symbols.search),
                          ),
                        ]),
                        if (_searchError != null || _partialFailure != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _searchError?.call() ?? _partialFailure!,
                              style: TextStyle(color: scheme.error),
                            ),
                          ),
                        const SizedBox(height: 10),
                      ],
                    )),
                    if (_searching || _results.isEmpty)
                      SliverToBoxAdapter(
                          child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                            child: _searching
                                ? const CircularProgressIndicator()
                                : Text(ui("没有可关联的候选，请修改关键词后重试。"))),
                      ))
                    else
                      SliverList.builder(
                        key: const ValueKey('song-comment-match-results'),
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final item = _results[index];
                          final selected = _selected?.path == item.path;
                          return ListTile(
                            key: ValueKey('song-comment-match-${item.path}'),
                            selected: selected,
                            selectedTileColor: scheme.secondaryContainer,
                            shape: AppShape.control,
                            onTap: () => _select(item),
                            leading: ClipRRect(
                              borderRadius: AppShape.smallRadius,
                              child: AudioArtwork(
                                audio: item,
                                placeholder: const Icon(Symbols.album),
                              ),
                            ),
                            title: Text(item.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              ui("{0}\n专辑：{1} · 作曲：{2} · {3}", [
                                item.artist,
                                item.album,
                                item.composer?.trim().isNotEmpty == true
                                    ? item.composer
                                    : ui('平台未提供'),
                                ui(item.sourceLabel)
                              ]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Icon(selected
                                ? Symbols.check_circle
                                : Symbols.radio_button_unchecked),
                          );
                        },
                      ),
                    if (_selected != null)
                      SliverToBoxAdapter(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                            const SizedBox(height: 10),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLow,
                                borderRadius: AppShape.controlRadius,
                                border:
                                    Border.all(color: scheme.outlineVariant),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: _previewing
                                    ? Row(children: [
                                        const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                            child: Text(ui("正在读取一条评论示例…"))),
                                      ])
                                    : Text(
                                        _preview == null
                                            ? (_previewError?.call() ??
                                                ui("平台当前没有返回评论示例。"))
                                            : ui("评论示例 · {0}\n{1}", [
                                                _preview!.author,
                                                _preview!.content
                                              ]),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                              ),
                            ),
                          ])),
                  ],
                )),
                const SizedBox(height: 12),
                OverflowBar(
                    alignment: MainAxisAlignment.end,
                    overflowAlignment: OverflowBarAlignment.end,
                    spacing: 10,
                    overflowSpacing: 4,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(ui("取消")),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('song-comment-match-confirm'),
                        onPressed: _selected == null
                            ? null
                            : () => Navigator.pop(context, _selected),
                        icon: const Icon(Symbols.link),
                        label: Text(ui("关联所选歌曲")),
                      ),
                    ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
