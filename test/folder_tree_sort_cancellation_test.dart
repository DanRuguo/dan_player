import 'dart:collection';
import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/folder_tree_pane.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/library/folder_tree.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

class _ObservedSongs extends ListBase<Audio> {
  _ObservedSongs(this.values);
  final List<Audio> values;
  var reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('Fixture is read-only');
  @override
  Audio operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, Audio value) =>
      throw UnsupportedError('Fixture is read-only');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final qa = path.join(Directory.current.parent.path, 'tool', 'qa-local',
      'folder-expansion-oct13');
  final music = path.join(qa, 'Cancel Music');
  setUpAll(loadPlaylistFeatureFonts);

  _ObservedSongs songs(int count) => _ObservedSongs([
        for (var index = count - 1; index >= 0; index--)
          CategoryTestAudio('Song ${index.toString().padLeft(5, '0')}',
              path: path.join(music, 'Song-$index.mp3')),
      ]);

  test('a revoked sort request reads no source descriptors', () async {
    final source = songs(20000);
    await expectLater(
        sortFolderTreeSongs(
            source, AudioSortField.name, SortDirection.ascending,
            isCancelled: () => true),
        throwsA(isA<FolderTreeSortCancelled>()));
    expect(source.reads, 0);
  });

  test('cancellation during a snapshot stops after its bounded admitted batch',
      () async {
    final source = songs(20000);
    var cancelled = false;
    final pending = sortFolderTreeSongs(
        source, AudioSortField.name, SortDirection.ascending,
        isCancelled: () => cancelled);
    expect(source.reads, 512);
    cancelled = true;
    await expectLater(pending, throwsA(isA<FolderTreeSortCancelled>()));
    expect(source.reads, 512,
        reason:
            'an obsolete folder must not snapshot the remaining 19488 songs');
  });

  test('the owner is rechecked before dispatching a completed snapshot',
      () async {
    final source = songs(100);
    await expectLater(
        sortFolderTreeSongs(
            source, AudioSortField.name, SortDirection.ascending,
            isCancelled: () => source.reads == source.length),
        throwsA(isA<FolderTreeSortCancelled>()));
    expect(source.reads, 100);
  });

  testWidgets(
      'real folder collapse stops default sorting admission and reopen owns a new batch',
      (tester) async {
    final source = songs(20000);
    final oldFolders = AudioLibrary.instance.folders;
    final oldFolderPreference = AppPreference.instance.foldersPagePref;
    final oldSongPreference = AppPreference.instance.folderDetailPagePref;
    final oldLanguage = uiLanguage.value;
    final playback = PlaylistFeaturePlayback([]);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      playback.dispose();
      AudioLibrary.instance.folders = oldFolders;
      AppPreference.instance.foldersPagePref = oldFolderPreference;
      AppPreference.instance.folderDetailPagePref = oldSongPreference;
      uiLanguage.value = oldLanguage;
    });
    AudioLibrary.instance.folders = [AudioFolder(source, music, 1, 1)];
    AppPreference.instance.foldersPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.table);
    AppPreference.instance.folderDetailPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.table);
    uiLanguage.value = UiLanguage.zh;
    sizePlaylistFeature(tester, width: 900, height: 720);
    await tester.pumpWidget(playlistFeatureHost(AppEntranceScope(
        child: FoldersPage(
            dataDirectory: Directory(qa),
            playbackService: playback,
            loadArtwork: (_, __) async => null))));
    await tester.pumpAndSettle();
    final folder = find.byKey(ValueKey('folder-open-$music'));
    Future<void> toggle() async {
      await tester.tapAt(tester.getTopLeft(folder) + const Offset(70, 35));
      await tester.pump();
    }

    expect(source.reads, 0);
    await toggle();
    expect(source.reads, 512);
    expect(find.byType(AudioTile), findsNothing,
        reason: 'the loading row must not expose an unsorted playback queue');
    await toggle();
    for (var turn = 0; turn < 8; turn++) {
      await tester.pump(Duration.zero);
    }
    expect(source.reads, 512,
        reason:
            'collapse must revoke real default-sort work, not just its result');
    expect(
        tester
            .widget<FolderTreePane>(find.byType(FolderTreePane))
            .sortingFolders,
        isEmpty);
    await toggle();
    expect(source.reads, 1024,
        reason:
            'reopening admits a new request rather than resuming stale work');
    await toggle();
    await tester.pump(Duration.zero);
    expect(source.reads, 1024);
    expect(tester.takeException(), isNull);
  });
}
