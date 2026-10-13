import 'dart:ui' as drawing;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/lyric_letter_spacing_preview.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'lyric_letter_spacing_render_test.dart' show loadLetterSpacingFonts;
import 'support/playlist_feature_fixture.dart' show capturePlaylistFeature;

/// The user replaced glyph tracking with one target-layout group entrance.
/// Check that the actual paint transforms/opacity share that finite clock;
/// native paragraph/attachment oracles below still check the resulting ink.
void expectMainSpacingGroup(
    WidgetTester tester, Finder paragraph, double progress) {
  final group = find.ancestor(
      of: paragraph,
      matching: find.byWidgetPredicate((widget) =>
          widget is Transform && widget.filterQuality == FilterQuality.low));
  if (progress >= 1) {
    expect(group, findsNothing,
        reason: 'The target group finishes without a retained sampling layer');
    return;
  }
  expect(group, findsOneWidget);
  final transform = tester.widget<Transform>(group);
  expect(
      transform.transform.storage[0], closeTo(.96 + .04 * progress, .000001));
  expect(
      transform.transform.storage[5], closeTo(.96 + .04 * progress, .000001));
  final opacity =
      group.evaluate().single.findAncestorWidgetOfExactType<Opacity>()!;
  expect(opacity.alwaysIncludeSemantics, isTrue);
  expect(opacity.opacity, closeTo(progress, .000001));
}

class _NativeParagraph extends CustomPainter {
  const _NativeParagraph(this.paragraph, this.origin);
  final TextPainter paragraph;
  final Offset origin;
  @override
  void paint(Canvas canvas, Size size) => paragraph.paint(canvas, origin);
  @override
  bool shouldRepaint(_NativeParagraph oldDelegate) => true;
}

Future<void> _sameNativeTargetInk(
    WidgetTester tester, GlobalKey boundary, TextPainter reference) async {
  final element = find.byType(CustomPaint).evaluate().singleWhere((element) =>
      (element.widget as CustomPaint).painter is PlainLyricWordFollowPainter);
  final render = element.renderObject! as RenderCustomPaint;
  final original = render.painter! as PlainLyricWordFollowPainter;
  final actual = await _rgba(tester, boundary);
  try {
    render.painter = _NativeParagraph(reference, original.inkOffset);
    tester.binding.rootPipelineOwner.flushCompositingBits();
    tester.binding.rootPipelineOwner.flushPaint();
    expect(await _rgba(tester, boundary), actual,
        reason: 'Independently shaped target glyphs reproduce every pixel '
            'through the actual group entrance and its unchanged origin');
  } finally {
    render.painter = original;
    tester.binding.rootPipelineOwner.flushCompositingBits();
    tester.binding.rootPipelineOwner.flushPaint();
  }
}

Future<List<int>> _rgba(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        return (await image.toByteData(
                format: drawing.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List()
            .toList(growable: false);
      } finally {
        image.dispose();
      }
    }))!;

double _inkCenter(List<int> pixels, int width) {
  var weight = 0.0, position = 0.0;
  for (var offset = 0; offset < pixels.length; offset += 4) {
    final ink =
        (765 - pixels[offset] - pixels[offset + 1] - pixels[offset + 2]) *
            pixels[offset + 3] /
            255;
    weight += ink;
    position += (offset ~/ 4 % width) * ink;
  }
  expect(weight, greaterThan(10000),
      reason: 'Actual glyph ink must be present');
  return position / weight;
}

