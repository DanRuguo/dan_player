import 'dart:async';

import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:flutter/foundation.dart';

@immutable
class TaskbarLyricAppearance {
  const TaskbarLyricAppearance({
    required this.accent,
    required this.fontFamily,
    required this.fontPath,
    this.fontPolicy,
    this.animate = true,
    this.layoutAnimate = true,
    this.placement = 'auto',
    this.areaSelection = 0,
    this.showNextTrack = true,
    this.showNextLyric = true,
    this.showPauseIndicator = true,
    this.strokeEnabled = false,
    this.colorScheme = 'player',
    this.showNextButton = false,
  });
  final int accent;
  final String fontFamily;
  final String fontPath;
  final AppFontPolicy? fontPolicy;
  final bool animate;
  final bool layoutAnimate;
  final String placement;
  final int areaSelection;
  final bool showNextTrack;
  final bool showNextLyric;
  final bool showPauseIndicator;
  final bool strokeEnabled;
  final String colorScheme;
  final bool showNextButton;
}

/// Read-only adapter to an already-owned lyric result and playback clock.
abstract class TaskbarLyricSource extends ChangeNotifier {
  Future<Lyric?> get lyric;
  int get generation;
  int get session;
  bool get hasTrack;
  double get position;
  bool get playing;
  bool get paused => !playing;
  double get playbackRate => 1;
  Object? get intent => null;
  double get duration => 0;
  String get nextTrackTitle => '';
  bool get nextButtonEnabled => false;
  bool get playbackButtonEnabled => false;
}

String taskbarLyricText(LyricLine line) {
  final content = switch (line) {
    UnsyncLyricLine() => line.content,
    SyncLyricLine() => line.content,
    _ => '',
  };
  return content.split('┃').first.replaceAll(RegExp(r'\r\n?|\n'), ' ').trim();
}

/// Event-driven lyric publishing. No timer, network lookup or frame work.
/// Native writes coalesce while an earlier acknowledged write is pending.
class TaskbarLyricsPublisher {
  TaskbarLyricsPublisher({
    required TaskbarLyricSource source,
    required TaskbarLyricAppearance Function() appearance,
    required Future<void> Function(Map<String, Object>) send,
    required void Function(Object, StackTrace) onError,
    Duration Function()? elapsed,
  })  : _source = source,
        _appearance = appearance,
        _send = send,
        _onError = onError,
        _elapsed = elapsed {
    _source.addListener(refresh);
    refresh();
  }

  final TaskbarLyricSource _source;
  final TaskbarLyricAppearance Function() _appearance;
  final Future<void> Function(Map<String, Object>) _send;
  final void Function(Object, StackTrace) _onError;
  final Duration Function()? _elapsed;
  final _clock = Stopwatch()..start();
  Future<Lyric?>? _future;
  int _sourceGeneration = -1;
  int _sourceSession = -1;
  bool _sourceHasTrack = false;
  int _resolution = 0;
  int _documentGeneration = -1;
  int _documentSession = -1;
  int _documentRevision = 0;
  Lyric? _resolved;
  bool _scheduled = false;
  bool _closed = false;
  bool _sending = false;
  Map<String, Object>? _pending;
  Map<String, Object>? _last;
  Future<void> _sendTail = Future.value();
  int _lineIndex = -2;
  Map<String, Object> _line = const {};
  Map<String, Object>? _lastContent;
  Object? _lastIntent;
  int _timelineRevision = 0;
  Duration? _lastPositionAt;
  AppFontPolicy? _serializedFontPolicy;
  Map<String, Object?>? _fontPolicyJson;

