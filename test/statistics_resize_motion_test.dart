import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/personal_annotations_card.dart';
import 'package:dan_player/component/statistics_distribution_view.dart';
import 'package:dan_player/component/statistics_resize.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

class _Probe extends StatefulWidget {
  const _Probe({super.key, required this.height});
  final double height;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final focus = FocusNode();
  var draft = 'retained draft';
  void replaceDraft(String value) => setState(() => draft = value);
  @override
  Widget build(BuildContext context) => Focus(
      focusNode: focus,
      child: SizedBox(height: widget.height, child: Text(draft)));
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }
}

class _Rig {
  final height = ValueNotifier(100.0);
  final width = ValueNotifier(480.0);
  final visible = ValueNotifier(true);
  final preferences = ValueNotifier(const RenderingPreferences());
  final scroll = ScrollController();
  Widget host({bool responsive = false, Widget? child}) => MaterialApp(
      home: Scaffold(
          body: SizedBox(
              height: 200,
              child: RenderingPreferencesScope(
                  preferences: preferences,
                  child: AnimatedBuilder(
                      animation: Listenable.merge([height, width, visible]),
                      builder: (context, _) => TickerMode(
                          enabled: visible.value,
                          child: SingleChildScrollView(
                              controller: scroll,
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 200),
                                    SizedBox(
                                        width: width.value,
                                        child: StatisticsResize(
                                            key: const ValueKey('resize'),
                                            child: child ??
                                                _Probe(
                                                    key:
                                                        const ValueKey('probe'),
                                                    height: responsive
                                                        ? width.value < 420
                                                            ? 360
                                                            : 100
                                                        : height.value))),
                                    const Text('following section'),
                                  ]))))))));
  void dispose() {
    height.dispose();
    width.dispose();
    visible.dispose();
    preferences.dispose();
    scroll.dispose();
  }
}

class _CountLayout extends SingleChildRenderObjectWidget {
  const _CountLayout({required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => _CountLayoutRender();
}

class _CountLayoutRender extends RenderProxyBox {
  int layouts = 0;
  @override
  void performLayout() {
    layouts++;
    super.performLayout();
  }
}

final _resize = find.byKey(const ValueKey('resize'));
double _height(WidgetTester tester) => tester.getSize(_resize).height;

void main({bool nativeOnly = false}) {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    final previous = uiLanguage.value;
    addTearDown(() => uiLanguage.value = previous);
  });

  if (nativeOnly) {
    _registerNativeRasterCases();
    return;
  }

