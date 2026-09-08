import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_action_icon.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/ui_layout_options.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/page/settings_page/other_settings.dart';
import 'package:dan_player/page/settings_page/theme_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/ui_layout_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _alternateFont = 'QAControlSelectedFont';

ThemeData _theme(Color seed, Brightness brightness, String font) =>
    Entry(welcome: false).fromSchemeAndFontFamily(
      colorScheme:
          ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
      fontFamily: font,
    );

Widget _host(
  Widget child, {
  Color seed = Colors.teal,
  Brightness brightness = Brightness.light,
  bool highContrast = false,
  String font = danEmbeddedFontFamily,
  double scale = 1,
}) =>
    UiLanguageScope(
      child: MaterialApp(
        theme: _theme(seed, brightness, font),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            highContrast: highContrast,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: Scaffold(body: Center(child: child)),
      ),
    );

class _Controls extends StatelessWidget {
  const _Controls(this.tooltipKey);
  final GlobalKey<TooltipState> tooltipKey;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Tooltip(
        key: tooltipKey,
        message: ui('切换列表视图'),
        child: const Icon(Icons.view_list),
      ),
      const SizedBox(height: 28),
      // Exercise the global theme, not a locally styled lookalike.
      SegmentedButton<bool>(
        showSelectedIcon: false,
        selected: const {true},
        onSelectionChanged: (_) {},
        segments: [
          ButtonSegment(value: true, label: Text(ui('本地'))),
          ButtonSegment(value: false, label: Text(ui('在线'))),
        ],
      ),
    ]);
  }
}

