import 'dart:io';

import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/component/playlist_cover_transition.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture {
  final tree = PlaylistTree([]);
  late final first = tree.createPlaylist('First');
  late final second = tree.createPlaylist('Second');
  late Playlist current = first;
  late StateSetter change;
  int saves = 0;

  Widget build() => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) {
              change = setState;
              return PlaylistBrowser(
                tree: tree,
                initialPlaylist: current,
                initialView: PlaylistViewMode.list,
                persist: () async => saves++,
                onPlay: (_, __) {},
                library: const [],
                trackBuilder: (_, audio, play, actions) => ListTile(
                  title: Text(audio.title),
                  onTap: play,
                  trailing: actions,
                ),
              );
            },
          ),
        ),
      );
}

PlaylistToolbar _toolbar(WidgetTester tester) =>
    tester.widget<PlaylistToolbar>(find.byType(PlaylistToolbar));

Future<void> _open(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory data;
  setUpAll(() async {
    data = await Directory.systemTemp.createTemp('playlist-menu-owner-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => data.path,
    );
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await data.delete(recursive: true);
  });

  testWidgets(
    'retained detail popup cannot dispatch reset to a new playlist',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = _Fixture();
      fixture.tree.createPlaylist('First child', parent: fixture.first);
      fixture.tree.createPlaylist('Second child', parent: fixture.second);
      fixture.first.imagePath = '${data.path}/first-no-cover.png';
      fixture.second.imagePath = '${data.path}/second-no-cover.png';
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      final toolbarState = tester.state(find.byType(PlaylistToolbar));
      await _open(tester, 'playlist-current-settings');
      final item = find.ancestor(
        of: find.text(ui('恢复默认封面')),
        matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
      );
      expect(item, findsOneWidget);
      fixture.change(() => fixture.current = fixture.second);
      await tester.pump();
      expect(
        tester.state(find.byType(PlaylistToolbar)),
        isNot(same(toolbarState)),
        reason: 'The actual detail header key retires the First toolbar State',
      );
      // The popup route is the opening First menu; its Second owner has rebuilt.
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(
        fixture.saves,
        0,
        reason: 'A retired detail menu must not edit its replacement owner',
      );
      expect(fixture.first.imagePath, '${data.path}/first-no-cover.png');
      expect(fixture.second.imagePath, '${data.path}/second-no-cover.png');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final input in ['mouse', 'touch', 'keyboard']) {
    testWidgets(
        'compact $input view click cannot overwrite a newer root layout input',
        (tester) async {
      tester.view.physicalSize = const Size(360, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tree = PlaylistTree([])..createPlaylist('Root cover');
      var view = PlaylistViewMode.list;
      late StateSetter change;
      final emitted = <PlaylistViewMode>[];
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
          home: Scaffold(body: StatefulBuilder(builder: (_, setState) {
            change = setState;
            return PlaylistBrowser(
              tree: tree,
              initialView: view,
              persist: () async {},
              onViewChanged: emitted.add,
              onPlay: (_, __) {},
              library: const [],
            );
          }))));
      await tester.pumpAndSettle();
      final toolbarState = tester.state(find.byType(PlaylistToolbar));
      expect(_toolbar(tester).view, PlaylistViewMode.list);
      await tester.tap(find.byKey(const ValueKey('playlist-view-selector')));
      await tester.pumpAndSettle();
      final circular = find.byKey(const ValueKey('playlist-view-circular'));
      expect(tester.widget(circular), isA<MenuItemButton>(),
          reason:
              'This exercises the narrow native menu, not a direct callback');
      if (input == 'keyboard') {
        final button =
            find.descendant(of: circular, matching: find.byType(TextButton));
        tester.widget<TextButton>(button).focusNode!.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        await tester.tap(circular,
            kind: input == 'touch'
                ? PointerDeviceKind.touch
                : PointerDeviceKind.mouse);
      }
      expect(emitted, isEmpty,
          reason:
              'Native MenuItemButton defers its action until after the frame');
      change(() => view = PlaylistViewMode.grid);
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 90)));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(PlaylistToolbar)), same(toolbarState),
          reason:
              'The root input rebuild retains the same actual toolbar State');
      expect(_toolbar(tester).view, PlaylistViewMode.grid,
          reason: 'The newer parent layout input owns this update');
      expect(emitted, isEmpty,
          reason:
              'An older menu click must not persist over the new page input');
      final controller = tester
          .widget<PlaylistCoverTransitionHost>(
              find.byType(PlaylistCoverTransitionHost))
          .controller;
      expect(controller.busy, isFalse);
      expect(controller.debugSnapshotCount, 0);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'a new compact view choice still commits and accepts its parent echo',
      (tester) async {
    tester.view.physicalSize = const Size(360, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tree = PlaylistTree([])..createPlaylist('Root cover');
    var view = PlaylistViewMode.list;
    final emitted = <PlaylistViewMode>[];
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!),
      home: Scaffold(
          body: StatefulBuilder(
              builder: (_, setState) => PlaylistBrowser(
                    tree: tree,
                    initialView: view,
                    persist: () async {},
                    onViewChanged: (value) => setState(() {
                      emitted.add(value);
                      view = value;
                    }),
                    onPlay: (_, __) {},
                    library: const [],
                  ))),
    ));
    await tester.pumpAndSettle();
    for (final mode in [
      PlaylistViewMode.circular,
      PlaylistViewMode.tree,
      PlaylistViewMode.list
    ]) {
      await tester.tap(find.byKey(const ValueKey('playlist-view-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('playlist-view-${mode.name}')));
      await tester.pumpAndSettle();
      expect(_toolbar(tester).view, mode);
      expect(view, mode);
    }
    expect(emitted, [
      PlaylistViewMode.circular,
      PlaylistViewMode.tree,
      PlaylistViewMode.list
    ]);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
