import 'dart:async';
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
import 'package:dan_player/page/uni_page_components.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

class _Playback extends PlaylistFeaturePlayback {
  _Playback() : super([]);
  List<Audio>? played;
  int? index;
  @override
  void play(int audioIndex, List<Audio> playlist) {
    index = audioIndex;
    played = playlist;
  }
}

class _SortRequest {
  _SortRequest(this.source, this.field, this.direction);
  final List<Audio> source;
  final AudioSortField field;
  final SortDirection direction;
  final result = Completer<List<Audio>>();
  List<Audio> finish() {
    final sorted = sortedAudios(source, field, direction: direction);
    result.complete(sorted);
    return sorted;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final qa = path.join(Directory.current.parent.path, 'tool', 'qa-local',
      'folder-expansion-oct13');
  final music = path.join(qa, 'Music');
  late List<AudioFolder> oldFolders;
  late PagePreference oldFolderPreference, oldSongPreference;
  late int oldChanges;
  late UiLanguage oldLanguage;
  late _Playback playback;

  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    oldFolders = AudioLibrary.instance.folders;
    oldFolderPreference = AppPreference.instance.foldersPagePref;
    oldSongPreference = AppPreference.instance.folderDetailPagePref;
    oldChanges = AudioLibrary.changes.value;
    oldLanguage = uiLanguage.value;
    uiLanguage.value = UiLanguage.zh;
    AppPreference.instance.foldersPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.table);
    AppPreference.instance.folderDetailPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.table);
    playback = _Playback();
  });
  tearDown(() {
    playback.dispose();
    AudioLibrary.instance.folders = oldFolders;
    AppPreference.instance.foldersPagePref = oldFolderPreference;
    AppPreference.instance.folderDetailPagePref = oldSongPreference;
    AudioLibrary.changes.value = oldChanges;
    uiLanguage.value = oldLanguage;
  });

  _ObservedSongs songs([String prefix = 'Song']) => _ObservedSongs([
        for (var index = 599; index >= 0; index--)
          CategoryTestAudio('$prefix ${index.toString().padLeft(4, '0')}',
              path: path.join(music, '$prefix-$index.mp3')),
      ]);
  Finder folder() => find.byKey(ValueKey('folder-open-$music'));
  Finder cover(Audio audio) =>
      find.byKey(ValueKey('folder-tree-cover-${audio.path}'));
  FolderTreePane pane(WidgetTester tester) =>
      tester.widget<FolderTreePane>(find.byType(FolderTreePane));
  List<Audio> queue(WidgetTester tester) =>
      pane(tester).songsByFolder[folderTreePathId(music)]!;

  Future<void> mount(WidgetTester tester, FolderTreeSongSorter sorter) async {
    sizePlaylistFeature(tester, width: 900, height: 720);
    await tester.pumpWidget(playlistFeatureHost(AppEntranceScope(
        child: FoldersPage(
            dataDirectory: Directory(qa),
            playbackService: playback,
            sortLargeFolder: sorter,
            loadArtwork: (_, __) async => null))));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.tapAt(tester.getTopLeft(folder()) + const Offset(70, 35));
    await tester.pump();
  }

  Future<void> sortFolders(WidgetTester tester,
      {int? method, bool descending = false}) async {
    final control = find.byType(SortMethodComboBox<AudioFolder>);
    await tester.tap(
        find.descendant(of: control, matching: find.byType(OutlinedButton)));
    await tester.pumpAndSettle();
    if (method != null) {
      await tester.tap(find.byKey(ValueKey('sort-method-$method')));
    } else if (descending) {
      await tester
          .tap(find.byKey(const ValueKey('app-sort-direction-descending')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape);
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
      'folder sorting preserves completed large-song queue and playback',
      (tester) async {
    final source = songs();
    AudioLibrary.instance.folders = [AudioFolder(source, music, 1, 1)];
    var sorts = 0;
    await mount(tester, (audios, field, direction) async {
      sorts++;
      return sortedAudios(audios, field, direction: direction);
    });
    await tester.pumpAndSettle();
    expect(sorts, 1);
    final original = queue(tester);
    final sourceReads = source.reads;
    final firstCover = tester.element(cover(original.first));
    final controller = pane(tester).controller;
    for (final method in [1, 2, 0]) {
      await sortFolders(tester, method: method);
      expect(sorts, 1,
          reason: 'folder-header ordering does not change a song sort key');
      expect(source.reads, sourceReads);
      expect(queue(tester), same(original));
      expect(pane(tester).controller, same(controller));
      expect(tester.element(cover(original.first)), same(firstCover),
          reason:
              'a header sort must retain mounted song cards and their fade');
    }
    await sortFolders(tester, descending: true);
    expect(sorts, 1);
    expect(queue(tester), same(original));
    await tester.tap(cover(original[1]));
    await tester.pumpAndSettle();
    expect(playback.played, same(original));
    expect(playback.index, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('folder-only reorder retains the pending song request and result',
      (tester) async {
    final source = songs();
    AudioLibrary.instance.folders = [AudioFolder(source, music, 1, 1)];
    final requests = <_SortRequest>[];
    await mount(tester, (audios, field, direction) {
      final request = _SortRequest(audios, field, direction);
      requests.add(request);
      return request.result.future;
    });
    expect(requests, hasLength(1));
    await sortFolders(tester, method: 2);
    final result = requests.single.finish();
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    expect(queue(tester), same(result));
    expect(pane(tester).sortingFolders, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'source replacement after folder reorder still rejects old song work',
      (tester) async {
    AudioLibrary.instance.folders = [AudioFolder(songs(), music, 1, 1)];
    final requests = <_SortRequest>[];
    await mount(tester, (audios, field, direction) {
      final request = _SortRequest(audios, field, direction);
      requests.add(request);
      return request.result.future;
    });
    await sortFolders(tester, method: 1);
    final replacement = songs('Replacement');
    AudioLibrary.instance.folders = [AudioFolder(replacement, music, 1, 1)];
    AudioLibrary.changes.value++;
    await tester.pump();
    requests.first.finish();
    await tester.pump();
    expect(requests, hasLength(2));
    expect(requests.last.source, same(replacement));
    final current = requests.last.finish();
    await tester.pumpAndSettle();
    expect(queue(tester), same(current));
    expect(queue(tester).first.title, startsWith('Replacement'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'folder reorder updates merged selection order and keeps each play queue',
      (tester) async {
    final aPath = path.join(music, 'A');
    final bPath = path.join(music, 'B');
    final a = [
      for (var index = 0; index < 2; index++)
        CategoryTestAudio('A $index', path: path.join(aPath, '$index.mp3')),
    ];
    final b = [
      for (var index = 0; index < 3; index++)
        CategoryTestAudio('B $index', path: path.join(bPath, '$index.mp3')),
    ];
    AudioLibrary.instance.folders = [
      AudioFolder([], music, 1, 1),
      AudioFolder(List.of(a.reversed), aPath, 1, 1),
      AudioFolder(List.of(b.reversed), bPath, 1, 1),
    ];
    await mount(tester, (_, __, ___) async => fail('small lists sort locally'));
    for (final location in [aPath, bPath]) {
      final row = find.byKey(ValueKey('folder-open-$location'));
      await tester.ensureVisible(row);
      await tester.tapAt(tester.getTopLeft(row) + const Offset(70, 35));
      await tester.pumpAndSettle();
    }
    final aQueue = pane(tester).songsByFolder[folderTreePathId(aPath)]!;
    final bQueue = pane(tester).songsByFolder[folderTreePathId(bPath)]!;
    await sortFolders(tester, method: 2);
    await sortFolders(tester, descending: true);
    expect(pane(tester).songsByFolder[folderTreePathId(aPath)], same(aQueue));
    expect(pane(tester).songsByFolder[folderTreePathId(bPath)], same(bQueue));
    final tile = tester.widget<AudioTile>(
        find.byKey(ValueKey('folder-tree-song-${b.first.path}')));
    final selection =
        tile.multiSelectController! as MultiSelectController<Audio>;
    selection.useMultiSelectView(true);
    selection.select(b.first);
    selection.select(a.last);
    await tester.pumpAndSettle();
    final actions = tester.widget<AudioMultiSelectionActions>(
        find.byType(AudioMultiSelectionActions));
    expect(actions.contentList, orderedEquals([...b, ...a]));
    selection.selectRange(actions.contentList, MultiSelectRange.between);
    await tester.pumpAndSettle();
    expect(selection.selectedInOrder(actions.contentList), [...b, ...a]);
    selection.exitMultiSelect();
    await tester.pumpAndSettle();
    await tester.ensureVisible(cover(b[1]));
    await tester.tap(cover(b[1]));
    await tester.pumpAndSettle();
    expect(playback.played, same(bQueue));
    expect(playback.index, 1);
    expect(tester.takeException(), isNull);
  });
}
