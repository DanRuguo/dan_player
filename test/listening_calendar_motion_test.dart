import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/listening_calendar_card.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _capture(GlobalKey key, WidgetTester tester, String name) async {
  const output = String.fromEnvironment('DAN_CALENDAR_MOTION_RENDER');
  if (output.isEmpty) return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
          (await image.toByteData(format: raster.ImageByteFormat.png))!
              .buffer
              .asUint8List());
    } finally {
      image.dispose();
    }
  });
}

class _Harness {
  final width = ValueNotifier(650.0);
  final visible = ValueNotifier(true);
  final reduced = ValueNotifier(false);
  final preferences = ValueNotifier(const MotionPreferences());
  final boundary = GlobalKey();
  final statistics = PlaybackStatistics.inMemory(initialData: {
    'version': 3,
    'playCountTrackingStartedOn': '2026-07-06',
    'days': {
      for (var day = 1; day <= 26; day++)
        '2026-09-${day.toString().padLeft(2, '0')}': day % 4 * 3600000
    },
    'dailyPlayCounts': {'2026-09-26': 2},
  });
  Widget build() => RepaintBoundary(
      key: boundary,
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: Entry(welcome: false)
              .fromSchemeAndFontFamily(
                  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal))
              .copyWith(platform: TargetPlatform.windows),
          home: AnimatedBuilder(
              animation:
                  Listenable.merge([width, visible, reduced, preferences]),
              builder: (context, _) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: reduced.value),
                  child: MotionPreferencesScope(
                      preferences: preferences.value,
                      child: TickerMode(
                          enabled: visible.value,
                          child: Scaffold(
                              body:
                                  SingleChildScrollView(child: Center(child: SizedBox(width: width.value, child: ListeningCalendarCard(statistics: statistics, now: DateTime(2026, 9, 26))))))))))));
  void dispose() {
    width.dispose();
    visible.dispose();
    reduced.dispose();
    preferences.dispose();
    statistics.dispose();
  }
}

