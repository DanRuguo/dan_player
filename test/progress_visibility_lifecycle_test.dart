import 'dart:async';

import 'package:dan_player/component/rectangle_progress_indicator.dart';
import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RectangleProgressPainter _bottomPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<RectangleProgressPainter>()
    .single;

void main() {
  testWidgets('offstage bottom progress releases its position demand',
      (tester) async {
    final positions = StreamController<double>.broadcast(sync: true);
    addTearDown(positions.close);
    Widget host(bool visible) => MaterialApp(
          home: TickerMode(
            enabled: visible,
            child: RectangleProgressIndicator(
              size: const Size(300, 64),
              positionStream: positions.stream,
              lengthProvider: () => 100,
              child: const SizedBox(width: 300, height: 64),
            ),
          ),
        );
    await tester.pumpWidget(host(true));
    expect(positions.hasListener, isTrue);
    await tester.pumpWidget(host(false));
    expect(positions.hasListener, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('detail progress follows the live hidden-refresh preference',
      (tester) async {
    final positions = StreamController<double>.broadcast(sync: true);
    final hidden = ValueNotifier(true);
    final preferences =
        ValueNotifier(const RenderingPreferences(pauseWhenHidden: false));
    addTearDown(positions.close);
    addTearDown(hidden.dispose);
    addTearDown(preferences.dispose);
    await tester.pumpWidget(RenderingPreferencesScope(
      preferences: preferences,
      child: MaterialApp(
        home: Scaffold(
            body: DetailProgressSlider(
          positions: positions.stream,
          readPosition: () => 30,
          duration: 100,
          trackIdentity: 'track',
          hidden: hidden,
          onSeek: (_) {},
        )),
      ),
    ));
    expect(positions.hasListener, isTrue);
    preferences.value = const RenderingPreferences();
    expect(positions.hasListener, isFalse,
        reason: 'native-hidden windows may not produce a rebuilding frame');
    preferences.value = const RenderingPreferences(pauseWhenHidden: false);
    expect(positions.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(positions.hasListener, isFalse);
  });

  testWidgets('bottom progress resumes latest snapshot and cancels immediately',
      (tester) async {
    final positions = StreamController<double>.broadcast(sync: true);
    final hidden = ValueNotifier(true);
    final preferences = ValueNotifier(const RenderingPreferences());
    addTearDown(positions.close);
    addTearDown(hidden.dispose);
    addTearDown(preferences.dispose);
    var position = 10.0;
    var reads = 0;
    await tester.pumpWidget(RenderingPreferencesScope(
      preferences: preferences,
      child: MaterialApp(
        home: RectangleProgressIndicator(
          size: const Size(300, 64),
          positionStream: positions.stream,
          readPosition: () {
            reads++;
            return position;
          },
          hidden: hidden,
          lengthProvider: () => 100,
          child: const SizedBox(width: 300, height: 64),
        ),
      ),
    ));
    expect(positions.hasListener, isFalse);
    expect(reads, 0);
    hidden.value = false;
    expect(positions.hasListener, isTrue);
    expect(_bottomPainter(tester).progress.value, .1);
    hidden.value = true;
    expect(positions.hasListener, isFalse);
    for (var i = 0; i < 500; i++) {
      positions.add(i / 10);
    }
    position = 65;
    expect(_bottomPainter(tester).progress.value, .1);
    expect(reads, 1);
    hidden.value = false;
    expect(_bottomPainter(tester).progress.value, .65);
    expect(reads, 2);
    hidden.value = true;
    preferences.value = const RenderingPreferences(pauseWhenHidden: false);
    expect(positions.hasListener, isTrue);
    positions.add(70);
    expect(_bottomPainter(tester).progress.value, .7);
    preferences.value = const RenderingPreferences();
    expect(positions.hasListener, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    hidden.value = false;
    expect(positions.hasListener, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden progress source replacement reads only the new source',
      (tester) async {
    final first = StreamController<double>.broadcast(sync: true);
    final second = StreamController<double>.broadcast(sync: true);
    final hidden = ValueNotifier(false);
    addTearDown(first.close);
    addTearDown(second.close);
    addTearDown(hidden.dispose);
    Widget host(Stream<double> source, double snapshot) => MaterialApp(
          home: RectangleProgressIndicator(
            size: const Size(300, 64),
            positionStream: source,
            readPosition: () => snapshot,
            hidden: hidden,
            lengthProvider: () => 100,
            child: const SizedBox(width: 300, height: 64),
          ),
        );
    await tester.pumpWidget(host(first.stream, 10));
    hidden.value = true;
    await tester.pumpWidget(host(second.stream, 80));
    expect(first.hasListener, isFalse);
    expect(second.hasListener, isFalse);
    hidden.value = false;
    expect(_bottomPainter(tester).progress.value, .8);
    expect(first.hasListener, isFalse);
    expect(second.hasListener, isTrue);
    first.add(40);
    expect(_bottomPainter(tester).progress.value, .8);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hiding while dragging cannot seek on pointer release',
      (tester) async {
    final positions = StreamController<double>.broadcast(sync: true);
    final hidden = ValueNotifier(false);
    final seeks = <double>[];
    addTearDown(positions.close);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: RectangleProgressIndicator(
          size: const Size(300, 64),
          positionStream: positions.stream,
          initialPosition: 50,
          readPosition: () => 50,
          hidden: hidden,
          lengthProvider: () => 100,
          onSeek: seeks.add,
          child: const SizedBox(width: 300, height: 64),
        ),
      ),
    ));
    final rect = tester.getRect(find.byType(RectangleProgressIndicator));
    final drag = await tester.startGesture(rect.center);
    await drag.moveBy(const Offset(50, 0));
    await tester.pump();
    expect(_bottomPainter(tester).progress.value, greaterThan(.5));
    hidden.value = true;
    expect(positions.hasListener, isFalse);
    hidden.value = false;
    await drag.up();
    await tester.pumpAndSettle();
    expect(seeks, isEmpty);
    expect(_bottomPainter(tester).progress.value, .5);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final bottom in [false, true]) {
    testWidgets(
        '${bottom ? 'bottom' : 'detail'} progress keeps popup updates but suspends opaque cover',
        (tester) async {
      final positions = StreamController<double>.broadcast(sync: true);
      final navigator = GlobalKey<NavigatorState>();
      addTearDown(positions.close);
      final child = bottom
          ? RectangleProgressIndicator(
              size: const Size(300, 64),
              positionStream: positions.stream,
              lengthProvider: () => 100,
              child: const SizedBox(width: 300, height: 64),
            )
          : DetailProgressSlider(
              positions: positions.stream,
              readPosition: () => 20,
              duration: 100,
              trackIdentity: 'track',
              onSeek: (_) {},
            );
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(body: child),
      ));
      unawaited(navigator.currentState!.push(PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, animation, secondary) => const Text('Popup'),
      )));
      await tester.pumpAndSettle();
      expect(positions.hasListener, isTrue);
      unawaited(navigator.currentState!.push(PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, animation, secondary) => const Text('Covered'),
      )));
      await tester.pumpAndSettle();
      expect(positions.hasListener, isFalse);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(positions.hasListener, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(positions.hasListener, isFalse);
    });
  }
}
