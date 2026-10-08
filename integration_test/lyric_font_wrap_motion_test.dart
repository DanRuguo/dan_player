import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_fractional_filter.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

// Use the production lyric row and font transition on Windows. The middle
// Japanese line is laid out once on either side of an actual wrap threshold;
// the following row exposes any one-frame height jump.
const _wrappingText = '音もない世界、何を見てるの?';
const _outputPath = String.fromEnvironment('DAN_LYRIC_FONT_WRAP_OUTPUT');

Future<void> _saveFrame(GlobalKey boundary, File file) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await render.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  } finally {
    image.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('font transition crosses a Japanese wrap without row jumping',
      (tester) async {
    final normalized = path.normalize(_outputPath).replaceAll('\\', '/');
    expect(path.isAbsolute(_outputPath), isTrue);
    expect(normalized.toLowerCase().contains('/tool/qa-local/'), isTrue);
    final output = Directory(_outputPath);
    await tester.runAsync(() => output.create(recursive: true));
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf')))
        .load();

    final paragraph = TextPainter(
      text: const TextSpan(
        text: _wrappingText,
        style: TextStyle(
          fontFamily: danEmbeddedFontFamily,
          fontSize: 22 * LyricMotion.focusedFontScale,
          fontWeight: LyricMotion.focusedFontWeight,
          height: 1.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final oldWidth = paragraph.maxIntrinsicWidth;
    paragraph.text = const TextSpan(
      text: _wrappingText,
      style: TextStyle(
        fontFamily: danEmbeddedFontFamily,
        fontSize: 23 * LyricMotion.focusedFontScale,
        fontWeight: LyricMotion.focusedFontWeight,
        height: 1.3,
      ),
    );
    paragraph.layout();
    final newWidth = paragraph.maxIntrinsicWidth;
    paragraph.dispose();
    expect(newWidth, greaterThan(oldWidth + 4));
    // LyricViewTile has 12px padding and a 7px ink guard on each side.
    final tileWidth = (oldWidth + newWidth) / 2 + 24 + 14;

    final settings = LyricViewController(
      preferences: NowPlayingPagePreference.fromMap(const {
        'lyricFontSize': 22,
        'translationFontSize': 18,
        'showLyricTimestamps': true,
        'showLyricTranslation': true,
        'showLyricRomanization': true,
      }),
    );
    final position = ValueNotifier(Duration.zero);
    final lines = <LrcLine>[
      LrcLine(const Duration(seconds: 16), '錆び付いた心、┃锈迹斑斑的心灵', isBlank: false),
      LrcLine(const Duration(seconds: 19), '$_wrappingText┃寂静无比的世界, 你到底看见了什么?',
          isBlank: false)
        ..romanization = 'o to mo na i se ka i, na ni wo mi te ru no?',
      LrcLine(const Duration(seconds: 24), 'またねを言える顔を探すよ┃寻找着能将再见说出口的表情',
          isBlank: false),
    ];
    addTearDown(() {
      settings.dispose();
      position.dispose();
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: danEmbeddedFontFamily),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: Colors.white,
              child: SizedBox(
                width: tileWidth,
                child: ChangeNotifierProvider.value(
                  value: settings,
                  child: Builder(
                      builder: (context) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var index = 0; index < lines.length; index++)
                                // LyricFollowEffects supplies this scope in the
                                // real lyric column. Keep native raster sampling
                                // identical while the font setting animates.
                                LyricFractionalFilterScope(
                                  sigma: 0,
                                  dpr: View.of(context).devicePixelRatio,
                                  enabled: true,
                                  repaintToken: (index, 0),
                                  child: LyricViewTile(
                                    key: ValueKey('line-$index'),
                                    line: lines[index],
                                    position: position,
                                    opacity: 1,
                                    distance: index,
                                    reducedMotion: false,
                                    onTap: () {},
                                  ),
                                ),
                            ],
                          )),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final wrappingRow = find.byKey(const ValueKey('line-1'));
    final followingRow = find.byKey(const ValueKey('line-2'));
    expect(wrappingRow, findsOneWidget);
    expect(followingRow, findsOneWidget);
    final frames = <Map<String, Object?>>[];

    Future<void> record(String action, int frame) async {
      final wrapped = tester.getRect(wrappingRow);
      final following = tester.getRect(followingRow);
      frames.add({
        'action': action,
        'frame': frame,
        'wrappingHeight': wrapped.height,
        'followingTop': following.top,
      });
      if (frame % 4 != 0 && frame != 31) return;
      final file = File(path.join(
          output.path, '$action-${frame.toString().padLeft(2, '0')}.png'));
      await tester.runAsync(() => _saveFrame(boundary, file));
    }

    for (final action in ['increase', 'decrease']) {
      await record(action, -1);
      if (action == 'increase') {
        settings.increaseFontSize();
      } else {
        settings.decreaseFontSize();
      }
      await tester.pump();
      for (var frame = 0; frame <= 31; frame++) {
        if (frame > 0) await tester.pump(const Duration(milliseconds: 16));
        await record(action, frame);
      }
      await tester.pumpAndSettle();
      await record(action, 32);
      final sequence =
          frames.where((entry) => entry['action'] == action).toList();
      final heights =
          sequence.map((entry) => entry['wrappingHeight']! as double);
      final initialHeight = heights.first;
      final finalHeight = heights.last;
      expect((finalHeight - initialHeight).abs(), greaterThan(20),
          reason: '$action must actually cross the one/two-line threshold');
      var largestStep = 0.0;
      for (var index = 1; index < sequence.length; index++) {
        final previous = sequence[index - 1]['followingTop']! as double;
        final current = sequence[index]['followingTop']! as double;
        largestStep = math.max(largestStep, (current - previous).abs());
      }
      expect(largestStep, lessThan(10),
          reason: '$action moved the following lyric in one frame');
      expect(tester.takeException(), isNull);
    }
    await tester.runAsync(
        () => File(path.join(output.path, 'frames.json')).writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'tileWidth': tileWidth,
              'initialIntrinsicWidth': oldWidth,
              'finalIntrinsicWidth': newWidth,
              'frames': frames,
            }),
            flush: true));
  });
}
