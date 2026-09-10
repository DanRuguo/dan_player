import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/settings_page/theme_picker_dialog.dart';
import 'package:dan_player/entry.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      )
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
  });
  testWidgets(
      'invalid hex is retained without throwing and cancel never applies a preview',
      (tester) async {
    final original = AppSettings.instance.defaultTheme;
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    final result = showDialog<Color>(
        context: context, builder: (_) => const ThemePickerDialog());
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('theme-hex-input'));
    await tester.enterText(input, '#zzzzzz');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<TextField>(input).controller!.text, '#zzzzzz');
    expect(tester.widget<TextField>(input).decoration!.errorText, isNotNull);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('theme-confirm')))
            .onPressed,
        isNull);
    await tester.enterText(input, '#ff8800');
    await tester.pumpAndSettle();
    final wheel =
        tester.widget<ColorWheelPicker>(find.byType(ColorWheelPicker));
    expect(wheel.color, const Color(0xffff8800));
    expect(wheel.shouldUpdate, isTrue);
    expect(AppSettings.instance.defaultTheme, original);
    await tester.tap(find.text(ui('取消')));
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(AppSettings.instance.defaultTheme, original);
  });
  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets('theme picker renders ${language.name} narrow=$narrow',
          (tester) async {
        final original = AppSettings.instance.defaultTheme;
        AppSettings.instance.defaultTheme = 0xff489785;
        uiLanguage.value = language;
        addTearDown(() {
          AppSettings.instance.defaultTheme = original;
          uiLanguage.value = UiLanguage.zh;
        });
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize =
            Size(narrow ? 400 : 1120, narrow ? 800 : 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: Entry(welcome: false).fromSchemeAndFontFamily(
                  colorScheme: ColorScheme.fromSeed(
                      seedColor: Colors.teal,
                      brightness: narrow ? Brightness.dark : Brightness.light)),
              locale: language.locale,
              supportedLocales: UiLanguage.values.map((v) => v.locale),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c).copyWith(
                      textScaler: TextScaler.linear(narrow ? 1.6 : 1)),
                  child: UiLanguageScope(child: child!)),
              home: const Scaffold(body: ThemePickerDialog()),
            )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        const output = String.fromEnvironment('DAN_THEME_RENDER');
        Future<void> capture(String suffix) async {
          if (output.isEmpty) return;
          await tester.runAsync(() async {
            final image = await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: drawing.ImageByteFormat.png);
            final file = File('$output/${language.name}-$narrow-$suffix.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('initial');
        final preset = find.byKey(const ValueKey('theme-preset-4286079656'));
        // Choose the purple swatch through the real pointer path.
        await tester.ensureVisible(preset);
        await tester.tap(preset);
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<ColorWheelPicker>(find.byType(ColorWheelPicker))
                .color,
            const Color(0xff7862a8));
        expect(
            tester
                .widget<TextField>(
                    find.byKey(const ValueKey('theme-hex-input')))
                .controller!
                .text,
            '#7862a8');
        expect(AppSettings.instance.defaultTheme, 0xff489785);
        final expectedScheme = ColorScheme.fromSeed(
            seedColor: const Color(0xff7862a8),
            brightness: narrow ? Brightness.dark : Brightness.light);
        final field = tester
            .widget<TextField>(find.byKey(const ValueKey('theme-hex-input')));
        expect(field.cursorColor, expectedScheme.primary);
        expect(field.decoration!.floatingLabelStyle!.color,
            expectedScheme.primary);
        expect(field.decoration!.enabledBorder!.borderSide.color,
            expectedScheme.outlineVariant);
        expect(tester.takeException(), isNull);
        await capture('purple');
      });
    }
  }
}
