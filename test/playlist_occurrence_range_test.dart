import 'dart:io';

import 'package:dan_player/component/audio_selection_toolbar.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/component/smart_playlist_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';
import 'support/playlist_actions.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

class _SmartStore extends SmartPlaylistStore {
  _SmartStore() : super(File('unused-selection-smart-store'));
  @override
  Future<List<SmartPlaylist>> list() async =>
      [const SmartPlaylist(id: 'a', name: 'Rule')];
}

Widget _browser(PlaylistTree tree, Playlist root,
        {Future<void> Function()? persist}) =>
    PlaylistBrowser(
        tree: tree,
        initialPlaylist: root,
        persist: persist ?? () async {},
        onPlay: (_, __) {},
        trackBuilder: (_, audio, play, actions) =>
            ListTile(title: Text(audio.title), onTap: play, trailing: actions));

Future<void> _range(WidgetTester tester, String kind) async {
  await tester.tap(_key('audio-selection-more'));
  await tester.pumpAndSettle();
  final action = _key('multi-selection-range-$kind');
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action.hitTestable());
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    uiLanguage.value = UiLanguage.zh;
    playlistUiSaveError.value = null;
  });

  testWidgets(
      'playlist interval retains separate occurrences of a repeated song',
      (tester) async {
    sizePlaylistFeature(tester);
    final tree = PlaylistTree([]), repeated = CategoryTestAudio('Same');
    final root = tree.createPlaylist('Root');
    final first = tree.createPlaylist('Child', parent: root);
    tree.addAudio(first, repeated);
    final middle = tree.addAudio(root, CategoryTestAudio('Middle'));
    final second = tree.addAudio(root, repeated);
    final tail = tree.addAudio(root, CategoryTestAudio('Tail'));
    await tester.pumpWidget(playlistFeatureHost(_browser(tree, root)));
    await tester.pumpAndSettle();
    await tapPlaylistAction(tester, 'playlist-start-selection');
    for (final id in [first.id, second.id]) {
      await tester.tap(_key('playlist-select-$id'));
      await tester.pumpAndSettle();
    }
    expect(
        tester
            .widget<AudioSelectionMenu>(find.byType(AudioSelectionMenu))
            .selected,
        [repeated, repeated]);
    expect(
        tester
            .widget<Semantics>(_key('playlist-select-${middle.id}'))
            .properties
            .selected,
        isFalse);
    await _range(tester, 'between');
    expect(
        tester
            .widget<AudioSelectionMenu>(find.byType(AudioSelectionMenu))
            .selected,
        [repeated, middle.audio, repeated]);
    expect(
        tester
            .widget<Semantics>(_key('playlist-select-${tail.id}'))
            .properties
            .selected,
        isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'playlist range follows reordered visible entries rather than model insertion',
      (tester) async {
    sizePlaylistFeature(tester);
    final tree = PlaylistTree([]);
    final root = tree.createPlaylist('Root');
    final entries = [
      for (final title in ['D', 'A', 'C', 'B'])
        tree.addAudio(root, CategoryTestAudio(title))
    ];
    await tester.pumpWidget(playlistFeatureHost(_browser(tree, root)));
    await tester.pumpAndSettle();
    // The existing sort control owns the visible sort; no tree order is changed.
    await tester.tap(_key('playlist-sort'));
    await tester.pumpAndSettle();
    await tester.tap(_key('playlist-sort-nameAscending'));
    await tester.pumpAndSettle();
    await tester.tap(_key('playlist-sort'));
    await tester.pumpAndSettle();
    await tester.tap(_key('app-sort-direction-descending'));
    await tester.pumpAndSettle();
    await tapPlaylistAction(tester, 'playlist-start-selection');
    await tester.tap(_key('playlist-select-${entries[2].id}'));
    await tester.pumpAndSettle();
    await _range(tester, 'below');
    expect(
        tester
            .widget<AudioSelectionMenu>(find.byType(AudioSelectionMenu))
            .selected
            .map((audio) => audio.title),
        ['C', 'B', 'A']);
    expect(
        root.flattenAudios().map((audio) => audio.title), ['D', 'A', 'C', 'B']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'playlist removal cancel and save failure preserve mode, success exits',
      (tester) async {
    sizePlaylistFeature(tester);
    final tree = PlaylistTree([]), root = tree.createPlaylist('Root');
    final a = tree.addAudio(root, CategoryTestAudio('A'));
    final b = tree.addAudio(root, CategoryTestAudio('B'));
    var fail = true;
    await tester
        .pumpWidget(playlistFeatureHost(_browser(tree, root, persist: () async {
      if (fail) throw StateError('fixture save failure');
    })));
    await tester.pumpAndSettle();
    await tapPlaylistAction(tester, 'playlist-start-selection');
    await tester.tap(_key('playlist-select-${a.id}'));
    await tester.pumpAndSettle();
    await tester.tap(_key('playlist-remove-selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(_key('playlist-end-selection'), findsOneWidget);
    expect(root.entries.length, 2);
    await tester.tap(_key('playlist-remove-selected'));
    await tester.pumpAndSettle();
    await tester.tap(_key('playlist-confirm-remove-selected'));
    await tester.pumpAndSettle();
    expect(_key('playlist-end-selection'), findsOneWidget);
    expect(root.entries.single.id, b.id);
    fail = false;
    await tester.tap(_key('playlist-select-${b.id}'));
    await tester.pumpAndSettle();
    await tester.tap(_key('playlist-remove-selected'));
    await tester.pumpAndSettle();
    await tester.tap(_key('playlist-confirm-remove-selected'));
    await tester.pumpAndSettle();
    expect(_key('playlist-end-selection'), findsNothing);
    expect(root.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'successful retry of a failed batch removal retires its selection session',
      (tester) async {
    sizePlaylistFeature(tester);
    final tree = PlaylistTree([]), root = tree.createPlaylist('Root');
    final entry = tree.addAudio(root, CategoryTestAudio('A'));
    var saves = 0;
    await tester
        .pumpWidget(playlistFeatureHost(_browser(tree, root, persist: () async {
      if (++saves == 1) throw StateError('fixture save failure');
    })));
    await tester.pumpAndSettle();
    await tapPlaylistAction(tester, 'playlist-start-selection');
    await tester.tap(_key('playlist-select-${entry.id}'));
    await tester.pumpAndSettle();
    await tester.tap(_key('playlist-remove-selected'));
    await tester.pumpAndSettle();
    await tester.tap(_key('playlist-confirm-remove-selected'));
    await tester.pumpAndSettle();
    expect(_key('playlist-end-selection'), findsOneWidget);
    expect(_key('playlist-retry-save'), findsOneWidget);
    await tester.tap(_key('playlist-retry-save'));
    await tester.pumpAndSettle();
    expect(saves, 2);
    expect(root.entries, isEmpty);
    expect(_key('playlist-end-selection'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'smart playlist explicitly fills its visible interval without rerunning its preview',
      (tester) async {
    sizePlaylistFeature(tester);
    final tracks = [
      for (final title in ['A', 'B', 'C', 'D']) CategoryTestAudio(title)
    ];
    var evaluations = 0;
    List<Audio>? exported;
    await tester.pumpWidget(playlistFeatureHost(SmartPlaylistsDialog(
        loadStore: () async => _SmartStore(),
        library: () => tracks,
        evaluate: (_, __) async {
          evaluations++;
          return tracks;
        },
        onExport: (items) => exported = items)));
    await tester.pumpAndSettle();
    await tester.tap(_key('smart-rule-a'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('smart-select'));
    await tester.tap(_key('smart-select'));
    await tester.pumpAndSettle();
    for (final audio in [tracks[1], tracks[2]]) {
      final row = _key('smart-result-${audio.path}');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(_key('audio-selection-more'));
    final calls = evaluations;
    expect(
        tester
            .widget<AudioSelectionToolbar>(find.byType(AudioSelectionToolbar))
            .selected,
        [tracks.first, tracks.last]);
    await _range(tester, 'between');
    expect(
        tester
            .widget<AudioSelectionToolbar>(find.byType(AudioSelectionToolbar))
            .selected,
        tracks);
    expect(evaluations, calls);
    await tester.tap(_key('audio-selection-more'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('audio-selection-export'));
    await tester.tap(_key('audio-selection-export'));
    await tester.pumpAndSettle();
    expect(exported, tracks);
    expect(find.byType(AudioSelectionToolbar), findsOneWidget,
        reason: 'legacy void export cannot claim a committed result');
    expect(tester.takeException(), isNull);
  });
}
