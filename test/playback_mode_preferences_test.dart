import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/play_service/playback_modes.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shuffle is independent of all repeat policies and survives JSON', () {
    for (final mode in PlayMode.values) {
      for (final shuffle in [false, true]) {
        final pref = PlaybackPreference(mode, .37,
            shuffle: shuffle, eqEnabled: true, eqGains: List.filled(10, 1.5));
        final restored =
            PlaybackPreference.fromMap(jsonDecode(jsonEncode(pref.toMap())));
        expect(restored.playMode, mode);
        expect(restored.shuffle, shuffle);
        expect(restored.volumeDsp, .37);
        expect(restored.eqEnabled, isTrue);
        expect(restored.eqGains, List.filled(10, 1.5));
      }
    }
  });

  test('missing/invalid shuffle remains legacy null while explicit false wins',
      () {
    for (final raw in [
      {},
      {'shuffle': null},
      {'shuffle': 'true'}
    ]) {
      final legacy = PlaybackPreference.fromMap(raw);
      expect(legacy.shuffle, isNull);
      expect(legacy.toMap().containsKey('shuffle'), isFalse);
      expect(legacy.shuffle ?? true, isTrue,
          reason: 'Legacy saved queue can migrate.');
    }
    final explicit = PlaybackPreference.fromMap({'shuffle': false});
    expect(explicit.shuffle ?? true, isFalse);
  });

  test('empty queue choice persists independently of playback_state.json',
      () async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final parent = Directory(path.join(
        Directory.current.parent.path, 'tool', 'qa-local', 'snapshot5-modes'));
    await parent.create(recursive: true);
    final fixture = await parent.createTemp('preferences-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => fixture.path);
    try {
      final data = await getAppDataDir();
      expect(path.isWithin(parent.path, data.path), isTrue);
      final file = File(path.join(data.path, 'app_preference.json'));
      final pref = AppPreference();
      pref.playbackPref.shuffle = true;
      pref.playbackPref.playMode = PlayMode.singleLoop;
      await pref.save();
      var stored = jsonDecode(await file.readAsString()) as Map;
      var restored = PlaybackPreference.fromMap(stored['playbackPref']);
      expect(restored.shuffle, isTrue);
      expect(restored.playMode, PlayMode.singleLoop);
      pref.playbackPref.shuffle = false;
      await pref.save();
      stored = jsonDecode(await file.readAsString()) as Map;
      restored = PlaybackPreference.fromMap(stored['playbackPref']);
      expect(restored.shuffle, isFalse);
      expect(restored.playMode, PlayMode.singleLoop);
      expect(await File(path.join(data.path, 'playback_state.json')).exists(),
          isFalse);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      final resolved = await fixture.resolveSymbolicLinks();
      final parentResolved = await parent.resolveSymbolicLinks();
      if (!path.isWithin(parentResolved, resolved)) {
        throw StateError('Invalid QA cleanup path.');
      }
      await Directory(resolved).delete(recursive: true);
    }
  });
}
