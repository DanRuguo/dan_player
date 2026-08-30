import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const dataChannel = MethodChannel('plugins.flutter.io/path_provider');
  const windowChannel = MethodChannel('window_manager');
  late Directory fixture;
  late File settingsFile;
  late PlayerExperiencePreferences original;

  setUp(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final parent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    fixture = await parent.createTemp('tray-blur-');
    messenger.setMockMethodCallHandler(dataChannel, (_) async => fixture.path);
    messenger.setMockMethodCallHandler(
        windowChannel,
        (call) async => throw StateError(
            'Tray preferences must not read native geometry: ${call.method}'));
    settingsFile =
        File(path.join((await getAppDataDir()).path, 'settings.json'));
    original = AppSettings.instance.experience.value;
  });

  tearDown(() async {
    AppSettings.instance.experience.value = original;
    messenger.setMockMethodCallHandler(dataChannel, null);
    messenger.setMockMethodCallHandler(windowChannel, null);
    final resolved = await fixture.resolveSymbolicLinks();
    final parent = path.join(Directory.current.path, 'build', 'test-data');
    if (!path.isWithin(parent, resolved) ||
        !path.basename(resolved).startsWith('tray-blur-')) {
      throw StateError('Refusing cleanup outside the tray blur test fixture');
    }
    await Directory(resolved).delete(recursive: true);
  });

  test(
      'real settings JSON retains tray radius and unrelated experience on restart',
      () async {
    for (final radius in [0.0, 12.0, 24.0]) {
      final saved = original.copyWith(
          trayMenuBlurRadius: radius, closeToTray: true, playbackRate: 1.5);
      AppSettings.instance.experience.value = saved;
      await AppSettings.instance
          .saveSettings(throwOnError: true, captureWindowSize: false);
      expect(
          jsonDecode(await settingsFile.readAsString())['PlayerExperience']
              ['trayMenuBlurRadius'],
          radius);
      AppSettings.instance.experience.value =
          const PlayerExperiencePreferences();
      await AppSettings.readFromJson();
      expect(AppSettings.instance.experience.value, saved);
    }
  });

  test('legacy settings do not turn screen capture on', () async {
    await settingsFile.writeAsString(jsonEncode({
      'Version': '26.0.0',
      'PlayerExperience': {'closeToTray': true}
    }));
    AppSettings.instance.experience.value =
        original.copyWith(trayMenuBlurRadius: 24);
    await AppSettings.readFromJson();
    expect(AppSettings.instance.experience.value.trayMenuBlurRadius, 0);
    expect(AppSettings.instance.experience.value.closeToTray, true);
  });
}
