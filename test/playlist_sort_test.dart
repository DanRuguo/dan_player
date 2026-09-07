import 'dart:convert';

import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';
import 'support/playlist_actions.dart';

CategoryTestAudio _ranked(String id, int rank) => CategoryTestAudio(id,
    path: 'D:/sort-fixtures/$id.${rank == 1 ? 'flac' : 'mp3'}',
    artist: rank == 1 ? 'Alpha' : 'Zulu',
    album: rank == 1 ? 'Alpha' : 'Zulu',
    composer: rank == 1 ? 'Alpha' : 'Zulu',
    albumArtist: rank == 1 ? 'Alpha' : 'Zulu',
    language: rank == 1 ? 'en' : 'zh',
    track: rank)
  ..duration = rank * 100
  ..bitrate = rank * 128
  ..sampleRate = rank * 44100
  ..fileSizeBytes = rank * 1000;

CategoryTestAudio _missing() => CategoryTestAudio('Missing',
    artist: 'UNKNOWN', album: '', path: 'D:/sort-fixtures/Missing')
  ..duration = 0
  ..bitrate = null
  ..sampleRate = null;

class _Fixture {
  final roots = <Playlist>[];
  late final tree = PlaylistTree(roots);
  late final parent = tree.createPlaylist('Parent');
  late final missing = _missing();
  late final low = _ranked('Low', 1);
  late final high = _ranked('High', 2);
  late final equal = _ranked('Equal', 1);
  late final nestedB = CategoryTestAudio('NestedB');
  late final nestedA = CategoryTestAudio('NestedA');
  late Playlist childB;
  late Playlist childA;
  int saves = 0;
  final played = <({int index, List<Audio> queue})>[];

  void populate() {
    tree.addAudio(parent, missing);
    childB = tree.createPlaylist('Child B', parent: parent);
    tree.addAudio(childB, nestedB);
    tree.addAudio(parent, low);
    tree.addAudio(parent, high);
    childA = tree.createPlaylist('Child A', parent: parent);
    tree.addAudio(childA, nestedA);
    tree.addAudio(parent, equal);
  }

  String get snapshot => jsonEncode(roots.map((root) => root.toMap()).toList());

  Widget browser() => PlaylistBrowser(
        tree: tree,
        initialPlaylist: parent,
        library: const [],
        persist: () async => saves++,
        onPlay: (index, queue) => played.add((index: index, queue: queue)),
        trackBuilder: (_, audio, play, actions) => ListTile(
          key: ValueKey(('sort-song', audio.path)),
          title: Text(audio.title),
          onTap: play,
          trailing: actions,
        ),
      );
}

Future<void> _show(WidgetTester tester, _Fixture fixture) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1100, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(platform: TargetPlatform.windows, useMaterial3: true),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    home: Scaffold(body: fixture.browser()),
  ));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(const ValueKey('playlist-sort')));
  await tester.pumpAndSettle();
  final option = find.byKey(ValueKey(key));
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Future<void> _play(WidgetTester tester) async {
  await playVisiblePlaylistSelection(tester);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    playlistUiSaveError.value = null;
    playlistUiSaving.value = false;
  });
  tearDown(() => expect(PlayService.isInitialized, isFalse));

  for (final mode in [
    PlaylistSortMode.artist,
    PlaylistSortMode.album,
    PlaylistSortMode.composer,
    PlaylistSortMode.albumArtist,
    PlaylistSortMode.duration,
    PlaylistSortMode.track,
    PlaylistSortMode.bitrate,
    PlaylistSortMode.sampleRate,
    PlaylistSortMode.fileSize,
    PlaylistSortMode.format,
    PlaylistSortMode.language
  ]) {
    testWidgets(
        '${mode.name} changes only display/DFS queue, missing folders stable both directions',
        (tester) async {
      final fixture = _Fixture()..populate();
      final source = fixture.snapshot;
      await _show(tester, fixture);
      await _choose(tester, 'playlist-sort-${mode.name}');
      await _play(tester);
      expect(fixture.played.last.queue, [
        fixture.low,
        fixture.equal,
        fixture.high,
        fixture.missing,
        fixture.nestedB,
        fixture.nestedA
      ]);
      expect(fixture.snapshot, source);
      await _choose(tester, 'app-sort-direction-descending');
      await _play(tester);
      expect(fixture.played.last.queue, [
        fixture.high,
        fixture.low,
        fixture.equal,
        fixture.missing,
        fixture.nestedB,
        fixture.nestedA
      ]);
      expect(
          tester
              .getTopLeft(
                  find.byKey(ValueKey('playlist-open-${fixture.childB.id}')))
              .dy,
          lessThan(tester
              .getTopLeft(
                  find.byKey(ValueKey('playlist-open-${fixture.childA.id}')))
              .dy));
      await tester.tap(find.byKey(ValueKey(('sort-song', fixture.equal.path))));
      expect(fixture.played.last.index, 2);
      await _choose(tester, 'playlist-sort-custom');
      await _play(tester);
      expect(fixture.played.last.queue, [
        fixture.missing,
        fixture.nestedB,
        fixture.low,
        fixture.high,
        fixture.nestedA,
        fixture.equal
      ]);
      expect(fixture.saves, 0);
      expect(fixture.snapshot, source);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'source sort differentiates actual local/online descriptors and keeps folder last',
      (tester) async {
    final fixture = _Fixture();
    final remote = CategoryTestAudio('Remote', online: true);
    final local = CategoryTestAudio('Local');
    fixture.tree.addAudio(fixture.parent, remote);
    final child = fixture.tree.createPlaylist('Child', parent: fixture.parent);
    final nested = CategoryTestAudio('Nested');
    fixture.tree.addAudio(child, nested);
    fixture.tree.addAudio(fixture.parent, local);
    await _show(tester, fixture);
    await _choose(tester, 'playlist-sort-source');
    await _play(tester);
    expect(fixture.played.last.queue.last, nested);
    final ascending = fixture.played.last.queue.take(2).toList();
    await _choose(tester, 'app-sort-direction-descending');
    await _play(tester);
    expect(fixture.played.last.queue, [...ascending.reversed, nested]);
    expect(fixture.saves, 0);
    expect(compareAudioSort(remote, local, AudioSortField.source), isNot(0));
  });
}
