import 'dart:convert';

import 'package:desktop_lyric/component/desktop_lyric_appearance_options.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _mount(
  WidgetTester tester,
  ValueNotifier<DesktopLyricAppearance> preferences, {
  double scale = 1,
  Color? primary,
  Color? foreground,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(507, 320);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(colorSchemeSeed: Colors.blue, brightness: brightness),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ValueListenableBuilder(
              valueListenable: preferences,
              builder: (context, appearance, _) =>
                  DesktopLyricAppearanceOptions(
                appearance: appearance,
                onChanged: (value) {
                  // Use the same JSON boundary as disk/pipe snapshots for
                  // every edit, including color selections and theme reset.
                  preferences.value = DesktopLyricAppearance.fromJson(
                      jsonDecode(jsonEncode(value.toJson())));
                },
                primaryColor: primary,
                foregroundColor: foreground,
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('shared appearance edits are independent and scroll at $scale',
        (tester) async {
      final preferences = ValueNotifier(DesktopLyricAppearance.defaults
          .copyWith(taskbarMode: true, taskbarHeight: 80, taskbarGap: 24));
      addTearDown(preferences.dispose);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await _mount(tester, preferences, scale: scale);
      final original = preferences.value;
      final bounds = {
        'desktop-lyric-font-size': (18.0, 64.0),
        'desktop-translation-font-size': (14.0, 60.0),
        'desktop-text-opacity': (.2, 1.0),
        'desktop-background-opacity': (0.0, 1.0),
      };
      for (final entry in bounds.entries) {
        final finder = find.byKey(ValueKey(entry.key));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        final slider = tester.widget<Slider>(finder);
        expect((slider.min, slider.max), entry.value);
        slider.onChanged!(entry.value.$1);
        await tester.pump();
        expect(tester.widget<Slider>(finder).value, entry.value.$1);
        tester.widget<Slider>(finder).onChanged!(entry.value.$2);
        await tester.pump();
        expect(tester.widget<Slider>(finder).value, entry.value.$2);
        expect(
            tester
                .widget<Text>(find.byKey(ValueKey('${entry.key}-value')))
                .data,
            entry.key.endsWith('opacity')
                ? '100%'
                : '${entry.value.$2.round()}');
      }
      final stroke = find.byKey(const ValueKey('desktop-lyric-stroke'));
      await tester.ensureVisible(stroke);
      await tester.pumpAndSettle();
      await tester.tap(stroke);
      await tester.pump();
      expect(preferences.value.strokeEnabled, true);
      expect(preferences.value.lyricFontSize, 64);
      expect(preferences.value.translationFontSize, 60);
      expect(preferences.value.taskbarMode, original.taskbarMode);
      expect(preferences.value.taskbarHeight, original.taskbarHeight);
      expect(preferences.value.taskbarGap, original.taskbarGap);
      expect(preferences.value.customColor, null);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('slider pointer drag changes only its own font size',
      (tester) async {
    final preferences = ValueNotifier(DesktopLyricAppearance.defaults);
    addTearDown(preferences.dispose);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await _mount(tester, preferences);
    final slider = find.byKey(const ValueKey('desktop-lyric-font-size'));
    await tester.dragFrom(tester.getCenter(slider), const Offset(90, 0));
    await tester.pumpAndSettle();
    expect(preferences.value.lyricFontSize, greaterThan(22));
    expect(preferences.value.translationFontSize, 18);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('manual color survives theme changes and follow theme clears it',
      (tester) async {
    final preferences = ValueNotifier(DesktopLyricAppearance.defaults);
    addTearDown(preferences.dispose);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const primary = Color(0xffb75424);
    const foreground = Color(0xffefe0dc);
    await _mount(tester, preferences,
        scale: 2, primary: primary, foreground: foreground);
    final color = Colors.purple.toARGB32();
    final swatch =
        find.byKey(ValueKey('desktop-color-${color.toRadixString(16)}'));
    await tester.ensureVisible(swatch);
    await tester.pumpAndSettle();
    expect(tester.getSize(swatch), const Size(44, 44));
    await tester.tap(swatch);
    await tester.pumpAndSettle();
    expect(preferences.value.customColor, color);
    expect(find.text('#FF9C27B0'), findsOneWidget);
    expect(find.byType(DesktopLyricAppearanceOptions), findsOneWidget,
        reason: 'The shared editor must not pop its owner route.');
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics &&
            widget.properties.selected == true &&
            widget.properties.label == '文字颜色 #FF9C27B0'),
        findsOneWidget);

    const updatedPrimary = Color(0xfff4dc91);
    await _mount(tester, preferences,
        scale: 2,
        primary: updatedPrimary,
        foreground: foreground,
        brightness: Brightness.dark);
    expect(preferences.value.customColor, color);
    final font = find.byKey(const ValueKey('desktop-lyric-font-size'));
    final sliderTheme = SliderTheme.of(tester.element(font));
    expect(sliderTheme.thumbColor, updatedPrimary);
    expect(sliderTheme.valueIndicatorColor, updatedPrimary);
    expect(sliderTheme.valueIndicatorTextStyle!.color, Colors.black);
    final stroke = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('desktop-lyric-stroke')));
    expect(stroke.activeThumbColor, updatedPrimary);
    expect((stroke.title! as Text).style!.color, foreground);
    final follow = find.byKey(const ValueKey('desktop-color-follow-theme'));
    await tester.ensureVisible(follow);
    await tester.pumpAndSettle();
    await tester.tap(follow);
    await tester.pumpAndSettle();
    expect(preferences.value.customColor, null);
    expect(
        find.byKey(const ValueKey('desktop-custom-color-value')), findsNothing);
    expect(find.text('正在跟随播放器主题'), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('omitted theme overrides use the host dynamic color scheme',
      (tester) async {
    final preferences = ValueNotifier(DesktopLyricAppearance.defaults);
    addTearDown(preferences.dispose);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await _mount(tester, preferences);
    final slider = find.byKey(const ValueKey('desktop-lyric-font-size'));
    final context = tester.element(slider);
    final scheme = Theme.of(context).colorScheme;
    expect(SliderTheme.of(context).thumbColor, scheme.primary);
    expect(SliderTheme.of(context).valueIndicatorColor, scheme.primary);
    expect(
        SliderTheme.of(context).valueIndicatorTextStyle!.color, Colors.white);
    expect(
        tester.widget<Text>(find.text('原文字号')).style!.color, scheme.onSurface);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