  testWidgets('equal height column changes retain value-keyed child and focus',
      (tester) async {
    final columns = ValueNotifier(2);
    addTearDown(columns.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 480,
                child: ValueListenableBuilder<int>(
                    valueListenable: columns,
                    builder: (context, value, child) =>
                        StatisticsEqualHeightRows(
                            columns: value,
                            children: const [
                              _Probe(key: ValueKey('first'), height: 100),
                              _Probe(key: ValueKey('second'), height: 80),
                            ]))))));
    final first =
        tester.state<_ProbeState>(find.byKey(const ValueKey('first')));
    first.replaceDraft('unsaved state');
    first.focus.requestFocus();
    await tester.pump();
    columns.value = 1;
    await tester.pump();
    expect(tester.state(find.byKey(const ValueKey('first'))), same(first));
    expect(first.focus.hasFocus, isTrue);
    expect(find.text('unsaved state'), findsOneWidget);
    columns.value = 2;
    await tester.pump();
    expect(tester.state(find.byKey(const ValueKey('first'))), same(first));
    expect(first.focus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('continuous width reflow animates height and commits width now',
      (tester) async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    await tester.pumpWidget(rig.host(responsive: true));
    await tester.pumpAndSettle();
    rig.width.value = 479;
    await tester.pump();
    rig.width.value = 478;
    await tester.pump();
    rig.width.value = 410;
    await tester.pump();
    expect(tester.getSize(_resize).width, 410);
    expect(_height(tester), closeTo(100, .05),
        reason:
            'A responsive height change must not inherit width instability');
    await tester.pump(const Duration(milliseconds: 70));
    expect(_height(tester), inExclusiveRange(100, 360));
    await tester.pumpAndSettle();
    expect(_height(tester), closeTo(360, .05));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'section height reverses from its visible size with no state reset',
      (tester) async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    await tester.pumpWidget(rig.host());
    await tester.pumpAndSettle();
    final state = tester.state<_ProbeState>(find.byType(_Probe));
    state.focus.requestFocus();
    rig.scroll.jumpTo(100);
    rig.height.value = 360;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final intermediate = _height(tester);
    expect(intermediate, inExclusiveRange(100, 360));
    rig.height.value = 100;
    await tester.pump();
    expect(_height(tester), closeTo(intermediate, .05));
    await tester.pumpAndSettle();
    expect(_height(tester), closeTo(100, .05));
    expect(tester.state(find.byType(_Probe)), same(state));
    expect(state.focus.hasFocus, isTrue);
    expect(rig.scroll.offset, 100);
    rig.height.value = 360;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(_height(tester), inExclusiveRange(100, 360));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pure section width updates never start a size clock',
      (tester) async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    await tester.pumpWidget(rig.host());
    await tester.pumpAndSettle();
    for (final width in [479.0, 460.0, 390.0, 360.0]) {
      rig.width.value = width;
      await tester.pump();
      expect(tester.getSize(_resize), Size(width, 100));
      expect(tester.binding.transientCallbackCount, 0);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('height ticks reuse the already laid out child', (tester) async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    await tester.pumpWidget(rig.host(
        child: ValueListenableBuilder<double>(
            valueListenable: rig.height,
            builder: (context, value, child) =>
                _CountLayout(child: SizedBox(height: value)))));
    await tester.pumpAndSettle();
    final child =
        tester.renderObject<_CountLayoutRender>(find.byType(_CountLayout));
    final initialLayouts = child.layouts;
    rig.height.value = 360;
    await tester.pump();
    expect(child.layouts, initialLayouts + 1);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 30));
      expect(child.layouts, initialLayouts + 1);
    }
    await tester.pumpAndSettle();
    expect(child.layouts, initialLayouts + 1);
    expect(_height(tester), 360);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final interruption in [
    'layout off',
    'native reduce',
    'hidden',
    'lifecycle'
  ]) {
    testWidgets('section resize interruption lands idle: $interruption',
        (tester) async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(rig.host());
      await tester.pumpAndSettle();
      final state = tester.state<_ProbeState>(find.byType(_Probe));
      state.focus.requestFocus();
      rig.height.value = 360;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(_height(tester), inExclusiveRange(100, 360));
      switch (interruption) {
        case 'layout off':
          rig.preferences.value = const RenderingPreferences(
              animations: MotionPreferences(disabled: {MotionKind.layout}));
        case 'native reduce':
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(reduceMotion: true);
        case 'hidden':
          rig.visible.value = false;
        case 'lifecycle':
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      }
      await tester.pump();
      expect(_height(tester), closeTo(360, .05));
      expect(tester.state(find.byType(_Probe)), same(state));
      expect(state.focus.hasFocus, isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.transientCallbackCount, 0);
      rig.visible.value = true;
      rig.preferences.value = const RenderingPreferences();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_height(tester), closeTo(360, .05));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final language in UiLanguage.values) {
    testWidgets('personal section grows smoothly ${language.code} narrow 200%',
        (tester) async {
      uiLanguage.value = language;
      sizePlaylistFeature(tester, width: 360, height: 1500);
      final summary = PersonalOrganizationSummary.fromTrackIds(trackIds: [
        'online://qq/one'
      ], personal: {
        'online://qq/one': const PersonalTrack(
            rating: 3, tags: ['Alpha', 'Beta', 'Chi', 'Delta', 'Eta', 'Other'])
      }, identities: TrackIdentityRegistry.inMemory());
      final boundary = GlobalKey();
      await tester.pumpWidget(listeningStatusHost(
          Builder(
              builder: (context) => MediaQuery(
                  data:
                      MediaQuery.of(context).copyWith(disableAnimations: false),
                  child: SingleChildScrollView(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: StatisticsResize(
                              key: const ValueKey('resize'),
                              child: PersonalAnnotationsCard(
                                  snapshot: summary)))))),
          boundary: boundary,
          scale: 2));
      await tester.pumpAndSettle();
      final short = _height(tester);
      await tester.tap(find.byKey(const ValueKey('personal-annotations-tags')));
      await tester.pump();
      expect(_height(tester), closeTo(short, .05));
      await tester.pump(const Duration(milliseconds: 70));
      final intermediate = _height(tester);
      expect(intermediate, greaterThan(short));
      await tester.pumpAndSettle();
      expect(_height(tester), greaterThan(short));
      expect(intermediate, lessThan(_height(tester)));
      expect(find.text(ui('其他 {0} 个标签', [1])), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureListeningStatus(tester, boundary,
          'statistics-resize-personal-${language.code}-360-200');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}

const _rasterText = '窗口改宽，最后一个字符仍然完整。\n'
    'Every final character remains visible after reflow.\n'
    '窓幅が変わっても最後の文字まで表示します。\n'
    '창 너비가 바뀌어도 마지막 글자까지 표시합니다。\n'
    '窗口改宽，最后一个字符仍然完整。\n'
    'Every final character remains visible after reflow.\n'
    '窓幅が変わっても最後の文字まで表示します。\n'
    '창 너비가 바뀌어도 마지막 글자까지 표시합니다。\n'
    '終 最后 끝 FINAL';
const _rasterBackground = Color(0xffd9eeee);

class _RasterRig {
  final width = ValueNotifier(480.0);
  final animated = ValueNotifier(true);
  final visible = ValueNotifier(true);
  final preferences = ValueNotifier(const RenderingPreferences());
  final boundary = GlobalKey();
  final policy = AppFontPolicy.defaults(language: UiLanguage.zh);

  Widget host() => listeningStatusHost(
      AppFontScope(
          policy: policy,
          child: RenderingPreferencesScope(
              preferences: preferences,
              child: Builder(
                  builder: (context) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(disableAnimations: false),
                      child: AnimatedBuilder(
                          animation:
                              Listenable.merge([width, animated, visible]),
                          builder: (context, _) {
                            final content = ColoredBox(
                                color: _rasterBackground,
                                child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text.rich(appFontSpan(_rasterText,
                                        style: const TextStyle(
                                            fontSize: 24,
                                            height: 1.4,
                                            color: Colors.black),
                                        policy: policy))));
                            return TickerMode(
                                enabled: visible.value,
                                child: ColoredBox(
                                    color: Colors.white,
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                              width: width.value,
                                              child: animated.value
                                                  ? StatisticsResize(
                                                      key: const ValueKey(
                                                          'resize'),
                                                      child: content)
                                                  : content),
                                          const Expanded(child: SizedBox()),
                                        ])));
                          }))))),
      boundary: boundary);

  void dispose() {
    width.dispose();
    animated.dispose();
    visible.dispose();
    preferences.dispose();
  }
}

