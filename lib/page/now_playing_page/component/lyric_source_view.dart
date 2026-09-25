import 'dart:convert';
import 'dart:collection';
import 'package:dan_player/lyric/lyric_lookup_status.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_scrollbar.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/lyric/lyric_source_exception.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_candidate_tile.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:desktop_lyric/app_motion.dart';

class SetLyricSourceBtn extends StatelessWidget {
  const SetLyricSourceBtn({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
      listenable: PlayService.instance.lyricService,
      builder: (context, _) => FutureBuilder(
        future: PlayService.instance.lyricService.currLyricFuture,
        builder: (context, snapshot) {
          final audio = PlayService.instance.playbackService.nowPlaying;
          final lyricNullable = snapshot.connectionState == ConnectionState.done
              ? snapshot.data
              : null;
          final isLocal = lyricNullable == null
              ? null
              : (lyricNullable is Lrc &&
                  lyricNullable.source == LrcSource.local);
          // A slow automatic lyric lookup must never prevent manual selection.
          return LyricSourceMenuButton(
            enabled: audio != null,
            showLocal: audio?.isLocal == true && audio?.isCueTrack != true,
            isLocal: isLocal,
            onChooseDefault: () {
              final selectedAudio =
                  PlayService.instance.playbackService.nowPlaying;
              if (selectedAudio == null) return;
              showAppDialog<String>(
                context: context,
                builder: (context) => LyricSourceDialog(audio: selectedAudio),
              );
            },
            onOnline: PlayService.instance.lyricService.useOnlineLyric,
            onLocal: PlayService.instance.lyricService.useLocalLyric,
          );
        },
      ),
    );
  }
}

class LyricSourceMenuButton extends StatelessWidget {
  const LyricSourceMenuButton({
    super.key,
    required this.enabled,
    required this.showLocal,
    required this.isLocal,
    required this.onChooseDefault,
    required this.onOnline,
    required this.onLocal,
  });

  final bool enabled;
  final bool showLocal;
  final bool? isLocal;
  final VoidCallback onChooseDefault;
  final VoidCallback onOnline;
  final VoidCallback onLocal;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      useRootOverlay: true,
      consumeOutsideTap: true,
      style: const MenuStyle(
        shape: WidgetStatePropertyAll(AppShape.control),
        minimumSize: WidgetStatePropertyAll(Size(220, 0)),
        maximumSize: WidgetStatePropertyAll(Size(320, double.infinity)),
      ),
      onOpen: () {
        ALWAYS_SHOW_LYRIC_VIEW_CONTROLS = true;
      },
      onClose: () {
        ALWAYS_SHOW_LYRIC_VIEW_CONTROLS = false;
      },
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('lyric-source-choose-default'),
          onPressed: onChooseDefault,
          leadingIcon: const Icon(Symbols.search),
          child: Text(
            ui("指定默认歌词"),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        MenuItemButton(
          key: const ValueKey('lyric-source-online'),
          onPressed: onOnline,
          leadingIcon: const Icon(Symbols.cloud),
          trailingIcon:
              isLocal == false ? const Icon(Symbols.check, size: 20) : null,
          child: Text(ui("在线")),
        ),
        if (showLocal)
          MenuItemButton(
            key: const ValueKey('lyric-source-local-menu-item'),
            onPressed: onLocal,
            leadingIcon: const Icon(Symbols.folder),
            trailingIcon:
                isLocal == true ? const Icon(Symbols.check, size: 20) : null,
            child: Text(ui("本地")),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        key: const ValueKey('lyric-source-menu-button'),
        onPressed: !enabled
            ? null
            : () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
        tooltip: ui("选择歌词来源"),
        icon: const Icon(Symbols.lyrics),
        color: scheme.primary,
      ),
    );
  }
}

typedef LyricCandidateSearchCallback = Future<LyricSearchResponse> Function(
  Audio audio,
);
typedef LyricCandidateProgressSearchCallback = Future<LyricSearchResponse>
    Function(Audio audio, void Function(LyricSearchResponse) onProgress);
typedef LyricCandidateLoadCallback = Future<Lyric?> Function(
  SongSearchResult candidate,
);
typedef LyricSourcePersistCallback = Future<void> Function(
  String audioPath,
  LyricSource source,
);
typedef LyricCandidateApplyCallback = bool Function(
  String expectedTrackPath,
  Lyric lyric,
);
typedef LocalLyricApplyCallback = bool Function(String expectedTrackPath);

