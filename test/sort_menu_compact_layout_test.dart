import 'dart:io';

import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/component/audio_sort_options.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/playlist_feature_fixture.dart';

const _buttonKey = ValueKey('compact-sort-button');
const _describedKey = ValueKey('compact-sort-described-field');
const _tailFields = [
  AudioSortField.bitrate,
  AudioSortField.sampleRate,
  AudioSortField.fileSize,
  AudioSortField.format,
  AudioSortField.source,
];

String get _rawHelp =>
    '$audioSortMissingValueNote\n${AudioSortField.fileSize.note!}';
String get _translatedHelp =>
    '${ui(audioSortMissingValueNote)}\n${ui(AudioSortField.fileSize.note!)}';

Finder _field(AudioSortField field) =>
    find.byKey(ValueKey('compact-sort-${field.name}'));

Rect _panelRect(WidgetTester tester, Finder content) => tester.getRect(find
    .ancestor(
        of: content,
        matching: find.byWidgetPredicate(
            (widget) => widget is Material && widget.type == MaterialType.card))
    .first);

/// Read the laid-out paragraph, including the final authored character. A
/// matching Text string alone would still pass when ellipsis hides its suffix.
List<Rect> _completeGlyphRects(WidgetTester tester, Finder textFinder) {
  final text = tester.widget<Text>(textFinder).data!;
  final richText =
      find.descendant(of: textFinder, matching: find.byType(RichText));
  expect(richText, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(richText);
  expect(paragraph.didExceedMaxLines, isFalse,
      reason: 'The complete visible text must survive natural wrapping');
  // Full-line selections include unpainted trailing wrap spaces, whose boxes
  // can extend past the paragraph. Inspect every non-whitespace text run.
  final boxes = [
    for (final run in RegExp(r'\S+').allMatches(text))
      ...paragraph.getBoxesForSelection(
          TextSelection(baseOffset: run.start, extentOffset: run.end)),
  ];
  expect(boxes, isNotEmpty);
  final suffix = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: text.length - 1, extentOffset: text.length));
  expect(suffix.any((box) => box.right > box.left), isTrue,
      reason: 'The final character must have a real laid-out glyph box');
  final glyphs = <Rect>[];
  for (final box in boxes) {
    if (box.right <= box.left) continue;
    final rect = box.toRect();
    glyphs.add(paragraph.localToGlobal(rect.topLeft) & rect.size);
  }
  return glyphs;
}

void _inside(Rect content, Rect bounds) {
  expect(content.left, greaterThanOrEqualTo(bounds.left - .1));
  expect(content.top, greaterThanOrEqualTo(bounds.top - .1));
  expect(content.right, lessThanOrEqualTo(bounds.right + .1));
  expect(content.bottom, lessThanOrEqualTo(bounds.bottom + .1));
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(_buttonKey));
  await tester.pumpAndSettle();
  expect(_field(AudioSortField.source), findsOneWidget);
}

Future<void> _closeAndCheckIdle(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape,
      physicalKey: PhysicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(_field(AudioSortField.source), findsNothing);
  expect(tester.binding.transientCallbackCount, 0,
      reason: 'The mounted sorting capsule must be idle after menu exit');
  expect(tester.takeException(), isNull);
}

Future<GlobalKey> _mount(WidgetTester tester,
    {required UiLanguage language,
    required double width,
    required double scale,
    required List<AudioSortField> selected,
    String? describedLabel}) async {
  sizePlaylistFeature(tester, width: width, height: 820);
  final previousLanguage = uiLanguage.value;
  addTearDown(() => uiLanguage.value = previousLanguage);
  uiLanguage.value = language;
  final boundary = GlobalKey();
  final body = Padding(
    padding: const EdgeInsets.all(16),
    child: Align(
      alignment: Alignment.topLeft,
      child: AppSortButton<AudioSortField>(
        key: _buttonKey,
        value: AudioSortField.fileSize,
        scopeId: 'compact-real-audio-fields',
        direction: SortDirection.ascending,
        onDirectionChanged: (_) {},
        onChanged: selected.add,
        helpText: _rawHelp,
        options: [
          for (final field in AudioSortField.values)
            AppSortOption(
              value: field,
              label: field == AudioSortField.fileSize && describedLabel != null
                  ? describedLabel
                  : field.label,
              icon: audioSortIcon(field),
              group: field.group,
              key: field == AudioSortField.fileSize && describedLabel != null
                  ? _describedKey
                  : ValueKey('compact-sort-${field.name}'),
            ),
        ],
      ),
    ),
  );
  final host = playlistFeatureHost(body, textScale: scale, boundary: boundary)
      as MaterialApp;
  await tester.pumpWidget(UiLanguageScope(
    child: MaterialApp(
      theme: host.theme,
      locale: language.locale,
      supportedLocales: UiLanguage.values.map((value) => value.locale),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: host.builder,
      home: host.home,
    ),
  ));
  await tester.pumpAndSettle();
  return boundary;
}

