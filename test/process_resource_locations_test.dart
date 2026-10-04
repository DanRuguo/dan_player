import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const provider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late File settings;
  late ProcessResourcePreferences original;

  setUpAll(() async {
    final fixture =
        await Directory.systemTemp.createTemp('resource-locations-');
    messenger.setMockMethodCallHandler(provider, (_) async => fixture.path);
    final root = await getAppDataDir();
    expect(
        path.isWithin(fixture.path, root.path) ||
            path.equals(root.path, fixture.path),
        isTrue);
    settings = File(path.join(root.path, 'settings.json'));
    original = AppSettings.instance.processResources.value;
  });
  tearDownAll(() {
    AppSettings.instance.processResources.value = original;
    messenger.setMockMethodCallHandler(provider, null);
  });

  test('legacy resources stay settings-only; malformed locations stay off', () {
    for (final value in [null, 'true', 1, [], {}]) {
      final prefs = ProcessResourcePreferences.fromMap({
        'enabled': true,
        'display': 'line',
        'intervalSeconds': 10,
        'showInSidebar': value,
        'showInLyrics': value,
      });
      expect(prefs.enabled, isTrue);
      expect(prefs.display, ProcessResourceDisplay.line);
      expect(prefs.intervalSeconds, 10);
      expect(prefs.showInSidebar, isFalse);
      expect(prefs.showInLyrics, isFalse);
    }
    final legacy = ProcessResourcePreferences.fromMap({'enabled': true});
    expect(legacy.showInSidebar || legacy.showInLyrics, isFalse);
    expect(legacy.copyWith(showInSidebar: true), isNot(legacy));
    expect(legacy.copyWith(showInLyrics: true), isNot(legacy));
  });

  test('real settings retain independent locations through disable and reload',
      () async {
    for (final sidebar in [false, true]) {
      for (final lyrics in [false, true]) {
        var prefs = ProcessResourcePreferences(
            enabled: true,
            showInSidebar: sidebar,
            showInLyrics: lyrics,
            display: ProcessResourceDisplay.bar,
            intervalSeconds: 1);
        for (final enabled in [true, false, true]) {
          prefs = prefs.copyWith(enabled: enabled);
          AppSettings.instance.processResources.value = prefs;
          await AppSettings.instance
              .saveSettings(throwOnError: true, captureWindowSize: false);
          final data = jsonDecode(await settings.readAsString()) as Map;
          expect(data['ProcessResources'], prefs.toMap());
          AppSettings.instance.processResources.value =
              const ProcessResourcePreferences();
          await AppSettings.readFromJson();
          expect(AppSettings.instance.processResources.value, prefs);
        }
      }
    }
  });
}
