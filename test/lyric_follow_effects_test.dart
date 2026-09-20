import 'dart:async';

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Lyric extends Lyric {
  _Lyric(super.lines);
}

class _Fixture {
  _Fixture() {
    settings.lyricFontSize = 22;
    settings.translationFontSize = 17;
    settings.lyricTextAlign = LyricTextAlign.left;
    addTearDown(() async {
      await positions.close();
      settings.dispose();
      preferences.dispose();
      hidden.dispose();
    });
  }

  final settings = LyricViewController();
  final positions = StreamController<double>.broadcast(sync: true);
  final hidden = ValueNotifier(false);
  final preferences = ValueNotifier(const RenderingPreferences());
  final lyric = _Lyric([
    for (var i = 0; i < 320; i++)
      LrcLine(Duration(seconds: i * 4), 'Lyric line $i',
          isBlank: false, length: const Duration(seconds: 4)),
  ]);
  double position = 400;
  bool highContrast = false;
  bool reduced = false;

  void emit(double value) {
    position = value;
    positions.add(value);
  }

  Widget app() => MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            highContrast: highContrast,
            disableAnimations: reduced,
          ),
          child: RenderingPreferencesScope(
              preferences: preferences, child: child!),
        ),
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
                  onSeek: emit,
                  hidden: hidden,
                ),
              ),
            ),
          ),
        ),
      );
}

Finder get _scroll => find.byKey(const ValueKey('vertical-lyric-scroll'));
List<LyricFollowEffects> _effects(WidgetTester tester) => tester
    .widgetList<LyricFollowEffects>(find.byType(LyricFollowEffects))
    .toList();
ScrollController _controller(WidgetTester tester) =>
    tester.widget<CustomScrollView>(_scroll).controller!;
double _offset(LyricFollowEffects effect) =>
    effect.transition?.sample(effect.clock.value).offset ?? 0;
Iterable<ImageFiltered> _enabledFilters(WidgetTester tester) => tester
    .widgetList<ImageFiltered>(find.byType(ImageFiltered))
    .where((filter) => filter.enabled);

