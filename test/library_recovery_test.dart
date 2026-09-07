import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/online/online_library.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory testRoot;
  late Directory dataRoot;
  final audio = Audio.online(
    provider: 'netease',
    id: '123456',
    title: 'Recovery test',
    artist: 'Test artist',
    album: 'Test album',
    duration: 180,
  );

  setUp(() async {
    final parent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    testRoot = await parent.createTemp('library-recovery-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => testRoot.path);
    dataRoot = await getAppDataDir();
    // Never write a fixture to the user's real library if a platform plugin
    // bypasses the test channel on a future Flutter version.
    expect(path.isWithin(testRoot.path, dataRoot.path), isTrue);
    AudioLibrary.instance.replaceOnlineAudios([]);
    PLAYLISTS.clear();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    AudioLibrary.instance.replaceOnlineAudios([]);
    PLAYLISTS.clear();
    final expectedParent =
        path.join(Directory.current.path, 'build', 'test-data');
    if (path.isWithin(expectedParent, testRoot.path)) {
      await testRoot.delete(recursive: true);
    }
  });

  File fixture(String name) => File(path.join(dataRoot.path, name));

  test('refreshing the local index preserves online library entries', () async {
    AudioLibrary.instance.replaceOnlineAudios([audio]);
    await fixture('index.json')
        .writeAsString(jsonEncode({'version': 1, 'folders': []}));

    await AudioLibrary.initFromIndex();

    expect(AudioLibrary.instance.audioByPath[audio.path], same(audio));
    expect(AudioLibrary.instance.onlineAudioCollection, [audio]);
  });

  test(
      'online recovery replaces the corrupt primary without rotating the good backup',
      () async {
    final valid = jsonEncode({
      'version': 1,
      'tracks': [audio.toOnlineMap()]
    });
    await fixture('online_library.json').writeAsString('{broken');
    await fixture('online_library.json.bak').writeAsString(valid);

    await OnlineLibrary.instance.initialize();

    expect(OnlineLibrary.instance.audios.single.path, audio.path);
    expect(await fixture('online_library.json.bak').readAsString(), valid);
    expect(
        jsonDecode(
            await fixture('online_library.json').readAsString())['tracks'],
        hasLength(1));
    expect(await fixture('online_library.json.tmp').exists(), isFalse);
  });

  test('playlist recovery keeps its good backup through the next save',
      () async {
    final valid = jsonEncode([
      Playlist('Recovered', {audio.path: audio}).toMap()
    ]);
    await fixture('playlists.json').writeAsString('{broken');
    await fixture('playlists.json.bak').writeAsString(valid);

    await readPlaylists();
    await savePlaylists();

    expect(PLAYLISTS.single.audios.values.single.isOnline, isTrue);
    expect(await fixture('playlists.json.bak').readAsString(), valid);
    expect(
        decodePlaylists(
                jsonDecode(await fixture('playlists.json').readAsString()))
            .single
            .name,
        'Recovered');
  });

  test('overlapping playlist saves are serialized in request order', () async {
    PLAYLISTS.add(Playlist('First', {}));
    final first = savePlaylists();
    PLAYLISTS.single.name = 'Last';
    final second = savePlaylists();
    await Future.wait([first, second]);

    expect(
        decodePlaylists(
                jsonDecode(await fixture('playlists.json').readAsString()))
            .single
            .name,
        'Last');
    expect(
        decodePlaylists(
                jsonDecode(await fixture('playlists.json.bak').readAsString()))
            .single
            .name,
        'First');
    expect(await fixture('playlists.json.tmp').exists(), isFalse);
  });

  for (final version in [1, 2]) {
    test(
        'statistics v$version recovery preserves history and paused restoration adds no play',
        () async {
      final valid = jsonEncode(
          {'version': version, 'tracks': [], 'days': {}, 'hours': []});
      await fixture('playback_statistics.json').writeAsString('{broken');
      await fixture('playback_statistics.json.bak').writeAsString(valid);

      final statistics = PlaybackStatistics.instance;
      await statistics.initialize();
      expect(statistics.storageWarning, isNull);
      expect(
          await fixture('playback_statistics.json.bak').readAsString(), valid,
          reason:
              'Recovery must not rotate a corrupt primary over the backup.');
      statistics.tick(audio, PlayerState.paused);
      await statistics.flush();

      expect(statistics.totalPlayCount, 0);
      final primary =
          jsonDecode(await fixture('playback_statistics.json').readAsString())
              as Map;
      expect(primary['version'], 2);
      expect(primary['tracks'], isEmpty);
      final originalV1 = fixture('playback_statistics.pre-track-id-v1.json');
      if (version == 1) {
        // The .bak file is a rotating healthy snapshot. The v1 migration keeps
        // its original bytes in a separate immutable file before any rewrite.
        expect(await originalV1.readAsString(), valid);
        final backup = jsonDecode(
            await fixture('playback_statistics.json.bak').readAsString());
        expect(backup, primary);
        await statistics.initialize();
        await statistics.flush();
        expect(await originalV1.readAsString(), valid);
        expect(statistics.totalPlayCount, 0);
      } else {
        expect(await originalV1.exists(), isFalse);
        expect(await fixture('playback_statistics.json.bak').readAsString(),
            valid);
      }
    });
  }
}
