import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _background = Color(0xff161419);
const _interludeStart = Duration(seconds: 15);
const _interludeLength = Duration(seconds: 12);

class _ContextLyrics extends Lyric {
  _ContextLyrics()
      : super([
          for (var index = 0; index < 3; index++) _longLine(index * 5, index),
          LrcLine(_interludeStart, '', isBlank: true, length: _interludeLength),
          for (var index = 0; index < 5; index++)
            _longLine(27 + index * 5, index + 3),
        ]);
}

LrcLine _longLine(int seconds, int index) => LrcLine(
    Duration(seconds: seconds),
    '風が運んだ長い物語を、いつまでも心の中で歌い続ける。'
    '夜が明けても遠い記憶を辿りながら、この道を歩いてゆこう。┃'
    '清风带来漫长的故事，旋律一直在心中回响。'
    '即使天色渐明，也沿着遥远的回忆继续向前走。 $index',
    isBlank: false,
    length: const Duration(seconds: 5))
  ..romanization = 'ka ze ga ha kon da na ga i mo no ga ta ri wo '
      'i tsu ma de mo ko ko ro no na ka de u ta i tsu zu ke ru '
      'yo ru ga a ke te mo to o i ki o ku wo ta do ri na ga ra';

Future<void> _inspect(WidgetTester tester, GlobalKey key,
    {required double dpr,
    required double seconds,
    required String name}) async {
  final dots = tester.renderObject<RenderBox>(find.byType(LyricTransitionTile));
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final transform = dots.getTransformTo(boundary);
  final pose = LyricMotion.interludePose(
      Duration(milliseconds: (seconds * 1000).round()) - _interludeStart,
      _interludeLength);
  final radius = 4.2 * pose.scale * transform[5] * dpr;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: dpr);
    try {
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
      for (var dot = 0; dot < 3; dot++) {
        final center = MatrixUtils.transformPoint(transform,
                dots.size.center(Offset(24 * (dot - 1) * pose.scale, 0))) *
            dpr;
        expect(center.dy - radius, greaterThan(24 * dpr),
            reason:
                'Inspect the current interlude inside the unfaded viewport');
        expect(center.dy + radius, lessThan(image.height - 24 * dpr));
        var mass = 0.0;
        var moment = 0.0;
        var lowest = 0;
        var highest = image.height;
        for (var y = (center.dy - radius - 3).floor();
            y <= (center.dy + radius + 3).ceil();
            y++) {
          for (var x = (center.dx - radius - 3).floor();
              x <= (center.dx + radius + 3).ceil();
              x++) {
            final at = (y * image.width + x) * 4;
            final ink = math.max(
                0, bytes[at] + bytes[at + 1] + bytes[at + 2] - (22 + 20 + 25));
            mass += ink;
            moment += ink * (y + .5);
            if (ink > 20) {
              lowest = math.max(lowest, y);
              highest = math.min(highest, y);
            }
          }
        }
        expect(mass, greaterThan(100),
            reason: '$name dot $dot must remain visible');
        expect(moment / mass, closeTo(center.dy, .3),
            reason: '$name dot $dot lower semicircle must retain its mass');
        expect(lowest + 1 - center.dy, greaterThan(radius - 1.5));
        expect(center.dy - highest, greaterThan(radius - 1.5));
      }
      final output = Platform.environment['DAN_LYRIC_INTERLUDE_CONTEXT_RENDER'];
      if (output != null) {
        await Directory(output).create(recursive: true);
        await File('$output/$name.png').writeAsBytes(
            (await image.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List());
      }
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
  });
  for (final scenario in [
    (width: 520.0, height: 600.0, dpr: 1.25),
    (width: 300.0, height: 360.0, dpr: 1.5),
  ]) {
    testWidgets(
        'interlude inside long surrounding paragraphs at ${scenario.width}',
        (tester) async {
      tester.view.devicePixelRatio = scenario.dpr;
      tester.view.physicalSize = Size(900 * scenario.dpr, 760 * scenario.dpr);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final settings = LyricViewController()
        ..lyricFontSize = 22
        ..translationFontSize = 18
        ..lyricTextAlign = LyricTextAlign.center;
      final positions = StreamController<double>.broadcast(sync: true);
      addTearDown(settings.dispose);
      addTearDown(positions.close);
      final imageKey = GlobalKey();
      var position = 14.9;
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark().copyWith(
              textTheme: ThemeData.dark()
                  .textTheme
                  .apply(fontFamily: danEmbeddedFontFamily)),
          home: Center(
              child: RepaintBoundary(
                  key: imageKey,
                  child: SizedBox(
                      width: scenario.width,
                      height: scenario.height,
                      child: ColoredBox(
                          color: _background,
                          child: Material(
                              type: MaterialType.transparency,
                              child: ChangeNotifierProvider.value(
                                  value: settings,
                                  child: VerticalLyricScrollView(
                                      lyric: _ContextLyrics(),
                                      positionStream: positions.stream,
                                      readPosition: () => position,
                                      onSeek: (_) {},
                                      springLyrics: true)))))))));
      await tester.pumpAndSettle();
      final longRows =
          tester.widgetList<LyricViewTile>(find.byType(LyricViewTile));
      expect(longRows.length, 9);
      expect(tester.getSize(find.byType(LyricViewTile).at(2)).height,
          greaterThan(200),
          reason:
              'The neighbors must wrap real primary/translation/phonetic text');
      position = 18.125;
      positions.add(position);
      await tester.pump();
      await tester.pump();
      final scroll = tester
          .widget<CustomScrollView>(
              find.byKey(const ValueKey('vertical-lyric-scroll')))
          .controller!;
      var previous = 0;
      for (final elapsed in [360, 540, 650, 720]) {
        await tester.pump(Duration(milliseconds: elapsed - previous));
        previous = elapsed;
        await _inspect(tester, imageKey,
            dpr: scenario.dpr,
            seconds: position,
            name: 'context-${scenario.width.toInt()}-spring-$elapsed');
      }
      await tester.pumpAndSettle();
      expect(scroll.position.isScrollingNotifier.value, isFalse);
      position = 26.85;
      positions.add(position);
      await tester.pump();
      await _inspect(tester, imageKey,
          dpr: scenario.dpr,
          seconds: position,
          name: 'context-${scenario.width.toInt()}-contracting');
      expect(tester.takeException(), isNull);
    });
  }
}
