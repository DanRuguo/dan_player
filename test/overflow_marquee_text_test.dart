import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/overflow_marquee_text.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const longTitle = 'A long song title with artists and album details';

Finder _paint() => find.descendant(
    of: find.byType(OverflowMarqueeText), matching: find.byType(CustomPaint));
dynamic _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_paint()).painter;
double _offset(WidgetTester tester) =>
    _painter(tester).pose.value.offset as double;

Widget _host(
        {String text = longTitle,
        double width = 180,
        ValueNotifier<bool>? hidden,
        ValueNotifier<RenderingPreferences>? preferences,
        bool tickerEnabled = true,
        bool disableAnimations = false,
        double scale = 1,
        TextDirection direction = TextDirection.ltr,
        Brightness brightness = Brightness.light,
        GlobalKey? boundary,
        VoidCallback? onBuild}) =>
    MaterialApp(
      theme: ThemeData(
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.orange, brightness: brightness)),
      home: Scaffold(
        body: Builder(builder: (context) {
          onBuild?.call();
          Widget child = Center(
              child: RepaintBoundary(
                  key: boundary,
                  child: ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: SizedBox(
                          width: width,
                          child: OverflowMarqueeText(text,
                              hidden: hidden,
                              style: const TextStyle(fontSize: 20))))));
          if (preferences != null) {
            child = RenderingPreferencesScope(
                preferences: preferences, child: child);
          }
          return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  disableAnimations: disableAnimations,
                  textScaler: TextScaler.linear(scale)),
              child: Directionality(
                  textDirection: direction,
                  child: TickerMode(enabled: tickerEnabled, child: child)));
        }),
      ),
    );

