import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_action_icon.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_circle_tile.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory fixtureRoot;
  late File source;
  late Playlist parent;
  late Playlist child;
  late List<Playlist> previousRoots;

  setUp(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final workspace =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    fixtureRoot = await workspace.createTemp('circle-readonly-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => fixtureRoot.path);
    final data = await getAppDataDir();
    expect(path.isWithin(fixtureRoot.path, data.path), isTrue);
    source = File(path.join(data.path, 'playlists.json'));
    previousRoots = PLAYLISTS;
    PLAYLISTS = [];
    final tree = playlistTree;
    parent = tree.createPlaylist('Read-only parent');
    child = tree.createPlaylist('Child', parent: parent);
    tree.addAudio(child, CategoryTestAudio('Keep original song'));
    await source.writeAsString('{ corrupt fixture; never overwrite');
    await readPlaylists();
    expect(playlistsReadBlocked, isTrue);
    expect(PLAYLISTS.single, same(parent));
  });

  tearDown(() async {
    // Clear only our validated fixture, then reset read-error state while
    // path-provider still points here, never to the user's actual storage.
    final resolved = await fixtureRoot.resolveSymbolicLinks();
    final workspace =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .resolveSymbolicLinks();
    if (!path.isWithin(workspace, resolved) ||
        !path.basename(resolved).startsWith('circle-readonly-')) {
      throw StateError('Refusing to remove an unverified read-only fixture');
    }
    await source.delete();
    await readPlaylists();
    PLAYLISTS = previousRoots;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await Directory(resolved).delete(recursive: true);
  });

  testWidgets(
      'read-only circle preserves browsing/playback but blocks mutation and dragging',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final opened = <Playlist?>[];
    var played = 0;
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: PlaylistBrowser(
        initialPlaylist: parent,
        initialView: PlaylistViewMode.circular,
        persist: () async => saves++,
        onPlay: (_, __) => played++,
        onNavigate: opened.add,
        trackBuilder: (_, audio, play, action) => Text(audio.displayTitle),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PlaylistCircleTile), findsOneWidget);
    expect(
        tester
            .widget<PlaylistToolbar>(find.byType(PlaylistToolbar))
            .editingEnabled,
        isFalse);
    final drag = tester.widget<Draggable<PlaylistDragData>>(
        find.byKey(ValueKey('playlist-drag-${child.id}')));
    expect(drag.maxSimultaneousDrags, 0);
    await tester.tap(find.byKey(ValueKey('playlist-play-${child.id}')));
    expect(played, 1);
    expect(
        tester
            .widget<AppIconActionButton>(
                find.byKey(ValueKey('playlist-play-${child.id}')))
            .onPressed,
        isNotNull);
    await tester.tap(find.byKey(ValueKey('playlist-circle-open-${child.id}')));
    expect(opened.single, same(child));
    await tester.tap(find.byKey(ValueKey('playlist-menu-${child.id}')));
    await tester.pumpAndSettle();
    for (final label in ['重命名', '移动到…', '删除歌单…']) {
      final item = find
          .ancestor(
              of: find.text(ui(label)), matching: find.byType(MenuItemButton))
          .first;
      expect(tester.widget<MenuItemButton>(item).onPressed, isNull,
          reason: label);
    }
    expect(saves, 0);
    expect(parent.entries.single.childPlaylist, same(child));
    final bytes = await tester.runAsync(source.readAsString);
    expect(bytes, '{ corrupt fixture; never overwrite');
    expect(tester.takeException(), isNull);
  });
}
