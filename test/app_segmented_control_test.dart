import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/audio_columns.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child,
        {double scale = 1,
        Brightness brightness = Brightness.light,
        Color seed = Colors.teal}) =>
    MaterialApp(
      locale: uiLanguage.value.locale,
      supportedLocales: UiLanguage.values.map((language) => language.locale),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: applyAppControlTheme(ThemeData(
        fontFamily: danEmbeddedFontFamily,
        fontFamilyFallback: danFontFamilyFallback,
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
      )),
      builder: (context, child) => UiLanguageScope(
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale), disableAnimations: true),
          child: child!,
        ),
      ),
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader(danEmbeddedFontFamily)
      ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf'));
    await loader.load();
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final language in UiLanguage.values) {
    for (final width in [96.0, 320.0, 1080.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final brightness in Brightness.values) {
          testWidgets('three choices fit $language/$width/$scale/$brightness',
              (tester) async {
            uiLanguage.value = language;
            var selected = 0;
            var changes = 0;
            await tester.pumpWidget(_app(
                StatefulBuilder(
                  builder: (context, setState) => SizedBox(
                    width: width,
                    child: AppSegmentedControl<int>(
                      value: selected,
                      semanticLabel: ui('歌单视图'),
                      options: [
                        AppSegmentOption(
                            value: 0, label: ui('列表'), icon: Icons.list),
                        AppSegmentOption(
                            value: 1, label: ui('方形网格'), icon: Icons.grid_view),
                        AppSegmentOption(
                            value: 2, label: ui('圆形封面'), icon: Icons.album),
                      ],
                      onChanged: (value) => setState(() {
                        selected = value;
                        changes++;
                      }),
                    ),
                  ),
                ),
                scale: scale,
                brightness: brightness));
            await tester.pumpAndSettle();
            final segmented = find.byType(SegmentedButton<int>);
            if (segmented.evaluate().isEmpty) {
              await tester.tap(find.byType(IconButton).evaluate().isNotEmpty
                  ? find.byType(IconButton)
                  : find.byType(OutlinedButton));
              await tester.pumpAndSettle();
            }
            await tester.tap(find.text(ui('圆形封面')).last);
            await tester.pumpAndSettle();
            expect(selected, 2);
            expect(changes, 1);
            expect(tester.takeException(), isNull);
            final bounds =
                tester.getRect(find.byType(AppSegmentedControl<int>));
            expect(bounds.width, lessThanOrEqualTo(width));
            if (segmented.evaluate().isNotEmpty) {
              final widget = tester.widget<SegmentedButton<int>>(segmented);
              final scheme = Theme.of(tester.element(segmented)).colorScheme;
              expect(
                  widget.style!.foregroundColor!.resolve({}), scheme.primary);
              expect(
                  widget.style!.foregroundColor!
                      .resolve({WidgetState.selected}),
                  scheme.onPrimaryContainer);
              expect(widget.style!.textStyle!.resolve({})!.fontFamily,
                  danEmbeddedFontFamily);
            }
          });
        }
      }
    }
  }

  testWidgets('unequal labels use equal segment width for the fit decision',
      (tester) async {
    await tester.pumpWidget(_app(SizedBox(
      width: 320,
      child: AppSegmentedControl<int>(
        value: 0,
        options: const [
          AppSegmentOption(value: 0, label: 'A', icon: Icons.list),
          AppSegmentOption(
              value: 1,
              label: 'A particularly long album view',
              icon: Icons.album),
        ],
        onChanged: (_) {},
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<int>), findsNothing);
    expect(find.byType(MenuAnchor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'page selector explicitly selects grid and ignores repeated selection',
      (tester) async {
    var current = ContentView.list;
    var changes = 0;
    await tester.pumpWidget(_app(StatefulBuilder(
        builder: (context, setState) => ContentViewSwitch(
            contentView: current,
            setContentView: (value) => setState(() {
                  current = value;
                  changes++;
                })))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('网格'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('网格'));
    await tester.pumpAndSettle();
    expect(current, ContentView.table);
    expect(changes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabling an open fallback removes its actions', (tester) async {
    var enabled = true;
    var changes = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(_app(StatefulBuilder(builder: (context, setState) {
      rebuild = setState;
      return AppSegmentedControl<int>(
          value: 0,
          compact: true,
          maxWidth: 96,
          options: const [
            AppSegmentOption(value: 0, label: 'First', icon: Icons.list),
            AppSegmentOption(value: 1, label: 'Second', icon: Icons.album)
          ],
          onChanged: enabled ? (_) => changes++ : null);
    })));
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    rebuild(() => enabled = false);
    await tester.pumpAndSettle();
    final second = tester
        .widget<MenuItemButton>(find.widgetWithText(MenuItemButton, 'Second'));
    expect(second.onPressed, isNull);
    final check = find.byIcon(Icons.check);
    expect(tester.widget<Icon>(check).color, isNull);
    final checkContext = tester.element(check);
    expect(
        IconTheme.of(checkContext).color!.toARGB32(),
        Theme.of(checkContext)
            .colorScheme
            .onSurface
            .withValues(alpha: .38)
            .toARGB32());
    expect(changes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'column headings retain font and follow live palette with rounded frame',
      (tester) async {
    for (final seed in [Colors.teal, Colors.purple]) {
      await tester.pumpWidget(_app(
          const SizedBox(width: 760, child: AudioColumnsHeader()),
          seed: seed));
      await tester.pumpAndSettle();
      final heading = find.text('歌名');
      final scheme = Theme.of(tester.element(heading)).colorScheme;
      final text = tester.widget<Text>(heading);
      expect(text.style!.fontFamily, danEmbeddedFontFamily);
      expect(text.style!.color, scheme.primary);
      final container = tester.widget<Container>(
          find.byKey(const ValueKey('audio-columns-header')));
      expect((container.decoration as BoxDecoration).borderRadius,
          BorderRadius.circular(14));
      expect(tester.takeException(), isNull);
    }
  });
}
