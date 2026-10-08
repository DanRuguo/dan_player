import 'dart:async';
import 'dart:io';

import 'package:dan_player/component/smart_playlist_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

class _Store extends SmartPlaylistStore {
  _Store([this.rules = const []]) : super(File('unused-smart-name-fixture'));
  List<SmartPlaylist> rules;
  int saves = 0;

  @override
  Future<List<SmartPlaylist>> list() async => List.of(rules);

  @override
  Future<void> upsert(SmartPlaylist rule) async {
    saves++;
    rules = [...rules.where((item) => item.id != rule.id), rule];
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _new(WidgetTester tester, SmartPlaylistsDialog dialog) async {
  sizePlaylistFeature(tester, width: 1080, height: 1200);
  await tester.pumpWidget(playlistFeatureHost(UiLanguageScope(child: dialog)));
  await tester.pumpAndSettle();
  await _tap(tester, _key('smart-new'));
}

Future<void> _waitPreview(WidgetTester tester) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();
    if (_key('smart-preview-busy').evaluate().isEmpty) return;
  }
  fail('The real random evaluation did not complete.');
}

({PlaybackStatistics statistics, ValueNotifier<int> changes}) _dependencies() {
  final statistics = PlaybackStatistics.inMemory();
  final changes = ValueNotifier(0);
  addTearDown(statistics.dispose);
  addTearDown(changes.dispose);
  return (statistics: statistics, changes: changes);
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final language in UiLanguage.values) {
    testWidgets(
        'renaming keeps the random preview actionable in ${language.name}',
        (tester) async {
      uiLanguage.value = language;
      sizePlaylistFeature(tester, width: 1080, height: 1200);
      final dependencies = _dependencies();
      final store = _Store([
        const SmartPlaylist(
            id: 'random',
            name: 'Original',
            sort: SmartPlaylistSort.random,
            maxResults: 5)
      ]);
      final tracks = List.generate(30, (i) => CategoryTestAudio('Track $i'));
      var libraryReads = 0;
      var evaluations = 0;
      var seeds = 0;
      List<Audio>? added;
      await tester.pumpWidget(playlistFeatureHost(UiLanguageScope(
          child: SmartPlaylistsDialog(
              loadStore: () async => store,
              statistics: dependencies.statistics,
              libraryChanges: dependencies.changes,
              library: () {
                libraryReads++;
                return tracks;
              },
              randomSeedFactory: () {
                seeds++;
                return 77;
              },
              evaluate: (rule, library) {
                evaluations++;
                return rule.evaluate(library, randomSeed: 77);
              },
              onAddToPlaylist: (items) => added = items))));
      await tester.pumpAndSettle();
      await _tap(tester, _key('smart-rule-random'));
      await _waitPreview(tester);
      await _tap(tester, find.text(ui('筛选规则')));
      expect(evaluations, 1);
      expect(libraryReads, 1);
      expect(_key('smart-preview-busy'), findsNothing);
      await tester.enterText(
          _key('smart-name'), '  Renamed ${language.name}  ');
      await tester.pump();
      expect(_key('smart-preview-busy'), findsNothing,
          reason: 'Changing a label must not suspend result actions.');
      expect(tester.widget<OutlinedButton>(_key('smart-ordinary')).onPressed,
          isNotNull);
      await tester.pump(const Duration(milliseconds: 300));
      expect(evaluations, 1, reason: 'The matching inputs did not change.');
      expect(libraryReads, 1, reason: 'Renaming must not clone the library.');
      expect(seeds, 1);
      await _tap(tester, _key('smart-ordinary'));
      expect(added, hasLength(5));
      expect(
          added!.map((audio) => audio.path).toList(),
          (await tester.runAsync(
                  () => store.rules.single.evaluate(tracks, randomSeed: 77)))!
              .map((audio) => audio.path)
              .toList());
      await _tap(tester, _key('smart-save'));
      expect(store.rules.single.name, 'Renamed ${language.name}');
      expect(store.rules.single.sort, SmartPlaylistSort.random);
      expect(store.saves, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('renaming does not discard an in-flight matching result',
      (tester) async {
    final dependencies = _dependencies();
    final gate = Completer<List<Audio>>();
    var evaluations = 0;
    final tracks = [CategoryTestAudio('Canon')];
    await _new(
        tester,
        SmartPlaylistsDialog(
            loadStore: () async => _Store(),
            statistics: dependencies.statistics,
            libraryChanges: dependencies.changes,
            library: () => tracks,
            evaluate: (_, __) {
              evaluations++;
              return gate.future;
            }));
    await tester.enterText(_key('smart-name'), 'Changed while loading');
    gate.complete(tracks);
    await tester.pump();
    await tester.pump();
    expect(_key('smart-preview-busy'), findsNothing);
    expect(tester.widget<OutlinedButton>(_key('smart-ordinary')).onPressed,
        isNotNull);
    await tester.pump(const Duration(milliseconds: 300));
    expect(evaluations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renaming does not postpone a pending query preview',
      (tester) async {
    final dependencies = _dependencies();
    final queries = <String>[];
    await _new(
        tester,
        SmartPlaylistsDialog(
            loadStore: () async => _Store(),
            statistics: dependencies.statistics,
            libraryChanges: dependencies.changes,
            library: () => [],
            evaluate: (rule, _) async {
              queries.add(rule.query);
              return [];
            }));
    await tester.enterText(_key('smart-query'), 'Canon');
    await tester.pump(const Duration(milliseconds: 170));
    await tester.enterText(_key('smart-name'), 'New label');
    await tester.pump(const Duration(milliseconds: 60));
    expect(queries, ['', 'Canon']);
    await tester.pump(const Duration(milliseconds: 300));
    expect(queries, ['', 'Canon']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty name still blocks saving without rescanning results',
      (tester) async {
    final dependencies = _dependencies();
    final store = _Store();
    var evaluations = 0;
    await _new(
        tester,
        SmartPlaylistsDialog(
            loadStore: () async => store,
            statistics: dependencies.statistics,
            libraryChanges: dependencies.changes,
            library: () => [CategoryTestAudio('Canon')],
            evaluate: (_, library) async {
              evaluations++;
              return library;
            }));
    await tester.enterText(_key('smart-name'), 'Temporary');
    await tester.enterText(_key('smart-name'), '   ');
    await _tap(tester, _key('smart-save'));
    expect(store.saves, 0);
    expect(find.text(ui('请输入 1–120 个字符的智能歌单名称。')), findsOneWidget);
    expect(tester.widget<OutlinedButton>(_key('smart-ordinary')).onPressed,
        isNotNull);
    await tester.pump(const Duration(milliseconds: 300));
    expect(evaluations, 1);
    await tester.enterText(_key('smart-name'), 'Recovered');
    await _tap(tester, _key('smart-save'));
    expect(store.rules.single.name, 'Recovered');
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid Unicode name and its repair retain validation semantics',
      (tester) async {
    final dependencies = _dependencies();
    final store = _Store();
    var evaluations = 0;
    await _new(
        tester,
        SmartPlaylistsDialog(
            loadStore: () async => store,
            statistics: dependencies.statistics,
            libraryChanges: dependencies.changes,
            library: () => [],
            evaluate: (_, library) async {
              evaluations++;
              return library;
            }));
    // TextField counts graphemes; the persisted rule limits UTF-16 units.
    await tester.enterText(_key('smart-name'), List.filled(61, '😀').join());
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(evaluations, 1);
    expect(find.text(ui('请输入 1–120 个字符的智能歌单名称。')), findsOneWidget);
    await _tap(tester, _key('smart-save'));
    expect(store.saves, 0);
    await tester.enterText(_key('smart-name'), 'Valid again');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(evaluations, 2);
    expect(_key('smart-preview-busy'), findsNothing);
    expect(find.text(ui('请输入 1–120 个字符的智能歌单名称。')), findsOneWidget,
        reason: 'The last failed Save remains visible until another Save.');
    await _tap(tester, _key('smart-save'));
    expect(store.rules.single.name, 'Valid again');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a name edit can still retry a failed preview', (tester) async {
    final dependencies = _dependencies();
    var evaluations = 0;
    await _new(
        tester,
        SmartPlaylistsDialog(
            loadStore: () async => _Store(),
            statistics: dependencies.statistics,
            libraryChanges: dependencies.changes,
            library: () => [CategoryTestAudio('Canon')],
            evaluate: (_, library) async {
              if (++evaluations == 1) {
                throw StateError('fixture evaluation failure');
              }
              return library;
            }));
    expect(find.text(ui('无法更新结果预览，请重试。')), findsOneWidget);
    await tester.enterText(_key('smart-name'), 'Retry');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(evaluations, 2);
    expect(tester.widget<OutlinedButton>(_key('smart-ordinary')).onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a queued text input can finish while leaving the editor',
      (tester) async {
    final dependencies = _dependencies();
    await _new(
        tester,
        SmartPlaylistsDialog(
            loadStore: () async => _Store(),
            statistics: dependencies.statistics,
            libraryChanges: dependencies.changes,
            library: () => [],
            evaluate: (_, library) async => library));
    await tester.enterText(_key('smart-name'), 'Draft');
    await tester.tap(find.byTooltip(ui('返回')));
    // The native text client can deliver its already-queued update before the
    // next frame unmounts the field. It no longer owns an editable rule.
    tester.testTextInput.enterText('Queued composition');
    await tester.pumpAndSettle();
    expect(_key('smart-new'), findsOneWidget);
    expect(_key('smart-save'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
