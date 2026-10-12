import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/folder_tree_pane.dart';
import 'package:dan_player/component/playlist_tree_item.dart';
import 'package:dan_player/folder_note_preferences.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/library/folder_tree.dart';
import 'package:dan_player/page/audio_sort_methods.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

class _Playback extends PlaylistFeaturePlayback {
  _Playback() : super([]);
  int? playedIndex;
  List<Audio>? played;
  @override
  void play(int audioIndex, List<Audio> playlist) {
    playedIndex = audioIndex;
    played = List.of(playlist);
  }
}

class _ObservedSnapshotSongs extends ListBase<Audio> {
  _ObservedSnapshotSongs(this.values);
  final List<Audio> values;
  int reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('Read-only fixture');
  @override
  Audio operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, Audio value) =>
      throw UnsupportedError('Read-only fixture');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final qa = path.join(Directory.current.parent.path, 'tool', 'qa-local',
      'selection-folders-oct11', 'lyrics');
  final music = path.join(qa, 'data', 'Music');
  final cache = Directory(path.join(qa, 'data', 'PlayerData'));
  late _Playback playback;
  late List<AudioFolder> previousFolders;
  late PagePreference previousFolderPref, previousSongPref;
  late FolderNotePreferences previousNotes;
  final songs = [
    for (var i = 0; i < 9; i++)
      CategoryTestAudio('Song ${i.toString().padLeft(2, '0')} 国かな한글 🎵',
          path: path.join(music, '$i.mp3')),
  ];
  final child = path.join(music, 'Child');
  final sibling = path.join(music, 'Sibling');
  final leaf = path.join(child, 'Missing', 'Leaf');

  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    uiLanguage.value = UiLanguage.zh;
    previousFolders = AudioLibrary.instance.folders;
    previousFolderPref = AppPreference.instance.foldersPagePref;
    previousSongPref = AppPreference.instance.folderDetailPagePref;
    previousNotes = AppSettings.instance.folderNotes.value;
    AudioLibrary.instance.folders = [
      AudioFolder(List.of(songs.reversed), music, 1, 1),
      AudioFolder(
          [CategoryTestAudio('Child direct', path: path.join(child, 'c.mp3'))],
          child,
          2,
          2),
      AudioFolder(
          [CategoryTestAudio('Leaf direct', path: path.join(leaf, 'l.mp3'))],
          leaf,
          3,
          3),
      AudioFolder([], sibling, 0, 0),
    ];
    AppPreference.instance.foldersPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.table);
    AppPreference.instance.folderDetailPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.table);
    AppSettings.instance.folderNotes.value =
        const FolderNotePreferences().withNote(music, 'Folder note 音楽 모음');
    playback = _Playback();
  });
  tearDown(() {
    playback.dispose();
    AudioLibrary.instance.folders = previousFolders;
    AppPreference.instance.foldersPagePref = previousFolderPref;
    AppPreference.instance.folderDetailPagePref = previousSongPref;
    AppSettings.instance.folderNotes.value = previousNotes;
    uiLanguage.value = UiLanguage.zh;
  });

  Future<void> mount(WidgetTester tester,
      {double width = 1000,
      double scale = 1,
      String? initial,
      GlobalKey? boundary,
      FolderTreeSongSorter? sortLargeFolder}) async {
    sizePlaylistFeature(tester, width: width, height: 1000);
    await tester.pumpWidget(UiLanguageScope(
        child: playlistFeatureHost(
            AppEntranceScope(
                child: FoldersPage(
                    dataDirectory: cache,
                    initialFolderPath: initial,
                    playbackService: playback,
                    sortLargeFolder: sortLargeFolder,
                    loadArtwork: (_, __) async => null)),
            textScale: scale,
            boundary: boundary)));
    await tester.pumpAndSettle();
  }

  Finder folder(String value) => find.byKey(ValueKey('folder-open-$value'));
  Finder cover(Audio audio) =>
      find.byKey(ValueKey('folder-tree-cover-${audio.path}'));
  Future<void> toggle(WidgetTester tester, String value) async {
    await tester.ensureVisible(folder(value));
    // Primary input lands on the real folder row, away from its menu button.
    await tester.tapAt(tester.getTopLeft(folder(value)) + const Offset(70, 35));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'short press shows direct songs before true children without navigation',
      (tester) async {
    await mount(tester);
    expect(find.byType(ContentViewSwitch<AudioFolder>), findsNothing);
    expect(find.byType(AudioTile), findsNothing);
    await toggle(tester, music);
    expect(folder(child), findsOneWidget);
    expect(folder(sibling), findsOneWidget);
    expect(folder(leaf), findsNothing);
    expect(tester.getTopLeft(folder(child)).dx,
        tester.getTopLeft(folder(sibling)).dx);
    final childArtwork = find.byKey(ValueKey('folder-artwork-$child'));
    final siblingArtwork = find.byKey(ValueKey('folder-artwork-$sibling'));
    expect(tester.getTopLeft(childArtwork).dx,
        tester.getTopLeft(siblingArtwork).dx);
    expect(tester.getTopLeft(cover(songs.first)).dx,
        closeTo(tester.getTopLeft(childArtwork).dx, .01));
    expect(tester.getTopLeft(cover(songs.first)).dy,
        lessThan(tester.getTopLeft(folder(child)).dy));
    expect(find.text('Folder note 音楽 모음'), findsOneWidget);
    await toggle(tester, child);
    final middle = path.join(child, 'Missing');
    expect(folder(middle), findsOneWidget);
    expect(folder(leaf), findsNothing);
    await toggle(tester, middle);
    expect(folder(leaf), findsOneWidget);
    expect(tester.getTopLeft(folder(leaf)).dx,
        greaterThan(tester.getTopLeft(folder(child)).dx));
    expect(find.byType(FoldersPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'song covers are row-major and playback keeps sorted direct folder queue',
      (tester) async {
    await mount(tester, width: 360);
    await toggle(tester, music);
    final rectangles = [for (final song in songs) tester.getRect(cover(song))];
    var sawNextRow = false;
    for (var i = 1; i < rectangles.length; i++) {
      if ((rectangles[i].top - rectangles[i - 1].top).abs() < .01) {
        expect(rectangles[i].left, greaterThan(rectangles[i - 1].left));
      } else {
        sawNextRow = true;
        expect(rectangles[i].top, greaterThan(rectangles[i - 1].top));
        expect(rectangles[i].left, closeTo(rectangles.first.left, .01));
      }
    }
    expect(sawNextRow, isTrue);
    await tester.tap(cover(songs[6]));
    await tester.pumpAndSettle();
    expect(playback.playedIndex, 6);
    expect(playback.played, songs);
    expect(AudioLibrary.instance.folders.first.audios, songs.reversed.toList());
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(cover(songs.first)));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(find.text(songs.first.displayTitle), findsOneWidget);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'folder and song menus change independent legacy sort preferences',
      (tester) async {
    await mount(tester);
    await toggle(tester, music);
    final sortFolders = find.byType(SortMethodComboBox<AudioFolder>);
    await tester.tap(find.descendant(
        of: sortFolders, matching: find.byType(OutlinedButton)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sort-method-2')));
    await tester.pumpAndSettle();
    expect(AppPreference.instance.foldersPagePref.sortMethod, 2);
    expect(AppPreference.instance.folderDetailPagePref.sortMethod, 0);
    expect(tester.getTopLeft(folder(sibling)).dy,
        lessThan(tester.getTopLeft(folder(child)).dy));
    final sortSongs = find.byType(SortMethodComboBox<Audio>);
    await tester.tap(
        find.descendant(of: sortSongs, matching: find.byType(OutlinedButton)));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('app-sort-direction-descending')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(AppPreference.instance.folderDetailPagePref.sortOrder,
        SortOrder.decending);
    expect(tester.getTopLeft(cover(songs.last)).dx,
        lessThan(tester.getTopLeft(cover(songs[songs.length - 2])).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'path reveal opens ancestors once and refresh keeps expansion and projected identity',
      (tester) async {
    await mount(tester, initial: leaf.toUpperCase());
    final pane = tester.widget<FolderTreePane>(find.byType(FolderTreePane));
    final tree = pane.tree;
    final projectedSongs = pane.songsByFolder;
    expect(folder(leaf), findsOneWidget);
    await toggle(tester, child);
    expect(folder(leaf), findsNothing);
    expect(tester.widget<FolderTreePane>(find.byType(FolderTreePane)).tree,
        same(tree));
    expect(
        tester
            .widget<FolderTreePane>(find.byType(FolderTreePane))
            .songsByFolder,
        same(projectedSongs));
    uiLanguage.value = UiLanguage.ja;
    await tester.pumpAndSettle();
    expect(tester.widget<FolderTreePane>(find.byType(FolderTreePane)).tree,
        same(tree));
    AudioLibrary.instance.folders = [
      for (final item in AudioLibrary.instance.folders)
        AudioFolder(
            List.of(item.audios), item.path, item.modified, item.latest),
    ];
    AudioLibrary.changes.value++;
    await tester.pumpAndSettle();
    expect(folder(child), findsOneWidget);
    expect(folder(leaf), findsNothing,
        reason: 'Refresh must not undo manual collapse');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'tree selection uses displayed order and keeps collapsed selections hidden',
      (tester) async {
    await mount(tester, initial: music);
    final firstTile = tester.widget<AudioTile>(
        find.byKey(ValueKey('folder-tree-song-${songs[1].path}')));
    final controller =
        firstTile.multiSelectController! as MultiSelectController<Audio>;
    controller.useMultiSelectView(true);
    controller.select(songs[1]);
    controller.select(songs[5]);
    await tester.pumpAndSettle();
    final actions = tester.widget<AudioMultiSelectionActions>(
        find.byType(AudioMultiSelectionActions));
    expect(actions.contentList, songs);
    controller.selectRange(actions.contentList, MultiSelectRange.between);
    await tester.pumpAndSettle();
    expect(
        controller.selectedInOrder(actions.contentList), songs.sublist(1, 6));
    await toggle(tester, music);
    expect(controller.selected, hasLength(5));
    expect(
        tester
            .widget<AudioMultiSelectionActions>(
                find.byType(AudioMultiSelectionActions))
            .contentList,
        isEmpty);
    controller.exitMultiSelect();
    await tester.pumpAndSettle();
    expect(find.byType(AudioMultiSelectionActions), findsNothing);
    expect(controller.selected, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large expanded directory mounts only visible song rows',
      (tester) async {
    AudioLibrary.instance.folders = [
      AudioFolder([
        for (var i = 0; i < 5000; i++) CategoryTestAudio('Track $i'),
      ], music, 1, 1)
    ];
    await mount(tester, width: 360, initial: music);
    expect(find.byType(AudioTile).evaluate().length, lessThan(100));
    expect(
        tester
            .widget<FolderTreePane>(find.byType(FolderTreePane))
            .songsByFolder
            .values
            .single,
        hasLength(5000));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'duration revision during folder snapshot rejects the obsolete real worker',
      (tester) async {
    final oldRevision = AudioLibrary.revision;
    final oldSortRevision = AudioLibrary.sortRevision;
    final oldChanges = AudioLibrary.changes.value;
    addTearDown(() {
      AudioLibrary.revision = oldRevision;
      AudioLibrary.sortRevision = oldSortRevision;
      AudioLibrary.changes.value = oldChanges;
    });
    final source = _ObservedSnapshotSongs([
      for (var index = 1599; index >= 0; index--)
        CategoryTestAudio('Duration $index',
            duration: index + 10, path: path.join(music, '$index.mp3')),
    ]);
    AudioLibrary.instance.folders = [AudioFolder(source, music, 1, 1)];
    AppPreference.instance.folderDetailPagePref.sortMethod =
        audioSortMethods(AudioSortProfile.folder).indexWhere((method) =>
            (method as AudioSortMethodDesc).field == AudioSortField.duration);
    final firstDelivery = Completer<void>();
    List<Audio>? obsoleteResult;
    var calls = 0, firstSynchronousReads = 0;
    await mount(tester, sortLargeFolder: (songs, field, direction) {
      final first = ++calls == 1;
      final pending = sortFolderTreeSongs(songs, field, direction);
      if (!first) return pending;
      firstSynchronousReads = source.reads;
      return pending.then((actual) async {
        // Hold only delivery of a genuine worker result, never its algorithm
        // or input. The result itself must show the captured obsolete key.
        obsoleteResult = actual;
        await firstDelivery.future;
        return actual;
      });
    });
    final id = folderTreePathId(music);
    final loading = find.byKey(ValueKey('folder-tree-sorting-$id'));
    final corrected = source.values.first;
    void rejectObsoletePaint() {
      if (find.byType(AudioTile).evaluate().isNotEmpty) {
        final order = tester
            .widget<FolderTreePane>(find.byType(FolderTreePane))
            .songsByFolder[id]!;
        expect(order.first, same(corrected),
            reason: 'No rendered frame may publish the obsolete key order.');
      }
    }

    try {
      await tester
          .tapAt(tester.getTopLeft(folder(music)) + const Offset(70, 35));
      await tester.pump();
      expect(calls, 1);
      expect(firstSynchronousReads, 512);
      expect(source.reads, lessThan(source.length),
          reason: 'Change metadata while the real key snapshot is yielding.');
      expect(loading, findsOneWidget);
      expect(find.byType(AudioTile), findsNothing);
      corrected.duration = 1;
      AudioLibrary.instance.publishDurationChanges();
      await tester.pump();
      expect(
          tester
              .widget<FolderTreePane>(find.byType(FolderTreePane))
              .songsByFolder[id],
          same(source),
          reason:
              'The revision changes in-place metadata, not the source array.');
      rejectObsoletePaint();
      for (var turn = 0; turn < 300 && obsoleteResult == null; turn++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        // The real isolate needs runAsync; the yielding snapshot's timers
        // belong to FakeAsync and separately need explicit clock advancement.
        await tester.pump(const Duration(milliseconds: 1));
        rejectObsoletePaint();
      }
      expect(obsoleteResult, isNotNull);
      expect(obsoleteResult!.first, isNot(same(corrected)));
      expect(loading, findsOneWidget);
      firstDelivery.complete();
      await tester.pump();
      rejectObsoletePaint();
      for (var turn = 0; turn < 300 && loading.evaluate().isNotEmpty; turn++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump(const Duration(milliseconds: 1));
        rejectObsoletePaint();
      }
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(loading, findsNothing);
      final actual = tester
          .widget<FolderTreePane>(find.byType(FolderTreePane))
          .songsByFolder[id]!;
      final expected = sortedAudios(source, AudioSortField.duration);
      for (var index = 0; index < expected.length; index++) {
        expect(actual[index], same(expected[index]));
      }
      expect(actual.first, same(corrected));
      expect(AudioLibrary.instance.folders.single.audios, same(source));
      expect(cover(corrected), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      if (!firstDelivery.isCompleted) firstDelivery.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  for (final language in UiLanguage.values) {
    for (final width in [1000.0, 360.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            'folder tree ${language.name} width $width text $scale renders controls and covers',
            (tester) async {
          uiLanguage.value = language;
          final boundary = GlobalKey();
          await mount(tester,
              width: width, scale: scale, initial: music, boundary: boundary);
          expect(find.text(ui('文件夹排序')), findsOneWidget);
          expect(find.text(ui('歌曲排序')), findsOneWidget);
          expect(find.text(ui('{0} 个文件夹', [5])), findsOneWidget);
          for (final control in [
            find.byType(SortMethodComboBox<AudioFolder>),
            find.byType(SortMethodComboBox<Audio>),
          ]) {
            final button = find.descendant(
                of: control, matching: find.byType(OutlinedButton));
            await tester.ensureVisible(button);
            final rect = tester.getRect(button);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            await tester.tap(button);
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('sort-method-0')), findsOneWidget);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape,
                physicalKey: PhysicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('sort-method-0')), findsNothing);
          }
          final footer = find.byType(PlayerDataFolderTile);
          // Group captions may move the footer beyond the lazy mount budget.
          // Scroll its real viewport before requiring a mounted render object.
          await tester.scrollUntilVisible(footer, 180,
              scrollable: find
                  .descendant(
                      of: find.byType(FolderTreePane),
                      matching: find.byType(Scrollable))
                  .first);
          await tester.ensureVisible(footer);
          await tester.pumpAndSettle();
          expect(tester.getRect(footer).right, lessThanOrEqualTo(width));
          await tester.tap(
              find.descendant(of: footer, matching: find.byType(IconButton)));
          await tester.pumpAndSettle();
          expect(
              find.byKey(const ValueKey('folder-note-menu')), findsOneWidget);
          await tester.tap(
              find.descendant(of: footer, matching: find.byType(IconButton)));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('folder-note-menu')), findsNothing);
          final scroll = tester
              .widget<FolderTreePane>(find.byType(FolderTreePane))
              .controller!;
          scroll.jumpTo(0);
          await tester.pumpAndSettle();
          expect(find.byType(PlaylistTreeItem), findsWidgets);
          await capturePlaylistFeature(tester, boundary,
              'folder-tree-${language.name}-${width.toInt()}-${scale.toInt()}');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          expect(tester.binding.transientCallbackCount, 0);
        });
      }
    }
  }
}
