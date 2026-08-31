import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/update/update_channel_preference.dart';
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
  late UpdateChannelPreference previous;
  setUp(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final parent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    fixture = await parent.createTemp('update-prefs-');
    messenger.setMockMethodCallHandler(dataChannel, (_) async => fixture.path);
    messenger.setMockMethodCallHandler(windowChannel,
        (_) async => throw StateError('No native window access'));
    settingsFile =
        File(path.join((await getAppDataDir()).path, 'settings.json'));
    previous = AppSettings.instance.updateChannel;
  });
  tearDown(() async {
    AppSettings.instance.updateChannel = previous;
    messenger.setMockMethodCallHandler(dataChannel, null);
    messenger.setMockMethodCallHandler(windowChannel, null);
    final resolved = await fixture.resolveSymbolicLinks();
    final parent = path.join(Directory.current.path, 'build', 'test-data');
    if (!path.isWithin(parent, resolved) ||
        !path.basename(resolved).startsWith('update-prefs-')) {
      throw StateError('Refusing cleanup outside the update fixture');
    }
    await Directory(resolved).delete(recursive: true);
  });
  test(
      'real JSON preserves explicit on and off independent of snapshot default',
      () async {
    for (final value in [false, true]) {
      AppSettings.instance.receivePreviewUpdates = value;
      await AppSettings.instance
          .saveSettings(throwOnError: true, captureWindowSize: false);
      expect(
          jsonDecode(
              await settingsFile.readAsString())['ReceivePreviewUpdates'],
          value);
      AppSettings.instance.updateChannel = const UpdateChannelPreference();
      await AppSettings.readFromJson();
      expect(AppSettings.instance.receivePreviewUpdates, value);
    }
  });
  test('legacy JSON remains implicit after unrelated save', () async {
    await settingsFile.writeAsString(jsonEncode({'Version': '26.0.3'}));
    AppSettings.instance.receivePreviewUpdates = false;
    await AppSettings.readFromJson();
    expect(AppSettings.instance.updateChannel.receivePreviews, isNull);
    await AppSettings.instance
        .saveSettings(throwOnError: true, captureWindowSize: false);
    expect(
        jsonDecode(await settingsFile.readAsString())
            .containsKey('ReceivePreviewUpdates'),
        isFalse);
  });
}
