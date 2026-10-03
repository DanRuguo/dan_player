import 'dart:async';

import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/appearance_palette_app.dart';
import 'package:desktop_lyric/appearance_palette_bridge.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/desktop_lyric_test_support.dart';
import 'support/palette_test_bridge.dart';
import 'support/playlist_feature_fixture.dart';

/// Real palette host/client with only the native window transport substituted.
/// The activation callback stays inside the fixture and never writes stdout.
class _Palette {
  _Palette() {
    source = DesktopLyricController.detached(
        sendMessage: messages.add, clock: PlaybackClock(automaticTicks: false));
    layout = DesktopLyricWindowLayout(adapter: window);
    host = DesktopLyricPaletteHost(
      controller: source,
      layout: layout,
      channel: owner,
      activateTaskbarLyrics: () {
        activations++;
        activatedAppearance = source.appearance.value;
      },
    );
    owner.request = (call) async {
      if (call.method == 'open' || call.method == 'update') {
        snapshot = Map<Object?, Object?>.from(call.arguments as Map);
        if (call.method == 'update') client?.applySnapshot(snapshot);
      } else if (call.method == 'close') {
        await closeNative();
      }
      return null;
    };
    child.request = (call) async {
      calls.add(call);
      if (call.method == 'ready') return snapshot;
      if (call.method == 'close') {
        await closeNative();
        return null;
      }
      if (call.method == 'edit') {
        final gate = editGate;
        editGate = null;
        if (gate != null) await gate.future;
        if (editError != null) throw editError!;
      }
      if (call.method == 'taskbarLyrics' && commandError != null) {
        throw commandError!;
      }
      return owner.receiver?.call(call);
    };
  }

  final window = FakeDesktopLyricWindow();
  final owner = PaletteLoopbackChannel('test/taskbar_palette_owner');
  final child = PaletteLoopbackChannel('test/taskbar_palette_child');
  final calls = <MethodCall>[];
  final messages = <String>[];
  late final DesktopLyricController source;
  late final DesktopLyricWindowLayout layout;
  late final DesktopLyricPaletteHost host;
  DesktopLyricPaletteClient? client;
  Map<Object?, Object?> snapshot = {};
  Future<void>? opening;
  Completer<void>? editGate;
  Object? editError;
  Object? commandError;
  int activations = 0;
  DesktopLyricAppearance? activatedAppearance;

  Future<void> initialize({
    UiLanguage language = UiLanguage.zh,
    bool dark = false,
    Color accent = const Color(0xff975423),
  }) async {
    uiLanguage.value = language;
    source.theme.value = ThemeChangedMessage(accent.toARGB32(),
        dark ? 0xff202322 : 0xfff8faf9, dark ? 0xffedf2ef : 0xff19211c);
    source.isDarkMode.value = dark;
    await layout.initialize(vertical: false);
    await open();
    client = DesktopLyricPaletteClient(channel: child);
    await client!.initialize(initialSnapshot: snapshot);
    calls.clear();
    window.operations.clear();
  }

  Future<void> open() async {
    opening = host.open();
    // Host.open has already issued its real startup snapshot synchronously.
    await Future<void>.value();
  }

  Future<void> closeNative() async {
    await owner.receiver?.call(MethodCall('closed', {
      'session': snapshot['session'],
      'ownerHover': false,
    }));
    await opening;
  }

