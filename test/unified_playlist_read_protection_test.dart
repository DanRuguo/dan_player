import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_destination_dialog.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;
  late File primary;

  setUp(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final parent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    root = await parent.createTemp('unified-read-protection-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    final data = await getAppDataDir();
    expect(path.isWithin(root.path, data.path), isTrue);
    primary = File(path.join(data.path, 'playlists.json'));
    await readPlaylists();
    playlistTree.createPlaylist('Retained playlist');
    await primary.writeAsString('{invalid fixture');
    await readPlaylists();
    expect(playlistsReadBlocked, isTrue);
    playlistUiSaveError.value = null;
    playlistUiSaving.value = false;
  });

  tearDown(() async {
    await primary.writeAsString('[]');
    await readPlaylists();
    expect(playlistsReadBlocked, isFalse);
    PLAYLISTS.clear();
    playlistUiSaveError.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final resolved = await root.resolveSymbolicLinks();
    final parent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .resolveSymbolicLinks();
    if (!path.isWithin(parent, resolved) ||
        !path.basename(resolved).startsWith('unified-read-protection-')) {
      throw StateError('Refusing to remove an unverified test fixture');
    }
    await Directory(resolved).delete(recursive: true);
    expect(PlayService.isInitialized, isFalse);
  });

  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'read failure disables canonical create and rename before mutation',
      (tester) async {
    final id = PLAYLISTS.single.id;
    await show(tester, const PlaylistBrowser());
    expect(
        tester
            .widget<FilledButton>(find.descendant(
                of: find.byKey(const ValueKey('playlist-create')),
                matching: find.byType(FilledButton)))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(ValueKey('playlist-menu-$id')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<MenuItemButton>(find.widgetWithText(MenuItemButton, '重命名'))
            .onPressed,
        isNull);
    expect(PLAYLISTS.single.id, id);
    expect(playlistsHaveUnsavedChanges, isFalse);
    expect(await tester.runAsync(() => primary.readAsString()),
        '{invalid fixture');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a prior save error cannot hide reload and repaired data enables editing',
      (tester) async {
    playlistUiSaveError.value = 'Earlier rejected write';
    await show(tester, const PlaylistBrowser());
    expect(
        find.byKey(const ValueKey('playlist-retry-storage')), findsOneWidget);
    expect(find.byKey(const ValueKey('playlist-retry-save')), findsNothing);
    await tester.runAsync(() async {
      await primary.writeAsString(jsonEncode({
        'version': 3,
        'playlists': PLAYLISTS.map((playlist) => playlist.toMap()).toList(),
        'legacyCollectionsMigrated': true,
        'migratedCollectionKeys': [],
      }));
      await tester.tap(find.byKey(const ValueKey('playlist-retry-storage')));
      await readPlaylists(); // Joins the button's in-flight read, no timing sleeps.
    });
    await tester.pumpAndSettle();
    expect(playlistsReadBlocked, isFalse);
    expect(playlistUiSaveError.value, isNull);
    expect(find.byKey(const ValueKey('playlist-retry-storage')), findsNothing);
    expect(
        tester
            .widget<FilledButton>(find.descendant(
                of: find.byKey(const ValueKey('playlist-create')),
                matching: find.byType(FilledButton)))
            .onPressed,
        isNotNull);
    expect(PLAYLISTS.single.name, 'Retained playlist');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'external add-to-playlist action respects the same read protection',
      (tester) async {
    final before = PLAYLISTS.single.toMap();
    await show(
        tester,
        Builder(
            builder: (context) => TextButton(
                  onPressed: () => showAddAudiosToPlaylistDialog(context, [
                    Audio.online(
                        provider: 'qq',
                        id: 'new',
                        title: 'New',
                        artist: 'Artist',
                        album: 'Album',
                        duration: 60),
                  ]),
                  child: const Text('Add'),
                )));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.byType(PlaylistDestinationDialog), findsNothing);
    expect(find.textContaining('歌单数据尚未完整读取'), findsOneWidget);
    expect(PLAYLISTS.single.toMap(), before);
    expect(playlistsHaveUnsavedChanges, isFalse);
    expect(tester.takeException(), isNull);
  });
}
