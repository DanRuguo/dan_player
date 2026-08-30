import 'dart:async';

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/horizontal_lyric_view.dart';
import 'package:dan_player/component/title_bar.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _capsuleKey = ValueKey('centred-title-capsule');
const _scrollKey = ValueKey('horizontal-lyric-scroll');

class _Lyric extends Lyric {
  _Lyric(String line)
      : super([
          LrcLine(Duration.zero, line,
              isBlank: line.isEmpty, length: const Duration(seconds: 10)),
        ]);
}

class _Harness {
  _Harness(String line) : future = Future.value(_Lyric(line)) {
    addTearDown(positions.close);
  }

  final positions = StreamController<double>.broadcast();
  Future<Lyric?>? future;
  double position = 0;

  Future<void> seek(WidgetTester tester, double seconds) async {
    position = seconds;
    positions.add(seconds);
    await tester.pump();
    await tester.pumpAndSettle();
  }
}

Widget _app(
  _Harness harness, {
  double width = 720,
  double textScale = 1,
  bool reducedMotion = false,
  TextDirection direction = TextDirection.ltr,
  Color seed = Colors.teal,
  ThemeMode mode = ThemeMode.light,
  VoidCallback? onTap,
}) {
  ThemeData theme(Brightness brightness) => ThemeData(
        platform: TargetPlatform.windows,
        fontFamily: danEmbeddedFontFamily,
        fontFamilyFallback: danFontFamilyFallback,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: brightness,
        ),
      );

  return MaterialApp(
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    themeMode: mode,
    themeAnimationDuration: Duration.zero,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reducedMotion,
      ),
      child: Directionality(textDirection: direction, child: child!),
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: TitleBarSongRegion(
            child: Builder(builder: (context) {
              return DecoratedBox(
                key: _capsuleKey,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: GestureDetector(
                  onTap: onTap,
                  child: HorizontalLyricContent(
                    lyricFuture: harness.future,
                    positionStream: harness.positions.stream,
                    readPosition: () => harness.position,
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    ),
  );
}

ScrollController _controller(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(find.byKey(_scrollKey).last)
    .controller!;

void _expectCentred(WidgetTester tester, String text) {
  final capsule = tester.getRect(find.byKey(_capsuleKey));
  final bounds = tester.getRect(find.text(text));
  expect(bounds.center.dx, closeTo(capsule.center.dx, .01));
  expect(bounds.center.dy, closeTo(capsule.center.dy, .01));
  expect(capsule.contains(bounds.topLeft), isTrue);
  expect(capsule.contains(bounds.bottomRight), isTrue);
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
  expect(paragraph.maxLines, 1);
  expect(paragraph.softWrap, false);
  expect(paragraph.textAlign, TextAlign.center);
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader(danEmbeddedFontFamily)
      ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf'));
    await loader.load();
  });

  const shortLines = [
    '让音乐陪着你',
    'Music · café · Grüße · Ελληνικά',
    '音楽のある日々 · 음악과 함께',
    'مرحبا بالعالم · שלום',
    '👩🏽‍🎤 👨‍👩‍👧‍👦 🇨🇳 e\u0301 ✈️ ♫ <>& “—”',
  ];
  for (final direction in TextDirection.values) {
    for (final text in shortLines) {
      testWidgets('short $direction lyric stays centred and intact: $text',
          (tester) async {
        final harness = _Harness(text);
        await tester.pumpWidget(_app(harness,
            direction: direction, textScale: 2, reducedMotion: true));
        await tester.pumpAndSettle();

        _expectCentred(tester, text);
        expect(
            tester.renderObject<RenderParagraph>(find.text(text)).textDirection,
            direction);
        expect(_controller(tester).position.maxScrollExtent, 0);
        expect(find.bySemanticsLabel(text), findsOneWidget);
        expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, text);
        expect(PlayService.isInitialized, isFalse);
      });
    }
  }

  for (final direction in TextDirection.values) {
    for (final text in [
      '这是一句很长的中文歌词，标点和译文仍保留完整。' * 12,
      'Donaudampfschifffahrtsgesellschaftskapitän' * 12,
      'مرحبا بالعالم Ελληνικά 日本語 한국어 👩🏽‍🎤 e\u0301 & < > — ' * 12,
    ]) {
      testWidgets(
          'long $direction lyric keeps complete single-line scroll: ${text.substring(0, 8)}',
          (tester) async {
        final harness = _Harness(text);
        await tester.pumpWidget(
            _app(harness, width: 180, textScale: 2, direction: direction));
        await tester.pumpAndSettle();
        final scroll = _controller(tester);
        final viewport = tester.getRect(find.byKey(_scrollKey));
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        expect(paragraph.text.toPlainText(), text);
        expect(paragraph.maxLines, 1);
        expect(paragraph.softWrap, false);
        expect(paragraph.textDirection, direction);
        expect(paragraph.didExceedMaxLines, false);
        expect(scroll.position.maxScrollExtent, greaterThan(viewport.width));
        final isLtr = direction == TextDirection.ltr;
        final startRect = tester.getRect(find.text(text));
        expect(isLtr ? startRect.left : startRect.right,
            closeTo(isLtr ? viewport.left : viewport.right, .01));
        expect(find.bySemanticsLabel(text), findsOneWidget);
        expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, text);

        await harness.seek(tester, 9.8);
        expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, .01));
        final endRect = tester.getRect(find.text(text));
        expect(isLtr ? endRect.right : endRect.left,
            closeTo(isLtr ? viewport.right : viewport.left, .01));
        final stoppedOffset = scroll.offset;
        await tester.pump(const Duration(seconds: 2));
        expect(scroll.offset, stoppedOffset);
        await harness.seek(tester, 0);
        expect(scroll.offset, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('resize centres fitting text and restores overflow progress',
      (tester) async {
    const text = 'Longer lyric · 音乐陪伴每一天';
    final harness = _Harness(text)..position = 5;
    await tester.pumpWidget(_app(harness, width: 180));
    await tester.pumpAndSettle();
    final scroll = _controller(tester);
    expect(scroll.offset, greaterThan(0));
    await tester.pumpWidget(_app(harness));
    await tester.pumpAndSettle();
    expect(_controller(tester), same(scroll));
    expect(scroll.position.maxScrollExtent, 0);
    expect(scroll.offset, 0);
    _expectCentred(tester, text);
    await tester.pumpWidget(_app(harness, width: 180));
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent * .5, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('idle, loading, unavailable and instrumental text are centred',
      (tester) async {
    final harness = _Harness('');
    final pending = Completer<Lyric?>();
    harness.future = null;
    await tester.pumpWidget(_app(harness, reducedMotion: true));
    await tester.pumpAndSettle();
    _expectCentred(tester, 'Enjoy Music');
    harness.future = pending.future;
    await tester.pumpWidget(_app(harness, reducedMotion: true));
    await tester.pump();
    _expectCentred(tester, 'Enjoy Music');
    pending.completeError(StateError('fixture offline'));
    await tester.pumpAndSettle();
    _expectCentred(tester, '歌词暂不可用');
    harness.future = Future.value(_Lyric(''));
    await tester.pumpWidget(_app(harness, reducedMotion: true));
    await tester.pumpAndSettle();
    _expectCentred(tester, '间奏 · 聆听音乐');
  });

  testWidgets(
      'dynamic palettes and system brightness keep colour and alignment',
      (tester) async {
    const text = 'Music · 音乐 · ♫';
    final harness = _Harness(text);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    for (final seed in [Colors.teal, Colors.deepPurple, Colors.orange]) {
      for (final brightness in Brightness.values) {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        await tester.pumpWidget(_app(harness,
            seed: seed, mode: ThemeMode.system, reducedMotion: true));
        await tester.pumpAndSettle();
        final expected =
            ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
        expect(tester.widget<Text>(find.text(text)).style!.color,
            expected.onSecondaryContainer);
        _expectCentred(tester, text);
      }
    }
  });

  testWidgets('lyric content still forwards taps to its surrounding target',
      (tester) async {
    var taps = 0;
    for (final text in ['短句', 'LongWordWithoutSpaces' * 20]) {
      final harness = _Harness(text);
      await tester.pumpWidget(_app(harness, onTap: () => taps++));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.byKey(_capsuleKey)));
      await tester.pump();
    }
    expect(taps, 2);
    expect(tester.takeException(), isNull);
  });
}
