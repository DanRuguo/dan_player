import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Lyric extends Lyric {
  _Lyric(super.lines);
}

class _Word extends SyncLyricWord {
  _Word(int startMs, int lengthMs, String text)
      : super(Duration(milliseconds: startMs), Duration(milliseconds: lengthMs),
            text);
}

class _SyncLine extends SyncLyricLine {
  _SyncLine(int startMs, int lengthMs, List<SyncLyricWord> words,
      [String? translation])
      : super(Duration(milliseconds: startMs), Duration(milliseconds: lengthMs),
            words, translation);
}

Lyric _plainLyric([int count = 12]) => _Lyric([
      for (var index = 0; index < count; index++)
        LrcLine(Duration(seconds: index * 5), 'Line $index',
            isBlank: false, length: const Duration(seconds: 5)),
    ]);

class _Harness {
  _Harness({Lyric? lyric, this.position = 0}) {
    future = Future.value(lyric ?? _plainLyric());
    settings.lyricFontSize = 22;
    settings.translationFontSize = 18;
    settings.lyricTextAlign = LyricTextAlign.left;
    addTearDown(() async {
      await positions.close();
      settings.dispose();
    });
  }

  final positions = StreamController<double>.broadcast();
  final settings = LyricViewController();
  late Future<Lyric?> future;
  double position;
  bool failSeek = false;
  final seekRequests = <double>[];

  void seek(double value) {
    seekRequests.add(value);
    if (failSeek) throw StateError('fixture seek rejected');
    emit(value);
  }

  void emit(double value) {
    position = value;
    positions.add(value);
  }

  Widget content() => ChangeNotifierProvider.value(
        value: settings,
        child: VerticalLyricContent(
          lyricFuture: future,
          positionStream: positions.stream,
          readPosition: () => position,
          onSeek: seek,
        ),
      );
}

Widget _app(_Harness harness,
        {bool reduced = false,
        bool tickerEnabled = true,
        double textScale = 1,
        double width = 420,
        double height = 480,
        bool highContrast = false,
        Widget? body}) =>
    MaterialApp(
      theme: ThemeData(
        platform: TargetPlatform.windows,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduced,
          textScaler: TextScaler.linear(textScale),
          highContrast: highContrast,
        ),
        child: TickerMode(enabled: tickerEnabled, child: child!),
      ),
      home: Scaffold(
        body: body ??
            Center(
              child: SizedBox(
                width: width,
                height: height,
                child: harness.content(),
              ),
            ),
      ),
    );

Finder _row(int index) => find.byType(LyricViewTile).at(index);
Finder _motion(int index) =>
    find.descendant(of: _row(index), matching: find.byType(LyricLineMotion));
Finder _scroll() => find.byKey(const ValueKey('vertical-lyric-scroll'));
ScrollController _controller(WidgetTester tester) =>
    tester.widget<CustomScrollView>(_scroll()).controller!;
double _opacity(WidgetTester tester, int index) => tester
    .widget<Opacity>(find
        .descendant(of: _motion(index), matching: find.byType(Opacity))
        .first)
    .opacity;
double _scale(WidgetTester tester, int index) => tester
    .widget<Transform>(find
        .descendant(of: _motion(index), matching: find.byType(Transform))
        .first)
    .transform
    .storage[0];
int _active(WidgetTester tester) => tester
    .widgetList<LyricViewTile>(find.byType(LyricViewTile))
    .toList()
    .indexWhere((row) => row.distance == 0);
LyricWordHighlightPainter _wordPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<LyricWordHighlightPainter>()
    .firstWhere((painter) => painter.active);

Future<void> _mount(WidgetTester tester, _Harness harness,
    {bool reduced = false}) async {
  expect(PlayService.isInitialized, isFalse);
  await tester.pumpWidget(_app(harness, reduced: reduced));
  await tester.pumpAndSettle();
}

Future<void> _wheel(WidgetTester tester, double delta) async {
  await tester.sendEventToBinding(PointerScrollEvent(
    position: tester.getCenter(_scroll()),
    scrollDelta: Offset(0, delta),
  ));
  await tester.pump();
}