Future<({int width, int height, List<int> rgba})> _rasterSnapshot(
    WidgetTester tester, GlobalKey boundary, String name) async {
  return (await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage(pixelRatio: 1);
    try {
      final data =
          await image.toByteData(format: raster.ImageByteFormat.rawRgba);
      final directory =
          Platform.environment['DAN_STATISTICS_RESIZE_RENDER_DIR'];
      if (directory != null) {
        final png = await image.toByteData(format: raster.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File('$directory/$name.png')
            .writeAsBytes(png!.buffer.asUint8List());
      }
      return (
        width: image.width,
        height: image.height,
        rgba: data!.buffer.asUint8List().toList(growable: false)
      );
    } finally {
      image.dispose();
    }
  }))!;
}

void _expectRasterClipped(({int width, int height, List<int> rgba}) pixels,
    double paintedHeight, double naturalHeight, double width) {
  var leaked = 0;
  for (var y = paintedHeight.ceil() + 2;
      y < naturalHeight.floor() && y < pixels.height;
      y++) {
    for (var x = 2; x < width.floor() - 2; x++) {
      final offset = (y * pixels.width + x) * 4;
      if (pixels.rgba[offset] != 255 ||
          pixels.rgba[offset + 1] != 255 ||
          pixels.rgba[offset + 2] != 255) {
        leaked++;
      }
    }
  }
  expect(leaked, 0,
      reason: 'Incoming text/background must stay inside the clip');
}

Future<Duration> _pumpRasterFrame(WidgetTester tester,
    [Duration duration = Duration.zero]) async {
  Duration? frame;
  // The scheduler clears currentFrameTimeStamp after a real Profile frame;
  // its one-shot post-frame argument is the same adjusted ticker timestamp.
  tester.binding.addPostFrameCallback((timestamp) => frame = timestamp);
  await tester.pump(duration);
  expect(frame, isNotNull);
  return frame!;
}

