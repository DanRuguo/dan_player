import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final override = Platform.environment['DAN_PLAYER_DATA_DIR']?.trim();
  late Directory fixture;
  late File settingsFile;
  final settings = AppSettings.instance;
  final originalDynamicTheme = settings.dynamicTheme;
  final originalLocalFirst = settings.localLyricFirst;
  final originalAutomatic = settings.automaticOnlineLyrics.value;

  setUpAll(() async {
    if (override != null && override.isNotEmpty) {
      final qaRoot = path.normalize(
          path.join(Directory.current.parent.path, 'tool', 'qa-local'));
      if (!path.isWithin(qaRoot, path.normalize(override))) {
        throw StateError('Settings fixture must be inside workspace QA data');
      }
      fixture = await Directory(override).create(recursive: true);
    } else {
      final parent = await Directory(
              path.join(Directory.current.path, 'build', 'test-data'))
          .create(recursive: true);
      fixture = await parent.createTemp('app-settings-legacy-boolean-');
      messenger.setMockMethodCallHandler(channel, (_) async => fixture.path);
    }
    // The mocked provider returns Documents/Support, while the default data
    // root adds the player's directory name. Write the file the real reader
    // will consume in both the default and explicit-override test modes.
    final data = await getAppDataDir();
    expect(
        path.equals(fixture.path, data.path) ||
            path.isWithin(fixture.path, data.path),
        isTrue,
        reason: 'settings reader must remain inside the isolated fixture');
    settingsFile = File(path.join(data.path, 'settings.json'));
  });

  tearDownAll(() async {
    settings.dynamicTheme = originalDynamicTheme;
    settings.localLyricFirst = originalLocalFirst;
    settings.automaticOnlineLyrics.value = originalAutomatic;
    messenger.setMockMethodCallHandler(channel, null);
    if (override == null || override.isEmpty) {
      final resolved = await fixture.resolveSymbolicLinks();
      final parent = path.join(Directory.current.path, 'build', 'test-data');
      if (!path.isWithin(parent, resolved) ||
          !path.basename(resolved).startsWith('app-settings-legacy-boolean-')) {
        throw StateError('Refusing cleanup outside test fixture');
      }
      await Directory(resolved).delete(recursive: true);
    } else if (await settingsFile.exists()) {
      await settingsFile.delete();
    }
  });

  test('unversioned boolean and integer flags retain their meaning', () async {
    for (final value in [true, 1, false, 0]) {
      final expected = value == true || value == 1;
      settings.dynamicTheme = !expected;
      settings.localLyricFirst = !expected;
      await settingsFile.writeAsString(jsonEncode({
        'DynamicTheme': value,
        'LocalLyricFirst': value,
        'ArtistSeparator': ['/', '、'],
      }));

      await AppSettings.readFromJson();
      expect(settings.dynamicTheme, expected, reason: '$value dynamic theme');
      expect(settings.localLyricFirst, expected,
          reason: '$value lyric priority');
    }
  });

  test('missing and invalid legacy flags follow their prior defaults',
      () async {
    settings.dynamicTheme = true;
    settings.localLyricFirst = true;
    await settingsFile.writeAsString(jsonEncode({
      'ArtistSeparator': ['/', '、'],
      'LocalLyricFirst': 'invalid',
    }));

    await AppSettings.readFromJson();
    expect(settings.dynamicTheme, isFalse);
    expect(settings.localLyricFirst, isTrue);
  });

  test('invalid versioned flags do not interrupt later settings', () async {
    settings.dynamicTheme = true;
    settings.localLyricFirst = false;
    settings.automaticOnlineLyrics.value = false;
    await settingsFile.writeAsString(jsonEncode({
      'Version': AppSettings.version,
      'DynamicTheme': 'invalid',
      'LocalLyricFirst': 'invalid',
      'AutomaticOnlineLyrics': true,
    }));

    await AppSettings.readFromJson();
    expect(settings.dynamicTheme, isTrue);
    expect(settings.localLyricFirst, isFalse);
    expect(settings.automaticOnlineLyrics.value, isTrue);
  });
}
