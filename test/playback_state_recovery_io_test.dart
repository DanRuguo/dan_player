import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/play_service/playback_state_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a corrupted latest session falls back to the prior completed save',
      () async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final parent = Directory(path.join(Directory.current.parent.path, 'tool',
        'qa-local', 'playback-state-recovery'));
    await parent.create(recursive: true);
    final fixture = await parent.createTemp('profile-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => fixture.path);
    try {
      final data = await getAppDataDir();
      expect(path.isWithin(parent.path, data.path), isTrue);
      const previous = SavedPlaybackState(
        queuePaths: ['C:/music/first.mp3'],
        backupPaths: ['C:/music/first.mp3'],
        index: 0,
        position: 41,
        shuffle: false,
      );
      const current = SavedPlaybackState(
        queuePaths: ['C:/music/second.mp3'],
        backupPaths: ['C:/music/second.mp3'],
        index: 0,
        position: 82,
        shuffle: false,
      );
      await PlaybackStateStore.save(previous);
      await PlaybackStateStore.save(current);
      final latest = File(path.join(data.path, 'playback_state.json'));
      final backup = File('${latest.path}.bak');
      expect(await backup.exists(), isTrue);
      expect((await PlaybackStateStore.load())!.queuePaths,
          ['C:/music/second.mp3']);
      await latest.writeAsString('{damaged');
      final restored = await PlaybackStateStore.load();
      expect(restored?.queuePaths, ['C:/music/first.mp3']);
      expect(restored?.position, 41);

      // The damaged primary must not replace the known-good backup on the
      // next save. A later independent corruption must still have a fallback.
      const newer = SavedPlaybackState(
        queuePaths: ['C:/music/third.mp3'],
        backupPaths: ['C:/music/third.mp3'],
        index: 0,
        position: 93,
        shuffle: false,
      );
      await PlaybackStateStore.save(newer);
      expect((await PlaybackStateStore.load())?.queuePaths,
          ['C:/music/third.mp3']);
      await latest.writeAsString('{damaged again');
      expect((await PlaybackStateStore.load())?.queuePaths,
          ['C:/music/first.mp3']);
    } finally {
      messenger.setMockMethodCallHandler(channel, null);
      final resolved = await fixture.resolveSymbolicLinks();
      final parentResolved = await parent.resolveSymbolicLinks();
      if (!path.isWithin(parentResolved, resolved)) {
        throw StateError('Invalid isolated playback-state cleanup path.');
      }
      await Directory(resolved).delete(recursive: true);
    }
  }, skip: !Platform.isWindows);
}
