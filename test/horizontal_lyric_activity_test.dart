import 'dart:async';

import 'package:dan_player/component/horizontal_lyric_view.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

class _Lyrics extends Lyric {
  _Lyrics(super.lines);
}

class _Harness {
  _Harness({bool longLine = false}) {
    future = Future.value(_Lyrics([
      LrcLine(Duration.zero, longLine ? '完整的横向歌词 reading ' * 30 : 'First',
          isBlank: false, length: const Duration(seconds: 10)),
      LrcLine(const Duration(seconds: 10), 'Second',
          isBlank: false, length: const Duration(seconds: 10)),
    ]));
    addTearDown(positions.close);
    addTearDown(preferences.dispose);
    addTearDown(hidden.dispose);
  }

  final positions = StreamController<double>.broadcast();
  final preferences = ValueNotifier(const RenderingPreferences());
  final hidden = ValueNotifier(false);
  late Future<Lyric?> future;
  double position = 2;

  Widget app({bool visible = true}) => MaterialApp(
        home: RenderingPreferencesScope(
          preferences: preferences,
          child: TickerMode(
            enabled: visible,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  height: 36,
                  child: HorizontalLyricContent(
                    lyricFuture: future,
                    positionStream: positions.stream,
                    readPosition: () => position,
                    hidden: hidden,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

Finder get _scroll =>
    find.byKey(const ValueKey('horizontal-lyric-scroll')).last;
ScrollController _controller(WidgetTester tester) =>
    tester.widget<SingleChildScrollView>(_scroll).controller!;

void main() {
  testWidgets('native hidden title lyrics detach without a lifecycle frame',
      (tester) async {
    final harness = _Harness(longLine: true);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    expect(harness.positions.hasListener, isTrue);
    harness.hidden.value = true;
    expect(harness.positions.hasListener, isFalse);
    harness.position = 12;
    harness.positions.add(12);
    await tester.pump();
    expect(find.text('Second'), findsNothing);
    harness.hidden.value = false;
    await tester.pumpAndSettle();
    expect(harness.positions.hasListener, isTrue);
    expect(find.text('Second'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hidden title lyrics detach before another Flutter frame',
      (tester) async {
    final harness = _Harness();
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    expect(harness.positions.hasListener, isTrue);

    harness.position = 11;
    harness.positions.add(11);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(harness.positions.hasListener, isFalse,
        reason: 'A hidden native window may never produce the next frame');
    await tester.pump();
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(harness.positions.hasListener, isTrue);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('offstage title lyrics catch up from the current media clock',
      (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    await tester.pumpWidget(harness.app(visible: false));
    expect(harness.positions.hasListener, isFalse);
    harness.position = 13;
    harness.positions.add(13);
    await tester.pump();
    expect(find.text('First'), findsOneWidget);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    expect(harness.positions.hasListener, isTrue);
    expect(find.text('Second'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hidden update preference respects paused lifecycle boundary',
      (tester) async {
    final harness = _Harness();
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    harness.preferences.value =
        const RenderingPreferences(pauseWhenHidden: false);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(harness.positions.hasListener, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(harness.positions.hasListener, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(harness.positions.hasListener, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(harness.positions.hasListener, isTrue);
    harness.preferences.value = const RenderingPreferences();
    expect(harness.positions.hasListener, isFalse,
        reason: 'Preference changes also apply without a native redraw');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('secondary touch cancellation cannot release title lyric reading',
      (tester) async {
    final harness = _Harness(longLine: true);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    final controller = _controller(tester);
    final followed = controller.offset;
    final primary =
        await tester.startGesture(tester.getCenter(_scroll), pointer: 101);
    await primary.moveBy(const Offset(-60, 0));
    await tester.pump();
    await primary.moveBy(const Offset(-60, 0));
    await tester.pump();
    final held = controller.offset;
    expect(held, greaterThan(followed + 40));
    final secondary = await tester.startGesture(
        tester.getCenter(_scroll) + const Offset(40, 0),
        pointer: 102);
    await secondary.cancel();
    await tester.pump(LyricMotion.manualScrollGrace);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(held, .1),
        reason: 'The remaining contact still owns manual reading');
    await primary.up();
    await tester.pumpAndSettle();
    await tester.pump(LyricMotion.manualScrollGrace);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(followed, .1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'remaining touch holds title lyrics after the scrolling touch ends',
      (tester) async {
    final harness = _Harness(longLine: true);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    final controller = _controller(tester);
    final followed = controller.offset;
    final primary =
        await tester.startGesture(tester.getCenter(_scroll), pointer: 101);
    await primary.moveBy(const Offset(-60, 0));
    await tester.pump();
    await primary.moveBy(const Offset(-60, 0));
    await tester.pump();
    final held = controller.offset;
    final secondary = await tester.startGesture(
        tester.getCenter(_scroll) + const Offset(40, 0),
        pointer: 102);
    await primary.cancel();
    await tester.pump(LyricMotion.manualScrollGrace);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(held, .1));
    await secondary.up();
    await tester.pumpAndSettle();
    await tester.pump(LyricMotion.manualScrollGrace);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(followed, .1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('trackpad pan holds title lyric reading until its gesture ends',
      (tester) async {
    final harness = _Harness(longLine: true);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    final controller = _controller(tester);
    final followed = controller.offset;
    final trackpad =
        await tester.createGesture(kind: PointerDeviceKind.trackpad);
    final center = tester.getCenter(_scroll);
    await trackpad.panZoomStart(center);
    await trackpad.panZoomUpdate(center, pan: const Offset(-80, 0));
    await tester.pump();
    await trackpad.panZoomUpdate(center, pan: const Offset(-160, 0));
    await tester.pump();
    final held = controller.offset;
    expect(held, greaterThan(followed + 40));
    await tester.pump(LyricMotion.manualScrollGrace);
    expect(controller.offset, closeTo(held, .1));
    await trackpad.panZoomEnd();
    await tester.pumpAndSettle();
    await tester.pump(LyricMotion.manualScrollGrace);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(followed, .1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
