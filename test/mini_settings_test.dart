import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/window_geometry.dart';
import 'package:dan_player/window_mode_controller.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/fake_window_mode_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory testParent;
  late Directory testRoot;
  late Directory dataRoot;
  late FakeWindowModeAdapter window;
  late Size previousSize;
  late bool previousMaximized;
  final pendingGates = <Completer<void>>[];

  File getSettingsFile() => File(path.join(dataRoot.path, 'settings.json'));
  Future<Map<String, dynamic>> readSettings() async =>
      jsonDecode(await getSettingsFile().readAsString())
          as Map<String, dynamic>;

  setUp(() async {
    // An inherited user override must never redirect this test's fixtures.
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty,
        reason: 'Unset DAN_PLAYER_DATA_DIR before isolated settings tests');
    testParent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    testRoot = await testParent.createTemp('mini-settings-');
    messenger.setMockMethodCallHandler(pathChannel, (_) async => testRoot.path);
    dataRoot = await getAppDataDir();
    expect(path.isWithin(testRoot.path, dataRoot.path), isTrue,
        reason: 'Fixtures must stay in this test-created workspace directory');
    window = FakeWindowModeAdapter();
    messenger.setMockMethodCallHandler(windowChannel, window.handleMethodCall);
    expect(WindowModeController.instance.isBusy, isFalse);
    expect(WindowModeController.instance.isMini, isFalse);
    previousSize = AppSettings.instance.windowSize;
    previousMaximized = AppSettings.instance.isWindowMaximized;
    AppSettings.instance.windowSize = const Size(1280, 756);
    AppSettings.instance.isWindowMaximized = false;
  });

  tearDown(() async {
    for (final gate in pendingGates) {
      if (!gate.isCompleted) gate.complete();
    }
    pendingGates.clear();
    window.beforeCall = null;
    await WindowModeController.instance.exit();
    AppSettings.instance.windowSize = previousSize;
    AppSettings.instance.isWindowMaximized = previousMaximized;
    messenger.setMockMethodCallHandler(windowChannel, null);
    messenger.setMockMethodCallHandler(pathChannel, null);
    final resolvedParent = await testParent.resolveSymbolicLinks();
    final resolvedRoot = await testRoot.resolveSymbolicLinks();
    if (!path.isWithin(resolvedParent, resolvedRoot) ||
        !path.basename(resolvedRoot).startsWith('mini-settings-')) {
      throw StateError('Refusing to remove an unverified fixture directory');
    }
    await Directory(resolvedRoot).delete(recursive: true);
  });

  test('normal saves use actual current normal bounds', () async {
    await AppSettings.instance.saveSettings();
    final saved = await readSettings();
    expect(saved['WindowSize'], '900.0,700.0');
    expect(saved[WindowGeometryPolicy.schemaKey],
        WindowGeometryPolicy.currentSchemaVersion);
    expect(saved['IsWindowMaximized'], isFalse);
    expect(saved['Version'], AppSettings.version);
    expect(AppSettings.instance.windowSize, const Size(900, 700));
    expect(PlayService.isInitialized, isFalse);
  });

  test('legacy maximized minimum-square geometry recovers once', () async {
    await getSettingsFile().writeAsString(jsonEncode(<String, Object>{
      'Version': '26.0.3',
      'WindowSize': '506.4,506.4',
      'IsWindowMaximized': true,
    }));

    await AppSettings.readFromJson();

    expect(AppSettings.instance.windowSize, const Size(1280, 756));
    expect(AppSettings.instance.isWindowMaximized, isTrue);
  });

  test('current geometry schema preserves intentional small square', () async {
    await getSettingsFile().writeAsString(jsonEncode(<String, Object>{
      'Version': '26.0.3',
      WindowGeometryPolicy.schemaKey: WindowGeometryPolicy.currentSchemaVersion,
      'WindowSize': '507.0,507.0',
      'IsWindowMaximized': true,
    }));

    await AppSettings.readFromJson();

    expect(AppSettings.instance.windowSize, const Size(507, 507));
    expect(AppSettings.instance.isWindowMaximized, isTrue);
  });

  test('state-only save never samples a transition rectangle', () async {
    AppSettings.instance.windowSize = const Size(930, 680);
    window.bounds = const Rect.fromLTWH(100, 80, 507, 320);
    window.restoredBounds = window.bounds;
    window.calls.clear();

    await AppSettings.instance.saveSettings(captureWindowSize: false);

    final saved = await readSettings();
    expect(saved['WindowSize'], '930.0,680.0');
    expect(AppSettings.instance.windowSize, const Size(930, 680));
    expect(window.calls, isNot(contains('getBounds')));
  });

  test('mini saves retain normal size and do not query compact native size',
      () async {
    await WindowModeController.instance.enter();
    expect(window.bounds.size, const Size(520, 300));
    window.calls.clear();
    await AppSettings.instance.saveSettings();
    expect((await readSettings())['WindowSize'], '900.0,700.0');
    expect(AppSettings.instance.windowSize, const Size(900, 700));
    expect(window.calls, isEmpty);
  });

  for (final fullScreen in [false, true]) {
    for (final maximized in [false, true]) {
      test('mini persists original max=$maximized fullscreen=$fullScreen state',
          () async {
        window = FakeWindowModeAdapter(
          normalBounds: const Rect.fromLTWH(-900, 40, 930, 680),
          maximized: maximized,
          fullScreen: fullScreen,
        );
        messenger.setMockMethodCallHandler(
            windowChannel, window.handleMethodCall);
        await WindowModeController.instance.enter();
        await AppSettings.instance.saveSettings();
        final saved = await readSettings();
        expect(saved['WindowSize'], '930.0,680.0');
        expect(saved['IsWindowMaximized'], maximized);
        expect(AppSettings.instance.isWindowMaximized, maximized);
      });
    }
  }

  for (final originallyFullScreen in [false, true]) {
    test(
        'F11 from visible mini enters fullscreen with original '
        'fullscreen=$originallyFullScreen snapshot', () async {
      const normalBounds = Rect.fromLTWH(-900, 40, 930, 680);
      window = FakeWindowModeAdapter(
        normalBounds: normalBounds,
        fullScreen: originallyFullScreen,
      );
      messenger.setMockMethodCallHandler(
          windowChannel, window.handleMethodCall);
      final mode = WindowModeController.instance;
      await mode.enter();
      expect(mode.isMini, isTrue);
      expect(window.fullScreen, isFalse,
          reason: 'The currently visible mini window is not fullscreen');
      expect(mode.normalWindowSnapshot!.fullScreen, originallyFullScreen);
      expect(window.bounds.size, const Size(520, 300));
      window.calls.clear();

      await HotkeysHelper.runCommand(PlayerCommand.toggleFullScreen);

      expect(mode.isMini, isFalse);
      expect(mode.isBusy, isFalse);
      expect(mode.normalWindowSnapshot, isNull);
      expect(window.fullScreen, isTrue);
      expect(window.restoredBounds, normalBounds);
      expect(window.minimumSize, mode.normalMinimumSize);
      expect(window.alwaysOnTop, isFalse);
      expect(window.calls.where((method) => method == 'setFullScreen'),
          hasLength(1),
          reason: 'Do not toggle off a fullscreen snapshot restored by exit');

      // Once back in the normal layout, F11 resumes its ordinary toggle.
      await HotkeysHelper.runCommand(PlayerCommand.toggleFullScreen);
      expect(window.fullScreen, isFalse);
      expect(window.bounds, normalBounds);
      expect(mode.isMini, isFalse);
      expect(PlayService.isInitialized, isFalse);
    });
  }

  test('busy transition preserves existing file and avoids window queries',
      () async {
    await AppSettings.instance.saveSettings();
    final original = await getSettingsFile().readAsString();
    final gate = Completer<void>();
    pendingGates.add(gate);
    final started = Completer<void>();
    window.beforeCall = (method) async {
      if (method == 'setMinimumSize' && !started.isCompleted) {
        started.complete();
        await gate.future;
      }
    };
    final enter = WindowModeController.instance.enter();
    await started.future;
    final callsBeforeSave = List<String>.of(window.calls);
    await AppSettings.instance.saveSettings();
    expect(window.calls, callsBeforeSave);
    expect(await getSettingsFile().readAsString(), original);
    expect(AppSettings.instance.windowSize, const Size(900, 700));
    gate.complete();
    await enter;
  });

  test('busy no-op geometry save cannot cancel a pending appearance write',
      () async {
    final originalAppearance =
        AppSettings.instance.desktopLyricAppearance.value;
    final appearance =
        DesktopLyricAppearance.defaults.copyWith(textOpacity: .45);
    final pathGate = Completer<void>();
    final pathStarted = Completer<void>();
    final windowGate = Completer<void>();
    final windowStarted = Completer<void>();
    pendingGates.addAll([pathGate, windowGate]);
    messenger.setMockMethodCallHandler(pathChannel, (_) async {
      if (!pathStarted.isCompleted) pathStarted.complete();
      await pathGate.future;
      return testRoot.path;
    });
    AppSettings.instance.desktopLyricAppearance.value = appearance;
    final saving = AppSettings.instance
        .saveSettings(throwOnError: true, captureWindowSize: false);
    await pathStarted.future;
    window.beforeCall = (method) async {
      if (method == 'setMinimumSize' && !windowStarted.isCompleted) {
        windowStarted.complete();
        await windowGate.future;
      }
    };
    final enter = WindowModeController.instance.enter();
    await windowStarted.future;
    await AppSettings.instance.saveSettings();
    pathGate.complete();
    await saving;
    expect(
        (await readSettings())['DesktopLyricAppearance'], appearance.toJson());
    windowGate.complete();
    await enter;
    AppSettings.instance.desktopLyricAppearance.value = originalAppearance;
  });

  test('transition beginning during an async size read cancels stale saving',
      () async {
    await AppSettings.instance.saveSettings();
    final original = await getSettingsFile().readAsString();
    final gate = Completer<void>();
    pendingGates.add(gate);
    final started = Completer<void>();
    var pauseSizeRead = true;
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      if (call.method == 'getBounds' && pauseSizeRead) {
        pauseSizeRead = false;
        // Snapshot geometry at call entry, just like the native plugin. Delay
        // delivery only; never invent a future result from a later window.
        final snapshot = window.bounds;
        started.complete();
        await gate.future;
        return {
          'x': snapshot.left,
          'y': snapshot.top,
          'width': snapshot.width,
          'height': snapshot.height,
        };
      }
      return window.handleMethodCall(call);
    });
    final save = AppSettings.instance.saveSettings();
    await started.future;
    await WindowModeController.instance.enter();
    gate.complete();
    await save;
    expect(await getSettingsFile().readAsString(), original);
    expect(AppSettings.instance.windowSize, const Size(900, 700));
  });

  test(
      'maximized normal save never overwrites its restored size with work area',
      () async {
    AppSettings.instance.windowSize = const Size(930, 680);
    window = FakeWindowModeAdapter(maximized: true);
    messenger.setMockMethodCallHandler(windowChannel, window.handleMethodCall);
    await AppSettings.instance.saveSettings();
    final saved = await readSettings();
    expect(saved['WindowSize'], '930.0,680.0');
    expect(saved['IsWindowMaximized'], isTrue);
    expect(window.calls, isNot(contains('getBounds')));
  });
}
