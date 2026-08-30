import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_reorder_surface.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

ScrollController _warningController(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(_key('playlist-warning-scroll'))
    .controller!;

Future<void> _waitForUiWrite(Future<void> Function() action) async {
  final settled = Completer<void>();
  void changed() {
    if (!playlistUiSaving.value && !settled.isCompleted) settled.complete();
  }

  playlistUiSaving.addListener(changed);
  try {
    await action();
    if (playlistUiSaving.value) await settled.future;
  } finally {
    playlistUiSaving.removeListener(changed);
  }
}

bool _hasFocusWithin(WidgetTester tester, Finder target) {
  final targetElement = tester.element(target);
  final focusContext = FocusManager.instance.primaryFocus?.context;
  if (focusContext == null) return false;
  if (identical(focusContext, targetElement)) return true;
  var found = false;
  focusContext.visitAncestorElements((element) {
    found = identical(element, targetElement);
    return !found;
  });
  return found;
}

void _expectBoundedWarning(WidgetTester tester) {
  final body = tester.getRect(_key('playlist-browser-body'));
  final warning = tester.getRect(_key('playlist-warning-viewport'));
  final list = tester.getRect(find.byType(PlaylistReorderSurface));
  expect(warning.height, inInclusiveRange(44, body.height * .4 + .01));
  expect(list.height, greaterThanOrEqualTo(body.height * .6 - .01));
  expect(list.height, greaterThan(64));
  expect(warning.bottom, closeTo(list.top, .01));
  expect(_warningController(tester).position.maxScrollExtent, greaterThan(0));
  expect(find.byType(AudioTile), findsWidgets);
  expect(tester.takeException(), isNull);
}

Future<void> _scrollToRetry(WidgetTester tester, String buttonKey) async {
  final list = find.byType(PlaylistReorderSurface);
  final listScrollable =
      find.descendant(of: list, matching: find.byType(Scrollable));
  final listPosition = tester.state<ScrollableState>(listScrollable).position;
  final oldListOffset = listPosition.pixels;
  await tester.drag(_key('playlist-warning-scroll'), const Offset(0, -300));
  await tester.pumpAndSettle();
  final warning = tester.getRect(_key('playlist-warning-viewport'));
  final retry = tester.getRect(_key(buttonKey));
  expect(retry.center.dy, inInclusiveRange(warning.top, warning.bottom));
  expect(_key(buttonKey).hitTestable(), findsOneWidget);
  expect(listPosition.pixels, oldListOffset,
      reason: 'Reading a warning must not move the song list');
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory testRoot;
  late File primary;
  late File backup;
  late Directory blockedTemporary;
  late Playlist parent;
  late Playlist child;
  late String savedJson;

  setUp(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty,
        reason: 'A data-directory override must never bypass the fixture');
    final fixtureParent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    testRoot = await fixtureParent.createTemp('playlist-warning-layout-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => testRoot.path);
    final data = await getAppDataDir();
    expect(path.isWithin(testRoot.path, data.path), isTrue);
    primary = File(path.join(data.path, 'playlists.json'));
    backup = File('${primary.path}.bak');
    blockedTemporary = Directory('${primary.path}.tmp');

    await readPlaylists();
    expect(PLAYLISTS, isEmpty);
    playlistUiSaveError.value = null;
    playlistUiSaving.value = false;
    final songs = [
      for (var i = 0; i < 10; i++)
        CategoryTestAudio('歌曲 $i',
            online: true, path: 'online://qq/${Uri.encodeComponent('歌曲 $i')}'),
    ];
    AudioLibrary.instance.replaceOnlineAudios(songs);
    final tree = playlistTree;
    parent = tree.createPlaylist('很长的歌单名称 · 原声与交响乐 · 已保留的歌曲');
    tree.addAudios(parent, songs);
    child = tree.createPlaylist('保留的子歌单', parent: parent, index: 2);
    tree.addAudio(child, songs.first);
    await savePlaylists();
    savedJson = await primary.readAsString();
    expect(playlistsHaveUnsavedChanges, isFalse);
    expect(PlayService.isInitialized, isFalse);
  });

  tearDown(() async {
    // Unblock and settle only this test's canonical store before removing it.
    // Do not leave a failed snapshot/read guard alive for the next fixture.
    if (await blockedTemporary.exists()) {
      expect(path.isWithin(testRoot.path, blockedTemporary.path), isTrue);
      await blockedTemporary.delete();
    }
    if (playlistsHaveUnsavedChanges) await savePlaylists();
    await primary.writeAsString('[]');
    await readPlaylists();
    expect(playlistsReadBlocked, isFalse);
    expect(playlistsHaveUnsavedChanges, isFalse);
    PLAYLISTS.clear();
    AudioLibrary.instance.replaceOnlineAudios([]);
    playlistUiSaveError.value = null;
    playlistUiSaving.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final resolved = await testRoot.resolveSymbolicLinks();
    final fixtureParent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .resolveSymbolicLinks();
    if (!path.isWithin(fixtureParent, resolved) ||
        !path.basename(resolved).startsWith('playlist-warning-layout-')) {
      throw StateError('Refusing to delete an unverified test directory');
    }
    await Directory(resolved).delete(recursive: true);
    expect(PlayService.isInitialized, isFalse);
  });

  Future<void> show(WidgetTester tester,
      {Brightness brightness = Brightness.light, double textScale = 2}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 480);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        platform: TargetPlatform.windows,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo, brightness: brightness),
      ),
      builder: (context, content) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child: content!,
      ),
      home: Scaffold(body: PlaylistBrowser(initialPlaylist: parent)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> failUiWrite(WidgetTester tester) async {
    final first = parent.entries.first;
    final audioRow = _key('playlist-audio-${first.id}');
    await tester.ensureVisible(audioRow);
    await tester.pumpAndSettle();
    Focus.of(tester.element(audioRow)).requestFocus();
    await tester.pump();
    await tester.runAsync(() async {
      await blockedTemporary.create();
      // Use the real Browser's keyboard move and default savePlaylists path.
      // A directory at the temporary-file path creates a real, portable I/O
      // failure without changing permissions or touching a user's files.
      await _waitForUiWrite(() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      });
    });
    await tester.pumpAndSettle();
    expect(parent.entries[1].id, first.id);
    expect(parent.entries[2].childPlaylist, same(child));
    expect(playlistsHaveUnsavedChanges, isTrue);
    expect(playlistUiSaveError.value, contains('playlists.json.tmp'));
    expect(await tester.runAsync(() => primary.readAsString()), savedJson);
    ScaffoldMessenger.of(tester.element(find.byType(PlaylistBrowser)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets(
        'short 200% ${brightness.name} write failure keeps songs and retry reachable',
        (tester) async {
      await show(tester, brightness: brightness);
      final surfaceState = tester.state(find.byType(PlaylistReorderSurface));
      await failUiWrite(tester);
      final retained = parent.toMap();
      final retainedIds =
          parent.flattenEntries().map((entry) => entry.entryId).toList();
      _expectBoundedWarning(tester);
      expect(tester.state(find.byType(PlaylistReorderSurface)),
          same(surfaceState));
      await _scrollToRetry(tester, 'playlist-retry-save');
      await tester.runAsync(() async {
        await blockedTemporary.delete();
        await _waitForUiWrite(() => tester.tap(_key('playlist-retry-save')));
      });
      await tester.pumpAndSettle();
      expect(playlistUiSaveError.value, isNull);
      expect(playlistsHaveUnsavedChanges, isFalse);
      expect(_key('playlist-retry-save'), findsNothing);
      expect(tester.getSize(_key('playlist-warning-viewport')).height, 0);
      expect(tester.state(find.byType(PlaylistReorderSurface)),
          same(surfaceState));
      final decoded = await tester.runAsync(() async =>
          decodePlaylists(jsonDecode(await primary.readAsString())).single);
      expect(decoded!.toMap(), retained);
      expect(
          parent.flattenEntries().map((entry) => entry.entryId), retainedIds);
      expect(parent.entries[2].childPlaylist!.id, child.id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'short 200% ${brightness.name} read failure is scrollable without replacing the tree',
        (tester) async {
      final retained = parent.toMap();
      await tester.runAsync(() async {
        await primary.writeAsString('{ invalid primary fixture');
        await backup.writeAsString('{ invalid backup fixture');
        await readPlaylists();
      });
      expect(playlistsReadBlocked, isTrue);
      expect(PLAYLISTS.single, same(parent));
      await show(tester, brightness: brightness);
      _expectBoundedWarning(tester);
      expect(_key('playlist-retry-save'), findsNothing);
      await _scrollToRetry(tester, 'playlist-retry-storage');
      final warning = tester.getRect(_key('playlist-warning-viewport'));
      final surface = find.byType(PlaylistReorderSurface);
      final scrollable =
          find.descendant(of: surface, matching: find.byType(Scrollable));
      final position = tester.state<ScrollableState>(scrollable).position;
      final initialOffset = position.pixels;
      await tester.drag(surface, const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(initialOffset));
      expect(tester.getRect(_key('playlist-warning-viewport')), warning);
      expect(PLAYLISTS.single.toMap(), retained);
      expect(await tester.runAsync(() => primary.readAsString()),
          '{ invalid primary fixture');
      await tester.runAsync(() async {
        await primary.writeAsString(savedJson);
        await tester.tap(_key('playlist-retry-storage'));
        await readPlaylists(); // Join the real button's in-flight read.
      });
      await tester.pumpAndSettle();
      expect(playlistsReadBlocked, isFalse);
      expect(_key('playlist-retry-storage'), findsNothing);
      expect(tester.getSize(_key('playlist-warning-viewport')).height, 0);
      expect(PLAYLISTS.single.toMap(), retained);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'keyboard traversal reveals the retry button inside the warning viewport',
      (tester) async {
    await show(tester);
    await failUiWrite(tester);
    _expectBoundedWarning(tester);
    _warningController(tester).jumpTo(0);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final retry = _key('playlist-retry-save');
    for (var tab = 0; tab < 30 && !_hasFocusWithin(tester, retry); tab++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(_hasFocusWithin(tester, retry), isTrue);
    final warning = tester.getRect(_key('playlist-warning-viewport'));
    expect(tester.getCenter(retry).dy,
        inInclusiveRange(warning.top, warning.bottom));
    await tester.runAsync(() async {
      await blockedTemporary.delete();
      await _waitForUiWrite(
          () => tester.sendKeyEvent(LogicalKeyboardKey.enter));
    });
    await tester.pumpAndSettle();
    expect(playlistUiSaveError.value, isNull);
    expect(playlistsHaveUnsavedChanges, isFalse);
    expect(tester.getSize(_key('playlist-warning-viewport')).height, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('no warning at text scale $scale reserves no list space',
        (tester) async {
      await show(tester, textScale: scale);
      final body = tester.getRect(_key('playlist-browser-body'));
      final list = tester.getRect(find.byType(PlaylistReorderSurface));
      expect(tester.getSize(_key('playlist-warning-viewport')).height, 0);
      expect(list.height, body.height);
      expect(list.top, body.top);
      expect(parent.flattenAudios(), hasLength(11));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
