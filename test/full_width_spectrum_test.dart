import 'dart:async';

import 'package:dan_player/component/full_width_spectrum.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _SpectrumFixture {
  final samples = StreamController<List<double>>.broadcast(sync: true);
  List<double> current = [0, .5, 1];
  bool failRead = false;

  List<double> read() {
    if (failRead) throw StateError('fixture spectrum unavailable');
    return current;
  }

  void emit(List<double> values) {
    current = values;
    samples.add(values);
  }

  Widget view({double height = 32}) => FullWidthSpectrumView(
        samples: samples.stream,
        readLevels: read,
        height: height,
      );
}

Widget _app(_SpectrumFixture fixture,
        {bool reduced = false,
        bool tickerEnabled = true,
        bool highContrast = false,
        Brightness brightness = Brightness.light,
        double textScale = 1,
        double width = 440,
        Widget? body,
        GlobalKey<NavigatorState>? navigatorKey}) =>
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: ThemeData(
        platform: TargetPlatform.windows,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: brightness,
        ),
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
          child: SizedBox(width: width, child: body ?? fixture.view()),
        ),
      ),
    );

Finder _paintFinder() => find.byWidgetPredicate((widget) =>
    widget is CustomPaint && widget.painter is FrequencySpectrumPainter);

FrequencySpectrumPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_paintFinder()).painter!
        as FrequencySpectrumPainter;

Future<void> _mount(WidgetTester tester, _SpectrumFixture fixture,
    {bool reduced = false}) async {
  expect(PlayService.isInitialized, isFalse);
  addTearDown(fixture.samples.close);
  await tester.pumpWidget(_app(fixture, reduced: reduced));
  await tester.pumpAndSettle();
}

