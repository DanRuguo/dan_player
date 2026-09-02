import 'package:dan_player/component/app_presentation.dart';
import 'dart:typed_data';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/online/online_artwork_request.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';
import 'package:dan_player/component/online_source_display.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class OnlineMetadataSelection {
  const OnlineMetadataSelection(
      {this.title, this.artist, this.album, this.artworkPng});
  final String? title;
  final String? artist;
  final String? album;
  final Uint8List? artworkPng;
}

typedef OnlineMetadataCandidateSearch = Future<OnlineSearchResponse> Function(
    String query);

String onlineMetadataQuery(Audio audio, {String? title, String? artist}) {
  bool meaningful(String? value) =>
      value != null &&
      value.trim().isNotEmpty &&
      !const {'UNKNOWN', '未知', '未知艺术家', '未知专辑'}
          .contains(value.trim().toUpperCase());
  final name = meaningful(title ?? audio.title)
      ? (title ?? audio.title).trim()
      : audio.fileNameTitle;
  final performer = artist ?? audio.artist;
  return [
    canonicalSongTitleForMatch(name),
    if (meaningful(performer)) performer.trim(),
  ].join(' ');
}

Future<OnlineMetadataSelection?> showOnlineMetadataLookupDialog(
  BuildContext context, {
  required Audio audio,
  String? title,
  String? artist,
  OnlineMetadataCandidateSearch? search,
}) =>
    showAppDialog<OnlineMetadataSelection>(
      context: context,
      builder: (_) => _OnlineMetadataLookupDialog(
        audio: audio,
        query: onlineMetadataQuery(audio, title: title, artist: artist),
        search: search,
      ),
    );

class _OnlineMetadataLookupDialog extends StatefulWidget {
  const _OnlineMetadataLookupDialog({
    required this.audio,
    required this.query,
    this.search,
  });
  final Audio audio;
  final String query;
  final OnlineMetadataCandidateSearch? search;

  @override
  State<_OnlineMetadataLookupDialog> createState() =>
      _OnlineMetadataLookupDialogState();
}

