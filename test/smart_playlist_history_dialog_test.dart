import 'dart:io';
import 'package:dan_player/component/smart_playlist_dialog.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';

class _Store extends SmartPlaylistStore {
  _Store() : super(File('unused-smart-history-fixture'));
  final rules = <SmartPlaylist>[];
  @override
  Future<List<SmartPlaylist>> list() async => List.of(rules);
  @override
  Future<void> upsert(SmartPlaylist rule) async {
    rules.removeWhere((r) => r.id == rule.id);
    rules.add(rule);
  }
}

Widget host(Widget child,
        {Brightness brightness = Brightness.light, double scale = 1}) =>
    MaterialApp(
        theme: ThemeData(brightness: brightness, colorSchemeSeed: Colors.teal),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale), disableAnimations: true),
            child: UiLanguageScope(child: child!)),
        home: Scaffold(body: child));

void main() {
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  testWidgets(
      'presets are editable drafts, persist history and limit, and fit narrow multilingual layouts',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      final store = _Store();
      final stats = PlaybackStatistics.inMemory();
      uiLanguage.value =
          brightness == Brightness.dark ? UiLanguage.en : UiLanguage.zh;
      await tester.pumpWidget(host(
          SmartPlaylistsDialog(
              loadStore: () async => store,
              library: () => [],
              statistics: stats,
              evaluate: (_, __) async => []),
          brightness: brightness,
          scale: 1.6));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('smart-preset-recent')));
      await tester.pumpAndSettle();
      expect(store.rules, isEmpty);
      expect(find.byKey(const ValueKey('smart-history-days')), findsOneWidget);
      await tester
          .ensureVisible(find.byKey(const ValueKey('smart-history-days')));
      await tester.enterText(
          find.byKey(const ValueKey('smart-history-days')), '7');
      await tester
          .ensureVisible(find.byKey(const ValueKey('smart-result-limit')));
      await tester.enterText(
          find.byKey(const ValueKey('smart-result-limit')), '20');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.ensureVisible(find.byKey(const ValueKey('smart-save')));
      await tester.tap(find.byKey(const ValueKey('smart-save')));
      await tester.pumpAndSettle();
      expect(store.rules.single.history, SmartPlaylistHistory.recent);
      expect(store.rules.single.historyDays, 7);
      expect(store.rules.single.maxResults, 20);
      expect(store.rules.single.sort, SmartPlaylistSort.recentlyPlayed);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      stats.dispose();
    }
  });
  testWidgets(
      'only relevant statistics changes refresh an open history rule; clear and disposal are safe',
      (tester) async {
    var now = DateTime.utc(2026, 9, 6);
    final stats = PlaybackStatistics.inMemory(clock: () => now);
    addTearDown(stats.dispose);
    final audio = CategoryTestAudio('A');
    final store = _Store()
      ..rules.add(const SmartPlaylist(id: 'metadata', name: 'Metadata'));
    final calls = <SmartPlaylist>[];
    await tester.pumpWidget(host(SmartPlaylistsDialog(
        loadStore: () async => store,
        library: () => [audio],
        statistics: stats,
        evaluate: (rule, _) async {
          calls.add(rule);
          return [audio];
        })));
    await tester.pumpAndSettle();
    stats.start(audio);
    await tester.pump(const Duration(milliseconds: 550));
    expect(calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('smart-rule-metadata')));
    await tester.pumpAndSettle();
    expect(calls.length, 1);
    await stats.initialize();
    await tester.pump(const Duration(milliseconds: 550));
    expect(calls.length, 1);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('smart-preset-unplayed')));
    await tester.pumpAndSettle();
    expect(calls.last.history, SmartPlaylistHistory.unplayed);
    expect(calls.length, 2);
    stats.start(audio);
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pumpAndSettle();
    expect(calls.length, 3);
    now = now.add(const Duration(seconds: 6));
    stats.tick(audio, PlayerState.playing);
    await tester.pump(const Duration(milliseconds: 550));
    expect(calls.length, 3,
        reason: 'Listening time is not a smart history condition.');
    await stats.initialize();
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pumpAndSettle();
    expect(calls.length, 4);
    await tester.ensureVisible(find.byKey(const ValueKey('smart-refresh')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('smart-refresh')));
    await tester.pumpAndSettle();
    expect(calls.length, 5);
    await tester.pumpWidget(const SizedBox());
    stats.start(audio);
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls.length, 5);
    expect(tester.takeException(), isNull);
  });
}
