import 'package:dan_player/lyric/lyric_lookup_status.dart';
import 'package:dan_player/lyric/japanese_lyric_readings.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:dan_player/lyric/japanese_reading_analyzer.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'dart:async';
import 'package:dan_player/lyric/cached_lyric.dart';
export 'package:dan_player/lyric/cached_lyric.dart';
import 'package:dan_player/lyric/online_lyric_cache.dart';
import 'package:dan_player/search/lyric_search_index.dart';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/local_lyric_reader.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/foundation.dart';

final _desktopLyricSyncOwnerKey = Object();

/// Scope one helper's async initial sync without changing the public sender
/// contract. The owner is local to this async request, never global state:
/// late callbacks cannot cross a closed/reopened helper. Ordinary lyric updates
/// retain their existing source ownership.
Future<void> withDesktopLyricSyncOwner(
        bool Function() stillCurrent, Future<void> Function() sync) =>
    runZoned(sync, zoneValues: {_desktopLyricSyncOwnerKey: stillCurrent});

/// A cached online result can win over local lyrics when the user selected
/// online-first. This stage only reads saved sources; network fallback is gated
/// separately by the opt-in preference after both saved sources miss.
@visibleForTesting
Future<Lyric?> resolveAutomaticLyricSources({
  required bool localFirst,
  required Future<Lyric?> Function() local,
  required Future<Lyric?> Function() cachedOnline,
  bool Function()? stillCurrent,
}) async {
  final savedSources =
      localFirst ? [local, cachedOnline] : [cachedOnline, local];
  for (final readSaved in savedSources) {
    if (stillCurrent?.call() == false) return null;
    final result = await readSaved();
    if (stillCurrent?.call() == false) return null;
    if (result != null) return result;
  }
  return null;
}

/// Recheck permission after asynchronous disk reads and before starting I/O.
@visibleForTesting
Future<Lyric?> resolveMissingLyricOnline({
  required Future<Lyric?> saved,
  required bool Function() allowed,
  required Future<Lyric?> Function() search,
}) async {
  final lyric = await saved;
  if (lyric != null || !allowed()) return lyric;
  return search();
}

/// 只通知 lyric 变更
class LyricService extends ChangeNotifier {
  final PlayService playService;
  final Future<Lyric?> Function(bool localFirst)? _resolveDefaultForTesting;
  final OnlineLyricCache? _onlineCacheForTesting;
  final Future<Lyric?> Function(Audio, bool Function())?
      _onlineLookupForTesting;
  final LyricDocumentStore? documents;
  final JapaneseReadingProjector _japaneseProjector;
  final ValueListenable<JapaneseReadingPreferences> _japanesePreferences;
  final _japaneseReadingsBusy = ValueNotifier(false);
  ValueListenable<bool> get japaneseReadingsBusy => _japaneseReadingsBusy;
  bool _disposed = false;
  LyricSearchCancellation? _automaticLookup;

  LyricService(PlayService playService)
      : this._(playService, null, LyricDocumentStore.instance, null, null, null,
            null);

  @visibleForTesting
  LyricService.forTesting(
    PlayService playService, {
    required Future<Lyric?> Function(bool localFirst) resolveDefaultLyric,
    LyricDocumentStore? documents,
    OnlineLyricCache? onlineCache,
    Future<Lyric?> Function(Audio, bool Function())? onlineLookup,
    JapaneseReadingProjector? japaneseProjector,
    ValueListenable<JapaneseReadingPreferences>? japanesePreferences,
  }) : this._(
          playService,
          resolveDefaultLyric,
          documents,
          onlineCache,
          onlineLookup,
          japaneseProjector,
          japanesePreferences,
        );

