import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:desktop_lyric/appearance_palette_bridge.dart';
import 'package:desktop_lyric/app_presentation.dart';
import 'package:desktop_lyric/component/action_row.dart';
import 'package:desktop_lyric/component/desktop_lyric_body.dart';
import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/desktop_lyric_test_support.dart';
import 'support/palette_test_bridge.dart';

class _MetricsWindow extends FakeDesktopLyricWindow {
  _MetricsWindow(this.tester);
  final WidgetTester tester;
  @override
  Future<void> setBounds(Rect value) async {
    await super.setBounds(value);
    tester.view.physicalSize = value.size * tester.view.devicePixelRatio;
  }
}

class _Fixture {
  _Fixture(this.tester) {
    native = _MetricsWindow(tester);
    source = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false), sendMessage: messages.add);
    layout = DesktopLyricWindowLayout(adapter: native);
    bridge = PaletteTestBridge(source: source, layout: layout);
  }
  final WidgetTester tester;
  final messages = <String>[];
  late final _MetricsWindow native;
  late final DesktopLyricController source;
  late final DesktopLyricWindowLayout layout;
  late final PaletteTestBridge bridge;
  final triggerVisible = ValueNotifier(true);
  late Rect original;

  Future<void> mount(
      {bool vertical = false,
      bool taskbar = false,
      double scale = 1,
      bool body = true}) async {
    tester.view.devicePixelRatio = 1;
    native.bounds =
        Rect.fromLTWH(100, 100, vertical ? 248 : 800, vertical ? 560 : 160);
    source.vertical.value = vertical;
    source.appearance.value = source.appearance.value
        .copyWith(taskbarMode: taskbar, taskbarHeight: 48);
    await layout.initialize(
        vertical: vertical, appearance: source.appearance.value);
    tester.view.physicalSize = native.bounds.size;
    await tester.pumpWidget(DesktopLyricPaletteScope(
      host: bridge.host,
      child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: AppPresentationHost(child: child!)),
          home: body
              ? ValueListenableProvider<ThemeChangedMessage>.value(
                  value: source.theme,
                  child: DesktopLyricBody(
                      controller: source,
                      windowLayout: layout,
                      sendMessage: messages.add))
              : Scaffold(
                  body: Center(
                      child: ValueListenableBuilder(
                          valueListenable: triggerVisible,
                          builder: (_, visible, __) => visible
                              ? DesktopLyricAppearanceButton(
                                  controller: source, windowLayout: layout)
                              : const Text('replacement foreground'))))),
    ));
    await tester.pumpAndSettle();
    original = native.bounds;
    native.operations.clear();
  }

  Future<void> open() async {
    await tester.tap(find.byKey(const ValueKey('desktop-appearance-open')));
    if (bridge.openGate == null) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      expect(find.byKey(const ValueKey('desktop-appearance-starting')),
          findsOneWidget);
    }
    expect(bridge.host.isOpen.value, isTrue);
    expect(bridge.opens, greaterThan(0));
    expect(
        find.byKey(const ValueKey('desktop-appearance-dialog')), findsNothing,
        reason: 'The palette must not be inserted into the lyric engine.');
  }

  Future<void> close() async {
    await bridge.closeNative();
    await tester.pumpAndSettle();
    expect(bridge.host.isOpen.value, isFalse);
  }

  Future<void> dispose() async {
    bridge.dispose();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    source.dispose();
    layout.dispose();
    triggerVisible.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    ALWAYS_SHOW_ACTION_ROW = false;
  }
}

