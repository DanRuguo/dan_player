import 'dart:async';
import 'dart:ui' as ui;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/rectangle_progress_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture {
  final positions = StreamController<double>.broadcast(sync: true);
  final seeks = <double>[];
  double length = 120;
  double initialPosition = 12;
  Object identity = ('same.mp3', 1);
  bool enabled = true;
  int taps = 0;
  Color seed = Colors.blue;
  Brightness brightness = Brightness.light;
  bool showButton = false;
  int buttonTaps = 0;
  bool disableAnimations = false;
  ValueChanged<double>? seekOverride;

  Widget app() => MaterialApp(
        theme: ThemeData(
            colorScheme:
                ColorScheme.fromSeed(seedColor: seed, brightness: brightness)),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: disableAnimations),
            child: child!),
        home: Scaffold(
            body: Center(
                child: SizedBox(
          width: 400,
          height: 80,
          child: RepaintBoundary(
              key: const ValueKey('bar-paint'),
              child: RectangleProgressIndicator(
                size: const Size(400, 80),
                positionStream: positions.stream,
                lengthProvider: () => length,
                initialPosition: initialPosition,
                trackIdentity: identity,
                onSeek: enabled ? seekOverride ?? seeks.add : null,
                child: InkWell(
                    onTap: () => taps++,
                    child: Stack(fit: StackFit.expand, children: [
                      const Center(child: Text('song')),
                      if (showButton)
                        Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                                key: const ValueKey('transport'),
                                onPressed: () => buttonTaps++,
                                icon: const Icon(Icons.play_arrow))),
                    ])),
              )),
        ))),
      );
}

RectangleProgressPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<RectangleProgressPainter>()
    .single;

Focus _seekFocus(WidgetTester tester) =>
    tester.widget(find.byKey(const ValueKey('now-playing-seek')));

Future<void> _withBarPixels(
    WidgetTester tester, void Function(int Function(int, int)) verify) async {
  final painter = _painter(tester);
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(400, 80));
    final picture = recorder.endRecording();
    final image = await picture.toImage(400, 80);
    try {
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      verify((x, y) => pixels.getUint32((y * image.width + x) * 4));
    } finally {
      image.dispose();
      picture.dispose();
    }
  });
}