  late final StreamSubscription<double> _positionStreamSubscription;
  LyricService._(
      this.playService,
      this._resolveDefaultForTesting,
      this.documents,
      this._onlineCacheForTesting,
      this._onlineLookupForTesting,
      JapaneseReadingProjector? japaneseProjector,
      ValueListenable<JapaneseReadingPreferences>? japanesePreferences)
      : _japaneseProjector = japaneseProjector ?? JapaneseReadingProjector(),
        _japanesePreferences =
            japanesePreferences ?? AppSettings.instance.japaneseReadings {
    _previousJapanesePreferences = _japanesePreferences.value;
    _japanesePreferences.addListener(_handleJapaneseReadingsChange);
    documents?.addListener(_handleDocumentChange);
    AppSettings.instance.automaticOnlineLyrics
        .addListener(_handleAutomaticOnlineChange);
    _positionStreamSubscription =
        playService.playbackService.positionStream.listen((pos) {
      if (_disposed) return;
      final value = _resolvedLyric;
      if (value == null || value.lines.isEmpty) return;

      final lineIndex = findCurrentLyricLineIndex(
        value.lines,
        Duration(milliseconds: (pos * 1000).round()),
      );
      if (lineIndex == _currentLyricLine) return;

      _publishLyricLine(value, lineIndex);
    });
  }

  Audio? _getNowPlaying() =>
      _disposed ? null : playService.playbackService.nowPlaying;

  bool _isPlaying(Audio audio) => _getNowPlaying()?.path == audio.path;

  /// 供 widget 使用
  Future<Lyric?> currLyricFuture = Future.value(null);

  Lyric? _resolvedLyric;
  Lyric? _rawResolvedLyric;
  bool _explicitLookupPending = false;
  Future<Lyric?>? _rawLyricFuture;
  var _presentationToken = 0;
  late JapaneseReadingPreferences _previousJapanesePreferences;
  var _displayOffsetMs = 0;
  bool _manualJapaneseReadings = false;
  JapaneseReadingRequestMode? _manualJapaneseMode;
  Future<JapaneseReadingResult>? _manualReadingRequest;
  int? _manualReadingSource;
  int? _manualReadingPresentation;
  ({
    int source,
    int presentation,
    Future<JapaneseReadingProjection?> result
  })? _projectingReadings;

  /// Canonical timestamps, before the song's application offset. Locking and
  /// editing must use this copy instead of saving the displayed offset twice.
  Lyric? get rawCurrentLyric => _rawResolvedLyric;

  /// The offset-aware lyric already available for this source. Its original
  /// text may be shown while derived readings are still being generated;
  /// [currLyricFuture] continues to resolve to the final projected document.
  Lyric? get currentPresentation => _resolvedLyric;
  int _documentRevision = -1;
  int _lyricToken = 0;
  int get resolutionGeneration => _lyricToken;
  int _currentLyricLine = -1;
  bool _isCurrent(int token) => !_disposed && token == _lyricToken;

  bool _isPresentationCurrent(int token, int presentation) =>
      _isCurrent(token) && presentation == _presentationToken;

  void _handleJapaneseReadingsChange() {
    final previous = _previousJapanesePreferences;
    final next = _japanesePreferences.value;
    _previousJapanesePreferences = next;
    // A preference update does not renew a completed manual authorization.
    _manualJapaneseMode = null;
    if (!next.enabled) _manualJapaneseReadings = false;
    if ((!previous.enabled || !previous.offlineGenerationAllowed) &&
        next.enabled &&
        next.offlineGenerationAllowed &&
        previous.copyWith(enabled: true, offlineGenerationAllowed: true) ==
            next &&
        !_japaneseReadingsBusy.value &&
        _hasJapaneseReadings(_resolvedLyric)) {
      // The new continuous intent is already persisted in the preferences.
      // Reusing an available display preserves its future and reading owner;
      // subsequent sources will observe the newly enabled preference.
      _manualJapaneseReadings = false;
      return;
    }
    if (!_disposed && _rawLyricFuture != null) {
      _reprojectJapaneseReadings(
          restoreCached: !(previous.enabled && !next.enabled));
    }
  }

