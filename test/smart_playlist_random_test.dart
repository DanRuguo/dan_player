import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/data/cache_backup_service.dart';
import 'package:dan_player/data/snapshot3_upgrade.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/music_category_fixtures.dart';

class _Track extends CategoryTestAudio {
  _Track(super.id, {super.artist, super.online});
  int reads = 0;
  @override
  String get stableTrackId {
    reads++;
    return 'test:$path';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const randomRule = SmartPlaylist(
      id: 'random',
      name: 'Sample',
      sort: SmartPlaylistSort.random,
      maxResults: 7);
  late Directory fixture;
  setUpAll(() async {
    final parent = Directory(p.join(Directory.current.parent.path, 'tool',
        'qa-local', 'smart-random-next', 'data'));
    await parent.create(recursive: true);
    fixture = await parent.createTemp('random-store-');
  });
  tearDownAll(() async => fixture.delete(recursive: true));

  test(
      'random sample filters first, is distinct and preserves original objects',
      () async {
    final eligible = List.generate(20, (i) => _Track('Match $i', artist: 'A'));
    final library = <Audio>[
      ...eligible,
      eligible.first,
      _Track('Other', artist: 'B'),
      _Track('Online', artist: 'A', online: true),
    ];
    const rule = SmartPlaylist(
        id: 'random',
        name: 'Sample',
        artist: 'A',
        sort: SmartPlaylistSort.random,
        maxResults: 7);
    final result = await rule.evaluate(library, randomSeed: 41);
    expect(result, hasLength(7));
    expect(result.map((a) => a.stableTrackId).toSet(), hasLength(7));
    expect(result.every(eligible.contains), isTrue);
    expect(() => result.add(eligible.first), throwsUnsupportedError);
    expect(library.first, same(eligible.first));
    expect(library.last.displayTitle, 'Online');
  });

  test(
      'retained seed reproduces a batch; another seed changes order and subset',
      () async {
    final tracks = List.generate(100, (i) => _Track('$i'));
    final first = await randomRule.evaluate(tracks, randomSeed: 1);
    expect(await randomRule.evaluate(tracks, randomSeed: 1), first);
    final next = await randomRule.evaluate(tracks, randomSeed: 2);
    expect(next, isNot(orderedEquals(first)));
    expect(next.toSet(), isNot(first.toSet()));
    expect(randomRule.toJson().containsKey('randomSeed'), isFalse);
  });

  test(
      'unlimited sampling shuffles all unique matches; small and empty are safe',
      () async {
    const rule =
        SmartPlaylist(id: 'all', name: 'All', sort: SmartPlaylistSort.random);
    final tracks = List.generate(30, (i) => _Track('$i'));
    final result =
        await rule.evaluate([...tracks, tracks.first], randomSeed: 8);
    expect(result.toSet(), tracks.toSet());
    expect(result, isNot(orderedEquals(tracks)));
    expect(await randomRule.evaluate([], randomSeed: 8), isEmpty);
    expect(await randomRule.evaluate([tracks.first], randomSeed: 8),
        [same(tracks.first)]);
  });

  test(
      'random duplicate identity collapses but different versions and CUE stay',
      () async {
    const cue = CueTrackReference(
        cuePath: 'J:/fixtures/album.cue',
        sourcePath: 'J:/fixtures/album.flac',
        number: 2,
        startFrame: 750,
        endFrame: 1500);
    final first = _Track('Title');
    final repeatedIdentity = _Track('Title');
    final version = CategoryTestAudio('Title', path: 'J:/fixtures/other.flac');
    final slice = Audio.fromMap({
      'path': cue.identity,
      'title': 'Title',
      'duration': 10,
      'cue_track': cue.toMap()
    });
    const rule =
        SmartPlaylist(id: 'all', name: 'All', sort: SmartPlaylistSort.random);
    final result = await rule
        .evaluate([first, repeatedIdentity, version, slice], randomSeed: 6);
    expect(result, hasLength(3));
    expect(result, containsAll([same(first), same(version), same(slice)]));
    expect(result, isNot(contains(same(repeatedIdentity))));
    expect(
        await const SmartPlaylist(id: 'fixed', name: 'Fixed')
            .evaluate([first, repeatedIdentity]),
        hasLength(2),
        reason: 'Existing fixed-order duplicate behavior is preserved.');
  });

  test('large random pool has linear identity work and honors cancellation',
      () async {
    final tracks = List.generate(12000, (i) => _Track('$i'));
    expect(await randomRule.evaluate(tracks, randomSeed: 3), hasLength(7));
    expect(tracks.fold<int>(0, (sum, a) => sum + a.reads), tracks.length);
    var cancelled = false;
    final pending = randomRule.evaluate(tracks,
        randomSeed: 3, shouldCancel: () => cancelled);
    cancelled = true;
    expect(await pending, isEmpty);
    expect(tracks.fold<int>(0, (sum, a) => sum + a.reads), tracks.length);
  });

  test('worker never captures non-sendable cancellation callback owners',
      () async {
    final port = ReceivePort();
    addTearDown(port.close);
    expect(
        await randomRule.evaluate(List.generate(30, (i) => _Track('$i')),
            randomSeed: 1, shouldCancel: () {
          port.hashCode;
          return false;
        }),
        hasLength(7));
  });

  test(
      'random schema round trips alongside old rules and returns to legacy schema',
      () async {
    final file = File(p.join(fixture.path, 'roundtrip.json'));
    final store = SmartPlaylistStore(file);
    const old = SmartPlaylist(id: 'old', name: 'Name order');
    await store.upsert(old);
    expect(jsonDecode(await file.readAsString())['version'], 4);
    await store.upsert(randomRule);
    final raw = jsonDecode(await file.readAsString());
    expect(raw['version'], 5);
    expect(raw['randomSampling'], 1);
    expect(raw['playlists'][1]['sort'], 'random');
    final loaded = await SmartPlaylistStore(file).list();
    expect(loaded.first.toJson(), old.toJson());
    expect(loaded.last.toJson(), randomRule.toJson());
    await store.remove(randomRule.id);
    expect(jsonDecode(await file.readAsString())['version'], 4);
    expect(
        (await SmartPlaylistStore(file).list()).single.toJson(), old.toJson());
  });

  test('unrecognized random schemas refuse backup recovery or overwriting',
      () async {
    for (final raw in [
      {
        'version': 5,
        'playlists': [randomRule.toJson()]
      },
      {
        'version': 5,
        'randomSampling': 2,
        'playlists': [randomRule.toJson()]
      },
      {
        'version': 4,
        'playlists': [randomRule.toJson()]
      },
      {'version': 4, 'randomSampling': 1, 'playlists': []},
      {'version': 5, 'randomSampling': 1.0, 'playlists': []},
      {'version': 5.0, 'randomSampling': 1, 'playlists': []},
      {'version': 6, 'randomSampling': 1, 'playlists': []},
    ]) {
      final file = File(p.join(fixture.path, 'unknown.json'));
      final before = jsonEncode(raw);
      await file.writeAsString(before);
      await File('${file.path}.bak').writeAsString(jsonEncode({
        'version': 4,
        'playlists': [const SmartPlaylist(id: 'old', name: 'Old').toJson()]
      }));
      await expectLater(
          SmartPlaylistStore(file).upsert(randomRule), throwsUnsupportedError);
      expect(await file.readAsString(), before);
      expect(
          () => Snapshot3Upgrade.validateDocument('smart_playlists.json', raw),
          throwsUnsupportedError);
    }
  });

  test(
      'random rules survive startup validation, backup export and real restore',
      () async {
    final source = Directory(p.join(fixture.path, 'source'));
    final file = File(p.join(source.path, 'smart_playlists.json'));
    await SmartPlaylistStore(file).upsert(randomRule);
    final before = await file.readAsString();
    Snapshot3Upgrade.validateDocument(
        'smart_playlists.json', jsonDecode(before));
    const service = CacheBackupService();
    final backup = File(p.join(fixture.path, 'random-rules.zip'));
    await service.exportBackup(
        source: source,
        destination: backup,
        selection:
            const BackupSelection(components: {BackupComponent.playlists}));
    Directory? restored;
    await service.restoreBackup(
        backup: backup,
        currentData: source,
        destination: Directory(p.join(fixture.path, 'restored')),
        activateLocation: (_, staged) async => restored = staged);
    final recovered = File(p.join(restored!.path, 'smart_playlists.json'));
    expect((await SmartPlaylistStore(recovered).list()).single.toJson(),
        randomRule.toJson());
    expect(await file.readAsString(), before);
  });

  test('extension marker retains duplicate ID and invalid enum validation', () {
    expect(
        () => SmartPlaylistStore.validateSnapshot({
              'version': 5,
              'randomSampling': 1,
              'playlists': [randomRule.toJson(), randomRule.toJson()]
            }),
        throwsFormatException);
    expect(
        () => SmartPlaylistStore.validateSnapshot({
              'version': 5,
              'randomSampling': 1,
              'playlists': [
                {...randomRule.toJson(), 'sort': 'unknown'}
              ]
            }),
        throwsFormatException);
  });
}