List<TextPainter> _mainPainters(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<PlainLyricWordFollowPainter>()
    .map((painter) => painter.text)
    .toList();

DesktopLyricTextPainter _previewPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<DesktopLyricTextPainter>()
    .single;

Widget _host(Widget child, {bool layout = true, bool reduced = false}) =>
    MaterialApp(
      theme: ThemeData(
          fontFamily: AppFontPolicy.defaults().uiFamily,
          fontFamilyFallback: AppFontPolicy.defaults().fallback,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: AppFontScope(
        policy: AppFontPolicy.defaults(),
        child: MotionPreferencesScope(
          preferences: MotionPreferences(
              disabled: layout ? const {} : {MotionKind.layout}),
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );

void main({bool onlyRender = false}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadLetterSpacingFonts);

  testWidgets('spacing enters one final native paragraph from early frames',
      (tester) async {
    final appearance = ValueNotifier(DesktopLyricAppearance.defaults);
    final controller = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap({}),
        appearance: appearance)
      ..lyricTextAlign = LyricTextAlign.left;
    final position = ValueNotifier(Duration.zero);
    addTearDown(controller.dispose);
    addTearDown(appearance.dispose);
    addTearDown(position.dispose);
    final line = LrcLine(Duration.zero, '音乐伴每一天', isBlank: false);
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(ChangeNotifierProvider.value(
      value: controller,
      child: RepaintBoundary(
        key: boundary,
        child: Material(
          color: Colors.white,
          child: SizedBox(
            width: 600,
            child: LyricViewTile(
                line: line,
                position: position,
                opacity: 1,
                distance: 0,
                reducedMotion: false),
          ),
        ),
      ),
    )));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byKey(boundary));
    final before = await _rgba(tester, boundary);
    final source = _mainPainters(tester).single;
    final style = source.text!.style!;
    final primaryElement = find.byType(CustomPaint).evaluate().singleWhere(
        (element) => (element.widget as CustomPaint).painter
            is PlainLyricWordFollowPainter);
    final policy = AppFontScope.of(primaryElement);
    TextPainter reference(double spacing, double width) => TextPainter(
          text: appFontSpan(line.content,
              style: style.copyWith(letterSpacing: spacing), policy: policy),
          textAlign: source.textAlign,
          textDirection: source.textDirection,
          textScaler: source.textScaler,
          locale: source.locale,
          strutStyle: source.strutStyle,
          maxLines: source.maxLines,
          ellipsis: source.ellipsis,
          textWidthBasis: source.textWidthBasis,
          textHeightBehavior: source.textHeightBehavior,
        )..layout(minWidth: width, maxWidth: width);
    final oldReference = reference(style.letterSpacing ?? 0, source.width);
    await _sameNativeTargetInk(tester, boundary, oldReference);
    oldReference.dispose();
    await capturePlaylistFeature(
        tester, boundary, 'spacing-visible-main-start');
    controller.setLyricLetterSpacing(8);
    await tester.pump();
    final target = _mainPainters(tester).single;
    expect(target, isNot(same(source)),
        reason: 'The previous spacing retires immediately');
    expect(target.text!.style!.letterSpacing, (style.letterSpacing ?? 0) + 8);
    expect(target.computeLineMetrics(), hasLength(1));
    expect(tester.getSize(find.byKey(boundary)), size);
    final nativeTarget =
        reference((style.letterSpacing ?? 0) + 8, target.width);
    addTearDown(nativeTarget.dispose);
    final paragraph = find.byWidgetPredicate((widget) =>
        widget is CustomPaint && widget.painter is PlainLyricWordFollowPainter);
    expectMainSpacingGroup(tester, paragraph, 0);
    final zero = await _rgba(tester, boundary);
    expect(zero.every((channel) => channel == 255), isTrue,
        reason: 'The old paragraph disappears before the target fades in');

    double progressAt(Duration elapsed) => LyricMotion.curve.transform(
        elapsed.inMicroseconds / LyricMotion.spacingDuration.inMicroseconds);
    await tester.pump(const Duration(milliseconds: 16));
    expectMainSpacingGroup(
        tester, paragraph, progressAt(const Duration(milliseconds: 16)));
    final early = await _rgba(tester, boundary);
    expect(early, isNot(zero));
    expect(_mainPainters(tester).single, same(target));
    await _sameNativeTargetInk(tester, boundary, nativeTarget);
    final startX = _inkCenter(before, size.width.round());
    final earlyX = _inkCenter(early, size.width.round());
    expect(earlyX, greaterThan(startX + .2),
        reason: 'The newly spaced native glyphs are visible from early frames');
    await capturePlaylistFeature(tester, boundary, 'spacing-visible-main-mid');
    await tester.pump(const Duration(milliseconds: 16));
    expectMainSpacingGroup(
        tester, paragraph, progressAt(const Duration(milliseconds: 32)));
    final middle = await _rgba(tester, boundary);
    expect(middle, isNot(early));
    expect(_mainPainters(tester).single, same(target));
    await _sameNativeTargetInk(tester, boundary, nativeTarget);
    expect(tester.getSize(find.byKey(boundary)), size);

    final nearElapsed =
        LyricMotion.spacingDuration - const Duration(milliseconds: 1);
    await tester.pump(nearElapsed - const Duration(milliseconds: 32));
    expectMainSpacingGroup(tester, paragraph, progressAt(nearElapsed));
    final nearEnd = await _rgba(tester, boundary);
    await _sameNativeTargetInk(tester, boundary, nativeTarget);
    await tester.pump(const Duration(milliseconds: 1));
    expectMainSpacingGroup(tester, paragraph, 1);
    final after = await _rgba(tester, boundary);
    expect(_mainPainters(tester).single, same(target),
        reason: 'The final frame keeps the very same target paragraph');
    expect(
        (_inkCenter(after, size.width.round()) -
                _inkCenter(nearEnd, size.width.round()))
            .abs(),
        lessThan(.5),
        reason: 'Finishing the group entrance does not jump the target ink');
    await _sameNativeTargetInk(tester, boundary, nativeTarget);
    await tester.pumpAndSettle();
    expect(await _rgba(tester, boundary), after);
    expect(tester.binding.transientCallbackCount, 0);
    await capturePlaylistFeature(tester, boundary, 'spacing-visible-main-end');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });

  if (onlyRender) return;

  testWidgets(
      'isolated spacing draft preview paints finite retarget and cancel',
      (tester) async {
    final value = ValueNotifier(0.0);
    addTearDown(value.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(RepaintBoundary(
      key: boundary,
      child: Material(
        color: Colors.white,
        child: SizedBox(
          width: 500,
          child: ValueListenableBuilder(
            valueListenable: value,
            builder: (_, current, __) => LyricLetterSpacingPreview(
                value: current, text: 'Music every day'),
          ),
        ),
      ),
    )));
    await tester.pumpAndSettle();
    final before = await _rgba(tester, boundary);
    value.value = 6;
    await tester.pump();
    final target = _previewPainter(tester).cachedShapingIdentities;
    await tester.pump(const Duration(milliseconds: 16));
    expect(await _rgba(tester, boundary), isNot(before));
    expect(_previewPainter(tester).cachedShapingIdentities, target);
    expect(_previewPainter(tester).layoutProgress, greaterThan(0));
    expect(_previewPainter(tester).layoutProgress, lessThan(1));
    value.value = 8;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    value.value = 0;
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_previewPainter(tester).retainsPreviousLayout, isFalse);
    expect(await _rgba(tester, boundary), before);
    expect(_previewPainter(tester).clock.playing, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  for (final gate in ['layout', 'reduced', 'hidden']) {
    testWidgets('spacing draft preview stops immediately for $gate',
        (tester) async {
      var spacing = 0.0;
      Widget host(bool stop) => _host(
          SizedBox(
            width: 500,
            child: LyricLetterSpacingPreview(
                value: spacing,
                text: 'Music every day',
                visible: gate != 'hidden' || !stop),
          ),
          layout: gate != 'layout' || !stop,
          reduced: gate == 'reduced' && stop);
      await tester.pumpWidget(host(false));
      await tester.pumpAndSettle();
      spacing = 8;
      await tester.pumpWidget(host(false));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_previewPainter(tester).retainsPreviousLayout, isTrue);
      await tester.pumpWidget(host(true));
      await tester.pump();
      expect(_previewPainter(tester).retainsPreviousLayout, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }
}
