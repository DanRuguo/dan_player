import 'dart:typed_data';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/taskbar_lyric_row.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_theme_transition.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/desktop_lyric_test_support.dart';
import 'support/playlist_feature_fixture.dart';

const _actual = ValueKey('taskbar-single-line-text');
const _reference = ValueKey('taskbar-fresh-fit-reference');

class _FitTrace {
  int calls = 0;
}

// Observe actual binary-search text measurements without a production counter.
// Scaling performed by controls or the cached lyric painter is not counted.
class _CountingScaler extends TextScaler {
  const _CountingScaler(this.trace, this.factor);
  final _FitTrace trace;
  final double factor;

  @override
  double scale(double fontSize) {
    if (StackTrace.current.toString().contains('taskbarLyricFontSize')) {
      trace.calls++;
    }
    return fontSize * factor;
  }

  @override
  double get textScaleFactor => factor;
}

class _Host {
  _Host() {
    source = controller();
  }
  late DesktopLyricController source;
  final window = DesktopLyricWindowLayout(adapter: FakeDesktopLyricWindow());
  final trace = _FitTrace();
  late _CountingScaler scaler = _CountingScaler(trace, 1);
  AppFontPolicy policy = AppFontPolicy.defaults();
  TextStyle style = const TextStyle(
      fontFamily: danEmbeddedFontFamily,
      fontFamilyFallback: danFontFamilyFallback);
  double width = 500;
  double height = 56;
  bool visible = true;
  TextDirection direction = TextDirection.ltr;
  Locale locale = const Locale('en', 'US');
  DesktopLyricText? reference;

