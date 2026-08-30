import 'dart:convert';
import 'dart:async';

import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/taskbar_lyric_row.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_binding.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/desktop_lyric_test_support.dart';

class _AsyncAreaWindow extends FakeDesktopLyricWindow {
  Completer<void>? areaGate;
  @override
  Future<Rect> workAreaFor(Rect bounds) async {
    final snapshot = area;
    final gate = areaGate;
    areaGate = null;
    if (gate != null) await gate.future;
    return snapshot;
  }
}

void main() {
  test('an in-flight work-area lookup drains the final display event',
      () async {
    final native = _AsyncAreaWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(
        vertical: false,
        appearance:
            DesktopLyricAppearance.defaults.copyWith(taskbarMode: true));
    final gate = Completer<void>();
    native.areaGate = gate;
    final first = layout.fitToWorkArea();
    await Future<void>.delayed(Duration.zero);
    native.area = const Rect.fromLTWH(-900, 0, 900, 500);
    final trailing = layout.fitToWorkArea();
    gate.complete();
    await Future.wait([first, trailing]);
    expect(native.bounds, const Rect.fromLTWH(-900, 436, 900, 56));
  });

  test('DPI changes during native lookup re-read before changing bounds',
      () async {
    final native = _AsyncAreaWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(
        vertical: false,
        appearance:
            DesktopLyricAppearance.defaults.copyWith(taskbarMode: true));
    final gate = Completer<void>();
    native.areaGate = gate;
    final fitting = layout.fitToWorkArea();
    await Future<void>.delayed(Duration.zero);
    native.pixelRatio = 2;
    native.area = const Rect.fromLTWH(0, 0, 960, 520);
    gate.complete();
    await fitting;
    expect(native.bounds, const Rect.fromLTWH(0, 456, 960, 56));
  });

  test('disposing layout invalidates late native reads and queued writes',
      () async {
    final native = _AsyncAreaWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(vertical: false);
    final gate = Completer<void>();
    native.areaGate = gate;
    native.operations.clear();
    final fitting = layout.setAppearance(
        DesktopLyricAppearance.defaults.copyWith(taskbarMode: true));
    await Future<void>.delayed(Duration.zero);
    layout.dispose();
    gate.complete();
    await fitting;
    await layout.setVertical(true);
    expect(native.operations, isEmpty);
  });

  test(
      'all auto-hide edges reserve space for buttons without double subtracting',
      () {
    const monitor = Rect.fromLTWH(-1200, 0, 1200, 800);
    const expected = Rect.fromLTRB(-1152, 40, -48, 744);
    expect(
        DesktopLyricGeometry.reserveAutoHideEdges(
            monitor, monitor, [48, 40, 48, 56]),
        expected);
    expect(
        DesktopLyricGeometry.reserveAutoHideEdges(
            expected, monitor, [48, 40, 48, 56]),
        expected);
  });
  test(
      'auto-hide bottom reservation avoids double subtraction and malformed shell sizes',
      () {
    const monitor = Rect.fromLTWH(-1920, 0, 1920, 1080);
    const visibleWork = Rect.fromLTWH(-1920, 0, 1920, 1032);
    expect(DesktopLyricGeometry.reserveAutoHideBottom(monitor, monitor, 48),
        visibleWork);
    expect(DesktopLyricGeometry.reserveAutoHideBottom(visibleWork, monitor, 48),
        visibleWork);
    for (final height in [double.nan, -1.0, 0.0, 1080.0]) {
      expect(
          DesktopLyricGeometry.reserveAutoHideBottom(monitor, monitor, height),
          monitor);
    }
  });
  test(
      'minimum font wins over preference and a short viewport avoids vertical clipping',
      () {
    double fit(double height) => taskbarLyricFontSize('Hello',
        style: const TextStyle(height: 1.25),
        scaler: const TextScaler.linear(2),
        direction: TextDirection.ltr,
        width: 900,
        height: height,
        preferred: 18,
        minimum: 24);
    expect(fit(100), 24);
    final font = fit(44);
    final painter = TextPainter(
        text: TextSpan(
            text: 'Hello', style: TextStyle(fontSize: font, height: 1.25)),
        textScaler: const TextScaler.linear(2),
        textDirection: TextDirection.ltr)
      ..layout();
    expect(painter.height, lessThanOrEqualTo(44.1));
    painter.dispose();
  });

  testWidgets(
      'native failure rolls back mode and error survives a successful save ACK',
      (tester) async {
    final native = FakeDesktopLyricWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    final source = DesktopLyricController.detached(
        sendMessage: (_) {}, clock: PlaybackClock(automaticTicks: false));
    await layout.initialize(vertical: false);
    final original = native.bounds;
    final binding = DesktopLyricWindowBinding(source, layout)..attach();
    await tester.pump();
    native.failNextBounds = StateError('fixture denied');
    source.appearance.setTaskbarMode(true);
    await tester.pump();
    await tester.pump();
    expect(source.appearance.value.taskbarMode, false);
    expect(native.bounds, original);
    expect(layout.lastError.value, isNotNull);
    source.appearanceSaveError.value = null;
    expect(layout.lastError.value, isNotNull);
    source.appearance.setTaskbarMode(true);
    await tester.pump();
    await tester.pump();
    expect(layout.lastError.value, isNull);
    expect(layout.taskbarMode, true);
    binding.dispose();
    source.dispose();
  });

  test('large text raises dock height and palette restoration retains it',
      () async {
    final native = FakeDesktopLyricWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(
        vertical: false,
        appearance: DesktopLyricAppearance.defaults
            .copyWith(taskbarMode: true, taskbarHeight: 48));
    await layout.ensureTaskbarMinimumHeight(66.4);
    expect(native.bounds.height, closeTo(66.4, .01));
    await layout.setPaletteOpen(true);
    await layout.setPaletteOpen(false);
    expect(native.bounds.height, closeTo(66.4, .01));
  });
  test('taskbar preferences validate and survive the existing framed protocol',
      () {
    final prefs = DesktopLyricAppearance.defaults.copyWith(
        taskbarMode: true,
        taskbarGap: 48,
        taskbarHeight: 96,
        taskbarMinimumFontSize: 24,
        taskbarTranslation: true);
    final message = jsonDecode(
        DesktopLyricAppearanceChangedMessage(prefs, revision: 20)
            .buildMessageJson());
    expect(
        DesktopLyricAppearanceChangedMessage.fromJson(message['message'])
            .appearance,
        prefs);
    for (final entry in {
      'taskbarMode': 1,
      'taskbarGap': double.nan,
      'taskbarHeight': 10,
      'taskbarMinimumFontSize': 0,
      'taskbarTranslation': 'true'
    }.entries) {
      expect(
          DesktopLyricAppearance.tryFromJson(
              {...prefs.toJson(), entry.key: entry.value}),
          isNull);
    }
    final legacy = {...DesktopLyricAppearance.defaults.toJson()}
      ..removeWhere((key, _) => key.startsWith('taskbar'));
    expect(DesktopLyricAppearance.tryFromJson(legacy),
        DesktopLyricAppearance.defaults);
  });

  test(
      'docking fills current work area width and restores independent floating modes',
      () async {
    final native = FakeDesktopLyricWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(vertical: false);
    final original = native.bounds;
    await layout.setAppearance(
        DesktopLyricAppearance.defaults.copyWith(taskbarMode: true));
    expect(native.bounds, const Rect.fromLTWH(0, 976, 1920, 56));
    await layout.ensureContentMinimum(const Size(900, 800), vertical: false);
    expect(native.bounds.height, 56);
    await layout.setPaletteOpen(true);
    expect(native.bounds.size, const Size(1920, 440));
    await layout.setPaletteOpen(false);
    expect(native.bounds, const Rect.fromLTWH(0, 976, 1920, 56));
    await layout.setAppearance(DesktopLyricAppearance.defaults);
    expect(native.bounds.left, original.left);
    expect(
        native.bounds.width, 900); // latest floating content minimum retained
    expect(native.bounds.height, 800);
  });

  test(
      'changing modes inside palette never stores the expanded palette as lyric bounds',
      () async {
    final native = FakeDesktopLyricWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(vertical: false);
    final original = native.bounds;
    await layout.setPaletteOpen(true);
    await layout.setAppearance(
        DesktopLyricAppearance.defaults.copyWith(taskbarMode: true));
    await layout.setPaletteOpen(false);
    await layout.setPaletteOpen(true);
    await layout.setAppearance(DesktopLyricAppearance.defaults);
    await layout.setPaletteOpen(false);
    expect(native.bounds, original);
  });

  test(
      'negative monitor, changed DPI, removal, narrow area and settings changes stay inside',
      () async {
    final native = FakeDesktopLyricWindow()
      ..area = const Rect.fromLTWH(-1280, -200, 1280, 700);
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(
        vertical: true,
        appearance:
            DesktopLyricAppearance.defaults.copyWith(taskbarMode: true));
    expect(native.bounds, const Rect.fromLTWH(-1280, 436, 1280, 56));
    native.pixelRatio = 2;
    native.area = const Rect.fromLTWH(10, 20, 260, 40);
    await layout.fitToWorkArea();
    expect(native.bounds, native.area);
    expect(native.minimum.width, 260);
    native.area = const Rect.fromLTWH(0, 0, 1000, 800);
    await layout.setAppearance(DesktopLyricAppearance.defaults
        .copyWith(taskbarMode: true, taskbarGap: 16, taskbarHeight: 72));
    expect(native.bounds, const Rect.fromLTWH(0, 712, 1000, 72));
    native.operations.clear();
    await layout.fitToWorkArea();
    await layout.setAppearance(DesktopLyricAppearance.defaults.copyWith(
        taskbarMode: true, taskbarGap: 16, taskbarHeight: 72, textOpacity: .5));
    expect(native.operations, isEmpty);
  });

  test('failed native dock rolls back and can retry', () async {
    final native = FakeDesktopLyricWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    await layout.initialize(vertical: false);
    final original = native.bounds;
    final prefs = DesktopLyricAppearance.defaults.copyWith(taskbarMode: true);
    native.failNextBounds = StateError('fixture native failure');
    await expectLater(layout.setAppearance(prefs), throwsStateError);
    expect(native.bounds, original);
    expect(layout.taskbarMode, false);
    await layout.setAppearance(prefs);
    expect(layout.taskbarMode, true);
  });

  testWidgets('metrics coalesce and binding detaches without polling',
      (tester) async {
    final native = FakeDesktopLyricWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    final controller = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false));
    await layout.initialize(vertical: false);
    final binding = DesktopLyricWindowBinding(controller, layout)..attach();
    controller.appearance.setTaskbarMode(true);
    await tester.pump();
    native.area = const Rect.fromLTWH(0, 0, 800, 500);
    binding.didChangeMetrics();
    binding.didChangeMetrics();
    await tester.pump();
    await tester.pump();
    expect(native.bounds, const Rect.fromLTWH(0, 436, 800, 56));
    binding.dispose();
    native.operations.clear();
    controller.appearance.setTaskbarHeight(96);
    await tester.pump();
    expect(native.operations, isEmpty);
    controller.dispose();
  });

  for (final width in [180.0, 320.0, 520.0, 1920.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'single line + all buttons within ${width}px at ${scale}x text',
          (tester) async {
        tester.view.physicalSize = Size(width, 56);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final source = DesktopLyricController.detached(
            clock: PlaybackClock(automaticTicks: false));
        addTearDown(source.dispose);
        source.appearance.value =
            DesktopLyricAppearance.defaults.copyWith(taskbarMode: true);
        source.lyricLine.value = LyricLineChangedMessage(
            'Very long 日本語 中文 👨‍👩‍👧‍👦 line ' * 40, Duration.zero, '译文');
        final sent = <String>[];
        await tester.pumpWidget(ValueListenableProvider.value(
            value: source.theme,
            child: MaterialApp(
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: Scaffold(
                    body: TaskbarLyricRow(
                        controller: source,
                        windowLayout: DesktopLyricWindowLayout(
                            adapter: FakeDesktopLyricWindow()),
                        sendMessage: sent.add)))));
        expect(tester.takeException(), isNull);
        final area = Rect.fromLTWH(0, 0, width, 56);
        for (final element in find.byType(IconButton).evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          expect(rect.left, greaterThanOrEqualTo(area.left - .01));
          expect(rect.right, lessThanOrEqualTo(area.right + .01));
          expect(rect.bottom, lessThanOrEqualTo(area.bottom + .01));
        }
        final text =
            tester.widget<DesktopLyricText>(find.byType(DesktopLyricText));
        expect(text.maxHorizontalWidth, isNotNull);
        expect(text.style.fontSize, lessThanOrEqualTo(22));
        await tester.tap(find.byTooltip('播放'));
        expect(jsonDecode(sent.single)['message']['event'], isNotNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets(
      'single line switches theme and translation without replacing clock',
      (tester) async {
    final source = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false));
    addTearDown(source.dispose);
    source.lyricLine.value =
        const LyricLineChangedMessage('Original', Duration.zero, '译文');
    await tester.pumpWidget(ValueListenableProvider.value(
        value: source.theme,
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    height: 56,
                    child: TaskbarLyricRow(
                        controller: source,
                        windowLayout: DesktopLyricWindowLayout(
                            adapter: FakeDesktopLyricWindow())))))));
    source.theme.value =
        const ThemeChangedMessage(0xffbb6611, 0xff111111, 0xffeeeeee);
    source.appearance.setTaskbarTranslation(true);
    await tester.pump();
    final text = tester.widget<DesktopLyricText>(find.byType(DesktopLyricText));
    expect(text.text, '译文');
    expect(text.playedColor, const Color(0xffbb6611));
    expect(text.clock, same(source.playbackClock));
    for (final icon in tester.widgetList<IconButton>(find.byType(IconButton))) {
      expect(icon.color, const Color(0xffbb6611));
    }
    source.lyricLine.value =
        const LyricLineChangedMessage('Fallback', Duration.zero);
    await tester.pump();
    expect(tester.widget<DesktopLyricText>(find.byType(DesktopLyricText)).text,
        'Fallback');
    await tester.pumpWidget(const SizedBox());
  });
}