  Future<JapaneseReadingProjection?> _presentRaw(Future<Lyric?> raw,
      {required int token,
      required int presentation,
      Audio? audio,
      bool restoreCached = true}) async {
    final value = await raw;
    bool current() => _isPresentationCurrent(token, presentation);
    if (!current() || value == null) return null;
    final display = _displayOffsetMs == 0 || value is PlainLyric
        ? value
        : LyricSnapshot.capture(value).toLyric(offsetMs: _displayOffsetMs);
    if (!_manualJapaneseReadings && _hasJapaneseReadings(display)) {
      return JapaneseReadingProjection(
          display, JapaneseReadingResult.unchanged);
    }
    if (restoreCached &&
        !_manualJapaneseReadings &&
        AppSettings.instance.desktopLyricAppearance.value.showJapaneseReading) {
      // The persisted visibility flag does not grant automatic generation.
      // Restore its valid display cache before publishing a first plain copy,
      // so a cached song mounts with its readings in the same presentation.
      final cached = await _japaneseProjector.projectCached(display,
          stillCurrent: current);
      if (!current()) return null;
      if (cached.result == JapaneseReadingResult.applied) {
        // Getter consumers (including a paused taskbar adapter) must receive
        // the same completed cache presentation as FutureBuilder consumers.
        // The final observer sees this same instance and does not force a
        // second line publication.
        if (!identical(_resolvedLyric, cached.lyric)) {
          _resolvedLyric = cached.lyric;
          _syncLineAtCurrentPosition(cached.lyric, force: true);
          notifyListeners();
          if (!current()) return null;
        }
        return cached;
      }
    }
    if (!_japanesePreferences.value.enabled && !_manualJapaneseReadings) {
      return JapaneseReadingProjection(
          display, JapaneseReadingResult.unchanged);
    }
    // A first source need not wait for derived annotations before publishing
    // its original text and timeline. Reprojection retains its existing copy.
    if (_resolvedLyric == null) {
      _resolvedLyric = display;
      _syncLineAtCurrentPosition(display, force: true);
      notifyListeners();
      if (!current()) return null;
    }
    _japaneseReadingsBusy.value = true;
    try {
      final projected = await _japaneseProjector.project(display,
          language: audio?.language,
          enabled: _japanesePreferences.value.enabled,
          force: _manualJapaneseReadings,
          requestMode: _manualJapaneseMode ??
              (_japanesePreferences.value.enabled &&
                      _japanesePreferences.value.offlineGenerationAllowed &&
                      !AppSettings.instance.automaticOnlineLyrics.value
                  ? JapaneseReadingRequestMode.offline
                  : JapaneseReadingRequestMode.automatic),
          stillCurrent: current);
      return current() ? projected : null;
    } finally {
      if (current()) _japaneseReadingsBusy.value = false;
    }
  }

  Future<JapaneseReadingProjection?> _reprojectJapaneseReadings(
      {bool restoreCached = true}) {
    currLyricFuture.ignore();
    _japaneseProjector.cancel();
    _japaneseReadingsBusy.value = false;
    final presentation = ++_presentationToken;
    final projected = _presentRaw(_rawLyricFuture!,
        token: _lyricToken,
        presentation: presentation,
        audio: _getNowPlaying(),
        restoreCached: restoreCached);
    _projectingReadings =
        (source: _lyricToken, presentation: presentation, result: projected);
    currLyricFuture = projected.then((value) => value?.lyric);
    _observePresentationFuture(_lyricToken, presentation,
        preservePresentation: true);
    notifyListeners();
    return projected;
  }

  /// One explicit, in-memory reading request for the captured lyric source.
  /// It never selects a new lyric source or changes the automatic preference.
  Future<JapaneseReadingResult> ensureJapaneseReadingsForCurrentTrack(
      {required int expectedGeneration,
      JapaneseReadingRequestMode mode = JapaneseReadingRequestMode.offline}) {
    if (!_isCurrent(expectedGeneration) ||
        _getNowPlaying() == null ||
        _rawLyricFuture == null) {
      return Future.value(JapaneseReadingResult.stale);
    }
    // Visibility is independent of generation. Reopening a completed display
    // must not replace its lyric, line identities or current reading position.
    if (_hasJapaneseReadings(_resolvedLyric)) {
      return Future.value(JapaneseReadingResult.unchanged);
    }
    final projecting = _projectingReadings;
    if (_japanesePreferences.value.enabled &&
        !_manualJapaneseReadings &&
        projecting != null &&
        projecting.source == expectedGeneration &&
        projecting.presentation == _presentationToken) {
      // Enabling the menu and the settings switch starts the same source-owned
      // projection. Its explicit current-track ensure joins that work.
      return _joinJapaneseReadings(projecting);
    }
    return generateJapaneseReadingsForCurrentTrack(
        expectedGeneration: expectedGeneration, mode: mode);
  }