bool lyricCandidateMayUseDifferentVersion(
    Audio audio, SongSearchResult candidate) {
  final shortVersion = RegExp(
      r'\bshort(?:\s*ver\.?)?|\btv\s*(?:size|ver\.?)|ショート|短版',
      caseSensitive: false);
  return shortVersion.hasMatch(audio.title) &&
      !shortVersion.hasMatch(candidate.title);
}

/// The dialog owns one search generation. It never creates a network Future in
/// build, and a selected lyric is committed only if the captured song is still
/// current after the download and source save have both completed.
class LyricSourceDialog extends StatefulWidget {
  const LyricSourceDialog({
    super.key,
    required this.audio,
    this.search,
    this.searchWithProgress,
    this.loadCandidate,
    this.persistSource,
    this.applyCandidate,
    this.applyLocal,
    this.currentTrackPath,
    this.playbackListenable,
    this.positionStream,
    this.readPosition,
  });

  final Audio audio;
  final LyricCandidateSearchCallback? search;
  final LyricCandidateProgressSearchCallback? searchWithProgress;
  final LyricCandidateLoadCallback? loadCandidate;
  final LyricSourcePersistCallback? persistSource;
  final LyricCandidateApplyCallback? applyCandidate;
  final LocalLyricApplyCallback? applyLocal;
  final String? Function()? currentTrackPath;
  final Listenable? playbackListenable;
  final Stream<double>? positionStream;
  final double Function()? readPosition;

  @override
  State<LyricSourceDialog> createState() => _LyricSourceDialogState();
}

class _LyricSourceDialogState extends State<LyricSourceDialog> {
  LyricSearchResponse? _response;
  String? _responseTrackId;
  bool _searching = true;
  bool _closed = false;
  bool _trackChanged = false;
  int _searchGeneration = 0;
  int _selectionGeneration = 0;
  String Function()? _searchError;
  String Function()? _operationError;
  String? _loadingCandidate;
  // Cache message sources, not already-translated text. Switching UI language
  // must not restart lyric lookup or change the captured track/provider IDs.
  final Map<String, String Function()> _candidateErrors = {};
  Listenable? _playbackListenable;
  final ScrollController _scrollController = ScrollController();
  final Map<String, _QueuedLyricPreview> _previews = {};
  final Queue<_QueuedLyricPreview> _previewQueue = Queue();
  final Map<String, int> _previewRevisions = {};
  int _activePreviewLoads = 0;
  int _previewGeneration = 0;
  LyricSearchCancellation? _searchCancellation;
  bool _searchStopped = false;
  bool _previewQueueStopped = false;

  Stream<double> get _positionStream =>
      widget.positionStream ??
      (widget.currentTrackPath != null
          ? const Stream<double>.empty()
          : PlayService.instance.playbackService.positionStream);
  double _readPosition() =>
      widget.readPosition?.call() ??
      (widget.currentTrackPath != null
          ? 0
          : PlayService.instance.playbackService.position);

  void _clearPreviews() {
    _previewGeneration++;
    for (final job in _previews.values) {
      job.timeoutTimer?.cancel();
      job.done = true;
      if (!job.completer.isCompleted) job.completer.complete(null);
    }
    _previewQueue.clear();
    _previews.clear();
    _previewRevisions.clear();
    _activePreviewLoads = 0;
  }

  Future<Lyric?> _candidateLyric(SongSearchResult candidate,
      {bool priority = false, bool retryFailed = false}) {
    if (_previewQueueStopped && !priority) return Future.value(null);
    final identity = candidate.identity;
    var job = _previews[identity];
    if (retryFailed && job?.done == true && job?.failed == true) {
      _previews.remove(identity);
      job = null;
    }
    if (job == null) {
      job = _QueuedLyricPreview(candidate, _previewGeneration);
      _previews[identity] = job;
      // Metadata-only custom candidates already carry parsed lyrics.
      if (priority || candidate.previewLyric != null) {
        _startPreview(job);
      } else {
        _previewQueue.add(job);
        _pumpPreviewQueue();
      }
    } else if (priority && !job.started) {
      _previewQueue.remove(job);
      _startPreview(job);
    }
    _previews.remove(identity);
    _previews[identity] = job;
    return job.completer.future;
  }

  void _releaseCandidatePreview(String identity) {
    final job = _previews[identity];
    if (job == null ||
        job.started ||
        job.done ||
        _loadingCandidate == identity) {
      return;
    }
    _previewQueue.remove(job);
    _previews.remove(identity);
    job.done = true;
    if (!job.completer.isCompleted) job.completer.complete(null);
  }

  void _pumpPreviewQueue() {
    while (!_previewQueueStopped &&
        _activePreviewLoads < 2 &&
        _previewQueue.isNotEmpty) {
      final job = _previewQueue.removeFirst();
      if (job.generation == _previewGeneration) _startPreview(job);
    }
  }

