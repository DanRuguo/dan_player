import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Isolate the actual lyric rows under a controlled 480 ms height change.
// The Windows integration harness also verifies the complete production view.
const _background = Color(0xff17151a);
const _viewportWidth = 420.0;
const _viewportHeight = 320.0;
const _initialScroll = 40.375;
const _scrollTravel = 12.0;

enum _ScaleMode { native, sampled, direct }

class _Scenario {
  const _Scenario(this.name,
      {required this.nextHasText,
      required this.nextFilter,
      this.matchNextHeight = false,
      this.scaleMode = _ScaleMode.native});

  final String name;
  final bool nextHasText;
  final bool nextFilter;
  final bool matchNextHeight;
  final _ScaleMode scaleMode;
}

const _scenarios = [
  _Scenario('text-filtered', nextHasText: true, nextFilter: true),
  _Scenario('blank-natural', nextHasText: false, nextFilter: true),
  _Scenario('blank-matched',
      nextHasText: false, nextFilter: true, matchNextHeight: true),
  _Scenario('text-unfiltered', nextHasText: true, nextFilter: false),
  _Scenario('text-scale-low',
      nextHasText: true, nextFilter: true, scaleMode: _ScaleMode.sampled),
  _Scenario('text-scale-direct',
      nextHasText: true, nextFilter: true, scaleMode: _ScaleMode.direct),
];

class _Ink {
  const _Ink(this.mass, this.x, this.yWithinRow, this.rowTop, this.rowHeight,
      this.hash);

  final double mass;
  final double x;
  final double yWithinRow;
  final double rowTop;
  final double rowHeight;
  final int hash;

  Map<String, Object?> toJson() => {
        'mass': mass,
        'xPx': mass == 0 ? null : x,
        'yWithinRowPx': mass == 0 ? null : yWithinRow,
        'rowTopLogical': rowTop,
        'rowHeightLogical': rowHeight,
        'hash': hash,
      };
}

class _Frame {
  const _Frame(
      this.phase, this.step, this.reveal, this.scroll, this.current, this.next);

  final String phase;
  final int step;
  final double reveal;
  final double scroll;
  final _Ink current;
  final _Ink next;

  Map<String, Object?> toJson() => {
        'phase': phase,
        'step': step,
        'reveal': reveal,
        'scroll': scroll,
        'current': current.toJson(),
        'next': next.toJson(),
      };
}

double _spread(Iterable<double> values) {
  final list = values.toList();
  return list.reduce(math.max) - list.reduce(math.min);
}

/// Match the backed-up timestamp reveal without restoring the rest of the old
/// LyricLineMotion contract. Blank lyric rows do not have this time label.
class _TimeReveal extends StatelessWidget {
  const _TimeReveal({required this.progress, required this.label});

  final Animation<double> progress;
  final String label;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: progress,
        builder: (context, _) {
          final value = progress.value;
          if (value <= 0) return const SizedBox.shrink();
          return ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: value,
              child: Opacity(
                opacity: value.clamp(0.0, 1.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20, bottom: 4),
                    child: Text(label,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(
                                color: Theme.of(context).colorScheme.primary)),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

Widget _row({
  required String id,
  required LrcLine line,
  required ValueNotifier<Duration> position,
  required Animation<double> reveal,
  required bool filter,
  required _ScaleMode scaleMode,
  required int distance,
  double? forcedHeight,
}) {
  final blank = line.content.trim().isEmpty;
  final externalScale = distance == 1 && scaleMode != _ScaleMode.native;
  Widget tile = SizedBox(
    key: ValueKey('$id-tile'),
    width: double.infinity,
    height: forcedHeight,
    child: LyricViewTile(
      line: line,
      position: position,
      distance: distance,
      opacity: LyricMotion.opacityForDistance(distance),
      // The separate scale-quality contrast keeps the same context glyph but
      // lets the test own its one <1 scale instead of applying it twice.
      reducedMotion: externalScale,
      onTap: () {},
    ),
  );
  if (externalScale) {
    tile = Transform.scale(
      scale: LyricMotion.scaleForDistance(1),
      alignment: Alignment.centerLeft,
      filterQuality: scaleMode == _ScaleMode.sampled ? FilterQuality.low : null,
      child: tile,
    );
  }
  return LyricFollowEffects(
    clock: const AlwaysStoppedAnimation(1),
    transition: null,
    blur: 0,
    blurEnabled: filter,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!blank)
          _TimeReveal(
              progress: reveal, label: id == 'current' ? '00:02' : '00:10'),
        tile,
      ],
    ),
  );
}