  bool _hasJapaneseReadings(Lyric? lyric) =>
      lyric?.lines.any((line) {
        final content = switch (line) {
          UnsyncLyricLine() => line.content,
          SyncLyricLine() => line.content,
          _ => '',
        };
        return line.japaneseReadingSpans.any((span) =>
            span.start >= 0 &&
            span.end > span.start &&
            span.end <= content.length &&
            span.text.trim().isNotEmpty);
      }) ==
      true;

  /// A real reader OFF action also retires a legacy one-track request whose
  /// disabled generation preference would otherwise not emit a change.
  void cancelJapaneseReadingsForCurrentTrack(
      {required int expectedGeneration}) {
    if (!_isCurrent(expectedGeneration) ||
        _rawLyricFuture == null ||
        (!_manualJapaneseReadings && !_japaneseReadingsBusy.value)) {
      return;
    }
    _manualJapaneseReadings = false;
    _manualJapaneseMode = null;
    _reprojectJapaneseReadings();
  }

  Future<JapaneseReadingResult> _joinJapaneseReadings(
      ({
        int source,
        int presentation,
        Future<JapaneseReadingProjection?> result
      }) projecting) async {
    bool current() =>
        _isPresentationCurrent(projecting.source, projecting.presentation);
    try {
      final result = await projecting.result;
      return current()
          ? result?.result ?? JapaneseReadingResult.unchanged
          : JapaneseReadingResult.stale;
    } catch (_) {
      return current()
          ? JapaneseReadingResult.unavailable
          : JapaneseReadingResult.stale;
    }
  }

  /// Explicit generation retains its request mode even when a display copy
  /// already contains readings; showing that copy uses the ensure API above.
  Future<JapaneseReadingResult> generateJapaneseReadingsForCurrentTrack(
      {required int expectedGeneration,
      JapaneseReadingRequestMode mode = JapaneseReadingRequestMode.offline}) {
    if (_manualReadingSource == expectedGeneration &&
        _manualReadingPresentation == _presentationToken &&
        _manualReadingRequest != null &&
        _manualJapaneseMode == mode) {
      return _manualReadingRequest!;
    }
    final pending = _generateJapaneseReadings(expectedGeneration, mode);
    _manualReadingRequest = pending;
    _manualReadingSource = expectedGeneration;
    _manualReadingPresentation = _presentationToken;
    pending.whenComplete(() {
      if (identical(_manualReadingRequest, pending)) {
        _manualReadingRequest = null;
        _manualReadingSource = null;
        _manualReadingPresentation = null;
      }
    }).ignore();
    return pending;
  }

  Future<JapaneseReadingResult> _generateJapaneseReadings(
      int expectedGeneration, JapaneseReadingRequestMode mode) async {
    if (!_isCurrent(expectedGeneration) ||
        _getNowPlaying() == null ||
        _rawLyricFuture == null) {
      return JapaneseReadingResult.stale;
    }
    _manualJapaneseReadings = true;
    _manualJapaneseMode = mode;
    final pending = _reprojectJapaneseReadings();
    final presentation = _presentationToken;
    try {
      final result = await pending;
      return _isPresentationCurrent(expectedGeneration, presentation)
          ? result?.result ?? JapaneseReadingResult.unchanged
          : JapaneseReadingResult.stale;
    } catch (_) {
      return _isPresentationCurrent(expectedGeneration, presentation)
          ? JapaneseReadingResult.unavailable
          : JapaneseReadingResult.stale;
    }
  }

  void _handleAutomaticOnlineChange() {
    if (!AppSettings.instance.automaticOnlineLyrics.value) {
      _automaticLookup?.cancel();
    }
    // A remembered manual choice is not a new network authorization.
    _manualJapaneseMode = null;
    if (!_disposed &&
        _rawLyricFuture != null &&
        (_japanesePreferences.value.enabled || _manualJapaneseReadings)) {
      _reprojectJapaneseReadings();
    }
    // Opting in starts a missing default lookup; it must not supersede the
    // source the user is already loading explicitly on this track.
    if (AppSettings.instance.automaticOnlineLyrics.value &&
        !_explicitLookupPending &&
        _rawResolvedLyric == null) {
      updateLyric();
    }
  }