  void refresh() {
    if (_closed || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_closed) return;
      _syncSource();
      _publish();
    });
  }

  void _syncSource() {
    final future = _source.lyric;
    final generation = _source.generation;
    final session = _source.session;
    final hasTrack = _source.hasTrack;
    if (identical(future, _future) &&
        generation == _sourceGeneration &&
        session == _sourceSession &&
        hasTrack == _sourceHasTrack) {
      return;
    }
    final sameSession =
        session == _sourceSession && hasTrack && _sourceHasTrack;
    _future = future;
    _sourceGeneration = generation;
    _sourceSession = session;
    _sourceHasTrack = hasTrack;
    final token = ++_resolution;
    if (!sameSession) {
      _resolved = null;
      _lineIndex = -2;
      _commitIdentity(generation, session, token);
    }
    // A selected source may still retain the previous decoder/document. Do
    // not commit that future while opening, or revive it on the next true edge.
    if (!hasTrack) return;
    unawaited(future.then((value) {
      if (!_owns(token, future, generation, session)) return;
      _resolved = value;
      _lineIndex = -2;
      _commitIdentity(generation, session, token);
      refresh();
    }, onError: (Object error, StackTrace trace) {
      if (!_owns(token, future, generation, session)) return;
      _resolved = null;
      _lineIndex = -2;
      _commitIdentity(generation, session, token);
      // Lyric lookup errors belong to the existing lyric UI, not this subtitle.
      refresh();
    }));
  }

  void _commitIdentity(int generation, int session, int revision) {
    _documentGeneration = generation;
    _documentSession = session;
    _documentRevision = revision;
  }

  bool _owns(int token, Future<Lyric?> future, int generation, int session) =>
      !_closed &&
      _source.hasTrack &&
      token == _resolution &&
      identical(future, _source.lyric) &&
      generation == _source.generation &&
      session == _source.session;

  void _publish() {
    final style = _appearance();
    final lines = _resolved?.lines;
    final position = _source.position;
    final index = lines == null || !_source.hasTrack || !position.isFinite
        ? -1
        : findCurrentLyricLineIndex(
            lines, Duration(microseconds: (position * 1000000).round()));
    if (index != _lineIndex) {
      _lineIndex = index;
      _line = index < 0
          ? const {
              'text': '',
              'nextText': '',
              'words': <Object>[],
              'lineStartMilliseconds': 0,
              'lineEndMilliseconds': 0,
            }
          : _projectLine(lines!, index);
    }
    final intent = _source.intent;
    final nextTrackTitle = _source.nextTrackTitle;
    final explicitChange = intent != _lastIntent;
    if (explicitChange) {
      _lastIntent = intent;
      _timelineRevision++;
    }
    if (style.fontPolicy != _serializedFontPolicy) {
      _serializedFontPolicy = style.fontPolicy;
      _fontPolicyJson = style.fontPolicy?.toJson();
    }
    final content = <String, Object>{
      'enabled': true,
      ..._line,
      'accent': style.accent,
      'fontFamily': style.fontFamily,
      'fontPath': style.fontPath,
      if (_fontPolicyJson != null) 'fontPolicy': _fontPolicyJson!,
      'animate': style.animate,
      'animateLayout': style.layoutAnimate,
      'playing': _source.playing,
      'paused': _source.paused,
      'playbackRate': _source.playbackRate,
      'placement': style.placement,
      'areaSelection': style.areaSelection,
      'nextTrackText':
          style.showNextTrack && _source.hasTrack && nextTrackTitle.isNotEmpty
              ? ui('下一首：{0}', [nextTrackTitle])
              : '',
      'showPauseIndicator': style.showPauseIndicator && _source.hasTrack,
      'playbackButtonEnabled':
          style.showPauseIndicator && _source.playbackButtonEnabled,
      'showNextLyric': style.showNextLyric,
      'strokeEnabled': style.strokeEnabled,
      'colorScheme': style.colorScheme,
      'showNextButton': style.showNextButton,
      'nextButtonEnabled': style.showNextButton && _source.nextButtonEnabled,
      'sourceIdentity':
          '$_documentSession:$_documentGeneration:$_documentRevision',
      'lineIdentity':
          '$_documentSession:$_documentGeneration:$_documentRevision:$index',
    };
    final at = _elapsed?.call() ?? _clock.elapsed;
    final changed = !mapEquals(content, _lastContent);
    final hasText = content['text'] != '';
    if (!changed &&
        (!hasText ||
            (!explicitChange &&
                (!_source.playing ||
                    (_lastPositionAt != null &&
                        at - _lastPositionAt! <
                            const Duration(milliseconds: 400)))))) {
      return;
    }
    _lastContent = content;
    _lastPositionAt = at;
    final payload = <String, Object>{
      ...content,
      'positionMilliseconds': position.isFinite ? (position * 1000).round() : 0,
      'timelineRevision': _timelineRevision,
    };
    if (mapEquals(payload, _last)) return;
    _pending = payload;
    _drain();
  }

  Map<String, Object> _projectLine(List<LyricLine> lines, int index) {
    final line = lines[index];
    final text = taskbarLyricText(line);
    // Only authored word timings whose UTF-16 content matches the displayed
    // primary line are valid. LRC/plain text never receive guessed word slots.
    final words = line is SyncLyricLine &&
            line.words.length <= 4096 &&
            line.words.map((word) => word.content).join() == text &&
            line.words.every((word) => word.length >= Duration.zero)
        ? <Map<String, Object>>[
            for (final word in line.words)
              {
                'startMilliseconds': word.start.inMilliseconds,
                'lengthMilliseconds': word.length.inMilliseconds,
                'content': word.content,
              }
          ]
        : const <Map<String, Object>>[];
    return {
      'text': text,
      'nextText':
          index + 1 < lines.length ? taskbarLyricText(lines[index + 1]) : '',
      'words': words,
      'lineStartMilliseconds': line.start.inMilliseconds,
      'lineEndMilliseconds': _lineEnd(lines, index),
    };
  }

  int _lineEnd(List<LyricLine> lines, int index) {
    final line = lines[index];
    if (line is SyncLyricLine) return syncLyricLineEnd(line).inMilliseconds;
    if (line is LrcLine && line.length > Duration.zero) {
      return (line.start + line.length).inMilliseconds;
    }
    if (index + 1 < lines.length) return lines[index + 1].start.inMilliseconds;
    final duration = _source.duration;
    return duration.isFinite && duration * 1000 > line.start.inMilliseconds
        ? (duration * 1000).round()
        : line.start.inMilliseconds;
  }

  void _drain() {
    if (_sending || _closed) return;
    _sending = true;
    _sendTail = () async {
      try {
        while (!_closed && _pending != null) {
          final payload = _pending!;
          _pending = null;
          if (mapEquals(payload, _last)) continue;
          try {
            await _send(payload);
            _last = payload;
          } catch (error, trace) {
            if (!_closed) _onError(error, trace);
          }
        }
      } finally {
        _sending = false;
      }
    }();
  }

  Future<void> close() async {
    if (_closed) return _sendTail;
    _closed = true;
    _resolution++;
    _pending = null;
    _source.removeListener(refresh);
    // The disable ack follows any in-flight enable, so it cannot be resurrected.
    await _sendTail;
    await _send({'enabled': false, 'text': ''});
  }
}