void main() {
  for (final kind in [ui.PointerDeviceKind.mouse, ui.PointerDeviceKind.touch]) {
    testWidgets(
        'release fades the handle within 120ms with $kind focus retained',
        (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.positions.close);
      await tester.pumpWidget(fixture.app());
      final bar = tester.getRect(find.byType(RectangleProgressIndicator));
      final gesture = await tester.createGesture(kind: kind);
      if (kind == ui.PointerDeviceKind.mouse) {
        await gesture.addPointer(location: bar.topLeft + const Offset(40, 40));
        await gesture.moveTo(bar.topLeft + const Offset(41, 40));
      }
      await gesture.down(bar.topLeft + const Offset(40, 40));
      await gesture.moveTo(bar.topLeft + const Offset(300, 40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(_seekFocus(tester).focusNode!.hasPrimaryFocus, isTrue,
          reason: 'pointer release may hide the hint, not break keyboard seek');
      await _withBarPixels(tester, (pixel) {
        for (final y in [1, 8, 30, 40, 50, 72, 78]) {
          expect(pixel(300, y), pixel(310, y),
              reason: 'no persistent handle after release at y=$y');
        }
      });
      expect(fixture.seeks, [90]);
      await gesture.removePointer();
    });
  }

  testWidgets('active handle is a short inset line, not a full-height rule',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final bar = tester.getRect(find.byType(RectangleProgressIndicator));
    final gesture =
        await tester.startGesture(bar.topLeft + const Offset(40, 40));
    await gesture.moveTo(bar.topLeft + const Offset(300, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await _withBarPixels(tester, (pixel) {
      expect(pixel(300, 40), isNot(pixel(310, 40)));
      for (final y in [0, 8, 20, 60, 72, 79]) {
        expect(pixel(300, y), pixel(310, y),
            reason: 'the hint never reaches the top/bottom edges');
      }
    });
    await gesture.cancel();
  });

  testWidgets('keyboard feedback works after the pointer hint has faded',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final bar = tester.getRect(find.byType(RectangleProgressIndicator));
    final gesture =
        await tester.startGesture(bar.topLeft + const Offset(40, 40));
    await gesture.moveTo(bar.topLeft + const Offset(300, 40));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_painter(tester).highlightBoundary!.value, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(AppMotion.quick);
    expect(fixture.seeks, [90, 95]);
    expect(_painter(tester).highlightBoundary!.value, 1);
    _seekFocus(tester).focusNode!.unfocus();
    await tester.pump();
    expect(_seekFocus(tester).focusNode!.hasPrimaryFocus, isFalse);
    // Focus changes are committed after the frame; start the fade's first tick.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_painter(tester).highlightBoundary!.value, 0);
  });

  testWidgets('stationary mouse cannot pin hint; leave and reenter reveals it',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final bar = tester.getRect(find.byType(RectangleProgressIndicator));
    final gesture =
        await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await gesture.addPointer(location: bar.topLeft + const Offset(40, 40));
    await gesture.moveTo(bar.topLeft + const Offset(41, 40));
    await gesture.down(bar.topLeft + const Offset(40, 40));
    await gesture.moveTo(bar.topLeft + const Offset(300, 40));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.moveTo(bar.topLeft + const Offset(301, 40));
    await tester.pump(const Duration(milliseconds: 120));
    expect(_painter(tester).highlightBoundary!.value, 0);
    await gesture.moveTo(bar.topLeft + const Offset(330, 40));
    await gesture.moveTo(bar.topLeft + const Offset(301, 40));
    await tester.pump();
    await tester.pump(AppMotion.quick);
    expect(_painter(tester).highlightBoundary!.value, 1);
    await gesture.removePointer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_painter(tester).highlightBoundary!.value, 0);
  });

  testWidgets('reduced motion removes the drag hint immediately on release',
      (tester) async {
    final fixture = _Fixture()..disableAnimations = true;
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final bar = tester.getRect(find.byType(RectangleProgressIndicator));
    final gesture =
        await tester.startGesture(bar.topLeft + const Offset(40, 40));
    await gesture.moveTo(bar.topLeft + const Offset(300, 40));
    expect(_painter(tester).highlightBoundary!.value, 1);
    await gesture.up();
    expect(_painter(tester).highlightBoundary!.value, 0);
    await tester.pump();
  });

  testWidgets('stationary hover stops highlighting when playback moves away',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final bar = tester.getRect(find.byType(RectangleProgressIndicator));
    final gesture =
        await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await gesture.addPointer(location: bar.topLeft + const Offset(40, 40));
    await gesture.moveTo(bar.topLeft + const Offset(41, 40));
    await tester.pump();
    await tester.pump(AppMotion.quick);
    expect(_painter(tester).highlightBoundary!.value, 1);
    fixture.positions.add(60);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_painter(tester).highlightBoundary!.value, 0);
    expect(fixture.seeks, isEmpty);
    await gesture.removePointer();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'handle is a crisp solid line without a raised outline in $brightness',
        (tester) async {
      final fixture = _Fixture()..brightness = brightness;
      addTearDown(fixture.positions.close);
      await tester.pumpWidget(fixture.app());
      final bar = tester.getRect(find.byType(RectangleProgressIndicator));
      final gesture =
          await tester.startGesture(bar.topLeft + const Offset(40, 40));
      await gesture.moveTo(bar.topLeft + const Offset(300, 40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await _withBarPixels(tester, (pixel) {
        int contrast(int y) {
          final active = pixel(300, y);
          final background = pixel(310, y);
          return [0, 8, 16, 24]
              .map((shift) =>
                  (((active >> shift) & 255) - ((background >> shift) & 255))
                      .abs())
              .reduce((a, b) => a + b);
        }

        expect(contrast(20), 0);
        expect(contrast(60), 0);
        expect(contrast(25), lessThan(contrast(30)));
        expect(contrast(30), contrast(40),
            reason: 'the handle is solid, not a blurred alpha gradient');
        expect(contrast(55), lessThan(contrast(50)));
        expect(contrast(50), contrast(40));
        expect(pixel(300, 40) & 255, 255,
            reason: 'fully shown handle has an opaque, crisp core');
        for (final y in [30, 35, 40, 45, 50]) {
          expect(pixel(298, y), pixel(290, y),
              reason: 'no halo or bulge on the filled side');
          expect(pixel(301, y), pixel(310, y),
              reason: 'no halo or bulge on the unfilled side');
        }
        expect(pixel(300, 36), pixel(300, 40));
        expect(pixel(300, 44), pixel(300, 40),
            reason: 'a uniform hairline, not a spindle-shaped capsule');
      });
      await gesture.cancel();
    });
  }

  testWidgets('failed seek releases drag and hint; the next drag still works',
      (tester) async {
    final fixture = _Fixture()
      ..seekOverride = (_) => throw StateError('isolated seek failure');
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final bar = tester.getRect(find.byType(RectangleProgressIndicator));
    var gesture = await tester.startGesture(bar.topLeft + const Offset(40, 40));
    await gesture.moveTo(bar.topLeft + const Offset(300, 40));
    await gesture.up();
    expect(tester.takeException(), isA<StateError>());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_painter(tester).highlightBoundary!.value, 0);
    expect(_painter(tester).progress.value, .1);
    fixture.seekOverride = null;
    await tester.pumpWidget(fixture.app());
    gesture = await tester.startGesture(bar.topLeft + const Offset(40, 40));
    await gesture.moveTo(bar.topLeft + const Offset(200, 40));
    await gesture.up();
    expect(fixture.seeks, [60]);
  });

  testWidgets('disposing while hint fades releases its ticker and stream',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final bar = tester.getRect(find.byType(RectangleProgressIndicator));
    final gesture =
        await tester.startGesture(bar.topLeft + const Offset(40, 40));
    await gesture.moveTo(bar.topLeft + const Offset(300, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    expect(fixture.positions.hasListener, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag previews without seeking every frame or opening details',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final rect = tester.getRect(find.byType(RectangleProgressIndicator));
    final gesture =
        await tester.startGesture(rect.topLeft + const Offset(40, 30));
    await gesture.moveBy(const Offset(260, 0));
    await tester.pump();
    expect(_painter(tester).progress.value, closeTo(.75, .01));
    fixture.positions.add(18);
    expect(_painter(tester).progress.value, closeTo(.75, .01));
    expect(fixture.seeks, isEmpty);
    await gesture.up();
    expect(fixture.seeks, hasLength(1));
    expect(find.byType(Slider), findsNothing,
        reason: 'drag the existing colour boundary, no extra bottom slider');
    expect(fixture.seeks.single, closeTo(90, .1));
    expect(fixture.taps, 0);
    await tester.tapAt(rect.topLeft + const Offset(100, 30));
    expect(fixture.taps, 1);
    expect(fixture.seeks, hasLength(1));
  });

  testWidgets('cancel restores the newest native position, not drag preview',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final rect = tester.getRect(find.byType(RectangleProgressIndicator));
    final gesture =
        await tester.startGesture(rect.topLeft + const Offset(40, 30));
    await gesture.moveBy(const Offset(260, 0));
    fixture.positions.add(24);
    await gesture.cancel();
    expect(_painter(tester).progress.value, .2);
    expect(fixture.seeks, isEmpty);
  });

  for (final change in [
    'different-track',
    'same-track-new-session',
    'buffering',
    'unknown-length'
  ]) {
    testWidgets('$change invalidates a captured boundary drag', (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.positions.close);
      await tester.pumpWidget(fixture.app());
      final rect = tester.getRect(find.byType(RectangleProgressIndicator));
      final gesture =
          await tester.startGesture(rect.topLeft + const Offset(40, 30));
      await gesture.moveBy(const Offset(280, 0));
      await tester.pump();
      expect(_painter(tester).progress.value, .8);
      switch (change) {
        case 'different-track':
          fixture.identity = ('second.mp3', 2);
        case 'same-track-new-session':
          fixture.identity = ('same.mp3', 2);
        case 'buffering':
          fixture.enabled = false;
        case 'unknown-length':
          fixture.length = 0;
      }
      fixture.initialPosition = 0;
      await tester.pumpWidget(fixture.app());
      await gesture.moveBy(const Offset(10, 0));
      await gesture.up();
      expect(fixture.seeks, isEmpty);
      expect(_painter(tester).progress.value, inInclusiveRange(0, 1));
    });
  }

  testWidgets(
      'keyboard adjusts the same paused fill, without a second progress widget',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    _seekFocus(tester).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    expect(fixture.seeks, [17, 12, 120, 0]);
    expect(_painter(tester).progress.value, 0);
  });

  testWidgets('invalid positions and lengths cannot paint NaN or enable seek',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    for (final length in [0.0, -1.0, double.nan, double.infinity]) {
      fixture.length = length;
      await tester.pumpWidget(fixture.app());
      for (final position in [
        double.nan,
        double.infinity,
        -double.infinity,
        -1.0,
        999.0
      ]) {
        fixture.positions.add(position);
        expect(_painter(tester).progress.value, 0);
      }
      expect(_seekFocus(tester).canRequestFocus, isFalse);
    }
    expect(fixture.seeks, isEmpty);
  });

  testWidgets('accessibility changes share the fill and preserve child actions',
      (tester) async {
    final fixture = _Fixture()..showButton = true;
    addTearDown(fixture.positions.close);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(fixture.app());
    final node = tester
        .getSemantics(find.byKey(const ValueKey('now-playing-seek-semantics')));
    expect(node.getSemanticsData().hasAction(SemanticsAction.increase), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.increase);
    await tester.pump();
    expect(fixture.seeks.single, closeTo(17, 1e-9));
    expect(node.getSemanticsData().value, '14%');
    await tester.tap(find.byKey(const ValueKey('transport')));
    expect(fixture.buttonTaps, 1);
    expect(fixture.taps, 0);
    semantics.dispose();
  });

  testWidgets(
      'boundary never blocks transport taps, but is draggable over them',
      (tester) async {
    final fixture = _Fixture()..showButton = true;
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final bar = tester.getRect(find.byType(RectangleProgressIndicator));
    final button = tester.getCenter(find.byKey(const ValueKey('transport')));
    fixture.positions.add((button.dx - bar.left) / bar.width * fixture.length);
    await tester.pump();
    await tester.tapAt(button);
    expect(fixture.buttonTaps, 1);
    expect(fixture.taps, 0);
    expect(fixture.seeks, isEmpty);
    final gesture = await tester.startGesture(button);
    await gesture.moveTo(bar.topLeft + const Offset(200, 40));
    await gesture.up();
    expect(fixture.seeks.single, 60);
    expect(fixture.buttonTaps, 1);
    expect(fixture.taps, 0);
  });

  for (final atBoundary in [false, true]) {
    testWidgets('mouse click jitter keeps transport tap, boundary=$atBoundary',
        (tester) async {
      final fixture = _Fixture()..showButton = true;
      addTearDown(fixture.positions.close);
      await tester.pumpWidget(fixture.app());
      final bar = tester.getRect(find.byType(RectangleProgressIndicator));
      final button = tester.getCenter(find.byKey(const ValueKey('transport')));
      if (atBoundary) {
        fixture.positions
            .add((button.dx - bar.left) / bar.width * fixture.length);
        await tester.pump();
      }
      final gesture =
          await tester.startGesture(button, kind: ui.PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(3, 0));
      await gesture.up();
      expect(fixture.buttonTaps, 1);
      expect(fixture.seeks, isEmpty);
      expect(fixture.taps, 0);
    });
  }

  testWidgets('mouse can still drag the boundary after passing tap tolerance',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final bar = tester.getRect(find.byType(RectangleProgressIndicator));
    final gesture = await tester.startGesture(
        bar.topLeft + const Offset(40, 30),
        kind: ui.PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(200, 0));
    expect(fixture.seeks, isEmpty);
    await gesture.up();
    expect(fixture.seeks, [72]);
    expect(fixture.taps, 0);
  });

  for (final fraction in [0.0, 1.0]) {
    testWidgets('boundary at $fraction stays draggable within bar bounds',
        (tester) async {
      final fixture = _Fixture()..initialPosition = 120 * fraction;
      addTearDown(fixture.positions.close);
      await tester.pumpWidget(fixture.app());
      final bar = tester.getRect(find.byType(RectangleProgressIndicator));
      final gesture = await tester
          .startGesture(bar.topLeft + Offset(fraction == 0 ? 2 : 398, 30));
      await gesture.moveTo(bar.center);
      await gesture.up();
      expect(fixture.seeks, [60]);
    });
  }

  testWidgets('dragging away from the boundary does not accidentally seek',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final bar = tester.getRect(find.byType(RectangleProgressIndicator));
    final gesture =
        await tester.startGesture(bar.topLeft + const Offset(160, 30));
    await gesture.moveBy(const Offset(100, 0));
    await gesture.up();
    expect(fixture.seeks, isEmpty);
    expect(fixture.taps, 0);
    expect(_painter(tester).progress.value, .1);
  });

  testWidgets('the full-height colour fill has no separate bottom track',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('bar-paint')));
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      int pixel(int x, int y) => pixels.getUint32((y * image.width + x) * 4);
      for (final x in [18, 30, 60, 200, 360]) {
        expect(pixel(x, 12), pixel(x, 74),
            reason: 'same filled/unfilled material from top to bottom at x=$x');
      }
      expect(pixel(30, 12), isNot(pixel(60, 12)),
          reason: 'existing vertical progress boundary remains visible');
      image.dispose();
    });
  });

  testWidgets(
      'paused progress repaints immediately for cover-derived theme changes',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.positions.close);
    await tester.pumpWidget(fixture.app());
    final oldPainter = _painter(tester);
    fixture.seed = Colors.red;
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    expect(_painter(tester).shouldRepaint(oldPainter), isTrue);
    expect(_painter(tester).progress.value, .1);
  });

  testWidgets(
      'switching streams releases old subscriptions and ignores old ticks',
      (tester) async {
    final first = _Fixture();
    final second = _Fixture()..initialPosition = 60;
    addTearDown(first.positions.close);
    addTearDown(second.positions.close);
    await tester.pumpWidget(first.app());
    expect(first.positions.hasListener, isTrue);
    await tester.pumpWidget(second.app());
    expect(first.positions.hasListener, isFalse);
    first.positions.add(120);
    expect(_painter(tester).progress.value, .5);
    await tester.pumpWidget(const SizedBox());
    expect(second.positions.hasListener, isFalse);
  });
}
