import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/online/online_source_preferences.dart';
import 'package:dan_player/page/settings_page/background_settings.dart';
import 'package:dan_player/page/settings_page/music_source_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/fake_window_mode_adapter.dart';

const _sourceError = '保存歌源设置失败；当前选择仍对本次会话生效。';
const _backgroundError = '保存背景设置失败；当前选择仍对本次会话生效。';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows, useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(padding: const EdgeInsets.all(16), children: [child]),
      ),
    );

/// The production default persist callback owns real async File I/O. Let its
/// I/O zone progress, then pump the queued UI update until the observable error
/// appears. A fixed pumpAndSettle cannot wait for an outstanding OS File call.
Future<void> _waitForError(WidgetTester tester, String message) async {
  for (var attempt = 0;
      attempt < 100 && find.text(message).evaluate().isEmpty;
      attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(find.text(message), findsOneWidget);
}

Future<Map<String, dynamic>> _waitForSavedSettings(
    WidgetTester tester, File target) async {
  Map<String, dynamic>? saved;
  for (var attempt = 0; attempt < 100 && saved == null; attempt++) {
    saved = await tester.runAsync<Map<String, dynamic>?>(() async {
      if (await target.exists()) {
        try {
          return jsonDecode(await target.readAsString())
              as Map<String, dynamic>;
        } on FormatException {
          // The save may have created its file but not written the JSON yet.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return null;
    });
    await tester.pump();
  }
  expect(saved, isNotNull, reason: 'The default save must finish after retry.');
  return saved!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory parent;
  late Directory root;
  late Directory occupiedTarget;
  late File target;
  late OnlineSourcePreferences previousSources;
  late BackgroundPreferences previousBackgrounds;
  late Size previousWindowSize;
  late bool previousMaximized;
  var windowCalls = 0;

  setUp(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    parent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    root = await parent.createTemp('settings-write-failure-');
    messenger.setMockMethodCallHandler(pathChannel, (_) async => root.path);
    final window = FakeWindowModeAdapter();
    windowCalls = 0;
    messenger.setMockMethodCallHandler(windowChannel, (call) {
      windowCalls++;
      return window.handleMethodCall(call);
    });
    final data = await getAppDataDir();
    expect(path.isWithin(root.path, data.path), isTrue);
    target = File(path.join(data.path, 'settings.json'));
    // An empty temporary directory at the FILE target reliably rejects both
    // File.create and writing without platform-specific ACL changes.
    occupiedTarget = await Directory(target.path).create();
    final settings = AppSettings.instance;
    previousSources = settings.onlineSources.value;
    previousBackgrounds = settings.backgrounds.value;
    previousWindowSize = settings.windowSize;
    previousMaximized = settings.isWindowMaximized;
    settings.onlineSources.value = const OnlineSourcePreferences();
    settings.backgrounds.value = const BackgroundPreferences();
  });

  tearDown(() async {
    final settings = AppSettings.instance;
    settings.onlineSources.value = previousSources;
    settings.backgrounds.value = previousBackgrounds;
    settings.windowSize = previousWindowSize;
    settings.isWindowMaximized = previousMaximized;
    messenger.setMockMethodCallHandler(windowChannel, null);
    messenger.setMockMethodCallHandler(pathChannel, null);
    final resolvedParent = await parent.resolveSymbolicLinks();
    final resolvedRoot = await root.resolveSymbolicLinks();
    if (!path.isWithin(resolvedParent, resolvedRoot) ||
        !path.basename(resolvedRoot).startsWith('settings-write-failure-')) {
      throw StateError('Refusing to remove an unverified settings fixture');
    }
    await Directory(resolvedRoot).delete(recursive: true);
    expect(PlayService.isInitialized, isFalse);
  });

  test('legacy save stays non-throwing when the real file target is unwritable',
      () async {
    await AppSettings.instance.saveSettings();
    expect(await occupiedTarget.exists(), isTrue);
    expect(await target.exists(), isFalse);
    expect(windowCalls, greaterThan(0));
  });

  test('strict save propagates the real FileSystemException', () async {
    await expectLater(AppSettings.instance.saveSettings(throwOnError: true),
        throwsA(isA<FileSystemException>()));
    expect(await occupiedTarget.exists(), isTrue);
    expect(await target.exists(), isFalse);
  });

  testWidgets(
      'source default persist reports a real failure and retains choice',
      (tester) async {
    // Neither preferences nor persist is replaced: this exercises the real
    // MusicSourceSettings -> AppSettings strict save -> File chain.
    await tester.pumpWidget(_host(const MusicSourceSettings()));
    await tester.pumpAndSettle();
    expect(windowCalls, 0, reason: 'Opening settings must not save or probe.');
    await tester.tap(find.byKey(const ValueKey('online-source-qq')));
    await _waitForError(tester, _sourceError);
    expect(AppSettings.instance.onlineSources.value.qqEnabled, isFalse);
    expect(AppSettings.instance.onlineSources.value.neteaseEnabled, isTrue);
    expect(await tester.runAsync(occupiedTarget.exists), isTrue);
    expect(await tester.runAsync(target.exists), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'background default onSave reports a real failure and retains choice',
      (tester) async {
    final status =
        ValueNotifier(const WindowBackdropStatus(reason: 'disabled'));
    addTearDown(status.dispose);
    // Status is render-only; preferences and onSave still use production paths.
    await tester.pumpWidget(_host(BackgroundSettingsPanel(status: status)));
    await tester.pumpAndSettle();
    expect(windowCalls, 0);
    await tester.tap(find.byKey(const ValueKey('background-source-artwork')));
    await _waitForError(tester, _backgroundError);
    expect(AppSettings.instance.backgrounds.value.main.source,
        BackgroundSource.artwork);
    expect(await tester.runAsync(occupiedTarget.exists), isTrue);
    expect(await tester.runAsync(target.exists), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source default persist can retry successfully after the failure',
      (tester) async {
    await tester.pumpWidget(_host(const MusicSourceSettings()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('online-source-qq')));
    await _waitForError(tester, _sourceError);
    // Remove only the verified, empty fixture directory occupying settings.json.
    // No recursive removal and no real application settings are involved.
    expect(path.isWithin(root.path, occupiedTarget.path), isTrue);
    await tester.runAsync(() async => occupiedTarget.delete());
    final netease = find.byKey(const ValueKey('online-source-netease'));
    await tester.ensureVisible(netease);
    await tester.tap(netease);
    final saved = await _waitForSavedSettings(tester, target);
    expect(saved['OnlineSources'], isEmpty);
    expect(saved['Backgrounds'], const BackgroundPreferences().toMap());
    expect(AppSettings.instance.onlineSources.value.isEmpty, isTrue);
    expect(find.text(_sourceError), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
