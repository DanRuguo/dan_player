import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart' show getAppDataDir;
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/folder_tree_pane.dart';
import 'package:dan_player/component/playlist_tree_item.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/folder_tree.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

class _ProgressivePlayback extends PlaylistFeaturePlayback {
  _ProgressivePlayback() : super([]);
  List<Audio>? played;
  int? playedIndex;
  @override
  void play(int audioIndex, List<Audio> playlist) {
    played = playlist;
    playedIndex = audioIndex;
  }
}

class _ProgressiveFolderFixture {
  _ProgressiveFolderFixture(this.music, this.songs)
      : tree = FolderTree.project(
            folders: [AudioFolder(songs, music, 1, 1)], scanRoots: []);
  final String music;
  final List<Audio> songs;
  final FolderTree tree;
  final scroll = ScrollController();
  final hidden = ValueNotifier(false);
  final playback = _ProgressivePlayback();
  final selection = MultiSelectController<Audio>();
  final built = <String>[];
  late StateSetter change;
  bool expanded = false;

  Widget host() => playlistFeatureHost(StatefulBuilder(builder: (context, set) {
        change = set;
        return FolderTreePane(
            tree: tree,
            expanded: expanded ? {tree.roots.single.id} : {},
            songsByFolder: {tree.roots.single.id: songs},
            controller: scroll,
            hidden: hidden,
            footer: const SizedBox(height: 72),
            folderBuilder: (_, __) => SizedBox(
                height: 72,
                child: TextButton(
                    key: const ValueKey('progressive-folder-toggle'),
                    onPressed: () => change(() => expanded = !expanded),
                    child: const Text('Music'))),
            songBuilder: (context, _, audio, index, coverSize) {
              built.add(audio.path);
              return AudioTile(
                  key: ValueKey('progressive-song-${audio.path}'),
                  audioIndex: index,
                  playlist: songs,
                  multiSelectController: selection,
                  playbackService: playback,
                  presentationBuilder:
                      (context, _, activate, secondary, longPress, action) =>
                          PlaylistTreeItem(
                              title: audio.displayTitle,
                              coverSize: coverSize,
                              playlist: false,
                              onTap: activate,
                              onSecondaryTapDown: secondary,
                              onLongPress: longPress,
                              cover: AudioArtwork(
                                  audio: audio,
                                  size: coverSize,
                                  placeholder: const ColoredBox(
                                      color: Colors.teal))));
            });
      }));