List<RRect> _drawnBars(TestRecordingCanvas canvas) => [
      for (final record in canvas.invocations)
        if (record.invocation.memberName == #drawRRect)
          record.invocation.positionalArguments[0] as RRect,
    ];

Paint _firstBarPaint(TestRecordingCanvas canvas) => canvas.invocations
    .firstWhere((record) =>
        record.invocation.memberName == #drawRRect ||
        record.invocation.memberName == #drawVertices)
    .invocation
    .positionalArguments
    .last as Paint;

void main() {
  testWidgets('initial FFT snapshot is real and frames repaint without rebuild',
      (tester) async {
    final fixture = _SpectrumFixture();
    await _mount(tester, fixture);
    final before = tester.widget<CustomPaint>(_paintFinder());
    final painter = _painter(tester);
    final render = tester.renderObject<RenderCustomPaint>(_paintFinder());
    expect(painter.sampleAt(.5), .5);
    expect(fixture.samples.hasListener, isTrue);
    var repaints = 0;
    painter.addListener(() => repaints++);
    for (var index = 1; index <= 20; index++) {
      fixture.emit([0, index / 20, 1]);
      expect(render.debugNeedsLayout, isFalse);
      await tester.pump(const Duration(milliseconds: 33));
      expect(tester.widget<CustomPaint>(_paintFinder()), same(before));
      expect(_painter(tester), same(painter));
      expect(painter.sampleAt(.5), index / 20);
    }
    expect(repaints, 20);
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets('identical samples and paused zeroes do not keep repainting',
      (tester) async {
    final fixture = _SpectrumFixture();
    await _mount(tester, fixture);
    final painter = _painter(tester);
    var repaints = 0;
    painter.addListener(() => repaints++);
    fixture.emit([0, 0, 0]);
    await tester.pump();
    expect(repaints, 1);
    for (var index = 0; index < 100; index++) {
      fixture.emit([0, 0, 0]);
    }
    await tester.pump(const Duration(seconds: 2));
    expect(repaints, 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(painter.sampleAt(.5), 0);
  });

  testWidgets('input snapshots survive a producer reusing its mutable buffer',
      (tester) async {
    final fixture = _SpectrumFixture();
    await _mount(tester, fixture);
    final buffer = [.2, .4, .6];
    fixture.emit(buffer);
    await tester.pump();
    expect(_painter(tester).sampleAt(.5), .4);
    buffer[1] = .9;
    expect(_painter(tester).sampleAt(.5), .4);
    fixture.emit(buffer);
    await tester.pump();
    expect(_painter(tester).sampleAt(.5), .9);
  });

  testWidgets('source replacement detaches old FFT frames and failures',
      (tester) async {
    final old = _SpectrumFixture();
    final current = _SpectrumFixture()..current = [.1, .2, .3];
    await _mount(tester, old);
    addTearDown(current.samples.close);
    await tester.pumpWidget(_app(current));
    await tester.pumpAndSettle();
    expect(old.samples.hasListener, isFalse);
    expect(current.samples.hasListener, isTrue);
    old.emit([1, 1, 1]);
    old.samples.addError(StateError('stale FFT source'));
    await tester.pump();
    expect(_painter(tester).sampleAt(.5), .2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable and invalid FFT samples become a quiet baseline',
      (tester) async {
    final fixture = _SpectrumFixture()..failRead = true;
    await _mount(tester, fixture);
    expect(_painter(tester).sampleAt(.5), 0);
    fixture.emit([double.nan, double.infinity, -1, 2]);
    await tester.pump();
    expect(_painter(tester).levels.value, [0, 0, 0, 1]);
    fixture.samples.addError(StateError('FFT unavailable'));
    await tester.pump();
    expect(_painter(tester).sampleAt(.5), 0);
    fixture.emit([.7, .7]);
    await tester.pump();
    expect(_painter(tester).sampleAt(.5), .7);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live reduced motion stops FFT demand and resumes from snapshot',
      (tester) async {
    final fixture = _SpectrumFixture();
    await _mount(tester, fixture);
    await tester.pumpWidget(_app(fixture, reduced: true));
    await tester.pump();
    expect(fixture.samples.hasListener, isFalse);
    expect(_painter(tester).sampleAt(.5), 0);
    fixture.emit([.3, .6, .9]);
    await tester.pump(const Duration(seconds: 1));
    expect(_painter(tester).sampleAt(.5), 0);
    await tester.pumpWidget(_app(fixture));
    await tester.pump();
    expect(fixture.samples.hasListener, isTrue);
    expect(_painter(tester).sampleAt(.5), .6);
  });

  for (final feature in ['disableAnimations', 'reduceMotion']) {
    testWidgets('platform $feature also suspends frequency demand',
        (tester) async {
      final fixture = _SpectrumFixture();
      await _mount(tester, fixture);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(
        disableAnimations: feature == 'disableAnimations',
        reduceMotion: feature == 'reduceMotion',
      );
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pump();
      expect(fixture.samples.hasListener, isFalse);
      expect(_painter(tester).sampleAt(.5), 0);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets('hidden ticker scope stops subscriptions until visible',
      (tester) async {
    final fixture = _SpectrumFixture();
    await _mount(tester, fixture);
    await tester.pumpWidget(_app(fixture, tickerEnabled: false));
    await tester.pump();
    expect(fixture.samples.hasListener, isFalse);
    fixture.current = [.8, .8];
    await tester.pumpWidget(_app(fixture));
    await tester.pump();
    expect(fixture.samples.hasListener, isTrue);
    expect(_painter(tester).sampleAt(.5), .8);
  });

  testWidgets('covered route pauses FFT while keeping its widget alive',
      (tester) async {
    final fixture = _SpectrumFixture();
    final navigator = GlobalKey<NavigatorState>();
    addTearDown(fixture.samples.close);
    await tester.pumpWidget(_app(fixture, navigatorKey: navigator));
    await tester.pumpAndSettle();
    expect(fixture.samples.hasListener, isTrue);
    unawaited(navigator.currentState!.push<void>(PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => const Center(child: Text('overlay')),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(FullWidthSpectrumView), findsOneWidget);
    expect(fixture.samples.hasListener, isFalse);
    fixture.current = [.9, .9];
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(fixture.samples.hasListener, isTrue);
    expect(_painter(tester).sampleAt(.5), .9);
  });

  testWidgets('application pause and resume gates native sample demand',
      (tester) async {
    final fixture = _SpectrumFixture();
    await _mount(tester, fixture);
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // Cleanup must not depend on another frame: paused bindings stop frames.
    expect(fixture.samples.hasListener, isFalse);
    await tester.pump();
    fixture.current = [.4, .4];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(fixture.samples.hasListener, isTrue);
    expect(_painter(tester).sampleAt(.5), .4);
  });

  testWidgets('disposing the view removes all sample listeners and timers',
      (tester) async {
    final fixture = _SpectrumFixture();
    await _mount(tester, fixture);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(fixture.samples.hasListener, isFalse);
    fixture.emit([1, 1]);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  test('bar drawing remains inside even fractional tiny or very wide bounds',
      () {
    final values = ValueNotifier<List<double>>([1, double.nan, .8, -1, 2]);
    addTearDown(values.dispose);
    final painter = FrequencySpectrumPainter(
      levels: values,
      startColor: Colors.blue,
      endColor: Colors.purple,
    );
    for (final size in const [
      Size(.1, .1),
      Size(1, 1),
      Size(24, 24),
      Size(100, 1),
      Size(200, 24),
      Size(440, 32),
      Size(3000, 72),
    ]) {
      final canvas = TestRecordingCanvas();
      painter.paint(canvas, size);
      final bars = _drawnBars(canvas);
      if (bars.isEmpty) {
        expect(
            canvas.invocations
                .where((v) => v.invocation.memberName == #drawVertices)
                .length,
            1);
      } else {
        expect(bars.length, inInclusiveRange(1, 112));
      }
      for (final bar in bars) {
        expect(bar.left, greaterThanOrEqualTo(0));
        expect(bar.top, greaterThanOrEqualTo(0));
        expect(bar.right, lessThanOrEqualTo(size.width + .000001));
        expect(bar.bottom, lessThanOrEqualTo(size.height + .000001));
        expect(bar.width, greaterThan(0));
        expect(bar.height, greaterThan(0));
      }
      expect(canvas.getSaveCount(), 0);
    }
    final emptyCanvas = TestRecordingCanvas();
    painter.paint(emptyCanvas, Size.zero);
    expect(emptyCanvas.invocations, isEmpty);
  });

  test(
      'spectrum reuses shader and x geometry, height still follows real levels',
      () {
    final values = ValueNotifier<List<double>>([0, 0, 0]);
    addTearDown(values.dispose);
    final painter = FrequencySpectrumPainter(
      levels: values,
      startColor: Colors.blue,
      endColor: Colors.purple,
    );
    final before = TestRecordingCanvas();
    painter.paint(before, const Size(440, 32));
    final oldShader = _firstBarPaint(before).shader;
    values.value = [1, 1, 1];
    final after = TestRecordingCanvas();
    painter.paint(after, const Size(440, 32));
    expect(_firstBarPaint(after).shader, same(oldShader));
    expect(painter.sampleAt(.5), 1);
    expect(
        after.invocations
            .where((v) => v.invocation.memberName == #drawVertices)
            .length,
        1);
    final resized = TestRecordingCanvas();
    painter.paint(resized, const Size(200, 24));
    expect(_firstBarPaint(resized).shader, isNot(same(oldShader)));
  });

  for (final brightness in Brightness.values) {
    for (final height in [24.0, 32.0]) {
      testWidgets(
          'spectrum above progress remains touchable at 200%, $brightness/$height',
          (tester) async {
        final fixture = _SpectrumFixture();
        addTearDown(fixture.samples.close);
        final value = ValueNotifier(.25);
        final focus = FocusNode();
        addTearDown(value.dispose);
        addTearDown(focus.dispose);
        final body = SpectrumProgressSection(
          spectrum: fixture.view(height: height),
          progress: Column(mainAxisSize: MainAxisSize.min, children: [
            ValueListenableBuilder<double>(
              valueListenable: value,
              builder: (_, position, __) => Slider(
                key: const ValueKey('progress'),
                focusNode: focus,
                value: position,
                onChanged: (next) => value.value = next,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: OverflowBar(
                  alignment: MainAxisAlignment.spaceBetween,
                  spacing: 8,
                  overflowSpacing: 2,
                  overflowAlignment: OverflowBarAlignment.end,
                  children: [Text('03:20'), Text('05:10')]),
            ),
          ]),
        );
        await tester.pumpWidget(_app(fixture,
            body: body,
            width: 320,
            textScale: 2,
            brightness: brightness,
            highContrast: true));
        await tester.pumpAndSettle();
        final spectrum = tester.getRect(find.byType(FullWidthSpectrumView));
        final slider = tester.getRect(find.byKey(const ValueKey('progress')));
        expect(spectrum.bottom, closeTo(slider.top, .001));
        expect(spectrum.height, height);
        expect(spectrum.left, closeTo(slider.left + 24, .001));
        expect(spectrum.right, closeTo(slider.right - 24, .001));
        expect(slider.height, greaterThanOrEqualTo(44));
        await tester.drag(
            find.byKey(const ValueKey('progress')), const Offset(45, 0));
        await tester.pumpAndSettle();
        expect(value.value, greaterThan(.25));
        final beforeKey = value.value;
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(value.value, greaterThan(beforeKey));
        expect(tester.takeException(), isNull);
        expect(PlayService.isInitialized, isFalse);
      });
    }
  }
}
