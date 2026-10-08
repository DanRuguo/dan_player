import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

// Native Windows capture. Supply an absolute workspace QA directory with
// --dart-define=DAN_LYRIC_CONTENT_MOTION_OUTPUT=.../tool/qa-local/<case>.
// The production row, scroll, filter, word and entrance clocks remain live;
// no replacement animation or manually advanced controller is used here.
class _Word extends SyncLyricWord {
  _Word(int line, int part, String text)
      : super(Duration(seconds: line * 20 + part * 6),
            const Duration(seconds: 6), text);
}

class _TimedLine extends SyncLyricLine {
  _TimedLine(int index)
      : super(
          Duration(seconds: index * 20),
          const Duration(seconds: 20),
          [
            _Word(index, 0, '’Cause this '),
            _Word(index, 1, 'is all we '),
            _Word(index, 2, 'know $index'),
          ],
          '这就是我们所知道的一切，下一段歌词仍然完整呈现 $index',
        ) {
    romanization = 'Cause this is all we know, and what comes after $index';
  }
}

class _MotionLyrics extends Lyric {
  _MotionLyrics({required bool blankBelow})
      : super([
          for (var index = 0; index < 12; index++)
            if (index == 5 && blankBelow)
              LrcLine(Duration(seconds: index * 20), '',
                  isBlank: true, length: Duration.zero)
            else
              _TimedLine(index),
        ]);
}

Map<String, double> _rect(Rect value) => {
      'left': value.left,
      'top': value.top,
      'width': value.width,
      'height': value.height,
    };

Rect _union3(Rect first, Rect second, Rect third) => Rect.fromLTRB(
      math.min(first.left, math.min(second.left, third.left)),
      math.min(first.top, math.min(second.top, third.top)),
      math.max(first.right, math.max(second.right, third.right)),
      math.max(first.bottom, math.max(second.bottom, third.bottom)),
    );

Rect _sourceRect(Rect logical, double dpr, ui.Image image) {
  final left = (logical.left * dpr).floor().clamp(0, image.width);
  final top = (logical.top * dpr).floor().clamp(0, image.height);
  final right = (logical.right * dpr).ceil().clamp(left, image.width);
  final bottom = (logical.bottom * dpr).ceil().clamp(top, image.height);
  return Rect.fromLTRB(
      left.toDouble(), top.toDouble(), right.toDouble(), bottom.toDouble());
}

Map<String, Object?> _ink(Uint8List rgba, ui.Image image, Rect source) {
  var mass = 0.0, momentX = 0.0, momentY = 0.0;
  for (var y = source.top.toInt(); y < source.bottom.toInt(); y++) {
    for (var x = source.left.toInt(); x < source.right.toInt(); x++) {
      final offset = (y * image.width + x) * 4;
      // The fixture uses a white page and dark/pink production theme text.
      final weight =
          (765 - rgba[offset] - rgba[offset + 1] - rgba[offset + 2]) / 3.0;
      if (weight <= 0) continue;
      mass += weight;
      momentX += x * weight;
      momentY += y * weight;
    }
  }
  return {
    'mass': mass,
    'x': mass == 0 ? null : momentX / mass,
    'y': mass == 0 ? null : momentY / mass,
  };
}

Future<void> _saveCrop(ui.Image image, Rect source, File file) async {
  if (source.isEmpty) return;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
      image,
      source,
      Rect.fromLTWH(0, 0, source.width, source.height),
      Paint()..filterQuality = FilterQuality.none);
  final picture = recorder.endRecording();
  final crop =
      await picture.toImage(source.width.toInt(), source.height.toInt());
  try {
    final png = await crop.toByteData(format: ui.ImageByteFormat.png);
    await file.writeAsBytes(png!.buffer.asUint8List(), flush: true);
  } finally {
    crop.dispose();
    picture.dispose();
  }
}

Finder _row(WidgetTester tester, LyricLine line) => find.byWidgetPredicate(
    (widget) => widget is LyricViewTile && identical(widget.line, line));

