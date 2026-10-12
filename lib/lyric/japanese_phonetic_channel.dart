import 'dart:async';
import 'dart:io';

import 'package:dan_player/library/japanese_dictionary_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class JapanesePhoneticWord {
  const JapanesePhoneticWord(this.text, this.reading);
  final String text;
  final String reading;
}

@immutable
class JapanesePhoneticBatch {
  const JapanesePhoneticBatch(this.words,
      {this.available = true,
      this.dictionaryMissing = false,
      this.cacheNamespace = 'offline'});
  final List<List<JapanesePhoneticWord>?> words;
  final bool available;
  final bool dictionaryMissing;
  final String cacheNamespace;
}

typedef JapaneseChunkAnalyzer = Future<JapanesePhoneticBatch> Function(
    List<String> chunks);
const _unavailable = JapanesePhoneticBatch([], available: false);

/// Foreground playback and background batches share the single native worker.
/// Cancelling a background owner never cancels the current playback request.
class JapanesePhoneticChannel {
  JapanesePhoneticChannel({
    MethodChannel? channel,
    bool? supported,
    JapanesePhoneticChannel? foreground,
    Future<String?> Function()? dictionaryPath,
  })  : _background = foreground != null,
        _arbiter = foreground?._arbiter ??
            _JapanesePhoneticArbiter(
              channel ?? const MethodChannel('dan_player/japanese_phonetic'),
              supported ?? Platform.isWindows,
              dictionaryPath ??
                  (channel == null
                      ? JapaneseDictionaryRuntime.shared.dictionaryPath
                      : () async => null),
            );

  static final instance = JapanesePhoneticChannel();
  static final background = JapanesePhoneticChannel(foreground: instance);
  final bool _background;
  final _JapanesePhoneticArbiter _arbiter;
  var _generation = 0;

  Future<JapanesePhoneticBatch> analyze(List<String> chunks) {
    final generation = ++_generation;
    if (!_arbiter.supported || chunks.isEmpty) {
      return Future.value(_unavailable);
    }
    if (chunks.length > 16 ||
        chunks.any((text) => text.isEmpty || text.length > 100)) {
      return Future.error(ArgumentError(
          'Japanese analyzer batches contain at most 16 × 100 UTF-16 units'));
    }
    return _arbiter.submit(_JapaneseAnalysis(
      this,
      List.unmodifiable(chunks),
      () => generation == _generation,
    ));
  }

  void cancel() {
    _generation++;
    _arbiter.cancel(this);
  }
}

class _JapaneseAnalysis {
  _JapaneseAnalysis(this.owner, this.chunks, this.current);
  final JapanesePhoneticChannel owner;
  final List<String> chunks;
  final bool Function() current;
  final done = Completer<JapanesePhoneticBatch>();
  var attempt = 0;
  void finish(JapanesePhoneticBatch value) {
    if (!done.isCompleted) done.complete(value);
  }
}

class _JapanesePhoneticArbiter {
  _JapanesePhoneticArbiter(this.channel, this.supported, this.dictionaryPath);
  final MethodChannel channel;
  final bool supported;
  final Future<String?> Function() dictionaryPath;
  _JapaneseAnalysis? _active, _foreground, _background;
  var _handoff = false;
  var _handoffRevision = 0;

  Future<JapanesePhoneticBatch> submit(_JapaneseAnalysis next) {
    if (next.owner._background) {
      _background?.finish(_unavailable);
      _background = next;
      if (_active?.owner == next.owner) {
        _active!.attempt++;
        _active!.finish(_unavailable);
        _active = null;
      }
    } else {
      _foreground?.finish(_unavailable);
      _foreground = next;
      final active = _active;
      if (active != null) {
        active.attempt++;
        _active = null;
        if (active.owner._background && active.current()) {
          _background?.finish(_unavailable);
          _background = active;
          _cancelNative();
        } else {
          // Native analyze itself replaces the previous foreground request.
          // An obsolete future cannot cancel the replacement on its timeout.
          active.finish(_unavailable);
        }
      }
    }
    _pump();
    return next.done.future;
  }

  void cancel(JapanesePhoneticChannel owner) {
    if (_foreground?.owner == owner) {
      _foreground!.finish(_unavailable);
      _foreground = null;
    }
    if (_background?.owner == owner) {
      _background!.finish(_unavailable);
      _background = null;
    }
    if (_active?.owner == owner) {
      _active!.attempt++;
      _active!.finish(_unavailable);
      _active = null;
      _cancelNative();
    }
    _pump();
  }

  void _cancelNative() {
    if (!supported) return;
    final revision = ++_handoffRevision;
    _handoff = true;
    channel.invokeMethod<void>('cancel').catchError((_) {}).whenComplete(() {
      if (revision != _handoffRevision) return;
      _handoff = false;
      _pump();
    });
  }

  void _pump() {
    if (_active != null || _handoff) return;
    var next = _foreground;
    if (next != null) {
      _foreground = null;
    } else {
      next = _background;
      _background = null;
    }
    if (next == null) return;
    if (!next.current()) {
      next.finish(_unavailable);
      _pump();
      return;
    }
    _active = next;
    _run(next, ++next.attempt).ignore();
  }

  Future<void> _run(_JapaneseAnalysis job, int attempt) async {
    bool current() =>
        identical(_active, job) && job.attempt == attempt && job.current();
    try {
      final path = await dictionaryPath();
      if (!current()) return;
      final response =
          await channel.invokeMapMethod<String, Object?>('analyze', {
        'chunks': job.chunks,
        if (path != null) 'dictionaryPath': path,
      }).timeout(const Duration(seconds: 5));
      if (current()) job.finish(_decode(response, job.chunks.length));
    } catch (_) {
      if (current()) {
        job.finish(_unavailable);
        _cancelNative();
      }
    } finally {
      if (identical(_active, job) && job.attempt == attempt) {
        _active = null;
        _pump();
      }
    }
  }

  JapanesePhoneticBatch _decode(Map<String, Object?>? response, int count) {
    final raw = response?['chunks'];
    final missing = response?['dictionaryMissing'] == true;
    if (response?['available'] != true || raw is! List || raw.length != count) {
      return JapanesePhoneticBatch(const [],
          available: false, dictionaryMissing: missing);
    }
    final words = <List<JapanesePhoneticWord>?>[];
    for (final chunk in raw) {
      if (chunk == null) {
        words.add(null);
        continue;
      }
      if (chunk is! List || chunk.length > 100) return _unavailable;
      final parsed = <JapanesePhoneticWord>[];
      var readingUnits = 0;
      for (final word in chunk) {
        if (word is! Map ||
            word['text'] is! String ||
            word['reading'] is! String ||
            (word['text'] as String).isEmpty ||
            (word['text'] as String).length > 100 ||
            (word['reading'] as String).length > 2000) {
          return _unavailable;
        }
        readingUnits += (word['reading'] as String).length;
        if (readingUnits > 2000) {
          return _unavailable;
        }
        parsed.add(JapanesePhoneticWord(
            word['text'] as String, word['reading'] as String));
      }
      words.add(List.unmodifiable(parsed));
    }
    return JapanesePhoneticBatch(List.unmodifiable(words),
        dictionaryMissing: missing);
  }
}
