import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/smart_playlist_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:desktop_lyric/l10n/catalog_smart_random.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

class _Store extends SmartPlaylistStore {
  _Store(this.rules) : super(File('unused-random-smart-fixture'));
  List<SmartPlaylist> rules;
  @override
  Future<List<SmartPlaylist>> list() async => List.of(rules);
  @override
  Future<void> upsert(SmartPlaylist rule) async {
    rules = [...rules.where((r) => r.id != rule.id), rule];
  }
}

const _rule = SmartPlaylist(
    id: 'random',
    name: 'Random music',
    sort: SmartPlaylistSort.random,
    maxResults: 5);
Finder _key(String name) => find.byKey(ValueKey(name));
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _waitBatch(WidgetTester tester) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();
    final batch = _key('smart-next-batch');
    if (batch.evaluate().isNotEmpty &&
        tester.widget<OutlinedButton>(batch).onPressed != null) {
      return;
    }
  }
  fail('The random preview did not complete.');
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  test('all random labels translate in four languages', () {
    for (final entry in catalogSmartRandom.entries) {
      expect(entry.value, hasLength(3));
      for (final language in UiLanguage.values) {
        uiLanguage.value = language;
        expect(ui(entry.key), isNotEmpty);
        if (language != UiLanguage.zh) expect(ui(entry.key), isNot(entry.key));
      }
    }
  });

  testWidgets(
      'one real batch survives hover, locale, theme and metadata refresh',
      (tester) async {
    sizePlaylistFeature(tester, width: 1080, height: 1000);
    final tracks = List.generate(40, (i) => CategoryTestAudio('Track $i'));
    final changes = ValueNotifier(0);
    final stats = PlaybackStatistics.inMemory();
    addTearDown(changes.dispose);
    addTearDown(stats.dispose);
    var seedCalls = 0;
    var libraryCalls = 0;
    List<Audio>? saved;
    final widget = SmartPlaylistsDialog(
        loadStore: () async => _Store([_rule]),
        library: () {
          libraryCalls++;
          return tracks;
        },
        libraryChanges: changes,
        statistics: stats,
        randomSeedFactory: () => ++seedCalls,
        onAddToPlaylist: (items) => saved = items);
    await tester.pumpWidget(listeningStatusHost(widget));
    await tester.pumpAndSettle();
    await _tap(tester, _key('smart-rule-random'));
    await _waitBatch(tester);
    await _tap(tester, _key('smart-ordinary'));
    final first = List<Audio>.of(saved!);
    expect(first, hasLength(5));
    final libraryBefore = libraryCalls;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
        location: tester.getCenter(_key('smart-next-batch')));
    await tester.pump(const Duration(milliseconds: 400));
    uiLanguage.value = UiLanguage.en;
    await tester.pumpAndSettle();
    await tester.pumpWidget(listeningStatusHost(widget,
        brightness: Brightness.dark, seed: Colors.orange));
    await tester.pumpAndSettle();
    expect(seedCalls, 1);
    expect(libraryCalls, libraryBefore);
    await _tap(tester, _key('smart-ordinary'));
    expect(saved, first);
    changes.value++;
    await tester.pump();
    await _waitBatch(tester);
    await _tap(tester, _key('smart-ordinary'));
    expect(saved, first);
    expect(seedCalls, 1);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'manual batch changes share preview, play and save snapshots; reopen draws anew',
      (tester) async {
    sizePlaylistFeature(tester, width: 1080, height: 1000);
    final tracks = List.generate(40, (i) => CategoryTestAudio('Track $i'));
    final store = _Store([_rule]);
    final stats = PlaybackStatistics.inMemory();
    addTearDown(stats.dispose);
    var seed = 0;
    List<Audio>? saved, played;
    final saveGate = Completer<void>();
    await tester.pumpWidget(listeningStatusHost(SmartPlaylistsDialog(
        library: () => tracks,
        loadStore: () async => store,
        statistics: stats,
        randomSeedFactory: () => ++seed,
        onPlay: (items) => played = items,
        onAddToPlaylist: (items) {
          saved = items;
          return saveGate.future;
        })));
    await tester.pumpAndSettle();
    await _tap(tester, _key('smart-rule-random'));
    await _waitBatch(tester);
    await _tap(tester, _key('smart-ordinary'));
    final first = List<Audio>.of(saved!);
    await _tap(tester, _key('smart-next-batch'));
    await _waitBatch(tester);
    final tiles = tester.widgetList<AudioTile>(find.byType(AudioTile));
    final second = List<Audio>.of(tiles.first.playlist);
    expect(second, hasLength(5));
    expect(second, isNot(orderedEquals(first)));
    expect(saved, first, reason: 'Pending save owns the clicked batch.');
    saveGate.complete();
    await tester.pumpAndSettle();
    await _tap(tester, _key('smart-select'));
    await _tap(tester, _key('audio-selection-play'));
    expect(played, second);
    expect(identical(played, second), isFalse);
    await _tap(tester, _key('smart-ordinary'));
    expect(saved, second);
    await _tap(tester, _key('smart-save'));
    expect(store.rules.single.sort, SmartPlaylistSort.random);
    expect(store.rules.single.toJson().containsKey('randomSeed'), isFalse);
    await _tap(tester, _key('smart-rule-random'));
    await _waitBatch(tester);
    expect(seed, 3,
        reason: 'Reopening saved random rules draws another batch.');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'sort dropdown opts into random while existing refresh remains intact',
      (tester) async {
    sizePlaylistFeature(tester, width: 1080, height: 1000);
    final store = _Store([const SmartPlaylist(id: 'fixed', name: 'Fixed')]);
    final stats = PlaybackStatistics.inMemory();
    addTearDown(stats.dispose);
    var seeds = 0;
    final drafts = <SmartPlaylist>[];
    await tester.pumpWidget(listeningStatusHost(SmartPlaylistsDialog(
        loadStore: () async => store,
        library: () => [],
        statistics: stats,
        randomSeedFactory: () => ++seeds,
        evaluate: (rule, _) async {
          drafts.add(rule);
          return [];
        })));
    await tester.pumpAndSettle();
    await _tap(tester, _key('smart-rule-fixed'));
    expect(_key('smart-refresh'), findsOneWidget);
    expect(seeds, 0);
    await _tap(tester, find.text(ui('筛选规则')));
    await _tap(tester, find.byType(DropdownButtonFormField<SmartPlaylistSort>));
    await _tap(tester, find.text(ui('随机抽取')).last);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(drafts.last.sort, SmartPlaylistSort.random);
    expect(_key('smart-refresh'), findsNothing);
    expect(_key('smart-next-batch'), findsOneWidget);
    expect(_key('smart-random-help'), findsOneWidget);
    expect(seeds, 1);
    await _tap(tester, _key('smart-next-batch'));
    expect(seeds, 2);
    await _tap(tester, _key('smart-save'));
    expect(store.rules.single.sort, SmartPlaylistSort.random);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'random stale callbacks cannot replace a newer batch or survive close',
      (tester) async {
    sizePlaylistFeature(tester, width: 1080, height: 1000);
    final changes = ValueNotifier(0);
    final stats = PlaybackStatistics.inMemory();
    addTearDown(changes.dispose);
    addTearDown(stats.dispose);
    final pending = <Completer<List<Audio>>>[];
    List<Audio>? saved;
    await tester.pumpWidget(listeningStatusHost(SmartPlaylistsDialog(
        loadStore: () async => _Store([_rule]),
        library: () => [],
        libraryChanges: changes,
        statistics: stats,
        randomSeedFactory: () => pending.length,
        evaluate: (_, __) {
          final result = Completer<List<Audio>>();
          pending.add(result);
          return result.future;
        },
        onAddToPlaylist: (items) => saved = items)));
    await tester.pumpAndSettle();
    await _tap(tester, _key('smart-rule-random'));
    changes.value++;
    await tester.pump();
    final current = [CategoryTestAudio('Current')];
    pending[1].complete(current);
    await tester.pumpAndSettle();
    pending[0].complete([CategoryTestAudio('Stale')]);
    await tester.pumpAndSettle();
    await _tap(tester, _key('smart-ordinary'));
    expect(saved, current);
    await _tap(tester, _key('smart-next-batch'));
    await tester.pumpWidget(const SizedBox());
    pending[2].complete([CategoryTestAudio('Closed')]);
    await tester.pumpAndSettle();
    expect(saved, current);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'random controls render ${language.name} ${narrow ? 'narrow-200' : 'wide'}',
          (tester) async {
        uiLanguage.value = language;
        sizePlaylistFeature(tester, width: narrow ? 360 : 1080, height: 1100);
        final boundary = GlobalKey();
        final stats = PlaybackStatistics.inMemory();
        addTearDown(stats.dispose);
        final tracks = List.generate(
            5, (i) => CategoryTestAudio('月光 / Moonlight / 月の光 / 달빛 $i'));
        var seedCalls = 0;
        final name = '${language.name}-${narrow ? 'narrow-200' : 'wide'}';
        await tester.pumpWidget(listeningStatusHost(
            SmartPlaylistsDialog(
                loadStore: () async => _Store([_rule]),
                library: () => tracks,
                statistics: stats,
                randomSeedFactory: () => ++seedCalls,
                evaluate: (_, __) async => tracks),
            boundary: boundary,
            scale: narrow ? 2 : 1,
            brightness: narrow ? Brightness.dark : Brightness.light,
            seed: narrow ? Colors.deepOrange : Colors.indigo));
        await tester.pumpAndSettle();
        await _tap(tester, _key('smart-rule-random'));
        await tester.ensureVisible(_key('smart-next-batch'));
        await tester.pumpAndSettle();
        await capturePlaylistFeature(tester, boundary, '$name-batch');
        final button = tester.getRect(_key('smart-next-batch'));
        expect(button.left, greaterThanOrEqualTo(0));
        expect(button.right, lessThanOrEqualTo(narrow ? 360 : 1080));
        await _tap(tester, _key('smart-next-batch'));
        expect(seedCalls, 2);
        await _tap(tester, find.text(ui('筛选规则')));
        final sort = find.byType(DropdownButtonFormField<SmartPlaylistSort>);
        await tester.ensureVisible(sort);
        await tester.pumpAndSettle();
        final selectedLabel = find
            .descendant(of: sort, matching: find.text(ui('随机抽取')))
            .hitTestable();
        final labelRect = tester.getRect(selectedLabel);
        expect(labelRect.top, greaterThanOrEqualTo(tester.getRect(sort).top));
        expect(labelRect.bottom, lessThanOrEqualTo(tester.getRect(sort).bottom),
            reason:
                'Selected text must fit the field instead of losing a line.');
        await capturePlaylistFeature(tester, boundary, '$name-rule');
        await _tap(tester, sort);
        await capturePlaylistFeature(tester, boundary, '$name-menu');
        expect(find.text(ui('随机抽取')).last, findsOneWidget);
        await tester.tap(find.text(ui('随机抽取')).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
