import 'dart:async';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  group('language classification', () {
    test('recognizes language tags and locales, including other languages', () {
      const cases = {
        'zh-Hant-TW': SongLanguage.chinese,
        'CHI': SongLanguage.chinese,
        '粤语': SongLanguage.chinese,
        'eng': SongLanguage.english,
        'en_JP': SongLanguage.english,
        '日本語': SongLanguage.japanese,
        'jpn': SongLanguage.japanese,
        'ko-KR': SongLanguage.korean,
        '한국어': SongLanguage.korean,
        'fr': SongLanguage.other,
        'zxx': SongLanguage.other,
      };
      for (final entry in cases.entries) {
        final result = classifySongLanguage(
          languageTag: entry.key,
          title: 'unrelated title',
        );
        expect(result.language, entry.value, reason: entry.key);
        expect(result.evidence, LanguageEvidence.tag, reason: entry.key);
      }
    });

    test('language tags take priority over titles and lyrics', () {
      final result = classifySongLanguage(
        languageTag: 'zh',
        title: 'きらきら',
        lyrics: _englishLyrics,
      );
      expect(result.language, SongLanguage.chinese);
      expect(result.isInferred, isFalse);
    });

    test('substantial Han-only original lyrics are marked as lyric evidence',
        () {
      for (final title in ['春夏秋冬', '東京', '青花瓷', '音乐与人生']) {
        final result = classifySongLanguage(
          title: title,
          lyrics: '[00:01.00]春夏秋冬世界和平\n[00:05.00]青山绿水天地之间',
        );
        expect(result.language, SongLanguage.chinese, reason: title);
        expect(result.evidence, LanguageEvidence.lyrics);
      }
    });

    test('Latin-only titles are not treated as English', () {
      for (final title in ['Hello', 'Despacito', 'Amore', 'We are the world']) {
        expect(
            classifySongLanguage(title: title).language, SongLanguage.unknown,
            reason: title);
      }
    });

    test('explicit script clues are visibly inferred', () {
      final japanese = classifySongLanguage(title: 'きらきらした世界');
      expect(japanese.language, SongLanguage.japanese);
      expect(japanese.evidence, LanguageEvidence.title);
      expect(japanese.isInferred, isTrue);
      expect(classifySongLanguage(title: '사랑해').language, SongLanguage.korean);
      expect(
          classifySongLanguage(title: 'Любовь').language, SongLanguage.other);
    });

    test('metadata fallback uses available title, composer and album fields',
        () {
      final english = classifySongLanguage(
        title: 'Track 01 (Live)',
        composer: 'Jane Doe',
        album: 'Night Stories 2026',
        useMetadataFallback: true,
      );
      expect(english.language, SongLanguage.english);
      expect(english.evidence, LanguageEvidence.metadata);

      final chinese = classifySongLanguage(
        title: '春风 2026',
        composer: '李明',
        album: '山河（原声）',
        useMetadataFallback: true,
      );
      expect(chinese.language, SongLanguage.chinese);

      for (final composer in [null, '', 'UNKNOWN', '1234']) {
        expect(
          classifySongLanguage(
            title: 'Track',
            composer: composer,
            album: 'Album',
            useMetadataFallback: true,
          ).language,
          SongLanguage.english,
          reason: 'composer=$composer',
        );
      }

      expect(
        classifySongLanguage(
          title: 'Quiet Night',
          composer: 'Jane Doe',
          useMetadataFallback: true,
        ).language,
        SongLanguage.english,
      );
      expect(
        classifySongLanguage(
          title: '春风',
          album: '山河',
          useMetadataFallback: true,
        ).language,
        SongLanguage.chinese,
      );
      final noTitleEvidence = classifySongLanguage(
        title: '1234',
        composer: 'Jane Doe',
        album: 'Night Stories',
        useMetadataFallback: true,
      );
      expect(noTitleEvidence.language, SongLanguage.unknown,
          reason: 'the title itself must contain usable language evidence');
      expect(noTitleEvidence.evidence, LanguageEvidence.unknown);
    });

    test('metadata fallback detects kana and Hangul and contains conflicts',
        () {
      expect(
        classifySongLanguage(
          title: 'Track',
          composer: 'さくら',
          album: 'Album',
          useMetadataFallback: true,
        ).language,
        SongLanguage.japanese,
      );
      expect(
        classifySongLanguage(
          title: 'Track',
          composer: 'Composer',
          album: '사랑 이야기',
          useMetadataFallback: true,
        ).language,
        SongLanguage.korean,
      );
      expect(
        classifySongLanguage(
          title: 'Track',
          composer: 'さくら',
          album: '사랑',
          useMetadataFallback: true,
        ).language,
        SongLanguage.other,
      );
      expect(
        classifySongLanguage(
          title: '歩き出す君へ',
          album: 'Original Soundtrack',
          useMetadataFallback: true,
        ).language,
        SongLanguage.japanese,
        reason: 'any kana evidence outranks a Latin album title',
      );
      expect(
        classifySongLanguage(
          title: '春风',
          album: 'Original Soundtrack',
          useMetadataFallback: true,
        ).language,
        SongLanguage.chinese,
        reason: 'a Han title is Chinese text inference despite a Latin album',
      );
    });

    test('tag and lyric evidence still outrank metadata fallback', () {
      expect(
        classifySongLanguage(
          languageTag: 'zh',
          title: 'English title',
          composer: 'English composer',
          album: 'English album',
          useMetadataFallback: true,
        ).language,
        SongLanguage.chinese,
      );
      expect(
        classifySongLanguage(
          title: '春风',
          composer: '李明',
          album: '山河',
          lyrics: _englishLyrics,
          useMetadataFallback: true,
        ).language,
        SongLanguage.english,
      );
    });

    test('substantial English lyric evidence can be inferred', () {
      final result =
          classifySongLanguage(title: 'Track 01', lyrics: _englishLyrics);
      expect(result.language, SongLanguage.english);
      expect(result.evidence, LanguageEvidence.lyrics);
      expect(result.isInferred, isTrue);
    });

    test('LRC title and artist metadata are not lyrical evidence', () {
      final result = classifySongLanguage(
        title: 'Track 01',
        lyrics: '[ti:きらきら]\n[ar:こんにちは]\n[00:01.00]春夏秋冬',
      );
      expect(result.language, SongLanguage.unknown);
    });

    test('a lyric language declaration is not counted as an audio tag', () {
      final result = classifySongLanguage(
        title: 'Track 01',
        lyrics: '[language:zh-CN]\n[00:01.00]春夏秋冬',
      );
      expect(result.language, SongLanguage.chinese);
      expect(result.evidence, LanguageEvidence.lyrics);
    });

    test('English translations next to Han-only text stay unidentified', () {
      final result = classifySongLanguage(
        title: 'Track 01',
        lyrics: '[00:01.00]春夏秋冬\n$_englishLyrics',
      );
      expect(result.language, SongLanguage.unknown);
    });

    test('unknown tags do not become an invented other language', () {
      for (final tag in ['und', 'unknown', 'xxx', 'not-a-language', 'VOCAL']) {
        expect(
          classifySongLanguage(languageTag: tag, title: 'Track 01').language,
          SongLanguage.unknown,
          reason: tag,
        );
      }
    });

    test('multiple languages are counted once, with same-family tags merged',
        () {
      expect(
        classifySongLanguage(languageTag: 'en/jpn', title: 'Track').language,
        SongLanguage.other,
      );
      expect(
        classifySongLanguage(languageTag: 'zh;cmn', title: 'Track').language,
        SongLanguage.chinese,
      );
    });
  });

  group('read-only library snapshot', () {
    late Directory scratch;

    setUp(() async {
      final root = Directory(
        path.join(Directory.current.path, 'build', 'library_statistics_tests'),
      );
      await root.create(recursive: true);
      scratch = await root.createTemp('case-');
    });

    tearDown(() async {
      if (await scratch.exists()) await scratch.delete(recursive: true);
    });

    test('uses actual file lengths, never stale index or stream estimates',
        () async {
      final file = File(path.join(scratch.path, 'music.flac'));
      await file.writeAsBytes(List<int>.filled(2048, 1));
      final local = _local(file.path, language: 'zh')..fileSizeBytes = 999999;
      final online = _online('10')..fileSizeBytes = 5000000;
      final snapshot = await LibraryStatisticsScanner().scan([local, online]);

      expect(snapshot.totalLocalBytes, 2048);
      expect(snapshot.localTracks, 1);
      expect(snapshot.onlineTracks, 1);
      expect(snapshot.measuredLocalTracks, 1);
      expect(snapshot.formats.single.format, 'FLAC');
      expect(snapshot.formats.single.bytes, 2048);
      expect(snapshot.largestFiles.single.path, file.path);
    });

    test('online descriptors never reach filesystem or lyric readers',
        () async {
      var reads = 0;
      final scanner = LibraryStatisticsScanner(
        inspectFile: (_) async {
          reads++;
          throw StateError('must not inspect a remote track');
        },
        readLyrics: (_) async {
          reads++;
          throw StateError('must not request remote lyrics');
        },
      );
      final snapshot = await scanner.scan([
        _online('10'),
        _local('online://legacy/id'),
      ]);
      expect(reads, 0);
      expect(snapshot.totalLocalBytes, 0);
      expect(snapshot.localTracks, 0);
      expect(snapshot.onlineTracks, 2);
      expect(snapshot.formats, isEmpty);
    });

    test('deduplicates Windows paths and provider identities', () async {
      var inspections = 0;
      final scanner = LibraryStatisticsScanner(
        windowsPaths: true,
        inspectFile: (_) async {
          inspections++;
          return const LocalAudioFileInfo.available(4096);
        },
        readLyrics: (_) async => null,
      );
      final snapshot = await scanner.scan([
        _local(r'D:\Music\song.flac', language: 'zh'),
        _local('d:/music/./song.flac', language: 'ja'),
        _online('10'),
        _online('10'),
      ]);
      expect(inspections, 1);
      expect(snapshot.totalTracks, 2);
      expect(snapshot.totalLocalBytes, 4096);
      expect(snapshot.duplicateEntries, 2);
      expect(snapshot.languageCounts.values.reduce((a, b) => a + b), 2);
    });

    test('resolved symlink aliases do not double-count the same source',
        () async {
      final scanner = LibraryStatisticsScanner(
        windowsPaths: true,
        inspectFile: (_) async => const LocalAudioFileInfo.available(
          120,
          resolvedPath: r'D:\Music\original.mp3',
        ),
        readLyrics: (_) async => null,
      );
      final snapshot = await scanner.scan([
        _local(r'D:\Links\first.mp3'),
        _local(r'D:\Links\second.mp3'),
      ]);
      expect(snapshot.totalTracks, 1);
      expect(snapshot.totalLocalBytes, 120);
      expect(snapshot.duplicateEntries, 1);
    });

    test('missing files are counted but contribute no phantom bytes', () async {
      final snapshot = await LibraryStatisticsScanner().scan([
        _local(path.join(scratch.path, 'missing.mp3'), language: 'en')
          ..fileSizeBytes = 8000,
      ]);
      expect(snapshot.localTracks, 1);
      expect(snapshot.missingLocalTracks, 1);
      expect(snapshot.inaccessibleLocalTracks, 0);
      expect(snapshot.totalLocalBytes, 0);
      expect(snapshot.languageCounts[SongLanguage.english], 1);
    });

    test('permission failures are isolated from other readable files',
        () async {
      final scanner = LibraryStatisticsScanner(
        inspectFile: (value) async => value.endsWith('denied.mp3')
            ? const LocalAudioFileInfo.inaccessible()
            : const LocalAudioFileInfo.available(100),
        readLyrics: (_) async => null,
      );
      final snapshot = await scanner.scan([
        _local(path.join(scratch.path, 'denied.mp3')),
        _local(path.join(scratch.path, 'good.mp3')),
      ]);
      expect(snapshot.inaccessibleLocalTracks, 1);
      expect(snapshot.measuredLocalTracks, 1);
      expect(snapshot.totalLocalBytes, 100);
      expect(snapshot.totalTracks, 2);
    });

    test('reads a bounded same-name local LRC for marked inference', () async {
      final audioFile = File(path.join(scratch.path, 'track.mp3'));
      await audioFile.writeAsBytes([1, 2, 3]);
      await File(path.setExtension(audioFile.path, '.lrc'))
          .writeAsString(_englishLyrics);
      final snapshot = await LibraryStatisticsScanner().scan([
        _local(audioFile.path, title: 'Track 01'),
      ]);
      expect(snapshot.languageCounts[SongLanguage.english], 1);
      expect(snapshot.inferredTracks, 1);
      expect(snapshot.taggedTracks, 0);
    });

    test('scanner freezes and applies the three-field metadata fallback',
        () async {
      final scanner = LibraryStatisticsScanner(
        inspectFile: (_) async => const LocalAudioFileInfo.available(3),
        readLyrics: (_) async => null,
      );
      final snapshot = await scanner.scan([
        _local(
          path.join(scratch.path, 'track.mp3'),
          title: 'Quiet Night',
          composer: 'Jane Doe',
          album: 'Winter Stories',
        ),
      ]);
      expect(snapshot.languageCounts[SongLanguage.english], 1);
      expect(snapshot.inferredTracks, 1);
    });

    test('reliable tags avoid unnecessary lyric reads', () async {
      var lyricReads = 0;
      final scanner = LibraryStatisticsScanner(
        inspectFile: (_) async => const LocalAudioFileInfo.available(3),
        readLyrics: (_) async {
          lyricReads++;
          return _englishLyrics;
        },
      );
      final snapshot = await scanner.scan([
        _local(path.join(scratch.path, 'track.mp3'), language: 'ja'),
      ]);
      expect(lyricReads, 0);
      expect(snapshot.taggedTracks, 1);
      expect(snapshot.languageCounts[SongLanguage.japanese], 1);
    });

    test('freezes metadata while a scan is in flight', () async {
      final measurement = Completer<LocalAudioFileInfo>();
      final scanner = LibraryStatisticsScanner(
        inspectFile: (_) => measurement.future,
        readLyrics: (_) async => null,
      );
      final audio = _local(path.join(scratch.path, 'old.mp3'),
          title: 'Old title', language: 'en');
      final scanning = scanner.scan([audio]);
      audio.title = '新标题';
      audio.language = 'zh';
      audio.path = path.join(scratch.path, 'new.mp3');
      measurement.complete(const LocalAudioFileInfo.available(15));
      final snapshot = await scanning;
      expect(snapshot.languageCounts[SongLanguage.english], 1);
      expect(snapshot.largestFiles.single.title, 'Old title');
      expect(snapshot.largestFiles.single.path, endsWith('old.mp3'));
    });

    test('empty and cancelled scans never inspect files', () async {
      var reads = 0;
      final scanner = LibraryStatisticsScanner(inspectFile: (_) async {
        reads++;
        return const LocalAudioFileInfo.available(1);
      });
      final empty = await scanner.scan([]);
      expect(empty.totalTracks, 0);
      expect(empty.totalLocalBytes, 0);
      expect(empty.languageCounts.values, everyElement(0));
      await expectLater(
        scanner.scan([_local('unused.mp3')], isCancelled: () => true),
        throwsA(isA<LibraryScanCancelled>()),
      );
      expect(reads, 0);
    });
  });

  test('optional index fields remain compatible and round-trip', () {
    final audio = _local(r'D:\Music\track.mp3', language: 'ja')
      ..fileSizeBytes = 4096;
    final restored = Audio.fromMap(audio.toMap());
    expect(restored.language, 'ja');
    expect(restored.fileSizeBytes, 4096);
    final oldMap = Map.of(audio.toMap())
      ..remove('language')
      ..remove('file_size');
    final legacy = Audio.fromMap(oldMap);
    expect(legacy.language, isNull);
    expect(legacy.fileSizeBytes, isNull);
    final remote = _online('id')..language = 'en';
    expect(Audio.fromOnlineMap(remote.toOnlineMap()).language, 'en');
    expect(remote.toOnlineMap().containsKey('file_size'), isFalse);
  });

  test('byte labels use binary units without mislabeling GiB as GB', () {
    expect(formatLibraryBytes(0), '0 B');
    expect(formatLibraryBytes(1024), '1.00 KiB');
    expect(formatLibraryBytes(1024 * 1024), '1.00 MiB');
    expect(formatLibraryBytes(1024 * 1024 * 1024), '1.00 GiB');
  });
}

Audio _local(
  String filePath, {
  String title = 'Track',
  String? composer,
  String album = 'Album',
  String? language,
}) =>
    Audio(
      title,
      'Artist',
      album,
      1,
      240,
      320,
      44100,
      filePath,
      1,
      1,
      'test',
      composer: composer,
      language: language,
    );

Audio _online(String id) => Audio.online(
      provider: 'qq',
      id: id,
      title: 'Online title',
      artist: 'Artist',
      album: 'Album',
      duration: 240,
      bitrate: 320,
    );

const _englishLyrics = '[00:01.00]You are the light and we are here with you. '
    'When the night is over, your dreams will stay with our hearts. '
    'We have the time and they will not take this from you.';
