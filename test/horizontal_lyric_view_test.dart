import 'dart:async';

import 'package:dan_player/component/horizontal_lyric_view.dart';
import 'package:dan_player/component/title_bar.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Lyric extends Lyric {
  _Lyric(super.lines);
}

class _Harness {
  _Harness({Lyric? lyric, this.position = 0}) {
    future = Future.value(lyric ?? _fixtureLyric());
    addTearDown(positions.close);
  }

  final positions = StreamController<double>.broadcast();
  late Future<Lyric?> future;
  double position;

  void emit(double value) {
    position = value;
    positions.add(value);
  }
}

Lyric _fixtureLyric() => _Lyric([
      LrcLine(Duration.zero, 'First line',
          isBlank: false, length: const Duration(seconds: 5)),
      LrcLine(const Duration(seconds: 5), 'Second line┃第二句译文',
          isBlank: false, length: const Duration(seconds: 5)),
      LrcLine(const Duration(seconds: 10), 'Third line',
          isBlank: false, length: const Duration(seconds: 5)),
    ]);

Lyric _longLyric({Duration length = const Duration(seconds: 10)}) => _Lyric([
      LrcLine(Duration.zero, 'A long lyric with Chinese 这是完整的长歌词与译文 ' * 8,
          isBlank: false, length: length),
    ]);

Widget _app(_Harness harness,
        {bool reduced = false,
        bool tickerEnabled = true,
        double width = 320,
        double textScale = 1,
        bool highContrast = false}) =>
    MaterialApp(
      theme: ThemeData(
        platform: TargetPlatform.windows,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduced,
          highContrast: highContrast,
          textScaler: TextScaler.linear(textScale),
        ),
        child: TickerMode(enabled: tickerEnabled, child: child!),
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: TitleBarSongRegion(
              key: const ValueKey('test-title-region'),
              child: DecoratedBox(
                key: const ValueKey('test-title-capsule'),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: HorizontalLyricContent(
                  lyricFuture: harness.future,
                  positionStream: harness.positions.stream,
                  readPosition: () => harness.position,
                ),
              ),
            ),
          ),
        ),
      ),
    );

Finder _scroll() => find.byKey(const ValueKey('horizontal-lyric-scroll')).last;
ScrollController _controller(WidgetTester tester) =>
    tester.widget<SingleChildScrollView>(_scroll()).controller!;
Finder _switcher() => find.byKey(const ValueKey('horizontal-lyric-switcher'));

Future<void> _mount(WidgetTester tester, _Harness harness,
    {bool reduced = false}) async {
  expect(PlayService.isInitialized, isFalse);
  await tester.pumpWidget(_app(harness, reduced: reduced));
  await tester.pumpAndSettle();
}

