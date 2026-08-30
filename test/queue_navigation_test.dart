import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/play_service/queue_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

Audio song(String id) => Audio.online(
    provider: 'qq', id: id, title: id, artist: '', album: '', duration: 60);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a replaced shorter queue does not use its previous numeric index', () {
    final queue = [song('new'), song('other')];
    expect(
        queueIndexForTrack(queue, 'online://qq/old', preferredIndex: 400), -1);
    expect(queueIndexForTrack(queue, queue.last.path, preferredIndex: 400), 1);
  });

  test('the pending online track can be used for rapid next/previous actions',
      () {
    final queue = [song('old'), song('pending'), song('next')];
    final index = queueIndexForTrack(queue, queue[1].path, preferredIndex: 0);
    expect(index, 1);
    expect(queue[index + 1].onlineId, 'next');
    expect(queue[index - 1].onlineId, 'old');
  });

  test('an existing duplicate position is retained when still valid', () {
    final duplicate = song('duplicate');
    final queue = [duplicate, song('other'), duplicate];
    expect(queueIndexForTrack(queue, duplicate.path, preferredIndex: 2), 2);
    expect(queueIndexForTrack(queue, duplicate.path, preferredIndex: 1), 0);
  });

  test('empty queues and missing tracks return an explicit absent index', () {
    expect(queueIndexForTrack([], null), -1);
    expect(
        queueIndexForTrack([], 'online://qq/missing', preferredIndex: 0), -1);
  });

  test(
      'reference refresh preserves the selected duplicate despite new Audio instances',
      () {
    final duplicate = song('duplicate');
    final queue = [duplicate, song('other'), duplicate];
    final replacements = {
      for (final old in queue) old.path: song(old.onlineId!),
    };
    final refreshed = [for (final old in queue) replacements[old.path] ?? old];
    expect(refreshed[2], isNot(same(duplicate)));
    expect(queueIndexForTrack(refreshed, duplicate.path, preferredIndex: 2), 2);
    expect(queueIndexForTrack(refreshed, duplicate.path, preferredIndex: 0), 0);
  });

  test('session restore retains the second occurrence of an unchanged queue',
      () {
    const paths = ['A', 'B', 'A', 'C'];
    expect(queueIndexAfterFiltering(paths, 2, keepPath: (_) => true), 2);
    expect(queueIndexAfterFiltering(paths, 0, keepPath: (_) => true), 0);
  });

  test(
      'missing prefix tracks shift the saved occurrence by exactly the removed count',
      () {
    const paths = ['missing-1', 'A', 'missing-2', 'B', 'A', 'C'];
    final available = {'A', 'B', 'C'};
    expect(queueIndexAfterFiltering(paths, 4, keepPath: available.contains), 2);
    expect(queueIndexAfterFiltering(paths, 1, keepPath: available.contains), 0);
    expect(queueIndexAfterFiltering(paths, 5, keepPath: available.contains), 3);
  });

  test('consecutive duplicate occurrences are not collapsed during restoration',
      () {
    const paths = ['A', 'A', 'A'];
    for (var index = 0; index < paths.length; index++) {
      expect(
          queueIndexAfterFiltering(paths, index, keepPath: (_) => true), index);
    }
  });

  test(
      'filtering only the suffix does not change the selected occurrence index',
      () {
    const paths = ['A', 'B', 'A', 'missing'];
    expect(
        queueIndexAfterFiltering(paths, 2,
            keepPath: (path) => path != 'missing'),
        2);
  });

  test('a missing saved target reports absence even when other songs survive',
      () {
    const paths = ['A', 'missing', 'A', 'B'];
    expect(
        queueIndexAfterFiltering(paths, 1,
            keepPath: (path) => path != 'missing'),
        -1);
    expect(queueIndexAfterFiltering(paths, 2, keepPath: (_) => false), -1);
  });

  test('invalid saved indices never index a path or invoke the resolver', () {
    bool doNotResolve(String _) => throw StateError('invalid index accessed');
    expect(queueIndexAfterFiltering([], 0, keepPath: doNotResolve), -1);
    expect(queueIndexAfterFiltering(['A'], -1, keepPath: doNotResolve), -1);
    expect(queueIndexAfterFiltering(['A'], 1, keepPath: doNotResolve), -1);
    expect(queueIndexAfterFiltering(['A'], 10000, keepPath: doNotResolve), -1);
  });

  test('mixed local and online path filters preserve the same occurrence', () {
    const local = 'D:\\Music\\song.flac';
    const remote = 'online://qq/song%2Fmid';
    const paths = ['D:\\missing.flac', remote, local, remote];
    final knownPaths = {local, remote};
    expect(
        queueIndexAfterFiltering(paths, 3, keepPath: knownPaths.contains), 2);
  });

  test('all availability subsets match a source-index-tagged reference filter',
      () {
    const paths = ['A', 'B', 'A', 'C', 'A'];
    const unique = ['A', 'B', 'C'];
    for (var mask = 0; mask < 8; mask++) {
      final available = {
        for (var bit = 0; bit < unique.length; bit++)
          if ((mask & (1 << bit)) != 0) unique[bit],
      };
      final retainedSourceIndices = [
        for (var index = 0; index < paths.length; index++)
          if (available.contains(paths[index])) index,
      ];
      for (var index = -1; index <= paths.length; index++) {
        expect(
          queueIndexAfterFiltering(paths, index, keepPath: available.contains),
          retainedSourceIndices.indexOf(index),
          reason: 'mask=$mask originalIndex=$index',
        );
      }
    }
  });
}
