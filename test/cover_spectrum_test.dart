import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as graphics;

import 'package:dan_player/component/full_width_spectrum.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/lyric_cover_spectrum.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
  });

  test('cover and all four bar bands fit only their allotted cell', () {
    for (final size in [
      const Size(800, 900),
      const Size(400, 600),
      const Size(260, 100),
      const Size(30, 20),
      Size.zero
    ]) {
      final geometry = CoverSpectrumGeometry.fit(size, enabled: true);
      expect(geometry.size.width, lessThanOrEqualTo(size.width));
      expect(geometry.size.height, lessThanOrEqualTo(size.height));
      expect(geometry.coverRect.left, greaterThanOrEqualTo(0));
      expect(geometry.coverRect.top, greaterThanOrEqualTo(0));
      expect(geometry.coverRect.right, lessThanOrEqualTo(geometry.size.width));
      expect(
          geometry.coverRect.bottom, lessThanOrEqualTo(geometry.size.height));
      expect(geometry.coverRect.width, geometry.coverRect.height);
    }
    expect(
        CoverSpectrumGeometry.fit(const Size(800, 900), enabled: true)
            .coverRect
            .size,
        const Size.square(400));
    expect(
        CoverSpectrumGeometry.fit(const Size(400, 600), enabled: false)
            .coverRect,
        const Rect.fromLTWH(0, 0, 400, 400));
  });

  test('only one placement is selected and absent artwork falls back', () {
    for (final placement in LyricSpectrumPlacement.values) {
      for (final enabled in [true, false]) {
        for (final coverVisible in [true, false]) {
          final prefs = RenderingPreferences(
              lyricSpectrum: enabled, lyricSpectrumPlacement: placement);
          final cover = lyricSpectrumVisibleAt(
              prefs, LyricSpectrumPlacement.cover,
              coverVisible: coverVisible);
          final progress = lyricSpectrumVisibleAt(
              prefs, LyricSpectrumPlacement.progress,
              coverVisible: coverVisible);
          expect(cover && progress, isFalse);
          expect(cover || progress, enabled);
          if (!coverVisible) expect(progress, enabled);
        }
      }
    }
  });

  test('four edges share the density budget and leave artwork transparent',
      () async {
    const output = String.fromEnvironment('DAN_COVER_SPECTRUM_RENDER');
    final levels = ValueNotifier<List<double>>(List.filled(48, 1));
    addTearDown(levels.dispose);
    for (final density in SpectrumDensity.values) {
      for (final side in [180.0, 476.0]) {
        final geometry =
            CoverSpectrumGeometry.fit(Size.square(side), enabled: true);
        final painter = CoverSpectrumPainter(
          levels: levels,
          coverRect: geometry.coverRect,
          maximumBars: density.maximumBars,
          startColor: Colors.blue,
          endColor: Colors.pink,
        );
        final canvas = TestRecordingCanvas();
        painter.paint(canvas, geometry.size);
        expect(painter.barCount, inInclusiveRange(4, density.maximumBars));
        expect(
            canvas.invocations.where(
                (record) => record.invocation.memberName == #drawVertices),
            hasLength(4));
        final recorder = graphics.PictureRecorder();
        painter.paint(Canvas(recorder), geometry.size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(side.toInt(), side.toInt());
        picture.dispose();
        final bytes = (await image.toByteData())!.buffer.asUint8List();
        final cover = geometry.coverRect;
        var top = 0, right = 0, bottom = 0, left = 0;
        for (var y = 0; y < side; y++) {
          for (var x = 0; x < side; x++) {
            final alpha = bytes[(y * side.toInt() + x) * 4 + 3];
            if (alpha == 0) continue;
            final point = Offset(x + .5, y + .5);
            expect(cover.contains(point), isFalse,
                reason: 'bar entered artwork at $point');
            if (y < cover.top) top++;
            if (x > cover.right) right++;
            if (y > cover.bottom) bottom++;
            if (x < cover.left) left++;
          }
        }
        for (final ink in [top, right, bottom, left]) {
          expect(ink, greaterThan(0));
        }
        if (output.isNotEmpty) {
          await Directory(output).create(recursive: true);
          await File('$output/edges-${density.name}-$side.png').writeAsBytes(
              (await image.toByteData(format: graphics.ImageByteFormat.png))!
                  .buffer
                  .asUint8List());
        }
        image.dispose();
      }
    }
  });

  testWidgets('responsive handoff never retains two FFT subscriptions',
      (tester) async {
    var active = 0, maximum = 0;
    final source = StreamController<List<double>>.broadcast(sync: true);
    final stream = Stream<List<double>>.multi((sink) {
      active++;
      maximum = math.max(maximum, active);
      final subscription = source.stream.listen(sink.addSync);
      sink.onCancel = () {
        active--;
        return subscription.cancel();
      };
    }, isBroadcast: true);
    final coverVisible = ValueNotifier(true);
    final hidden = ValueNotifier(false);
    final prefs = ValueNotifier(const RenderingPreferences(
        lyricSpectrumPlacement: LyricSpectrumPlacement.cover));
    addTearDown(source.close);
    addTearDown(coverVisible.dispose);
    addTearDown(hidden.dispose);
    addTearDown(prefs.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RenderingPreferencesScope(
            preferences: prefs,
            child: Column(children: [
              for (final location in LyricSpectrumPlacement.values)
                FullWidthSpectrumView(
                    key: ValueKey(location),
                    samples: stream,
                    readLevels: () => [.2, .6, .9],
                    hidden: hidden,
                    activity: coverVisible,
                    height: 100,
                    coverRect: location == LyricSpectrumPlacement.cover
                        ? const Rect.fromLTWH(20, 20, 60, 60)
                        : null,
                    shouldListen: (value) => lyricSpectrumVisibleAt(
                        value, location,
                        coverVisible: coverVisible.value)),
            ]))));
    await tester.pump();
    expect(active, 1);
    for (var i = 0; i < 10; i++) {
      coverVisible.value = !coverVisible.value;
      await tester.pump();
      expect(active, 1);
    }
    expect(maximum, 1);
    hidden.value = true;
    expect(active, 0);
    hidden.value = false;
    await tester.pump();
    expect(active, 1);
    prefs.value = prefs.value.copyWith(lyricSpectrum: false);
    expect(active, 0);
    prefs.value = prefs.value.copyWith(lyricSpectrum: true);
    await tester.pump();
    expect(active, 1);
    // Responsive page replacement deactivates the old owner before mounting
    // the new owner; disposal at frame end would otherwise briefly duplicate it.
    await tester.pumpWidget(MaterialApp(
        home: FullWidthSpectrumView(
            samples: stream, readLevels: () => [.2, .6, .9], height: 32)));
    expect(active, 1);
    expect(maximum, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(active, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('cover paint changes without rebuilding and paused data is idle',
      (tester) async {
    final source = StreamController<List<double>>.broadcast(sync: true);
    addTearDown(source.close);
    final artwork = _CountArtworkPaints();
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SizedBox.square(
                dimension: 300,
                child: RepaintBoundary(
                    child: CoverSpectrumFrame(
                        enabled: true,
                        coverBuilder: (_) => CustomPaint(painter: artwork),
                        spectrumBuilder: (size, coverRect) =>
                            FullWidthSpectrumView(
                                samples: source.stream,
                                readLevels: () => [.2, .6, .9],
                                height: size.height,
                                coverRect: coverRect)))))));
    final initialArtworkPaints = artwork.paints;
    final finder = find.byWidgetPredicate((widget) =>
        widget is CustomPaint && widget.painter is CoverSpectrumPainter);
    final before = tester.widget<CustomPaint>(finder);
    final painter = before.painter! as CoverSpectrumPainter;
    var paints = 0;
    painter.addListener(() => paints++);
    source.add([0, 0, 0]);
    await tester.pump();
    for (var i = 0; i < 100; i++) {
      source.add([0, 0, 0]);
    }
    await tester.pump(const Duration(seconds: 1));
    expect(paints, 1);
    expect(tester.widget<CustomPaint>(finder), same(before));
    expect(artwork.paints, initialArtworkPaints);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rapid AnimatedSwitcher reversal never revives an old cover',
      (tester) async {
    var active = 0, maximum = 0;
    final owners = <int, int>{};
    final source = StreamController<List<double>>.broadcast(sync: true);
    final hidden = ValueNotifier(false);
    final key = GlobalKey<_SpectrumSwitchHarnessState>();
    Stream<List<double>> samples(int generation) =>
        Stream<List<double>>.multi((sink) {
          active++;
          maximum = math.max(maximum, active);
          owners.update(generation, (value) => value + 1, ifAbsent: () => 1);
          final subscription = source.stream.listen(sink.addSync);
          sink.onCancel = () {
            active--;
            owners[generation] = owners[generation]! - 1;
            return subscription.cancel();
          };
        }, isBroadcast: true);
    addTearDown(source.close);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(MaterialApp(
        home: _SpectrumSwitchHarness(
            key: key, samples: samples, hidden: hidden)));
    await tester.pump();
    expect(owners[0], 1);
    // Keep the first cover partway through its entering fade so its outgoing
    // animation survives a fast reversal, exactly as the responsive page does.
    await tester.pump(const Duration(milliseconds: 50));
    key.currentState!.showCover(false);
    expect(owners[0], 0, reason: 'Outgoing demand stops before its next frame');
    await tester.pump(const Duration(milliseconds: 30));
    key.currentState!.showCover(true);
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byType(FullWidthSpectrumView), findsNWidgets(3),
        reason: 'Old cover, new cover and progress really coexist');
    expect(owners[0], 0);
    expect(owners[2], 1);
    expect(active, 1);
    expect(maximum, 1);
    hidden.value = true;
    expect(active, 0);
    hidden.value = false;
    await tester.pump();
    expect(owners[0], 0, reason: 'Native show must not revive old artwork');
    expect(owners[2], 1);
    for (var i = 0; i < 8; i++) {
      key.currentState!.showCover(false);
      await tester.pump(const Duration(milliseconds: 10));
      key.currentState!.showCover(true);
      await tester.pump(const Duration(milliseconds: 10));
      expect(owners[0], 0);
      expect(active, 1);
      expect(maximum, 1);
    }
    // Remove the whole owner while outgoing animation controllers still exist.
    // Its notifiers are disposed before descendants remove their listeners.
    await tester.pumpWidget(const SizedBox.shrink());
    expect(active, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('envelope avoids adjacent content and toggling preserves artwork',
      (tester) async {
    final coverKey = GlobalKey();
    final sceneKey = GlobalKey();
    final levels = ValueNotifier<List<double>>(
        List.generate(48, (index) => .2 + .8 * math.sin(index * .2).abs()));
    addTearDown(levels.dispose);
    Future<void> mount(Size size, bool enabled, Brightness brightness) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(
          themeAnimationDuration: Duration.zero,
          theme: ThemeData(
              fontFamily: danEmbeddedFontFamily,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.blue, brightness: brightness)),
          home: RepaintBoundary(
              key: sceneKey,
              child: Scaffold(
                  body: Column(children: [
                const SizedBox(height: 56),
                Expanded(
                    child: Row(children: [
                  Expanded(
                      child: Column(children: [
                    const SizedBox(
                        key: ValueKey('metadata'),
                        height: 60,
                        width: double.infinity,
                        child: Center(
                            child: SizedBox(
                                width: 400,
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('封面四周频谱',
                                          maxLines: 1,
                                          style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold)),
                                      Text('艺术家 - 专辑', maxLines: 1),
                                    ])))),
                    Expanded(
                        child: CoverSpectrumFrame(
                            enabled: enabled,
                            coverBuilder: (_) => DecoratedBox(
                                key: coverKey,
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    gradient: const LinearGradient(colors: [
                                      Color(0xff58355e),
                                      Color(0xffdf977e),
                                      Color(0xff283957)
                                    ]))),
                            spectrumBuilder: (size, coverRect) => CustomPaint(
                                key: const ValueKey('spectrum-envelope'),
                                painter: CoverSpectrumPainter(
                                    levels: levels,
                                    coverRect: coverRect,
                                    startColor: Colors.blue,
                                    endColor: Colors.pink)))),
                  ])),
                  const Expanded(
                      child: SizedBox.expand(
                          key: ValueKey('lyrics'),
                          child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('歌词内容保持原位置',
                                        style: TextStyle(fontSize: 26)),
                                    SizedBox(height: 18),
                                    Text('音柱不会越过封面区域',
                                        style: TextStyle(fontSize: 18)),
                                  ])))),
                ])),
                SizedBox(
                    key: const ValueKey('controls'),
                    height: 110,
                    width: double.infinity,
                    child: Column(children: [
                      Slider(value: .4, onChanged: (_) {}),
                      const Text('上一首　　播放 / 暂停　　下一首'),
                    ])),
              ])))));
      await tester.pumpAndSettle();
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(1280, 840), const Size(960, 420)]) {
      for (final brightness in Brightness.values) {
        await mount(size, true, brightness);
        final envelope =
            tester.getRect(find.byKey(const ValueKey('spectrum-envelope')));
        for (final key in ['metadata', 'lyrics', 'controls']) {
          expect(envelope.overlaps(tester.getRect(find.byKey(ValueKey(key)))),
              isFalse);
        }
        expect(tester.takeException(), isNull);
        const output = String.fromEnvironment('DAN_COVER_SPECTRUM_RENDER');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            await Directory(output).create(recursive: true);
            final image = await (sceneKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
            await File(
                    '$output/layout-${size.width.toInt()}-${brightness.name}.png')
                .writeAsBytes((await image.toByteData(
                        format: graphics.ImageByteFormat.png))!
                    .buffer
                    .asUint8List());
            image.dispose();
          });
        }
        final render = tester.renderObject(find.byKey(coverKey));
        await mount(size, false, Brightness.light);
        expect(tester.renderObject(find.byKey(coverKey)), same(render));
        expect(tester.takeException(), isNull);
      }
    }
  });
}

