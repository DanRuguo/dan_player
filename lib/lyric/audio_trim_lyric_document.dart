import 'dart:math' as math;

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_source.dart';

/// Mirrors a committed audio trim in the application-owned lyric document.
/// Parsed format offsets are already in the snapshots; the application offset
/// is absorbed exactly once before clipping. Source audio and sidecars are not
/// touched here. The store serializes this with edits and publishes atomically.
Future<void> synchronizeTrimmedLyricDocument(
    Audio source, Audio saved, double startSeconds, double endSeconds,
    {required bool preserve, LyricDocumentStore? documents}) async {
  if (!startSeconds.isFinite ||
      !endSeconds.isFinite ||
      startSeconds < 0 ||
      endSeconds <= startSeconds ||
      endSeconds > 9007199254) {
    throw ArgumentError('Invalid lyric trim interval');
  }
  final start = (startSeconds * Duration.microsecondsPerSecond).round();
  final end = (endSeconds * Duration.microsecondsPerSecond).round();
  if (end <= start) throw ArgumentError('Empty lyric trim interval');
  await (documents ?? LyricDocumentStore.instance).replaceFromAudio(
      source,
      saved,
      (document) => !preserve || document == null
          ? null
          : _trimDocument(document.toJson(), start, end));
}

Map<String, dynamic> _trimDocument(
    Map<String, dynamic> document, int start, int end) {
  final offset = (document['offsetMs'] as int? ?? 0) * 1000;
  final hasActiveSnapshot =
      document['original'] != null || document['edited'] != null;
  for (final kind in const ['original', 'edited', 'draft']) {
    final previous = document[kind];
    final snapshot = previous == null
        ? null
        : _trimSnapshot(Map<String, dynamic>.from(previous as Map), start, end,
            kind == 'draft' && !hasActiveSnapshot ? 0 : offset);
    document[kind] = snapshot;
    final textKey = '${kind}Text';
    if (document[textKey] != null) {
      // The editor reads these text copies ahead of the snapshot. Rebuild them
      // too, keeping non-timing headers rather than offering the old timeline.
      document[textKey] = snapshot == null
          ? null
          : _editableText(snapshot, document[textKey] as String);
    }
  }
  // Offset-only documents have no snapshot into which we can bake the
  // calibration. Their newly trimmed local sidecar/tag still needs that same
  // display offset; clearing it would silently lose the user's correction.
  if (document['original'] != null || document['edited'] != null) {
    document['offsetMs'] = 0;
  }
  // A clip no longer shares the remote song's full timeline. This also covers
  // source/offset-only records and their undo versions, whose missing snapshot
  // would otherwise make LyricService request the original remote lyrics.
  document['source'] = LyricSource(LyricSourceType.local).toMap();
  document['history'] = [
    for (final version in document['history'] as List? ?? const [])
      _trimDocument(Map<String, dynamic>.from(version as Map), start, end)
        ..remove('history')
  ];
  return document;
}

Map<String, dynamic> _trimSnapshot(
    Map<String, dynamic> snapshot, int start, int end, int offset) {
  // Untimed text cannot be aligned to a selected audio interval. Keep it
  // explicitly untimed instead of manufacturing synchronization timestamps.
  if (snapshot['format'] == 'plain') return snapshot;
  final lines = [
    for (final (index, line) in (snapshot['lines'] as List).indexed)
      (index: index, data: Map<String, dynamic>.from(line as Map))
  ];
  lines.sort((a, b) {
    final time = (a.data['start'] as int).compareTo(b.data['start'] as int);
    return time == 0 ? a.index.compareTo(b.index) : time;
  });
  // Infer open-ended LRC spans in one backward pass. Equal-time translations
  // share the next distinct timestamp rather than becoming zero-length lines.
  final nextTimes = List<int>.filled(lines.length, end - offset);
  for (var i = lines.length - 2; i >= 0; i--) {
    final following = lines[i + 1].data['start'] as int;
    nextTimes[i] = following > (lines[i].data['start'] as int)
        ? following
        : nextTimes[i + 1];
  }
  final kept = <Map<String, dynamic>>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].data;
    final lineStart = (line['start'] as int) + offset;
    final length = line['length'] as int;
    final words = line['words'] as List?;
    var lineEnd = lineStart + length;
    if (words == null && length == 0) {
      lineEnd = nextTimes[i] + offset;
    } else if (words != null) {
      for (final word in words) {
        lineEnd = math.max(
            lineEnd, (word['start'] as int) + offset + (word['length'] as int));
      }
    }
    if (!_intersects(lineStart, lineEnd, start, end)) continue;
    final clippedStart = math.max(lineStart, start);
    final clippedEnd = math.max(clippedStart, math.min(lineEnd, end));
    line['start'] = clippedStart - start;
    line['length'] = clippedEnd - clippedStart;
    if (words != null) {
      line['words'] = [
        for (final raw in words)
          if (_intersects(
              (raw['start'] as int) + offset,
              (raw['start'] as int) + offset + (raw['length'] as int),
              start,
              end))
            {
              ...raw as Map,
              'start': math.max((raw['start'] as int) + offset, start) - start,
              'length': math.max(
                  0,
                  math.min(
                          (raw['start'] as int) +
                              offset +
                              (raw['length'] as int),
                          end) -
                      math.max((raw['start'] as int) + offset, start)),
            }
      ];
    }
    kept.add(line);
  }
  snapshot['lines'] = kept;
  return snapshot;
}

bool _intersects(int itemStart, int itemEnd, int start, int end) =>
    itemStart < end &&
    (itemEnd > start || (itemEnd == itemStart && itemStart >= start));

String _editableText(Map<String, dynamic> snapshot, String original) {
  if (snapshot['format'] == 'plain') return snapshot['text'] as String;
  final header = RegExp(r'^\s*\[([a-zA-Z][a-zA-Z0-9_-]*):.*\]\s*$');
  final result = <String>[];
  for (final line in original.split(RegExp(r'\r?\n'))) {
    final match = header.firstMatch(line);
    if (match != null &&
        !const {'offset', 'length'}.contains(match.group(1)!.toLowerCase())) {
      result.add(line);
    }
  }
  for (final line in snapshot['lines'] as List) {
    final micros = line['start'] as int;
    final minutes = micros ~/ Duration.microsecondsPerMinute;
    final seconds = (micros ~/ Duration.microsecondsPerSecond) % 60;
    final fraction = micros % Duration.microsecondsPerSecond;
    final timestamp = '[${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.'
        '${fraction.toString().padLeft(6, '0')}]';
    final words = line['words'] as List?;
    final text = words == null
        ? line['text'] as String
        : [
            words.map((word) => word['text'] as String).join(),
            if ((line['translation'] as String?)?.isNotEmpty == true)
              line['translation'] as String
          ].join('┃');
    for (final part in text.replaceAll('\r\n', '\n').split('\n')) {
      result.add('$timestamp$part');
    }
  }
  return result.join('\n');
}
