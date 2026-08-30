import 'dart:async';

import 'package:dan_player/component/background_image_motion.dart';
import 'package:dan_player/component/full_width_spectrum.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Lyric extends Lyric {
  _Lyric()
      : super([
          for (var i = 0; i < 20; i++)
            LrcLine(Duration(seconds: i * 5), 'Synthetic line $i',
                isBlank: false, length: const Duration(seconds: 5)),
        ]);
}

class _Fixture {
  final preferences = ValueNotifier(const RenderingPreferences());
  final hidden = ValueNotifier(false);
  final positions = StreamController<double>.broadcast(sync: true);
  final spectra = StreamController<List<double>>.broadcast(sync: true);
  final lyric = _Lyric();
  final controller = LyricViewController();
  double current = 0;
  int reads = 0;
  int fftReads = 0;

  void emit(double seconds) {
    current = seconds;
    positions.add(seconds);
    spectra.add([seconds / 100, .8]);
  }

  Widget views({bool visible = true}) => Column(children: [
        SizedBox(
            height: 300,
            child: ChangeNotifierProvider.value(
              value: controller,
              child: VerticalLyricScrollView(
                lyric: lyric,
                positionStream: positions.stream,
                readPosition: () {
                  reads++;
                  return current;
                },
                onSeek: emit,
                hidden: hidden,
              ),
            )),
        FullWidthSpectrumView(
            height: 60,
            samples: spectra.stream,
            readLevels: () {
              fftReads++;
              return [.1, .8];
            },
            hidden: hidden),
        SizedBox(
            height: 30,
            child: BackgroundImageMotion(
              enabled: true,
              isPlaying: true,
              isVisible: visible,
              hidden: hidden,
              child: const ColoredBox(color: Colors.blue),
            )),
      ]);

  Widget app(
          {bool ticker = true,
          bool visible = true,
          ValueListenable<RenderingPreferences>? preferenceSource,
          GlobalKey<NavigatorState>? navigator}) =>
      RenderingPreferencesScope(
        preferences: preferenceSource ?? preferences,
        child: MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
              body: TickerMode(
            enabled: ticker,
            child: Center(
                child: SizedBox(width: 440, child: views(visible: visible))),
          )),
        ),
      );

  Future<void> dispose() async {
    await positions.close();
    await spectra.close();
    preferences.dispose();
    hidden.dispose();
    controller.dispose();
  }
}

ValueListenable<Duration> _position(WidgetTester tester) => tester
    .widgetList<LyricViewTile>(find.byType(LyricViewTile, skipOffstage: false))
    .first
    .position;

ValueListenable<double> _phase(WidgetTester tester) => tester
    .widget<ValueListenableBuilder<double>>(find.descendant(
      of: find.byType(BackgroundImageMotion, skipOffstage: false),
      matching:
          find.byType(ValueListenableBuilder<double>, skipOffstage: false),
      skipOffstage: false,
    ))
    .valueListenable;

ValueListenable<List<double>> _levels(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint, skipOffstage: false))
    .map((paint) => paint.painter)
    .whereType<FrequencySpectrumPainter>()
    .single
    .levels;