  void _startPreview(_QueuedLyricPreview job) {
    if (job.started) return;
    job.started = true;
    _activePreviewLoads++;
    void finish() {
      if (job.generation != _previewGeneration) return;
      _activePreviewLoads--;
      _trimPreviewCache();
      _pumpPreviewQueue();
    }

    job.timeoutTimer = Timer(const Duration(seconds: 12), () {
      if (job.done) return;
      job.done = true;
      job.failed = true;
      job.completer.completeError(TimeoutException('lyric preview timeout'));
      finish();
    });
    Future.sync(() {
      // Injected track identity is a widget-test seam. Its synthetic search
      // results must not cause real provider traffic unless a loader is given.
      if (widget.currentTrackPath != null && widget.loadCandidate == null) {
        return Future<Lyric?>.value(null);
      }
      return (widget.loadCandidate ?? getLyricForCandidate)(job.candidate);
    }).then((lyric) {
      if (job.done) return;
      job.timeoutTimer?.cancel();
      job.done = true;
      job.failed = lyric == null || lyric.lines.isEmpty;
      if (!job.completer.isCompleted) job.completer.complete(lyric);
      finish();
    }, onError: (Object error, StackTrace stack) {
      if (job.done) return;
      job.timeoutTimer?.cancel();
      job.done = true;
      job.failed = true;
      if (!job.completer.isCompleted) {
        job.completer.completeError(error, stack);
      }
      finish();
    });
  }

  void _trimPreviewCache() {
    if (_previews.length <= 16) return;
    for (final entry in _previews.entries.toList(growable: false)) {
      if (_previews.length <= 16) break;
      if (entry.value.done && entry.key != _loadingCandidate) {
        _previews.remove(entry.key);
      }
    }
  }

  void _stopSearchForSelection() {
    if (_searching) {
      _searchCancellation?.cancel();
      _searchGeneration++;
      _searching = false;
      _searchStopped = true;
    }
    _previewQueueStopped = true;
    for (final job in _previewQueue) {
      job.done = true;
      if (!job.completer.isCompleted) job.completer.complete(null);
      _previews.remove(job.candidate.identity);
    }
    _previewQueue.clear();
  }

  bool get _usingSavedDraft {
    final document = LyricDocumentStore.instance.forAudio(widget.audio);
    return document?.edited != null &&
        document?.draft != null &&
        jsonEncode(document!.edited!.toJson()) ==
            jsonEncode(document.draft!.toJson());
  }

  String? _currentTrackPath() =>
      widget.currentTrackPath?.call() ??
      PlayService.instance.playbackService.nowPlaying?.path;

  @override
  void initState() {
    super.initState();
    _playbackListenable = widget.playbackListenable ??
        (widget.currentTrackPath == null
            ? PlayService.instance.playbackService
            : null);
    _playbackListenable?.addListener(_handlePlaybackChange);
    _trackChanged = _currentTrackPath() != widget.audio.path;
    if (_trackChanged) {
      _searching = false;
    } else {
      unawaited(_search());
    }
  }

