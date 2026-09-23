import 'package:dan_player/lyric/online_lyric_cache.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'dart:async';
import 'package:dan_player/taskbar_progress.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric_cache_batch.dart';
import 'package:dan_player/lyric/lyric_lookup_status.dart';
import 'package:flutter_test/flutter_test.dart';

Audio audio(String file) =>
    Audio(file, 'Artist', 'Album', 0, 120, null, null, file, 0, 0, null);
void main() {
  test('taskbar follows scan and completed tracks then restores other tasks',
      () async {
    final progress = TaskbarProgress();
    final older = progress.begin()..update(.25);
    final scanning = Completer<List<Audio>>();
    final second = Completer<bool>();
    final values = <TaskbarProgressValue?>[];
    progress.addListener(() => values.add(progress.value));
    final task = LyricCacheBatch(
        taskbarProgress: progress,
        scan: (_, __) => scanning.future,
        hasSaved: (a) async => a.path == 'one',
        fetchAndCache: (_, __) => second.future);
    final job = task.start('J:/music');
    expect(progress.value, TaskbarProgressValue.indeterminate);
    scanning.complete([audio('one'), audio('two')]);
    await Future<void>.delayed(Duration.zero);
    expect(progress.value, TaskbarProgressValue.fraction(.5));
    second.complete(true);
    await job;
    expect(values, contains(TaskbarProgressValue.fraction(1)));
    expect(progress.value, TaskbarProgressValue.fraction(.25));
    older.dispose();
    expect(progress.value, isNull);
    task.dispose();
    progress.dispose();
  });
  test('taskbar releases on cancellation empty folder and scan failure',
      () async {
    for (final mode in ['cancel', 'empty', 'error']) {
      final progress = TaskbarProgress();
      final pending = Completer<List<Audio>>();
      final task = LyricCacheBatch(
          taskbarProgress: progress, scan: (_, __) => pending.future);
      final job = task.start('J:/music');
      if (mode == 'cancel') task.cancel();
      if (mode == 'error') {
        pending.completeError(StateError('scan failed'));
      } else {
        pending.complete([]);
      }
      await job;
      expect(progress.value, isNull, reason: mode);
      expect(task.running, isFalse);
      task.dispose();
      progress.dispose();
    }
  });
  test(
      'a readable network result is not counted as cached when disk writes fail',
      () async {
    final track = Audio.online(
        provider: 'netease',
        id: 'cache-write-fixture',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        duration: 180);
    final task = LyricCacheBatch(
        scan: (_, __) async => [track],
        hasSaved: (_) async => false,
        cache: OnlineLyricCache(
            directory: () async => throw StateError('Read-only cache fixture')),
        lookup: (_, __) async =>
            Lrc.fromLrcText('[00:01.00]downloaded', LrcSource.web));
    addTearDown(task.dispose);
    await task.start('J:/music');
    expect(task.saved, 0);
    expect(task.failed, 1);
    expect(task.completed, 1);
  });
  test('folder restriction uses imported tracks including descendants only',
      () {
    final tracks = [
      audio('J:/music/one.mp3'),
      audio('J:/music/sub/two.flac'),
      audio('J:/music-other/three.mp3')
    ];
    expect(
        LyricCacheBatch.selectImportedTracks('J:/music', ['J:/music'], tracks),
        tracks.take(2));
    expect(
        () => LyricCacheBatch.selectImportedTracks(
            'J:/downloads', ['J:/music'], tracks),
        throwsArgumentError);
  });
  test(
      'batch skips saved lyrics and continues after no match instrumental and errors',
      () async {
    final requested = <String>[];
    final task = LyricCacheBatch(
        scan: (_, __) async => [
              'saved',
              'matched',
              'none',
              'instrumental',
              'failed'
            ].map(audio).toList(),
        hasSaved: (a) async => a.path == 'saved',
        fetchAndCache: (a, active) async {
          requested.add(a.path);
          if (a.path == 'instrumental') throw const InstrumentalLyric();
          if (a.path == 'failed') throw StateError('fixture');
          return a.path == 'matched';
        });
    addTearDown(task.dispose);
    await task.start('J:/music');
    expect(requested, ['matched', 'none', 'instrumental', 'failed']);
    expect([
      task.completed,
      task.saved,
      task.skipped,
      task.unmatched,
      task.instrumental,
      task.failed
    ], [
      5,
      1,
      1,
      1,
      1,
      1
    ]);
    expect(task.running, isFalse);
  });
  test(
      'cancel blocks subsequent tracks and late cache publication; another start cannot overlap',
      () async {
    final pending = Completer<void>();
    final requested = <String>[];
    var writes = 0;
    final task = LyricCacheBatch(
        scan: (_, __) async => [audio('one'), audio('two')],
        hasSaved: (_) async => false,
        fetchAndCache: (a, active) async {
          requested.add(a.path);
          await pending.future;
          if (active()) writes++;
          return active();
        });
    addTearDown(task.dispose);
    final job = task.start('J:/music');
    while (requested.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await task.start('J:/music');
    task.cancel();
    pending.complete();
    await job;
    expect(requested, ['one']);
    expect(writes, 0);
    expect(task.status, '已取消，已缓存的歌词会保留。');
  });
}