Rect? _primaryRect(WidgetTester tester, Finder row) {
  final paint = find.descendant(
      of: row,
      matching: find.byWidgetPredicate((widget) =>
          widget is CustomPaint &&
          widget.painter is LyricWordHighlightPainter));
  if (paint.evaluate().isEmpty) return null;
  final custom = tester.widget<CustomPaint>(paint.first);
  final painter = custom.painter! as LyricWordHighlightPainter;
  final render = tester.renderObject<RenderBox>(paint.first);
  return MatrixUtils.transformRect(
      render.getTransformTo(null), painter.paintedTextBounds);
}

Rect? _timestampRect(WidgetTester tester, Finder row) {
  final text = find.descendant(
      of: row, matching: find.byKey(const ValueKey('lyric-line-timestamp')));
  return text.evaluate().isEmpty ? null : tester.getRect(text.first);
}

double _horizontalAnchor(Map<String, double> rect, LyricTextAlign alignment) =>
    switch (alignment) {
      LyricTextAlign.left => rect['left']!,
      LyricTextAlign.center => rect['left']! + rect['width']! / 2,
      LyricTextAlign.right => rect['left']! + rect['width']!,
    };

double _horizontalAnchorAt(Map<String, double> rect, double alignmentX) =>
    rect['left']! + rect['width']! * ((alignmentX + 1) / 2);

Map<String, Object?> _motion(WidgetTester tester, Finder row) {
  final lineMotion =
      find.descendant(of: row, matching: find.byType(LyricLineMotion));
  final motion = tester.widget<LyricLineMotion>(lineMotion.first);
  final follow = tester.widget<LyricFollowEffects>(
      find.ancestor(of: row, matching: find.byType(LyricFollowEffects)).first);
  final scaleTransform =
      find.descendant(of: lineMotion, matching: find.byType(Transform));
  final timedPaint = find.descendant(
      of: row,
      matching: find.byWidgetPredicate((widget) =>
          widget is CustomPaint &&
          widget.painter is LyricWordHighlightPainter));
  final fontMorph =
      find.descendant(of: row, matching: find.byType(LyricFontMorph));
  final paintedFontSize = timedPaint.evaluate().isEmpty
      ? null
      : (tester.widget<CustomPaint>(timedPaint.first).painter!
              as LyricWordHighlightPainter)
          .paintedFontSize;
  return {
    'targetScale': motion.scale,
    'paintedScale': scaleTransform.evaluate().isEmpty
        ? null
        : tester.widget<Transform>(scaleTransform.first).transform.storage[0],
    'paintedAlignmentX': scaleTransform.evaluate().isEmpty
        ? null
        : tester
            .widget<Transform>(scaleTransform.first)
            .alignment
            ?.resolve(TextDirection.ltr)
            .x,
    'targetOpacity': motion.opacity,
    'targetFontSize': motion.presentation.fontSize,
    'paintedFontSize': paintedFontSize,
    'fontMorphProgress': fontMorph.evaluate().isEmpty
        ? null
        : tester.widget<LyricFontMorph>(fontMorph.first).progress,
    'paintedFontSizes': [
      for (final paint in timedPaint.evaluate())
        ((paint.widget as CustomPaint).painter! as LyricWordHighlightPainter)
            .paintedFontSize,
    ],
    'targetTranslationFontSize': motion.presentation.translationFontSize,
    'targetAlignmentX': motion.presentation.alignment.x,
    'baseBlurSigma': follow.blur,
    'animatedBlurSigma': follow.blurAnimation?.value,
    'followClock': follow.clock.value,
    'followOffset': follow.transition?.sample(follow.clock.value).offset,
  };
}