  void _handleDocumentChange() {
    if (documents?.savingDraftOnly == true) {
      final audio = _getNowPlaying();
      if (audio != null) _documentRevision = documents!.revisionFor(audio);
      return;
    }
    final audio = _getNowPlaying();
    if (audio != null && documents!.revisionFor(audio) != _documentRevision) {
      updateLyric();
    }
  }

  void _useRawFuture(Future<Lyric?> raw,
      {int offsetMs = 0,
      bool explicit = false,
      LyricSearchCancellation? automaticLookup}) {
    // The caller constructs the next owner before its deferred lookup starts.
    // Retire the previous source without cancelling this newly installed one.
    if (!identical(_automaticLookup, automaticLookup)) {
      _automaticLookup?.cancel();
    }
    _automaticLookup = automaticLookup;
    currLyricFuture.ignore();
    _japaneseProjector.cancel();
    _japaneseReadingsBusy.value = false;
    _manualJapaneseReadings = false;
    _manualJapaneseMode = null;
    _displayOffsetMs = offsetMs;
    final presentation = ++_presentationToken;
    _explicitLookupPending = explicit;
    final token = _lyricToken + 1;
    final audio = _getNowPlaying();
    _rawResolvedLyric = null;
    final canonical = raw.then((value) {
      if (_isCurrent(token)) {
        _explicitLookupPending = false;
        _rawResolvedLyric = value;
        if (_resolveDefaultForTesting == null &&
            audio != null &&
            _isPlaying(audio) &&
            value != null &&
            isDiscoveredLocalLyric(value)) {
          LyricSearchIndex.instance.rememberLoadedLocal(audio, value);
          cacheLocalLyric(audio, value,
                  shouldStore: () => _isCurrent(token) && _isPlaying(audio))
              .ignore();
        }
      }
      return value;
    });
    _rawLyricFuture = canonical;
    final projected = _presentRaw(canonical,
        token: token, presentation: presentation, audio: audio);
    _projectingReadings =
        (source: token, presentation: presentation, result: projected);
    currLyricFuture = projected.then((value) => value?.lyric);
    _trackLyricFuture();
    notifyListeners();
  }

  void _trackLyricFuture() {
    if (_disposed) return;
    final token = ++_lyricToken;
    _observePresentationFuture(token, _presentationToken);
  }

  void _observePresentationFuture(int token, int presentation,
      {bool preservePresentation = false}) {
    final future = currLyricFuture;
    if (!preservePresentation) {
      _resolvedLyric = null;
      _currentLyricLine = -1;
    }
    unawaited(currLyricFuture.then<void>(
      (value) {
        if (!_isPresentationCurrent(token, presentation) ||
            !identical(future, currLyricFuture)) {
          return;
        }

        final previous = _resolvedLyric;
        final changed = !identical(previous, value);
        _resolvedLyric = value;
        if (value == null || value.lines.isEmpty) {
          playService.desktopLyricService.sendNoLyricMessage();
          if (previous != null && changed) notifyListeners();
          return;
        }
        _syncLineAtCurrentPosition(value, force: changed);
      },
      onError: (Object _, StackTrace __) {
        if (!_isPresentationCurrent(token, presentation) ||
            !identical(future, currLyricFuture)) {
          return;
        }
        _explicitLookupPending = false;
        final hadPresentation = _resolvedLyric != null;
        _resolvedLyric = null;
        _currentLyricLine = -1;
        playService.desktopLyricService.sendNoLyricMessage();
        if (hadPresentation) notifyListeners();
      },
    ));
  }

  StreamController<int>? _lyricLineStreamController;

  Stream<int> get lyricLineStream {
    if (_disposed) return const Stream<int>.empty();
    return (_lyricLineStreamController ??=
            StreamController<int>.broadcast(onListen: () {
      if (!_disposed && _currentLyricLine >= 0) {
        _lyricLineStreamController?.add(_currentLyricLine);
      }
    }))
        .stream;
  }

