import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Keep separate author words (including whitespace), UTF-16 offsets, and
// timing throughout the font/geometry changes. Font runs are only a view.
const _parts = [
  '漢字',
  '\n',
  'かな ',
  'English ',
  'e\u0301',
  '\n',
  '한글 ',
  '👩🏽‍🚀',
  '\n',
  'שלום ',
  'العربية',
];
final _text = _parts.join();
const _captureHeight = 420.0;

class _Word extends SyncLyricWord {
  _Word(int index, String content)
      : super(Duration(milliseconds: index * 400),
            const Duration(milliseconds: 600), content);
}

class _Line extends SyncLyricLine {
  _Line()
      : super(Duration.zero, const Duration(seconds: 8), [
          for (final (index, part) in _parts.indexed) _Word(index, part),
        ]);
}

({TextPainter text, CustomPainter painter, Size size}) _paint(GlobalKey key) {
  ({TextPainter text, CustomPainter painter, Size size})? result;
  void visit(Element element) {
    if (element.widget case CustomPaint(painter: final painter)) {
      final text = switch (painter) {
        PlainLyricWordFollowPainter() => painter.text,
        LyricWordHighlightPainter() => painter.text,
        _ => null,
      };
      if (text != null) {
        result = (
          text: text,
          painter: painter!,
          size: (element.renderObject! as RenderBox).size
        );
      }
    }
    element.visitChildren(visit);
  }

  visit(key.currentContext! as Element);
  return result!;
}

List<({int start, int end, String? family})> _fontExtents(InlineSpan span) {
  var offset = 0;
  final result = <({int start, int end, String? family})>[];
  void visit(InlineSpan value, String? inherited) {
    final family = value.style?.fontFamily ?? inherited;
    if (value is TextSpan) {
      final text = value.text;
      if (text != null && text.isNotEmpty) {
        result.add((start: offset, end: offset + text.length, family: family));
        offset += text.length;
      }
      for (final child in value.children ?? const <InlineSpan>[]) {
        visit(child, family);
      }
    }
  }

  visit(span, null);
  expect(offset, _text.length);
  return result;
}