Future<void> _advance(WidgetTester tester, int milliseconds) async {
  for (var elapsed = 0; elapsed < milliseconds; elapsed += 20) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
  });

  testWidgets('fitting text schedules no visual work and uses normal alignment',
      (tester) async {
    await tester.pumpWidget(_host(text: 'Short title', width: 400));
    expect(_paint(), findsNothing);
    expect(find.text('Short title'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(minutes: 1));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('overflow pauses, paints without reshaping, and resumes in place',
      (tester) async {
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    var builds = 0;
    await tester.pumpWidget(_host(hidden: hidden, onBuild: () => builds++));
    final initialPainter = _painter(tester).text;
    final initialBuilds = builds;
    expect(_offset(tester), 0);
    expect(tester.binding.transientCallbackCount, 0);
    await _advance(tester, 1100);
    expect(_offset(tester), 0);
    await _advance(tester, 800);
    expect(_offset(tester), greaterThan(8));
    expect(_painter(tester).text, same(initialPainter));
    expect(builds, initialBuilds);
    final beforeHide = _offset(tester);
    hidden.value = true;
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 20));
    expect(_offset(tester), beforeHide);
    hidden.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(_offset(tester), inInclusiveRange(beforeHide, beforeHide + 1));
    expect(_painter(tester).text, same(initialPainter));
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'animation and visibility policies stop pending and active clocks',
      (tester) async {
    final hidden = ValueNotifier(false);
    final preferences = ValueNotifier(const RenderingPreferences());
    addTearDown(hidden.dispose);
    addTearDown(preferences.dispose);
    await tester.pumpWidget(_host(hidden: hidden, preferences: preferences));
    await _advance(tester, 1600);
    expect(_offset(tester), greaterThan(0));
    preferences.value = preferences.value.copyWith(
        animations:
            const MotionPreferences().withKind(MotionKind.layout, false));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpAndSettle();
    expect(_paint(), findsNothing);
    expect(tester.widget<Text>(find.text(longTitle)).overflow,
        TextOverflow.ellipsis);
    preferences.value = preferences.value.copyWith(
        animations: const MotionPreferences(), pauseWhenHidden: false);
    hidden.value = true;
    await tester.pump();
    await _advance(tester, 1700);
    expect(_offset(tester), greaterThan(0),
        reason: 'Explicit background visual updates retain their meaning');
    await tester.pumpWidget(_host(
        hidden: hidden, preferences: preferences, disableAnimations: true));
    expect(_paint(), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'resize and text replacement reset safely; RTL retains full label',
      (tester) async {
    await tester.pumpWidget(_host(direction: TextDirection.rtl));
    await _advance(tester, 1700);
    expect(_offset(tester), greaterThan(0));
    expect(find.bySemanticsLabel(longTitle), findsOneWidget);
    await tester.pumpWidget(
        _host(text: 'A new title that still overflows', width: 140));
    expect(_offset(tester), 0);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(_host(text: 'Short', width: 140));
    expect(_paint(), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 10));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
      'full loop rests at both ends and joins the next copy without a jump',
      (tester) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(
        _host(text: 'A long readable title', width: 160, boundary: boundary));
    final painter = _painter(tester);
    final shape = painter.text;
    final overflow = (shape.width as double) - 160;
    final cycle = (shape.width as double) + (painter.gap as double);
    await _advance(tester, 1220);
    for (var frame = 0; frame < 2000 && _offset(tester) < overflow; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(_offset(tester), closeTo(overflow, .0001));
    expect(tester.binding.transientCallbackCount, 0);
    await _advance(tester, 1100);
    expect(_offset(tester), closeTo(overflow, .0001));
    expect(tester.binding.transientCallbackCount, 0);
    await _advance(tester, 200);
    expect(_painter(tester).pose.value.wrapping, isTrue);

    Future<List<int>> pixels() async => (await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes =
              (await image.toByteData(format: drawing.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List()
                  .toList();
          image.dispose();
          return bytes;
        }))!;
    List<int>? beforeJoin;
    double? beforeOffset;
    for (var frame = 0; frame < 2000; frame++) {
      final offset = _offset(tester);
      if (cycle - offset < .5) {
        beforeJoin = await pixels();
        beforeOffset = offset;
      }
      await tester.pump(const Duration(milliseconds: 20));
      if (_offset(tester) == 0) break;
    }
    expect(beforeJoin, isNotNull);
    expect(cycle - beforeOffset!, lessThan(.03));
    expect(_offset(tester), 0);
    expect(_painter(tester).pose.value.wrapping, isFalse);
    final afterJoin = await pixels();
    var difference = 0;
    for (var i = 0; i < afterJoin.length; i++) {
      difference += (afterJoin[i] - beforeJoin![i]).abs();
    }
    expect(difference / afterJoin.length, lessThan(1.0),
        reason:
            'The arriving duplicate must become the original without a flash');
    expect(tester.binding.transientCallbackCount, 0);
    await _advance(tester, 1000);
    expect(_offset(tester), 0);
    expect(_painter(tester).text, same(shape));
    await _advance(tester, 600);
    expect(_offset(tester), greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  for (final item in [
    ('zh', '这一首有很长很长的歌曲名字，艺术家与专辑信息也需要完整阅读'),
    ('en', longTitle),
    ('ja', '君が好きだと叫びたい とても長い曲名とアーティストとアルバム'),
    ('ko', '아주 긴 노래 제목과 아티스트 및 앨범 정보를 천천히 표시합니다'),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets('marquee edge fade ${item.$1} ${brightness.name}',
          (tester) async {
        final boundary = GlobalKey();
        await tester.pumpWidget(_host(
            text: item.$2,
            width: 230,
            scale: 1.5,
            brightness: brightness,
            boundary: boundary));
        final height = tester.getSize(find.byType(OverflowMarqueeText)).height;
        await _advance(tester, 1900);
        expect(_offset(tester), greaterThan(0));
        expect(tester.getSize(find.byType(OverflowMarqueeText)).height, height);
        expect(tester.takeException(), isNull);
        const output = String.fromEnvironment('DAN_MARQUEE_RENDER');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
            await Directory(output).create(recursive: true);
            await File('$output/${item.$1}-${brightness.name}.png')
                .writeAsBytes((await image.toByteData(
                        format: drawing.ImageByteFormat.png))!
                    .buffer
                    .asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