void main() {
  testWidgets('focused text is larger, extra-bold and distinct from context',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    final focused = tester.widget<Text>(find.text('Line 0')).style!;
    final contextStyle = tester.widget<Text>(find.text('Line 1')).style!;
    expect(focused.fontWeight, FontWeight.w800);
    expect(focused.fontSize, closeTo(22 * 1.12, .000001));
    final focusedSize = focused.fontSize! * _scale(tester, 0);
    final contextSize = contextStyle.fontSize! * _scale(tester, 1);
    expect(focusedSize / contextSize, greaterThan(1.13));
    expect(_opacity(tester, 0) / _opacity(tester, 1), greaterThan(2));
    expect(_opacity(tester, 1), greaterThan(_opacity(tester, 3)));
    expect(_opacity(tester, 3), greaterThan(_opacity(tester, 5)));
  });

  testWidgets('scroll travels quickly then decelerates into the next line',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    final start = _controller(tester).offset;
    final distance = tester.getSize(_row(0)).height;
    harness.emit(5.1);
    // Deliver the asynchronous sample, run its post-frame follow request, then
    // prime the DrivenScrollActivity ticker before measuring elapsed travel.
    await tester.pump();
    await tester.pump();
    await tester.pump();
    var previous = start;
    final intervals = <double>[];
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 155));
      final current = _controller(tester).offset;
      intervals.add(current - previous);
      expect(current, inInclusiveRange(start, start + distance + .001));
      previous = current;
    }
    expect(intervals.first / distance, greaterThan(.65));
    expect(intervals[0], greaterThan(intervals[1]));
    expect(intervals[1], greaterThan(intervals[2]));
    expect(intervals[2], greaterThan(intervals[3]));
    expect(previous - start, closeTo(distance, .001));
    // Flutter's interpolation simulation reports done strictly after duration,
    // not at equality. Keep the exact endpoint assertion above, then verify
    // the next vsync ends the activity without another positional step.
    await tester.pump(const Duration(milliseconds: 16));
    expect(_controller(tester).offset, closeTo(previous, .001));
    expect(_controller(tester).position.isScrollingNotifier.value, isFalse);
  });

  testWidgets('touch can stop the fast scroll and retain manual control',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    harness.emit(5.1);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final gesture = await tester.startGesture(tester.getCenter(_scroll()));
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    final held = _controller(tester).offset;
    harness.emit(30);
    await tester.pump(const Duration(seconds: 1));
    expect(_controller(tester).offset, held);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_active(tester), 6);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shrunk context line keeps a full unscaled edge touch target',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    final contextRow = _row(3);
    final ink = find.descendant(of: contextRow, matching: find.byType(InkWell));
    final rect = tester.getRect(ink);
    expect(rect.height, greaterThanOrEqualTo(48));
    expect(rect.width, tester.getSize(contextRow).width);
    // Top/right lies outside the shrunken text transform, but inside the row.
    await tester.tapAt(Offset(rect.right - 2, rect.top + 2));
    await tester.pumpAndSettle();
    expect(harness.seekRequests, [15]);
    expect(_active(tester), 3);
  });

  for (final alignment in LyricTextAlign.values) {
    testWidgets('large lyrics wrap without clipping at 200%, $alignment',
        (tester) async {
      final lyric = _Lyric([
        LrcLine(Duration.zero, '前一句', isBlank: false),
        LrcLine(const Duration(seconds: 5),
            '很长的原文mixed long words ' * 3 + '┃翻译也必须保留并自动换行。' * 3,
            isBlank: false),
        LrcLine(const Duration(seconds: 10), '后一句', isBlank: false),
      ]);
      final harness = _Harness(lyric: lyric)
        ..settings.lyricFontSize = 36
        ..settings.translationFontSize = 28
        ..settings.lyricTextAlign = alignment;
      await tester
          .pumpWidget(_app(harness, width: 200, height: 300, textScale: 2));
      await tester.pumpAndSettle();
      final rowSize = tester.getSize(_row(1));
      final paragraphs =
          find.descendant(of: _row(1), matching: find.byType(RichText));
      for (final paragraph
          in tester.renderObjectList<RenderParagraph>(paragraphs)) {
        expect(paragraph.didExceedMaxLines, isFalse);
        final plain = paragraph.text.toPlainText();
        for (var index = 0; index < plain.length; index++) {
          // A selection includes unpainted line-end whitespace beyond the
          // paragraph. Check actual glyph boxes rather than those caret areas.
          if (plain[index].trim().isEmpty) continue;
          final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: index, extentOffset: index + 1));
          for (final box in boxes) {
            final reason = 'glyph ${plain[index]} at $index, $alignment';
            expect(box.left, greaterThanOrEqualTo(-.01), reason: reason);
            expect(box.right, lessThanOrEqualTo(paragraph.size.width + .01),
                reason: reason);
            expect(box.bottom, lessThanOrEqualTo(paragraph.size.height + .01),
                reason: reason);
          }
        }
      }
      harness.emit(6);
      await tester.pumpAndSettle();
      expect(tester.getSize(_row(1)), rowSize);
      expect(tester.getTopLeft(_row(1)).dy,
          closeTo(tester.getTopLeft(_scroll()).dy, .5));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('initial timed line uses actual nonzero position before any tick',
      (tester) async {
    final harness = _Harness(
      position: 6,
      lyric: _Lyric([
        LrcLine(Duration.zero, 'First', isBlank: false),
        _SyncLine(5000, 4000,
            [_Word(5000, 2000, 'Hello '), _Word(7000, 2000, 'world')], '译文'),
        LrcLine(const Duration(seconds: 10), 'Last', isBlank: false),
      ]),
    );
    await _mount(tester, harness);
    expect(_active(tester), 1);
    final painter = _wordPainter(tester);
    expect(painter.position, const Duration(seconds: 6));
    expect(painter.progressForWord(0), .5);
    expect(painter.progressForWord(1), 0);
    expect(find.text('译文'), findsOneWidget);
    expect(_controller(tester).offset, greaterThan(0));
  });

  testWidgets('real rows retain State and interpolate both sides of a handoff',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    final firstState = tester.state(_motion(0));
    final nextState = tester.state(_motion(1));
    final sizes = [tester.getSize(_row(0)), tester.getSize(_row(1))];
    harness.emit(5.1);
    await tester.pump();
    expect(tester.state(_motion(0)), same(firstState));
    expect(tester.state(_motion(1)), same(nextState));
    expect(_opacity(tester, 0), 1);
    expect(_opacity(tester, 1), .46);
    var lastOldOpacity = 1.0;
    var lastNewOpacity = .46;
    var lastNewScale = .88;
    for (var frame = 0; frame < 14; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
      final oldOpacity = _opacity(tester, 0);
      final newOpacity = _opacity(tester, 1);
      final newScale = _scale(tester, 1);
      expect(oldOpacity, inInclusiveRange(.46, lastOldOpacity + .000001));
      expect(newOpacity, inInclusiveRange(lastNewOpacity - .000001, 1));
      expect(newScale, inInclusiveRange(lastNewScale - .000001, 1));
      lastOldOpacity = oldOpacity;
      lastNewOpacity = newOpacity;
      lastNewScale = newScale;
      expect(tester.getSize(_row(0)), sizes[0]);
      expect(tester.getSize(_row(1)), sizes[1]);
    }
    expect(lastOldOpacity, .46);
    expect(lastNewOpacity, 1);
    expect(lastNewScale, 1);
  });

  testWidgets('interrupted cross-line seek starts at the painted values',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    harness.emit(5.1);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    final beforeOpacity = _opacity(tester, 1);
    final beforeScale = _scale(tester, 1);
    expect(beforeOpacity, inExclusiveRange(.46, 1));
    harness.emit(21.0);
    await tester.pump();
    expect(_opacity(tester, 1), closeTo(beforeOpacity, .000001));
    expect(_scale(tester, 1), closeTo(beforeScale, .000001));
    for (var frame = 0; frame < 16; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
      for (var row = 0; row < 6; row++) {
        expect(_scale(tester, row), inInclusiveRange(.84, 1));
        expect(_opacity(tester, row), inInclusiveRange(.16, 1));
      }
    }
    expect(_active(tester), 4);
    final expectedTop = tester.getTopLeft(_scroll()).dy +
        (tester.getSize(_scroll()).height - tester.getSize(_row(4)).height) *
            .25;
    expect(tester.getTopLeft(_row(4)).dy, closeTo(expectedTop, .5));
  });

  testWidgets('same-line samples do not rebuild rows or restart transitions',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    harness.emit(5.05);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final before =
        tester.widgetList<LyricViewTile>(find.byType(LyricViewTile)).toList();
    final opacity = _opacity(tester, 1);
    for (var sample = 1; sample <= 10; sample++) {
      harness.emit(5.05 + sample * .033);
      await tester.pump(const Duration(milliseconds: 33));
    }
    final after =
        tester.widgetList<LyricViewTile>(find.byType(LyricViewTile)).toList();
    for (var index = 0; index < before.length; index++) {
      expect(after[index], same(before[index]));
    }
    expect(_opacity(tester, 1), greaterThan(opacity));
  });

  testWidgets('latest of several seeks owns the scroll target', (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    harness.emit(40);
    harness.emit(10);
    harness.emit(25);
    await tester.pumpAndSettle();
    expect(_active(tester), 5);
    final top = tester.getTopLeft(_row(5)).dy;
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getTopLeft(_row(5)).dy, top);
    expect(tester.takeException(), isNull);
  });

  testWidgets('automatic following moves monotonically without overshoot',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    var previous = _controller(tester).offset;
    final start = previous;
    harness.emit(5.1);
    await tester.pump();
    for (var frame = 0; frame < 17; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
      final current = _controller(tester).offset;
      expect(current, greaterThanOrEqualTo(previous - .000001));
      previous = current;
    }
    expect(previous, greaterThan(start));
    expect(previous - start, closeTo(tester.getSize(_row(0)).height, .5));
  });

  testWidgets('mouse wheel suppresses following until the four-second grace',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    await _wheel(tester, 180);
    final manualOffset = _controller(tester).offset;
    harness.emit(35);
    await tester.pump(const Duration(seconds: 3));
    expect(_controller(tester).offset, manualOffset);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect((_controller(tester).offset - manualOffset).abs(), greaterThan(20));
    expect(_active(tester), 7);
  });

  testWidgets('a held touch drag never times out beneath the finger',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    final gesture = await tester.startGesture(tester.getCenter(_scroll()));
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();
    final heldOffset = _controller(tester).offset;
    harness.emit(40);
    await tester.pump(const Duration(seconds: 5));
    expect(_controller(tester).offset, heldOffset);
    await gesture.up();
    await tester.pumpAndSettle();
    final releasedOffset = _controller(tester).offset;
    await tester.pump(const Duration(seconds: 3));
    expect(_controller(tester).offset, releasedOffset);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect(
        (_controller(tester).offset - releasedOffset).abs(), greaterThan(20));
  });

  testWidgets('click seek releases manual protection and uses actual position',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    await _wheel(tester, 60);
    await tester.tap(find.text('Line 3'));
    await tester.pumpAndSettle();
    expect(harness.seekRequests, [15]);
    expect(_active(tester), 3);
  });

  testWidgets('failed click seek keeps the old timeline and reports the error',
      (tester) async {
    final harness = _Harness()..failSeek = true;
    await _mount(tester, harness);
    await tester.tap(find.text('Line 2'));
    await tester.pump();
    expect(_active(tester), 0);
    expect(find.textContaining('无法跳转到该歌词'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion immediately settles focus and local scrolling',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness, reduced: true);
    harness.emit(20);
    await tester.pump();
    await tester.pump();
    expect(_active(tester), 4);
    expect(_opacity(tester, 4), 1);
    expect(_opacity(tester, 0), .16);
    expect(_scale(tester, 4), 1);
    expect(_scale(tester, 0), 1);
    expect(_controller(tester).position.isScrollingNotifier.value, isFalse);
  });

  testWidgets('live reduced motion finishes an already-running transition',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    harness.emit(5.1);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_opacity(tester, 1), inExclusiveRange(.46, 1));
    await tester.pumpWidget(_app(harness, reduced: true));
    await tester.pump();
    expect(_opacity(tester, 1), 1);
    expect(_opacity(tester, 0), .46);
    expect(_scale(tester, 0), 1);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(_app(harness));
    await tester.pump();
    expect(_opacity(tester, 1), 1);
  });

  for (final feature in ['disableAnimations', 'reduceMotion']) {
    testWidgets('live platform $feature overrides a custom MediaQuery',
        (tester) async {
      final harness = _Harness();
      await _mount(tester, harness);
      harness.emit(5.1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(
        disableAnimations: feature == 'disableAnimations',
        reduceMotion: feature == 'reduceMotion',
      );
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pump();
      await tester.pump();
      expect(_opacity(tester, 1), 1);
      expect(_scale(tester, 0), 1);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets('inactive ticker scope has no unfinished lyric animation',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    harness.emit(5.1);
    await tester.pump();
    await tester.pumpWidget(_app(harness, tickerEnabled: false));
    await tester.pump();
    expect(_opacity(tester, 1), 1);
    expect(_scale(tester, 0), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('timed wrapping and translations retain layout at 200 percent',
      (tester) async {
    final harness = _Harness(
      lyric: _Lyric([
        LrcLine(Duration.zero, 'Before', isBlank: false),
        _SyncLine(
            5000,
            5000,
            [
              _Word(5000, 5000, 'averylongwordwithoutbreaks汉字混合文字' * 3),
            ],
            '很长的翻译文字，需要正常换行并保持整句完整。' * 4),
        LrcLine(const Duration(seconds: 10), 'After', isBlank: false),
      ]),
    );
    await tester.pumpWidget(_app(harness, textScale: 2, width: 250));
    await tester.pumpAndSettle();
    final size = tester.getSize(_row(1));
    final beforeElement = tester.element(_motion(1));
    harness.emit(7.5);
    await tester.pump();
    for (var frame = 0; frame < 14; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.getSize(_row(1)), size);
      expect(tester.element(_motion(1)), same(beforeElement));
    }
    expect(_wordPainter(tester).progressForWord(0), .5);
    harness.emit(10.1);
    await tester.pumpAndSettle();
    expect(tester.getSize(_row(1)), size);
    expect(tester.takeException(), isNull);
  });

  testWidgets('interlude space is stable and a paused interlude has no ticker',
      (tester) async {
    final harness = _Harness(
        lyric: _Lyric([
      LrcLine(Duration.zero, 'Before', isBlank: false),
      LrcLine(const Duration(seconds: 5), '',
          isBlank: true, length: const Duration(seconds: 8)),
      LrcLine(const Duration(seconds: 13), 'After', isBlank: false),
    ]));
    await _mount(tester, harness);
    final height = tester.getSize(_row(1)).height;
    expect(height, greaterThanOrEqualTo(44));
    harness.emit(7);
    await tester.pumpAndSettle();
    expect(tester.getSize(_row(1)).height, height);
    expect(find.byType(LyricTransitionTile), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.transientCallbackCount, 0);
    harness.emit(14);
    await tester.pumpAndSettle();
    expect(tester.getSize(_row(1)).height, height);
  });

  testWidgets('line-timed LRC does not invent a word sweep', (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    expect(find.byType(ShaderMask), findsNothing);
    expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .where((widget) => widget.painter is LyricWordHighlightPainter),
        isEmpty);
    final color = tester.widget<Text>(find.text('Line 0')).style!.color;
    harness.emit(2.5);
    await tester.pump();
    expect(tester.widget<Text>(find.text('Line 0')).style!.color, color);
  });

  testWidgets('old lyric futures cannot restore stale rows or failures',
      (tester) async {
    final harness = _Harness();
    final old = Completer<Lyric?>();
    final current = Completer<Lyric?>();
    harness.future = old.future;
    await tester.pumpWidget(_app(harness, reduced: true));
    harness.future = current.future;
    await tester.pumpWidget(_app(harness, reduced: true));
    current.complete(_plainLyric(2));
    await tester.pumpAndSettle();
    old.completeError(StateError('old source failed'));
    await tester.pumpAndSettle();
    expect(find.byType(LyricViewTile), findsNWidgets(2));
    expect(find.textContaining('歌词加载失败'), findsNothing);
    harness.future = Future.value(null);
    await tester.pumpWidget(_app(harness, reduced: true));
    expect(find.byType(LyricViewTile), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('无歌词'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a current source error is readable and never opens a player',
      (tester) async {
    final harness = _Harness();
    final source = Completer<Lyric?>();
    harness.future = source.future;
    await tester.pumpWidget(_app(harness, reduced: true));
    source.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('歌词加载失败'), findsOneWidget);
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets('replacing the position stream detaches old updates',
      (tester) async {
    final first = _Harness();
    final second = _Harness(position: 15)..future = first.future;
    await _mount(tester, first);
    await tester.pumpWidget(_app(second));
    await tester.pumpAndSettle();
    expect(_active(tester), 3);
    first.emit(40);
    await tester.pumpAndSettle();
    expect(_active(tester), 3);
    expect(first.positions.hasListener, isFalse);
    expect(second.positions.hasListener, isTrue);
  });

  testWidgets('dispose cancels subscriptions, follow frames and manual timer',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    harness.emit(20);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await _wheel(tester, 80);
    await tester.pumpWidget(const SizedBox.shrink());
    harness.emit(30);
    await tester.pump(const Duration(seconds: 8));
    expect(harness.positions.hasListener, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('following never scrolls an ancestor viewport', (tester) async {
    final harness = _Harness();
    final outer = ScrollController();
    addTearDown(outer.dispose);
    await tester.pumpWidget(_app(harness,
        body: SingleChildScrollView(
          controller: outer,
          child: Column(children: [
            const SizedBox(height: 80),
            SizedBox(height: 350, width: 420, child: harness.content()),
            const SizedBox(height: 1000),
          ]),
        )));
    await tester.pumpAndSettle();
    outer.jumpTo(50);
    final oldOffset = outer.offset;
    harness.emit(40);
    await tester.pumpAndSettle();
    expect(outer.offset, oldOffset);
    expect(_active(tester), 8);
  });

  testWidgets('two independent lyric surfaces do not share a GlobalKey',
      (tester) async {
    final first = _Harness();
    final second = _Harness(position: 10);
    await tester.pumpWidget(_app(first,
        body: Row(children: [
          Expanded(child: first.content()),
          Expanded(child: second.content()),
        ])));
    await tester.pumpAndSettle();
    expect(find.byType(VerticalLyricScrollView), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('high contrast keeps context readable and semantics complete',
      (tester) async {
    final harness = _Harness(
        lyric: _Lyric([
      LrcLine(Duration.zero, '原文┃翻译', isBlank: false),
      ..._plainLyric(6).lines.skip(1),
    ]));
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(harness, highContrast: true, reduced: true));
    await tester.pumpAndSettle();
    for (var index = 0; index < 6; index++) {
      expect(_opacity(tester, index), 1);
      expect(tester.getSize(_row(index)).height, greaterThanOrEqualTo(44));
    }
    final semantics = tester.getSemantics(_row(0));
    expect(semantics.label, '原文\n翻译');
    expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  for (final offset in [500, -500]) {
    testWidgets('offset $offset is applied once before selection and seeking',
        (tester) async {
      final lyric = Lrc.fromLrcText(
        '[offset:$offset]\n[00:05.00]First\n[00:10.00]Second',
        LrcSource.local,
      )!;
      final adjustedSecond = 10 - offset / 1000;
      final harness = _Harness(lyric: lyric, position: adjustedSecond + .01);
      await _mount(tester, harness, reduced: true);
      expect(_active(tester), 1);
      await tester.tap(find.text('First'));
      await tester.pumpAndSettle();
      expect(harness.seekRequests, [5 - offset / 1000]);
      expect(_active(tester), 0);
    });
  }
}