Future<Map<String, Object?>> _capture(
    WidgetTester tester,
    GlobalKey boundary,
    _MotionLyrics lyric,
    LyricViewController settings,
    File fullFile,
    File pairFile,
    int activeIndex,
    double mediaPosition,
    int frame,
    int elapsedMs,
    int wallMs,
    {bool capturePixels = true}) async {
  Finder row(int index) => _row(tester, lyric.lines[index]);
  final current = row(activeIndex),
      next = row(activeIndex + 1),
      following = row(activeIndex + 2),
      far = row(activeIndex + 4);
  expect(current, findsOneWidget);
  expect(next, findsOneWidget);
  final currentTile = tester.widget<LyricViewTile>(current);
  final nextTile = tester.widget<LyricViewTile>(next);
  expect(currentTile.distance, 0);
  expect(nextTile.distance, 1);
  final origin = tester.getTopLeft(find.byKey(boundary));
  Rect local(Rect rect) => rect.shift(-origin);
  final currentRect = local(tester.getRect(current));
  final nextRect = local(tester.getRect(next));
  final followingRect = local(tester.getRect(following));
  final currentInkRect = _primaryRect(tester, current);
  final nextInkRect = _primaryRect(tester, next);
  final followingInkRect = _primaryRect(tester, following);
  final currentTimestampRect = _timestampRect(tester, current);
  final nextTimestampRect = _timestampRect(tester, next);
  final pairRect = _union3(currentRect, nextRect, followingRect).inflate(16);
  final scroll = tester
      .widget<CustomScrollView>(
          find.byKey(const ValueKey('vertical-lyric-scroll')))
      .controller!;
  final entrance = tester.widget<AnimatedBuilder>(find
      .descendant(
          of: find.byType(AppEntrance), matching: find.byType(AnimatedBuilder))
      .first);
  final metadata = <String, Object?>{
    'frame': frame,
    'activeIndex': activeIndex,
    'mediaPositionSeconds': mediaPosition,
    'pumpElapsedMs': elapsedMs,
    'wallElapsedMs': wallMs,
    'showTimestamps': settings.showTimestamps,
    'showTranslation': settings.showTranslation,
    'showRomanization': settings.showRomanization,
    'lyricFontSize': settings.lyricFontSize,
    'translationFontSize': settings.translationFontSize,
    'lyricTextAlign': settings.lyricTextAlign.name,
    'entranceProgress': (entrance.animation as Animation<double>).value,
    'scrollPixels': scroll.offset,
    'scrollMin': scroll.position.minScrollExtent,
    'scrollMax': scroll.position.maxScrollExtent,
    'scrollViewport': scroll.position.viewportDimension,
    'current': {
      'row': _rect(currentRect),
      'primary': currentInkRect == null ? null : _rect(local(currentInkRect)),
      'timestamp': currentTimestampRect == null
          ? null
          : _rect(local(currentTimestampRect)),
      'motion': _motion(tester, current),
    },
    'next': {
      'row': _rect(nextRect),
      'primary': nextInkRect == null ? null : _rect(local(nextInkRect)),
      'timestamp':
          nextTimestampRect == null ? null : _rect(local(nextTimestampRect)),
      'motion': _motion(tester, next),
    },
    'following': {
      'row': _rect(followingRect),
      'primary':
          followingInkRect == null ? null : _rect(local(followingInkRect)),
    },
    'farBlurAndScale': _motion(tester, far),
    'fullImage': capturePixels ? path.basename(fullFile.path) : null,
    'pairImage': capturePixels ? path.basename(pairFile.path) : null,
  };
  if (!capturePixels) return metadata;
  final rendered = await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage(pixelRatio: tester.view.devicePixelRatio);
    try {
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await fullFile.writeAsBytes(png!.buffer.asUint8List(), flush: true);
      final logicalBounds = Rect.fromLTWH(
          0,
          0,
          image.width / tester.view.devicePixelRatio,
          image.height / tester.view.devicePixelRatio);
      final pair = _sourceRect(pairRect.intersect(logicalBounds),
          tester.view.devicePixelRatio, image);
      await _saveCrop(image, pair, pairFile);
      Rect region(Rect value) => _sourceRect(
          value.intersect(logicalBounds), tester.view.devicePixelRatio, image);
      return <String, Object?>{
        'imageWidth': image.width,
        'imageHeight': image.height,
        'devicePixelRatio': tester.view.devicePixelRatio,
        'pairCrop': _rect(pair),
        'pageInk': _ink(
            raw,
            image,
            Rect.fromLTWH(
                0, 0, image.width.toDouble(), image.height.toDouble())),
        'pairInk': _ink(raw, image, pair),
        'currentInk': _ink(raw, image, region(currentRect)),
        'nextInk': _ink(raw, image, region(nextRect)),
        'followingInk': _ink(raw, image, region(followingRect)),
        'currentPrimaryInk': currentInkRect == null
            ? null
            : _ink(raw, image, region(local(currentInkRect))),
        'nextPrimaryInk': nextInkRect == null
            ? null
            : _ink(raw, image, region(local(nextInkRect))),
        'currentTimestampInk': currentTimestampRect == null
            ? null
            : _ink(raw, image, region(local(currentTimestampRect))),
        'nextTimestampInk': nextTimestampRect == null
            ? null
            : _ink(raw, image, region(local(nextTimestampRect))),
      };
    } finally {
      image.dispose();
    }
  });
  metadata.addAll(rendered!);
  return metadata;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real lyric content, type size and alignment motion on Windows',
      (tester) async {
    const target = String.fromEnvironment('DAN_LYRIC_CONTENT_MOTION_OUTPUT');
    const focusOnly = bool.fromEnvironment('DAN_LYRIC_MOTION_FOCUS_ONLY');
    const clickOnly = bool.fromEnvironment('DAN_LYRIC_CLICK_ONLY');
    const windowMode = String.fromEnvironment('DAN_LYRIC_WINDOW_MODE',
        defaultValue: 'normal');
    final normalized = path.normalize(target).replaceAll('\\', '/');
    expect(path.isAbsolute(target), isTrue,
        reason: 'Supply an absolute QA output directory');
    expect(normalized.toLowerCase().contains('/tool/qa-local/'), isTrue,
        reason: 'Captures must stay under the workspace tool/qa-local');
    final output = Directory(target);
    await tester.runAsync(() => output.create(recursive: true));
    if (clickOnly) {
      await windowManager.ensureInitialized();
      if (windowMode == 'maximized') await windowManager.maximize();
      if (windowMode == 'fullscreen') await windowManager.setFullScreen(true);
    }
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    final manifest = <Map<String, Object?>>[];
    final boundary = GlobalKey();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(-10, -10));

    for (final blankBelow in clickOnly ? [false] : [true, false]) {
      final lyric = _MotionLyrics(blankBelow: blankBelow);
      final settings = LyricViewController(
          preferences: NowPlayingPagePreference.fromMap({
        'showLyricTranslation': false,
        'showLyricRomanization': false,
        'showLyricTimestamps': false,
      }));
      final rendering = ValueNotifier(const RenderingPreferences());
      final source = StreamController<double>.broadcast(sync: true);
      var position = 85.15;
      var activeIndex = 4;
      final condition = blankBelow ? 'next-blank' : 'next-text';
      final conditionDir = Directory(path.join(output.path, condition));
      await tester.runAsync(() => conditionDir.create(recursive: true));

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        scrollBehavior: const DanPlayerScrollBehavior(),
        theme: ThemeData(
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback,
          colorScheme:
              ColorScheme.fromSeed(seedColor: const Color(0xffb83767)).copyWith(
            surface: Colors.white,
            onSurface: const Color(0xff141414),
            primary: const Color(0xffb02050),
            onSecondaryContainer: const Color(0xff141414),
          ),
        ),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox(
                width: 700,
                height: 620,
                child: ColoredBox(
                  color: Colors.white,
                  child: RenderingPreferencesScope(
                    preferences: rendering,
                    child: ChangeNotifierProvider.value(
                      value: settings,
                      child: AppEntranceScope(
                        child: AppEntrance(
                          identity: 'lyric-content-motion',
                          child: VerticalLyricScrollView(
                            lyric: lyric,
                            positionStream: source.stream,
                            readPosition: () => position,
                            onSeek: (seconds) {
                              if (!clickOnly) return;
                              position = seconds;
                              activeIndex = lyric.lines.indexWhere((line) =>
                                  line.start.inMilliseconds / 1000 == seconds);
                              source.add(position);
                            },
                            playing: true,
                            springLyrics: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byType(VerticalLyricScrollView), findsOneWidget);
      expect(find.byType(StretchingOverscrollIndicator), findsNothing);
      if (focusOnly) await tester.pump(const Duration(milliseconds: 800));

      Future<void> trace(String label,
          {VoidCallback? change,
          bool capturePixels = true,
          int pixelStride = 1}) async {
        final directory = Directory(path.join(conditionDir.path, label));
        await tester.runAsync(() => directory.create(recursive: true));
        final frames = <Map<String, Object?>>[];
        final clock = Stopwatch()..start();
        Future<void> record(int frame, int elapsed) async {
          final name = frame < 0 ? 'before' : frame.toString().padLeft(3, '0');
          final samplePixels = capturePixels &&
              (pixelStride == 1 ||
                  frame < 0 ||
                  frame == 43 ||
                  (frame > 0 && frame % pixelStride == 0));
          frames.add(await _capture(
              tester,
              boundary,
              lyric,
              settings,
              File(path.join(directory.path, 'full-$name.png')),
              File(path.join(directory.path, 'current-next-$name.png')),
              activeIndex,
              position,
              frame,
              elapsed,
              clock.elapsedMilliseconds,
              capturePixels: samplePixels));
        }

        if (change != null) {
          await record(-1, -1);
          change();
          await tester.pump();
        }
        for (var frame = 0; frame <= 43; frame++) {
          if (frame > 0) {
            await tester.pump(Duration(milliseconds: frame <= 40 ? 16 : 80));
          }
          await record(
              frame, frame <= 40 ? frame * 16 : 640 + (frame - 40) * 80);
        }
        if (label.endsWith('-geometry')) {
          double anchor(Map<String, Object?> frame) {
            final current = frame['current'] as Map<String, Object?>;
            final row = current['row'] as Map<String, double>;
            return row['top']! + row['height']! * .34;
          }

          final firstAnchor = anchor(frames.first);
          final expanding = label.contains('-show-');
          for (var index = 0; index < frames.length; index++) {
            expect(anchor(frames[index]), closeTo(firstAnchor, .5),
                reason: '$condition/$label frame $index painted off-anchor');
            if (index == 0) continue;
            final previous = frames[index - 1]['scrollPixels'] as double;
            final current = frames[index]['scrollPixels'] as double;
            expect(
                expanding ? current >= previous - .1 : current <= previous + .1,
                isTrue,
                reason: '$condition/$label frame $index reversed scroll');
          }
        }
        if (label == 'page-entry') {
          final first = (frames.first['current'] as Map<String, Object?>)['row']
              as Map<String, double>;
          for (final frame in frames) {
            final row = (frame['current'] as Map<String, Object?>)['row']
                as Map<String, double>;
            expect(row['left'], closeTo(first['left']!, .5),
                reason: '$condition page entrance moved horizontally');
          }
        }
        if (label == 'timestamps-show' || label.startsWith('align-')) {
          for (var index = 0; index < frames.length; index++) {
            final frame = frames[index];
            for (final rowName in ['current', 'next']) {
              final row = frame[rowName] as Map<String, Object?>;
              final primary = row['primary'] as Map<String, double>?;
              final timestamp = row['timestamp'] as Map<String, double>?;
              if (primary == null || timestamp == null) continue;
              final motion = row['motion'] as Map<String, Object?>;
              final alignmentX = motion['paintedAlignmentX'] as double?;
              expect(alignmentX, isNotNull,
                  reason: '$condition/$label $rowName frame $index');
              expect(_horizontalAnchorAt(timestamp, alignmentX!),
                  closeTo(_horizontalAnchorAt(primary, alignmentX), 12),
                  reason: '$condition/$label $rowName frame $index '
                      'timestamp left its lyric alignment');
            }
          }
          final finalCurrent = frames.last['current'] as Map<String, Object?>;
          final primary = finalCurrent['primary'] as Map<String, double>;
          final timestamp = finalCurrent['timestamp'] as Map<String, double>?;
          expect(timestamp, isNotNull,
              reason: '$condition/$label current timestamp is absent');
          expect(_horizontalAnchor(timestamp!, settings.lyricTextAlign),
              closeTo(_horizontalAnchor(primary, settings.lyricTextAlign), 12),
              reason: '$condition/$label settled timestamp position');
          final timestampInk =
              frames.last['currentTimestampInk'] as Map<String, Object?>?;
          expect((timestampInk?['mass'] as double?) ?? 0, greaterThan(0),
              reason: '$condition/$label settled timestamp has no pixels');
        }
        if (label.startsWith('font-')) {
          double width(Map<String, Object?> frame) {
            final current = frame['current'] as Map<String, Object?>;
            return (current['primary'] as Map<String, double>)['width']!;
          }

          double anchor(Map<String, Object?> frame) {
            final current = frame['current'] as Map<String, Object?>;
            final row = current['row'] as Map<String, double>;
            return row['top']! + row['height']! * .34;
          }

          final firstWidth = width(frames.first);
          final finalWidth = width(frames.last);
          final growing = label == 'font-increase';
          expect(growing ? finalWidth - firstWidth : firstWidth - finalWidth,
              greaterThan(2),
              reason: '$condition/$label primary glyph size did not change');
          double morphProgress(Map<String, Object?> frame) {
            final current = frame['current'] as Map<String, Object?>;
            final motion = current['motion'] as Map<String, Object?>;
            return motion['fontMorphProgress'] as double;
          }

          final firstFont = morphProgress(frames.first);
          final finalFont = morphProgress(frames.last);
          expect(firstFont, 1);
          expect(finalFont, 1);
          expect(
              frames.skip(1).take(frames.length - 2).any((frame) {
                final progress = morphProgress(frame);
                final current = frame['current'] as Map<String, Object?>;
                final motion = current['motion'] as Map<String, Object?>;
                final sizes = motion['paintedFontSizes'] as List<double>;
                return progress > .01 &&
                    progress < .99 &&
                    sizes.length == 2 &&
                    (sizes.first - sizes.last).abs() > .1;
              }),
              isTrue,
              reason: '$condition/$label did not blend fixed font endpoints');
          final firstAnchor = anchor(frames.first);
          for (var index = 0; index < frames.length; index++) {
            expect(anchor(frames[index]), closeTo(firstAnchor, 1),
                reason: '$condition/$label frame $index jumped vertically');
            if (index == 0) continue;
            final delta = width(frames[index]) - width(frames[index - 1]);
            expect(growing ? delta >= -.6 : delta <= .6, isTrue,
                reason: '$condition/$label frame $index reversed font size');
          }
        }
        if (label.startsWith('align-')) {
          double alignment(Map<String, Object?> frame) {
            final current = frame['current'] as Map<String, Object?>;
            final motion = current['motion'] as Map<String, Object?>;
            return motion['paintedAlignmentX'] as double;
          }

          double left(Map<String, Object?> frame, String part) {
            final current = frame['current'] as Map<String, Object?>;
            return (current[part] as Map<String, double>)['left']!;
          }

          final first = alignment(frames.first);
          final last = alignment(frames.last);
          final movingRight = last > first;
          expect((last - first).abs(), greaterThan(.9),
              reason: '$condition/$label alignment target did not change');
          expect(
              frames.skip(1).take(frames.length - 2).any((frame) {
                final value = alignment(frame);
                return value > math.min(first, last) + .01 &&
                    value < math.max(first, last) - .01;
              }),
              isTrue,
              reason: '$condition/$label did not paint intermediate alignment');
          final primaryTravel =
              left(frames.last, 'primary') - left(frames.first, 'primary');
          final timestampTravel =
              left(frames.last, 'timestamp') - left(frames.first, 'timestamp');
          expect(movingRight ? primaryTravel : -primaryTravel, greaterThan(12),
              reason: '$condition/$label primary text did not move');
          expect(
              movingRight ? timestampTravel : -timestampTravel, greaterThan(12),
              reason: '$condition/$label timestamp did not move');
          for (var index = 1; index < frames.length; index++) {
            final previous = alignment(frames[index - 1]);
            final current = alignment(frames[index]);
            expect(
                movingRight
                    ? current >= previous - .01
                    : current <= previous + .01,
                isTrue,
                reason: '$condition/$label frame $index reversed alignment');
          }
        }
        expect(tester.takeException(), isNull, reason: '$condition/$label');
        await tester.runAsync(
            () => File(path.join(directory.path, 'frames.json')).writeAsString(
                const JsonEncoder.withIndent('  ').convert({
                  'condition': condition,
                  'action': label,
                  'blankBelow': blankBelow,
                  'capturedAt': DateTime.now().toUtc().toIso8601String(),
                  'frames': frames,
                }),
                flush: true));
        manifest.add({
          'condition': condition,
          'action': label,
          'frameCount': frames.length,
          'directory': directory.path,
        });
      }

      if (clickOnly) {
        await tester.pump(const Duration(milliseconds: 800));
        final target = find.byWidgetPredicate(
            (widget) => widget is LyricViewTile &&
                identical(widget.line, lyric.lines[5]));
        final point = tester.getCenter(target);
        await mouse.moveTo(point);
        await tester.pump(const Duration(milliseconds: 300));
        await mouse.down(point);
        await mouse.up();
        await tester.pump();
        expect(activeIndex, 5);
        await trace('click-focus');
        await tester.pumpWidget(const SizedBox.shrink());
        await source.close();
        settings.dispose();
        rendering.dispose();
        continue;
      }
      if (!focusOnly) await trace('page-entry');
      for (final action in focusOnly
          ? ['timestamps']
          : ['timestamps', 'translation', 'romanization']) {
        void set(bool value) {
          switch (action) {
            case 'timestamps':
              settings.setShowTimestamps(value);
            case 'translation':
              settings.setShowTranslation(value);
            case 'romanization':
              settings.setShowRomanization(value);
          }
        }

        await trace('$action-show-geometry',
            change: () => set(true), capturePixels: false);
        await trace('$action-hide-geometry',
            change: () => set(false), capturePixels: false);
        await trace('$action-show', change: () => set(true));
        if (action == 'timestamps') {
          await trace('font-increase',
              change: settings.increaseFontSize, pixelStride: 4);
          await trace('font-decrease',
              change: settings.decreaseFontSize, pixelStride: 4);
          await trace('align-left-center',
              change: settings.switchLyricTextAlign, pixelStride: 4);
          await trace('align-center-right',
              change: settings.switchLyricTextAlign, pixelStride: 4);
          await trace('align-right-left',
              change: settings.switchLyricTextAlign, pixelStride: 4);
        }
        await trace('$action-hide', change: () => set(false));
      }
      if (!focusOnly) {
        await trace('advance-to-next-line', change: () {
          position = 105.15;
          activeIndex = 5;
          source.add(position);
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await source.close();
      settings.dispose();
      rendering.dispose();
    }
    await mouse.removePointer();

    await tester.runAsync(
        () => File(path.join(output.path, 'manifest.json')).writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'harness':
                  'production VerticalLyricScrollView and DanPlayerScrollBehavior',
              'note': 'Upcoming rows 1-3 are deliberately clear in production; the '
                  'far row records nonzero blur while the next row records scale.',
              'cases': manifest,
            }),
            flush: true));
  });
}