Widget _surface({
  required GlobalKey boundary,
  required ScrollController scroll,
  required LyricViewController settings,
  required ValueNotifier<Duration> position,
  required Animation<double> reveal,
  required _Scenario scenario,
  double? matchedNextHeight,
}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        platform: TargetPlatform.windows,
        fontFamily: danEmbeddedFontFamily,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xffe7d379), brightness: Brightness.dark),
      ),
      home: Scaffold(
        backgroundColor: _background,
        body: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: boundary,
            child: SizedBox(
              width: _viewportWidth,
              height: _viewportHeight,
              child: ColoredBox(
                color: _background,
                child: ChangeNotifierProvider.value(
                  value: settings,
                  child: ScrollConfiguration(
                    behavior: const DanPlayerScrollBehavior()
                        .copyWith(scrollbars: false),
                    child: CustomScrollView(
                      controller: scroll,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 74),
                              _row(
                                id: 'current',
                                line: LrcLine(const Duration(seconds: 2),
                                    'This is all we know',
                                    isBlank: false,
                                    length: const Duration(seconds: 6)),
                                position: position,
                                reveal: reveal,
                                filter: true,
                                scaleMode: _ScaleMode.native,
                                distance: 0,
                              ),
                              _row(
                                id: 'next',
                                line: LrcLine(
                                    const Duration(seconds: 10),
                                    scenario.nextHasText
                                        ? 'The smoke through the window'
                                        : '',
                                    isBlank: !scenario.nextHasText,
                                    length: Duration.zero),
                                position: position,
                                reveal: reveal,
                                filter: scenario.nextFilter,
                                scaleMode: scenario.scaleMode,
                                distance: 1,
                                forcedHeight: scenario.matchNextHeight
                                    ? matchedNextHeight
                                    : null,
                              ),
                              const SizedBox(height: 600),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

Future<_Frame> _sample(WidgetTester tester, GlobalKey boundary, double dpr,
    String phase, int step, double reveal, double scroll) async {
  final boundaryRect = tester.getRect(find.byKey(boundary));
  final currentRect =
      tester.getRect(find.byKey(const ValueKey('current-tile')));
  final nextRect = tester.getRect(find.byKey(const ValueKey('next-tile')));
  return (await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage(pixelRatio: dpr);
    try {
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
      _Ink inspect(Rect rect) {
        final local = rect.shift(-boundaryRect.topLeft);
        final left = math.max(0, (local.left * dpr).floor());
        final right = math.min(image.width, (local.right * dpr).ceil());
        final top = math.max(0, (local.top * dpr).floor());
        final bottom = math.min(image.height, (local.bottom * dpr).ceil());
        final red = (_background.r * 255).round();
        final green = (_background.g * 255).round();
        final blue = (_background.b * 255).round();
        var mass = 0.0, sumX = 0.0, sumY = 0.0;
        var hash = 0x811c9dc5;
        for (var y = top; y < bottom; y++) {
          for (var x = left; x < right; x++) {
            final index = (y * image.width + x) * 4;
            final r = bytes[index], g = bytes[index + 1], b = bytes[index + 2];
            hash = ((hash ^ r) * 0x01000193) & 0xffffffff;
            hash = ((hash ^ g) * 0x01000193) & 0xffffffff;
            hash = ((hash ^ b) * 0x01000193) & 0xffffffff;
            final weight =
                (r - red).abs() + (g - green).abs() + (b - blue).abs();
            if (weight < 45) continue;
            mass += weight;
            sumX += weight * (x + .5);
            sumY += weight * (y + .5);
          }
        }
        return _Ink(
            mass,
            mass == 0 ? 0 : sumX / mass,
            mass == 0 ? 0 : sumY / mass - local.top * dpr,
            local.top,
            local.height,
            hash);
      }

      return _Frame(
          phase, step, reveal, scroll, inspect(currentRect), inspect(nextRect));
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf')))
        .load();
  });

  testWidgets(
      'next-row ink stays anchored while timestamp rows reveal and hide',
      (tester) async {
    const dpr = 1.25;
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = const Size(700, 440);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final traces = <String, List<_Frame>>{};
    double? naturalTextHeight;
    const maxCases =
        int.fromEnvironment('DAN_LYRIC_MAX_CASES', defaultValue: 6);

    for (final scenario in _scenarios.take(maxCases)) {
      if (scenario.matchNextHeight) expect(naturalTextHeight, isNotNull);
      final boundary = GlobalKey();
      final scroll = ScrollController(initialScrollOffset: _initialScroll);
      final position = ValueNotifier(const Duration(seconds: 3));
      final settings = LyricViewController(
          preferences: NowPlayingPagePreference(
              NowPlayingViewMode.withLyric, LyricTextAlign.left, 22, 18,
              showLyricTranslation: false,
              showLyricRomanization: false,
              showLyricTimestamps: false));
      final clock = AnimationController(
          vsync: tester, duration: LyricMotion.lineDuration);
      final reveal = CurvedAnimation(parent: clock, curve: LyricMotion.curve);
      final frames = <_Frame>[];
      try {
        await tester.pumpWidget(_surface(
            boundary: boundary,
            scroll: scroll,
            settings: settings,
            position: position,
            reveal: reveal,
            scenario: scenario,
            matchedNextHeight: naturalTextHeight));
        await tester.pumpAndSettle();
        if (scenario.name == 'text-filtered') {
          naturalTextHeight =
              tester.getSize(find.byKey(const ValueKey('next-tile'))).height;
        }
        frames.add(await _sample(
            tester, boundary, dpr, 'hidden', 0, reveal.value, scroll.offset));

        Future<void> travel(String phase, VoidCallback start) async {
          // The ticker completes only after pump advances it. Awaiting
          // forward()/reverse() here would wait forever before the first frame.
          start();
          await tester.pump();
          for (var step = 1; step <= 30; step++) {
            if (step == 1 || step % 10 == 0) {}
            await tester.pump(const Duration(milliseconds: 16));
            scroll.jumpTo(_initialScroll + _scrollTravel * reveal.value);
            await tester.pump();
            frames.add(await _sample(tester, boundary, dpr, phase, step,
                reveal.value, scroll.offset));
          }
          // The final handoff and several subsequent painted frames are part
          // of the contract; an endpoint jump is not visible at t=0.99 alone.
          for (var step = 31; step <= 34; step++) {
            await tester.pump(const Duration(milliseconds: 16));
            frames.add(await _sample(tester, boundary, dpr, '$phase-settled',
                step, reveal.value, scroll.offset));
          }
        }

        await travel('show', () => clock.forward());
        await travel('hide', () => clock.reverse());
        traces[scenario.name] = frames;

        expect(frames.first.current.mass, greaterThan(1000),
            reason: scenario.name);
        expect(frames.every((frame) => frame.current.mass > 1000), isTrue,
            reason: '${scenario.name}: current glyph was missing in a frame');
        expect(
            frames.every((frame) => scenario.nextHasText
                ? frame.next.mass > 1000
                : frame.next.mass < 1000),
            isTrue,
            reason: '${scenario.name}: next-row fixture is not isolated');
        expect(_spread(frames.map((frame) => frame.current.rowHeight)),
            lessThan(.02),
            reason: '${scenario.name}: current tile itself changed height');
        expect(
            _spread(frames.map((frame) => frame.next.rowHeight)), lessThan(.02),
            reason: '${scenario.name}: next tile itself changed height');

        // Two separate time labels expand when the next row has text. With
        // a blank row only the current label expands. Compare painted ink to
        // each row's own measured rect rather than assuming equal velocities.
        final origin = frames.first;
        final shown = frames.lastWhere((frame) => frame.phase == 'show');
        final labelExtent = shown.current.rowTop -
            origin.current.rowTop +
            shown.scroll -
            origin.scroll;
        expect(labelExtent, greaterThan(10), reason: scenario.name);
        for (final frame in frames) {
          final scrolled = frame.scroll - origin.scroll;
          expect(
              frame.current.rowTop,
              closeTo(
                  origin.current.rowTop + labelExtent * frame.reveal - scrolled,
                  .08),
              reason: '${scenario.name}: current layout trajectory changed at '
                  '${frame.phase} ${frame.step}');
          expect(
              frame.next.rowTop,
              closeTo(
                  origin.next.rowTop +
                      labelExtent *
                          frame.reveal *
                          (scenario.nextHasText ? 2 : 1) -
                      scrolled,
                  .08),
              reason: '${scenario.name}: next layout trajectory changed at '
                  '${frame.phase} ${frame.step}');
        }

        // The next glyph is permitted to move with its row. Its *position
        // inside that row* and its horizontal ink origin must not oscillate.
        // Record the filter/scale contrasts separately: a static difference
        // between controls is not evidence that the reveal caused trembling.
        expect(_spread(frames.map((frame) => frame.current.x)), lessThan(.9),
            reason: '${scenario.name}: current glyph jumped horizontally');
        expect(_spread(frames.map((frame) => frame.current.yWithinRow)),
            lessThan(.9),
            reason: '${scenario.name}: current glyph moved inside its row');
        if (scenario.nextHasText) {
          expect(_spread(frames.map((frame) => frame.next.x)), lessThan(.9),
              reason: '${scenario.name}: next glyph jumped horizontally');
          expect(_spread(frames.map((frame) => frame.next.yWithinRow)),
              lessThan(.9),
              reason: '${scenario.name}: next glyph moved inside its row');
        }
        for (final phase in ['show-settled', 'hide-settled']) {
          final stable = frames.where((frame) => frame.phase == phase).toList();
          expect(
              stable.map((frame) => frame.current.hash).toSet(), hasLength(1),
              reason: '${scenario.name}: current ink changed after $phase');
          expect(stable.map((frame) => frame.next.hash).toSet(), hasLength(1),
              reason: '${scenario.name}: next ink changed after $phase');
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        reveal.dispose();
        clock.dispose();
        scroll.dispose();
        position.dispose();
        settings.dispose();
      }
    }

    // The only material difference between these two cases is the text and
    // therefore the extra timestamp-reveal row immediately below the singer.
    final blank = traces['blank-natural']!;
    final text = traces['text-filtered']!;
    final matchedBlank = traces['blank-matched']!;
    expect(blank.length, text.length);
    expect(matchedBlank.first.next.rowHeight,
        closeTo(text.first.next.rowHeight, .02),
        reason:
            'Matched blank controls for the original blank/text row height');
    for (var i = 0; i < blank.length; i++) {
      expect(blank[i].current.rowTop, closeTo(text[i].current.rowTop, .02),
          reason: 'The current layout differs before inspecting the next row');
      expect(blank[i].scroll, closeTo(text[i].scroll, .02));
      expect(
          matchedBlank[i].current.rowTop, closeTo(text[i].current.rowTop, .02));
    }

    // Optional exact frame data for a targeted local run. Callers should set
    // this to a directory under tool/qa-local; normal test runs write nothing.
    const output = String.fromEnvironment('DAN_LYRIC_NEXT_ROW_RENDER');
    if (output.isNotEmpty) {
      await tester.runAsync(() async {
        final directory = Directory(output);
        await directory.create(recursive: true);
        await File('${directory.path}/frames.json').writeAsString(jsonEncode({
          'dpr': dpr,
          'curve': 'LyricMotion.curve',
          'durationMs': LyricMotion.lineDuration.inMilliseconds,
          'cases': {
            for (final entry in traces.entries)
              entry.key: entry.value.map((frame) => frame.toJson()).toList(),
          },
        }));
      });
    }
    expect(tester.takeException(), isNull);
  });
}
