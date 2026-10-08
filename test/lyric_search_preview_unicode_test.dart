import 'package:dan_player/lyric/lyric_text_search.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_find_dialog.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

const _clusters = <String, String>{
  'Latin accent': 'e\u0301',
  'Japanese voicing': 'か\u3099',
  'Hangul jamo': '각',
  'skin tone': '👍🏽',
  'profession ZWJ': '👩🏽‍💻',
  'family ZWJ': '👨‍👩‍👧‍👦',
  'flag': '🇨🇳',
  'keycap': '1\uFE0F\u20E3',
};

String _edgeSource(String cluster, bool leading) {
  if (!leading) return '${'x' * 100}NEEDLE${'x' * 113}${cluster}tail';
  final clusterStart = 60 - cluster.length ~/ 2;
  return '${'x' * clusterStart}$cluster'
      '${'x' * (100 - clusterStart - cluster.length)}NEEDLE${'x' * 160}';
}

LyricSearchRow _hit(PlainLyric lyric, [String query = 'needle']) =>
    filterLyricSearchRows(
            lyricSearchRows(lyric, project: lyricReadingText), query)
        .single;

void _expectWholePreview(String source, String preview, String hit) {
  expect(preview, contains(hit));
  var interior = preview;
  if (interior.startsWith('…')) interior = interior.substring(1);
  if (interior.endsWith('…')) {
    interior = interior.substring(0, interior.length - 1);
  }
  final from = source.indexOf(interior);
  expect(from, greaterThanOrEqualTo(0),
      reason: 'Preview text must remain an unmodified authored substring');
  final to = from + interior.length;
  final boundaries = <int>{0};
  var offset = 0;
  for (final cluster in source.characters) {
    offset += cluster.length;
    boundaries.add(offset);
  }
  expect(boundaries, contains(from),
      reason: 'The leading edge must not start inside an authored grapheme');
  expect(boundaries, contains(to),
      reason: 'The trailing edge must not end inside an authored grapheme');
}

void _expectTarget(LyricSearchRow row, PlainLyric lyric, String needle) {
  expect(row.target.textOffset, lyric.text.indexOf(needle));
  expect(row.target.line, same(lyric.lines.single));
  expect(row.target.belongsTo(lyric), isTrue);
  expect(lyric.lines, hasLength(1));
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);

  for (final entry in _clusters.entries) {
    for (final leading in [true, false]) {
      test(
          'search preview retains complete ${entry.key} at '
          '${leading ? 'leading' : 'trailing'} edge', () {
        final lyric = PlainLyric(_edgeSource(entry.value, leading));
        final row = _hit(lyric);
        _expectWholePreview(lyric.text, row.preview('needle'), 'NEEDLE');
        _expectTarget(row, lyric, 'NEEDLE');
      });
    }
  }

  final giant = 'a${'\u0301' * 4096}';
  for (final leading in [true, false]) {
    test(
        'search preview omits oversized unmatched '
        '${leading ? 'leading' : 'trailing'} cluster within its budget', () {
      final source = leading
          ? '${'x' * 10}$giant${'x' * 20}NEEDLE${'x' * 160}'
          : _edgeSource(giant, false);
      final lyric = PlainLyric(source);
      final row = _hit(lyric);
      final preview = row.preview('needle');
      _expectWholePreview(lyric.text, preview, 'NEEDLE');
      expect(preview.length, lessThanOrEqualTo(162),
          reason: 'An unmatched edge must not expand a 160-unit preview '
              'into thousands of combining marks');
      expect(preview, isNot(contains(giant)));
      _expectTarget(row, lyric, 'NEEDLE');
    });
  }

  test('a matched oversized grapheme preserves its authored text and offset',
      () {
    final lyric = PlainLyric('${'x' * 100}${giant}tail');
    final row = _hit(lyric, 'a');
    final preview = row.preview('a');
    _expectWholePreview(lyric.text, preview, 'a');
    expect(preview, contains(giant),
        reason: 'The actual matching grapheme follows existing long-query '
            'semantics rather than losing authored marks');
    _expectTarget(row, lyric, 'a');
  });

  test('an explicit long query preserves the existing full-match preview', () {
    final query = 'a' * 300;
    final lyric = PlainLyric('${'x' * 100}$query${'x' * 100}');
    final row = _hit(lyric, query);
    _expectWholePreview(lyric.text, row.preview(query), query);
    _expectTarget(row, lyric, query);
  });

  for (final language in UiLanguage.values) {
    testWidgets(
        'actual find preview keeps whole Unicode and original target '
        'in ${language.name}', (tester) async {
      sizePlaylistFeature(tester, width: 1000, height: 800);
      final previousLanguage = uiLanguage.value;
      addTearDown(() => uiLanguage.value = previousLanguage);
      uiLanguage.value = language;
      final lyric = PlainLyric(_edgeSource(_clusters['family ZWJ']!, false));
      LyricReadingTarget? selected;
      final host = playlistFeatureHost(Builder(
        builder: (context) => Center(
          child: FilledButton(
            key: const ValueKey('open-unicode-find'),
            onPressed: () async {
              selected = await showLyricFindDialog(context,
                  lyric: lyric,
                  isCurrentLyric: () => true,
                  songTitle: '夜の歌 · 밤의 노래');
            },
            child: const Text('Open'),
          ),
        ),
      )) as MaterialApp;
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
      await tester.tap(find.byKey(const ValueKey('open-unicode-find')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('lyric-find-search')), 'needle');
      await tester.pumpAndSettle();
      final row = find.byKey(
          ValueKey('lyric-find-result-0-${lyric.text.indexOf('NEEDLE')}'));
      expect(row.hitTestable(), findsOneWidget);
      final text = find.descendant(
          of: row,
          matching: find.byWidgetPredicate((widget) =>
              widget is Text && widget.semanticsLabel == lyric.text));
      expect(text, findsOneWidget);
      final preview = tester.widget<Text>(text).data!;
      _expectWholePreview(lyric.text, preview, 'NEEDLE');
      final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: text, matching: find.byType(RichText)));
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(
          paragraph.getBoxesForSelection(TextSelection(
              baseOffset: preview.length - 2,
              extentOffset: preview.length - 1)),
          isNotEmpty,
          reason: 'The last authored preview character is actually laid out');
      await tester.tap(find.byKey(const ValueKey('lyric-find-locate')));
      await tester.pumpAndSettle();
      expect(selected, isNotNull);
      expect(selected!.textOffset, lyric.text.indexOf('NEEDLE'));
      expect(selected!.line, same(lyric.lines.single));
      expect(selected!.belongsTo(lyric), isTrue);
      expect(find.byType(LyricFindDialog), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
