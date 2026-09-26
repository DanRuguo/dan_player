import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/lyric/local_lyric_preferences.dart';
import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:dan_player/page/now_playing_page/component/detail_waveform_track.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class TransitionFixture {
  final positions = StreamController<double>.broadcast(sync: true);
  late final stream = positions.stream;
  final hidden = ValueNotifier(false);
  final seeks = <double>[];
  String identity = 'A';
  double position = 38;
  Widget host({
    List<double>? peaks,
    WaveformBarDensity density = WaveformBarDensity.automatic,
    bool reduced = false,
    bool feedback = true,
    bool visible = true,
    bool enabled = true,
    TextDirection direction = TextDirection.ltr,
    double width = 400,
    GlobalKey? boundary,
  }) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        themeAnimationDuration: Duration.zero,
        builder: (context, child) =>
            Directionality(textDirection: direction, child: child!),
        theme: Entry(welcome: false).fromSchemeAndFontFamily(
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal,
                brightness: width < 400 ? Brightness.dark : Brightness.light)),
        home: MotionPreferencesScope(
            preferences: const MotionPreferences()
                .withKind(MotionKind.feedback, feedback),
            child: MediaQuery(
                data: MediaQueryData(
                    disableAnimations: reduced,
                    textScaler: TextScaler.linear(width < 400 ? 2 : 1)),
                child: TickerMode(
                    enabled: visible,
                    child: RepaintBoundary(
                        key: boundary,
                        child: Scaffold(
                            body: Center(
                                child: RepaintBoundary(
                                    child: SizedBox(
                                        width: width,
                                        child: DetailProgressSlider(
                                            positions: stream,
                                            readPosition: () => position,
                                            duration: 100,
                                            trackIdentity: identity,
                                            hidden: hidden,
                                            enabled: enabled,
                                            waveform: peaks,
                                            waveformDensity: density,
                                            onSeek: (target) =>
                                                seeks.add(target)))))))))),
      );
  Future<void> dispose() async {
    hidden.dispose();
    await positions.close();
  }
}

WaveformTrackVisual visual(WidgetTester tester) {
  final shape =
      tester.widget<SliderTheme>(find.byType(SliderTheme).last).data.trackShape;
  return shape is DetailWaveformTrackShape
      ? shape.visual
      : const WaveformTrackVisual.line();
}

