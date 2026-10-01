import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/play_service/lyric_line_practice.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

class _Playback extends Fake implements PlaybackService {
  @override
  final segmentLoop = SegmentLoopController();
  @override
  int playbackSessionToken = 7;
  @override
  double length = 100;
  @override
  bool canUseSegmentLoop = true;
  int enables = 0, starts = 0;
  @override
  bool setSegmentLoopEnabled(bool value) {
    enables++;
    segmentLoop.setEnabled(value);
    return segmentLoop.enabled;
  }

  @override
  void start({bool recordIntent = true}) => starts++;
}

LrcLine _line(
        {int start = 10000, int length = 4000, String text = '听见雨落 🎵'}) =>
    LrcLine(Duration(milliseconds: start), text,
        isBlank: text.trim().isEmpty, length: Duration(milliseconds: length));
Lyric _lyric(LyricLine line) => Lrc([line], LrcSource.local);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['DAN_LINE_PRACTICE_RENDER_DIR'];
  setUpAll(() async {
    if (output != null &&
        !path.isWithin(
            path.join(Directory.current.parent.path, 'tool', 'qa-local'),
            output)) {
      throw StateError('Render output must be in workspace QA');
    }
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final korean = await File('C:/Windows/Fonts/malgun.ttf').readAsBytes();
    await (FontLoader('Malgun Gothic')
          ..addFont(Future.value(ByteData.sublistView(korean))))
        .load();
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  test('LRC uses displayed offset once and leaves authored data unchanged', () {
    final line = _line(start: 8500);
    expect(lyricLinePracticeRange(_lyric(line), line, 100),
        (start: 8.5, end: 12.5));
    expect(line.start.inMilliseconds, 8500);
    expect(line.length.inMilliseconds, 4000);
    expect(line.content, '听见雨落 🎵');
  });
  test('negative offset and EOF are clipped without stretching a short phrase',
      () {
    final line = _line(start: -2000);
    expect(lyricLinePracticeRange(_lyric(line), line, 100),
        (start: 0.0, end: 2.0));
    final tail = _line(start: 98000);
    expect(lyricLinePracticeRange(_lyric(tail), tail, 100),
        (start: 98.0, end: 100.0));
    expect(lyricLinePracticeRange(_lyric(tail), tail, 98.9), isNull);
    final short = _line(length: 999);
    expect(lyricLinePracticeRange(_lyric(short), short, 100), isNull);
  });
  test('zero-length LRC uses next distinct timestamp or the track end', () {
    final line = _line(length: 0);
    final lyric = Lrc([_line(start: 15000), line, _line(), _line(start: 12000)],
        LrcSource.local);
    expect(lyricLinePracticeRange(lyric, line, 100), (start: 10.0, end: 12.0));
    expect(lyricLinePracticeRange(_lyric(line), line, 15),
        (start: 10.0, end: 15.0));
  });
  test('word lyric range includes a final word beyond approximate line end',
      () {
    final lyric = Qrc.fromQrcText('[10000,2000]听(10000,2000)见(12000,2500)');
    final line = lyric.lines
        .whereType<QrcLine>()
        .firstWhere((line) => line.content.isNotEmpty);
    expect(lyricLinePracticeRange(lyric, line, 100), (start: 10.0, end: 14.5));
  });
  test('plain, blank, foreign line and invalid duration cannot become a loop',
      () {
    final plain = PlainLyric('第一句\n第二句');
    expect(lyricLinePracticeRange(plain, plain.lines.first, 100), isNull);
    final blank = _line(text: '  ');
    expect(lyricLinePracticeRange(_lyric(blank), blank, 100), isNull);
    final line = _line();
    expect(lyricLinePracticeRange(_lyric(_line()), line, 100), isNull);
    for (final duration in [double.nan, double.infinity, -1.0, .5]) {
      expect(lyricLinePracticeRange(_lyric(line), line, duration), isNull);
    }
  });

  LyricPracticeResult apply(_Playback playback, Lyric lyric, LyricLine line,
          {int session = 7, bool Function()? current}) =>
      practiceLyricLine(
          playback: playback,
          lyric: lyric,
          line: line,
          playbackSession: session,
          isCurrentLyric: current ?? () => true);

  test('practice reuses rounds and interval and never starts paused transport',
      () {
    final playback = _Playback();
    addTearDown(playback.segmentLoop.dispose);
    playback.segmentLoop.configurePractice(rounds: 5, interval: 2);
    final line = _line();
    expect(apply(playback, _lyric(line), line), LyricPracticeResult.applied);
    expect(playback.segmentLoop.start, 10);
    expect(playback.segmentLoop.end, 14);
    expect(playback.segmentLoop.enabled, isTrue);
    expect(playback.segmentLoop.totalRounds, 5);
    expect(playback.segmentLoop.intervalSeconds, 2);
    expect(playback.enables, 1);
    expect(playback.starts, 0);
  });
  test('source or lyric replacement rejects an old menu without editing range',
      () {
    final playback = _Playback();
    addTearDown(playback.segmentLoop.dispose);
    playback.segmentLoop.setStart(1, 100);
    playback.segmentLoop.setEnd(3, 100);
    final line = _line();
    expect(apply(playback, _lyric(line), line, session: 6),
        LyricPracticeResult.stale);
    expect(apply(playback, _lyric(line), line, current: () => false),
        LyricPracticeResult.stale);
    expect(playback.segmentLoop.start, 1);
    expect(playback.segmentLoop.end, 3);
    expect(playback.enables, 0);
  });
  test('source replacement from controller listener prevents further edits',
      () {
    final playback = _Playback();
    addTearDown(playback.segmentLoop.dispose);
    playback.segmentLoop.addListener(() => playback.playbackSessionToken++);
    final line = _line();
    expect(apply(playback, _lyric(line), line), LyricPracticeResult.stale);
    expect(playback.segmentLoop.end, isNull);
    expect(playback.enables, 0);
  });
  test('unavailable playback and invalid phrase keep the existing range', () {
    final playback = _Playback();
    addTearDown(playback.segmentLoop.dispose);
    playback.segmentLoop.setStart(1, 100);
    playback.segmentLoop.setEnd(3, 100);
    final line = _line(length: 500);
    expect(
        apply(playback, _lyric(line), line), LyricPracticeResult.invalidRange);
    playback.canUseSegmentLoop = false;
    expect(
        apply(playback, _lyric(line), line), LyricPracticeResult.unavailable);
    expect(playback.segmentLoop.start, 1);
    expect(playback.segmentLoop.end, 3);
    expect(playback.enables, 0);
  });
  test('exact one-second millisecond phrase survives double subtraction at EOF',
      () {
    final playback = _Playback()..length = 2.002;
    addTearDown(playback.segmentLoop.dispose);
    final line = _line(start: 1002, length: 1000);
    expect(apply(playback, _lyric(line), line), LyricPracticeResult.applied);
    expect(playback.segmentLoop.hasRange, isTrue);
    expect(playback.segmentLoop.end, 2.002);
    expect(playback.segmentLoop.start, closeTo(1.002, 1e-12));
    expect(line.start.inMilliseconds, 1002);
    expect(line.length.inMilliseconds, 1000);
  });

  Future<void> mount(WidgetTester tester, Lyric lyric,
      LyricViewController controller, ValueChanged<LyricLine>? practice,
      {double width = 800,
      GlobalKey? capture,
      Future<Lyric?>? lyricFuture}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 720);
    final future = lyricFuture ?? Future<Lyric?>.value(lyric);
    await tester.pumpWidget(RepaintBoundary(
        key: capture,
        child: MaterialApp(
          theme: Entry(welcome: false).fromSchemeAndFontFamily(
              fontFamily: danEmbeddedFontFamily,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.amber, brightness: Brightness.dark)),
          builder: (context, child) => UiLanguageScope(
              child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(width < 400 ? 2 : 1),
                      disableAnimations: true),
                  child: child!)),
          home: Scaffold(
              body: ChangeNotifierProvider.value(
                  value: controller,
                  child: VerticalLyricContent(
                      lyricFuture: future,
                      positionStream: const Stream.empty(),
                      readPosition: () => 10,
                      onSeek: (_) {},
                      onPractice: practice))),
        )));
    await tester.pumpAndSettle();
  }

  for (final language in UiLanguage.values) {
    testWidgets(
        'real line menu invokes practice at both widths ${language.name}',
        (tester) async {
      uiLanguage.value = language;
      final controller = LyricViewController(
          preferences: NowPlayingPagePreference.fromMap({}));
      addTearDown(controller.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final line = _line();
      final lyric = _lyric(line);
      final selections = <LyricLine>[];
      for (final width in [380.0, 900.0]) {
        final capture = GlobalKey();
        await mount(tester, lyric, controller, selections.add,
            width: width, capture: capture);
        final tile = find.byType(LyricViewTile);
        if (width < 400) {
          await tester.longPress(tile);
        } else {
          final pointer = await tester.startGesture(tester.getCenter(tile),
              kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
          await pointer.up();
        }
        await tester.pumpAndSettle();
        final action = find.widgetWithText(MenuItemButton, ui('练习这一句'));
        expect(action, findsOneWidget);
        expect(tester.getRect(action).width, greaterThan(48));
        expect(tester.getRect(action).right, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);
        if (output != null) {
          await tester.runAsync(() async {
            await Directory(output).create(recursive: true);
            final image = await (capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: raster.ImageByteFormat.png);
            await File(
                    path.join(output, '${language.name}-${width.toInt()}.png'))
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(selections.last, same(line));
      }
      expect(selections, hasLength(2));
    });
  }
  testWidgets(
      'same lyric new session rejects saved handler and refreshes practice action',
      (tester) async {
    final controller =
        LyricViewController(preferences: NowPlayingPagePreference.fromMap({}));
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final line = _line(), lyric = _lyric(line);
    final future = Future<Lyric?>.value(lyric);
    final playback = _Playback();
    addTearDown(playback.segmentLoop.dispose);
    final results = <LyricPracticeResult>[];
    await mount(tester, lyric, controller,
        (line) => results.add(apply(playback, lyric, line, session: 7)),
        lyricFuture: future);
    final oldTile = tester.widget<LyricViewTile>(find.byType(LyricViewTile));
    playback.playbackSessionToken = 8;
    await mount(tester, lyric, controller,
        (line) => results.add(apply(playback, lyric, line, session: 8)),
        lyricFuture: future);
    oldTile.onPractice!();
    expect(results, [LyricPracticeResult.stale]);
    expect(playback.enables, 0);
    tester.widget<LyricViewTile>(find.byType(LyricViewTile)).onPractice!();
    expect(results.last, LyricPracticeResult.applied);
    expect(playback.enables, 1);
    await mount(tester, _lyric(line), controller, null);
    expect(tester.widget<LyricViewTile>(find.byType(LyricViewTile)).onPractice,
        isNull);
    await mount(tester, PlainLyric('无时间歌词'), controller,
        (_) => fail('Plain lyrics must never offer practice'));
    expect(tester.widget<LyricViewTile>(find.byType(LyricViewTile)).onPractice,
        isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'stable practice callback keeps cached lyric rows on parent rebuild',
      (tester) async {
    final controller =
        LyricViewController(preferences: NowPlayingPagePreference.fromMap({}));
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lyric = _lyric(_line());
    final future = Future<Lyric?>.value(lyric);
    void practice(LyricLine line) {}
    await mount(tester, lyric, controller, practice, lyricFuture: future);
    final tile = tester.widget<LyricViewTile>(find.byType(LyricViewTile));
    await mount(tester, lyric, controller, practice, lyricFuture: future);
    expect(
        tester.widget<LyricViewTile>(find.byType(LyricViewTile)), same(tile));
  });
}
