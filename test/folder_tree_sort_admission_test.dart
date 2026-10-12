import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/library/folder_tree.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';

class _SortAudio extends CategoryTestAudio {
  _SortAudio(super.id,
      {super.artist,
      super.album,
      super.composer,
      super.albumArtist,
      super.language,
      super.path,
      super.track,
      super.duration,
      super.bitrate,
      super.online});

  @override
  String get displayTitle => title;
}

class _OpaqueAudio extends _SortAudio {
  _OpaqueAudio(super.id, {required super.path});

  // A custom Audio may carry unrelated local state. Sorting its scalar
  // descriptor must not transfer that state to the worker isolate.
  final localState = ReceivePort();
}

class _MeasuredSongs extends ListBase<Audio> {
  _MeasuredSongs(this.values);
  final List<Audio> values;
  int reads = 0, _turnReads = 0, maximumTurnReads = 0;

  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('Read-only fixture');
  @override
  Audio operator [](int index) {
    if (_turnReads == 0) {
      // This callback precedes the next yielding batch's timer. A synchronous
      // walk cannot reset its own measured event-loop budget.
      Timer.run(() => _turnReads = 0);
    }
    reads++;
    _turnReads++;
    if (_turnReads > maximumTurnReads) maximumTurnReads = _turnReads;
    return values[index];
  }

  @override
  void operator []=(int index, Audio value) =>
      throw UnsupportedError('Read-only fixture');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final qa = path.join(Directory.current.parent.path, 'tool', 'qa-local',
      'kana-reveal-blur-oct12', 'folders', 'sort-admission');

  test('large folder worker admission yields between bounded song snapshots',
      () async {
    const count = 20000;
    final source = _MeasuredSongs([
      for (var index = count - 1; index >= 0; index--)
        _SortAudio(index.toString().padLeft(5, '0'),
            path: path.join(qa, '$index.mp3')),
    ]);
    final clock = Stopwatch()..start();
    final pending = sortFolderTreeSongs(
        source, AudioSortField.name, SortDirection.ascending);
    final invocationWall = clock.elapsedMicroseconds;
    final initialReads = source.reads;
    final sorted = await pending;
    stdout.writeln('FOLDER_SORT_ADMISSION ${jsonEncode({
          'songs': count,
          'invocationReturnWallMicroseconds': invocationWall,
          'totalIncludingWorkerWallMicroseconds': clock.elapsedMicroseconds,
          'synchronousSourceReads': initialReads,
          'maximumEventTurnSourceReads': source.maximumTurnReads,
          'totalSourceReads': source.reads,
        })}');
    expect(initialReads, lessThanOrEqualTo(512),
        reason: 'The first opening must yield instead of snapshotting 20k '
            'songs before returning the worker future.');
    expect(source.maximumTurnReads, lessThanOrEqualTo(512));
    expect(source.reads, count);
    expect(sorted.length, count);
    expect(sorted.first, same(source.values.last));
    expect(sorted.last, same(source.values.first));
  });

  test('folder worker transfers sort descriptors without unrelated Audio state',
      () async {
    final a = _OpaqueAudio('Alpha', path: path.join(qa, 'a.mp3'));
    final b = _OpaqueAudio('Beta', path: path.join(qa, 'b.mp3'));
    try {
      final sorted = await sortFolderTreeSongs(
          [b, a, b], AudioSortField.name, SortDirection.ascending);
      expect(sorted, orderedEquals([a, b, b]));
      expect(sorted[0], same(a));
      expect(sorted[1], same(b));
      expect(sorted[2], same(b));
    } finally {
      a.localState.close();
      b.localState.close();
    }
  });

  test('folder scalar snapshots preserve every existing sort and occurrence',
      () async {
    final a = _SortAudio('Alpha',
        artist: '阿',
        album: 'One',
        composer: 'Composer A',
        albumArtist: 'Album artist A',
        language: 'en',
        duration: 60,
        track: 1,
        bitrate: 128,
        path: path.join(qa, 'Alpha.FLAC'))
      ..created = 10
      ..modified = 20
      ..fileSizeBytes = 0
      ..sampleRate = 44100;
    final b = _SortAudio('alpha',
        artist: '重阳',
        album: 'Two',
        composer: 'Composer B',
        albumArtist: 'Album artist B',
        language: 'ja',
        duration: 180,
        track: 2,
        bitrate: 320,
        path: path.join(qa, 'Alpha.mp3'))
      ..created = 30
      ..modified = 40
      ..fileSizeBytes = 1234
      ..sampleRate = 48000;
    final online = _SortAudio('夜空かな',
        artist: '日本群星',
        album: 'Three',
        language: 'ja-JP',
        duration: 120,
        bitrate: 256,
        online: true)
      ..created = 25
      ..modified = 999
      ..fileSizeBytes = 99999;
    final unknown = _SortAudio('',
        artist: 'Unknown',
        album: '未知专辑',
        language: 'n/a',
        duration: 0,
        bitrate: 0,
        path: path.join(qa, 'missing-extension'))
      ..created = 0
      ..modified = 0
      ..sampleRate = 0;
    final source = [unknown, b, online, a, b, unknown];
    for (final field in AudioSortField.values) {
      for (final direction in SortDirection.values) {
        final expected = sortedAudios(source, field, direction: direction);
        final actual = await sortFolderTreeSongs(source, field, direction);
        expect(actual.length, expected.length);
        for (var index = 0; index < expected.length; index++) {
          expect(actual[index], same(expected[index]),
              reason: '${field.name}/${direction.name}, occurrence $index');
        }
        expect(() => actual.add(a), throwsUnsupportedError);
        expect(source, orderedEquals([unknown, b, online, a, b, unknown]));
      }
    }
  });
}
