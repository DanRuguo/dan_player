import 'dart:io';

import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/component/smart_playlist_dialog.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

// All persistence is replaced at the dialog's existing injection point. The
// nominal file and metadata-only tracks are never opened.
class _Store extends SmartPlaylistStore {
  _Store() : super(File('unused-smart-sort-menu-fixture'));

  @override
  Future<List<SmartPlaylist>> list() async =>
      [const SmartPlaylist(id: 'compact', name: 'Compact', maxResults: 3)];
}

const _labels = [
  '歌曲名称',
  '歌手',
  '专辑',
  '最近加入优先',
  '时长从短到长',
  '最近播放优先',
  '播放次数从多到少',
  '播放次数从少到多',
  '专辑与音轨顺序',
  '随机抽取',
];

Finder _key(String value) => find.byKey(ValueKey(value));
Finder get _sort => find.byType(DropdownButtonFormField<SmartPlaylistSort>);

Widget _host(Widget child, GlobalKey boundary, bool narrow) => UiLanguageScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: Entry(welcome: false).fromSchemeAndFontFamily(
            colorScheme: ColorScheme.fromSeed(
                seedColor: narrow ? Colors.deepOrange : Colors.indigo,
                brightness: narrow ? Brightness.dark : Brightness.light)),
        locale: uiLanguage.value.locale,
        supportedLocales: UiLanguage.values.map((value) => value.locale),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
        ),
        home: Scaffold(body: child),
      ),
    );

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _waitPreview(WidgetTester tester) async {
  // Real model evaluation uses Isolate.run; give its result a real event-loop
  // turn rather than substituting a fake list or advancing only widget time.
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();
    if (_key('smart-preview-busy').evaluate().isEmpty &&
        _key('smart-result-count').evaluate().isNotEmpty) {
      return;
    }
  }
  fail('The real smart-playlist preview did not complete.');
}

Finder _popupLabel(String label) => find.text(ui(label)).last;

Rect _panel(WidgetTester tester, Finder label) => tester.getRect(find
    .ancestor(
        of: label,
        matching: find.byWidgetPredicate((widget) =>
            widget is Material && widget.type == MaterialType.transparency))
    .first);

Future<void> _expectFullLabel(
    WidgetTester tester, String label, double width) async {
  final text = _popupLabel(label);
  await tester.ensureVisible(text);
  await tester.pumpAndSettle();
  expect(text.hitTestable(), findsOneWidget);
  final panel = _panel(tester, text);
  expect(panel.width, lessThanOrEqualTo(appSortMenuMaxWidth + .01));
  expect(panel.left, greaterThanOrEqualTo(-.01));
  expect(panel.right, lessThanOrEqualTo(width + .01));
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)).first);
  expect(paragraph.didExceedMaxLines, isFalse);
  final boxes = paragraph.getBoxesForSelection(TextSelection(
      baseOffset: 0, extentOffset: paragraph.text.toPlainText().length));
  expect(boxes, isNotEmpty);
  for (final box in boxes) {
    final glyphs =
        MatrixUtils.transformRect(paragraph.getTransformTo(null), box.toRect());
    expect(glyphs.left, greaterThanOrEqualTo(panel.left - .1));
    expect(glyphs.right, lessThanOrEqualTo(panel.right + .1));
    expect(glyphs.top, greaterThanOrEqualTo(panel.top - .1));
    expect(glyphs.bottom, lessThanOrEqualTo(panel.bottom + .1));
  }
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  final onlyCase = Platform.environment['DAN_SMART_SORT_COMPACT_CASE'] ??
      const String.fromEnvironment('DAN_SMART_SORT_COMPACT_CASE');

  for (final language in UiLanguage.values) {
    for (final width in [360.0, 1100.0]) {
      final description =
          'smart result sort stays compact with full labels and real preview '
          '${language.name} ${width.toInt()} at 200 percent';
      if (onlyCase.isNotEmpty && !description.contains(onlyCase)) continue;
      testWidgets(description, (tester) async {
        uiLanguage.value = language;
        sizePlaylistFeature(tester, width: width, height: 1100);
        final boundary = GlobalKey();
        final stats = PlaybackStatistics.inMemory();
        final changes = ValueNotifier(0);
        addTearDown(stats.dispose);
        addTearDown(changes.dispose);
        final tracks = [
          CategoryTestAudio('Alpha', duration: 180),
          CategoryTestAudio('Zulu', duration: 60),
          CategoryTestAudio('Middle', duration: 120),
        ];
        var seedCalls = 0;
        List<Audio>? selected;
        await tester.pumpWidget(_host(
            SmartPlaylistsDialog(
              loadStore: () async => _Store(),
              library: () => tracks,
              libraryChanges: changes,
              statistics: stats,
              randomSeedFactory: () => ++seedCalls,
              onAddToPlaylist: (items) => selected = List.of(items),
            ),
            boundary,
            width == 360));
        await tester.pumpAndSettle();
        await _tap(tester, _key('smart-rule-compact'));
        await _waitPreview(tester);
        await _tap(tester, find.text(ui('筛选规则')));
        await _tap(tester, _sort);
        for (final label in _labels) {
          await _expectFullLabel(tester, label, width);
        }
        final name = 'smart-sort-${language.name}-${width.toInt()}-200';
        await capturePlaylistFeature(tester, boundary, '$name-menu-tail');
        await _tap(tester, _popupLabel('时长从短到长'));
        await _waitPreview(tester);
        expect(tester.state<FormFieldState<SmartPlaylistSort>>(_sort).value,
            SmartPlaylistSort.duration);
        await _tap(tester, _key('smart-ordinary'));
        expect(selected, orderedEquals([tracks[1], tracks[2], tracks[0]]));
        expect(seedCalls, 0);

        await _tap(tester, _sort);
        await _expectFullLabel(tester, '随机抽取', width);
        await _tap(tester, _popupLabel('随机抽取'));
        await _waitPreview(tester);
        expect(tester.state<FormFieldState<SmartPlaylistSort>>(_sort).value,
            SmartPlaylistSort.random);
        expect(seedCalls, 1);
        await _tap(tester, _key('smart-ordinary'));
        expect(selected, unorderedEquals(tracks));
        expect(_key('smart-refresh'), findsNothing);
        expect(_key('smart-next-batch'), findsOneWidget);
        await Scrollable.ensureVisible(tester.element(_sort), alignment: .35);
        await tester.pumpAndSettle();
        expect(tester.getSize(_sort).width,
            lessThanOrEqualTo(appSortMenuMaxWidth + .01));
        final current = find
            .descendant(of: _sort, matching: find.text(ui('随机抽取')))
            .hitTestable();
        expect(current, findsOneWidget);
        expect(find.ancestor(of: current, matching: find.byType(Tooltip)),
            findsWidgets);
        await capturePlaylistFeature(tester, boundary, '$name-field');
        await tester.pump(const Duration(seconds: 2));
        // Live binding waits in real time before the one requested frame.
        // Drain finite scrollbar/post-frame feedback before assessing idle;
        // an ongoing ticker still times out and fails this same idle contract.
        final idlePumps = await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5));
        debugPrint('$name idle settled after $idlePumps pumps');
        expect(seedCalls, 1, reason: 'Closing the menu must not draw anew.');
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }
}