  void dispose() {
    client?.dispose();
    host.dispose();
    layout.dispose();
    source.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MotionPreferences previousMotion;
  setUp(() {
    previousMotion = desktopMotionPreferences.value;
    desktopMotionPreferences.value = const MotionPreferences().all(false);
  });
  tearDown(() {
    desktopMotionPreferences.value = previousMotion;
    uiLanguage.value = UiLanguage.zh;
    Tooltip.dismissAllToolTips();
  });
  setUpAll(loadPlaylistFeatureFonts);

  test('taskbar command follows the successful final appearance edit ACK',
      () async {
    final fixture = _Palette();
    addTearDown(fixture.dispose);
    await fixture.initialize();
    fixture.client!.appearance.setBackgroundOpacity(.71);
    await fixture.client!.switchToTaskbarLyrics();
    expect(fixture.calls.map((call) => call.method), ['edit', 'taskbarLyrics']);
    expect(fixture.activatedAppearance!.backgroundOpacity, .71);
    expect(fixture.activations, 1);
    expect(fixture.client!.active, isTrue,
        reason:
            'The main coordinator owns mutually exclusive helper shutdown.');
    expect(fixture.window.operations, isEmpty);
  });

  test(
      'failed edit retains the appearance and does not issue a taskbar command',
      () async {
    final fixture = _Palette();
    addTearDown(fixture.dispose);
    await fixture.initialize();
    fixture.editError = PlatformException(code: 'fixture_edit_denied');
    fixture.client!.appearance.setBackgroundOpacity(.71);
    await fixture.client!.switchToTaskbarLyrics();
    expect(fixture.calls.map((call) => call.method), ['edit']);
    expect(fixture.activations, 0);
    expect(fixture.client!.appearance.value.backgroundOpacity, .71);
    expect(fixture.client!.saveError.value, isNotNull);
    expect(fixture.client!.switchingTaskbar, isFalse);
    fixture.editError = null;
    await fixture.client!.switchToTaskbarLyrics();
    expect(fixture.activations, 1);
    expect(fixture.activatedAppearance!.backgroundOpacity, .71);
  });

  test(
      'rapid commands share the busy gate and the host activates once per session',
      () async {
    final fixture = _Palette();
    addTearDown(fixture.dispose);
    await fixture.initialize();
    fixture.client!.appearance.setBackgroundOpacity(.61);
    final gate = fixture.editGate = Completer<void>();
    final first = fixture.client!.switchToTaskbarLyrics();
    final second = fixture.client!.switchToTaskbarLyrics();
    expect(fixture.client!.switchingTaskbar, isTrue);
    expect(fixture.calls.where((call) => call.method == 'edit'), hasLength(1));
    expect(fixture.activations, 0);
    gate.complete();
    await Future.wait([first, second]);
    expect(fixture.calls.where((call) => call.method == 'taskbarLyrics'),
        hasLength(1));
    await fixture.client!.switchToTaskbarLyrics();
    expect(fixture.activations, 1);
    expect(fixture.client!.switchingTaskbar, isFalse);
  });

  test('command transport failure stays visible and can be retried', () async {
    final fixture = _Palette();
    addTearDown(fixture.dispose);
    await fixture.initialize();
    fixture.commandError = PlatformException(code: 'fixture_command_denied');
    await fixture.client!.switchToTaskbarLyrics();
    expect(fixture.activations, 0);
    expect(fixture.client!.active, isTrue);
    expect(fixture.client!.switchingTaskbar, isFalse);
    expect(fixture.client!.layoutError.value, ui('任务栏歌词切换失败，请重试。'));
    fixture.commandError = null;
    await fixture.client!.switchToTaskbarLyrics();
    expect(fixture.activations, 1);
  });

  test(
      'a new presentation clears busy and an old edit cannot issue its command',
      () async {
    final fixture = _Palette();
    addTearDown(fixture.dispose);
    await fixture.initialize();
    fixture.client!.appearance.setBackgroundOpacity(.51);
    final gate = fixture.editGate = Completer<void>();
    final oldSession = fixture.snapshot['session'];
    final switching = fixture.client!.switchToTaskbarLyrics();
    expect(fixture.client!.switchingTaskbar, isTrue);
    fixture.client!.suspend();
    await fixture.closeNative();
    await fixture.open();
    expect(fixture.snapshot['session'], isNot(oldSession));
    expect(fixture.client!.applySnapshot(fixture.snapshot, beginSession: true),
        isTrue);
    expect(fixture.client!.switchingTaskbar, isFalse);
    gate.complete();
    await switching;
    expect(
        fixture.calls.where((call) => call.method == 'taskbarLyrics'), isEmpty);
    expect(fixture.activations, 0);
    await fixture.client!.switchToTaskbarLyrics();
    expect(fixture.activations, 1);
  });

  test('the owner ignores obsolete and already-closed session commands',
      () async {
    final fixture = _Palette();
    addTearDown(fixture.dispose);
    await fixture.initialize();
    final session = fixture.snapshot['session'] as int;
    await fixture.owner.receiver!
        .call(MethodCall('taskbarLyrics', {'session': session - 1}));
    expect(fixture.activations, 0);
    await fixture.closeNative();
    await fixture.owner.receiver!
        .call(MethodCall('taskbarLyrics', {'session': session}));
    expect(fixture.activations, 0);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'taskbar palette real entry ${language.code} '
          '${narrow ? 'narrow-large' : 'wide'}', (tester) async {
        final width = narrow ? 360.0 : 1080.0;
        sizePlaylistFeature(tester, width: width, height: 900);
        tester.platformDispatcher.textScaleFactorTestValue = narrow ? 2 : 1;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final fixture = _Palette();
        addTearDown(fixture.dispose);
        await fixture.initialize(
            language: language,
            dark: narrow,
            accent: narrow ? const Color(0xffe8b484) : const Color(0xff23784f));
        final boundary = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: DesktopLyricAppearanceApp(client: fixture.client!)));
        await tester.pumpAndSettle();
        final button =
            find.byKey(const ValueKey('desktop-switch-taskbar-lyrics'));
        expect(button, findsOneWidget);
        expect(find.descendant(of: button, matching: find.text(ui('切换到任务栏歌词'))),
            findsOneWidget);
        final rect = tester.getRect(button);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        expect(rect.bottom, lessThanOrEqualTo(900));
        final theme = Theme.of(tester.element(button));
        expect(theme.colorScheme.primary,
            narrow ? const Color(0xffe8b484) : const Color(0xff23784f));
        final style = tester.widget<FilledButton>(button).style!;
        expect(style.foregroundColor!.resolve({}), theme.colorScheme.primary);
        expect(style.backgroundColor!.resolve({}),
            theme.colorScheme.primary.withValues(alpha: .12));
        expect(tester.takeException(), isNull);
        await capturePlaylistFeature(tester, boundary,
            'taskbar-palette-${language.code}-${narrow ? 'narrow-large' : 'wide'}');
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(fixture.activations, 1);
        expect(fixture.calls.where((call) => call.method == 'taskbarLyrics'),
            hasLength(1));
        expect(fixture.window.operations, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
