import 'dart:async';

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_viewport_blur.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Word extends SyncLyricWord {
  _Word(int startMs, int lengthMs, String text)
      : super(Duration(milliseconds: startMs), Duration(milliseconds: lengthMs),
            text);
}

class _Line extends SyncLyricLine {
  _Line(int startMs, int lengthMs, String text)
      : super(Duration(milliseconds: startMs), Duration(milliseconds: lengthMs),
            [_Word(startMs, lengthMs, text)]);
}

class _Lyrics extends Lyric {
  _Lyrics()
      : super([
          _Line(0, 5600, 'Previous voice'),
          for (var i = 1; i < 12; i++) _Line(i * 5000, 5000, 'Voice $i'),
        ]);
}

class _Fixture {
  _Fixture({this.position = 4.9}) {
    addTearDown(() async {
      await positions.close();
      settings.dispose();
      hidden.dispose();
      preferences.dispose();
    });
  }

  final positions = StreamController<double>.broadcast(sync: true);
  final settings = LyricViewController()
    ..lyricFontSize = 22
    ..translationFontSize = 17
    ..lyricTextAlign = LyricTextAlign.left;
  final hidden = ValueNotifier(false);
  final preferences = ValueNotifier(const RenderingPreferences());
  final lyric = _Lyrics();
  double position;

