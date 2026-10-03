import 'dart:async';

import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/component/action_row.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/desktop_lyric_test_support.dart';
import 'support/palette_test_bridge.dart';

class _Fixture {
  _Fixture(this.tester) {
    source = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false));
    layout = DesktopLyricWindowLayout(adapter: FakeDesktopLyricWindow());
    bridge = PaletteTestBridge(source: source, layout: layout);
    bridge.openGate = Completer<void>();
  }
  final WidgetTester tester;
  late final DesktopLyricController source;
  late final DesktopLyricWindowLayout layout;
  late final PaletteTestBridge bridge;
  final feedback = ValueNotifier(true), ticker = ValueNotifier(true);
  bool _disposed = false;
  Future<void> mount({bool mediaReduced = false}) async {
    await tester.pumpWidget(MaterialApp(
        // Keep the existing tap ink out of the indicator's idle-clock probe.
        theme: AppMotion.controlTheme(ThemeData(), false),
        home: Scaffold(
            body: ValueListenableBuilder(
                valueListenable: feedback,
                builder: (context, enabled, _) => MotionPreferencesScope(
                    preferences: const MotionPreferences()
                        .withKind(MotionKind.feedback, enabled),
                    child: ValueListenableBuilder(
                        valueListenable: ticker,
                        builder: (context, active, _) => MediaQuery(
                            data: MediaQuery.of(context)
                                .copyWith(disableAnimations: mediaReduced),
                            child: TickerMode(
                                enabled: active,
                                child: Center(
                                    child: DesktopLyricAppearanceButton(
                                        controller: source,
                                        windowLayout: layout,
                                        paletteHost: bridge.host))))))))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('desktop-appearance-open')));
    await tester.pump();
  }

  void expectStatic() {
    final spinner = tester.widget<CircularProgressIndicator>(
        find.byKey(const ValueKey('desktop-appearance-starting')));
    expect(spinner.value, 0,
        reason: 'Unknown startup progress uses a static empty track');
    expect(find.byKey(const ValueKey('desktop-appearance-progress-semantics')),
        findsOneWidget);
    expect(
        tester
            .widget<IconButton>(
                find.byKey(const ValueKey('desktop-appearance-open')))
            .onPressed,
        isNull);
    expect(bridge.host.isStarting.value, isTrue);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (!bridge.openGate!.isCompleted) bridge.openGate!.complete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    bridge.dispose();
    layout.dispose();
    source.dispose();
    feedback.dispose();
    ticker.dispose();
  }
}

void main() {
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  for (final mode in ['feedback', 'media', 'hidden']) {
    testWidgets(
        'pending palette $mode stops feedback without fabricated progress',
        (tester) async {
      final fixture = _Fixture(tester);
      addTearDown(fixture.dispose);
      final semantics = tester.ensureSemantics();
      try {
        if (mode == 'feedback') fixture.feedback.value = false;
        await fixture.mount(mediaReduced: mode == 'media');
        if (mode == 'hidden') {
          addTearDown(() => tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
          await tester.pump();
          fixture.expectStatic();
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.binding.transientCallbackCount, 0);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await tester.pump();
          expect(
              tester
                  .widget<CircularProgressIndicator>(
                      find.byKey(const ValueKey('desktop-appearance-starting')))
                  .value,
              isNull);
          fixture.ticker.value = false;
          await tester.pump();
        }
        fixture.expectStatic();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.binding.transientCallbackCount, 0);
        final busy = tester
            .getSemantics(find.byKey(const ValueKey('desktop-appearance-busy')))
            .getSemanticsData();
        expect(busy.label, contains(ui('正在打开歌词外观…')));
        expect(busy.value, isNot(contains('%')));
        if (mode == 'media') {
          for (final language
              in UiLanguage.values.where((v) => v != UiLanguage.zh)) {
            expect(translateUi('正在打开歌词外观…', language), isNot('正在打开歌词外观…'));
          }
        }
        await fixture.dispose();
      } finally {
        semantics.dispose();
      }
    });
  }
  testWidgets(
      'native reduce motion interrupts a pending palette then resumes on request',
      (tester) async {
    final fixture = _Fixture(tester);
    addTearDown(fixture.dispose);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await fixture.mount();
    expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byKey(const ValueKey('desktop-appearance-starting')))
            .value,
        isNull);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();
    fixture.expectStatic();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.binding.transientCallbackCount, 0);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    await tester.pump();
    expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byKey(const ValueKey('desktop-appearance-starting')))
            .value,
        isNull);
    await fixture.dispose();
  });
}
