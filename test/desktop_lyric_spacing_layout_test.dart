import 'package:desktop_lyric/component/desktop_lyric_appearance_options.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

Finder _key(String name) => find.byKey(ValueKey(name));

RenderParagraph _value(WidgetTester tester, String id) =>
    tester.renderObject<RenderParagraph>(_key('$id-value'));

double _baseline(RenderParagraph paragraph) {
  final value =
      paragraph.getDryBaseline(paragraph.constraints, TextBaseline.alphabetic);
  expect(value, isNotNull);
  return value!;
}

Rect _track(WidgetTester tester, String id) {
  RenderBox? render;
  void visit(RenderObject object) {
    if (object.runtimeType.toString() == '_RenderSlider') {
      render = object as RenderBox;
      return;
    }
    object.visitChildren(visit);
  }

  final finder = _key(id);
  visit(tester.renderObject(finder));
  expect(render, isNotNull, reason: 'Inspect the actual Material slider track');
  final dynamic sliderRender = render!;
  final theme = sliderRender.sliderTheme as SliderThemeData;
  final slider = tester.widget<Slider>(finder);
  final bounds = theme.trackShape!.getPreferredRect(
      parentBox: render!,
      sliderTheme: theme,
      isEnabled: slider.onChanged != null,
      isDiscrete: slider.divisions != null);
  return bounds.shift(render!.localToGlobal(Offset.zero));
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final language in UiLanguage.values) {
    for (final size in [(1000.0, 1.0), (360.0, 2.0)]) {
      testWidgets(
          'desktop spacing matches adjacent sliders ${language.code} ${size.$1} ${size.$2}',
          (tester) async {
        uiLanguage.value = language;
        sizePlaylistFeature(tester, width: size.$1, height: 900);
        final boundary = GlobalKey();
        var writes = 0;
        await tester.pumpWidget(playlistFeatureHost(
            SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: DesktopLyricAppearanceOptions(
                    appearance: DesktopLyricAppearance.defaults
                        .copyWith(lyricFontSize: 23),
                    section: DesktopLyricOptionSection.sliders,
                    onChanged: (_) => writes++)),
            textScale: size.$2,
            boundary: boundary));
        await tester.pumpAndSettle();
        await capturePlaylistFeature(tester, boundary,
            'desktop-spacing-${language.code}-${size.$1.toInt()}-${size.$2.toInt()}');

        const spacingId = 'desktop-lyric-letter-spacing';
        final spacing = _value(tester, spacingId);
        final spacingTrack = _track(tester, '$spacingId-slider');
        final style = spacing.text.style!;
        for (final referenceId in [
          'desktop-lyric-font-size',
          'desktop-translation-font-size',
          'desktop-text-opacity',
          'desktop-background-opacity',
        ]) {
          final reference = _value(tester, referenceId);
          final referenceStyle = reference.text.style!;
          expect(style.fontSize, referenceStyle.fontSize,
              reason: 'Numeric values share their actual inherited font size');
          expect(style.fontFamily, referenceStyle.fontFamily);
          expect(style.fontWeight, referenceStyle.fontWeight);
          expect(style.color, referenceStyle.color);
          expect(spacing.size.height, closeTo(reference.size.height, .01));
          expect(_baseline(spacing), closeTo(_baseline(reference), .01));
          expect(
              spacing.localToGlobal(Offset(spacing.size.width, 0)).dx,
              closeTo(
                  reference.localToGlobal(Offset(reference.size.width, 0)).dx,
                  .01));
          final referenceTrack = _track(tester, referenceId);
          expect(spacingTrack.left, closeTo(referenceTrack.left, .01));
          expect(spacingTrack.right, closeTo(referenceTrack.right, .01));
          expect(spacingTrack.height, closeTo(referenceTrack.height, .01));
        }
        expect(spacingTrack.left, greaterThanOrEqualTo(0));
        expect(spacingTrack.right, lessThanOrEqualTo(size.$1));
        expect(writes, 0, reason: 'Rendering never changes saved appearance');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }
}