class _OnlineMetadataLookupDialogState
    extends State<_OnlineMetadataLookupDialog> {
  late final _query = TextEditingController(text: widget.query);
  final _controlsScroll = ScrollController();
  final _resultsScroll = ScrollController();
  List<Audio> _results = [];
  Audio? _selected;
  bool _loading = false;
  bool _loadingMetadata = false;
  bool _applying = false;
  bool _closed = false;
  bool _title = true;
  bool _artist = true;
  bool _album = true;
  bool _cover = true;
  int _searchToken = 0;
  String? _error;
  Map<String, String> _partialFailures = const {};
  OnlineArtworkRequest? _artworkRequest;
  OnlineSearchCancellation? _searchCancellation;
  CustomMusicSourceCancellation? _metadataCancellation;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    if (_closed || _query.text.trim().isEmpty || _applying) return;
    _searchCancellation?.cancel();
    _metadataCancellation?.cancel();
    _metadataCancellation = null;
    _loadingMetadata = false;
    final cancellation = OnlineSearchCancellation();
    _searchCancellation = cancellation;
    final token = ++_searchToken;
    if (_resultsScroll.hasClients) _resultsScroll.jumpTo(0);
    setState(() {
      _loading = true;
      _error = null;
      _partialFailures = const {};
      _selected = null;
      _results = [];
    });
    try {
      final submittedQuery = _query.text.trim();
      Future<OnlineSearchResponse> search(String query) =>
          widget.search?.call(query) ??
          OnlineMusicService.instance.search(
            query,
            limit: 20,
            cancellation: cancellation,
          );
      var results = await search(submittedQuery);
      if (results.tracks.isEmpty && submittedQuery == widget.query.trim()) {
        final failures = Map<String, String>.of(results.failures);
        for (final fallback in songMatchSearchQueries(widget.audio).skip(1)) {
          if (!mounted || _closed || token != _searchToken) return;
          final fallbackResults = await search(fallback);
          failures.addAll(fallbackResults.failures);
          results = OnlineSearchResponse(
            tracks: fallbackResults.tracks,
            failures: failures,
          );
          if (results.tracks.isNotEmpty) break;
        }
      }
      if (!mounted || _closed || token != _searchToken) return;
      final ranked = List<Audio>.of(results.tracks)
        ..sort((left, right) => computeSongMatchScore(
              widget.audio,
              right.title,
              right.artist,
              right.album,
            ).compareTo(computeSongMatchScore(
              widget.audio,
              left.title,
              left.artist,
              left.album,
            )));
      setState(() {
        _results = ranked;
        _partialFailures = Map<String, String>.unmodifiable(results.failures);
      });
    } catch (error, trace) {
      LOGGER.e('[metadata lookup] $error', stackTrace: trace);
      if (mounted && !_closed && token == _searchToken) {
        setState(() => _error = error is OnlineMusicException
            ? ui(error.message)
            : ui("搜索失败，请检查网络后重试"));
      }
    } finally {
      if (identical(_searchCancellation, cancellation)) {
        _searchCancellation = null;
      }
      if (mounted && !_closed && token == _searchToken) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _selectCandidate(Audio candidate) async {
    if (_closed || _applying) return;
    _metadataCancellation?.cancel();
    final cancellation = CustomMusicSourceCancellation();
    _metadataCancellation = cancellation;
    final custom = CustomMusicSourceProfile.profileIdFromProvider(
            candidate.onlineProvider) !=
        null;
    setState(() {
      _selected = candidate;
      _error = null;
      _loadingMetadata = custom;
    });
    if (!custom) return;
    bool active() =>
        mounted &&
        !_closed &&
        identical(_metadataCancellation, cancellation) &&
        !cancellation.isCancelled;
    try {
      final detailed = await OnlineMusicService.instance
          .refreshMetadata(candidate, cancellation: cancellation);
      if (active()) setState(() => _selected = detailed);
    } catch (_) {
      if (active()) {
        setState(() => _error = ui('补充歌曲信息失败，可重选候选后重试。'));
      }
    } finally {
      if (active()) setState(() => _loadingMetadata = false);
    }
  }

  Future<void> _apply() async {
    final selected = _selected;
    if (_closed || selected == null || _applying || _loadingMetadata) return;
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      Uint8List? artwork;
      if (_cover && selected.artworkUrl?.isNotEmpty == true) {
        final request = OnlineArtworkRequest();
        _artworkRequest = request;
        artwork = await request.loadPng(
          selected.artworkUrl!,
          provider: selected.onlineProvider,
        );
      }
      if (!mounted || _closed) return;
      Navigator.pop(
          context,
          OnlineMetadataSelection(
            title: _title ? selected.title : null,
            artist: _artist ? selected.artist : null,
            album: _album ? selected.album : null,
            artworkPng: artwork,
          ));
    } catch (error, trace) {
      LOGGER.e('[metadata artwork] $error', stackTrace: trace);
      if (mounted && !_closed) {
        setState(() => _error = ui("封面获取失败。可取消勾选“封面”后继续填入文字信息。"));
      }
    } finally {
      _artworkRequest = null;
      if (mounted && !_closed) setState(() => _applying = false);
    }
  }

  @override
  void dispose() {
    _closed = true;
    _searchToken++;
    _searchCancellation?.cancel();
    _metadataCancellation?.cancel();
    _artworkRequest?.cancel();
    _query.dispose();
    _controlsScroll.dispose();
    _resultsScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final selectedHasCover = _selected?.artworkUrl?.isNotEmpty == true;
    return PopScope<OnlineMetadataSelection>(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        // A popped route stays mounted during its exit animation. Cancel now
        // so a late artwork response cannot pop the editor underneath it.
        _closed = true;
        _searchToken++;
        _searchCancellation?.cancel();
        _artworkRequest?.cancel();
      },
      child: Dialog(
        child: SizedBox(
          width: 740,
          height: (MediaQuery.sizeOf(context).height - 64).clamp(300, 700),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(builder: (context, constraints) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Controls keep their own viewport when results
                          // arrive. In a short window they scroll independently
                          // instead of disappearing after the candidate list.
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: constraints.maxHeight * .65,
                            ),
                            child: Scrollbar(
                              controller: _controlsScroll,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                key: const ValueKey('metadata-lookup-controls'),
                                controller: _controlsScroll,
                                primary: false,
                                padding: const EdgeInsets.only(right: 12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    AppDialogTitle(ui("联网查找歌曲信息与封面"),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                    const SizedBox(height: 12),
                                    Row(children: [
                                      Expanded(
                                          child: TextField(
                                        key: const ValueKey(
                                            'metadata-lookup-query'),
                                        controller: _query,
                                        enabled: !_applying,
                                        onSubmitted: (_) => _search(),
                                        decoration: InputDecoration(
                                            labelText: ui("歌曲名 / 艺术家"),
                                            border: AppShape.inputBorder),
                                      )),
                                      const SizedBox(width: 8),
                                      IconButton.filledTonal(
                                          key: const ValueKey(
                                              'metadata-lookup-search'),
                                          onPressed: _loading || _applying
                                              ? null
                                              : _search,
                                          tooltip: ui("搜索"),
                                          icon: const Icon(Symbols.search)),
                                    ]),
                                    const SizedBox(height: 8),
                                    Wrap(spacing: 8, runSpacing: 4, children: [
                                      FilterChip(
                                          label: Text(ui("标题")),
                                          selected: _title,
                                          onSelected: _applying
                                              ? null
                                              : (value) => setState(
                                                  () => _title = value)),
                                      FilterChip(
                                          label: Text(ui("艺术家")),
                                          selected: _artist,
                                          onSelected: _applying
                                              ? null
                                              : (value) => setState(
                                                  () => _artist = value)),
                                      FilterChip(
                                          label: Text(ui("专辑")),
                                          selected: _album,
                                          onSelected: _applying
                                              ? null
                                              : (value) => setState(
                                                  () => _album = value)),
                                      FilterChip(
                                          label: Text(ui("封面")),
                                          tooltip: selectedHasCover
                                              ? ui("填入候选封面")
                                              : ui("候选未提供封面"),
                                          selected: _cover && selectedHasCover,
                                          onSelected:
                                              _applying || !selectedHasCover
                                                  ? null
                                                  : (value) => setState(
                                                      () => _cover = value)),
                                    ]),
                                    const SizedBox(height: 6),
                                    Text(ui("选中候选结果后仅填入编辑器；点击“保存”才会写入本地文件。")),
                                    if (_error != null ||
                                        _partialFailures.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: Text(
                                            _error ??
                                                _onlineFailureSummary(
                                                    _partialFailures),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                TextStyle(color: scheme.error)),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                              child: Scrollbar(
                            controller: _resultsScroll,
                            thumbVisibility: true,
                            child: ListView.builder(
                              key: const ValueKey('metadata-lookup-results'),
                              controller: _resultsScroll,
                              primary: false,
                              padding: const EdgeInsets.only(right: 12),
                              // Empty/error/loading states use the same independent
                              // list viewport and never change controls' placement.
                              itemCount: _loading || _results.isEmpty
                                  ? 1
                                  : _results.length,
                              itemBuilder: (context, index) {
                                if (_loading || _results.isEmpty) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: Center(
                                        child: _loading
                                            ? const SizedBox.square(
                                                dimension: 24,
                                                child:
                                                    CircularProgressIndicator())
                                            : Text(ui("没有找到候选结果，可修改关键词后重试"))),
                                  );
                                }
                                final item = _results[index];
                                final selected = _selected?.path == item.path;
                                return ListTile(
                                  key: ValueKey(
                                      'metadata-candidate-${item.path}'),
                                  selected: selected,
                                  selectedTileColor: scheme.secondaryContainer,
                                  shape: AppShape.control,
                                  enabled: !_applying,
                                  onTap: () => _selectCandidate(item),
                                  leading: ClipRRect(
                                    borderRadius: AppShape.smallRadius,
                                    child: AudioArtwork(
                                      audio: item,
                                      placeholder: const Icon(Symbols.album),
                                    ),
                                  ),
                                  title: Text(item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                      '${item.artist} · ${item.album}\n${onlineSourceDisplayLabel(provider: item.onlineProvider, fallback: item.sourceLabel)} · ${item.duration ~/ 60}:${(item.duration % 60).toString().padLeft(2, '0')}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  trailing: Icon(selected
                                      ? Symbols.check_circle
                                      : Symbols.radio_button_unchecked),
                                );
                              },
                            ),
                          )),
                        ],
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  OverflowBar(
                      alignment: MainAxisAlignment.end,
                      overflowAlignment: OverflowBarAlignment.end,
                      spacing: 12,
                      overflowSpacing: 4,
                      children: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(ui("取消"))),
                        FilledButton.icon(
                            onPressed: _selected == null ||
                                    _loadingMetadata ||
                                    _applying ||
                                    !(_title ||
                                        _artist ||
                                        _album ||
                                        (_cover && selectedHasCover))
                                ? null
                                : _apply,
                            icon: _applying || _loadingMetadata
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Symbols.download_done),
                            label: Text(_loadingMetadata
                                ? ui('读取歌曲信息…')
                                : _applying
                                    ? ui("获取封面…")
                                    : ui("填入编辑器"))),
                      ]),
                ]),
          ),
        ),
      ),
    );
  }
}

String _onlineFailureSummary(Map<String, String> failures) => failures.entries
    .map((entry) =>
        '${onlineSourceDisplayLabel(provider: entry.key, fallback: entry.key)}：${ui(entry.value)}')
    .join('；');
