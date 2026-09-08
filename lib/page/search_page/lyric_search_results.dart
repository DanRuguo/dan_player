import 'dart:async';

import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/search/lyric_search_index.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

typedef PlayLyricLine = Future<bool> Function(
    LyricSearchSong song, LyricSearchLine line, bool Function() stillCurrent);

class LyricSearchResultsView extends StatefulWidget {
  const LyricSearchResultsView(
      {super.key, required this.query, this.index, this.playLine});
  final String query;
  final LyricSearchIndex? index;
  final PlayLyricLine? playLine;
  @override
  State<LyricSearchResultsView> createState() => _LyricSearchResultsViewState();
}

class _LyricSearchResultsViewState extends State<LyricSearchResultsView> {
  late final index = widget.index ?? LyricSearchIndex.instance;
  LyricSearchResults? _results;
  Object? _error;
  int _request = 0;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    index.addListener(_refresh);
    _refresh();
  }

  @override
  void didUpdateWidget(covariant LyricSearchResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) _refresh();
  }

  void _refresh() {
    final request = ++_request;
    _error = null;
    unawaited(index.search(widget.query, checkCancelled: () {
      if (!mounted || request != _request) throw const LyricSearchSuperseded();
    }).then((value) {
      if (mounted && request == _request) setState(() => _results = value);
    }).catchError((Object error) {
      if (!mounted || request != _request || error is LyricSearchSuperseded) {
        return;
      }
      setState(() => _error = error);
    }));
  }

  @override
  void dispose() {
    _request++;
    index.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _play(LyricSearchSong song, LyricSearchLine line) async {
    if (!mounted || _busy || line.start == null) return;
    final request = _request;
    bool valid() => mounted && request == _request && index.isCurrent(song);
    if (!valid()) {
      showAppNotice(ui('歌词已更新，请使用最新搜索结果。'), context: context);
      return;
    }
    setState(() => _busy = true);
    try {
      final action = widget.playLine;
      final success = action != null
          ? await action(song, line, valid)
          : await PlayService.instance.playbackService.playAudioAt(song.audio,
              position: song.positionFor(line)!.inMilliseconds / 1000,
              stillCurrent: valid);
      if (mounted && !success) {
        showAppNotice(ui('未能从此句播放：歌曲不可用或歌词已更新。'), context: context);
      }
    } catch (_) {
      if (mounted) showAppNotice(ui('未能从此句播放：歌曲不可用或歌词已更新。'), context: context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final results = _results;
    return AppContentScrollbar(
        builder: (context, controller) => ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 100),
                children: [
                  Text(
                      ui('已索引 {0} 首歌曲的有效歌词',
                          [results?.indexedSongs ?? index.indexedSongs]),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(ui('仅检索已保存或已加载的本地歌词；尚未索引不代表没有歌词。'),
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  if (_error != null)
                    TextButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Symbols.refresh),
                        label: Text(ui('歌词检索暂时不可用，点击重试')))
                  else if (results == null)
                    const Center(child: CircularProgressIndicator())
                  else if (results.hits.isEmpty)
                    Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(ui('已索引歌词中没有匹配内容'),
                            textAlign: TextAlign.center))
                  else ...[
                    for (final hit in results.hits)
                      Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(hit.song.audio.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    const SizedBox(height: 4),
                                    Text(
                                        '${hit.song.audio.artist} · ${ui(hit.song.source)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                    const SizedBox(height: 12),
                                    for (final line in hit.lines) ...[
                                      _LyricLineContent(
                                          line: line, query: results.query),
                                      Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(_timeLabel(hit.song, line),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelMedium),
                                            if (line.start != null)
                                              TextButton.icon(
                                                  onPressed: _busy
                                                      ? null
                                                      : () =>
                                                          _play(hit.song, line),
                                                  icon: const Icon(
                                                      Symbols.play_arrow,
                                                      size: 18),
                                                  label: Text(ui('从此句播放'))),
                                          ]),
                                      const SizedBox(height: 8),
                                    ],
                                    if (hit.moreMatches)
                                      Text(ui('同曲还有更多匹配内容'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                    Align(
                                        alignment:
                                            AlignmentDirectional.centerEnd,
                                        child: TextButton.icon(
                                            onPressed: () => showDialog<void>(
                                                context: context,
                                                builder: (dialogContext) =>
                                                    LyricSearchPreview(
                                                        song: hit.song,
                                                        query: results.query,
                                                        onPlay: _busy
                                                            ? null
                                                            : (line) {
                                                                Navigator.of(
                                                                        dialogContext,
                                                                        rootNavigator:
                                                                            true)
                                                                    .pop();
                                                                unawaited(_play(
                                                                    hit.song,
                                                                    line));
                                                              })),
                                            icon: const Icon(Symbols.lyrics),
                                            label: Text(ui('预览歌词')))),
                                  ]))),
                    if (results.limited) Text(ui('结果较多，仅显示前 40 首，请缩小关键词范围。')),
                  ],
                ]));
  }
}

