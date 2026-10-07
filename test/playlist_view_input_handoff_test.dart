import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_cover_transition.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/page/playlist_detail_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

PlaylistToolbar _toolbar(WidgetTester tester) =>
    tester.widget<PlaylistToolbar>(find.byType(PlaylistToolbar));

void main() {
  late Directory data;
  setUpAll(() async {
    data = await Directory.systemTemp.createTemp('playlist-view-input-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => data.path);
  });
  tearDownAll(() async {
    await AppPreference.instance.save();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await data.delete(recursive: true);
  });

  testWidgets('new root layout input retires a pending toolbar capture',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tree = PlaylistTree([])..createPlaylist('Root cover');
    var view = PlaylistViewMode.list;
    var requestDuringRebuild = false;
    late StateSetter change;
    late PlaylistCoverTransitionController controller;
    final emitted = <PlaylistViewMode>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (_, setState) {
      change = setState;
      if (requestDuringRebuild) {
        requestDuringRebuild = false;
        // Start the real toolbar callback in this frame, before the owner
        // delivers its newer input. No private capture or paint hook is used.
        _toolbar(tester).onViewChanged!(PlaylistViewMode.circular);
        expect(controller.busy, isTrue);
        expect(controller.debugCaptureCount, 1);
        expect(controller.active, isFalse);
      }
      return PlaylistBrowser(
          tree: tree,
          initialView: view,
          persist: () async {},
          onViewChanged: emitted.add);
    }))));
    await tester.pumpAndSettle();
    controller = tester
        .widget<PlaylistCoverTransitionHost>(
            find.byType(PlaylistCoverTransitionHost))
        .controller;
    change(() {
      requestDuringRebuild = true;
      view = PlaylistViewMode.grid;
    });
    await tester.pump();
    final visibleView = _toolbar(tester).view;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 90)));
    await tester.pumpAndSettle();
    expect(visibleView, PlaylistViewMode.grid,
        reason: 'the newer page input replaces the old requested highlight');
    expect(_toolbar(tester).view, PlaylistViewMode.grid);
    expect(find.byType(GridView), findsOneWidget);
    expect(emitted, isEmpty,
        reason: 'a retired capture must not persist its older layout');
    expect(controller.busy, isFalse);
    expect(controller.debugSnapshotCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final replacePlaylist in [false, true]) {
    testWidgets(
        'detail default follows new page input replacePlaylist=$replacePlaylist',
        (tester) async {
      final tree = PlaylistTree([]);
      final first = tree.createPlaylist('First');
      final second = tree.createPlaylist('Second');
      tree.createPlaylist('First child', parent: first);
      tree.createPlaylist('Second child', parent: second);
      var current = first;
      var view = PlaylistViewMode.list;
      late StateSetter change;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: StatefulBuilder(builder: (_, setState) {
        change = setState;
        return PlaylistBrowser(
            tree: tree,
            initialPlaylist: current,
            initialView: view,
            persist: () async {});
      }))));
      await tester.pumpAndSettle();
      expect(_toolbar(tester).view, PlaylistViewMode.list);
      change(() {
        view = PlaylistViewMode.grid;
        if (replacePlaylist) current = second;
      });
      await tester.pumpAndSettle();
      expect(_toolbar(tester).view, PlaylistViewMode.grid);
      expect(find.byType(GridView), findsOneWidget);
      expect(current.presentation.containsKey('view'), isFalse,
          reason: 'a default input does not become a playlist-specific choice');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('new detail default preserves an explicit playlist layout',
      (tester) async {
    final tree = PlaylistTree([]);
    final parent = tree.createPlaylist('Chosen layout');
    tree.createPlaylist('Child', parent: parent);
    parent.presentation['view'] = PlaylistViewMode.circular.name;
    var view = PlaylistViewMode.list;
    late StateSetter change;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (_, setState) {
      change = setState;
      return PlaylistBrowser(
          tree: tree,
          initialPlaylist: parent,
          initialView: view,
          persist: () async {});
    }))));
    await tester.pumpAndSettle();
    change(() => view = PlaylistViewMode.grid);
    await tester.pumpAndSettle();
    expect(_toolbar(tester).view, PlaylistViewMode.circular);
    expect(parent.presentation['view'], PlaylistViewMode.circular.name);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('parent echo of a committed toolbar choice keeps its flight',
      (tester) async {
    final tree = PlaylistTree([])..createPlaylist('Echoed root');
    var view = PlaylistViewMode.list;
    late StateSetter change;
    final emitted = <PlaylistViewMode>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (_, setState) {
      change = setState;
      return PlaylistBrowser(
          tree: tree,
          initialView: view,
          persist: () async {},
          onViewChanged: (next) {
            emitted.add(next);
            change(() => view = next);
          });
    }))));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<PlaylistCoverTransitionHost>(
            find.byType(PlaylistCoverTransitionHost))
        .controller;
    await tester.tap(find.byKey(const ValueKey('playlist-view-circular')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(emitted, [PlaylistViewMode.circular]);
    expect(_toolbar(tester).view, PlaylistViewMode.circular);
    expect(controller.active, isTrue,
        reason: 'the owner echo is not a newer conflicting layout request');
    await tester.pumpAndSettle();
    expect(controller.busy, isFalse);
    expect(controller.debugSnapshotCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a default update keeps a pending explicit playlist choice',
      (tester) async {
    final tree = PlaylistTree([]);
    final parent = tree.createPlaylist('Explicit layout');
    tree.createPlaylist('Child', parent: parent);
    parent.presentation['view'] = PlaylistViewMode.list.name;
    var view = PlaylistViewMode.list;
    var requestDuringRebuild = false;
    late StateSetter change;
    late PlaylistCoverTransitionController controller;
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (_, setState) {
      change = setState;
      if (requestDuringRebuild) {
        requestDuringRebuild = false;
        _toolbar(tester).onViewChanged!(PlaylistViewMode.circular);
        expect(controller.busy, isTrue);
        expect(controller.active, isFalse);
      }
      return PlaylistBrowser(
          tree: tree,
          initialPlaylist: parent,
          initialView: view,
          persist: () async => saves++);
    }))));
    await tester.pumpAndSettle();
    controller = tester
        .widget<PlaylistCoverTransitionHost>(
            find.byType(PlaylistCoverTransitionHost))
        .controller;
    change(() {
      requestDuringRebuild = true;
      view = PlaylistViewMode.grid;
    });
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 90)));
    await tester.pumpAndSettle();
    expect(_toolbar(tester).view, PlaylistViewMode.circular);
    expect(parent.presentation['view'], PlaylistViewMode.circular.name);
    expect(saves, 1);
    expect(controller.busy, isFalse);
    expect(controller.debugSnapshotCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'actual detail page refreshes its default while reusing the browser',
      (tester) async {
    final oldDefault = AppPreference.instance.unifiedPlaylistDetailsLayout;
    final oldRoots = PLAYLISTS;
    addTearDown(() {
      AppPreference.instance.unifiedPlaylistDetailsLayout = oldDefault;
      PLAYLISTS = oldRoots;
    });
    final tree = PlaylistTree([]);
    final first = tree.createPlaylist('First routed detail');
    final second = tree.createPlaylist('Second routed detail');
    tree.createPlaylist('First child', parent: first);
    tree.createPlaylist('Second child', parent: second);
    PLAYLISTS = tree.roots;
    AppPreference.instance.unifiedPlaylistDetailsLayout = PlaylistViewMode.list;
    var current = first;
    late StateSetter change;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (_, setState) {
      change = setState;
      return PlaylistDetailPage(playlist: current);
    }))));
    await tester.pumpAndSettle();
    final browser = tester.state(find.byType(PlaylistBrowser));
    expect(_toolbar(tester).view, PlaylistViewMode.list);
    AppPreference.instance.unifiedPlaylistDetailsLayout = PlaylistViewMode.grid;
    change(() => current = second);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(PlaylistBrowser)), same(browser));
    expect(_toolbar(tester).view, PlaylistViewMode.grid);
    expect(find.byType(GridView), findsOneWidget);
    expect(first.presentation.containsKey('view'), isFalse);
    expect(second.presentation.containsKey('view'), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('legacy detail layout input refreshes without a saved override',
      (tester) async {
    final tree = PlaylistTree([]);
    final parent = tree.createPlaylist('Legacy default');
    tree.createPlaylist('Child', parent: parent);
    var legacy = ContentView.list;
    late StateSetter change;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (_, setState) {
      change = setState;
      return PlaylistBrowser(
          tree: tree,
          initialPlaylist: parent,
          initialContentView: legacy,
          persist: () async {});
    }))));
    await tester.pumpAndSettle();
    change(() => legacy = ContentView.table);
    await tester.pumpAndSettle();
    expect(_toolbar(tester).view, PlaylistViewMode.grid);
    expect(find.byType(GridView), findsOneWidget);
    expect(parent.presentation.containsKey('view'), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