RichText _rich(WidgetTester tester, String text) => tester.widget<RichText>(
      find
          .byWidgetPredicate((widget) =>
              widget is RichText && widget.text.toPlainText() == text)
          .last,
    );

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Register the production font and a selected-family alias of that same
    // real font; no Ahem-only width assertions or installed-font/file access.
    for (final family in [danEmbeddedFontFamily, _alternateFont]) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf'));
      await loader.load();
    }
  });
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() {
    Tooltip.dismissAllToolTips();
    uiLanguage.value = UiLanguage.zh;
  });

  test('real selected font provides non-Ahem metrics and complete theme styles',
      () {
    final theme = _theme(Colors.teal, Brightness.light, _alternateFont);
    final style = theme.tooltipTheme.textStyle!;
    expect(style.fontFamily, _alternateFont);
    expect(style.fontFamilyFallback, danFontFamilyFallback);
    final painter = TextPainter(textDirection: TextDirection.ltr);
    painter.text = TextSpan(text: 'iiii', style: style);
    painter.layout();
    final narrow = painter.width;
    painter.text = TextSpan(text: 'WWWW', style: style);
    painter.layout();
    expect(painter.width, greaterThan(narrow * 1.5));
    painter.dispose();
    expect(theme.segmentedButtonTheme.style!.textStyle!.resolve({})!.fontFamily,
        _alternateFont);
    expect(PlayService.isInitialized, isFalse);
  });

  for (final brightness in Brightness.values) {
    for (final highContrast in [false, true]) {
      for (final language in UiLanguage.values) {
        testWidgets(
            'real overlay font/colors $brightness HC=$highContrast ${language.code}',
            (tester) async {
          uiLanguage.value = language;
          final key = GlobalKey<TooltipState>();
          final font = highContrast ? _alternateFont : danEmbeddedFontFamily;
          final theme = _theme(Colors.teal, brightness, font);
          await tester.pumpWidget(_host(_Controls(key),
              brightness: brightness,
              highContrast: highContrast,
              font: font,
              scale: 2));
          await tester.pumpAndSettle();
          expect(key.currentState!.ensureTooltipVisible(), isTrue);
          await tester.pumpAndSettle();
          final tooltip = _rich(tester, ui('切换列表视图')).text.style!;
          final selected = _rich(tester, ui('本地')).text.style!;
          final unselected = _rich(tester, ui('在线')).text.style!;
          for (final style in [tooltip, selected, unselected]) {
            expect(style.fontFamily, font);
            expect(style.fontFamilyFallback, danFontFamilyFallback);
          }
          final scheme = theme.colorScheme;
          expect(tooltip.color, scheme.onSurface);
          expect(selected.color, scheme.onPrimaryContainer);
          expect(unselected.color, scheme.primary);
          final decoration = theme.tooltipTheme.decoration! as BoxDecoration;
          final tooltipSurface =
              Color.alphaBlend(decoration.color!, scheme.surface);
          expect(_contrast(tooltip.color!, tooltipSurface),
              greaterThanOrEqualTo(4.5));
          expect(_contrast(selected.color!, scheme.primaryContainer),
              greaterThanOrEqualTo(4.5));
          expect(_contrast(unselected.color!, scheme.surface),
              greaterThanOrEqualTo(4.5));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets('an already-open tooltip follows live font and palette changes',
      (tester) async {
    final key = GlobalKey<TooltipState>();
    final controls = _Controls(key);
    await tester.pumpWidget(_host(controls));
    await tester.pumpAndSettle();
    key.currentState!.ensureTooltipVisible();
    await tester.pumpAndSettle();
    final state = key.currentState;
    await tester.pumpWidget(_host(controls,
        seed: Colors.deepOrange,
        brightness: Brightness.dark,
        font: _alternateFont));
    await tester.pumpAndSettle();
    final style = _rich(tester, ui('切换列表视图')).text.style!;
    expect(style.fontFamily, _alternateFont);
    expect(
        style.color,
        _theme(Colors.deepOrange, Brightness.dark, _alternateFont)
            .colorScheme
            .onSurface);
    expect(key.currentState, same(state));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'action icons match labels through live palette changes and keep filled contrast',
      (tester) async {
    final controls = Builder(
        builder: (context) => Row(children: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.my_location)),
              const IconButton(onPressed: null, icon: Icon(Icons.undo)),
              TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.repeat),
                  label: const Text('A–B')),
              AppIconActionButton(
                  tooltip: 'More',
                  glyph: AppActionGlyph.moreVertical,
                  onPressed: () {}),
              IconButton.filledTonal(
                  style: appToolbarControlStyle(context,
                      primary: true, tonal: true, iconOnly: true),
                  onPressed: () {},
                  icon: const Icon(Icons.select_all)),
            ]));
    for (final (seed, brightness) in [
      (Colors.teal, Brightness.light),
      (Colors.deepOrange, Brightness.dark),
      (Colors.purple, Brightness.light),
    ]) {
      await tester
          .pumpWidget(_host(controls, seed: seed, brightness: brightness));
      await tester.pumpAndSettle();
      final scheme =
          _theme(seed, brightness, danEmbeddedFontFamily).colorScheme;
      Color? iconColor(IconData data) {
        final icon = find.byIcon(data);
        return tester.widget<Icon>(icon).color ??
            IconTheme.of(tester.element(icon)).color;
      }

      for (final icon in [
        Icons.my_location,
        Icons.repeat,
        AppActionGlyph.moreVertical.icon
      ]) {
        expect(iconColor(icon), scheme.primary);
      }
      expect(iconColor(Icons.undo), scheme.onSurface.withValues(alpha: .38));
      expect(iconColor(Icons.select_all), scheme.onSecondaryContainer);
      expect(_contrast(iconColor(Icons.select_all)!, scheme.secondaryContainer),
          greaterThanOrEqualTo(3));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('search and category chips follow live player theme colors',
      (tester) async {
    final colors = <String, List<Color>>{};
    final controls = Builder(
        builder: (context) => Wrap(children: [
              FilledButton.tonal(
                  style: appToolbarControlStyle(context,
                      primary: true, tonal: true),
                  onPressed: () {},
                  child: const AppToolbarLabel(
                      label: 'Search QA', icon: Icons.search)),
              ChoiceChip(
                  label: const Text('Selected QA'),
                  avatar: const Icon(Icons.person),
                  selected: true,
                  showCheckmark: false,
                  onSelected: (_) {}),
              ChoiceChip(
                  label: const Text('Unselected QA'),
                  avatar: const Icon(Icons.album),
                  selected: false,
                  showCheckmark: false,
                  onSelected: (_) {}),
            ]));
    for (final brightness in Brightness.values) {
      colors.clear();
      for (final seed in [Colors.amber, Colors.blue, Colors.purple]) {
        await tester
            .pumpWidget(_host(controls, seed: seed, brightness: brightness));
        await tester.pumpAndSettle();
        for (final label in ['Search QA', 'Selected QA', 'Unselected QA']) {
          final color = DefaultTextStyle.of(tester.element(find.text(label)))
              .style
              .color!;
          (colors[label] ??= []).add(color);
        }
        for (final icon in [Icons.search, Icons.person, Icons.album]) {
          final finder = find.byIcon(icon);
          final color = tester.widget<Icon>(finder).color ??
              IconTheme.of(tester.element(finder)).color!;
          (colors[icon.toString()] ??= []).add(color);
        }
      }
      for (final entry in colors.entries) {
        expect(entry.value.toSet().length, 3,
            reason: '${entry.key} must follow each palette in $brightness');
      }
    }
  });

  testWidgets('settings alternatives use shared control with explicit labels',
      (tester) async {
    uiLanguage.value = UiLanguage.en;
    await tester.pumpWidget(_host(const SizedBox(
      width: 900,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ThemeModeControl(),
        DefaultLyricSourceControl(),
      ]),
    )));
    await tester.pumpAndSettle();
    final theme = tester.widget<AppSegmentedControl<ThemeMode>>(
        find.byType(AppSegmentedControl<ThemeMode>));
    final lyric = tester.widget<AppSegmentedControl<bool>>(
        find.byType(AppSegmentedControl<bool>));
    expect(theme.options.map((option) => option.value),
        [ThemeMode.system, ThemeMode.light, ThemeMode.dark]);
    expect(theme.options.map((option) => option.label),
        ['System', 'Light', 'Dark']);
    expect(lyric.options.map((option) => option.value), [true, false]);
    expect(lyric.options.map((option) => option.label), ['Local', 'Online']);
    // Do not invoke settings persistence: these are read-only UI checks.
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout choices stay available in narrow four-language menus',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      var value = const UiLayoutPreferences();
      await tester.pumpWidget(_host(
          StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: UiLayoutOptions(
                  value: value,
                  onChanged: (next) => setState(() => value = next)),
            ),
          ),
          scale: 2));
      await tester.pumpAndSettle();
      final control = find.byType(AppSegmentedControl<LibraryRowLayout>);
      expect(find.descendant(of: control, matching: find.byType(MenuAnchor)),
          findsOneWidget);
      await tester.tap(find.byTooltip('${ui('音乐列表样式')} · ${ui('经典列表')}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ui('资源管理器分栏')));
      await tester.pumpAndSettle();
      expect(value.libraryRowLayout, LibraryRowLayout.columns);
      expect(value.compactPlaylists, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