void _checkFamilies(TextPainter painter, AppFontPolicy policy) {
  final extents = _fontExtents(painter.text!);
  String? familyAt(String token) {
    final offset = _text.indexOf(token);
    return extents
        .singleWhere((span) => span.start <= offset && offset < span.end)
        .family;
  }

  if (policy.mixedScripts) {
    expect(familyAt('English'), policy.en.family);
    expect(familyAt('e\u0301'), policy.en.family);
    expect(familyAt('かな'), policy.ja.family);
    expect(familyAt('한글'), policy.ko.family);
    final hanLanguage =
        policy.language == UiLanguage.en ? UiLanguage.zh : policy.language;
    expect(familyAt('漢字'), policy.faceFor(hanLanguage).family,
        reason: 'Kana/Hangul on another line must not claim this Han row.');
  } else {
    expect(extents.every((span) => span.family == policy.uiFamily), isTrue);
  }
  final boundaries = <int>{0};
  var offset = 0;
  for (final cluster in _text.characters) {
    offset += cluster.length;
    boundaries.add(offset);
  }
  for (final span in extents) {
    expect(boundaries.contains(span.start), isTrue);
    expect(boundaries.contains(span.end), isTrue,
        reason: 'A style run must retain the entire emoji/combining cluster.');
  }
}

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey key,
    {String? captureName}) async {
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data =
          await image.toByteData(format: raster.ImageByteFormat.rawRgba);
      final directory = Platform.environment['DAN_PLAYER_FONT_RENDER_DIR'];
      if (directory != null && captureName != null) {
        final output = File('$directory/$captureName.png');
        await output.parent.create(recursive: true);
        final png = await image.toByteData(format: raster.ImageByteFormat.png);
        await output.writeAsBytes(png!.buffer.asUint8List());
      }
      return Uint8List.fromList(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

int _inkPixels(Uint8List pixels) {
  var count = 0;
  for (var i = 0; i < pixels.length; i += 4) {
    if (pixels[i + 3] != 0 &&
        (pixels[i] < 245 || pixels[i + 1] < 245 || pixels[i + 2] < 245)) {
      count++;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => ensureAppFontsLoaded(AppFontPolicy.defaults()));

  for (final language in UiLanguage.values) {
    for (final timed in [false, true]) {
      testWidgets(
          'player ${language.code} ${timed ? 'timed' : 'plain'} mixed '
          'fonts retain width shaping and invalidate policy', (tester) async {
        final settings = LyricViewController()
          ..lyricFontSize = 16
          ..lyricTextAlign = LyricTextAlign.left;
        final position = ValueNotifier(const Duration(milliseconds: 1550));
        final preferences =
            ValueNotifier(const RenderingPreferences(surfaceBlur: false));
        addTearDown(settings.dispose);
        addTearDown(position.dispose);
        addTearDown(preferences.dispose);
        final line = _Line();
        final words = line.words;
        final author = [
          for (final word in words) (word.start, word.length, word.content)
        ];
        final offsets = <(int, int)>[];
        var offset = 0;
        for (final part in _parts) {
          offsets.add((offset, offset + part.length));
          offset += part.length;
        }
        final mixed = AppFontPolicy.defaults(language: language);
        final changedEnglish = AppFontPolicy(
            language: language,
            mixedScripts: true,
            zh: mixed.zh,
            en: mixed.zh,
            ja: mixed.ja,
            ko: mixed.ko,
            baseFallback: mixed.baseFallback);
        final uniform = AppFontPolicy(
            language: language,
            mixedScripts: false,
            zh: mixed.zh,
            en: mixed.zh,
            ja: mixed.zh,
            ko: mixed.zh,
            baseFallback: mixed.baseFallback);
        final direction = language == UiLanguage.en || language == UiLanguage.ko
            ? TextDirection.rtl
            : TextDirection.ltr;
        final retained = GlobalKey(), fresh = GlobalKey();
        var revision = 0;
        TextPainter? previousPolicyPainter;
        Uint8List? previousPolicyPixels;
        for (final (policyIndex, policy)
            in [mixed, changedEnglish, uniform].indexed) {
          final shapedParagraphs = <TextPainter>{};
          Object? previousLayout;
          for (final (widthIndex, width)
              in [340.0, 260.0, 259.0, 191.0, 190.0, 261.0, 340.0].indexed) {
            revision++;
            position.value =
                Duration(milliseconds: widthIndex.isEven ? 1550 : 420);
            Widget pane(GlobalKey key, Key paragraphKey) => RepaintBoundary(
                key: key,
                child: ColoredBox(
                    color: Colors.white,
                    child: SizedBox(
                        width: width,
                        height: _captureHeight,
                        child: timed
                            ? SingleChildScrollView(
                                child: LyricViewTile(
                                    key: paragraphKey,
                                    line: line,
                                    position: position,
                                    opacity: 1,
                                    distance: 0,
                                    reducedMotion: false))
                            : Align(
                                alignment: Alignment.topLeft,
                                child: BalancedLyricText(_text,
                                    key: paragraphKey,
                                    wordFollow: true,
                                    alignmentX: -1,
                                    textAlign: TextAlign.left,
                                    style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        height: 1.3,
                                        color: Colors.black))))));
            await tester.pumpWidget(MaterialApp(
                locale: language.locale,
                supportedLocales: [
                  for (final value in UiLanguage.values) value.locale
                ],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: ThemeData(
                    fontFamily: mixed.zh.family,
                    textTheme: ThemeData().textTheme.apply(
                        fontFamily: mixed.zh.family,
                        fontFamilyFallback: mixed.fallback)),
                home: AppFontScope(
                    policy: policy,
                    child: RenderingPreferencesScope(
                        preferences: preferences,
                        child: Directionality(
                            textDirection: direction,
                            child: Material(
                                color: Colors.white,
                                child: ChangeNotifierProvider.value(
                                    value: settings,
                                    child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          pane(retained,
                                              const ValueKey('retained')),
                                          const SizedBox(width: 16),
                                          pane(fresh, ValueKey(revision)),
                                        ]))))))));
            await tester.pumpAndSettle();
            final actual = _paint(retained), reference = _paint(fresh);
            shapedParagraphs.add(actual.text);
            expect(actual.text.text!.toPlainText(), _text);
            expect(actual.text.textDirection, direction);
            expect(actual.size, reference.size);
            expect(actual.text.size, reference.text.size);
            expect(
                actual.text.height +
                    lyricVerticalInkGuard * 2 +
                    (timed ? 24 : 0),
                lessThanOrEqualTo(_captureHeight),
                reason: 'The complete body must fit the captured viewport.');
            _checkFamilies(actual.text, policy);
            for (final (index, extent) in offsets.indexed) {
              final selection =
                  TextSelection(baseOffset: extent.$1, extentOffset: extent.$2);
              final boxes = actual.text.getBoxesForSelection(selection);
              expect(boxes, reference.text.getBoxesForSelection(selection));
              if (_parts[index].trim().isNotEmpty) {
                expect(
                    boxes.any(
                        (box) => box.right > box.left && box.bottom > box.top),
                    isTrue,
                    reason:
                        'Author word $index must retain a visible glyph box.');
              }
            }
            final Object layout;
            if (actual.painter case final LyricWordHighlightPainter painter) {
              layout = painter.layoutIdentity;
              final freshPainter =
                  reference.painter as LyricWordHighlightPainter;
              expect(painter.shapedWordCount, freshPainter.shapedWordCount);
              expect(painter.paintedTextBounds, freshPainter.paintedTextBounds);
              for (final (index, word) in words.indexed) {
                final expected = ((position.value - word.start).inMicroseconds /
                        word.length.inMicroseconds)
                    .clamp(0.0, 1.0);
                expect(painter.progressForWord(index), expected);
              }
            } else {
              final painter = actual.painter as PlainLyricWordFollowPainter;
              final freshPainter =
                  reference.painter as PlainLyricWordFollowPainter;
              layout = painter.layoutIdentity!;
              expect(painter.slots.map((slot) => (slot.start, slot.end)),
                  freshPainter.slots.map((slot) => (slot.start, slot.end)));
              for (var i = 0; i < painter.slots.length; i++) {
                expect(painter.slots[i].paintBoxes,
                    freshPainter.slots[i].paintBoxes);
              }
              expect(painter.slots.last.end, _text.length);
            }
            if (previousLayout != null) {
              expect(layout, isNot(same(previousLayout)));
            }
            previousLayout = layout;
            final actualPixels = await _pixels(tester, retained,
                captureName: widthIndex == 4 && policyIndex == 0
                    ? '${language.code}-${timed ? 'timed' : 'plain'}-190'
                    : null);
            expect(_inkPixels(actualPixels), greaterThan(100),
                reason:
                    'RGBA comparison must contain real ink, not an empty viewport.');
            expect(
                listEquals(actualPixels, await _pixels(tester, fresh)), isTrue,
                reason:
                    '${language.code} timed=$timed policy=$policyIndex width=$width');
            if (widthIndex == 0) {
              if (previousPolicyPainter != null) {
                expect(actual.text, isNot(same(previousPolicyPainter)),
                    reason:
                        'A real font choice must invalidate paragraph shaping.');
              }
              if (policyIndex == 1) {
                expect(listEquals(actualPixels, previousPolicyPixels), isFalse,
                    reason:
                        'Replacing Google Sans must change actual Latin ink.');
              }
              previousPolicyPainter = actual.text;
              previousPolicyPixels = actualPixels;
            }
            expect(line.words, same(words));
            expect(line.content, _text);
            expect([
              for (final word in words) (word.start, word.length, word.content)
            ], author);
            expect(tester.takeException(), isNull);
          }
          expect(shapedParagraphs, hasLength(1),
              reason:
                  'Pure width changes must retain this policy\'s shaped paragraph.');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }
}