void main() {
  testWidgets('opt-out immediately resumes mounted streams and hidden clock',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.hidden.value = true;
    await tester.pumpWidget(fixture.app(ticker: false, visible: false));
    final lyricState = tester.state(find.byType(VerticalLyricScrollView));
    final position = _position(tester);
    final phase = _phase(tester);
    final levels = _levels(tester);
    expect(fixture.positions.hasListener, isFalse);
    expect(fixture.spectra.hasListener, isFalse);
    expect(fixture.reads, 0);
    fixture.current = 20;
    fixture.preferences.value =
        const RenderingPreferences(pauseWhenHidden: false);
    // No frame: these are mounted stream/timer owners, not newly built pages.
    expect(fixture.positions.hasListener, isTrue);
    expect(fixture.spectra.hasListener, isTrue);
    expect(position.value, const Duration(seconds: 20));
    fixture.emit(35);
    expect(position.value, const Duration(seconds: 35));
    expect(levels.value.first, .35);
    await tester.pump(const Duration(milliseconds: 100));
    expect(phase.value, greaterThan(0));
    expect(
        tester.state(find.byType(VerticalLyricScrollView)), same(lyricState));

    final stoppedPhase = phase.value;
    fixture.preferences.value = const RenderingPreferences();
    expect(fixture.positions.hasListener, isFalse);
    expect(fixture.spectra.hasListener, isFalse);
    fixture.emit(40);
    await tester.pump(const Duration(seconds: 1));
    expect(position.value, const Duration(seconds: 35));
    expect(phase.value, stoppedPhase);
    expect(levels.value, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'opt-out keeps data and clock on an already mounted covered route',
      (tester) async {
    final fixture = _Fixture();
    final navigator = GlobalKey<NavigatorState>();
    addTearDown(fixture.dispose);
    fixture.preferences.value =
        const RenderingPreferences(pauseWhenHidden: false);
    await tester.pumpWidget(fixture.app(navigator: navigator));
    final original = tester.state(find.byType(VerticalLyricScrollView));
    final position = _position(tester);
    final phase = _phase(tester);
    var visits = 0;
    final page = PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, animation, secondary) {
        visits++;
        return const Text('Other page');
      },
    );
    expect(visits, 0);
    unawaited(navigator.currentState!.push(page));
    await tester.pump();
    await tester.pump();
    expect(visits, 1);
    expect(fixture.positions.hasListener, isTrue);
    expect(fixture.spectra.hasListener, isTrue);
    final before = phase.value;
    fixture.emit(45);
    await tester.pump(const Duration(milliseconds: 100));
    expect(position.value, const Duration(seconds: 45));
    expect(phase.value, greaterThan(before));
    // Navigator may still mute an offstage route's animation tickers. The
    // preference guarantees mounted data/timers, not offscreen raster frames.
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump();
    expect(tester.state(find.byType(VerticalLyricScrollView)), same(original));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  for (final lifecycle in [
    AppLifecycleState.paused,
    AppLifecycleState.detached
  ]) {
    testWidgets('opt-out still stops immediately at $lifecycle',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      fixture.preferences.value =
          const RenderingPreferences(pauseWhenHidden: false);
      await tester.pumpWidget(fixture.app());
      final position = _position(tester);
      final phase = _phase(tester);
      await tester.pump(const Duration(milliseconds: 100));
      final before = phase.value;
      tester.binding.handleAppLifecycleStateChanged(lifecycle);
      expect(fixture.positions.hasListener, isFalse);
      expect(fixture.spectra.hasListener, isFalse);
      fixture.emit(25);
      await tester.pump(const Duration(seconds: 1));
      expect(position.value, Duration.zero);
      expect(phase.value, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(fixture.positions.hasListener, isTrue);
      expect(fixture.spectra.hasListener, isTrue);
      expect(position.value, const Duration(seconds: 25));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  for (final lifecycle in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden
  ]) {
    testWidgets('opt-out allows mounted work at visibility-only $lifecycle',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      fixture.preferences.value =
          const RenderingPreferences(pauseWhenHidden: false);
      await tester.pumpWidget(fixture.app());
      final position = _position(tester);
      final phase = _phase(tester);
      tester.binding.handleAppLifecycleStateChanged(lifecycle);
      expect(fixture.positions.hasListener, isTrue);
      expect(fixture.spectra.hasListener, isTrue);
      fixture.emit(15);
      await tester.pump(const Duration(milliseconds: 100));
      expect(position.value, const Duration(seconds: 15));
      expect(phase.value, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  for (final feature in ['disableAnimations', 'reduceMotion', 'highContrast']) {
    testWidgets('opt-out does not override platform $feature', (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      fixture.preferences.value =
          const RenderingPreferences(pauseWhenHidden: false);
      await tester.pumpWidget(fixture.app());
      final phase = _phase(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(
        disableAnimations: feature == 'disableAnimations',
        reduceMotion: feature == 'reduceMotion',
        highContrast: feature == 'highContrast',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(phase.value, 0);
      if (feature != 'highContrast') {
        expect(fixture.spectra.hasListener, isFalse);
      }
      expect(fixture.positions.hasListener, isTrue,
          reason: 'Reduced animation does not disable current lyric data');
      fixture.emit(10);
      expect(_position(tester).value, const Duration(seconds: 10));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'replaced preference listener is detached and disposal still wins',
      (tester) async {
    final fixture = _Fixture();
    final replacement = ValueNotifier(const RenderingPreferences());
    addTearDown(fixture.dispose);
    addTearDown(replacement.dispose);
    fixture.hidden.value = true;
    fixture.preferences.value =
        const RenderingPreferences(pauseWhenHidden: false);
    await tester.pumpWidget(fixture.app());
    expect(fixture.positions.hasListener, isTrue);
    await tester.pumpWidget(fixture.app(preferenceSource: replacement));
    expect(fixture.positions.hasListener, isFalse);
    expect(fixture.spectra.hasListener, isFalse);
    fixture.preferences.value = const RenderingPreferences();
    fixture.preferences.value =
        const RenderingPreferences(pauseWhenHidden: false);
    expect(fixture.positions.hasListener, isFalse);
    replacement.value = const RenderingPreferences(pauseWhenHidden: false);
    expect(fixture.positions.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(fixture.positions.hasListener, isFalse);
    expect(fixture.spectra.hasListener, isFalse);
    replacement.value = const RenderingPreferences();
    fixture.hidden.value = false;
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
