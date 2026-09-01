import 'dart:async';
import 'dart:io';

import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';

void main() {
  test(
      'explicit composer credits do not conflate singers, lyricists or arrangers',
      () {
    expect(
        classifySongComposer(
                lyrics: '[00:00]演唱：Singer\n'
                    '[00:01]作词：Lyricist\n[00:02]编曲：Arranger')
            .value,
        isNull);
    final result =
        classifySongComposer(lyrics: '[00:00]作曲：Writer\n[00:01]演唱：Singer');
    expect(result.value, 'Writer');
    expect(result.evidence, ClassificationEvidence.lyrics);
    expect(
        classifySongComposer(
                composerTag: 'Tagged writer', lyrics: 'Music by: Other')
            .value,
        'Tagged writer');
    expect(classifySongComposer(lyrics: '词曲：Writer').value, 'Writer');
    expect(classifySongComposer(lyrics: '[composer:Writer]').value, 'Writer');
    expect(classifySongComposer(lyrics: '作曲：未知').value, isNull);
  });

  test(
      'contributor fallback is explicit, lower priority, and not a language tag',
      () {
    final fallback = classifySongComposer(artist: 'Contributor');
    expect(fallback.value, 'Contributor');
    expect(fallback.evidence, ClassificationEvidence.fallback);
    expect(
        classifySongComposer(artist: 'Contributor', composerTag: 'Composer')
            .evidence,
        ClassificationEvidence.tag);
    final lyric =
        classifySongComposer(artist: 'Contributor', lyrics: '作曲：Writer');
    expect(lyric.value, 'Writer');
    expect(lyric.evidence, ClassificationEvidence.lyrics);
    expect(classifySongComposer(artist: 'UNKNOWN').value, isNull);
    final music = classifyMusicMetadata(title: 'Hello', artist: 'さくら');
    expect(music.composer.value, 'さくら');
    expect(music.language.language, SongLanguage.japanese);
    expect(music.language.evidence, LanguageEvidence.metadata);
    final latinTitle = classifyMusicMetadata(
        title: 'A synthetic game track',
        album: 'Game Original Soundtrack',
        artist: '山田太郎');
    expect(latinTitle.language.language, SongLanguage.unknown);
  });

  test('translations and credits never pool into original lyric evidence', () {
    final english = classifySongLanguage(
        title: 'Track',
        lyrics: '$englishLyrics\n'
            '[00:01.000]きみの歌と世界\n[00:00]作曲：さくら');
    expect(english.language, SongLanguage.english);
    expect(english.evidence, LanguageEvidence.lyrics);
    final chinese = classifySongLanguage(
        title: 'Track',
        lyrics: '[00:01]春夏秋冬青山绿水世界和平\n[00:01.0]きみの世界\n'
            '[00:02]山河岁月白云蓝天星光依旧\n[00:02.000]あなたの空');
    expect(chinese.language, SongLanguage.chinese);
    final inline = classifySongLanguage(
        title: 'Track', lyrics: '$englishLyrics // こんにちは翻译文本');
    expect(inline.language, SongLanguage.english);
    final repeatedOriginal =
        englishLyrics.replaceFirst('[00:01.00]', '[00:01.00][00:02.00]');
    final repeated = classifySongLanguage(
        title: 'Track', lyrics: '$repeatedOriginal\n[00:02]こんにちは翻译文本');
    expect(repeated.language, SongLanguage.english);
  });

  test('English title alone is unknown and Han titles survive Latin credits',
      () {
    expect(classifyMusicMetadata(title: 'Hello').language.language,
        SongLanguage.unknown);
    expect(
        classifyMusicMetadata(title: '春风', album: 'Original Soundtrack')
            .language
            .language,
        SongLanguage.chinese);
    expect(
        classifyMusicMetadata(title: 'Hello', album: 'さくら').language.language,
        SongLanguage.japanese);
    expect(
        classifyMusicMetadata(title: 'Hello', album: 'Winter Stories')
            .language
            .evidence,
        LanguageEvidence.metadata);
  });

  test('Han main titles tolerate Latin stage names but keep script precedence',
      () {
    final jam =
        classifyMusicMetadata(title: '七月上', artist: 'Jam', album: '阿敬的单曲集');
    final dawn = classifyMusicMetadata(title: '山间的小调', artist: '初小晓Dawn');
    expect(jam.language.language, SongLanguage.chinese);
    expect(dawn.language.language, SongLanguage.chinese);
    expect(jam.language.evidence, LanguageEvidence.metadata);
    expect(
        classifyMusicMetadata(title: '春风', artist: 'Beyoncé').language.language,
        SongLanguage.chinese);
    expect(classifyMusicMetadata(title: '春风', artist: 'さくら').language.language,
        SongLanguage.japanese);
    expect(classifyMusicMetadata(title: '春风', album: '사랑').language.language,
        SongLanguage.korean);
    expect(
        classifyMusicMetadata(title: '春风', artist: 'Любовь').language.language,
        SongLanguage.other);
    expect(
        classifyMusicMetadata(
                title: 'Warriors 风', artist: '谭盾', album: '英雄 电影原声带')
            .language
            .language,
        SongLanguage.unknown);
    expect(
        classifyMusicMetadata(title: '室内系的TrackMaker', artist: 'hanser')
            .language
            .language,
        SongLanguage.unknown);
  });

  test(
      'filename extensions are not language evidence and source titles stay intact',
      () async {
    final track = CategoryTestAudio('春风.mp3',
        artist: '', album: '', path: r'D:\Music\春风.mp3');
    final classified =
        await MusicClassificationScanner(readLyrics: (_) async => null)
            .scan([track]);
    expect(classified.forAudio(track).language.language, SongLanguage.chinese);
    expect(classified.forAudio(track).language.evidence,
        LanguageEvidence.metadata);
    expect(track.title, '春风.mp3');
    final statistics = await LibraryStatisticsScanner(
      readLyrics: (_) async => null,
      inspectFile: (_) async => const LocalAudioFileInfo.available(1),
    ).scan([track]);
    expect(statistics.languageCounts[SongLanguage.chinese], 1);
    expect(
        classifyMusicMetadata(title: '', filePath: r'D:\Music\春风.mp3')
            .language
            .language,
        SongLanguage.chinese);
    expect(
        classifyMusicMetadata(
                title: 'Hello.mp3', filePath: r'D:\Music\Hello.mp3')
            .language
            .language,
        SongLanguage.unknown);
    expect(
        classifyMusicMetadata(
                title: '春风.mp3', filePath: 'online://provider/song')
            .language
            .language,
        SongLanguage.unknown);
  });

  test('category and statistics language totals use identical evidence',
      () async {
    final tracks = [
      CategoryTestAudio('tag', language: 'ja'),
      CategoryTestAudio('lyrics'),
      CategoryTestAudio('Quiet Night', album: 'Winter Stories'),
      CategoryTestAudio('春风', album: 'Original Soundtrack'),
    ];
    Future<String?> reader(String value) async => value.endsWith('/lyrics.mp3')
        ? '[00:00]作曲：Writer\n$englishLyrics'
        : null;
    final before = tracks.map((audio) => audio.toMap()).toList();
    final classifications =
        await MusicClassificationScanner(readLyrics: reader).scan(tracks);
    final categories =
        MusicCategories(tracks, classifications: classifications);
    final statistics = await LibraryStatisticsScanner(
      readLyrics: reader,
      inspectFile: (_) async => const LocalAudioFileInfo.available(10),
    ).scan(tracks);
    for (final language in SongLanguage.values) {
      final groups = categories
          .groups(MusicCategoryKind.language)
          .where((group) => group.title == language.label);
      expect(groups.isEmpty ? 0 : groups.single.audios.length,
          statistics.languageCounts[language]);
    }
    final english = categories
        .groups(MusicCategoryKind.language)
        .firstWhere((group) => group.title == '英文');
    expect(english.evidenceSummary, '歌词 1 · 推断 1');
    expect(statistics.lyricTracks, 1);
    expect(statistics.metadataInferredTracks, 2);
    expect(
        categories
            .groups(MusicCategoryKind.composer)
            .firstWhere((group) => group.title == 'Writer')
            .evidenceSummary,
        '歌词 1');
    expect(tracks.map((audio) => audio.toMap()).toList(), before);
  });

  test('contributing artist metadata stays consistent between both scanners',
      () async {
    final tracks = [
      CategoryTestAudio('A synthetic game track',
          artist: '山田太郎', album: 'Game Soundtrack'),
      CategoryTestAudio('Another track',
          artist: 'さくら', album: 'Game Soundtrack'),
    ];
    Future<String?> noLyrics(String _) async => null;
    final classified =
        await MusicClassificationScanner(readLyrics: noLyrics).scan(tracks);
    final statistics = await LibraryStatisticsScanner(
      readLyrics: noLyrics,
      inspectFile: (_) async => const LocalAudioFileInfo.available(1),
    ).scan(tracks);
    expect(classified.forAudio(tracks.first).language.language,
        SongLanguage.unknown);
    expect(statistics.languageCounts[SongLanguage.unknown], 1);
    expect(classified.forAudio(tracks.last).language.language,
        SongLanguage.japanese);
    expect(statistics.languageCounts[SongLanguage.japanese], 1);
    expect(classified.forAudio(tracks.last).language.evidence,
        LanguageEvidence.metadata);
  });

  test(
      'classification freezes descriptors and changed fields invalidate snapshot',
      () async {
    final pending = Completer<String?>();
    final track = CategoryTestAudio('Track', album: '');
    final scanning =
        MusicClassificationScanner(readLyrics: (_) => pending.future)
            .scan([track]);
    track.composer = 'New tag';
    pending.complete('作曲：Old credit');
    final snapshot = await scanning;
    expect(snapshot.forAudio(track).composer.value, 'New tag');
    expect(
        snapshot.forAudio(track).composer.evidence, ClassificationEvidence.tag);
    track.composer = null;
    expect(snapshot.forAudio(track).composer.value, 'Old credit');
  });

  test('online tracks never reach lyric reader, failures remain unknown',
      () async {
    var reads = 0;
    final remote =
        CategoryTestAudio('remote', online: true, album: '', artist: '');
    final local = CategoryTestAudio('local', album: '', artist: '');
    final scanner = MusicClassificationScanner(readLyrics: (_) async {
      reads++;
      throw StateError('unreadable fixture');
    });
    final snapshot = await scanner.scan([remote, local]);
    expect(reads, 1);
    expect(snapshot.forAudio(local).composer.value, isNull);
    expect(snapshot.forAudio(remote).language.language, SongLanguage.unknown);
    await expectLater(scanner.scan([local], isCancelled: () => true),
        throwsA(isA<LibraryScanCancelled>()));
    expect(reads, 1);
  });

  test('language-only scan skips lyrics when the language tag is known',
      () async {
    var reads = 0;
    final track = CategoryTestAudio('tagged language',
        language: 'ja', artist: '', composer: null);
    final snapshot = await MusicClassificationScanner(readLyrics: (_) async {
      reads++;
      return '[00:00]作曲：Should Not Be Read';
    }).scan([track], includeComposer: false);

    expect(reads, 0);
    expect(snapshot.forAudio(track).language.language, SongLanguage.japanese);
    expect(snapshot.forAudio(track).composer.value, isNull);
  });

  test('legacy composer scan still reads lyrics when its tag is missing',
      () async {
    var reads = 0;
    final track = CategoryTestAudio('legacy composer',
        language: 'ja', artist: '', composer: null);
    final snapshot = await MusicClassificationScanner(readLyrics: (_) async {
      reads++;
      return '[00:00]作曲：Legacy Writer';
    }).scan([track], includeComposer: true);

    expect(reads, 1);
    expect(snapshot.forAudio(track).composer.value, 'Legacy Writer');
    expect(snapshot.forAudio(track).composer.evidence,
        ClassificationEvidence.lyrics);
  });

  group('bounded read-only lyric cache', () {
    late Directory scratch;
    late File audio;

    setUp(() async {
      final root = await Directory(path.join(
              Directory.current.path, 'build', 'classification_reader_tests'))
          .create(recursive: true);
      scratch = await root.createTemp('case-');
      audio =
          await File(path.join(scratch.path, 'track.mp3')).writeAsBytes([1]);
    });

    tearDown(() async => scratch.delete(recursive: true));

    test('concurrent reads coalesce, source and sidecar changes invalidate',
        () async {
      var calls = 0;
      final gate = Completer<String?>();
      final entered = Completer<void>();
      final reader = LocalClassificationLyricsReader(readEmbeddedLyrics: (_) {
        calls++;
        if (!entered.isCompleted) entered.complete();
        return gate.future;
      });
      final first = reader.call(audio.path);
      final second = reader.call(audio.path);
      await entered.future;
      gate.complete(englishLyrics);
      expect(
          await Future.wait([first, second]), [englishLyrics, englishLyrics]);
      expect(await reader.call(audio.path), englishLyrics);
      expect(calls, 1);
      await audio.writeAsBytes([1, 2]);
      await reader.call(audio.path);
      expect(calls, 2);
      await audio.setLastModified(
          (await audio.lastModified()).add(const Duration(seconds: 2)));
      await reader.call(audio.path);
      expect(calls, 3,
          reason: 'mtime-only changes invalidate unchanged file sizes');
      final sidecar = File(path.setExtension(audio.path, '.lrc'));
      await sidecar.writeAsString('作曲：First');
      expect(await reader.call(audio.path), '作曲：First');
      await sidecar.writeAsString('作曲：Second writer');
      expect(await reader.call(audio.path), '作曲：Second writer');
      await sidecar.writeAsString('作曲：Third! writer');
      await sidecar.setLastModified(
          (await sidecar.lastModified()).add(const Duration(seconds: 2)));
      expect(await reader.call(audio.path), '作曲：Third! writer');
      expect(calls, 3);
    });

    test('exceptions retry immediately and absent lyrics have a short lifetime',
        () async {
      var calls = 0;
      var now = DateTime(2026);
      final reader = LocalClassificationLyricsReader(
          now: () => now,
          readEmbeddedLyrics: (_) async {
            calls++;
            if (calls == 1) throw StateError('temporary native failure');
            return null;
          });
      expect(await reader.call(audio.path), isNull);
      expect(await reader.call(audio.path), isNull);
      expect(calls, 2);
      await reader.call(audio.path);
      expect(calls, 2);
      now = now.add(const Duration(seconds: 31));
      await reader.call(audio.path);
      expect(calls, 3);
    });

    test('entry and byte limits evict old evidence', () async {
      var calls = 0;
      final reader = LocalClassificationLyricsReader(
          maximumEntries: 1,
          readEmbeddedLyrics: (_) async {
            calls++;
            return 'lyrics';
          });
      final other =
          await File(path.join(scratch.path, 'other.mp3')).writeAsBytes([2]);
      await reader.call(audio.path);
      await reader.call(other.path);
      await reader.call(audio.path);
      expect(calls, 3);
      var largeCalls = 0;
      final bounded = LocalClassificationLyricsReader(
          maximumBytes: 2,
          readEmbeddedLyrics: (_) async {
            largeCalls++;
            return 'too large';
          });
      await bounded.call(audio.path);
      await bounded.call(audio.path);
      expect(largeCalls, 2);
    });
  });
}

const englishLyrics = '[00:01.00]You are the light and we are here with you. '
    'When the night is over, your dreams will stay with our hearts. '
    'We have the time and they will not take this from you.';