void main() {
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      )
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  Future<_Harness> setup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();
    return harness;
  }

  Finder getRail() => find.byKey(const ValueKey('statistics-calendar-scroll'));
  ScrollController controller(WidgetTester tester) =>
      tester.widget<SingleChildScrollView>(getRail()).controller!;
  Finder day(String key) => find.byKey(ValueKey('listening-day-$key'));
  double cellWidth(WidgetTester tester) =>
      tester.getSize(day('2026-09-21')).width;
  double opacity(WidgetTester tester) => tester
      .widget<FadeTransition>(find.byKey(const ValueKey('calendar-range-fade')))
      .opacity
      .value;
  Future<void> year(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('statistics-calendar-year')));
    await tester.pumpAndSettle();
  }

  Future<void> wheel(WidgetTester tester, Offset delta) async =>
      tester.sendEventToBinding(PointerScrollEvent(
          position: tester.getCenter(getRail()), scrollDelta: delta));

  testWidgets(
      'resize cells interpolate start/middle/end and retain latest-week anchor',
      (tester) async {
    final harness = await setup(tester);
    final start = cellWidth(tester);
    await _capture(harness.boundary, tester, 'resize-start');
    harness.width.value = 1000;
    await tester.pump();
    expect(cellWidth(tester), closeTo(start, .01));
    await tester.pump(const Duration(milliseconds: 75));
    final middle = cellWidth(tester);
    expect(middle, greaterThan(start));
    await _capture(harness.boundary, tester, 'resize-middle');
    await tester.pumpAndSettle();
    final end = cellWidth(tester);
    expect(end, greaterThan(middle));
    await _capture(harness.boundary, tester, 'resize-end');
    final rail = tester.getRect(getRail());
    final last = tester.getRect(day('2026-09-21'));
    expect(last.right, closeTo(rail.right - 4, .1));
    harness.width.value = 320;
    await tester.pumpAndSettle();
    expect(controller(tester).offset,
        closeTo(controller(tester).position.maxScrollExtent, .1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'range switch fades one real grid and animates toward latest week',
      (tester) async {
    final harness = await setup(tester);
    await _capture(harness.boundary, tester, 'range-start');
    await tester.tap(find.byKey(const ValueKey('statistics-calendar-year')));
    await tester.pump();
    expect(opacity(tester), 0);
    await tester.pump();
    final start = controller(tester).offset;
    await tester.pump(const Duration(milliseconds: 75));
    expect(opacity(tester), inExclusiveRange(0.0, 1.0));
    expect(controller(tester).offset, greaterThan(start));
    expect(controller(tester).offset,
        lessThan(controller(tester).position.maxScrollExtent));
    expect(day('2026-09-26'), findsOneWidget);
    await _capture(harness.boundary, tester, 'range-middle');
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
    expect(
        controller(tester).offset, controller(tester).position.maxScrollExtent);
    await _capture(harness.boundary, tester, 'range-end');
    await tester
        .tap(find.byKey(const ValueKey('statistics-calendar-twelveWeeks')));
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
    expect(controller(tester).offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'continuous vertical and horizontal wheel events accumulate smooth targets',
      (tester) async {
    final harness = await setup(tester);
    await year(tester);
    final start = controller(tester).offset;
    await wheel(tester, const Offset(0, -40));
    await wheel(tester, const Offset(-60, 0));
    await tester.pump();
    expect(controller(tester).offset, start);
    await tester.pump(const Duration(milliseconds: 60));
    expect(controller(tester).offset, lessThan(start));
    expect(controller(tester).offset, greaterThan(start - 100));
    await _capture(harness.boundary, tester, 'wheel-middle');
    await wheel(tester, const Offset(0, -20));
    await tester.pumpAndSettle();
    expect(controller(tester).offset, closeTo(start - 120, .01));
    await _capture(harness.boundary, tester, 'wheel-end');
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [true, false]) {
    testWidgets(
        'reduced=$reduced or individual disabled categories finish immediately',
        (tester) async {
      final harness = await setup(tester);
      if (reduced) {
        harness.reduced.value = true;
      } else {
        harness.preferences.value = const MotionPreferences(disabled: {
          MotionKind.layout,
          MotionKind.feedback,
          MotionKind.transitions
        });
      }
      await tester.pump();
      final start = cellWidth(tester);
      harness.width.value = 1000;
      await tester.pump();
      expect(cellWidth(tester), greaterThan(start));
      await tester.tap(find.byKey(const ValueKey('statistics-calendar-year')));
      await tester.pump();
      expect(opacity(tester), 1);
      final rail = controller(tester);
      expect(rail.offset, rail.position.maxScrollExtent);
      final before = rail.offset;
      await wheel(tester, const Offset(0, -80));
      await tester.pump();
      expect(rail.offset, closeTo(before - 80, .01));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('opposing wheel signals at an edge cancel the pending target',
      (tester) async {
    await setup(tester);
    await year(tester);
    final end = controller(tester).position.maxScrollExtent;
    await wheel(tester, const Offset(0, -40));
    await wheel(tester, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(controller(tester).offset, end);
    controller(tester).jumpTo(0);
    await tester.pumpAndSettle();
    await wheel(tester, const Offset(40, 0));
    await wheel(tester, const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(controller(tester).offset, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'hidden mode completes in-flight range/scroll/layout and schedules no idle frames',
      (tester) async {
    final harness = await setup(tester);
    await tester.tap(find.byKey(const ValueKey('statistics-calendar-year')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 45));
    expect(opacity(tester), lessThan(1));
    harness.visible.value = false;
    harness.width.value = 1000;
    await tester.pump();
    await tester.pump();
    expect(opacity(tester), 1);
    expect(
        controller(tester).offset, controller(tester).position.maxScrollExtent);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    for (var tick = 0; tick < 4; tick++) {
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
    harness.visible.value = true;
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'native touch stretch deforms only grid at a fit-width edge and returns to rest',
      (tester) async {
    final harness = await setup(tester);
    final indicator = find.descendant(
        of: getRail(), matching: find.byType(StretchingOverscrollIndicator));
    expect(indicator, findsOneWidget);
    final native = tester.widget<StretchingOverscrollIndicator>(indicator);
    expect(native.axis, Axis.horizontal);
    final before = tester.getRect(find.text('周一'));
    expect(controller(tester).position.maxScrollExtent, 0);
    final touch = await tester.startGesture(tester.getCenter(getRail()),
        kind: PointerDeviceKind.touch);
    await touch.moveBy(const Offset(80, 0));
    await touch.moveBy(const Offset(90, 0));
    await tester.pump();
    final effect = tester.widget<StretchEffect>(
        find.descendant(of: indicator, matching: find.byType(StretchEffect)));
    expect(effect.stretchStrength.abs(), greaterThan(0));
    expect(tester.getRect(find.text('周一')), before);
    await _capture(harness.boundary, tester, 'touch-stretch-held');
    await touch.up();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<StretchEffect>(find.descendant(
                of: indicator, matching: find.byType(StretchEffect)))
            .stretchStrength,
        0);
    await _capture(harness.boundary, tester, 'touch-stretch-rest');
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final gate in ['feedback', 'reduced', 'hidden']) {
    testWidgets(
        'native heatmap stretch stops immediately when $gate disables motion',
        (tester) async {
      final harness = await setup(tester);
      final indicator = find.descendant(
          of: getRail(), matching: find.byType(StretchingOverscrollIndicator));
      final touch = await tester.startGesture(tester.getCenter(getRail()),
          kind: PointerDeviceKind.touch);
      await touch.moveBy(const Offset(80, 0));
      await touch.moveBy(const Offset(90, 0));
      await tester.pump();
      expect(
          tester
              .widget<StretchEffect>(find.descendant(
                  of: indicator, matching: find.byType(StretchEffect)))
              .stretchStrength
              .abs(),
          greaterThan(0));
      switch (gate) {
        case 'feedback':
          harness.preferences.value =
              const MotionPreferences(disabled: {MotionKind.feedback});
        case 'reduced':
          harness.reduced.value = true;
        case 'hidden':
          harness.visible.value = false;
      }
      await tester.pump();
      expect(indicator, findsNothing);
      await touch.up();
      await tester.pumpAndSettle();
      expect(controller(tester).offset, 0);
      for (var tick = 0; tick < 3; tick++) {
        await tester.pump(const Duration(seconds: 1));
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'platform reduce motion completes range and wheel without idle frames',
      (tester) async {
    final harness = await setup(tester);
    await tester.tap(find.byKey(const ValueKey('statistics-calendar-year')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(opacity(tester), lessThan(1));
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    await tester.pump();
    expect(opacity(tester), 1);
    final before = controller(tester).offset;
    await wheel(tester, const Offset(-50, 0));
    await tester.pump();
    expect(controller(tester).offset, closeTo(before - 50, .01));
    harness.width.value = 1000;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: getRail(),
            matching: find.byType(StretchingOverscrollIndicator)),
        findsNothing);
    for (var tick = 0; tick < 3; tick++) {
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
    expect(tester.takeException(), isNull);
  });
}