Future<void> _advance(
    WidgetTester tester, _Fixture fixture, double value) async {
  fixture.emit(value);
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  test('follow trajectory is continuous, bounded and ends exactly at rest', () {
    for (final distance in [-4000.0, -80.0, 80.0, 4000.0]) {
      final flight = LyricFollowTransition(
        distance: distance,
        delay: .18,
        curve: LyricMotion.scrollCurveFor(spring: true, distance: distance),
        initialOffset: 12,
        initialBlur: .65,
        finalBlur: 0,
      );
      expect(flight.sample(0), (offset: 12.0, blur: .65));
      for (var frame = 0; frame <= 100; frame++) {
        final sample = flight.sample(frame / 100);
        expect(sample.offset.abs(), lessThanOrEqualTo(36));
        expect(sample.blur, inInclusiveRange(0, .65));
      }
      expect(flight.sample(1), (offset: 0.0, blur: 0.0));
    }
  });

  testWidgets(
      'default follow staggers only a bounded viewport band without rebuilding rows',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final rowHeight = tester.getSize(find.byType(LyricViewTile).at(101)).height;
    await _advance(tester, fixture, 404.1);
    final effects = _effects(tester);
    final flying = effects.where((effect) => effect.transition != null);
    expect(flying.length, inInclusiveRange(2, LyricMotion.maximumFollowRows));
    expect(effects[10].transition, isNull);
    expect(effects[300].transition, isNull);
    final rowWidget = tester.widget(find.byType(LyricViewTile).at(102));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        _offset(effects[103]).abs(), greaterThan(_offset(effects[101]).abs()));
    expect(
        identical(rowWidget, tester.widget(find.byType(LyricViewTile).at(102))),
        isTrue);
    expect(
        tester.getSize(find.byType(LyricViewTile).at(101)).height, rowHeight);
    expect(_enabledFilters(tester).length,
        lessThanOrEqualTo(LyricMotion.maximumFollowRows));
    await tester.pumpAndSettle();
    expect(
        _effects(tester).every((effect) => effect.transition == null), isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'rapid handoff preserves painted offsets while seek cancels stale lag',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _advance(tester, fixture, 404.1);
    await tester.pump(const Duration(milliseconds: 100));
    final painted = _offset(_effects(tester)[103]);
    expect(painted.abs(), greaterThan(0));
    await _advance(tester, fixture, 408.1);
    expect(_offset(_effects(tester)[103]), closeTo(painted, .001));
    await tester.pump(const Duration(milliseconds: 50));
    await _advance(tester, fixture, 600.1);
    expect(
        _effects(tester).every((effect) => effect.transition == null), isTrue);
    var previous = _controller(tester).offset;
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final next = _controller(tester).offset;
      expect(next, greaterThanOrEqualTo(previous));
      previous = next;
    }
    await tester.pumpAndSettle();
    final row = tester.getRect(find.byType(LyricViewTile).at(150));
    final viewport = tester.getRect(_scroll);
    expect(row.top,
        closeTo(viewport.top + .25 * (viewport.height - row.height), .01));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'manual scrolling removes all reading effects and tap seeks the actual row',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await _advance(tester, fixture, 404.1);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.sendEventToBinding(PointerScrollEvent(
      position: tester.getCenter(_scroll),
      scrollDelta: const Offset(0, 45),
    ));
    await tester.pump();
    expect(
        _effects(tester).every((effect) => effect.transition == null), isTrue);
    expect(_enabledFilters(tester), isEmpty);
    expect(
        tester
            .widget<LyricViewportFade>(find.byType(LyricViewportFade))
            .enabled,
        isFalse);
    final manualOffset = _controller(tester).offset;
    fixture.emit(408.1);
    await tester.pump(const Duration(seconds: 1));
    expect(_controller(tester).offset, manualOffset);
    await tester.tap(find.text('Lyric line 103'));
    await tester.pumpAndSettle();
    expect(fixture.position, 412);
    expect(
        tester
            .widget<LyricViewportFade>(find.byType(LyricViewportFade))
            .enabled,
        isTrue);
  });

  testWidgets(
      'contrast, blur preference, animations and hidden state gate effects live',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(_enabledFilters(tester), isNotEmpty);
    await _advance(tester, fixture, 404.1);
    await tester.pump(const Duration(milliseconds: 80));
    fixture.highContrast = true;
    await tester.pumpWidget(fixture.app());
    expect(_enabledFilters(tester), isEmpty);
    expect(
        tester
            .widget<LyricViewportFade>(find.byType(LyricViewportFade))
            .enabled,
        isFalse);
    fixture.highContrast = false;
    fixture.preferences.value =
        fixture.preferences.value.copyWith(surfaceBlur: false);
    await tester.pumpWidget(fixture.app());
    expect(_enabledFilters(tester), isEmpty);
    fixture.preferences.value = fixture.preferences.value.copyWith(
      surfaceBlur: true,
      animations: const MotionPreferences(disabled: {MotionKind.lyrics}),
    );
    await tester.pumpAndSettle();
    expect(
        _effects(tester).every((effect) => effect.transition == null), isTrue);
    expect(_enabledFilters(tester), isEmpty);
    expect(tester.binding.transientCallbackCount, 0);
    fixture.preferences.value = const RenderingPreferences();
    await tester.pumpAndSettle();
    await _advance(tester, fixture, 408.1);
    await tester.pump(const Duration(milliseconds: 80));
    fixture.hidden.value = true;
    await tester.pump();
    expect(
        _effects(tester).every((effect) => effect.transition == null), isTrue);
    expect(_enabledFilters(tester), isEmpty);
    fixture.emit(800.1);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
    fixture.hidden.value = false;
    await tester.pumpAndSettle();
    final row = tester.getRect(find.byType(LyricViewTile).at(200));
    final viewport = tester.getRect(_scroll);
    expect(row.top,
        closeTo(viewport.top + .25 * (viewport.height - row.height), .01));
    expect(
        _effects(tester).every((effect) => effect.transition == null), isTrue);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
