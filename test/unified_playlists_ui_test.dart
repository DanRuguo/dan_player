import 'dart:io';
import 'dart:ui';

import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_cover.dart';
import 'package:dan_player/component/playlist_create_dialog.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/playlist_actions.dart';

Audio _audio(String id, {String artist = 'Artist', String album = 'Album'}) =>
    Audio.online(
        provider: 'qq',
        id: id,
        title: id,
        artist: artist,
        album: album,
        duration: 60);

class _Fixture {
  final roots = <Playlist>[];
  late final tree = PlaylistTree(roots);
  int saves = 0;
  final played = <({int index, List<Audio> queue})>[];
  final views = <ContentView>[];

  PlaylistBrowser browser({
    Playlist? current,
    List<Audio> library = const [],
    PlaylistImagePicker? pickImage,
    ContentView view = ContentView.list,
    VoidCallback? onOpenAlbums,
  }) =>
      PlaylistBrowser(
        tree: tree,
        initialPlaylist: current,
        library: library,
        persist: () async => saves++,
        pickImage: pickImage,
        initialContentView: view,
        onContentViewChanged: views.add,
        onOpenAlbums: onOpenAlbums,
        albumCount: 388,
        onPlay: (index, queue) => played.add((index: index, queue: queue)),
        trackBuilder: (_, audio, onPlay, actions) => ListTile(
          title: Text(audio.displayTitle,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: onPlay,
          trailing: actions,
        ),
      );
}

Future<void> _show(WidgetTester tester, Widget browser,
    {double width = 1280, double height = 1000, double textScale = 1}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(platform: TargetPlatform.windows, useMaterial3: true),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
          disableAnimations: true, textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(body: browser),
  ));
  await tester.pumpAndSettle();
}

