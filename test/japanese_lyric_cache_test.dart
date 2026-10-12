import 'dart:async';
import 'dart:io';
import 'package:dan_player/lyric/japanese_lyric_cache.dart';
import 'package:dan_player/lyric/japanese_lyric_readings.dart';
import 'package:dan_player/lyric/japanese_phonetic_channel.dart';
import 'package:dan_player/lyric/japanese_reading_analyzer.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

class _CountingCache extends JapaneseLyricReadingCache {
  _CountingCache(Directory directory)
      : super(directory: () async => directory, engine: 'cache-preflight-v1');
  var reads = 0;
  @override
  Future<Map<int, JapaneseCachedReading>?> read(String fingerprint,
      {required bool Function() stillCurrent}) {
    reads++;
    return super.read(fingerprint, stillCurrent: stillCurrent);
  }
}

const reading = JapaneseCachedReading(
    'にほんごかな', [JapaneseLyricReadingSpan(start: 0, end: 3, text: 'にほんご')]);
Lrc source([String text = '日本語かな']) =>
    Lrc([LrcLine(Duration.zero, text, isBlank: false)], LrcSource.local);

void main() {
  late Directory directory;
  late JapaneseLyricReadingCache cache;
  setUp(() async {
    final qa = Directory(path.join(Directory.current.parent.path, 'tool',
        'qa-local', 'blur-position-feedback-oct12', 'cache', 'cache-fixtures'));
    await qa.create(recursive: true);
    directory = await qa.createTemp('case-');
    cache = JapaneseLyricReadingCache(
        directory: () async => directory, engine: 'fixture-v4');
  });
  tearDown(() async {
    await cache.flush();
    await directory.delete(recursive: true);
  });

  test(
      'persistent reading restores fresh display without analyzer or canonical mutation',
      () async {
    final raw = source();
    await cache.write(cache.fingerprint(raw), {0: reading},
        stillCurrent: () => true);
    var calls = 0;
    final projector = JapaneseReadingProjector(
        cache: cache,
        analyze: (_) async {
          calls++;
          return const JapanesePhoneticBatch([], available: false);
        });
    final first =
        await projector.project(raw, enabled: true, stillCurrent: () => true);
    final second =
        await projector.project(raw, enabled: true, stillCurrent: () => true);
    expect(calls, 0);
    expect(first.lyric.lines.single.japaneseReading, reading.text);
    expect(first.lyric, isNot(same(second.lyric)));
    expect(raw.lines.single.japaneseReading, isNull);
    expect(first.lyric.lines.single.japaneseReadingSpans.single.end, 3);
  });

  test(
      'source text order timing author annotation and engine invalidate fingerprints',
      () {
    final raw = source();
    final original = cache.fingerprint(raw);
    raw.lines.single.japaneseReading = 'derived';
    expect(cache.fingerprint(raw), original);
    raw.lines.single.romanization = 'author';
    expect(cache.fingerprint(raw), isNot(original));
    expect(cache.fingerprint(source('日本語かな\n尾')), isNot(original));
    final changed = source()
      ..lines.single.start = const Duration(microseconds: 1);
    expect(cache.fingerprint(changed), isNot(original));
    final engine = JapaneseLyricReadingCache(
        directory: () async => directory, engine: 'other');
    expect(engine.fingerprint(source()), isNot(original));
  });

  test(
      'disabled and Chinese automatic requests never read a saved Japanese projection',
      () async {
    var reads = 0;
    final guarded = JapaneseLyricReadingCache(directory: () async {
      reads++;
      return directory;
    });
    final projector = JapaneseReadingProjector(
        cache: guarded,
        analyze: (_) => throw StateError('unexpected analysis'));
    await projector.project(source(), enabled: false, stillCurrent: () => true);
    await projector.project(source('中文漢字'),
        enabled: true, stillCurrent: () => true);
    expect(reads, 0);
  });

  test('corrupt cache falls back to analysis and stale writes do not commit',
      () async {
    final raw = source();
    final key = cache.fingerprint(raw);
    await File(path.join(directory.path, '$key.json')).writeAsString('{broken');
    var calls = 0;
    final projector = JapaneseReadingProjector(
        cache: cache,
        analyze: (_) async {
          calls++;
          return const JapanesePhoneticBatch([
            [
              JapanesePhoneticWord('日本語', 'にほんご'),
              JapanesePhoneticWord('かな', 'かな')
            ]
          ]);
        });
    expect(
        (await projector.project(raw, enabled: true, stillCurrent: () => true))
            .result,
        JapaneseReadingResult.applied);
    await cache.flush();
    expect(calls, 1);
    final blocked = Completer<Directory>();
    final stale = JapaneseLyricReadingCache(directory: () => blocked.future);
    var current = true;
    final saving =
        stale.write('a' * 64, {0: reading}, stillCurrent: () => current);
    await Future<void>.delayed(Duration.zero);
    current = false;
    blocked.complete(directory);
    await saving;
    expect(await File(path.join(directory.path, '${'a' * 64}.json')).exists(),
        isFalse);
  });

  test(
      'explicit online probes online before offline cache and partitions results',
      () async {
    final raw = source();
    await cache.write(cache.fingerprint(raw), {0: reading},
        stillCurrent: () => true);
    var online = true, calls = 0;
    final projector = JapaneseReadingProjector(
        cache: cache,
        waitForCacheWrites: true,
        cacheNamespaces: () =>
            online ? ['online/fixture', 'offline'] : ['offline'],
        analyze: (_) async {
          calls++;
          return const JapanesePhoneticBatch([
            [
              JapanesePhoneticWord('日本語', 'にっぽんご'),
              JapanesePhoneticWord('かな', 'かな'),
            ]
          ], cacheNamespace: 'online/fixture');
        });
    expect(
        (await projector.project(raw,
                enabled: true,
                requestMode: JapaneseReadingRequestMode.online,
                stillCurrent: () => true))
            .lyric
            .lines
            .single
            .japaneseReading,
        'にっぽんごかな');
    expect(calls, 1);
    online = false;
    expect(
        (await projector.project(raw,
                enabled: true,
                requestMode: JapaneseReadingRequestMode.online,
                stillCurrent: () => true))
            .lyric
            .lines
            .single
            .japaneseReading,
        'にほんごかな');
    online = true;
    expect(
        (await projector.project(raw,
                enabled: true,
                requestMode: JapaneseReadingRequestMode.online,
                stillCurrent: () => true))
            .lyric
            .lines
            .single
            .japaneseReading,
        'にっぽんごかな');
    expect(calls, 1);
  });

  test('automatic display prefers valid offline storage before online analysis',
      () async {
    final raw = source();
    await cache.write(cache.fingerprint(raw), {0: reading},
        stillCurrent: () => true);
    var calls = 0;
    final projector = JapaneseReadingProjector(
        cache: cache,
        cacheNamespaces: () => ['online/current-key', 'offline'],
        analyze: (_) async {
          calls++;
          throw StateError('A valid cache must not start online work');
        });
    addTearDown(projector.dispose);
    final display =
        await projector.project(raw, enabled: true, stillCurrent: () => true);
    expect(display.result, JapaneseReadingResult.applied);
    expect(display.lyric.lines.single.japaneseReading, reading.text);
    expect(display.lyric.lines.single.japaneseReadingSpans.single.text,
        reading.spans.single.text);
    expect(calls, 0);
    expect(raw.lines.single.japaneseReading, isNull);
    expect(raw.lines.single.japaneseReadingSpans, isEmpty);
  });

  test(
      'automatic display prefers complete offline memory before online analysis',
      () async {
    var online = false, calls = 0;
    final projector = JapaneseReadingProjector(
        cacheNamespaces: () =>
            online ? ['online/current-key', 'offline'] : ['offline'],
        analyze: (_) async {
          calls++;
          expect(online, isFalse,
              reason: 'Warm memory should prevent another online analysis');
          return const JapanesePhoneticBatch([
            [
              JapanesePhoneticWord('日本語', 'にほんご'),
              JapanesePhoneticWord('かな', 'かな'),
            ]
          ]);
        });
    addTearDown(projector.dispose);
    final raw = source();
    final warm =
        await projector.project(raw, enabled: true, stillCurrent: () => true);
    online = true;
    final display =
        await projector.project(raw, enabled: true, stillCurrent: () => true);
    expect(display.result, JapaneseReadingResult.applied);
    expect(display.lyric.lines.single.japaneseReading,
        warm.lyric.lines.single.japaneseReading);
    expect(display.lyric.lines.single.japaneseReadingSpans.single.text,
        reading.spans.single.text);
    expect(calls, 1);
    expect(raw.lines.single.japaneseReading, isNull);
  });

  test(
      'automatic network off permits only cached display and explicit offline request',
      () async {
    var calls = 0;
    final policy = JapaneseReadingAnalyzerPolicy(
        onlineAllowed: () => false,
        clientId: () => 'fixture-not-used-online',
        hasDictionary: () async => true,
        cancelOffline: () {},
        offline: (_) async {
          calls++;
          return const JapanesePhoneticBatch([
            [
              JapanesePhoneticWord('日本語', 'にほんご'),
              JapanesePhoneticWord('かな', 'かな'),
            ]
          ]);
        });
    final projector = JapaneseReadingProjector(
        cache: cache, policy: policy, waitForCacheWrites: true);
    final raw = source();
    expect(
        (await projector.project(raw, enabled: true, stillCurrent: () => true))
            .result,
        JapaneseReadingResult.unchanged);
    expect(calls, 0);
    final manual = await projector.project(raw,
        enabled: true,
        requestMode: JapaneseReadingRequestMode.offline,
        stillCurrent: () => true);
    expect(manual.result, JapaneseReadingResult.applied);
    expect(calls, 1);
    final automatic =
        await projector.project(raw, enabled: true, stillCurrent: () => true);
    expect(automatic.lyric.lines.single.japaneseReading, reading.text);
    expect(calls, 1);
    policy.dispose();
  });

  test('automatic off reuses complete memory readings without persistent IO',
      () async {
    var automatic = true, clientId = '';
    var calls = 0;
    Future<JapanesePhoneticBatch> offline(List<String> chunks) async {
      calls++;
      return const JapanesePhoneticBatch([
        [
          JapanesePhoneticWord('日本語', 'にほんご'),
          JapanesePhoneticWord('かな', 'かな'),
        ]
      ]);
    }

    final policy = JapaneseReadingAnalyzerPolicy(
        onlineAllowed: () => automatic,
        clientId: () => clientId,
        hasDictionary: () async => true,
        cancelOffline: () {},
        offline: offline);
    addTearDown(policy.dispose);
    // An explicitly injected analyzer keeps this test's persistent cache off.
    final projector =
        JapaneseReadingProjector(analyze: offline, policy: policy);
    addTearDown(projector.dispose);
    final raw = source();
    final warm =
        await projector.project(raw, enabled: true, stillCurrent: () => true);
    expect(warm.result, JapaneseReadingResult.applied);
    expect(warm.lyric.lines.single.japaneseReading, reading.text);
    expect(calls, 1);
    expect(projector.cachedEntries, 1);
    automatic = false;
    clientId = 'offline-memory-must-still-be-visible';
    final cached =
        await projector.project(raw, enabled: true, stillCurrent: () => true);
    expect(cached.result, JapaneseReadingResult.applied);
    expect(cached.lyric.lines.single.japaneseReading, reading.text);
    expect(cached.lyric.lines.single.japaneseReadingSpans.single.start, 0);
    expect(raw.lines.single.japaneseReading, isNull);
    expect(calls, 1);
    final partial = Lrc([
      LrcLine(Duration.zero, '日本語かな', isBlank: false),
      LrcLine(const Duration(seconds: 1), '未登録かな', isBlank: false),
    ], LrcSource.local);
    final missing = await projector.project(partial,
        enabled: true, stillCurrent: () => true);
    expect(missing.result, JapaneseReadingResult.unchanged);
    expect(missing.lyric, same(partial));
    expect(calls, 1);
  });

  test('entry count total bytes and single-entry bounds are enforced',
      () async {
    cache = JapaneseLyricReadingCache(
        directory: () async => directory,
        engine: 'bounded',
        maximumEntries: 2,
        maximumTotalBytes: 1200,
        maximumEntryBytes: 600);
    for (var index = 0; index < 4; index++) {
      await cache.write('$index'.padLeft(64, 'a'), {0: reading},
          stillCurrent: () => true);
    }
    final files = await directory
        .list()
        .where((entry) => entry is File)
        .cast<File>()
        .toList();
    expect(files.length, 2);
    var total = 0;
    for (final file in files) {
      total += await file.length();
    }
    expect(total, lessThanOrEqualTo(1200));
    await cache.write(
        'b' * 64, {0: JapaneseCachedReading('x' * 1000, const [])},
        stillCurrent: () => true);
    expect(await File(path.join(directory.path, '${'b' * 64}.json')).exists(),
        isFalse);
  });

  test('read-only cache restores Han-only lyrics without dictionary work',
      () async {
    final raw = source('日本語');
    const saved = JapaneseCachedReading(
        'にほんご', [JapaneseLyricReadingSpan(start: 0, end: 3, text: 'にほんご')]);
    await cache.write(cache.fingerprint(raw), {0: saved},
        stillCurrent: () => true);
    await cache.flush();
    final before =
        await File(path.join(directory.path, '${cache.fingerprint(raw)}.json'))
            .readAsBytes();
    var dictionaryCalls = 0, analyses = 0;
    final policy = JapaneseReadingAnalyzerPolicy(
        onlineAllowed: () => true,
        clientId: () => '',
        hasDictionary: () async {
          dictionaryCalls++;
          throw StateError('Cache display must not inspect components');
        },
        cancelOffline: () {},
        offline: (_) async {
          analyses++;
          throw StateError('Cache display must not analyze');
        });
    final projector = JapaneseReadingProjector(cache: cache, policy: policy);
    addTearDown(projector.dispose);
    final result = await projector.projectCached(raw, stillCurrent: () => true);
    expect(result.result, JapaneseReadingResult.applied);
    expect(result.lyric.lines.single.japaneseReading, saved.text);
    expect(result.lyric.lines.single.japaneseReadingSpans.single.text,
        saved.spans.single.text);
    expect(dictionaryCalls, 0);
    expect(analyses, 0);
    expect(raw.lines.single.japaneseReadingSpans, isEmpty);
    expect(
        await File(path.join(directory.path, '${cache.fingerprint(raw)}.json'))
            .readAsBytes(),
        before);
  });

  test('read-only cache miss neither analyzes nor writes a projection',
      () async {
    var calls = 0;
    final projector = JapaneseReadingProjector(
        cache: cache,
        analyze: (_) async {
          calls++;
          throw StateError('A cache-only miss is not generation permission');
        });
    addTearDown(projector.dispose);
    final raw = source();
    final result = await projector.projectCached(raw, stillCurrent: () => true);
    expect(result.result, JapaneseReadingResult.unchanged);
    expect(result.lyric, same(raw));
    expect(calls, 0);
    expect(projector.cachedEntries, 0);
    expect(await directory.list().toList(), isEmpty);
  });

  test('read-only cache rejects invalid UTF16 spans without analysis',
      () async {
    final raw = source('漢😀かな');
    await cache.write(
        cache.fingerprint(raw),
        {
          0: const JapaneseCachedReading(
              'かんかな', [JapaneseLyricReadingSpan(start: 0, end: 2, text: 'かん')])
        },
        stillCurrent: () => true);
    final projector = JapaneseReadingProjector(
        cache: cache,
        analyze: (_) => throw StateError('Invalid cached data must stay raw'));
    addTearDown(projector.dispose);
    final result = await projector.projectCached(raw, stillCurrent: () => true);
    expect(result.result, JapaneseReadingResult.unchanged);
    expect(result.lyric, same(raw));
    expect(raw.lines.single.japaneseReadingSpans, isEmpty);
  });

  test('read-only late cache cannot apply after its source retires', () async {
    final raw = source();
    await cache.write(cache.fingerprint(raw), {0: reading},
        stillCurrent: () => true);
    await cache.flush();
    final pending = Completer<Directory>();
    final delayed = JapaneseLyricReadingCache(
        directory: () => pending.future, engine: 'fixture-v4');
    var current = true;
    final projector = JapaneseReadingProjector(
        cache: delayed,
        analyze: (_) => throw StateError('A late cache is not a new request'));
    addTearDown(projector.dispose);
    final readingFuture =
        projector.projectCached(raw, stillCurrent: () => current);
    await Future<void>.delayed(Duration.zero);
    current = false;
    pending.complete(directory);
    final result = await readingFuture;
    expect(result.result, JapaneseReadingResult.stale);
    expect(result.lyric, same(raw));
    expect(projector.cachedEntries, 0);
    expect(raw.lines.single.japaneseReadingSpans, isEmpty);
  });

  test('display cache miss is consumed once by its automatic generation',
      () async {
    var calls = 0;
    final counted = _CountingCache(directory);
    final projector = JapaneseReadingProjector(
        cache: counted,
        analyze: (chunks) async {
          calls++;
          return const JapanesePhoneticBatch([
            [
              JapanesePhoneticWord('日本語', 'にほんご'),
              JapanesePhoneticWord('かな', 'かな'),
            ]
          ]);
        });
    addTearDown(projector.dispose);
    final raw = source();
    final cached = await projector.projectCached(raw, stillCurrent: () => true);
    expect(cached.result, JapaneseReadingResult.unchanged);
    expect(counted.reads, 1);
    final generated =
        await projector.project(raw, enabled: true, stillCurrent: () => true);
    expect(generated.result, JapaneseReadingResult.applied);
    expect(calls, 1);
    await counted.flush();
    expect(counted.reads, 1);
  });

  test('retired display miss cannot hide a newly saved valid cache', () async {
    final counted = _CountingCache(directory);
    var analyses = 0, previousOwner = true;
    final projector = JapaneseReadingProjector(
        cache: counted,
        analyze: (_) async {
          analyses++;
          throw StateError('The new owner has a complete valid cache');
        });
    addTearDown(projector.dispose);
    final raw = source();
    expect(
        (await projector.projectCached(raw, stillCurrent: () => previousOwner))
            .result,
        JapaneseReadingResult.unchanged);
    previousOwner = false;
    await counted.write(counted.fingerprint(raw), {0: reading},
        stillCurrent: () => true);
    final restored =
        await projector.project(raw, enabled: true, stillCurrent: () => true);
    expect(restored.result, JapaneseReadingResult.applied);
    expect(restored.lyric.lines.single.japaneseReading, reading.text);
    expect(counted.reads, 2);
    expect(analyses, 0);
  });
}