void idle(WidgetTester tester) {
  expect(tester.binding.hasScheduledFrame, isFalse);
  expect(tester.binding.transientCallbackCount, 0);
  expect(find.byType(Slider), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
  });

  test(
      'projections are reused and interrupted visuals retain their exact starting state',
      () {
    final a = WaveformTrackSource(const [.1, .9], WaveformBarDensity.sparse);
    final b = WaveformTrackSource(const [.1, .9], WaveformBarDensity.dense);
    expect(identical(a.buckets(48), a.buckets(48)), isTrue);
    expect(a.buckets(48).take(24), everyElement(.1));
    expect(a.buckets(48).skip(24), everyElement(.9));
    final halfway = WaveformTrackVisual.interpolate(
        const WaveformTrackVisual.line(), WaveformTrackVisual.wave(a), .5);
    expect(halfway.lineOpacity, .5);
    expect(halfway.layers.single.opacity, .5);
    expect(halfway.layers.single.growth, .5);
    expect(
        identical(
            WaveformTrackVisual.interpolate(
                halfway, WaveformTrackVisual.wave(b), 0),
            halfway),
        isTrue);
    final collapsed = WaveformTrackVisual.interpolate(
        halfway, const WaveformTrackVisual.line(), .5);
    expect(collapsed.layers.single.growth, .25);
    expect(collapsed.lineOpacity, .75);
  });

  testWidgets(
      'ready data grows from the same line, then stops every animation and preserves projection identity',
      (tester) async {
    final fixture = TransitionFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.host());
    final rect = tester.getRect(find.byType(Slider));
    await tester.pumpWidget(fixture.host(peaks: const [.1, 1]));
    expect(visual(tester).layers, isEmpty);
    await tester.pump(const Duration(milliseconds: 120));
    final mid = visual(tester);
    final mix = Curves.easeInOutCubic.transform(.5);
    expect(mid.lineOpacity, closeTo(1 - mix, .001));
    expect(mid.layers.single.growth, closeTo(mix, .001));
    expect(mid.layers.single.opacity, closeTo(mix, .001));
    expect(tester.getRect(find.byType(Slider)), rect);
    final source = mid.layers.single.source;
    final theme =
        tester.widget<SliderTheme>(find.byType(SliderTheme).last).data;
    final track = theme.trackShape!.getPreferredRect(
        parentBox: tester.renderObject<RenderBox>(find.byType(Slider)),
        sliderTheme: theme);
    final count = waveformBarLayout(track.width, source.density).count;
    final projection = source.buckets(count);
    fixture.position = 38.25;
    fixture.positions.add(fixture.position);
    await tester.pumpAndSettle();
    expect(visual(tester).lineOpacity, 0);
    expect(visual(tester).layers.single.growth, 1);
    expect(identical(visual(tester).layers.single.source, source), isTrue);
    expect(identical(source.buckets(count), projection), isTrue);
    expect(fixture.positions.hasListener, isTrue);
    idle(tester);
  });

  testWidgets(
      'reverse and repeated density changes continue from the currently painted visual',
      (tester) async {
    final fixture = TransitionFixture();
    addTearDown(fixture.dispose);
    const peaks = <double>[.2, 1, .4];
    await tester.pumpWidget(fixture.host(peaks: peaks));
    await tester.pump(const Duration(milliseconds: 80));
    final before = visual(tester);
    await tester.pumpWidget(
        fixture.host(peaks: peaks, density: WaveformBarDensity.dense));
    final retargeted = visual(tester);
    expect(retargeted.lineOpacity, before.lineOpacity);
    expect(retargeted.layers.single.source, same(before.layers.single.source));
    expect(retargeted.layers.single.growth, before.layers.single.growth);
    await tester.pump(const Duration(milliseconds: 80));
    expect(visual(tester).layers, hasLength(2));
    final mixed = visual(tester);
    await tester.pumpWidget(fixture.host());
    expect(visual(tester).lineOpacity, mixed.lineOpacity);
    expect(visual(tester).layers.map((layer) => layer.growth),
        mixed.layers.map((layer) => layer.growth));
    await tester.pump(const Duration(milliseconds: 120));
    expect(visual(tester).lineOpacity, greaterThan(mixed.lineOpacity));
    await tester.pumpAndSettle();
    expect(visual(tester).layers, isEmpty);
    idle(tester);
  });

  testWidgets(
      'rapid A B C switches purge all previous amplitudes on the first new frame',
      (tester) async {
    final fixture = TransitionFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.host(peaks: const [1, 0]));
    await tester.pump(const Duration(milliseconds: 100));
    expect(visual(tester).layers, isNotEmpty);
    fixture.identity = 'B';
    await tester.pumpWidget(
        fixture.host(peaks: const [0, .25], density: WaveformBarDensity.dense));
    expect(visual(tester).layers, isEmpty);
    await tester.pump(const Duration(milliseconds: 90));
    expect(visual(tester).layers.single.source.peaks, [0, .25]);
    fixture.identity = 'C';
    await tester.pumpWidget(fixture.host(density: WaveformBarDensity.sparse));
    expect(visual(tester).layers, isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    idle(tester);
    await tester.pumpWidget(fixture
        .host(peaks: const [.5, .75], density: WaveformBarDensity.sparse));
    expect(visual(tester).layers, isEmpty);
    await tester.pumpAndSettle();
    expect(visual(tester).layers.single.source.peaks, [.5, .75]);
    expect(
        visual(tester).layers.single.source.density, WaveformBarDensity.sparse);
    idle(tester);
  });

  testWidgets(
      'reduced motion, disabled feedback, hidden and offstage stop finite transitions immediately',
      (tester) async {
    final fixture = TransitionFixture();
    addTearDown(fixture.dispose);
    const peaks = <double>[.5, 1];
    await tester.pumpWidget(fixture.host(peaks: peaks));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(fixture.host(peaks: peaks, reduced: true));
    expect(visual(tester).layers.single.growth, 1);
    await tester.pumpAndSettle();
    idle(tester);
    await tester.pumpWidget(fixture.host(feedback: false));
    expect(visual(tester).layers, isEmpty);
    await tester.pumpWidget(fixture.host(peaks: peaks, feedback: false));
    expect(visual(tester).layers.single.growth, 1);
    await tester.pumpAndSettle();
    idle(tester);
    await tester.pumpWidget(fixture.host());
    await tester.pump(const Duration(milliseconds: 60));
    fixture.hidden.value = true;
    expect(fixture.positions.hasListener, isFalse);
    await tester.pumpAndSettle();
    idle(tester);
    fixture.hidden.value = false;
    await tester.pumpWidget(fixture.host(peaks: peaks));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(fixture.host(peaks: peaks, visible: false));
    expect(fixture.positions.hasListener, isFalse);
    await tester.pumpAndSettle();
    idle(tester);
    expect(visual(tester).layers.single.growth, 1);
  });

  testWidgets(
      'arrival and density morphs preserve captured preview and cancelling never seeks',
      (tester) async {
    final fixture = TransitionFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.host());
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Slider)));
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump();
    final preview = tester.widget<Slider>(find.byType(Slider)).value;
    await tester.pumpWidget(fixture.host(peaks: const [.2, 1]));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(
        fixture.host(peaks: const [.2, 1], density: WaveformBarDensity.medium));
    expect(tester.widget<Slider>(find.byType(Slider)).value, preview);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(fixture.seeks, isEmpty);
    expect(tester.widget<Slider>(find.byType(Slider)).value, fixture.position);
    idle(tester);
  });

  testWidgets(
      'visible inactive windows keep morphing and paused windows stop immediately',
      (tester) async {
    final fixture = TransitionFixture();
    addTearDown(fixture.dispose);
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await tester.pumpWidget(fixture.host());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpWidget(fixture.host(peaks: const [.2, 1]));
    await tester.pump(const Duration(milliseconds: 80));
    expect(fixture.positions.hasListener, isTrue);
    expect(visual(tester).layers.single.growth, inExclusiveRange(0, 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(fixture.positions.hasListener, isFalse);
    await tester.pumpAndSettle();
    expect(visual(tester).layers.single.growth, 1);
    // Paused bindings can retain muted framework callbacks, but must never
    // request frames. Once resumed, all finite animations must fully drain.
    expect(tester.binding.hasScheduledFrame, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fixture.positions.hasListener, isTrue);
    idle(tester);
  });

  testWidgets(
      'midpoint growth and interrupted density render with product fonts at wide and enlarged narrow widths',
      (tester) async {
    const output = String.fromEnvironment('DAN_WAVEFORM_TRANSITION_RENDER');
    final fixture = TransitionFixture();
    addTearDown(fixture.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final peaks = List.generate(512, (index) => (index % 64) / 63.0);
    for (final width in [800.0, 300.0]) {
      tester.view.physicalSize = Size(width, 240);
      final key = GlobalKey();
      fixture.identity = '$width';
      await tester.pumpWidget(fixture.host(width: width, boundary: key));
      await tester
          .pumpWidget(fixture.host(width: width, peaks: peaks, boundary: key));
      await tester.pump(const Duration(milliseconds: 120));
      for (final stage in ['growth', 'density']) {
        if (stage == 'density') {
          await tester.pumpWidget(fixture.host(
              width: width,
              peaks: peaks,
              boundary: key,
              density: WaveformBarDensity.dense));
          await tester.pump(const Duration(milliseconds: 120));
        }
        expect(tester.takeException(), isNull);
        expect(find.text('0:38'), findsOneWidget);
        expect(find.text('1:40'), findsOneWidget);
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            try {
              final bytes =
                  await image.toByteData(format: drawing.ImageByteFormat.png);
              await File('$output/$stage-${width.toInt()}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
      }
      await tester.pumpAndSettle();
      idle(tester);
    }
  });
}