void main() {
  // An optional name substring selects only failed native cases for resuming.
  // Without a filter, all 18 cases remain registered with their full coverage.
  final caseFilter = Platform.environment['DAN_SORT_COMPACT_CASE'];
  bool includesCase(String name) =>
      caseFilter == null || caseFilter.isEmpty || name.contains(caseFilter);
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    final output = Platform.environment['DAN_PLAYLIST_FEATURE_RENDER_DIR'];
    if (output == null) return;
    final qa = path.normalize(path.join(Directory.current.parent.path, 'tool',
        'qa-local', 'menu-delivery-2606-oct7', 'sort-compact'));
    expect(path.isWithin(qa, path.normalize(path.absolute(output))), isTrue,
        reason: 'Compact sorting screenshots must stay in their isolated QA');
  });

  for (final language in UiLanguage.values) {
    for (final width in [1100.0, 360.0]) {
      for (final scale in [1.0, 2.0]) {
        final name =
            'compact audio sort menu ${language.name} width $width scale $scale';
        if (!includesCase(name)) continue;
        testWidgets(name, (tester) async {
          final selected = <AudioSortField>[];
          final boundary = await _mount(tester,
              language: language,
              width: width,
              scale: scale,
              selected: selected);
          await _open(tester);
          final footer = find.text(_translatedHelp);
          expect(footer, findsOneWidget,
              reason: 'Both real sorting notes must retain their translation');
          final panel = _panelRect(tester, footer);
          expect(panel.width, lessThanOrEqualTo(280.1),
              reason: 'The expanded menu has its own compact width budget');
          _inside(panel, Rect.fromLTWH(0, 0, width, 820));
          for (final group
              in AudioSortField.values.map((field) => field.group).toSet()) {
            expect(find.text(ui(group)), findsOneWidget);
          }
          await Scrollable.ensureVisible(tester.element(footer), alignment: 1);
          final scroll = Scrollable.of(tester.element(footer)).position;
          scroll.jumpTo(scroll.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(footer.hitTestable(), findsOneWidget);
          final footerRect = tester.getRect(footer);
          _inside(footerRect, panel.deflate(6));
          final glyphs = _completeGlyphRects(tester, footer);
          expect(
              glyphs.map((rect) => rect.top.toStringAsFixed(2)).toSet().length,
              greaterThanOrEqualTo(2),
              reason:
                  'Explanations may use the complete natural multiline height');
          final footerItem = find
              .ancestor(
                  of: footer,
                  matching: find
                      .byWidgetPredicate((widget) => widget is PopupMenuItem))
              .first;
          // Real font ascent/descent may overhang the paragraph's rounded
          // layout height. Its row padding is the actual unclipped text body.
          final footerBody = tester.getRect(footerItem).deflate(6);
          for (final glyph in glyphs) {
            _inside(glyph, footerBody);
            _inside(glyph, panel.deflate(6));
          }
          await capturePlaylistFeature(tester, boundary,
              'sort-${language.code}-${width.toInt()}-${scale.toInt()}-footer');
          await _closeAndCheckIdle(tester);

          for (final field in _tailFields) {
            await _open(tester);
            await Scrollable.ensureVisible(tester.element(_field(field)),
                alignment: .5);
            await tester.pumpAndSettle();
            expect(_field(field).hitTestable(), findsOneWidget);
            final label =
                find.descendant(of: _field(field), matching: find.byType(Text));
            expect(label, findsOneWidget);
            expect(tester.widget<Text>(label).data, ui(field.label));
            final glyphs = _completeGlyphRects(tester, label);
            for (final glyph in glyphs) {
              _inside(glyph, tester.getRect(_field(field)).deflate(6));
            }
            await tester.tap(_field(field));
            await tester.pumpAndSettle();
            expect(selected.last, field);
          }
          expect(selected, _tailFields,
              reason:
                  'Every tail field remains reachable and selects its real enum');
          await _open(tester);
          await _closeAndCheckIdle(tester);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  for (final language in [UiLanguage.en, UiLanguage.ja]) {
    final name = 'complete described sort field wraps in ${language.name}';
    if (!includesCase(name)) continue;
    testWidgets(name, (tester) async {
      final label =
          '${translateUi(AudioSortField.fileSize.label, language)} · ${translateUi(AudioSortField.fileSize.note!, language)}';
      final selected = <AudioSortField>[];
      final boundary = await _mount(tester,
          language: language,
          width: 360,
          scale: 2,
          selected: selected,
          describedLabel: label);
      await _open(tester);
      final item = find.byKey(_describedKey);
      await Scrollable.ensureVisible(tester.element(item), alignment: .5);
      await tester.pumpAndSettle();
      final text = find.text(label).last;
      await capturePlaylistFeature(
          tester, boundary, 'sort-described-${language.code}-360-2');
      final glyphs = _completeGlyphRects(tester, text);
      expect(glyphs.map((rect) => rect.top.toStringAsFixed(2)).toSet().length,
          greaterThan(2),
          reason: 'The description genuinely needs more than two lines');
      for (final glyph in glyphs) {
        _inside(glyph, tester.getRect(item).deflate(6));
      }
      _inside(tester.getRect(item), _panelRect(tester, text));
      expect(item.hitTestable(), findsOneWidget);
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(selected, [AudioSortField.fileSize]);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
