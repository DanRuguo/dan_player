import 'package:desktop_lyric/app_typography.dart';
import 'package:desktop_lyric/appearance_palette_app.dart';
import 'package:desktop_lyric/appearance_palette_bridge.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/palette_test_bridge.dart';

const _selectedFont = 'QAPaletteSelectedFont';

Map<String, Object?> _snapshot(
        {required int revision,
        required bool dark,
        UiLanguage language = UiLanguage.en,
        String font = _selectedFont,
        Color primary = const Color(0xffba641a)}) =>
    {
      'session': 1,
      'revision': revision,
      'editAck': 0,
      'appearance': DesktopLyricAppearance.defaults.toJson(),
      'darkMode': dark,
      'primary': primary.toARGB32(),
      'surfaceContainer': dark ? 0xff202322 : 0xfff8faf9,
      'onSurface': dark ? 0xffedf2ef : 0xff19211c,
      'language': language.code,
      'fontFamily': font,
      'fontFamilyFallback': DesktopLyricTypography.fontFamilyFallback,
      'saveError': null,
      'layoutError': null,
    };

Finder get _close => find.byKey(const ValueKey('desktop-appearance-close'));
Finder get _tooltip =>
    find.descendant(of: _close, matching: find.byType(Tooltip));

TextStyle _actualTooltipStyle(WidgetTester tester) => tester
    .widget<RichText>(find
        .byWidgetPredicate((widget) =>
            widget is RichText && widget.text.toPlainText() == ui('关闭歌词外观'))
        .last)
    .text
    .style!;

InkResponse _actualButtonInk(WidgetTester tester) => tester.widget<InkResponse>(
    find
        .descendant(
            of: _close,
            matching: find.byWidgetPredicate((widget) => widget is InkResponse))
        .last);

double _contrast(Color a, Color b) {
  final first = a.computeLuminance(), second = b.computeLuminance();
  return (first > second ? first + .05 : second + .05) /
      (first > second ? second + .05 : first + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in [_selectedFont, DesktopLyricTypography.fontFamily]) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf'));
      await loader.load();
    }
  });
  tearDown(() {
    Tooltip.dismissAllToolTips();
    uiLanguage.value = UiLanguage.zh;
  });

  for (final dark in [false, true]) {
    for (final language in UiLanguage.values) {
      testWidgets(
          'palette actual tooltip font and current hover $dark ${language.code}',
          (tester) async {
        tester.view.physicalSize = const Size(507, 400);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final client = DesktopLyricPaletteClient(
            channel: PaletteLoopbackChannel('test/palette_theme'));
        addTearDown(client.dispose);
        final primary =
            dark ? const Color(0xffd8b2eb) : const Color(0xff945123);
        client.applySnapshot(_snapshot(
            revision: 1, dark: dark, language: language, primary: primary));
        await tester.pumpWidget(DesktopLyricAppearanceApp(client: client));
        await tester.pumpAndSettle();
        tester.state<TooltipState>(_tooltip).ensureTooltipVisible();
        await tester.pumpAndSettle();
        final style = _actualTooltipStyle(tester);
        expect(style.fontFamily, _selectedFont);
        expect(style.fontFamilyFallback,
            DesktopLyricTypography.fontFamilyFallback);
        final theme = Theme.of(tester.element(_close));
        final decoration = theme.tooltipTheme.decoration! as BoxDecoration;
        expect(style.color, theme.colorScheme.onSurface);
        expect(decoration.color, theme.colorScheme.surfaceContainer);
        expect(_contrast(style.color!, decoration.color!),
            greaterThanOrEqualTo(4.5));
        final ink = _actualButtonInk(tester);
        expect(ink.overlayColor!.resolve({WidgetState.hovered})!.toARGB32(),
            primary.withValues(alpha: .08).toARGB32());
        expect(ink.overlayColor!.resolve({WidgetState.pressed})!.toARGB32(),
            primary.withValues(alpha: .12).toARGB32());
        expect(ink.overlayColor!.resolve({WidgetState.focused})!.toARGB32(),
            primary.withValues(alpha: .10).toARGB32());
        final painter = TextPainter(textDirection: TextDirection.ltr);
        painter.text = TextSpan(text: 'iiii', style: style);
        painter.layout();
        final narrow = painter.width;
        painter.text = TextSpan(text: 'WWWW', style: style);
        painter.layout();
        expect(painter.width, greaterThan(narrow * 1.5),
            reason: 'Use the real bundled font, not Ahem.');
        painter.dispose();
        expect(find.byType(UiLanguageTransition), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets(
      'already-open palette tooltip and hover follow new font and theme',
      (tester) async {
    final client = DesktopLyricPaletteClient(
        channel: PaletteLoopbackChannel('test/palette_theme_live'));
    addTearDown(client.dispose);
    client.applySnapshot(_snapshot(revision: 1, dark: false));
    await tester.pumpWidget(DesktopLyricAppearanceApp(client: client));
    await tester.pumpAndSettle();
    final tooltipState = tester.state<TooltipState>(_tooltip);
    tooltipState.ensureTooltipVisible();
    await tester.pumpAndSettle();
    expect(_actualTooltipStyle(tester).fontFamily, _selectedFont);
    const primary = Color(0xffadd5bd);
    client.applySnapshot(_snapshot(
        revision: 2,
        dark: true,
        primary: primary,
        font: DesktopLyricTypography.fontFamily));
    await tester.pumpAndSettle();
    expect(tester.state<TooltipState>(_tooltip), same(tooltipState));
    final style = _actualTooltipStyle(tester);
    expect(style.fontFamily, DesktopLyricTypography.fontFamily);
    expect(style.fontFamilyFallback, DesktopLyricTypography.fontFamilyFallback);
    expect(style.color, const Color(0xffedf2ef));
    expect(
        _actualButtonInk(tester)
            .overlayColor!
            .resolve({WidgetState.hovered})!.toARGB32(),
        primary.withValues(alpha: .08).toARGB32());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
