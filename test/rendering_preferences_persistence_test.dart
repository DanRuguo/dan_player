import 'dart:convert';
import 'dart:io';
import 'package:dan_player/performance_preset.dart';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/rendering_preferences.dart';
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
  late RenderingPreferences original;

  setUp(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final parent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    fixture = await parent.createTemp('rendering-preferences-');
    messenger.setMockMethodCallHandler(channel, (_) async => fixture.path);
    settingsFile =
        File(path.join((await getAppDataDir()).path, 'settings.json'));
    original = AppSettings.instance.rendering.value;
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'),
        (call) async => throw StateError('No native geometry: ${call.method}'));
  });
  tearDown(() async {
    AppSettings.instance.rendering.value = original;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'), null);
    final resolved = await fixture.resolveSymbolicLinks();
    final parent = path.join(Directory.current.path, 'build', 'test-data');
    if (!path.isWithin(parent, resolved) ||
        !path.basename(resolved).startsWith('rendering-preferences-')) {
      throw StateError('Refusing cleanup outside test fixture');
    }
    await Directory(resolved).delete(recursive: true);
  });

  test('real settings file round trips both choices without window IO',
      () async {
    for (final pause in [false, true]) {
      final value = RenderingPreferences(pauseWhenHidden: pause);
      AppSettings.instance.rendering.value = value;
      await AppSettings.instance
          .saveSettings(throwOnError: true, captureWindowSize: false);
      expect(jsonDecode(await settingsFile.readAsString())['Rendering'],
          value.toMap());
      AppSettings.instance.rendering.value =
          value.copyWith(pauseWhenHidden: !pause);
      await AppSettings.readFromJson();
      expect(AppSettings.instance.rendering.value, value);
    }
  });

  test('a staging write failure preserves the committed recovery checkpoint',
      () async {
    await AppSettings.instance
        .saveSettings(throwOnError: true, captureWindowSize: false);
    final committed = await settingsFile.readAsBytes();
    final blockedStage =
        await Directory('${settingsFile.path}.pending').create();
    AppSettings.instance.rendering.value =
        const RenderingPreferences(lyricSpectrum: false);
    await expectLater(
        AppSettings.instance.saveSettings(
            throwOnError: true, captureWindowSize: false, requireCommit: true),
        throwsA(isA<FileSystemException>()));
    expect(await settingsFile.readAsBytes(), committed);
    await blockedStage.delete();
    await AppSettings.instance
        .saveSettings(throwOnError: true, captureWindowSize: false);
    expect(
        jsonDecode(await settingsFile.readAsString())['Rendering']
            ['lyricSpectrum'],
        false);
    expect(await File('${settingsFile.path}.pending').exists(), false);
  });

  test('legacy and malformed real settings restore default-on', () async {
    for (final raw in [
      null,
      {},
      {'pauseWhenHidden': 'false'}
    ]) {
      await settingsFile.writeAsString(jsonEncode({
        'Version': '26.0.0',
        if (raw != null) 'Rendering': raw,
      }));
      AppSettings.instance.rendering.value =
          const RenderingPreferences(pauseWhenHidden: false);
      await AppSettings.readFromJson();
      expect(
          AppSettings.instance.rendering.value, const RenderingPreferences());
    }
  });

  test('disk failure preserves session choice and remains retryable', () async {
    final blocked = await Directory(settingsFile.path).create();
    AppSettings.instance.rendering.value =
        const RenderingPreferences(pauseWhenHidden: false);
    await expectLater(
        AppSettings.instance
            .saveSettings(throwOnError: true, captureWindowSize: false),
        throwsA(isA<FileSystemException>()));
    expect(AppSettings.instance.rendering.value.pauseWhenHidden, isFalse);
    expect(path.isWithin(fixture.path, blocked.path), isTrue);
    await blocked.delete();
    await AppSettings.instance
        .saveSettings(throwOnError: true, captureWindowSize: false);
    expect(jsonDecode(await settingsFile.readAsString())['Rendering'], {
      'pauseWhenHidden': false,
      'lyricSpectrum': true,
      'compactSpectrum': true,
      'surfaceBlur': true,
      'spectrumDensity': 'high',
      'frameRate': {'mode': 'display', 'fps': 60},
    });
  });

  test('preset recovery copy survives an actual settings save and reload',
      () async {
    final controller = AppSettings.instance.performancePresets;
    final oldState = controller.value;
    final before = controller.capture();
    addTearDown(() {
      controller.apply(before);
      controller.value = oldState;
    });
    controller.value = const PerformancePresetState();
    await controller.select(PerformanceMode.economy);
    var saved = jsonDecode(await settingsFile.readAsString());
    expect(saved['PerformancePreset']['mode'], 'economy');
    expect(saved['PerformancePreset']['before'], before.toMap());
    controller.value = const PerformancePresetState();
    await AppSettings.readFromJson();
    expect(controller.value.mode, PerformanceMode.economy);
    await controller.select(PerformanceMode.custom);
    expect(controller.capture().toMap(), before.toMap());
    saved = jsonDecode(await settingsFile.readAsString());
    expect(saved['PerformancePreset'], {'mode': 'custom'});
  });
}