  DesktopLyricController controller() {
    final value = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false), sendMessage: (_) {});
    value.appearance.value = DesktopLyricAppearance.defaults
        .copyWith(lyricFontSize: 40, taskbarMinimumFontSize: 14);
    value.lyricLine.value = const LyricLineChangedMessage(
        'Window Hello 世界 한글 long song', Duration(seconds: 5));
    value.theme.value =
        const ThemeChangedMessage(0xff168c83, 0xffeeeeee, 0xff111111);
    return value;
  }

  Widget widget() => MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en', 'US'), Locale('en', 'GB')],
        home: MediaQuery(
          data: MediaQueryData(textScaler: scaler),
          child: Directionality(
            textDirection: direction,
            child: TickerMode(
              enabled: visible,
              child: AppFontScope(
                policy: policy,
                child: Scaffold(
                  body: DefaultTextStyle(
                    style: style,
                    child: Column(children: [
                      SizedBox(
                        width: width,
                        height: height,
                        child: ValueListenableBuilder<ThemeChangedMessage>(
                          valueListenable: source.theme,
                          builder: (context, colors, _) =>
                              DesktopLyricThemeTransition(
                            colors: colors,
                            builder: (context, current, _) =>
                                Provider<ThemeChangedMessage>.value(
                              value: current,
                              child: TaskbarLyricRow(
                                  controller: source,
                                  windowLayout: window,
                                  sendMessage: (_) {}),
                            ),
                          ),
                        ),
                      ),
                      if (reference != null) reference!,
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  void dispose() {
    source.dispose();
    window.dispose();
  }
}

DesktopLyricText _text(WidgetTester tester) =>
    tester.widget<DesktopLyricText>(find.byKey(_actual));

DesktopLyricTextPainter _painter(WidgetTester tester,
        [Key key = _actual]) =>
    tester
        .widget<CustomPaint>(find.descendant(
            of: find.byKey(key), matching: find.byType(CustomPaint)))
        .painter! as DesktopLyricTextPainter;

Future<Uint8List> _pixels(WidgetTester tester, [Key key = _actual]) async {
  final size = tester.getSize(find.byKey(key));
  final recorder = drawing.PictureRecorder();
  _painter(tester, key).paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  return (await tester.runAsync(() async {
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    try {
      return (await image.toByteData())!.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }))!;
}

Future<void> _expectFresh(WidgetTester tester, _Host host) async {
  final actual = _text(tester);
  final expected = taskbarLyricFontSize(actual.text,
      style: actual.style,
      scaler: TextScaler.linear(host.scaler.factor),
      direction: host.direction,
      fontPolicy: host.policy,
      width: actual.maxHorizontalWidth!,
      height: host.height - 4,
      preferred: host.source.appearance.value.lyricFontSize,
      minimum: host.source.appearance.value.taskbarMinimumFontSize);
  expect(actual.style.fontSize, expected);
  host.reference = DesktopLyricText(
      key: _reference,
      text: actual.text,
      clock: actual.clock,
      style: actual.style.copyWith(fontSize: expected),
      playedColor: actual.playedColor,
      unplayedColor: actual.unplayedColor,
      strokeColor: actual.strokeColor,
      words: actual.words,
      reducedMotion: actual.reducedMotion,
      maxHorizontalWidth: actual.maxHorizontalWidth);
  await tester.pumpWidget(host.widget());
  expect(tester.getSize(find.byKey(_actual)),
      tester.getSize(find.byKey(_reference)));
  final pixels = await _pixels(tester);
  expect(pixels.any((value) => value != 0), isTrue);
  expect(pixels, orderedEquals(await _pixels(tester, _reference)),
      reason: 'A retained fit must render exactly like a fresh fit');
  host.reference = null;
  await tester.pumpWidget(host.widget());
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  expect(tester.binding.transientCallbackCount, 0);
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadPlaylistFeatureFonts();
    await ensureAppFontsLoaded(AppFontPolicy.defaults());
  });

  testWidgets('surface-only theme motion retains taskbar fit metrics',
      (tester) async {
    final host = _Host();
    addTearDown(host.dispose);
    await tester.pumpWidget(host.widget());
    await tester.pumpAndSettle();
    final shape = _painter(tester).cachedShapingIdentities.first;
    final initialPixels = await _pixels(tester);
    expect(host.trace.calls, greaterThan(0));
    host.trace.calls = 0;
    host.source.theme.value =
        const ThemeChangedMessage(0xff168c83, 0xff222222, 0xff111111);
    await tester.pump();
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 30));
      expect(_painter(tester).cachedShapingIdentities.first, same(shape));
      expect(await _pixels(tester), orderedEquals(initialPixels));
    }
    expect(host.trace.calls, 0,
        reason: 'Background frames do not change text measurement inputs');
    await _finish(tester);
  });

  testWidgets('taskbar paint changes update pixels without repeating fit',
      (tester) async {
    final host = _Host();
    addTearDown(host.dispose);
    await tester.pumpWidget(host.widget());
    await tester.pumpAndSettle();
    final first = await _pixels(tester);
    host.trace.calls = 0;
    host.source.theme.value =
        const ThemeChangedMessage(0xffdd2277, 0xff222222, 0xfffafafa);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(await _pixels(tester), isNot(orderedEquals(first)));
    host.source.appearance.value = host.source.appearance.value.copyWith(
        customColor: 0xff3355ee, strokeEnabled: true, textOpacity: .6);
    host.style = host.style
        .copyWith(color: Colors.red, shadows: const [Shadow(blurRadius: 1)]);
    await tester.pumpWidget(host.widget());
    await tester.pumpAndSettle();
    expect(host.trace.calls, 0);
    expect(_text(tester).playedColor, const Color(0xff3355ee));
    expect(_text(tester).strokeColor, isNotNull);
    await _expectFresh(tester, host);
    await _finish(tester);
  });

  testWidgets('taskbar text and translation invalidate fit but timing does not',
      (tester) async {
    final host = _Host();
    addTearDown(host.dispose);
    await tester.pumpWidget(host.widget());
    for (final start in [0, 1000]) {
      host.trace.calls = 0;
      host.source.detailedLyricLine.value = LyricLineTimelineMessage(
          sequence: 1,
          lineIndex: 0,
          startMilliseconds: start,
          lengthMilliseconds: 6000,
          content: 'Hello e\u0301 世界 👩🏽‍🚀',
          translation: 'Translation かな 한글',
          words: [DesktopLyricWord(start, 6000, 'Hello e\u0301 世界 👩🏽‍🚀')]);
      await tester.pump();
      expect(host.trace.calls, start == 0 ? greaterThan(0) : 0);
      expect(_text(tester).words.single.startMilliseconds, start);
      await _expectFresh(tester, host);
    }
    host.trace.calls = 0;
    host.source.appearance.value =
        host.source.appearance.value.copyWith(taskbarTranslation: true);
    await tester.pump();
    expect(host.trace.calls, greaterThan(0));
    expect(_text(tester).text, 'Translation かな 한글');
    expect(_text(tester).words, isEmpty);
    await _expectFresh(tester, host);
    await _finish(tester);
  });

  testWidgets('taskbar bounds and size preferences invalidate the retained fit',
      (tester) async {
    final host = _Host();
    addTearDown(host.dispose);
    await tester.pumpWidget(host.widget());
    final changes = <VoidCallback>[
      () => host.width = 360,
      () => host.height = 48,
      () => host.width = 700,
      () => host.source.appearance.value =
          host.source.appearance.value.copyWith(lyricFontSize: 52),
      () => host.source.appearance.value =
          host.source.appearance.value.copyWith(taskbarMinimumFontSize: 22),
    ];
    for (final change in changes) {
      host.trace.calls = 0;
      change();
      await tester.pumpWidget(host.widget());
      expect(host.trace.calls, greaterThan(0));
      await _expectFresh(tester, host);
    }
    await _finish(tester);
  });

  testWidgets(
      'taskbar metric style scaling direction and locale invalidate fit',
      (tester) async {
    final host = _Host();
    addTearDown(host.dispose);
    await tester.pumpWidget(host.widget());
    final changes = <VoidCallback>[
      () => host.style = host.style.copyWith(letterSpacing: 2, wordSpacing: 3),
      () => host.style = host.style.copyWith(fontStyle: FontStyle.italic),
      () => host.scaler = _CountingScaler(host.trace, 1.5),
      () => host.direction = TextDirection.rtl,
      () => host.locale = const Locale('en', 'GB'),
    ];
    for (final change in changes) {
      host.trace.calls = 0;
      change();
      await tester.pumpWidget(host.widget());
      expect(host.trace.calls, greaterThan(0));
      await _expectFresh(tester, host);
    }
    await _finish(tester);
  });

  testWidgets(
      'taskbar font policy changes invalidate fit but equal snapshots reuse',
      (tester) async {
    final host = _Host();
    addTearDown(host.dispose);
    await tester.pumpWidget(host.widget());
    host.trace.calls = 0;
    host.policy = AppFontPolicy.defaults();
    await tester.pumpWidget(host.widget());
    expect(host.trace.calls, 0);
    final originalSize = _text(tester).style.fontSize;
    host.policy = AppFontPolicy(
        language: UiLanguage.en,
        mixedScripts: false,
        zh: appBundledFonts[1],
        en: appBundledFonts[1],
        ja: appBundledFonts[1],
        ko: appBundledFonts[1]);
    await tester.pumpWidget(host.widget());
    expect(host.trace.calls, greaterThan(0));
    expect(_text(tester).style.fontSize, isNot(originalSize));
    await _expectFresh(tester, host);
    host.trace.calls = 0;
    host.policy = AppFontPolicy.defaults(language: UiLanguage.ja);
    await tester.pumpWidget(host.widget());
    expect(host.trace.calls, greaterThan(0));
    await _expectFresh(tester, host);
    await _finish(tester);
  });

  testWidgets(
      'taskbar hidden timeline and controller handoff retain fit ownership',
      (tester) async {
    final host = _Host();
    addTearDown(host.dispose);
    await tester.pumpWidget(host.widget());
    final rowElement = tester.element(find.byType(TaskbarLyricRow));
    host.trace.calls = 0;
    host.source.isPlaying.value = true;
    host.source.playbackClock
        .sync(const PlaybackTimelineMessage(1, 500, false));
    await tester.pump();
    host.visible = false;
    await tester.pumpWidget(host.widget());
    host.source.theme.value =
        const ThemeChangedMessage(0xff168c83, 0xff222222, 0xff111111);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
    expect(host.trace.calls, 0);
    final previous = host.source;
    addTearDown(previous.dispose);
    host.source = host.controller();
    await tester.pumpWidget(host.widget());
    expect(tester.element(find.byType(TaskbarLyricRow)), same(rowElement));
    expect(host.trace.calls, 0);
    previous.lyricLine.value = const LyricLineChangedMessage(
        'Old owner must not repaint', Duration.zero);
    await tester.pump();
    expect(host.trace.calls, 0);
    expect(_text(tester).text, 'Window Hello 世界 한글 long song');
    host.source.lyricLine.value =
        const LyricLineChangedMessage('New owner 新歌', Duration.zero);
    await tester.pump();
    expect(host.trace.calls, greaterThan(0));
    host.trace.calls = 0;
    host.visible = true;
    await tester.pumpWidget(host.widget());
    expect(host.trace.calls, 0);
    await _expectFresh(tester, host);
    await _finish(tester);
  });
}
