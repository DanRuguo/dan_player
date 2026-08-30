import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory fixture;
  late File settingsFile;
  late DesktopLyricAppearance original;

  setUp(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final parent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    fixture = await parent.createTemp('desktop-appearance-');
    messenger.setMockMethodCallHandler(channel, (_) async => fixture.path);
    settingsFile =
        File(path.join((await getAppDataDir()).path, 'settings.json'));
    original = AppSettings.instance.desktopLyricAppearance.value;
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'),
        (call) async {
      throw StateError(
          'Appearance-only save must not read transient native geometry: ${call.method}');
    });
  });
  tearDown(() async {
    AppSettings.instance.desktopLyricAppearance.value = original;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'), null);
    final resolved = await fixture.resolveSymbolicLinks();
    final parent = path.join(Directory.current.path, 'build', 'test-data');
    if (!path.isWithin(parent, resolved) ||
        !path.basename(resolved).startsWith('desktop-appearance-')) {
      throw StateError('Refusing cleanup outside test fixture');
    }
    await Directory(resolved).delete(recursive: true);
  });

  test(
      'real AppSettings file round trips independent appearance without native window calls',
      () async {
    final value = DesktopLyricAppearance.defaults.copyWith(
        lyricFontSize: 40,
        translationFontSize: 36,
        customColor: 0xffeabc17,
        backgroundOpacity: .45,
        textOpacity: .65,
        strokeEnabled: true);
    AppSettings.instance.desktopLyricAppearance.value = value;
    await AppSettings.instance
        .saveSettings(throwOnError: true, captureWindowSize: false);
    final map = jsonDecode(await settingsFile.readAsString());
    expect(map['DesktopLyricAppearance'], value.toJson());
    expect(map['PlayerExperience'], isNot(contains('textOpacity')));
    AppSettings.instance.desktopLyricAppearance.value =
        DesktopLyricAppearance.defaults;
    await AppSettings.readFromJson();
    expect(AppSettings.instance.desktopLyricAppearance.value, value);
  });

  test('old JSON and malformed new fields restore safe defaults independently',
      () async {
    await settingsFile.writeAsString(jsonEncode({'Version': '26.0.0'}));
    AppSettings.instance.desktopLyricAppearance.value =
        DesktopLyricAppearance.defaults.copyWith(textOpacity: .4);
    await AppSettings.readFromJson();
    expect(AppSettings.instance.desktopLyricAppearance.value,
        DesktopLyricAppearance.defaults);
    await settingsFile.writeAsString(jsonEncode({
      'Version': '26.0.0',
      'DesktopLyricAppearance': {
        'lyricFontSize': 30,
        'translationFontSize': -5,
        'textOpacity': 900,
        'backgroundOpacity': 'NaN',
        'strokeEnabled': true,
        'customColor': -1,
      }
    }));
    await AppSettings.readFromJson();
    expect(
        AppSettings.instance.desktopLyricAppearance.value,
        DesktopLyricAppearance.defaults
            .copyWith(lyricFontSize: 30, strokeEnabled: true));
  });

  test('all editor extrema and manual-to-theme color choice survive restart',
      () async {
    final minimum = DesktopLyricAppearance.defaults.copyWith(
        lyricFontSize: 18,
        translationFontSize: 14,
        textOpacity: .2,
        backgroundOpacity: 0,
        customColor: 0xff9c27b0,
        taskbarMode: true,
        taskbarGap: 24,
        taskbarHeight: 80);
    final maximum = minimum.copyWith(
        lyricFontSize: 64,
        translationFontSize: 60,
        textOpacity: 1,
        backgroundOpacity: 1,
        strokeEnabled: true);
    for (final value in [
      minimum,
      maximum,
      maximum.copyWith(followTheme: true)
    ]) {
      AppSettings.instance.desktopLyricAppearance.value = value;
      await AppSettings.instance
          .saveSettings(throwOnError: true, captureWindowSize: false);
      AppSettings.instance.desktopLyricAppearance.value =
          DesktopLyricAppearance.defaults;
      await AppSettings.readFromJson();
      expect(AppSettings.instance.desktopLyricAppearance.value, value);
      expect(
          jsonDecode(
              await settingsFile.readAsString())['DesktopLyricAppearance'],
          value.toJson());
    }
  });

  test('real disk failure propagates while selected appearance remains usable',
      () async {
    final blocked = await Directory(settingsFile.path).create();
    AppSettings.instance.desktopLyricAppearance.value =
        DesktopLyricAppearance.defaults.copyWith(textOpacity: .3);
    await expectLater(
        AppSettings.instance
            .saveSettings(throwOnError: true, captureWindowSize: false),
        throwsA(isA<FileSystemException>()));
    expect(AppSettings.instance.desktopLyricAppearance.value.textOpacity, .3);
    expect(path.isWithin(fixture.path, blocked.path), true);
    await blocked.delete();
    await AppSettings.instance
        .saveSettings(throwOnError: true, captureWindowSize: false);
    expect(
        jsonDecode(await settingsFile.readAsString())['DesktopLyricAppearance']
            ['textOpacity'],
        .3);
  });
}