void _registerNativeRasterCases() {
  const names = [
    'native continuous reflow clips the middle and preserves final glyphs',
    'native height reversal retains its clip and disposes idle',
    'native hidden resize lands at the complete idle paragraph',
  ];
  final onlyCase = Platform.environment['DAN_STATISTICS_RESIZE_NATIVE_CASE'];
  if (onlyCase != null &&
      onlyCase.isNotEmpty &&
      !names.any((name) => name.contains(onlyCase))) {
    throw ArgumentError.value(onlyCase, 'DAN_STATISTICS_RESIZE_NATIVE_CASE',
        'Must match one of the registered native resize cases');
  }
  setUpAll(() =>
      ensureAppFontsLoaded(AppFontPolicy.defaults(language: UiLanguage.zh)));

  void rasterCase(String name, Future<void> Function(WidgetTester) callback) {
    if (onlyCase != null && onlyCase.isNotEmpty && !name.contains(onlyCase)) {
      return;
    }
    testWidgets(name, callback);
  }

  rasterCase(names[0], (tester) async {
    sizePlaylistFeature(tester, width: 640, height: 1300);
    final rig = _RasterRig();
    addTearDown(rig.dispose);
    await tester.pumpWidget(rig.host());
    await tester.pumpAndSettle();
    final original = _height(tester);
    for (final width in [479.0, 478.0]) {
      rig.width.value = width;
      await tester.pump();
      expect(_height(tester), closeTo(original, .05));
      expect(tester.binding.transientCallbackCount, 0);
    }
    rig.width.value = 300;
    await tester.pump();
    expect(tester.getSize(_resize).width, 300);
    expect(_height(tester), closeTo(original, .05));
    final natural = tester.getSize(find.byType(Text).last).height + 32;
    expect(natural, greaterThan(original));
    await tester.pump(const Duration(milliseconds: 70));
    final middle = _height(tester);
    expect(middle, inExclusiveRange(original, natural));
    final mid = await _rasterSnapshot(tester, rig.boundary, 'reflow-mid');
    _expectRasterClipped(mid, middle, natural, 300);
    await tester.pumpAndSettle();
    expect(_height(tester), closeTo(natural, .05));
    final finalPixels =
        await _rasterSnapshot(tester, rig.boundary, 'reflow-final');
    rig.animated.value = false;
    await tester.pump();
    final fresh = await _rasterSnapshot(tester, rig.boundary, 'reflow-fresh');
    expect(finalPixels.rgba, orderedEquals(fresh.rgba),
        reason: 'Natural final glyphs must match a fresh unclipped paragraph');
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  rasterCase(names[1], (tester) async {
    sizePlaylistFeature(tester, width: 640, height: 1300);
    final rig = _RasterRig();
    addTearDown(rig.dispose);
    await tester.pumpWidget(rig.host());
    await tester.pumpAndSettle();
    final original = _height(tester);
    rig.width.value = 300;
    final startFrame = await _pumpRasterFrame(tester);
    final natural = tester.getSize(find.byType(Text).last).height + 32;
    final middleFrame =
        await _pumpRasterFrame(tester, const Duration(milliseconds: 55));
    final middle = _height(tester);
    expect(middle, greaterThan(original));
    double forwardHeight(Duration frame) {
      final progress = ((frame - startFrame).inMicroseconds /
              AppMotion.standard.inMicroseconds)
          .clamp(0.0, 1.0);
      return original +
          (natural - original) * AppMotion.standardCurve.transform(progress);
    }

    expect(middle, closeTo(forwardHeight(middleFrame), .05));
    rig.width.value = 480;
    final reverseFrame = await _pumpRasterFrame(tester);
    final reverseStart = _height(tester);
    // A Windows pump owns a later frame timestamp, even without an explicit
    // fake-time duration. Continue the incoming motion at that real frame.
    expect(reverseStart, closeTo(forwardHeight(reverseFrame), .05));
    final afterReverseFrame =
        await _pumpRasterFrame(tester, const Duration(milliseconds: 50));
    final reverseProgress = ((afterReverseFrame - reverseFrame).inMicroseconds /
            AppMotion.standard.inMicroseconds)
        .clamp(0.0, 1.0);
    expect(
        _height(tester),
        closeTo(
            reverseStart +
                (original - reverseStart) *
                    AppMotion.standardCurve.transform(reverseProgress),
            .05));
    expect(_height(tester), inExclusiveRange(original, reverseStart));
    await _rasterSnapshot(tester, rig.boundary, 'reversal-mid');
    await tester.pumpAndSettle();
    expect(_height(tester), closeTo(original, .05));
    final finalPixels =
        await _rasterSnapshot(tester, rig.boundary, 'reversal-final');
    rig.animated.value = false;
    await tester.pump();
    final fresh = await _rasterSnapshot(tester, rig.boundary, 'reversal-fresh');
    expect(finalPixels.rgba, orderedEquals(fresh.rgba));
    rig.animated.value = true;
    rig.width.value = 300;
    await tester.pump();
    rig.width.value = 480;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  rasterCase(names[2], (tester) async {
    sizePlaylistFeature(tester, width: 640, height: 1300);
    final rig = _RasterRig();
    addTearDown(rig.dispose);
    await tester.pumpWidget(rig.host());
    await tester.pumpAndSettle();
    final original = _height(tester);
    rig.width.value = 300;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    final natural = tester.getSize(find.byType(Text).last).height + 32;
    expect(_height(tester), inExclusiveRange(original, natural));
    rig.visible.value = false;
    await tester.pump();
    expect(_height(tester), closeTo(natural, .05));
    expect(tester.binding.transientCallbackCount, 0);
    final hidden = await _rasterSnapshot(tester, rig.boundary, 'hidden-final');
    rig.animated.value = false;
    await tester.pump();
    final fresh = await _rasterSnapshot(tester, rig.boundary, 'hidden-fresh');
    expect(hidden.rgba, orderedEquals(fresh.rgba));
    rig.visible.value = true;
    rig.animated.value = true;
    await tester.pump();
    expect(_height(tester), closeTo(natural, .05));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