  Widget app() => MaterialApp(
        builder: (_, child) =>
            RenderingPreferencesScope(preferences: preferences, child: child!),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 440,
              height: 480,
              child: ChangeNotifierProvider.value(
                value: settings,
                child: VerticalLyricScrollView(
                  lyric: lyric,
                  positionStream: positions.stream,
                  readPosition: () => position,
                  onSeek: (_) {},
                  springLyrics: true,
                  hidden: hidden,
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> emit(WidgetTester tester, double seconds) async {
    position = seconds;
    positions.add(seconds);
    await tester.pump();
    await tester.pump();
  }
}

Finder get _scroll => find.byKey(const ValueKey('vertical-lyric-scroll'));
ScrollController _controller(WidgetTester tester) =>
    tester.widget<CustomScrollView>(_scroll).controller!;
LyricFollowEffects _effect(WidgetTester tester, int index) => tester
    .widgetList<LyricFollowEffects>(find.byType(LyricFollowEffects))
    .elementAt(index);

LyricViewportBlur _mask(WidgetTester tester) =>
    tester.widget<LyricViewportBlur>(find.byType(LyricViewportBlur));

List<({Rect bounds, Object filter, bool enabled})> _maskBands(
        WidgetTester tester) =>
    find
        .descendant(
            of: find.byType(LyricViewportBlur),
            matching: find.byType(BackdropFilter))
        .evaluate()
        .map((element) {
      final filter = element.widget as BackdropFilter;
      final render =
          tester.renderObject<RenderBackdropFilter>(find.byWidget(filter));
      expect(render.filterConfig.filter, isNotNull,
          reason: 'Each fixed band retains its real Gaussian filter');
      return (
        bounds: tester.getRect(find.byWidget(filter)),
        filter: render.filterConfig.filter!,
        enabled: render.enabled,
      );
    }).toList();

void _expectNoVoiceBlur(WidgetTester tester) {
  for (final effect in tester
      .widgetList<LyricFollowEffects>(find.byType(LyricFollowEffects))) {
    expect(effect.blur, 0);
    expect(effect.blurEnabled, isFalse);
    expect(effect.blurAnimation, isNull,
        reason: 'Overlapping voices cannot acquire their own blur clocks');
    if (effect.transition != null) {
      expect(effect.transition!.sample(effect.clock.value).blur, 0);
    }
  }
}

void _expectFixedMask(WidgetTester tester, {bool enabled = true}) {
  expect(
      tester.getRect(find.byType(LyricViewportBlur)), tester.getRect(_scroll));
  expect(_mask(tester).enabled, enabled);
  expect(_mask(tester).reading.value, 1);
  expect(_mask(tester).reading.isAnimating, isFalse);
  final bands = _maskBands(tester);
  expect(bands, hasLength(12));
  expect(bands.every((band) => band.enabled == enabled), isTrue);
  _expectNoVoiceBlur(tester);
}

void main() {
  testWidgets('an ending overlapping voice does not restart the same scroll',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final controller = _controller(tester);
    _expectFixedMask(tester);
    final bands = _maskBands(tester);
    final readingClock = _mask(tester).reading;
    await fixture.emit(tester, 5.08);
    await tester.pump(const Duration(milliseconds: 520));
    expect(controller.position.isScrollingNotifier.value, isTrue);
    final phase = _effect(tester, 1).clock.value;
    await fixture.emit(tester, 5.6);
    expect(_effect(tester, 1).clock.value, phase,
        reason: 'The same anchor must retain its original lag trajectory');
    _expectFixedMask(tester);
    expect(_maskBands(tester), bands,
        reason: 'Ending a voice cannot move or retune fixed viewport bands');
    expect(_mask(tester).reading, same(readingClock));
    await tester.pump(
        LyricMotion.springScrollDuration - const Duration(milliseconds: 519));
    expect(controller.position.isScrollingNotifier.value, isFalse,
        reason: 'The original scroll must finish on its original clock');
    _expectFixedMask(tester);
    expect(_maskBands(tester), bands);
    await tester.pumpAndSettle();
    _expectFixedMask(tester);
    expect(_maskBands(tester), bands);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('same-line seek rejoins a voice without moving the anchor',
      (tester) async {
    final fixture = _Fixture(position: 5.8);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final controller = _controller(tester);
    final offset = controller.offset;
    _expectFixedMask(tester);
    final bands = _maskBands(tester);
    final readingClock = _mask(tester).reading;
    await fixture.emit(tester, 5.5);
    _expectFixedMask(tester);
    expect(controller.position.isScrollingNotifier.value, isFalse);
    await tester.pump(const Duration(milliseconds: 120));
    expect(_maskBands(tester), bands);
    await fixture.emit(tester, 5.8);
    _expectFixedMask(tester);
    expect(_maskBands(tester), bands,
        reason: 'Rapid overlap changes retain the same viewport surface');
    expect(_mask(tester).reading, same(readingClock));
    await tester.pumpAndSettle();
    expect(controller.offset, offset);
    _expectFixedMask(tester);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a new line keeps fixed blur and a continuous bounded lag',
      (tester) async {
    final fixture = _Fixture(position: 5.8);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await fixture.emit(tester, 5.5);
    await tester.pump(const Duration(milliseconds: 120));
    final previous = _effect(tester, 0);
    final lag = previous.transition?.sample(previous.clock.value).offset ?? 0;
    final bands = _maskBands(tester);
    await fixture.emit(tester, 10.1);
    final effect = _effect(tester, 0);
    expect(effect.transition, isNotNull);
    expect(effect.transition!.sample(effect.clock.value).offset,
        closeTo(lag, 1e-9));
    _expectFixedMask(tester);
    expect(_maskBands(tester), bands);
    await tester.pump(const Duration(milliseconds: 120));
    expect(effect.clock.value, inExclusiveRange(0, 1));
    expect(effect.transition!.sample(effect.clock.value).offset.abs(),
        lessThanOrEqualTo(48));
    await tester.pumpAndSettle();
    expect(effect.clock.isAnimating, isFalse);
    expect(effect.transition!.sample(effect.clock.value).offset, 0);
    expect(_maskBands(tester), bands);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'voice changes while blur is disabled retain the correct resting state',
      (tester) async {
    final fixture = _Fixture(position: 5.5);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final bands = _maskBands(tester);
    fixture.preferences.value =
        fixture.preferences.value.copyWith(surfaceBlur: false);
    await tester.pump();
    await fixture.emit(tester, 5.8);
    _expectFixedMask(tester, enabled: false);
    fixture.preferences.value =
        fixture.preferences.value.copyWith(surfaceBlur: true);
    await tester.pumpAndSettle();
    _expectFixedMask(tester);
    expect(_maskBands(tester), bands);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'enabling blur while paused refreshes context without restarting scroll',
      (tester) async {
    final fixture = _Fixture(position: 5.8);
    fixture.preferences.value =
        fixture.preferences.value.copyWith(surfaceBlur: false);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final offset = _controller(tester).offset;
    fixture.preferences.value =
        fixture.preferences.value.copyWith(surfaceBlur: true);
    await tester.pumpAndSettle();
    _expectFixedMask(tester);
    expect(_controller(tester).offset, offset);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final stop in ['hidden', 'animations', 'blur', 'manual', 'dispose']) {
    testWidgets('fixed viewport blur leaves no finite clock after $stop',
        (tester) async {
      final fixture = _Fixture(position: 5.8);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await fixture.emit(tester, 5.5);
      await tester.pump(const Duration(milliseconds: 120));
      _expectFixedMask(tester);
      final bands = _maskBands(tester).map((band) => band.bounds).toList();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(_scroll));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      final readingClock = _mask(tester).reading;
      expect(readingClock.isAnimating, isTrue);
      expect(readingClock.value, inExclusiveRange(0, 1),
          reason: 'Exercise the real finite viewport hover clock');
      _expectNoVoiceBlur(tester);
      switch (stop) {
        case 'hidden':
          fixture.hidden.value = true;
        case 'animations':
          fixture.preferences.value = fixture.preferences.value.copyWith(
              animations:
                  const MotionPreferences(disabled: {MotionKind.lyrics}));
        case 'blur':
          fixture.preferences.value =
              fixture.preferences.value.copyWith(surfaceBlur: false);
        case 'manual':
          await tester.sendEventToBinding(PointerScrollEvent(
              position: tester.getCenter(_scroll),
              scrollDelta: const Offset(0, 50)));
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
      }
      await tester.pump();
      if (stop != 'dispose') {
        _expectNoVoiceBlur(tester);
        expect(_mask(tester).reading, same(readingClock));
        expect(_maskBands(tester).map((band) => band.bounds), bands,
            reason: 'Activity changes cannot relocate the fixed blur bands');
        expect(_mask(tester).enabled, stop != 'blur' && stop != 'manual');
        if (stop == 'hidden' || stop == 'animations' || stop == 'manual') {
          expect(readingClock.isAnimating, isFalse);
        }
      } else {
        expect(find.byType(LyricViewportBlur), findsNothing);
      }
      // Existing finite focus/hover motion can finish. Voice membership owns
      // no extra blur clock, and disabled/hidden surfaces must become idle.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(readingClock.isAnimating, isFalse);
      if (stop == 'manual' && tester.binding.transientCallbackCount != 0) {
        // A real wheel moves cards beneath the stationary mouse. The frame's
        // hit-test update can start Material enter/exit feedback at its end;
        // a zero-duration pump does not advance those newly started clocks.
        // Keep the original idle oracle and stay within the four-second grace.
        await tester.pumpAndSettle(const Duration(milliseconds: 16),
            EnginePhase.sendSemanticsUpdate, const Duration(seconds: 1));
        expect(readingClock.isAnimating, isFalse);
        expect(_mask(tester).enabled, isFalse);
        _expectNoVoiceBlur(tester);
      }
      expect(tester.binding.transientCallbackCount, 0);
      if (stop == 'hidden') {
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        _expectFixedMask(tester);
        fixture.hidden.value = false;
        await tester.pump();
        _expectFixedMask(tester);
        expect(_maskBands(tester).map((band) => band.bounds), bands,
            reason:
                'The first restored frame keeps its configured static mask');
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      }
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    });
  }
}