  /// 重新计算歌词进行到第几行
  void findCurrLyricLine() {
    if (_disposed) return;
    final token = _lyricToken;
    final future = currLyricFuture;
    unawaited(future.then<void>(
      (value) {
        if (!_isCurrent(token) ||
            !identical(future, currLyricFuture) ||
            value == null ||
            value.lines.isEmpty) {
          return;
        }
        _resolvedLyric = value;
        _syncLineAtCurrentPosition(value, force: true);
      },
      // The tracked future/FutureBuilder owns normal error presentation. A
      // pending re-sync must not create a second unhandled error during close.
      onError: (Object _, StackTrace __) {},
    ));
  }

  void _syncLineAtCurrentPosition(Lyric lyric, {required bool force}) {
    if (_disposed || lyric.lines.isEmpty) return;
    final lineIndex = findCurrentLyricLineIndex(
      lyric.lines,
      Duration(
        milliseconds: (playService.playbackService.position * 1000).round(),
      ),
    );
    if (!force && lineIndex == _currentLyricLine) return;
    _publishLyricLine(lyric, lineIndex);
  }

  void _publishLyricLine(Lyric lyric, int lineIndex) {
    if (_disposed || lineIndex < 0 || lineIndex >= lyric.lines.length) return;

    _currentLyricLine = lineIndex;
    _lyricLineStreamController?.add(lineIndex);
    final token = _lyricToken;
    final desktop = playService.desktopLyricService;
    unawaited(desktop.canSendMessage.then<void>(
      (canSend) {
        if (!_isCurrent(token) ||
            !canSend ||
            !identical(_resolvedLyric, lyric) ||
            _currentLyricLine != lineIndex) {
          return;
        }
        desktop.sendPlaybackTimelineMessage();
        desktop.sendLyricLineMessage(
          lyric.lines[lineIndex],
          lineIndex: lineIndex,
        );
      },
      onError: (Object _, StackTrace __) {},
    ));
  }

  /// Pushes an immediate, position-correct snapshot to a newly opened or
  /// recovered desktop lyric process.
  Future<void> syncDesktopLyric() async {
    final stillCurrent =
        Zone.current[_desktopLyricSyncOwnerKey] as bool Function()?;
    if (_disposed || stillCurrent?.call() == false) return;
    final token = _lyricToken;
    final future = currLyricFuture;
    Lyric? lyric;
    try {
      lyric = currentPresentation ?? await future;
    } catch (_) {
      if (_isCurrent(token) &&
          identical(future, currLyricFuture) &&
          stillCurrent?.call() != false) {
        playService.desktopLyricService.sendNoLyricMessage();
      }
      return;
    }
    if (!_isCurrent(token) ||
        !identical(future, currLyricFuture) ||
        stillCurrent?.call() == false) {
      return;
    }
    if (lyric == null || lyric.lines.isEmpty) {
      playService.desktopLyricService.sendNoLyricMessage();
      return;
    }

    _resolvedLyric = lyric;
    final lineIndex = findCurrentLyricLineIndex(
      lyric.lines,
      Duration(
        milliseconds: (playService.playbackService.position * 1000).round(),
      ),
    );
    _currentLyricLine = lineIndex;
    playService.desktopLyricService.sendPlaybackTimelineMessage();
    playService.desktopLyricService.sendLyricLineMessage(
      lyric.lines[lineIndex],
      lineIndex: lineIndex,
    );
  }

