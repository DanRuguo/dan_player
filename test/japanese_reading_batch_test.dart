import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/lyric/japanese_lyric_readings.dart';
import 'package:dan_player/lyric/japanese_phonetic_channel.dart';
import 'package:dan_player/lyric/japanese_reading_analyzer.dart';
import 'package:dan_player/lyric/japanese_reading_batch.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/taskbar_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Lrc lyric([String text = '日本語かな']) => Lrc([
      LrcLine(Duration.zero, text, isBlank: false)
        ..romanization = 'Authored romaji'
    ], LrcSource.local);
JapanesePhoneticBatch reading(List<String> chunks) => JapanesePhoneticBatch([
      for (final text in chunks)
        [JapanesePhoneticWord(text, text.replaceAll('日本語', 'にほんご'))]
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TaskbarProgress progress;
  setUp(() => progress = TaskbarProgress());
  tearDown(() => progress.dispose());

  test(
      'batch starts explicitly and processes snapshots without canonical changes',
      () async {
    var scans = 0, calls = 0;
    final source = lyric();
    final before = jsonEncode(LyricSnapshot.capture(source).toJson());
    final job = JapaneseReadingBatch(
        taskbarProgress: progress,
        scan: (_) async {
          scans++;
          return [
            JapaneseReadingBatchItem(read: () async => source),
            JapaneseReadingBatchItem(read: () async => null),
            JapaneseReadingBatchItem(
                read: () async => throw const FormatException('fixture')),
          ];
        },
        projector: JapaneseReadingProjector(analyze: (texts) async {
          calls++;
          return reading(texts);
        }));
    expect([scans, calls], [0, 0]);
    expect(progress.value, isNull);
    await job.start(mode: JapaneseReadingRequestMode.offline);
    expect([job.total, job.completed, job.generated, job.skipped, job.failed],
        [3, 3, 1, 1, 1]);
    expect(jsonEncode(LyricSnapshot.capture(source).toJson()), before);
    expect(source.lines.single.japaneseReading, isNull);
    expect(source.lines.single.romanization, 'Authored romaji');
    expect(progress.value, isNull);
    job.dispose();
  });

  test(
      'cancel immediately releases progress and prevents late reads and analysis',
      () async {
    final pending = Completer<Lrc?>();
    var reads = 0, cancels = 0, analyses = 0;
    final older = progress.begin()..update(.25);
    final job = JapaneseReadingBatch(
        taskbarProgress: progress,
        scan: (_) async => [
              JapaneseReadingBatchItem(read: () {
                reads++;
                return pending.future;
              }),
              JapaneseReadingBatchItem(read: () async {
                reads++;
                return lyric();
              }),
            ],
        projector: JapaneseReadingProjector(analyze: (texts) async {
          analyses++;
          return reading(texts);
        }, cancel: () {
          cancels++;
        }));
    final running = job.start();
    await Future<void>.delayed(Duration.zero);
    job.cancel();
    expect(progress.value, TaskbarProgressValue.fraction(.25));
    pending.complete(lyric());
    await running;
    expect([reads, analyses, cancels], [1, 0, 0]);
    expect(job.completed, 0);
    expect(job.status, '已取消，已生成的假名缓存会保留。');
    older.dispose();
    job.dispose();
  });

  test('dispose during native work revokes only the owned projector', () async {
    final pending = Completer<JapanesePhoneticBatch>();
    var cancels = 0, notices = 0;
    final job = JapaneseReadingBatch(
        taskbarProgress: progress,
        scan: (_) async =>
            [JapaneseReadingBatchItem(read: () async => lyric())],
        projector: JapaneseReadingProjector(
            analyze: (_) => pending.future,
            cancel: () {
              cancels++;
            }));
    job.addListener(() => notices++);
    final running = job.start();
    await Future<void>.delayed(Duration.zero);
    job.dispose();
    final notifications = notices;
    pending.complete(reading(['日本語かな']));
    await running;
    expect(notices, notifications);
    expect(cancels, 1);
    expect(progress.value, isNull);
    expect(job.generated, 0);
  });

  test('missing dictionary stops batch before the next snapshot', () async {
    var reads = 0;
    final job = JapaneseReadingBatch(
        taskbarProgress: progress,
        scan: (_) async => List.generate(
            3,
            (_) => JapaneseReadingBatchItem(read: () async {
                  reads++;
                  return lyric();
                })),
        projector: JapaneseReadingProjector(
            analyze: (_) async => const JapanesePhoneticBatch([],
                available: false, dictionaryMissing: true)));
    await job.start();
    expect(reads, 1);
    expect(job.status, '需要日语假名字典组件');
    expect(job.completed, 0);
    expect(progress.value, isNull);
    job.dispose();
  });

  test(
      'explicit batch mode is passed through and remembered choice grants no automatic work',
      () async {
    var calls = 0;
    final policy = JapaneseReadingAnalyzerPolicy(
        onlineAllowed: () => false,
        clientId: () => '',
        offline: (texts) async {
          calls++;
          return reading(texts);
        },
        cancelOffline: () {},
        hasDictionary: () async => true);
    // Injected policy uses no global app/cache directory.
    final job = JapaneseReadingBatch(
        taskbarProgress: progress,
        scan: (_) async =>
            [JapaneseReadingBatchItem(read: () async => lyric())],
        projector:
            JapaneseReadingProjector(analyze: policy.analyze, policy: policy));
    await job.start();
    expect(calls, 0);
    expect(job.generated, 0);
    await job.start(mode: JapaneseReadingRequestMode.offline);
    expect(calls, 1);
    expect(job.generated, 1);
    job.dispose();
    policy.dispose();
  });

  test('cache scan is bounded, lazy and leaves saved files unchanged',
      () async {
    final base = Directory(p.join(Directory.current.parent.path, 'tool',
        'qa-local', 'lyric-settings-feedback-oct11', 'root', 'batch-files'));
    await base.create(recursive: true);
    final scratch = await base.createTemp('case-');
    try {
      final valid = File(p.join(scratch.path, '${'a' * 64}.json'));
      final body = jsonEncode(LyricSnapshot.capture(lyric()).toJson());
      await valid.writeAsString(body);
      final bad = File(p.join(scratch.path, '${'b' * 64}.json'));
      await bad.writeAsString('invalid');
      await File(p.join(scratch.path, 'unrelated.json'))
          .writeAsString('unrelated');
      var active = true;
      final items = await scanSavedJapaneseReadingLyrics(() => active,
          directory: scratch, tracks: []);
      expect(items.length, 2);
      expect((await items.first.read())!.lines.single.romanization,
          'Authored romaji');
      await expectLater(items.last.read(), throwsFormatException);
      active = false;
      expect(await items.first.read(), isNull);
      expect(await valid.readAsString(), body);
      await expectLater(
          scanSavedJapaneseReadingLyrics(() => true,
              directory: scratch, tracks: [], maximumEntries: 2),
          throwsA(isA<FileSystemException>()));
    } finally {
      await scratch.delete(recursive: true);
    }
  });
}
