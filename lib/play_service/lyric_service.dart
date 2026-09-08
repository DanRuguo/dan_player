import 'dart:async';
import 'package:dan_player/search/lyric_search_index.dart';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/foundation.dart';

/// 只通知 lyric 变更
class LyricService extends ChangeNotifier {
  final PlayService playService;
  final Future<Lyric?> Function(bool localFirst)? _resolveDefaultForTesting;
  final LyricDocumentStore? documents;
  bool _disposed = false;

  LyricService(PlayService playService)
      : this._(playService, null, LyricDocumentStore.instance);

  @visibleForTesting
  LyricService.forTesting(
    PlayService playService, {
    required Future<Lyric?> Function(bool localFirst) resolveDefaultLyric,
    LyricDocumentStore? documents,
  }) : this._(playService, resolveDefaultLyric, documents);

  late final StreamSubscription<double> _positionStreamSubscription;
  LyricService._(
      this.playService, this._resolveDefaultForTesting, this.documents) {
    documents?.addListener(_handleDocumentChange);
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

  /// 供 widget 使用
  Future<Lyric?> currLyricFuture = Future.value(null);

  Lyric? _resolvedLyric;
  Lyric? _rawResolvedLyric;

  /// Canonical timestamps, before the song's application offset. Locking and
  /// editing must use this copy instead of saving the displayed offset twice.
  Lyric? get rawCurrentLyric => _rawResolvedLyric;
  int _documentRevision = -1;
  int _lyricToken = 0;
  int get resolutionGeneration => _lyricToken;
  int _currentLyricLine = -1;
  bool _isCurrent(int token) => !_disposed && token == _lyricToken;

  void _handleDocumentChange() {
    final audio = _getNowPlaying();
    if (audio != null && documents!.revisionFor(audio) != _documentRevision) {
      updateLyric();
    }
  }

  void _useRawFuture(Future<Lyric?> raw, {int offsetMs = 0}) {
    currLyricFuture.ignore();
    final token = _lyricToken + 1;
    final audio = _getNowPlaying();
    _rawResolvedLyric = null;
    currLyricFuture = raw.then((value) {
      if (_isCurrent(token)) {
        _rawResolvedLyric = value;
        if (_resolveDefaultForTesting == null &&
            audio != null &&
            value is Lrc &&
            value.source == LrcSource.local) {
          LyricSearchIndex.instance.rememberLoadedLocal(audio, value);
        }
      }
      return value == null || offsetMs == 0
          ? value
          : LyricSnapshot.capture(value).toLyric(offsetMs: offsetMs);
    });
    _trackLyricFuture();
    notifyListeners();
  }

  void _trackLyricFuture() {
    if (_disposed) return;
    final token = ++_lyricToken;
    _resolvedLyric = null;
    _currentLyricLine = -1;
    unawaited(currLyricFuture.then<void>(
      (value) {
        if (!_isCurrent(token)) return;

        _resolvedLyric = value;
        if (value == null || value.lines.isEmpty) {
          playService.desktopLyricService.sendNoLyricMessage();
          return;
        }
        _syncLineAtCurrentPosition(value, force: true);
      },
      onError: (Object _, StackTrace __) {
        if (!_isCurrent(token)) return;
        _resolvedLyric = null;
        _currentLyricLine = -1;
        playService.desktopLyricService.sendNoLyricMessage();
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
    unawaited(currLyricFuture.then<void>(
      (value) {
        if (!_isCurrent(token) || value == null || value.lines.isEmpty) return;
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
    if (_disposed) return;
    final token = _lyricToken;
    Lyric? lyric;
    try {
      lyric = await currLyricFuture;
    } catch (_) {
      if (_isCurrent(token)) {
        playService.desktopLyricService.sendNoLyricMessage();
      }
      return;
    }
    if (!_isCurrent(token)) return;
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

  Future<Lyric?> _getLyricDefault(bool localFirst) async {
    if (_disposed) return null;
    final resolve = _resolveDefaultForTesting;
    if (resolve != null) return resolve(localFirst);
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return Future.value(null);

    if (nowPlaying.isOnline) {
      final direct = switch (nowPlaying.onlineProvider) {
        "qq" => await getOnlineLyric(
            qqSongId: nowPlaying.onlineNumericId,
            qqSongMid: nowPlaying.onlineId,
          ),
        "netease" => await getOnlineLyric(neteaseSongId: nowPlaying.onlineId),
        _ => null,
      };
      if (_disposed) return null;
      return direct ?? await getMostMatchedLyric(nowPlaying);
    }

    if (localFirst) {
      final local = await Lrc.fromAudioPath(nowPlaying);
      if (_disposed) return null;
      return local ?? (await getMostMatchedLyric(nowPlaying));
    }
    final matched = await getMostMatchedLyric(nowPlaying);
    if (_disposed) return null;
    return matched ?? (await Lrc.fromAudioPath(nowPlaying));
  }

  /// 根据默认歌词来源获取歌词：
  /// 1. 如果没有指定来源，按照现在的方式寻找歌词（本地优先或在线优先）
  /// 2. 如果指定来源，按照指定的来源获取
  void updateLyric() {
    if (_disposed) return;
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return;

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
    Future<Lyric?> raw;
    if (lyricSource == null) {
      raw = _getLyricDefault(AppSettings.instance.localLyricFirst);
    } else {
      if (lyricSource.source == LyricSourceType.local) {
        raw = Lrc.fromAudioPath(nowPlaying);
      } else {
        raw = getOnlineLyric(
          qqSongId: lyricSource.qqSongId,
          qqSongMid: lyricSource.qqSongMid,
          kugouSongHash: lyricSource.kugouSongHash,
          neteaseSongId: lyricSource.neteaseSongId,
          lrclibId: lyricSource.lrclibId,
        );
      }
    }
    _useRawFuture(raw, offsetMs: store?.forAudio(nowPlaying)?.offsetMs ?? 0);
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

    _useExplicitFuture(nowPlaying, Lrc.fromAudioPath(nowPlaying),
        source: LyricSource(LyricSourceType.local));
    return true;
  }

  void useOnlineLyric() {
    if (_disposed) return;
    final nowPlaying = _getNowPlaying();
    if (nowPlaying == null) return;

    final raw = nowPlaying.isOnline
        ? _getLyricDefault(false)
        : getMostMatchedLyric(nowPlaying);
    _useExplicitFuture(nowPlaying, raw);
  }

  void _useExplicitFuture(Audio audio, Future<Lyric?> raw,
      {LyricSource? source}) {
    final store = documents;
    if (store == null) {
      _useRawFuture(raw);
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
    _useRawFuture(selected, offsetMs: store.forAudio(audio)?.offsetMs ?? 0);
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
        offsetMs: documents?.forAudio(nowPlaying)?.offsetMs ?? 0);
    return true;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    documents?.removeListener(_handleDocumentChange);
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