  Future<Lyric?> _searchOnline(
    Audio audio, {
    LyricSource? source,
    bool refresh = true,
    bool Function()? stillCurrent,
    LyricSearchCancellation? cancellation,
  }) async {
    bool current() =>
        cancellation?.isCancelled != true &&
        _isPlaying(audio) &&
        (stillCurrent?.call() ?? true);
    if (!current()) return null;
    return (_onlineCacheForTesting ?? OnlineLyricCache.instance)
        .resolve(onlineLyricCacheIdentity(audio, source: source), () async {
      if (!current()) return null;
      final testingLookup = _onlineLookupForTesting;
      if (testingLookup != null) return testingLookup(audio, current);
      if (source != null) {
        return getOnlineLyric(
          qqSongId: source.qqSongId,
          qqSongMid: source.qqSongMid,
          kugouSongHash: source.kugouSongHash,
          neteaseSongId: source.neteaseSongId,
          lrclibId: source.lrclibId,
          stillCurrent: current,
          cancellation: cancellation,
        );
      }
      return getMostMatchedLyric(audio,
          stillCurrent: current, cancellation: cancellation);
    }, refresh: refresh, shouldStore: current);
  }

  Future<Lyric?> _getLyricDefault(bool localFirst) async {
    if (_disposed) return null;
    final resolve = _resolveDefaultForTesting;
    if (resolve != null) return resolve(localFirst);
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return Future.value(null);

    final token = _lyricToken + 1;
    return _resolveSavedForRequest(nowPlaying, token,
        localFirst: nowPlaying.isOnline ? false : localFirst);
  }

  Future<Lyric?> _readLocalForRequest(Audio audio, int token) =>
      Future<Lyric?>.value().then((_) async {
        bool current() => _isCurrent(token) && _isPlaying(audio);
        if (!current()) return null;
        final fresh = await readLocalLyric(audio, stillCurrent: current);
        if (!current()) return null;
        if (fresh != null) return fresh;
        return readCachedLocalLyric(audio,
            cache: _onlineCacheForTesting, stillCurrent: current);
      });

  Future<Lyric?> _resolveSavedForRequest(Audio audio, int token,
          {required bool localFirst, LyricSource? source}) =>
      Future<Lyric?>.value().then((_) {
        bool current() => _isCurrent(token) && _isPlaying(audio);
        return resolveAutomaticLyricSources(
          localFirst: localFirst,
          local: () => _readLocalForRequest(audio, token),
          cachedOnline: () => readAvailableCachedOnlineLyric(audio,
              source: source,
              cache: _onlineCacheForTesting,
              stillCurrent: current),
          stillCurrent: current,
        );
      });

  /// 根据默认歌词来源获取歌词：
  /// 1. 如果没有指定来源，按照现在的方式寻找歌词（本地优先或在线优先）
  /// 2. 如果指定来源，按照指定的来源获取
  void updateLyric() {
    if (_disposed) return;
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) {
      // A removed last track has no replacement source. Invalidate pending
      // lyric/desktop callbacks as well as the currently displayed copy.
      _useRawFuture(Future.value(null));
      return;
    }

    final store = documents;
    if (store != null) {
      final document = store.forAudio(nowPlaying);
      _documentRevision = document?.revision ?? 0;
      if (document?.noLyrics == true) {
        _useRawFuture(Future.value(null));
        return;
      }
      if (document?.effective != null) {
        _useRawFuture(Future.value(document!.effective!.toLyric()),
            offsetMs: document.offsetMs);
        return;
      }
    }

