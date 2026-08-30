import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/page/audio_sort_methods.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Audio extends Audio {
  _Audio(String id,
      {String? name,
      String artist = '',
      String album = '',
      super.composer,
      super.albumArtist,
      super.language,
      int track = 0,
      int duration = 0,
      int? bitrate,
      int? sampleRate,
      int? bytes,
      int created = 0,
      int modified = 0,
      String? path,
      bool online = false})
      : super(
          name ?? id,
          artist,
          album,
          track,
          duration,
          bitrate,
          sampleRate,
          path ?? 'D:/sort-fixtures/$id.mp3',
          modified,
          created,
          null,
          fileSizeBytes: bytes,
          onlineProvider: online ? 'netease' : null,
          onlineId: online ? id : null,
        );

  @override
  String get displayTitle => title;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('empty and original sorts return fresh copies, including repeated songs',
      () {
    final a = _Audio('a');
    final source = [a, a, _Audio('b')];
    final result = sortedAudios(source, AudioSortField.original,
        direction: SortDirection.descending);
    expect(result, orderedEquals(source));
    expect(identical(result, source), isFalse);
    for (final field in AudioSortField.values) {
      expect(sortedAudios([], field), isEmpty);
    }
    expect(PlayService.isInitialized, isFalse);
  });

  final pairs = <AudioSortField, (_Audio, _Audio, _Audio)>{
    AudioSortField.name: (
      _Audio('low', name: 'Alpha'),
      _Audio('high', name: 'Zulu'),
      _Audio('none', name: '')
    ),
    AudioSortField.artist: (
      _Audio('low', artist: 'Alpha'),
      _Audio('high', artist: 'Zulu'),
      _Audio('none', artist: 'UNKNOWN')
    ),
    AudioSortField.album: (
      _Audio('low', album: 'Alpha'),
      _Audio('high', album: 'Zulu'),
      _Audio('none', album: '未知专辑')
    ),
    AudioSortField.composer: (
      _Audio('low', composer: 'Alpha'),
      _Audio('high', composer: 'Zulu'),
      _Audio('none')
    ),
    AudioSortField.albumArtist: (
      _Audio('low', albumArtist: 'Alpha'),
      _Audio('high', albumArtist: 'Zulu'),
      _Audio('none')
    ),
    AudioSortField.duration: (
      _Audio('low', duration: 1),
      _Audio('high', duration: 300),
      _Audio('none', duration: 0)
    ),
    AudioSortField.track: (
      _Audio('low', track: 1),
      _Audio('high', track: 12),
      _Audio('none', track: -1)
    ),
    AudioSortField.added: (
      _Audio('low', created: 10),
      _Audio('high', created: 30),
      _Audio('none')
    ),
    AudioSortField.modified: (
      _Audio('low', modified: 10),
      _Audio('high', modified: 30),
      _Audio('none')
    ),
    AudioSortField.bitrate: (
      _Audio('low', bitrate: 128),
      _Audio('high', bitrate: 320),
      _Audio('none', bitrate: 0)
    ),
    AudioSortField.sampleRate: (
      _Audio('low', sampleRate: 44100),
      _Audio('high', sampleRate: 192000),
      _Audio('none')
    ),
    AudioSortField.fileSize: (
      _Audio('low', bytes: 0),
      _Audio('high', bytes: 2000000000),
      _Audio('none', bytes: -1)
    ),
    AudioSortField.format: (
      _Audio('low', path: r'D:\Music\A.FLAC'),
      _Audio('high', path: '/fixture/B.mp3'),
      _Audio('none', path: 'D:/fixture/no-extension')
    ),
    AudioSortField.language: (
      _Audio('low', language: 'en'),
      _Audio('high', language: 'zh'),
      _Audio('none')
    ),
  };
  for (final entry in pairs.entries) {
    for (final direction in SortDirection.values) {
      test('${entry.key.name} ${direction.name}: stable ties and unknowns last',
          () {
        final (low, high, missing) = entry.value;
        final source = [missing, high, low, low, missing];
        final result = sortedAudios(source, entry.key, direction: direction);
        expect(
            result,
            orderedEquals(direction == SortDirection.ascending
                ? [low, low, high, missing, missing]
                : [high, low, low, missing, missing]));
        expect(source, [missing, high, low, low, missing]);
        expect(compareAudioSort(null, high, entry.key, direction: direction),
            greaterThan(0));
        expect(compareAudioSort(missing, null, entry.key, direction: direction),
            0);
        expect(compareAudioSort(low, high, entry.key, direction: direction),
            -compareAudioSort(high, low, entry.key, direction: direction));
      });
    }
  }

  test(
      'distinct equal-key rows preserve their actual occurrence order both ways',
      () {
    final a = _Audio('a', composer: 'same');
    final b = _Audio('b', composer: 'same');
    final missingA = _Audio('missing-a');
    final missingB = _Audio('missing-b');
    final input = [missingB, b, missingA, a, b];
    for (final direction in SortDirection.values) {
      expect(sortedAudios(input, AudioSortField.composer, direction: direction),
          [b, a, b, missingB, missingA]);
    }
  });

  test('text keeps the existing case-insensitive and Chinese pinyin semantics',
      () {
    final rows = [
      _Audio('z', name: '中国'),
      _Audio('b', name: '北京'),
      _Audio('a', name: 'alpha')
    ];
    expect(
        sortedAudios(rows, AudioSortField.name), [rows[2], rows[1], rows[0]]);
    expect(compareSortText('Same', 'same'), 0);
    expect(
        compareSortText(' UNKNOWN ', 'A', direction: SortDirection.descending),
        greaterThan(0));
  });

  test('online descriptors never claim local size, modified date, or extension',
      () {
    final local = _Audio('local', bytes: 0, modified: 10);
    final remote = _Audio('remote',
        online: true,
        bytes: 99999,
        modified: 99999,
        path: 'online://netease/not-a-file.flac',
        created: 5,
        duration: 210,
        composer: 'Writer');
    for (final field in [
      AudioSortField.fileSize,
      AudioSortField.modified,
      AudioSortField.format
    ]) {
      for (final direction in SortDirection.values) {
        expect(sortedAudios([remote, local], field, direction: direction),
            [local, remote]);
      }
    }
    expect(
        compareAudioSort(remote, null, AudioSortField.duration), lessThan(0));
    expect(
        compareAudioSort(remote, null, AudioSortField.composer), lessThan(0));
    expect(compareAudioSort(remote, null, AudioSortField.added), lessThan(0));
    expect(compareAudioSort(remote, local, AudioSortField.source), isNot(0));
    expect(PlayService.isInitialized, isFalse);
  });

  test('performers are not invented as composer or album-artist tags', () {
    final missing = _Audio('a', artist: 'AAA');
    final known = _Audio('b', composer: 'ZZZ', albumArtist: 'ZZZ');
    for (final field in [AudioSortField.composer, AudioSortField.albumArtist]) {
      expect(sortedAudios([missing, known], field), [known, missing]);
    }
  });

  test(
      'generic numeric comparison keeps legitimate zero and rejects non-finite',
      () {
    for (final direction in SortDirection.values) {
      expect(compareSortNumbers(null, 0, direction: direction), greaterThan(0));
      expect(compareSortNumbers(double.nan, 0, direction: direction),
          greaterThan(0));
      expect(
          compareSortNumbers(double.infinity, null, direction: direction), 0);
    }
  });

  test('legacy profile indexes and custom index five are preserved', () {
    var customCalls = 0;
    final custom = SortMethodDesc<Audio>(
        name: '自定义',
        icon: Icons.drag_handle,
        usesSortOrder: false,
        supportsReorder: true,
        method: (_, __) => customCalls++);
    final prefixes = <AudioSortProfile, List<AudioSortField>>{
      AudioSortProfile.library: [
        AudioSortField.name,
        AudioSortField.artist,
        AudioSortField.album,
        AudioSortField.added,
        AudioSortField.modified
      ],
      AudioSortProfile.folder: [
        AudioSortField.name,
        AudioSortField.artist,
        AudioSortField.album,
        AudioSortField.added,
        AudioSortField.modified
      ],
      AudioSortProfile.album: [
        AudioSortField.name,
        AudioSortField.artist,
        AudioSortField.track,
        AudioSortField.added,
        AudioSortField.modified
      ],
      AudioSortProfile.artist: [
        AudioSortField.name,
        AudioSortField.album,
        AudioSortField.added,
        AudioSortField.modified
      ],
    };
    for (final entry in prefixes.entries) {
      final methods = audioSortMethods(entry.key, custom: custom);
      expect(
          methods
              .take(entry.value.length)
              .cast<AudioSortMethodDesc>()
              .map((method) => method.field),
          entry.value);
      expect(
          methods
              .whereType<AudioSortMethodDesc>()
              .map((method) => method.field)
              .toSet(),
          AudioSortField.values
              .where((field) => field != AudioSortField.original)
              .toSet());
      if (entry.key == AudioSortProfile.library) {
        expect(identical(methods[5], custom), isTrue);
        methods[5].method([], SortOrder.decending);
        expect(methods[5].supportsReorder, isTrue);
        expect(methods[5].usesSortOrder, isFalse);
      }
    }
    expect(customCalls, 1);
    expect(
        () => audioSortMethods(AudioSortProfile.library), throwsArgumentError);
  });

  test('legacy in-place adapter sorts only its supplied display copy', () {
    final a = _Audio('a', duration: 100);
    final b = _Audio('b', duration: 200);
    final original = [a, b];
    final display = List<Audio>.of(original);
    AudioSortMethodDesc(AudioSortField.duration)
        .method(display, SortOrder.decending);
    expect(display, [b, a]);
    expect(original, [a, b]);
    expect(PlayService.isInitialized, isFalse);
  });
}