  Future<void> mount(WidgetTester tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 720);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(built, isEmpty);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      scroll.dispose();
      hidden.dispose();
      selection.dispose();
      playback.dispose();
    });
  }

  Future<void> toggle(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('progressive-folder-toggle')));
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final qa = Directory(path.join(Directory.current.parent.path, 'tool',
      'qa-local', 'folder-oct13-progress', 'formal-fixture'));
  final data = Directory(path.join(qa.path, 'data'));
  final music = path.join(qa.path, 'Music');
  final songs = <Audio>[
    for (var index = 0; index < 698; index++)
      CategoryTestAudio('Track ${index.toString().padLeft(4, '0')}',
          path: path.join(music, '$index.mp3')),
  ];
  const provider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR'], isNull,
        reason: 'The path_provider fixture owns all application storage.');
    expect(Directory.systemTemp.absolute.path.replaceAll('\\', '/'),
        contains('/tool/qa-local/'));
    await data.create(recursive: true);
    messenger.setMockMethodCallHandler(provider, (_) async => data.path);
    expect(path.isWithin(data.path, (await getAppDataDir()).path), isTrue);
    await loadPlaylistFeatureFonts();
  });
  tearDownAll(() => messenger.setMockMethodCallHandler(provider, null));

  testWidgets('cold folder cards mount in small batches without moving slots',
      (tester) async {
    final fixture = _ProgressiveFolderFixture(music, songs);
    await fixture.mount(tester);
    await fixture.toggle(tester);
    final view = tester.widget<ListView>(find.byType(ListView));
    final allRows =
        (view.childrenDelegate as SliverChildBuilderDelegate).childCount;
    final extent = fixture.scroll.position.maxScrollExtent;
    final slot = find.byKey(ValueKey((fixture.tree.roots.single.id,
        songs.first.path)));
    final bounds = tester.getRect(slot);
    for (var frame = 0; frame < 3; frame++) {
      final before = fixture.built.length;
      await tester.pump();
      expect(fixture.built.length - before, inInclusiveRange(1, 4),
          reason: 'Count actual AudioTile/AudioArtwork construction per frame.');
      expect(tester.getRect(slot), bounds);
      expect(fixture.scroll.position.maxScrollExtent, closeTo(extent, .01));
      expect(
          (tester.widget<ListView>(find.byType(ListView)).childrenDelegate
                  as SliverChildBuilderDelegate)
              .childCount,
          allRows);
    }
    expect(fixture.built.length, lessThan(32));
    await tester.pumpAndSettle();
    expect(fixture.built.length, greaterThan(12));
    expect(fixture.built.length, lessThan(songs.length),
        reason: 'Progressive work must not eagerly visit all 698 songs.');
    await tester.tap(find.byKey(ValueKey('progressive-song-${songs.first.path}')));
    expect(fixture.playback.played, same(songs));
    expect(fixture.playback.playedIndex, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden folder pauses pending cards and resumes with small batches',
      (tester) async {
    final fixture = _ProgressiveFolderFixture(music, songs);
    await fixture.mount(tester);
    fixture.hidden.value = true;
    await fixture.toggle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.built, isEmpty);
    fixture.hidden.value = false;
    await tester.pump();
    await tester.pump();
    expect(fixture.built, hasLength(4));
    fixture.hidden.value = true;
    final hiddenCount = fixture.built.length;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.built.length, hiddenCount,
        reason: 'A post-frame reservation must not start hidden artwork.');
    fixture.hidden.value = false;
    for (var frame = 0; frame < 3; frame++) {
      final before = fixture.built.length;
      await tester.pump();
      expect(fixture.built.length - before, inInclusiveRange(0, 4));
    }
    expect(fixture.built.length, greaterThan(hiddenCount));
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapse cancels cold pending cards and warm reopen is immediate',
      (tester) async {
    final fixture = _ProgressiveFolderFixture(music, songs);
    await fixture.mount(tester);
    await fixture.toggle(tester);
    await tester.pump();
    expect(fixture.built, hasLength(4));
    await fixture.toggle(tester);
    final afterCollapse = fixture.built.length;
    await tester.pumpAndSettle();
    expect(fixture.built.length, afterCollapse);
    expect(find.byType(AudioArtwork, skipOffstage: false), findsNothing);
    await fixture.toggle(tester);
    await tester.pumpAndSettle();
    final warmCount = find.byType(AudioTile, skipOffstage: false).evaluate().length;
    await fixture.toggle(tester);
    await tester.pumpAndSettle();
    await fixture.toggle(tester);
    expect(find.byType(AudioTile, skipOffstage: false), findsNWidgets(warmCount));
    expect(fixture.built.last, songs[warmCount - 1].path);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detaching a cold folder cancels its pending construction',
      (tester) async {
    final fixture = _ProgressiveFolderFixture(music, songs);
    await fixture.mount(tester);
    await fixture.toggle(tester);
    await tester.pump();
    final before = fixture.built.length;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(fixture.built.length, before);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('progressive folder preserves complete playback and range sources',
      (tester) async {
    final previousFolders = AudioLibrary.instance.folders;
    final previousFolder = AppPreference.instance.foldersPagePref;
    final previousSong = AppPreference.instance.folderDetailPagePref;
    final previousLanguage = uiLanguage.value;
    final playback = _ProgressivePlayback();
    addTearDown(() {
      AudioLibrary.instance.folders = previousFolders;
      AppPreference.instance.foldersPagePref = previousFolder;
      AppPreference.instance.folderDetailPagePref = previousSong;
      uiLanguage.value = previousLanguage;
      playback.dispose();
    });
    uiLanguage.value = UiLanguage.zh;
    AppPreference.instance.foldersPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.table);
    AppPreference.instance.folderDetailPagePref =
        PagePreference(0, SortOrder.ascending, ContentView.table);
    AudioLibrary.instance.folders = [
      AudioFolder(songs.reversed.toList(), music, 1, 1)
    ];
    sizePlaylistFeature(tester, width: 1000, height: 850);
    await tester.pumpWidget(playlistFeatureHost(FoldersPage(
        dataDirectory: data,
        playbackService: playback,
        initialFolderPath: music,
        sortLargeFolder: (_, __, ___) => SynchronousFuture(songs),
        loadArtwork: (_, __) => SynchronousFuture<ImageProvider?>(null))));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    for (var frame = 0; frame < 12 && find.byType(AudioTile).evaluate().isEmpty;
        frame++) {
      await tester.pump();
    }
    expect(find.byType(AudioTile).evaluate().length, inInclusiveRange(1, 4));
    final first = find.byKey(ValueKey('folder-tree-cover-${songs.first.path}'));
    await tester.tap(first);
    expect(playback.played, same(songs));
    expect(playback.playedIndex, 0);
    await tester.longPress(first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, ui('多选')).hitTestable());
    await tester.pumpAndSettle();
    final actions = tester.widget<AudioMultiSelectionActions>(
        find.byType(AudioMultiSelectionActions));
    expect(actions.contentList, orderedEquals(songs));
    expect(actions.contentList.length, 698);
    expect(find.byType(AudioTile, skipOffstage: false).evaluate().length,
        lessThan(698));
    await tester.tap(find.byKey(const ValueKey('audio-selection-more')));
    await tester.pumpAndSettle();
    final range = find.byKey(const ValueKey('multi-selection-range-below'));
    await tester.ensureVisible(range);
    await tester.tap(range.hitTestable());
    await tester.pumpAndSettle();
    expect(actions.controller.selectedInOrder(actions.contentList),
        orderedEquals(songs));
    expect(AudioLibrary.instance.folders.single.audios,
        orderedEquals(songs.reversed));
    expect(tester.takeException(), isNull);
  });
}
