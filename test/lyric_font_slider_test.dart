import 'package:dan_player/app_preference.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('lyric font slider supports track taps and thumb drags',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = NowPlayingPagePreference(
        NowPlayingViewMode.withLyric, LyricTextAlign.left, 39, 35);
    final controller = LyricViewController(preferences: preferences);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider.value(
          value: controller,
          child: const Align(
              alignment: Alignment.centerRight, child: LyricFontSizeMenu()),
        ),
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('lyric-font-size-open')));
    await tester.pumpAndSettle();
    final primary = Theme.of(tester.element(find.byType(LyricFontSizeMenu)))
        .colorScheme
        .primary;
    expect(tester.widget<Text>(find.text('A±')).style?.color, primary);
    final number = tester.widget<Text>(find.text('39'));
    expect(number.style?.color, primary);
    expect(number.style?.fontSize, 18);
    expect(tester.widget<Text>(find.text('A±')).style?.fontWeight,
        FontWeight.w400);
    final slider = find.byKey(const ValueKey('lyric-font-size-slider'));
    expect(tester.widget<Slider>(slider).allowedInteraction,
        SliderInteraction.tapAndSlide);
    expect(tester.widget<Slider>(slider).divisions, 50);
    final rect = tester.getRect(slider);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
    await tester.tapAt(Offset(rect.right - 18, rect.center.dy));
    await tester.pump();
    expect(slider, findsOneWidget);
    expect(controller.lyricFontSize, greaterThan(39));
    expect(controller.translationFontSize,
        closeTo(controller.lyricFontSize - 4, .0001));
    expect(controller.fontDragPreviewSize, isNull,
        reason: 'A track tap keeps the normal target-glyph animation');

    controller.setFontSize(39);
    await tester.pump();

    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(const Offset(48, 0));
    await tester.pump();
    expect(controller.lyricFontSize, 39);
    expect(tester.widget<Slider>(slider).value, greaterThan(39));
    expect(controller.fontSizeAdjusting, isTrue);
    expect(controller.fontDragPreviewSize, greaterThan(39));
    expect(preferences.lyricFontSize, 39);
    await gesture.up();
    await tester.pump();
    expect(controller.lyricFontSize, greaterThan(39));
    expect(controller.lyricFontSize, controller.lyricFontSize.roundToDouble());
    expect(controller.directFontSize, isTrue);
    expect(preferences.lyricFontSize, controller.lyricFontSize);
    expect(preferences.translationFontSize,
        closeTo(controller.lyricFontSize - 4, .0001));
    expect(controller.fontSizeAdjusting, isFalse);
    expect(controller.fontDragPreviewSize, isNull);

    controller.setFontSize(39);
    await tester.pump();
    final returnGesture = await tester.startGesture(rect.center);
    await returnGesture.moveBy(const Offset(48, 0));
    await tester.pump();
    expect(controller.fontDragPreviewSize, greaterThan(39));
    await returnGesture.moveBy(const Offset(-48, 0));
    await tester.pump();
    expect(controller.fontDragPreviewSize, isNull);
    await returnGesture.up();
    await tester.pump();
    expect(controller.lyricFontSize, 39);
    expect(controller.fontDragPreviewSize, isNull);
    await tester.tap(find.byKey(const ValueKey('lyric-font-size-open')));
    await tester.pumpAndSettle();
    expect(controller.fontSizeAdjusting, isFalse);
  });

  testWidgets('exact entry and presets apply an integer lyric size',
      (tester) async {
    final preferences = NowPlayingPagePreference(
        NowPlayingViewMode.withLyric, LyricTextAlign.left, 22, 18);
    final controller = LyricViewController(preferences: preferences);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider.value(
          value: controller,
          child: const Align(
              alignment: Alignment.centerRight, child: LyricFontSizeMenu()),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('lyric-font-size-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lyric-font-size-exact')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('player-number-input')), '27');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(controller.lyricFontSize, 27);
    expect(controller.translationFontSize, 23);

    final preset = find.byKey(const ValueKey('lyric-font-size-preset-48'));
    if (preset.evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('lyric-font-size-open')));
      await tester.pumpAndSettle();
    }
    await tester.tap(preset);
    await tester.pumpAndSettle();
    expect(controller.lyricFontSize, 48);
    expect(controller.translationFontSize, 44);
  });

  testWidgets('slider and preset sizes keep one selected glyph layout',
      (tester) async {
    Widget sample(double size, {bool direct = true}) => MaterialApp(
          home: Center(
            child: LyricLineMotion(
              opacity: 1,
              scale: 1,
              activation: 0,
              alignment: Alignment.centerLeft,
              presentation: (
                fontSize: size,
                translationFontSize: size,
                alignment: Alignment.centerLeft,
              ),
              directFontSize: direct,
              reducedMotion: false,
              builder: (context, activation, presentation, transition) {
                return Text('font sample',
                    style: TextStyle(fontSize: presentation.fontSize));
              },
            ),
          ),
        );
    double painted() =>
        tester.widget<Text>(find.text('font sample')).style!.fontSize!;

    await tester.pumpWidget(sample(22));
    await tester.pumpWidget(sample(32));
    expect(painted(), closeTo(32, .001));
    await tester.pump(const Duration(milliseconds: 155));
    expect(painted(), closeTo(32, .001));
    await tester.pump(const Duration(milliseconds: 100));
    expect(painted(), closeTo(32, .001));

    await tester.pumpWidget(sample(18));
    expect(painted(), closeTo(18, .001));
    await tester.pump(const Duration(milliseconds: 155));
    expect(painted(), closeTo(18, .001));
    await tester.pump(const Duration(milliseconds: 100));
    expect(painted(), closeTo(18, .001));

    await tester.pumpWidget(sample(22, direct: false));
    await tester.pump(const Duration(milliseconds: 50));
    expect(painted(), inExclusiveRange(18, 22));
    await tester.pump(LyricMotion.lineDuration);
    expect(painted(), closeTo(22, .001));
  });

  testWidgets('font size presets remain usable in a narrow scaled window',
      (tester) async {
    tester.view.physicalSize = const Size(240, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = LyricViewController(
      preferences: NowPlayingPagePreference(
          NowPlayingViewMode.withLyric, LyricTextAlign.left, 22, 18),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: ChangeNotifierProvider.value(
          value: controller,
          child: const Align(
              alignment: Alignment.centerRight, child: LyricFontSizeMenu()),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('lyric-font-size-open')));
    await tester.pumpAndSettle();
    for (final size in [18, 22, 32, 48]) {
      expect(
          find.byKey(ValueKey('lyric-font-size-preset-$size')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  test('continuous sizes preserve the auxiliary offset after clamping', () {
    final preferences = NowPlayingPagePreference(
        NowPlayingViewMode.withLyric, LyricTextAlign.left, 22, 18);
    final controller = LyricViewController(preferences: preferences);
    addTearDown(controller.dispose);
    controller.setFontSize(14);
    expect((controller.lyricFontSize, controller.translationFontSize),
        (14.0, 14.0));
    controller.setFontSize(22.25);
    expect((controller.lyricFontSize, controller.translationFontSize),
        (22.25, 18.25));
    expect(preferences.toMap()['lyricFontSize'], 22.25);
    controller.setFontSize(double.nan);
    expect(controller.lyricFontSize, 22.25);
  });
}