void main() {
  for (final mode in [(false, false), (true, false), (false, true)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('independent palette never resizes owner $mode / $scale',
          (tester) async {
        final fixture = _Fixture(tester);
        await fixture.mount(vertical: mode.$1, taskbar: mode.$2, scale: scale);
        expect(tester.takeException(), isNull, reason: 'initial lyric frame');
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(10, 10));
        await tester.pumpAndSettle();
        fixture.original = fixture.native.bounds;
        fixture.native.operations.clear();
        final surface = find.byKey(const ValueKey('desktop-lyric-surface'));
        final original = tester.getRect(surface);
        await fixture.open();
        await mouse.moveTo(const Offset(-10, -10));
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 60));
          expect(tester.getRect(surface), original);
          expect(fixture.native.operations, isEmpty);
        }
        await fixture.close();
        // Re-entry can arrive after the owned HWND has already closed.
        await tester.pump(const Duration(milliseconds: 16));
        await mouse.moveTo(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(tester.getRect(surface), original);
        expect(fixture.native.bounds, fixture.original);
        expect(fixture.native.operations, isEmpty,
            reason: 'Open/close may not mutate bounds OR minimum size.');
        expect(fixture.layout.palettePresentation.value, isNull);
        expect(tester.takeException(), isNull);
        await mouse.removePointer();
        await fixture.dispose();
      });
    }
  }

  testWidgets('button disposal does not destroy the independent session',
      (tester) async {
    final fixture = _Fixture(tester);
    await fixture.mount(body: false);
    await fixture.open();
    fixture.triggerVisible.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(DesktopLyricAppearanceButton), findsNothing);
    expect(fixture.bridge.host.isOpen.value, isTrue);
    await fixture.close();
    expect(fixture.native.operations, isEmpty);
    expect(tester.takeException(), isNull);
    await fixture.dispose();
  });

  testWidgets('cold opening retains a live loading animation until first frame',
      (tester) async {
    final fixture = _Fixture(tester);
    await fixture.mount(body: false);
    final gate = fixture.bridge.openGate = Completer<void>();
    await fixture.open();
    await tester.pump(const Duration(milliseconds: 40));
    final loading = find.byType(CircularProgressIndicator);
    expect(loading, findsOneWidget);
    final paint =
        find.descendant(of: loading, matching: find.byType(CustomPaint));
    final before = tester.widget<CustomPaint>(paint.first).painter!;
    await tester.pump(const Duration(milliseconds: 120));
    final after = tester.widget<CustomPaint>(paint.first).painter!;
    expect(after.shouldRepaint(before), isTrue);
    expect(fixture.bridge.host.isStarting.value, isTrue);
    expect(fixture.native.operations, isEmpty);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await fixture.close();
    await fixture.dispose();
  });

  testWidgets('repeated opening reuses one child and fresh snapshots on reopen',
      (tester) async {
    final fixture = _Fixture(tester);
    await fixture.mount(body: false);
    await fixture.open();
    unawaited(fixture.bridge.host.open());
    await tester.pumpAndSettle();
    expect(fixture.bridge.opens, 1);
    await fixture.close();
    fixture.source.appearance.setTextOpacity(.62);
    await fixture.open();
    expect(fixture.bridge.opens, 2);
    expect((fixture.bridge.snapshot['appearance'] as Map)['textOpacity'], .62);
    await fixture.close();
    expect(fixture.native.operations, isEmpty);
    await fixture.dispose();
  });

  testWidgets(
      'failed child startup stays explicit and retries without parent resize',
      (tester) async {
    final fixture = _Fixture(tester);
    await fixture.mount(body: false);
    fixture.bridge.openError = StateError('synthetic child startup failure');
    await tester.tap(find.byKey(const ValueKey('desktop-appearance-open')));
    await tester.pumpAndSettle();
    expect(fixture.bridge.host.isOpen.value, isFalse);
    expect(fixture.native.operations, isEmpty);
    final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('desktop-appearance-open')));
    expect(button.onPressed, isNotNull);
    expect(find.textContaining('无法打开歌词外观窗口：'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-notice-bubble')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    fixture.bridge.openError = null;
    await fixture.open();
    await fixture.close();
    expect(tester.takeException(), isNull);
    await fixture.dispose();
  });

  testWidgets('startup error remains visible after its trigger is disposed',
      (tester) async {
    final fixture = _Fixture(tester);
    await fixture.mount(body: false);
    final gate = fixture.bridge.openGate = Completer<void>();
    await fixture.open();
    fixture.triggerVisible.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(DesktopLyricAppearanceButton), findsNothing);
    gate.completeError(StateError('synthetic late child startup failure'));
    await tester.pumpAndSettle();
    expect(find.textContaining('无法打开歌词外观窗口：'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-notice-bubble')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
    await fixture.dispose();
  });

  testWidgets(
      'owner shutdown during pending child startup cannot revive the frame',
      (tester) async {
    final fixture = _Fixture(tester);
    await fixture.mount(body: false);
    final gate = fixture.bridge.openGate = Completer<void>();
    await fixture.open();
    fixture.bridge.host.dispose();
    gate.complete();
    await tester.pumpAndSettle();
    expect(fixture.native.operations, isEmpty);
    expect(fixture.layout.palettePresentation.value, isNull);
    expect(tester.takeException(), isNull);
    await fixture.dispose();
  });
}