    final configuredSource =
        store?.forAudio(nowPlaying)?.source ?? LYRIC_SOURCES[nowPlaying.path];
    final hasInvalidOnlineLocalSource = configuredSource != null &&
        !isLyricSourceCompatible(
          isOnline: nowPlaying.isOnline,
          source: configuredSource.source,
        );
    if (hasInvalidOnlineLocalSource) {
      LYRIC_SOURCES.remove(nowPlaying.path);
    }
    final lyricSource = hasInvalidOnlineLocalSource ? null : configuredSource;
    final token = _lyricToken + 1;
    final automaticLookup = LyricSearchCancellation();
    Future<Lyric?> raw;
    if (lyricSource == null) {
      raw = _getLyricDefault(AppSettings.instance.localLyricFirst);
    } else {
      if (lyricSource.source == LyricSourceType.local) {
        raw = _readLocalForRequest(nowPlaying, token);
      } else {
        raw = _resolveSavedForRequest(nowPlaying, token,
            localFirst: false, source: lyricSource);
      }
    }
    bool allowed() =>
        !automaticLookup.isCancelled &&
        _isCurrent(token) &&
        _isPlaying(nowPlaying) &&
        AppSettings.instance.automaticOnlineLyrics.value;
    raw = resolveMissingLyricOnline(
      saved: raw,
      allowed: allowed,
      search: () async {
        // A pinned source can miss while a previous default search is cached.
        if (lyricSource != null) {
          final cached = await readCachedOnlineLyric(nowPlaying);
          if (cached != null) return cached;
        }
        if (!allowed()) return null;
        final result = await _searchOnline(
          nowPlaying,
          source:
              lyricSource?.source == LyricSourceType.local ? null : lyricSource,
          refresh: false,
          stillCurrent: allowed,
          cancellation: automaticLookup,
        );
        if (result == null && allowed()) throw const NoMatchingOnlineLyric();
        return result;
      },
    );
    _useRawFuture(raw,
        offsetMs: store?.forAudio(nowPlaying)?.offsetMs ?? 0,
        automaticLookup: automaticLookup);
  }

  void useLocalLyric() {
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return;
    useLocalLyricForTrack(nowPlaying.path);
  }

  bool useLocalLyricForTrack(String expectedTrackPath) {
    if (_disposed) return false;
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null || nowPlaying.path != expectedTrackPath) {
      return false;
    }
    if (nowPlaying.isOnline) {
      LYRIC_SOURCES.remove(nowPlaying.path);
      useOnlineLyric();
      return true;
    }

    _useExplicitFuture(
        nowPlaying, _readLocalForRequest(nowPlaying, _lyricToken + 1),
        source: LyricSource(LyricSourceType.local));
    return true;
  }

  void useOnlineLyric() {
    if (_disposed) return;
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return;

    // Begin the search after _useExplicitFuture has installed its generation.
    // A later choice on the same track must not commit this result to cache.
    final token = _lyricToken + 1;
    final raw = Future<Lyric?>.value().then((_) => _searchOnline(
          nowPlaying,
          stillCurrent: () => _isCurrent(token),
        ));
    _useExplicitFuture(nowPlaying, raw);
  }

  void _useExplicitFuture(Audio audio, Future<Lyric?> raw,
      {LyricSource? source}) {
    final store = documents;
    if (store == null) {
      _useRawFuture(raw, explicit: true);
      return;
    }
    final revision = store.revisionFor(audio);
    final token = _lyricToken + 1;
    final selected = raw.then((value) async {
      if (!_isCurrent(token)) return null;
      if (value == null || value.lines.isEmpty) {
        throw StateError('此来源未返回可用歌词，之前保存的版本已保留。');
      }
      await store.select(audio, value,
          source: source,
          expectedRevision: revision,
          stillCurrent: () => _isCurrent(token));
      return value;
    });
    _useRawFuture(selected,
        offsetMs: store.forAudio(audio)?.offsetMs ?? 0, explicit: true);
  }

  void useSpecificLyric(Lyric lyric) {
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return;
    useSpecificLyricForTrack(nowPlaying.path, lyric);
  }

  bool useSpecificLyricForTrack(String expectedTrackPath, Lyric lyric) {
    if (_disposed) return false;
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null || nowPlaying.path != expectedTrackPath) {
      return false;
    }
    _useRawFuture(Future.value(lyric),
        offsetMs: documents?.forAudio(nowPlaying)?.offsetMs ?? 0,
        explicit: true);
    return true;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _automaticLookup?.cancel();
    _automaticLookup = null;
    _japanesePreferences.removeListener(_handleJapaneseReadingsChange);
    _japaneseProjector.dispose();
    _japaneseReadingsBusy.dispose();
    _presentationToken++;
    documents?.removeListener(_handleDocumentChange);
    AppSettings.instance.automaticOnlineLyrics
        .removeListener(_handleAutomaticOnlineChange);
    _lyricToken++;
    _resolvedLyric = null;
    _currentLyricLine = -1;
    currLyricFuture.ignore();
    // Cancellation is best-effort; no new stream/helper/player is constructed
    // just to dispose a service that never acquired that resource.
    Future<void>.sync(_positionStreamSubscription.cancel).ignore();
    _lyricLineStreamController?.close().ignore();
    super.dispose();
  }
}
