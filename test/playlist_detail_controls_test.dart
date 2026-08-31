import 'package:dan_player/component/playlist_header.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in UiLanguage.values) {
    testWidgets('detail icon-only controls stay in one row in $language',
        (tester) async {
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = UiLanguage.zh);
      tester.view.physicalSize = const Size(1250, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final changes = <PlaylistViewMode>[];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PlaylistHeader(
        compact: true,
        title: 'Long playlist name 音楽 모음',
        subtitle: '12 songs',
        coverBuilder: (_) => const ColoredBox(color: Colors.blue),
        breadcrumbs: const Text('All playlists > Detail'),
        actions: PlaylistToolbar(
          isRoot: false,
          hasItems: true,
          canPlay: true,
          onCreate: () {},
          onAddSongs: () {},
          onPlayAll: () {},
          onStartSelection: () {},
          onEndSelection: () {},
          onSelectAll: () {},
          onRemoveSelected: () {},
          onSortChanged: (_) {},
          view: PlaylistViewMode.list,
          onViewChanged: changes.add,
        ),
      ))));
      await tester.pumpAndSettle();
      final view = find.byKey(const ValueKey('playlist-view-selector'));
      expect(
          find.descendant(of: view, matching: find.byType(Text)), findsNothing);
      final playRect =
          tester.getRect(find.byKey(const ValueKey('playlist-play-all')));
      expect(tester.getRect(view).center.dy, closeTo(playRect.center.dy, .1));
      expect(tester.getRect(view).height, closeTo(playRect.height, .1));
      await tester.tap(find.byTooltip(ui('圆形封面')));
      expect(changes, [PlaylistViewMode.circular]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('root retains text labels for all three views', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PlaylistToolbar(
      isRoot: true,
      hasItems: true,
      canPlay: true,
      onCreate: () {},
      onPlayAll: () {},
      onStartSelection: () {},
      onEndSelection: () {},
      onSelectAll: () {},
      onRemoveSelected: () {},
      onSortChanged: (_) {},
      view: PlaylistViewMode.list,
      onViewChanged: (_) {},
    ))));
    expect(find.text('列表'), findsOneWidget);
    expect(find.text('方形网格'), findsOneWidget);
    expect(find.text('圆形封面'), findsOneWidget);
  });
}