Future<void> _settings(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('playlist-current-settings')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    playlistUiSaveError.value = null;
    playlistUiSaving.value = false;
  });

  tearDown(() => expect(PlayService.isInitialized, isFalse,
      reason: 'Presentation tests must never initialize BASS'));

  testWidgets('create combines name cover and selected songs in one save',
      (tester) async {
    final fixture = _Fixture();
    final first = _audio('First');
    final second = _audio('Second');
    final image = File('assets/images/RCE_logo_transparent.png').absolute.path;
    await _show(tester,
        fixture.browser(library: [first, second], pickImage: () => image));
    await tapPlaylistAction(tester, 'playlist-create');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('playlist-name-input')),
        '  Unified collection  ');
    await tester.tap(find.byKey(const ValueKey('playlist-create-cover')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-create-songs')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('playlist-pick-${second.path}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存选择（1 首）'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-confirm-create')));
    await tester.pumpAndSettle();
    expect(fixture.roots.single.name, 'Unified collection');
    expect(fixture.roots.single.imagePath, image);
    expect(fixture.roots.single.flattenAudios(), [second]);
    expect(fixture.saves, 1);
    expect(find.byType(PlaylistCover), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling the create dialog never adds a partial playlist',
      (tester) async {
    final fixture = _Fixture();
    await _show(tester, fixture.browser());
    await tapPlaylistAction(tester, 'playlist-create');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-confirm-create')));
    await tester.pumpAndSettle();
    expect(find.text('请输入歌单名称'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(fixture.roots, isEmpty);
    expect(fixture.saves, 0);
  });

  testWidgets(
      'editing selection preserves missing references child slots and IDs',
      (tester) async {
    final fixture = _Fixture();
    final parent = fixture.tree.createPlaylist('Migrated');
    final missing = _audio('Unavailable in current library');
    final keep = fixture.tree.addAudio(parent, missing);
    final child = fixture.tree.createPlaylist('Child', parent: parent);
    final removed = _audio('Unselect');
    fixture.tree.addAudio(parent, removed);
    final added = _audio('New');
    await _show(
        tester, fixture.browser(current: parent, library: [removed, added]));
    await _settings(tester, '更改所选歌曲');
    expect(find.text('总乐库暂未收录，保留歌曲引用'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('playlist-pick-${removed.path}')));
    await tester.tap(find.byKey(ValueKey('playlist-pick-${added.path}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存选择（2 首）'));
    await tester.pumpAndSettle();
    expect(
        parent.entries.take(2).map((entry) => entry.id), [keep.id, child.id]);
    expect(parent.flattenAudios(), [missing, added]);
    expect(identical(child.parent, parent), isTrue);
    expect(fixture.saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'editing selection can clear songs without deleting child playlists',
      (tester) async {
    final fixture = _Fixture();
    final parent = fixture.tree.createPlaylist('Root');
    final song = _audio('Direct');
    fixture.tree.addAudio(parent, song);
    final child = fixture.tree.createPlaylist('Child', parent: parent);
    fixture.tree.addAudio(child, _audio('Nested'));
    await _show(tester, fixture.browser(current: parent, library: [song]));
    await _settings(tester, '更改所选歌曲');
    await tester.tap(find.byKey(ValueKey('playlist-pick-${song.path}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存选择（0 首）'));
    await tester.pumpAndSettle();
    expect(parent.entries.single.childPlaylist, same(child));
    expect(parent.flattenAudios().single.title, 'Nested');
    expect(fixture.saves, 1);
  });

  testWidgets('cover changes and reset never alter song order or cover files',
      (tester) async {
    final fixture = _Fixture();
    final parent = fixture.tree.createPlaylist('Cover');
    fixture.tree.addAudio(parent, _audio('Keep'));
    final ids = parent.entries.map((entry) => entry.id).toList();
    final image = File('assets/images/RCE_logo_transparent.png').absolute.path;
    await _show(
        tester, fixture.browser(current: parent, pickImage: () => image));
    await _settings(tester, '更改歌单封面');
    expect(parent.imagePath, image);
    expect(parent.entries.map((entry) => entry.id), ids);
    await _settings(tester, '恢复默认封面');
    expect(parent.imagePath, isNull);
    expect(parent.entries.map((entry) => entry.id), ids);
    expect(fixture.saves, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'missing cover on an empty playlist preserves its path and uses the default image',
      (tester) async {
    final fixture = _Fixture();
    final empty = fixture.tree.createPlaylist('Empty',
        imagePath:
            File('build/missing-empty-playlist-cover.png').absolute.path);
    await _show(tester, fixture.browser(current: empty));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();

    expect(empty.imagePath,
        File('build/missing-empty-playlist-cover.png').absolute.path);
    expect(fixture.saves, 0);
    expect(
        find.descendant(
          of: find.byKey(const ValueKey('playlist-header-cover')),
          matching: find.byIcon(Icons.queue_music),
        ),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('album shortcut and layout toggle are views not playlist entries',
      (tester) async {
    final fixture = _Fixture();
    final parent = fixture.tree.createPlaylist('Root');
    fixture.tree.createPlaylist('Child', parent: parent);
    var albumsOpened = 0;
    await _show(tester, fixture.browser(onOpenAlbums: () => albumsOpened++));
    expect(find.text('浏览全部专辑 · 388'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('playlist-current-settings')));
    await tester.pumpAndSettle();
    expect(find.text('浏览全部专辑 · 388'), findsOneWidget);
    await tapPlaylistAction(tester, 'playlist-open-albums');
    await selectPlaylistView(tester, 'grid');
    expect(albumsOpened, 1);
    expect(fixture.views, [ContentView.table]);
    expect(find.byType(GridView), findsOneWidget);
    expect(fixture.roots, [parent]);
    expect(fixture.saves, 0);
    await selectPlaylistView(tester, 'list');
    expect(find.byType(GridView), findsNothing);
    expect(fixture.views, [ContentView.table, ContentView.list]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'grid artwork or title drag retains hierarchy and depth-first playback',
      (tester) async {
    final fixture = _Fixture();
    final parent = fixture.tree.createPlaylist('Root');
    final first = fixture.tree.addAudio(parent, _audio('First'));
    final child = fixture.tree.createPlaylist('Child', parent: parent);
    fixture.tree.addAudio(child, _audio('Nested'));
    fixture.tree.addAudio(parent, _audio('Last'));
    await _show(
        tester, fixture.browser(current: parent, view: ContentView.table));
    final drag = await tester.startGesture(
        tester
            .getCenter(find.byKey(ValueKey('playlist-card-drag-${first.id}'))),
        kind: PointerDeviceKind.mouse);
    await drag.moveBy(const Offset(12, 0));
    await tester.pump();
    await drag.moveTo(tester
        .getCenter(find.byKey(ValueKey('playlist-drop-folder-${child.id}'))));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    expect(parent.entries.first.childPlaylist, same(child));
    expect(child.entries.last.id, first.id);
    await tapPlaylistAction(tester, 'playlist-play-all');
    expect(fixture.played.single.queue.map((song) => song.title),
        ['Nested', 'First', 'Last']);
    expect(fixture.saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('song-count view preserves custom root order and child hierarchy',
      (tester) async {
    final fixture = _Fixture();
    final fewer = fixture.tree.createPlaylist('Same name');
    final more = fixture.tree.createPlaylist('Same name');
    final child = fixture.tree.createPlaylist('Child', parent: more);
    fixture.tree.addAudio(child, _audio('One'));
    fixture.tree.addAudio(child, _audio('Two'));
    fixture.tree.addAudio(fewer, _audio('Three'));
    await _show(tester, fixture.browser());
    await tester.tap(find.byKey(const ValueKey('playlist-sort')));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('playlist-sort-songCount')));
    await tester.tap(find.byKey(const ValueKey('playlist-sort-songCount')));
    await tester.pumpAndSettle();
    expect(fixture.roots, [fewer, more]);
    expect(
      tester.getTopLeft(find.byKey(ValueKey('playlist-open-${more.id}'))).dy,
      lessThan(tester
          .getTopLeft(find.byKey(ValueKey('playlist-open-${fewer.id}')))
          .dy),
    );
    expect(more.entries.single.childPlaylist, same(child));
    expect(fixture.saves, 0);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'unified grid toolbar and dialogs fit 440px at text scale $scale',
        (tester) async {
      final fixture = _Fixture();
      final parent =
          fixture.tree.createPlaylist('A long migrated playlist name');
      fixture.tree.createPlaylist('A long child playlist name', parent: parent);
      await _show(
          tester, fixture.browser(view: ContentView.table, onOpenAlbums: () {}),
          width: 440, height: 1100, textScale: scale);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(ValueKey('playlist-open-${parent.id}')));
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistCover), findsWidgets);
      expect(tester.takeException(), isNull);
      await tapPlaylistAction(tester, 'playlist-create');
      await tester.pumpAndSettle();
      expect(find.byType(PlaylistCreateDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'selecting the second duplicate with real AudioTile removes only that occurrence',
      (tester) async {
    final fixture = _Fixture();
    final shared = _audio('Repeated');
    AudioLibrary.instance.replaceOnlineAudios([shared]);
    addTearDown(() => AudioLibrary.instance.replaceOnlineAudios([]));
    final parent = Playlist.fromMap({
      'version': 3,
      'id': 'duplicate-parent',
      'name': 'Migrated repeated selection',
      'entries': [
        for (final id in ['first-occurrence', 'second-occurrence'])
          {
            'type': 'audio',
            'id': id,
            'audio': {
              'kind': 'online',
              'path': shared.path,
              ...shared.toOnlineMap()
            }
          },
      ],
    });
    fixture.roots.add(parent);
    expect(parent.entries[0].audio, same(parent.entries[1].audio));
    await _show(
        tester,
        PlaylistBrowser(
            tree: fixture.tree,
            initialPlaylist: parent,
            library: [shared],
            persist: () async => fixture.saves++));
    expect(find.byType(AudioTile), findsNWidgets(2));
    await tapPlaylistAction(tester, 'playlist-start-selection');
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('playlist-audio-second-occurrence')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Checkbox>(
                find.byKey(const ValueKey('playlist-select-first-occurrence')))
            .value,
        isFalse);
    expect(
        tester
            .widget<Checkbox>(
                find.byKey(const ValueKey('playlist-select-second-occurrence')))
            .value,
        isTrue);
    expect(find.text('移除所选（1）'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('playlist-remove-selected')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('playlist-confirm-remove-selected')));
    await tester.pumpAndSettle();
    expect(parent.entries.single.id, 'first-occurrence');
    expect(parent.entries.single.audio, same(shared));
    expect(fixture.saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'grid focus follows a playlist through two consecutive keyboard moves',
      (tester) async {
    final fixture = _Fixture();
    final first = fixture.tree.createPlaylist('First');
    final second = fixture.tree.createPlaylist('Second');
    final third = fixture.tree.createPlaylist('Third');
    await _show(tester, fixture.browser(view: ContentView.table));
    FocusNode rowFocus() => Focus.of(
        tester.element(find.byKey(ValueKey('playlist-drag-${first.id}'))));
    rowFocus().requestFocus();
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(rowFocus().hasFocus, isTrue);
    }
    expect(fixture.roots, [second, third, first]);
    expect(fixture.saves, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unified name sorting retains the library Chinese pinyin convention',
      (tester) async {
    final fixture = _Fixture();
    final zhang = fixture.tree.createPlaylist('张');
    final li = fixture.tree.createPlaylist('李');
    await _show(tester, fixture.browser());
    await tester.tap(find.byKey(const ValueKey('playlist-sort')));
    await tester.pumpAndSettle();
    final nameSort = find.byKey(const ValueKey('playlist-sort-nameAscending'));
    await tester.ensureVisible(nameSort);
    await tester.tap(nameSort);
    await tester.pumpAndSettle();
    expect(fixture.roots, [zhang, li]);
    expect(
      tester.getTopLeft(find.byKey(ValueKey('playlist-open-${li.id}'))).dy,
      lessThan(tester
          .getTopLeft(find.byKey(ValueKey('playlist-open-${zhang.id}')))
          .dy),
    );
    expect(fixture.saves, 0);
  });

  testWidgets(
      'legacy collection route highlights the single playlist destination',
      (tester) async {
    final previousStart = AppPreference.instance.startPage;
    addTearDown(() => AppPreference.instance.startPage = previousStart);
    final router =
        GoRouter(initialLocation: app_paths.COLLECTIONS_PAGE, routes: [
      GoRoute(
          path: app_paths.COLLECTIONS_PAGE,
          builder: (_, __) => const Scaffold(body: SideNav())),
      for (final destination in destinations)
        GoRoute(
            path: destination.desPath,
            builder: (_, __) => const Scaffold(body: SideNav())),
    ]);
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('合集'), findsNothing);
    expect(find.text('歌单'), findsOneWidget);
    expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        destinations
            .indexWhere((item) => item.desPath == app_paths.PLAYLISTS_PAGE));
    expect(tester.takeException(), isNull);
  });
}