String _timeLabel(LyricSearchSong song, LyricSearchLine line) {
  final position = song.positionFor(line);
  if (position == null) return ui('无时间歌词');
  return '${position.inMinutes}:${(position.inSeconds % 60).toString().padLeft(2, '0')}';
}

class LyricSearchPreview extends StatelessWidget {
  const LyricSearchPreview(
      {super.key, required this.song, required this.query, this.onPlay});
  final LyricSearchSong song;
  final String query;
  final ValueChanged<LyricSearchLine>? onPlay;
  @override
  Widget build(BuildContext context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660, maxHeight: 720),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
                child: Row(children: [
                  Expanded(
                      child: Text(song.audio.title,
                          style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(
                      tooltip: ui('关闭'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Symbols.close)),
                ])),
            const Divider(height: 1),
            Flexible(
                child: AppContentScrollbar(
                    builder: (context, controller) => ListView.builder(
                        controller: controller,
                        padding: const EdgeInsets.all(20),
                        itemCount: song.lines.length,
                        itemBuilder: (context, i) {
                          final line = song.lines[i];
                          return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _LyricLineContent(
                                        line: line, query: query, full: true),
                                    if (line.start != null)
                                      TextButton.icon(
                                          onPressed: onPlay == null
                                              ? null
                                              : () => onPlay!(line),
                                          icon: const Icon(Symbols.play_arrow,
                                              size: 18),
                                          label: Text(
                                              '${ui('从此句播放')} · ${_timeLabel(song, line)}')),
                                  ]));
                        }))),
          ])));
}

class _LyricLineContent extends StatelessWidget {
  const _LyricLineContent(
      {required this.line, required this.query, this.full = false});
  final LyricSearchLine line;
  final String query;
  final bool full;
  TextSpan _highlight(BuildContext context, String value) {
    final words = query.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return TextSpan(text: value);
    final pattern =
        RegExp(words.map(RegExp.escape).join('|'), caseSensitive: false);
    // A snippet centres on an actual hit even deep into a very long line.
    // The independent preview keeps a larger bounded line layout; original
    // text and the index remain complete, and the result list stays compact.
    final limit = full ? 2400 : 220;
    final firstHit = pattern.firstMatch(value)?.start ?? 0;
    final start =
        value.length <= limit ? 0 : (firstHit - 40).clamp(0, value.length);
    final end = (start + limit).clamp(0, value.length);
    final text =
        '${start > 0 ? '…' : ''}${value.substring(start, end)}${end < value.length ? '…' : ''}';
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              fontWeight: FontWeight.w600)));
      cursor = match.end;
    }
    spans.add(TextSpan(text: text.substring(cursor)));
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(_highlight(context, line.text)),
        if (line.translation?.isNotEmpty == true)
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text.rich(_highlight(context, line.translation!),
                  style: Theme.of(context).textTheme.bodySmall)),
      ]);
}