Future<void> _emit(WidgetTester tester, _Harness harness, double value) async {
  harness.emit(value);
  // The real player uses an asynchronous broadcast stream. Drain delivery,
  // then build its requested frame before inspecting animation time zero.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('plain lyric shows a one-line untimed summary without overflow',
      (tester) async {
    final harness = _Harness(
      lyric: PlainLyric('First untimed line\nSecond line\nThird line'),
    );
    await tester.pumpWidget(_app(
      harness,
      width: 180,
      textScale: 2,
      reduced: true,
    ));
    await tester.pumpAndSettle();

    expect(find.text('First untimed line · 无时间轴歌词'), findsOneWidget);
    expect(find.textContaining('Second line'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('title starts at the actual line without waiting for a new tick',
      (tester) async {
    final harness = _Harness(position: 6.5);
    await _mount(tester, harness);
    expect(find.text('Second line┃第二句译文'), findsOneWidget);
    expect(find.text('First line'), findsNothing);
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets('line changes crossfade while capsule geometry stays fixed',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    final region =
        tester.getRect(find.byKey(const ValueKey('test-title-region')));
    final capsule =
        tester.getRect(find.byKey(const ValueKey('test-title-capsule')));
    await _emit(tester, harness, 5.1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('First line'), findsOneWidget);
    expect(find.text('Second line┃第二句译文'), findsOneWidget);
    final fades = tester.widgetList<FadeTransition>(find.descendant(
        of: _switcher(), matching: find.byType(FadeTransition)));
    expect(
        fades.where((fade) => fade.opacity.value > 0 && fade.opacity.value < 1),
        hasLength(2));
    expect(tester.getRect(find.byKey(const ValueKey('test-title-region'))),
        region);
    expect(tester.getRect(find.byKey(const ValueKey('test-title-capsule'))),
        capsule);
    expect(capsule.top - region.top, 8);
    expect(region.bottom - capsule.bottom, 8);
    await tester.pumpAndSettle();
    expect(find.text('First line'), findsNothing);
  });

  testWidgets('same-line samples do not restart the line transition',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    final current = tester.element(find.text('First line'));
    for (var sample = 1; sample < 10; sample++) {
      await _emit(tester, harness, sample * .033);
    }
    expect(tester.element(find.text('First line')), same(current));
    final fade = tester.widget<FadeTransition>(find.descendant(
        of: _switcher(), matching: find.byType(FadeTransition)));
    expect(fade.opacity.value, 1);
  });

  testWidgets('marquee stops at the latest real position when playback pauses',
      (tester) async {
    final harness = _Harness(lyric: _longLyric(), position: 2);
    await _mount(tester, harness);
    final initial = _controller(tester).offset;
    expect(initial, greaterThan(0));
    await _emit(tester, harness, 2.033);
    await tester.pump(const Duration(milliseconds: 100));
    final paused = _controller(tester).offset;
    expect(paused, greaterThan(initial));
    await tester.pump(const Duration(seconds: 3));
    expect(_controller(tester).offset, paused);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('paused same-line backward seek immediately uses actual time',
      (tester) async {
    final harness = _Harness(lyric: _longLyric(), position: 8);
    await _mount(tester, harness);
    final later = _controller(tester).offset;
    await _emit(tester, harness, 2);
    final earlier = _controller(tester).offset;
    expect(earlier, lessThan(later));
    final expected =
        _controller(tester).position.maxScrollExtent * (2 - .3) / 9.4;
    expect(earlier, closeTo(expected, .01));
    expect(_controller(tester).position.isScrollingNotifier.value, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(_controller(tester).offset, earlier);
  });

  testWidgets('quick forward/back seeks cannot revive an outgoing line',
      (tester) async {
    final harness = _Harness();
    await _mount(tester, harness);
    await _emit(tester, harness, 10.1);
    await tester.pump(const Duration(milliseconds: 30));
    await _emit(tester, harness, 0.1);
    await tester.pump(const Duration(milliseconds: 30));
    final oldText = find.text('Third line');
    expect(
        find.ancestor(
            of: oldText,
            matching: find.byWidgetPredicate(
                (widget) => widget is ExcludeSemantics && widget.excluding)),
        findsWidgets);
    await tester.pumpAndSettle();
    expect(find.text('First line'), findsOneWidget);
    expect(find.text('Third line'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source replacement clears old data and ignores a late future',
      (tester) async {
    final harness = _Harness(lyric: _longLyric(), position: 4);
    await _mount(tester, harness);
    final old = Completer<Lyric?>();
    final current = Completer<Lyric?>();
    harness.future = old.future;
    await tester.pumpWidget(_app(harness));
    expect(find.textContaining('A long lyric'), findsNothing);
    harness.future = current.future;
    await tester.pumpWidget(_app(harness));
    current.complete(_Lyric([
      LrcLine(Duration.zero, 'Only new line', isBlank: false),
    ]));
    await tester.pumpAndSettle();
    old.complete(_fixtureLyric());
    await tester.pumpAndSettle();
    await _emit(tester, harness, 60);
    await tester.pumpAndSettle();
    expect(find.text('Only new line'), findsOneWidget);
    expect(find.text('Third line'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old stream is detached when playback input changes',
      (tester) async {
    final first = _Harness();
    final second = _Harness(position: 6)..future = first.future;
    await _mount(tester, first);
    await tester.pumpWidget(_app(second));
    await tester.pumpAndSettle();
    await _emit(tester, first, 12);
    await tester.pumpAndSettle();
    expect(find.text('Second line┃第二句译文'), findsOneWidget);
    expect(first.positions.hasListener, isFalse);
    expect(second.positions.hasListener, isTrue);
  });

  testWidgets('reduced motion uses static text with full tooltip',
      (tester) async {
    final lyric = _longLyric();
    final harness = _Harness(lyric: lyric, position: 7);
    await _mount(tester, harness, reduced: true);
    expect(_switcher(), findsNothing);
    expect(_controller(tester).offset, 0);
    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message,
        (lyric.lines.first as LrcLine).content);
    await _emit(tester, harness, 8);
    expect(_controller(tester).offset, 0);
  });

  for (final feature in ['disableAnimations', 'reduceMotion']) {
    testWidgets('live platform $feature stops marquee and crossfade',
        (tester) async {
      final harness = _Harness(lyric: _longLyric(), position: 4);
      await _mount(tester, harness);
      expect(_controller(tester).offset, greaterThan(0));
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(
        disableAnimations: feature == 'disableAnimations',
        reduceMotion: feature == 'reduceMotion',
      );
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pump();
      await tester.pump();
      expect(_switcher(), findsNothing);
      expect(_controller(tester).offset, 0);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets('inactive ticker scope does not leave paused animations',
      (tester) async {
    final harness = _Harness(lyric: _longLyric(), position: 4);
    await _mount(tester, harness);
    await tester.pumpWidget(_app(harness, tickerEnabled: false));
    await tester.pump();
    expect(_switcher(), findsNothing);
    expect(_controller(tester).offset, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final length in [Duration.zero, const Duration(milliseconds: 400)]) {
    testWidgets(
        'unknown or short duration $length never creates invalid motion',
        (tester) async {
      final harness = _Harness(lyric: _longLyric(length: length), position: 1);
      await _mount(tester, harness);
      await _emit(tester, harness, 5);
      await tester.pumpAndSettle();
      expect(_controller(tester).offset, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('narrow 200 percent title keeps original 48/32px geometry',
      (tester) async {
    final harness = _Harness(lyric: _longLyric());
    await tester.pumpWidget(_app(harness,
        width: 180, textScale: 2, highContrast: true, reduced: true));
    await tester.pumpAndSettle();
    final region =
        tester.getRect(find.byKey(const ValueKey('test-title-region')));
    final capsule =
        tester.getRect(find.byKey(const ValueKey('test-title-capsule')));
    expect(region.height, 48);
    expect(capsule.height, 32);
    expect(capsule.top - region.top, region.bottom - capsule.bottom);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty, failed and disposed sources leave no pending marquee',
      (tester) async {
    final harness = _Harness(lyric: _longLyric(), position: 4);
    await _mount(tester, harness);
    final failed = Completer<Lyric?>();
    harness.future = failed.future;
    await tester.pumpWidget(_app(harness));
    failed.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('歌词暂不可用'), findsOneWidget);
    harness.future = Future.value(_Lyric([]));
    await tester.pumpWidget(_app(harness));
    await tester.pumpAndSettle();
    expect(find.text('Enjoy Music'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    harness.emit(12);
    await tester.pump(const Duration(seconds: 5));
    expect(harness.positions.hasListener, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
