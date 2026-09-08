import 'dart:async';
import 'dart:io';
import 'package:dan_player/library/cover_repair.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'support/music_category_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('album scope deduplicates physical sources without merging equal titles',
      () async {
    final a = CategoryTestAudio('a', artist: 'A', album: 'Same');
    final b = CategoryTestAudio('b', artist: 'B', album: 'Same');
    final group = MusicCategories.albumGroupFor(a, [a, a, b]);
    final calls = <String>[];
    final repair =
        CoverRepair(group.audios, album: group, repair: (target) async {
      calls.add(target.source);
      return CoverRepairStatus.success;
    });
    addTearDown(repair.dispose);
    expect(repair.targets.length, 1);
    await repair.run();
    expect(calls, [a.path]);
  });
  test('summary separates absence from failure and retries only failed sources',
      () async {
    final audios = [for (var i = 0; i < 4; i++) CategoryTestAudio('track-$i')];
    final calls = <String, int>{};
    final repair = CoverRepair(audios, repair: (target) async {
      final attempt =
          calls.update(target.source, (value) => value + 1, ifAbsent: () => 1);
      if (attempt > 1) return CoverRepairStatus.success;
      return [
        CoverRepairStatus.success,
        CoverRepairStatus.noArtwork,
        CoverRepairStatus.unreadable,
        CoverRepairStatus.failed
      ][audios.indexWhere((audio) => identical(audio, target.audio))];
    });
    addTearDown(repair.dispose);
    await repair.run();
    expect(repair.count(CoverRepairStatus.noArtwork), 1);
    await repair.run(retryOnly: true);
    expect(calls.values, [1, 1, 2, 2]);
    expect(repair.count(CoverRepairStatus.success), 3);
  });
  test('cancelling does not start pending sources or undo completed repair',
      () async {
    final start = Completer<void>(), finish = Completer<void>();
    final repair = CoverRepair([CategoryTestAudio('a'), CategoryTestAudio('b')],
        repair: (target) async {
      start.complete();
      await finish.future;
      return CoverRepairStatus.success;
    });
    addTearDown(repair.dispose);
    final run = repair.run();
    await start.future;
    repair.cancel();
    finish.complete();
    await run;
    expect(repair.targets.map((target) => target.status),
        [CoverRepairStatus.success, CoverRepairStatus.cancelled]);
  });
  test(
      'production repair distinguishes missing sources and real files without artwork',
      () async {
    final parent = Directory(p.join(Directory.current.parent.path, 'tool',
        'qa-2605-update', 'cover-repair'));
    await parent.create(recursive: true);
    final fixture = await parent.createTemp('no-art-');
    final real =
        await File(p.join(fixture.path, 'no-art.wav')).writeAsBytes([0]);
    addTearDown(() async {
      if (!p.isWithin(parent.absolute.path, fixture.absolute.path)) {
        throw StateError('invalid fixture');
      }
      await fixture.delete(recursive: true);
    });
    final repair = CoverRepair([
      CategoryTestAudio('missing', path: p.join(fixture.path, 'missing.wav')),
      CategoryTestAudio('without-art', path: real.path)
    ]);
    addTearDown(repair.dispose);
    await repair.run();
    expect(repair.targets.map((target) => target.status),
        [CoverRepairStatus.unreadable, CoverRepairStatus.noArtwork]);
    expect(await real.readAsBytes(), [0]);
  });
}
