import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/online_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;
  late Directory data;
  final library = OnlineLibrary.instance;
  Audio track(String id) => Audio.online(
        provider: 'netease',
        id: id,
        title: 'Synthetic track $id',
        artist: 'Synthetic artist',
        album: 'Synthetic album',
        duration: 120,
      );
  File file(String suffix) =>
      File(p.join(data.path, 'online_library.json$suffix'));
  String contents(List<Audio> tracks, {int version = 1}) => jsonEncode({
        'version': version,
        'tracks': tracks.map((audio) => audio.toOnlineMap()).toList(),
      });

  setUp(() async {
    final parent =
        await Directory(p.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    root = await parent.createTemp('online-read-protection-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    data = await getAppDataDir();
    expect(p.isWithin(root.path, data.path), isTrue);
    await library.initialize();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    AudioLibrary.instance.replaceOnlineAudios([]);
    expect(
        p.isWithin(
            p.join(Directory.current.path, 'build', 'test-data'), root.path),
        isTrue);
    await root.delete(recursive: true);
  });

  test('unreadable primary and backup block mutation without rotating evidence',
      () async {
    await file('').writeAsString('{corrupt primary');
    await file('.bak').writeAsString('{corrupt backup');

    await library.initialize();
    await expectLater(library.add(track('200')), throwsA(isA<Exception>()));

    expect(await file('').readAsString(), '{corrupt primary');
    expect(await file('.bak').readAsString(), '{corrupt backup');
    expect(await file('.tmp').exists(), isFalse);
    expect(library.audios, isEmpty);
  });

  test('failed reload retains the published collection and blocks deletion',
      () async {
    final original = track('201');
    await library.add(original);
    await file('').writeAsString('{corrupt primary');
    await file('.bak').writeAsString('{corrupt backup');

    await library.initialize();

    expect(library.audios.single.path, original.path);
    expect(
        AudioLibrary.instance.onlineAudioCollection.single.path, original.path);
    await expectLater(library.remove(original), throwsA(isA<Exception>()));
    expect(await file('').readAsString(), '{corrupt primary');
    expect(await file('.bak').readAsString(), '{corrupt backup');
  });

  test('newer primary version never falls back to an older writable snapshot',
      () async {
    final future = contents([track('202')], version: 2);
    final backup = contents([track('203')]);
    await file('').writeAsString(future);
    await file('.bak').writeAsString(backup);

    await library.initialize();
    await expectLater(
        library.add(track('204')), throwsA(isA<UnsupportedError>()));

    expect(library.audios, isEmpty);
    expect(await file('').readAsString(), future);
    expect(await file('.bak').readAsString(), backup);
    expect(await file('.tmp').exists(), isFalse);
  });

  test('a successful reload clears protection and keeps recovered tracks',
      () async {
    await file('').writeAsString('{corrupt primary');
    await library.initialize();
    await file('').writeAsString(contents([track('205')]));

    await library.initialize();
    await library.add(track('206'));

    expect(library.audios.map((audio) => audio.onlineId), ['205', '206']);
    final saved = jsonDecode(await file('').readAsString()) as Map;
    expect(saved['version'], 1);
    expect(saved['tracks'], hasLength(2));
  });

  test('an edit waits for a pending reload and keeps the loaded tracks',
      () async {
    await file('').writeAsString(contents([track('207')]));
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      if (++calls == 1) {
        entered.complete();
        await release.future;
      }
      return root.path;
    });
    final reload = library.initialize();
    await entered.future;
    final edit = library.add(track('208'));
    try {
      await Future<void>.delayed(Duration.zero);
      expect(library.audios, isEmpty,
          reason: 'A mutation cannot overtake an unfinished disk read.');
      expect(calls, 1);
    } finally {
      release.complete();
      await Future.wait([reload, edit]);
    }
    expect(library.audios.map((audio) => audio.onlineId), ['207', '208']);
    final saved = jsonDecode(await file('').readAsString()) as Map;
    expect(saved['tracks'], hasLength(2));
  });
}
