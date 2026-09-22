import 'dart:async';

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

void main() {
  testWidgets('an ending overlapping voice does not restart the same scroll',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final controller = _controller(tester);
    await fixture.emit(tester, 5.08);
    await tester.pump(const Duration(milliseconds: 520));
    expect(controller.position.isScrollingNotifier.value, isTrue);
    final phase = _effect(tester, 1).clock.value;
    await fixture.emit(tester, 5.6);
    expect(_effect(tester, 1).clock.value, phase,
        reason: 'The same anchor must retain its original lag trajectory');
    expect(_effect(tester, 0).blurAnimation!.value, 0);
    await tester.pump(
        LyricMotion.springScrollDuration - const Duration(milliseconds: 519));
    expect(controller.position.isScrollingNotifier.value, isFalse,
        reason: 'The original scroll must finish on its original clock');
    expect(_effect(tester, 0).blurAnimation!.value,
        inExclusiveRange(0, LyricMotion.blurForDistance(1)));
    await tester.pumpAndSettle();
    expect(_effect(tester, 0).blurAnimation, isNull);
    expect(_effect(tester, 0).blur, LyricMotion.blurForDistance(1));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('same-line seek rejoins a voice without moving the anchor',
      (tester) async {
    final fixture = _Fixture(position: 5.8);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final controller = _controller(tester);
    final offset = controller.offset;
    await fixture.emit(tester, 5.5);
    expect(_effect(tester, 0).blurAnimation!.value,
        LyricMotion.blurForDistance(1));
    expect(controller.position.isScrollingNotifier.value, isFalse);
    await tester.pump(const Duration(milliseconds: 120));
    final blur = _effect(tester, 0).blurAnimation!.value;
    expect(blur, inExclusiveRange(0, LyricMotion.blurForDistance(1)));
    await fixture.emit(tester, 5.8);
    expect(_effect(tester, 0).blurAnimation!.value, closeTo(blur, 1e-9),
        reason: 'Rapid voice changes start at the currently painted blur');
    await tester.pumpAndSettle();
    expect(controller.offset, offset);
    expect(_effect(tester, 0).blurAnimation, isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a new line inherits the unfinished voice blur without snapping',
      (tester) async {
    final fixture = _Fixture(position: 5.8);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await fixture.emit(tester, 5.5);
    await tester.pump(const Duration(milliseconds: 120));
    final blur = _effect(tester, 0).blurAnimation!.value;
    await fixture.emit(tester, 10.1);
    final effect = _effect(tester, 0);
    expect(effect.blurAnimation, isNull);
    expect(effect.transition!.sample(effect.clock.value).blur,
        closeTo(blur, 1e-9));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'voice changes while blur is disabled retain the correct resting state',
      (tester) async {
    final fixture = _Fixture(position: 5.5);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    fixture.preferences.value =
        fixture.preferences.value.copyWith(surfaceBlur: false);
    await tester.pump();
    await fixture.emit(tester, 5.8);
    expect(_effect(tester, 0).blurAnimation, isNull);
    fixture.preferences.value =
        fixture.preferences.value.copyWith(surfaceBlur: true);
    await tester.pumpAndSettle();
    expect(_effect(tester, 0).blur, LyricMotion.blurForDistance(1));
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
    expect(_effect(tester, 0).blur, LyricMotion.blurForDistance(1));
    expect(_controller(tester).offset, offset);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final stop in ['hidden', 'animations', 'blur', 'manual', 'dispose']) {
    testWidgets('voice blur releases its finite clock on $stop',
        (tester) async {
      final fixture = _Fixture(position: 5.8);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await fixture.emit(tester, 5.5);
      await tester.pump(const Duration(milliseconds: 120));
      expect(_effect(tester, 0).blurAnimation, isNotNull);
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
        expect(_effect(tester, 0).blurAnimation, isNull);
      }
      // Existing finite scale/focus animation may finish; the new blur clock
      // must neither survive this boundary nor schedule work while idle.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
