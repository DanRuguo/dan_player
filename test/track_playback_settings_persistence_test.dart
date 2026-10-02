import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/data/backup_selection.dart';
import 'package:dan_player/data/protected_json_store.dart';
import 'package:dan_player/library/library_data_migration.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/play_service/track_playback_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/music_category_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late File file;
  late PersonalLibrary library;
  final audio = CategoryTestAudio('saved', online: true);
  final other = CategoryTestAudio('other', online: true);
  final parent = p.normalize(p.join(Directory.current.path, '..', 'tool',
      'qa-local', 'track-playback-settings', 'persistence'));
  setUp(() async {
    await Directory(parent).create(recursive: true);
    fixture = await Directory(parent).createTemp('store-');
    file = File(p.join(fixture.path, 'personal_library.json'));
    library = PersonalLibrary(file);
    // setPlayback flushes stable identities. Its root is explicit QA, even
    // though these online identities require no local registry record.
    await TrackIdentityRegistry.instance.initialize(directory: fixture);
  });
  tearDown(() async {
    expect(p.isWithin(parent, await fixture.resolveSymbolicLinks()), isTrue);
    await fixture.delete(recursive: true);
    PersonalLibrary.latest = const {};
  });

  Map<String, Object?> legacy() => {
        'version': 1,
        'seeded': true,
        'tracks': {
          audio.stableTrackId: {
            'rating': 5,
            'tags': ['夜晚', 'D:/literal tag'],
            'added': 1000,
            'addedFromCreation': true,
            'modified': 2000,
            'futureExtension': {'keep': true}
          },
          other.stableTrackId: {
            'rating': 2,
            'tags': ['other']
          },
        }
      };

  test('save reload clear retain legacy ratings tags dates and other track',
      () async {
    await file.writeAsString(jsonEncode(legacy()));
    expect(await library.playbackFor(audio.stableTrackId), isNull);
    const profile = TrackPlaybackSettings(rate: .875, pitch: -2.5);
    await library.setPlayback(audio, profile);
    final reloaded = PersonalLibrary(file);
    expect((await reloaded.playbackFor(audio.stableTrackId))!.toMap(),
        profile.toMap());
    final saved = await reloaded.store.readEntry('tracks', audio.stableTrackId);
    expect(saved!['rating'], 5);
    expect(saved['tags'], ['夜晚', 'D:/literal tag']);
    expect(saved['added'], 1000);
    expect(saved['addedFromCreation'], isTrue);
    expect(saved['futureExtension'], {'keep': true});
    expect(await reloaded.store.readEntry('tracks', other.stableTrackId), {
      'rating': 2,
      'tags': ['other']
    });
    await reloaded.setPlayback(audio, null);
    final cleared = await PersonalLibrary(file)
        .store
        .readEntry('tracks', audio.stableTrackId);
    expect(cleared!.containsKey('playback'), isFalse);
    expect(cleared['rating'], 5);
    expect(cleared['tags'], saved['tags']);
    expect(cleared['added'], saved['added']);
  });

  test('bad exponent and partial profile do not discard valid personal data',
      () async {
    final raw = legacy();
    final tracks = raw['tracks'] as Map;
    (tracks[audio.stableTrackId] as Map)['playback'] = {
      'rate': 'EXPONENT',
      'pitch': 3
    };
    (tracks[other.stableTrackId] as Map)['playback'] = {'rate': 1};
    await file.writeAsString(jsonEncode(raw).replaceAll('"EXPONENT"', '1e400'));
    expect(await library.playbackFor(audio.stableTrackId), isNull);
    expect(await library.playbackFor(other.stableTrackId), isNull);
    final snapshot = await library.snapshot();
    expect(snapshot[audio.stableTrackId]!.rating, 5);
    expect(snapshot[audio.stableTrackId]!.tags, ['夜晚', 'D:/literal tag']);
    await library.setPlayback(
        audio, const TrackPlaybackSettings(rate: 1.5, pitch: 2));
    final rawSaved = jsonDecode(await file.readAsString()) as Map;
    final personal = (rawSaved['tracks'] as Map)[audio.stableTrackId] as Map;
    expect(personal['playback'], {'rate': 1.5, 'pitch': 2});
    expect(personal['rating'], 5);
    expect(personal['futureExtension'], {'keep': true});
  });

  test('single entry reads wait for earlier queued commit and stay detached',
      () async {
    await file.writeAsString(jsonEncode(legacy()));
    await library.store.readEntry('tracks', audio.stableTrackId);
    final gate = Completer<void>();
    final held = ProtectedJsonStore.withSnapshot(() => gate.future);
    final commit = library.store.update((root) {
      ((root['tracks'] as Map)[audio.stableTrackId] as Map)['playback'] = {
        'rate': 1.25,
        'pitch': 4
      };
    });
    var finished = false;
    final reading = library.playbackFor(audio.stableTrackId).then((value) {
      finished = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    gate.complete();
    await held;
    await commit;
    expect((await reading)!.toMap(), {'rate': 1.25, 'pitch': 4});
    final detached =
        await library.store.readEntry('tracks', audio.stableTrackId);
    (detached!['tags'] as List).clear();
    (detached['playback'] as Map)['rate'] = 2;
    final reread = await library.store.readEntry('tracks', audio.stableTrackId);
    expect(reread!['tags'], ['夜晚', 'D:/literal tag']);
    expect(reread['playback'], {'rate': 1.25, 'pitch': 4});
    expect(await library.store.readEntry('tracks', 'missing'), isNull);
  });

  test('failed commit leaves single entry reader on committed value', () async {
    await file.writeAsString(jsonEncode(legacy()));
    final store = ProtectedJsonStore(file,
        validate: PersonalLibrary.validate, maxBytes: 1024);
    final before = await store.readEntry('tracks', audio.stableTrackId);
    await expectLater(store.update((root) {
      ((root['tracks'] as Map)[audio.stableTrackId] as Map)['futureExtension'] =
          'x' * 2048;
    }),
        throwsA(isA<StateError>().having((error) => error.message, 'capacity',
            'User data capacity reached')));
    expect(await store.readEntry('tracks', audio.stableTrackId), before);
    expect(jsonDecode(await file.readAsString()), legacy());
  });

  test('future version read and writes do not fall back to an older backup',
      () async {
    final bytes = jsonEncode({'version': 2, 'tracks': {}});
    await file.writeAsString(bytes);
    await File('${file.path}.bak').writeAsString(jsonEncode(legacy()));
    await expectLater(
        library.playbackFor(audio.stableTrackId), throwsUnsupportedError);
    await expectLater(
        library.setPlayback(
            audio, const TrackPlaybackSettings(rate: 1.2, pitch: 1)),
        throwsUnsupportedError);
    expect(await file.readAsString(), bytes);
  });

  test('profile remains in existing personal backup and stable-id migration',
      () {
    final data = legacy();
    ((data['tracks'] as Map)[audio.stableTrackId] as Map)['playback'] = {
      'rate': .75,
      'pitch': -3
    };
    expect(backupComponentForPath('personal_library.json'),
        BackupComponent.playlists);
    expect(backupComponentForPath('personal_library.json.bak'),
        BackupComponent.playlists);
    expect(
        remapLibraryDocument(data, LibraryPathMapping('D:/Music', 'E:/Music')),
        data);
  });
}
