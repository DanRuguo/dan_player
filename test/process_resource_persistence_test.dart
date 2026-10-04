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
  late Directory fixture;
  late File settings;
  late ProcessResourcePreferences original;
  setUpAll(() async {
    final configured = Platform.environment['DAN_PLAYER_DATA_DIR']?.trim();
    fixture = configured != null && configured.isNotEmpty
        ? await Directory(configured).create(recursive: true)
        : await Directory.systemTemp.createTemp('dan-resource-prefs-');
    messenger.setMockMethodCallHandler(provider, (_) async => fixture.path);
    final root = await getAppDataDir();
    expect(
        path.equals(root.path, fixture.path) ||
            path.isWithin(fixture.path, root.path),
        isTrue);
    settings = File(path.join(root.path, 'settings.json'));
    original = AppSettings.instance.processResources.value;
  });
  tearDownAll(() async {
    AppSettings.instance.processResources.value = original;
    messenger.setMockMethodCallHandler(provider, null);
    // QA artifacts are retained with the other evidence. No user directory is read.
  });
  test(
      'actual settings file persists all interval and display choices without window IO',
      () async {
    for (final enabled in [false, true]) {
      for (final interval in ProcessResourcePreferences.intervals) {
        for (final display in ProcessResourceDisplay.values) {
          final value = ProcessResourcePreferences(
              enabled: enabled, intervalSeconds: interval, display: display);
          AppSettings.instance.processResources.value = value;
          await AppSettings.instance
              .saveSettings(throwOnError: true, captureWindowSize: false);
          expect(jsonDecode(await settings.readAsString())['ProcessResources'],
              value.toMap());
          AppSettings.instance.processResources.value =
              const ProcessResourcePreferences();
          await AppSettings.readFromJson();
          expect(AppSettings.instance.processResources.value, value);
        }
      }
    }
  });
  test('actual legacy and malformed settings restore monitor defaults',
      () async {
    for (final value in [
      null,
      {'intervalSeconds': '1', 'display': 'unknown'},
      {'intervalSeconds': 2, 'display': null},
      {'enabled': 'true'}
    ]) {
      await settings.writeAsString(jsonEncode(
          {'Version': '26.0.6', if (value != null) 'ProcessResources': value}));
      AppSettings.instance.processResources.value =
          const ProcessResourcePreferences(
              intervalSeconds: 10, display: ProcessResourceDisplay.bar);
      await AppSettings.readFromJson();
      expect(AppSettings.instance.processResources.value,
          const ProcessResourcePreferences());
    }
  });
}