  @override
  void didUpdateWidget(covariant LyricSourceDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackListenable != widget.playbackListenable ||
        oldWidget.currentTrackPath != widget.currentTrackPath) {
      _playbackListenable?.removeListener(_handlePlaybackChange);
      _playbackListenable = widget.playbackListenable ??
          (widget.currentTrackPath == null
              ? PlayService.instance.playbackService
              : null);
      _playbackListenable?.addListener(_handlePlaybackChange);
    }
    if (oldWidget.audio.path != widget.audio.path ||
        oldWidget.search != widget.search ||
        oldWidget.searchWithProgress != widget.searchWithProgress) {
      _selectionGeneration++;
      unawaited(_search());
    }
    _handlePlaybackChange();
  }

  void _handlePlaybackChange() {
    final changed = _currentTrackPath() != widget.audio.path;
    if (_trackChanged == changed) return;
    _selectionGeneration++;
    if (changed) {
      _searchCancellation?.cancel();
      _searchGeneration++;
      _searching = false;
      _searchStopped = false;
      _previewQueueStopped = true;
      _clearPreviews();
    }
    if (mounted) {
      setState(() {
        _trackChanged = changed;
        if (changed) _loadingCandidate = null;
      });
    }
    if (!changed) unawaited(_search());
  }

  Future<void> _search() async {
    if (_trackChanged) return;
    _searchCancellation?.cancel();
    final cancellation = LyricSearchCancellation();
    _searchCancellation = cancellation;
    final generation = ++_searchGeneration;
    _selectionGeneration++;
    final preserveCandidates =
        _response != null && _responseTrackId == widget.audio.stableTrackId;
    final oldCandidates =
        preserveCandidates ? _response!.candidates : const <SongSearchResult>[];
    _searchStopped = false;
    _previewQueueStopped = false;
    if (!preserveCandidates) {
      _clearPreviews();
    } else {
      for (final candidate in oldCandidates) {
        final job = _previews[candidate.identity];
        if (job == null || job.failed) {
          _previews.remove(candidate.identity);
          _previewRevisions.update(candidate.identity, (value) => value + 1,
              ifAbsent: () => 1);
        }
      }
    }
    if (mounted) {
      setState(() {
        _searching = true;
        _searchError = null;
        _operationError = null;
        _response = preserveCandidates
            ? LyricSearchResponse(
                candidates: oldCandidates,
                failures: const {},
              )
            : null;
        _loadingCandidate = null;
        _candidateErrors.clear();
      });
    }
    try {
      void onProgress(LyricSearchResponse result) {
        if (!_isSearchCurrent(generation)) return;
        setState(() {
          final candidates = _mergeCandidates(oldCandidates, result.candidates);
          _response = LyricSearchResponse(
            candidates: candidates,
            failures: result.failures,
            customFailures: result.customFailures,
            sourcesDisabled: result.sourcesDisabled && candidates.isEmpty,
          );
          _responseTrackId = widget.audio.stableTrackId;
        });
      }

      final result = await (widget.searchWithProgress != null
          ? widget.searchWithProgress!(widget.audio, onProgress)
          : widget.search != null
              ? widget.search!(widget.audio)
              : searchManualLyricCandidates(widget.audio,
                  onProgress: onProgress, cancellation: cancellation));
      if (!_isSearchCurrent(generation)) return;
      setState(() {
        final candidates = _mergeCandidates(oldCandidates, result.candidates);
        _response = LyricSearchResponse(
            candidates: candidates,
            failures: result.failures,
            customFailures: result.customFailures,
            sourcesDisabled: result.sourcesDisabled && candidates.isEmpty);
        _responseTrackId = widget.audio.stableTrackId;
        _searching = false;
      });
    } catch (_) {
      if (!_isSearchCurrent(generation)) return;
      setState(() {
        _searching = false;
        _searchError = () => ui("搜索歌词候选失败，请检查网络后重试。");
      });
    }
  }

  List<SongSearchResult> _mergeCandidates(
      Iterable<SongSearchResult> prior, Iterable<SongSearchResult> fresh) {
    final byIdentity = <String, SongSearchResult>{
      for (final candidate in prior) candidate.identity: candidate,
      for (final candidate in fresh) candidate.identity: candidate,
    };
    return visibleManualLyricCandidates(byIdentity.values);
  }

  bool _isSearchCurrent(int generation) =>
      mounted && !_closed && generation == _searchGeneration;

  bool _isSelectionCurrent(int generation) =>
      mounted && !_closed && generation == _selectionGeneration;

  Future<void> _selectDraft() async {
    if (_trackChanged || _loadingCandidate != null) return;
    final generation = ++_selectionGeneration;
    _stopSearchForSelection();
    final store = LyricDocumentStore.instance;
    final revision = store.revisionFor(widget.audio);
    setState(() {
      _loadingCandidate = 'draft';
      _operationError = null;
    });
    try {
      await store.useDraft(widget.audio,
          expectedRevision: revision,
          stillCurrent: () =>
              _isSelectionCurrent(generation) &&
              !_trackChanged &&
              _currentTrackPath() == widget.audio.path);
      if (mounted && _isSelectionCurrent(generation)) Navigator.pop(context);
    } catch (_) {
      if (_isSelectionCurrent(generation)) {
        setState(() =>
            _operationError = () => ui('歌词已被另一操作修改，旧结果未覆盖当前版本，请重新打开后重试。'));
      }
    } finally {
      if (mounted && generation == _selectionGeneration) {
        setState(() => _loadingCandidate = null);
      }
    }
  }

  Future<void> _selectLocal() async {
    if (_trackChanged || _loadingCandidate != null) return;
    final generation = ++_selectionGeneration;
    _stopSearchForSelection();
    setState(() {
      _loadingCandidate = 'local';
      _operationError = null;
    });
    try {
      if (widget.persistSource == null) {
        final store = LyricDocumentStore.instance;
        final revision = store.revisionFor(widget.audio);
        final service = PlayService.instance.lyricService;
        final session = service.resolutionGeneration;
        bool stillCurrent() =>
            _isSelectionCurrent(generation) &&
            service.resolutionGeneration == session;
        final lyric = await Lrc.fromAudioPath(widget.audio);
        if (!stillCurrent() || _currentTrackPath() != widget.audio.path) {
          return;
        }
        if (lyric == null || lyric.lines.isEmpty) {
          setState(() => _operationError = () => ui('未找到可用的本地歌词，已保留之前保存的版本。'));
          return;
        }
        await store.select(widget.audio, lyric,
            source: LyricSource(LyricSourceType.local),
            expectedRevision: revision,
            stillCurrent: stillCurrent);
        if (!_isSelectionCurrent(generation)) return;
        if (mounted) Navigator.of(context).pop();
        return;
      }
      await (widget.persistSource ?? persistLyricSource)(
        widget.audio.path,
        LyricSource(LyricSourceType.local),
      );
      if (!_isSelectionCurrent(generation)) return;
      final applied = (widget.applyLocal ??
          PlayService.instance.lyricService.useLocalLyricForTrack)(
        widget.audio.path,
      );
      if (!applied) {
        _markTrackChanged(() => ui("歌曲已切换；已保存原歌曲的歌词来源，但没有应用到当前歌曲。"));
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (_isSelectionCurrent(generation)) {
        setState(() => _operationError = () => ui("保存本地歌词来源失败，旧设置已保留，请重试。"));
      }
    } finally {
      if (_isSelectionCurrent(generation)) {
        setState(() => _loadingCandidate = null);
      }
    }
  }

  Future<void> _selectCandidate(SongSearchResult candidate) async {
    if (_trackChanged || _loadingCandidate == candidate.identity) return;
    final generation = ++_selectionGeneration;
    final wasFailed = _previews[candidate.identity]?.failed == true;
    final request =
        _candidateLyric(candidate, priority: true, retryFailed: true);
    _stopSearchForSelection();
    setState(() {
      _loadingCandidate = candidate.identity;
      _operationError = null;
      _candidateErrors.remove(candidate.identity);
      if (wasFailed) {
        _previewRevisions.update(candidate.identity, (value) => value + 1,
            ifAbsent: () => 1);
      }
    });
    var stage =
        0; // Fetch, persist, then apply have different recovery actions.
    final documentRevision = widget.persistSource == null
        ? LyricDocumentStore.instance.revisionFor(widget.audio)
        : null;
    final session =
        widget.persistSource == null && widget.currentTrackPath == null
            ? PlayService.instance.lyricService.resolutionGeneration
            : null;
    bool stillCurrent() =>
        _isSelectionCurrent(generation) &&
        (session == null ||
            PlayService.instance.lyricService.resolutionGeneration == session);
    try {
      final lyric = await request;
      if (!stillCurrent()) return;
      if (_currentTrackPath() != widget.audio.path) {
        _markTrackChanged(() => ui("歌曲已切换，旧歌曲的候选没有应用。"));
        return;
      }
      if (lyric == null || lyric.lines.isEmpty) {
        setState(() => _candidateErrors[candidate.identity] =
            () => ui("{0}未返回可用歌词，可选择其他候选或重试。", [ui(candidate.sourceLabel)]));
        return;
      }
      final source = _sourceFor(candidate);
      stage = 1;
      if (widget.persistSource != null && source != null) {
        await widget.persistSource!(widget.audio.path, source);
      } else {
        await LyricDocumentStore.instance.select(widget.audio, lyric,
            source: source,
            expectedRevision: documentRevision,
            stillCurrent: stillCurrent);
      }
      if (!_isSelectionCurrent(generation)) return;
      stage = 2;
      final applied = widget.persistSource == null
          ? _currentTrackPath() == widget.audio.path
          : (widget.applyCandidate ??
              PlayService.instance.lyricService.useSpecificLyricForTrack)(
              widget.audio.path,
              lyric,
            );
      if (!applied) {
        _markTrackChanged(() => ui("歌曲已切换；已保存原歌曲的歌词来源，但没有应用到当前歌曲。"));
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (_isSelectionCurrent(generation)) {
        final message = error is InstrumentalLyric
            ? InstrumentalLyric.message
            : error is StaleLyricRevision
                ? error.toString()
                : stage == 1
                    ? '歌词已获取，但保存来源失败；旧设置已保留，请检查数据目录权限后重试。'
                    : stage == 2
                        ? '歌词来源已保存，但未能应用；请重新打开当前歌曲后重试。'
                        : error is LyricUnavailableException
                            ? '此来源暂未提供这条录音的可用歌词，请选择其他候选。'
                            : error is TimeoutException
                                ? '获取歌词超时，请重试或选择其他候选。'
                                : error is SocketException ||
                                        error is HandshakeException ||
                                        error is HttpException
                                    ? '连接歌词来源失败，请检查网络或代理后重试。'
                                    : error is FormatException
                                        ? '歌词来源返回的内容无法解析，请重试或选择其他候选。'
                                        : '获取歌词失败，可选择其他候选或重试。';
        setState(
            () => _candidateErrors[candidate.identity] = () => ui(message));
      }
    } finally {
      if (_isSelectionCurrent(generation)) {
        setState(() => _loadingCandidate = null);
      }
    }
  }

  void _markTrackChanged(String Function() message) {
    _selectionGeneration++;
    if (!mounted || _closed) return;
    setState(() {
      _trackChanged = true;
      _loadingCandidate = null;
      _operationError = message;
    });
  }

  LyricSource? _sourceFor(SongSearchResult candidate) =>
      candidate.customProfile != null &&
              (candidate.customProfile!.id != 'kugou' ||
                  candidate.kugouSongHash == null)
          ? null
          : switch (candidate.source) {
              ResultSource.qq => LyricSource(
                  LyricSourceType.qq,
                  qqSongId: candidate.qqSongId,
                  qqSongMid: candidate.qqSongMid,
                ),
              ResultSource.kugou => LyricSource(
                  LyricSourceType.kugou,
                  kugouSongHash: candidate.kugouSongHash,
                ),
              ResultSource.netease => LyricSource(
                  LyricSourceType.netease,
                  neteaseSongId: candidate.neteaseSongId,
                ),
              ResultSource.lrclib => LyricSource(
                  LyricSourceType.lrclib,
                  lrclibId: candidate.lrclibId,
                ),
            };

  bool _isCurrentCandidate(SongSearchResult candidate) {
    final configured =
        LyricDocumentStore.instance.forAudio(widget.audio)?.source ??
            LYRIC_SOURCES[widget.audio.path];
    if (configured != null) {
      return configured.matches(
        candidateSource: switch (candidate.source) {
          ResultSource.qq => LyricSourceType.qq,
          ResultSource.kugou => LyricSourceType.kugou,
          ResultSource.netease => LyricSourceType.netease,
          ResultSource.lrclib => LyricSourceType.lrclib,
        },
        candidateQqSongId: candidate.qqSongId,
        candidateQqSongMid: candidate.qqSongMid,
        candidateKugouSongHash: candidate.kugouSongHash,
        candidateNeteaseSongId: candidate.neteaseSongId,
        candidateLrclibId: candidate.lrclibId,
      );
    }
    if (!widget.audio.isOnline) return false;
    return switch (candidate.source) {
      ResultSource.qq => widget.audio.onlineProvider == 'qq' &&
          ((widget.audio.onlineNumericId != null &&
                  widget.audio.onlineNumericId == candidate.qqSongId) ||
              widget.audio.onlineId == candidate.qqSongMid),
      ResultSource.netease => widget.audio.onlineProvider == 'netease' &&
          widget.audio.onlineId == candidate.neteaseSongId,
      ResultSource.kugou => false,
      ResultSource.lrclib => false,
    };
  }

  @override
  void dispose() {
    _closed = true;
    _searchCancellation?.cancel();
    _searchGeneration++;
    _selectionGeneration++;
    _clearPreviews();
    _scrollController.dispose();
    _playbackListenable?.removeListener(_handlePlaybackChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final height =
        (MediaQuery.sizeOf(context).height - 48).clamp(320, 680).toDouble();
    final audioMetadata = [
      widget.audio.displayTitle.trim(),
      widget.audio.artist.trim(),
      widget.audio.album.trim(),
    ].where((value) => value.isNotEmpty).join(' · ');
    return Dialog(
      child: AppDialogContent(
        width: 620,
        maxHeight: height,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogTitle(
                ui("默认歌词"),
                style: Theme.of(context).textTheme.titleLarge,
                leading: const Icon(Symbols.lyrics),
                trailing: IconButton(
                  key: const ValueKey('lyric-source-close'),
                  tooltip: ui("关闭"),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Symbols.close),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                  child: AppScrollbar(
                      controller: _scrollController,
                      child: CustomScrollView(
                        controller: _scrollController,
                        shrinkWrap: true,
                        key: const ValueKey('lyric-source-scroll'),
                        slivers: [
                          SliverToBoxAdapter(
                              child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Tooltip(
                                message: audioMetadata,
                                child: Text(
                                  audioMetadata,
                                  key: const ValueKey(
                                      'lyric-source-song-metadata'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      TextStyle(color: scheme.onSurfaceVariant),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_trackChanged)
                                _MessagePanel(
                                  key: const ValueKey(
                                      'lyric-source-track-changed'),
                                  message:
                                      ui("当前播放歌曲已经改变。为避免歌词串歌，请关闭后从新歌曲重新选择。"),
                                  color: scheme.errorContainer,
                                ),
                              if (_operationError != null)
                                _MessagePanel(
                                  key: const ValueKey(
                                      'lyric-source-operation-error'),
                                  message: _operationError!(),
                                  color: scheme.errorContainer,
                                ),
                              if (AppSettings.instance.customMusicSources.value
                                  .any(
                                (profile) =>
                                    profile.enabled &&
                                    profile.capabilities.contains(
                                      CustomMusicSourceCapability.lyrics,
                                    ),
                              ))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _MessagePanel(
                                    key: const ValueKey(
                                        'lyric-source-custom-api-note'),
                                    message: ui('候选按匹配度和来源排序；自动选词时，同分优先逐字歌词。'),
                                    color: scheme.secondaryContainer,
                                  ),
                                ),
                              if (widget.audio.isLocal &&
                                  LyricDocumentStore.instance
                                          .forAudio(widget.audio)
                                          ?.draft !=
                                      null)
                                ListTile(
                                    key: const ValueKey('lyric-source-draft'),
                                    enabled: !_trackChanged &&
                                        _loadingCandidate == null,
                                    leading: const Icon(Symbols.edit_note),
                                    title: Text(ui('使用编辑的本地歌词')),
                                    subtitle:
                                        Text(ui('使用已保存的完整编辑副本，保留逐字时间、翻译和注音。')),
                                    trailing: _loadingCandidate == 'draft'
                                        ? SizedBox.square(
                                            dimension: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                value: AppMotion.enabled(
                                                        context,
                                                        MotionKind.feedback)
                                                    ? null
                                                    : .7))
                                        : Icon(_usingSavedDraft
                                            ? Symbols.check_circle
                                            : Symbols.chevron_right),
                                    onTap: _selectDraft),
                              if (widget.audio.isLocal &&
                                  !widget.audio.isCueTrack) ...[
                                ListTile(
                                  key: const ValueKey('lyric-source-local'),
                                  enabled: !_trackChanged,
                                  leading: const Icon(Symbols.folder),
                                  title: Text(ui("使用本地歌词")),
                                  subtitle: Text(ui("读取内嵌歌词或同目录同名 LRC 文件")),
                                  trailing: _loadingCandidate == 'local'
                                      ? SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              value: AppMotion.enabled(context,
                                                      MotionKind.feedback)
                                                  ? null
                                                  : .7),
                                        )
                                      : (LyricDocumentStore.instance
                                                              .forAudio(
                                                                  widget.audio)
                                                              ?.source ??
                                                          LYRIC_SOURCES[widget
                                                              .audio.path])
                                                      ?.source ==
                                                  LyricSourceType.local &&
                                              !_usingSavedDraft
                                          ? const Icon(Symbols.check_circle)
                                          : null,
                                  shape: AppShape.control,
                                  onTap: _selectLocal,
                                ),
                                const Divider(),
                              ],
                            ],
                          )),
                          ..._buildResults(context),
                        ],
                      ))),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildResults(BuildContext context) {
    final response = _response;
    if (_searching && (response == null || response.candidates.isEmpty)) {
      return [
        SliverToBoxAdapter(
            child: Center(
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(
                strokeWidth: 2,
                value: AppMotion.enabled(context, MotionKind.feedback)
                    ? null
                    : .7),
          ),
        ))
      ];
    }
    if (_searchError != null &&
        (response == null || response.candidates.isEmpty)) {
      return [
        SliverToBoxAdapter(
            child: _RetryState(message: _searchError!(), onRetry: _search))
      ];
    }
    if (response == null) {
      return [
        SliverToBoxAdapter(
            child: _RetryState(message: ui("候选状态不可用，请重试。"), onRetry: _search))
      ];
    }
    if (response.sourcesDisabled &&
        !_searching &&
        response.candidates.isEmpty &&
        response.failures.isEmpty &&
        response.customFailures.isEmpty) {
      return [
        SliverToBoxAdapter(
            child: Center(child: Text(ui("当前没有可用的联网歌词来源，请检查歌词与歌源设置。"))))
      ];
    }

    final failureText = [
      for (final entry in response.failures.entries)
        '${ui(entry.key.sourceLabel)}：${ui(entry.value)}',
      for (final entry in response.customFailures.entries)
        '${entry.key}：${ui(entry.value)}',
    ].join('\n');
    return [
      if (_searchError != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MessagePanel(
              key: const ValueKey('lyric-source-search-error'),
              message: _searchError!(),
              color: Theme.of(context).colorScheme.errorContainer,
              action: TextButton.icon(
                key: const ValueKey('lyric-source-retry'),
                onPressed: _loadingCandidate == null && !_trackChanged
                    ? _search
                    : null,
                icon: const Icon(Symbols.refresh),
                label: Text(ui('重试')),
              ),
            ),
          ),
        ),
      if (_searching)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: AppMotion.enabled(context, MotionKind.feedback)
                        ? null
                        : .7),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(ui('正在搜索其他歌词来源…'))),
            ]),
          ),
        ),
      if (_searchStopped)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MessagePanel(
              key: const ValueKey('lyric-source-search-stopped'),
              message: ui('已停止搜索其他来源，当前候选仍可选择。'),
              color: Theme.of(context).colorScheme.secondaryContainer,
              action: TextButton.icon(
                key: const ValueKey('lyric-source-continue-search'),
                onPressed: _loadingCandidate == null && !_trackChanged
                    ? _search
                    : null,
                icon: const Icon(Symbols.refresh),
                label: Text(ui('继续搜索')),
              ),
            ),
          ),
        ),
      if (failureText.isNotEmpty)
        SliverToBoxAdapter(
            child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _MessagePanel(
            key: const ValueKey('lyric-source-partial-failure'),
            message: failureText,
            color: Theme.of(context).colorScheme.errorContainer,
            action: TextButton.icon(
              key: const ValueKey('lyric-source-retry'),
              onPressed:
                  _loadingCandidate == null && !_trackChanged ? _search : null,
              icon: const Icon(Symbols.refresh),
              label: Text(ui("重试")),
            ),
          ),
        )),
      if (response.candidates.isEmpty)
        SliverToBoxAdapter(
            child: Center(
          child: Text(failureText.isEmpty
              ? ui("没有找到相关歌词候选，可检查歌曲标签后重试。")
              : ui("可用来源没有返回候选。")),
        ))
      else
        SliverList.builder(
          key: const ValueKey('lyric-source-candidates'),
          itemCount: response.candidates.length,
          findChildIndexCallback: (key) {
            if (key is! ValueKey<String>) return null;
            final identity = key.value;
            for (var i = 0; i < response.candidates.length; i++) {
              if (identity ==
                  'candidate-row-${response.candidates[i].identity}') {
                return i;
              }
            }
            return null;
          },
          itemBuilder: (context, index) {
            final candidate = response.candidates[index];
            return _candidateTile(candidate);
          },
        ),
    ];
  }

  Widget _candidateTile(SongSearchResult candidate) {
    return LyricCandidateTile(
      key: ValueKey('candidate-row-${candidate.identity}'),
      candidate: candidate,
      audio: widget.audio,
      positionStream: _positionStream,
      readPosition: _readPosition,
      load: _candidateLyric,
      release: _releaseCandidatePreview,
      retryRevision: _previewRevisions[candidate.identity] ?? 0,
      previewGeneration: _previewGeneration,
      versionWarning:
          lyricCandidateMayUseDifferentVersion(widget.audio, candidate),
      enabled: !_trackChanged,
      current: _isCurrentCandidate(candidate),
      loading: _loadingCandidate == candidate.identity,
      error: _candidateErrors[candidate.identity],
      onTap: () => _selectCandidate(candidate),
    );
  }
}

class _QueuedLyricPreview {
  _QueuedLyricPreview(this.candidate, this.generation) {
    // A sliver may dispose an offscreen row while the request is in flight.
    // Selection can still await the same future without a detached error.
    completer.future.ignore();
  }

  final SongSearchResult candidate;
  final int generation;
  final Completer<Lyric?> completer = Completer<Lyric?>();
  bool started = false;
  bool done = false;
  bool failed = false;
  Timer? timeoutTimer;
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    super.key,
    required this.message,
    required this.color,
    this.action,
  });

  final String message;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppShape.controlRadius,
      ),
      child: Row(children: [
        Expanded(child: Text(message)),
        if (action != null) action!,
      ]),
    );
  }
}

class _RetryState extends StatelessWidget {
  const _RetryState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          key: const ValueKey('lyric-source-retry'),
          onPressed: onRetry,
          icon: const Icon(Symbols.refresh),
          label: Text(ui("重试")),
        ),
      ]),
    );
  }
}
