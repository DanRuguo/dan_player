import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

const _bodyKey = ValueKey('lyric-touch-body');
final _renderDirectory = Platform.environment['DAN_LYRIC_TOUCH_RENDER_DIR'];
final _renderBoundary = GlobalKey();

Widget _host(LyricViewController settings, Widget child,
        {double textScale = 1}) =>
    MaterialApp(
      theme: _renderDirectory == null
          ? null
          : applyAppControlTheme(ThemeData(
              useMaterial3: true,
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: danFontFamilyFallback,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal))),
      builder: (context, child) => RepaintBoundary(
        key: _renderBoundary,
        child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 420,
            height: 480,
            child: ChangeNotifierProvider.value(
              value: settings,
              child: LyricControlsSurface(
                controls: Column(mainAxisSize: MainAxisSize.min, children: [
                  LyricReadingMenu(controller: settings, readLyric: () => null),
                  const LyricFontSizeMenu(),
                ]),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = _renderDirectory;
  if (directory == null) return;
  await tester.runAsync(() async {
    await Directory(directory).create(recursive: true);
    final image = await (_renderBoundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage();
    try {
      final bytes = await image.toByteData(format: raster.ImageByteFormat.png);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

LyricViewController _settings() {
  final settings =
      LyricViewController(preferences: NowPlayingPagePreference.fromMap({}));
  addTearDown(settings.dispose);
  return settings;
}

bool _controlsVisible(WidgetTester tester) => !tester
    .widget<IgnorePointer>(find
        .ancestor(
            of: find.byKey(const ValueKey('lyric-reading-tools')),
            matching: find.byType(IgnorePointer))
        .first)
    .ignoring;

void main() {
  setUpAll(() async {
    if (_renderDirectory == null) return;
    await Future.wait([
      (FontLoader(danEmbeddedFontFamily)
            ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
          .load(),
      (FontLoader(
              'packages/${Symbols.tune.fontPackage}/${Symbols.tune.fontFamily}')
            ..addFont(rootBundle.load(
                'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
          .load(),
    ]);
    // Widget tests do not discover installed Windows fallback fonts. Register
    // the real family already named in danFontFamilyFallback, rather than
    // substituting the primary font or treating missing Korean ink as valid.
    final windowsFonts =
        '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts';
    final korean = File('$windowsFonts/malgun.ttf');
    await (FontLoader('Malgun Gothic')
          ..addFont(
              Future.value(ByteData.sublistView(await korean.readAsBytes()))))
        .load();
  });

  testWidgets('touching empty lyric status space reveals the tools',
      (tester) async {
    final settings = _settings();
    await tester.pumpWidget(
        _host(settings, const Center(key: _bodyKey, child: Text('No lyric'))));
    await tester.pumpAndSettle();
    await tester
        .tapAt(tester.getTopLeft(find.byKey(_bodyKey)) + const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(_controlsVisible(tester), isTrue,
        reason: 'Manual lyric selection must also be reachable with no lyric');
    await tester.pumpWidget(const SizedBox());
  });

  for (final kind in [
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  ]) {
    testWidgets('$kind reveals controls while preserving lyric scrolling',
        (tester) async {
      final settings = _settings();
      final scroll = ScrollController();
      var rowTaps = 0;
      addTearDown(scroll.dispose);
      await tester.pumpWidget(_host(
          settings,
          ListView.builder(
            key: _bodyKey,
            controller: scroll,
            itemCount: 50,
            itemBuilder: (_, index) => SizedBox(
              height: 60,
              child: TextButton(
                  onPressed: () => rowTaps++, child: Text('Lyric $index')),
            ),
          )));
      await tester.pumpAndSettle();
      expect(_controlsVisible(tester), isFalse);
      final gesture = await tester
          .startGesture(tester.getCenter(find.byKey(_bodyKey)), kind: kind);
      await gesture.moveBy(const Offset(0, -32));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(50));
      expect(rowTaps, 0,
          reason: 'Revealing the toolbar must not accept the row tap arena');
      expect(_controlsVisible(tester), isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final language in UiLanguage.values) {
    testWidgets('touch opens real reading and font controls in $language',
        (tester) async {
      final previousLanguage = uiLanguage.value;
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = previousLanguage);
      if (_renderDirectory != null) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(380, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
      }
      final settings = _settings();
      await tester.pumpWidget(_host(
          settings,
          const ColoredBox(
              key: _bodyKey,
              color: Colors.transparent,
              child: SizedBox.expand()),
          textScale: _renderDirectory == null ? 1 : 2));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.byKey(_bodyKey)));
      await tester.pumpAndSettle();
      expect(_controlsVisible(tester), isTrue);
      final menu =
          tester.element(find.byKey(const ValueKey('lyric-reading-tools')));
      await tester.tap(find.byKey(const ValueKey('lyric-reading-tools')));
      await tester.pumpAndSettle();
      await _capture(tester, '${language.name}-narrow-reading');
      await tester.tap(find.text(ui('显示歌词时间')));
      await tester.pumpAndSettle();
      expect(settings.showTimestamps, isTrue);
      expect(tester.element(find.byKey(const ValueKey('lyric-reading-tools'))),
          same(menu),
          reason: 'Control visibility changes must retain the menu anchor');
      await tester.tap(find.byKey(const ValueKey('lyric-font-size-open')));
      await tester.pumpAndSettle();
      await _capture(tester, '${language.name}-narrow-font');
      await tester.tap(find.byKey(const ValueKey('lyric-font-size-preset-32')));
      await tester.pumpAndSettle();
      expect(settings.lyricFontSize, 32);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('mouse restores hover visibility after a direct touch',
      (tester) async {
    final settings = _settings();
    await tester.pumpWidget(_host(
        settings,
        const ColoredBox(
            key: _bodyKey,
            color: Colors.transparent,
            child: SizedBox.expand())));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byKey(_bodyKey)));
    await tester.pumpAndSettle();
    expect(_controlsVisible(tester), isTrue);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byKey(_bodyKey)));
    await tester.pumpAndSettle();
    expect(_controlsVisible(tester), isTrue);
    await mouse.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(_controlsVisible(tester), isFalse);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('keyboard focus reveals mounted lyric controls and opens tools',
      (tester) async {
    final settings = _settings();
    await tester.pumpWidget(_host(
        settings,
        const ColoredBox(
            key: _bodyKey,
            color: Colors.transparent,
            child: SizedBox.expand())));
    await tester.pumpAndSettle();
    expect(_controlsVisible(tester), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(_controlsVisible(tester), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text(ui('显示歌词时间')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text(ui('显示歌词时间')), findsNothing);
    expect(_controlsVisible(tester), isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
