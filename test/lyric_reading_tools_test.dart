import 'dart:async';
import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Lyrics extends Lyric {
  _Lyrics(super.lines);
}

NowPlayingPagePreference _preferences() => NowPlayingPagePreference.fromMap({});
Lyric _lyrics() => _Lyrics([
      for (var i = 0; i < 16; i++)
        LrcLine(Duration(seconds: 5 * i),
            '第 $i 行歌词，听见窗外轻轻落下的雨┃Translation line $i: listen to the rain outside',
            isBlank: false, length: const Duration(seconds: 5))
          ..romanization = 'Dì $i háng gēcí',
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
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
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                korean.readAsBytes().then((b) => ByteData.sublistView(b))))
          .load();
    }
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  Finder paragraph(String text) => find.byWidgetPredicate(
      (widget) => widget is BalancedLyricText && widget.text.contains(text));

  test(
      'legacy preferences preserve lyrics, clamp unsafe text sizes and round trip display settings',
      () {
    final legacy = _preferences();
    expect(legacy.showLyricTranslation, isTrue);
    expect(legacy.showLyricRomanization, isTrue);
    expect(legacy.showLyricTimestamps, isFalse);
    for (final invalid in [double.nan, double.infinity, 'very large', null]) {
      expect(
          NowPlayingPagePreference.fromMap({'lyricFontSize': invalid})
              .lyricFontSize,
          22);
    }
    expect(
        NowPlayingPagePreference.fromMap({'lyricFontSize': 200}).lyricFontSize,
        64);
    expect(
        NowPlayingPagePreference.fromMap({'translationFontSize': -8})
            .translationFontSize,
        14);
    final control = LyricViewController(preferences: legacy);
    addTearDown(control.dispose);
    control.setShowTranslation(false);
    control.setShowRomanization(false);
    control.setShowTimestamps(true);
    control.increaseFontSize();
    final restored = NowPlayingPagePreference.fromMap(legacy.toMap());
    expect(restored.showLyricTranslation, isFalse);
    expect(restored.showLyricRomanization, isFalse);
    expect(restored.showLyricTimestamps, isTrue);
    expect(restored.lyricFontSize, 23);
    control.resetFontSize();
    expect(legacy.lyricFontSize, 22);
    expect(legacy.translationFontSize, 18);
  });

  test('copy projection respects displayed columns and does not mutate source',
      () {
    final line = _lyrics().lines[2] as LrcLine;
    final original = line.content;
    final result = lyricReadingText(line, timestamp: true, romanization: false);
    expect(result, startsWith('[00:10.000] 第 2 行'));
    expect(result, contains('Translation line 2'));
    expect(result, isNot(contains('Dì')));
    expect(lyricReadingText(line, translation: false, romanization: false),
        isNot(contains('┃')));
    expect(line.content, original);
    expect(line.start, const Duration(seconds: 10));
  });

  Future<
          ({
            LyricViewController settings,
            void Function(double) position,
            ScrollController scroll
          })>
      mount(WidgetTester tester,
          {double width = 460,
          double scale = 1,
          bool reduced = false,
          bool spring = false,
          GlobalKey? boundary}) async {
    final settings = LyricViewController(preferences: _preferences());
    final changes = StreamController<double>.broadcast(sync: true);
    var current = 0.0;
    final future = Future<Lyric?>.value(_lyrics());
    addTearDown(() async {
      await changes.close();
      settings.dispose();
    });
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: Entry(welcome: false).fromSchemeAndFontFamily(
              fontFamily: danEmbeddedFontFamily,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
          builder: (context, child) => UiLanguageScope(
              child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      size: Size(width, 720),
                      textScaler: TextScaler.linear(scale),
                      disableAnimations: reduced),
                  child: child!)),
          home: Scaffold(
              body: Center(
                  child: SizedBox(
            width: width,
            height: 580,
            child: ChangeNotifierProvider.value(
                value: settings,
                child: Column(children: [
                  Align(
                      alignment: Alignment.centerRight,
                      child: LyricReadingMenu(
                          controller: settings, readLyric: () => future)),
                  Expanded(
                      child: VerticalLyricContent(
                          lyricFuture: future,
                          springLyrics: spring,
                          playing: false,
                          positionStream: changes.stream,
                          readPosition: () => current,
                          onSeek: (value) {
                            current = value;
                            changes.add(value);
                          })),
                ])),
          ))),
        )));
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<CustomScrollView>(
            find.byKey(const ValueKey('vertical-lyric-scroll')))
        .controller!;
    return (
      settings: settings,
      scroll: scroll,
      position: (value) {
        current = value;
        changes.add(value);
      }
    );
  }

  testWidgets(
      'playback takes over settings anchor without an immediate scroll jump',
      (tester) async {
    final h = await mount(tester, width: 700, spring: true);
    h.position(29.98);
    await tester.pumpAndSettle();
    h.settings.setShowTimestamps(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump(const Duration(milliseconds: 400));
    final before = h.scroll.offset;
    h.position(30.01);
    await tester.pump();
    expect(h.scroll.offset, closeTo(before, .05),
        reason: 'The next playback line must start its normal finite follow');
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 160));
    expect(h.scroll.offset, greaterThan(before));
    expect(h.scroll.position.isScrollingNotifier.value, isTrue);
    await tester.pumpAndSettle();
    final current = find.byWidgetPredicate((w) =>
        w is LyricViewTile && w.line.start == const Duration(seconds: 30));
    final viewport =
        tester.getRect(find.byKey(const ValueKey('vertical-lyric-scroll')));
    final row = tester.getRect(current);
    expect(row.top + row.height * .34,
        closeTo(viewport.top + viewport.height * .34, .05));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('delayed final settings frame preserves anchor before paint',
      (tester) async {
    final h = await mount(tester, width: 700);
    h.position(25);
    await tester.pumpAndSettle();
    final current = find.byWidgetPredicate((w) =>
        w is LyricViewTile && w.line.start == const Duration(seconds: 25));
    for (final change in <VoidCallback>[
      () => h.settings.setShowTimestamps(true),
      () => h.settings.setShowTimestamps(false),
      () => h.settings.setShowTranslation(false),
      () => h.settings.setShowTranslation(true),
      () => h.settings.setShowRomanization(false),
      () => h.settings.setShowRomanization(true),
    ]) {
      change();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump(const Duration(milliseconds: 400));
      final viewport =
          tester.getRect(find.byKey(const ValueKey('vertical-lyric-scroll')));
      final row = tester.getRect(current);
      expect(row.top + row.height * .34,
          closeTo(viewport.top + viewport.height * .34, .05));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'font and auxiliary height transitions keep the painted anchor in the same frame',
      (tester) async {
    final h = await mount(tester, width: 700);
    h.position(25);
    await tester.pumpAndSettle();
    final current = find.byWidgetPredicate((w) =>
        w is LyricViewTile && w.line.start == const Duration(seconds: 25));
    for (final change in <VoidCallback>[
      h.settings.increaseFontSize,
      () => h.settings.setShowTranslation(false),
      () => h.settings.setShowRomanization(false),
      () => h.settings.setShowTimestamps(true),
      h.settings.decreaseFontSize,
      () => h.settings.setShowTranslation(true),
      () => h.settings.setShowRomanization(true),
      () => h.settings.setShowTimestamps(false),
    ]) {
      change();
      await tester.pump();
      for (var frame = 0; frame < 32; frame++) {
        // Exactly one rendered frame: no zero-duration pump to conceal an
        // offset correction that only takes effect in the following frame.
        await tester.pump(const Duration(milliseconds: 16));
        final viewport =
            tester.getRect(find.byKey(const ValueKey('vertical-lyric-scroll')));
        final row = tester.getRect(current);
        expect(row.top + row.height * .34,
            closeTo(viewport.top + viewport.height * .34, .05),
            reason:
                'Settings transition frame $frame must paint at its own anchor');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
    }
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final reduced in [false, true]) {
    testWidgets(
        'manual reading stays put and return follows real position, reduced=$reduced',
        (tester) async {
      final h = await mount(tester, reduced: reduced);
      h.settings.setReadingMode(true);
      await tester.pumpAndSettle();
      h.scroll.jumpTo(300);
      final manual = h.scroll.offset;
      h.position(55);
      await tester.pump(const Duration(seconds: 15));
      expect(h.scroll.offset, closeTo(manual, .1));
      expect(
          find.byKey(const ValueKey('lyric-return-current')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lyric-return-current')));
      await tester.pumpAndSettle();
      expect(h.settings.readingMode, isFalse);
      expect(h.scroll.offset, greaterThan(manual + 50));
      expect(find.byKey(const ValueKey('lyric-return-current')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'display toggles affect rendered auxiliary rows and timestamps immediately',
      (tester) async {
    final h = await mount(tester);
    expect(paragraph('Translation line 0'), findsOneWidget);
    h.settings.setShowTranslation(false);
    h.settings.setShowRomanization(false);
    h.settings.setShowTimestamps(true);
    await tester.pumpAndSettle();
    expect(paragraph('Translation line 0'), findsNothing);
    expect(paragraph('Dì 0'), findsNothing);
    expect(find.text('00:00.000'), findsOneWidget);
    h.settings.setShowTranslation(true);
    await tester.pumpAndSettle();
    expect(paragraph('Translation line 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets(
        'reading settings update font and rows while current line stays anchored reduced=$reduced',
        (tester) async {
      final boundary = GlobalKey();
      final h =
          await mount(tester, width: 700, reduced: reduced, boundary: boundary);
      h.position(25);
      await tester.pumpAndSettle();
      final current = find.byWidgetPredicate((w) =>
          w is LyricViewTile && w.line.start == const Duration(seconds: 25));
      double font() => tester
          .widgetList<BalancedLyricText>(find.byType(BalancedLyricText))
          .where((w) => w.text.startsWith('第 5 行'))
          .last
          .style
          .fontSize!;
      Future<void> capture(String name) async {
        final output = Platform.environment['DAN_UI_MOTION_RENDER'];
        if (output == null) return;
        await tester.runAsync(() async {
          await Directory(output).create(recursive: true);
          final image = await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          final bytes =
              await image.toByteData(format: raster.ImageByteFormat.png);
          await File('$output/lyrics-$reduced-$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('before');
      expect(font(), closeTo(22 * 1.5, .01));
      for (var i = 0; i < 8; i++) {
        h.settings.increaseFontSize();
      }
      h.settings.setShowTranslation(false);
      h.settings.setShowRomanization(false);
      h.settings.setShowTimestamps(true);
      h.settings.switchLyricTextAlign();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();
      expect(font(), closeTo(h.settings.lyricFontSize * 1.5, .01),
          reason: 'The target paragraph is laid out once at its final size');
      expect(find.text('00:25.000'), findsOneWidget);
      final viewport =
          tester.getRect(find.byKey(const ValueKey('vertical-lyric-scroll')));
      final row = tester.getRect(current);
      expect(row.top + row.height * .34,
          closeTo(viewport.top + viewport.height * .34, 2));
      await capture('during');
      await tester.pumpAndSettle();
      expect(paragraph('Translation line 5'), findsNothing);
      expect(paragraph('Dì 5'), findsNothing);
      // A second choice applies from the current displayed settings.
      h.settings.setShowTranslation(true);
      h.settings.switchLyricTextAlign();
      h.settings.decreaseFontSize();
      await tester.pumpAndSettle();
      expect(font(), closeTo(h.settings.lyricFontSize * 1.5, .01));
      expect(paragraph('Translation line 5'), findsOneWidget);
      expect(paragraph('Dì 5'), findsNothing);
      expect(find.text('00:25.000'), findsOneWidget);
      await capture('after');
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'copy entire shown lyric and secondary-click timed line use clipboard without seeking',
      (tester) async {
    final writes = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        writes.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final h = await mount(tester);
    h.settings.setShowRomanization(false);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lyric-reading-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制完整显示歌词'));
    await tester.pumpAndSettle();
    expect(writes.single, contains('Translation line 15'));
    expect(writes.single, isNot(contains('Dì')));
    final line = find.byWidgetPredicate((widget) =>
        widget is LyricViewTile && widget.line.start == Duration.zero);
    final pointer = await tester.startGesture(tester.getCenter(line),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await pointer.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制歌词与时间'));
    await tester.pumpAndSettle();
    expect(writes.last, startsWith('[00:00.000] 第 0 行'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reading menu renders four languages at narrow and wide widths with large text',
      (tester) async {
    final output = Platform.environment['DAN_LYRIC_READING_RENDER_DIR'];
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final width in [380.0, 800.0]) {
        await tester.binding.setSurfaceSize(Size(width, 720));
        final boundary = GlobalKey();
        final h = await mount(tester,
            width: width, scale: width < 400 ? 2 : 1, boundary: boundary);
        h.settings.setShowTimestamps(true);
        h.settings.setReadingMode(true);
        await tester.pumpAndSettle();
        if (output != null) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: raster.ImageByteFormat.png);
            await Directory(output).create(recursive: true);
            await File('$output/${language.name}-${width.toInt()}-lyrics.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.byKey(const ValueKey('lyric-reading-tools')));
        await tester.pumpAndSettle();
        expect(find.text(ui('手动阅读歌词')), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (output != null) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: raster.ImageByteFormat.png);
            await File('$output/${language.name}-${width.toInt()}-menu.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    }
    await tester.binding.setSurfaceSize(null);
  });
}