class _CountArtworkPaints extends CustomPainter {
  var paints = 0;
  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.orange);
  }

  @override
  bool shouldRepaint(_CountArtworkPaints oldDelegate) => false;
}

class _SpectrumSwitchHarness extends StatefulWidget {
  const _SpectrumSwitchHarness(
      {super.key, required this.samples, required this.hidden});
  final Stream<List<double>> Function(int generation) samples;
  final ValueNotifier<bool> hidden;

  @override
  State<_SpectrumSwitchHarness> createState() => _SpectrumSwitchHarnessState();
}

class _SpectrumSwitchHarnessState extends State<_SpectrumSwitchHarness> {
  final _visible = ValueNotifier(true);
  final _generation = ValueNotifier(0);
  final _preferences = ValueNotifier(const RenderingPreferences(
      lyricSpectrumPlacement: LyricSpectrumPlacement.cover));
  final _streams = <int, Stream<List<double>>>{};

  void showCover(bool visible) {
    if (_visible.value == visible) return;
    _generation.value++;
    _visible.value = visible;
    setState(() {});
  }

  FullWidthSpectrumView spectrum(
          int generation, bool isCover) =>
      FullWidthSpectrumView(
          key: ValueKey(generation),
          height: 100,
          coverRect: isCover ? const Rect.fromLTWH(25, 25, 50, 50) : null,
          samples: _streams.putIfAbsent(
              generation, () => widget.samples(generation)),
          readLevels: () => [.2, .6, .9],
          hidden: widget.hidden,
          activity: Listenable.merge([_visible, _generation]),
          shouldListen: (preferences) => lyricSpectrumVisibleAt(
              preferences,
              isCover
                  ? LyricSpectrumPlacement.cover
                  : LyricSpectrumPlacement.progress,
              coverVisible: _visible.value &&
                  (!isCover || _generation.value == generation)));

  @override
  Widget build(BuildContext context) => RenderingPreferencesScope(
      preferences: _preferences,
      child: Column(children: [
        AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _visible.value
                ? spectrum(_generation.value, true)
                : const SizedBox(height: 100)),
        spectrum(-1, false),
      ]));

  @override
  void dispose() {
    _visible.dispose();
    _generation.dispose();
    _preferences.dispose();
    super.dispose();
  }
}
