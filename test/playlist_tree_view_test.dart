import 'dart:async';
import 'dart:io';
import 'dart:ui' as raster;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_cover.dart';
import 'package:dan_player/component/playlist_tree_pane.dart';
import 'package:dan_player/component/playlist_tree_item.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/component/playlist_cover_transition.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart'
    show kSecondaryMouseButton, PointerScrollEvent;
import 'package:flutter_test/flutter_test.dart';
import 'support/playlist_actions.dart';
import 'support/music_category_fixtures.dart';

class Fixture {
  final tree = PlaylistTree([]);
  late final root = tree.createPlaylist('日常收藏 · Daily');
  late final child = tree.createPlaylist('通勤 · Commute', parent: root);
  late final empty = tree.createPlaylist('空歌单 · Empty', parent: root);
  final repeated = Audio.online(
      provider: 'qq',
      id: 'repeat',
      title: '晨光 Morning',
      artist: '演示歌手',
      album: '示例专辑',
      duration: 123);
  final tail = Audio.online(
      provider: 'qq',
      id: 'tail',
      title: '夜晚 Evening',
      artist: 'Artist',
      album: 'Album',
      duration: 245);
  final played = <({int index, List<Audio> queue})>[];
  int saves = 0;
  Fixture() {
    tree.addAudio(child, repeated);
    tree.addAudio(root, repeated);
    tree.addAudio(root, tail);
    empty;
  }
  Widget browser({Playlist? initialPlaylist}) => PlaylistBrowser(
      initialPlaylist: initialPlaylist,
      tree: tree,
      initialView: PlaylistViewMode.tree,
      persist: () async {
        saves++;
      },
      onPlay: (index, queue) =>
          played.add((index: index, queue: List.of(queue))),
      trackBuilder: (_, audio, play, actions) => ListTile(
          title: Text(audio.displayTitle),
          subtitle: Text('${audio.artist} · ${audio.album}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: play,
          trailing: actions));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
  });
  final boundary = GlobalKey();
  Widget app(Widget child, {bool narrow = false, bool motion = false}) =>
      RepaintBoundary(
          key: boundary,
          child: UiLanguageScope(
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: Entry(welcome: false).fromSchemeAndFontFamily(
                      colorScheme: ColorScheme.fromSeed(
                          seedColor: narrow
                              ? Colors.deepPurple
                              : const Color(0xff965341),
                          brightness:
                              narrow ? Brightness.dark : Brightness.light),
                      fontFamily: danEmbeddedFontFamily),
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          disableAnimations: !motion,
                          textScaler: TextScaler.linear(narrow ? 1.8 : 1)),
                      child: child!),
                  home: Scaffold(body: child))));
  void size(WidgetTester tester, {bool narrow = false}) {
    tester.view.physicalSize = Size(narrow ? 390 : 1120, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final output = Platform.environment['DAN_TREE_RENDER'];
    if (output == null) return;
    await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final data = await image.toByteData(format: raster.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  Finder treeTile(String title) => find.byWidgetPredicate(
      (widget) => widget is PlaylistTreeItem && widget.title == title);

  testWidgets(
      'expanded descendants enter together while the existing folder stays opaque',
      (tester) async {
    size(tester);
    var expanded = <String>{};
    final nodes = [
      const PlaylistTreeNode(
          id: 'root',
          parentId: null,
          depth: 0,
          branch: true,
          searchText: 'Root',
          value: 0),
      const PlaylistTreeNode(
          id: 'track',
          parentId: 'root',
          depth: 1,
          branch: false,
          searchText: 'Track',
          value: 1),
    ];
    await tester.pumpWidget(app(
        StatefulBuilder(
            builder: (context, update) => PlaylistTreePane<int>(
                  nodes: nodes,
                  expanded: expanded,
                  onExpandedChanged: (next) => update(() => expanded = next),
                  itemBuilder: (_, node, toggle) =>
                      ListTile(title: Text(node.searchText), onTap: toggle),
                )),
        motion: true));
    final rootSlide = tester.widget<SlideTransition>(find.descendant(
        of: find.byKey(const ValueKey('playlist-tree-entry-root')),
        matching: find.byType(SlideTransition)));
    expect(rootSlide.position.value.dy, greaterThan(0),
        reason: 'First-level covers rise on initial page entry');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-tree-toggle-root')));
    await tester.pump();
    double opacity(String id) => tester
        .widget<FadeTransition>(find.byKey(ValueKey('playlist-tree-entry-$id')))
        .opacity
        .value;
    expect(opacity('root'), 1);
    expect(opacity('track'), 0);
    final slide = tester.widget<SlideTransition>(find.descendant(
        of: find.byKey(const ValueKey('playlist-tree-entry-track')),
        matching: find.byType(SlideTransition)));
    expect(slide.position.value.dx, lessThan(0));
    expect(slide.position.value.dy, 0);
    expect(slide.child, isA<Focus>(),
        reason: 'A song tile enters once without adding a raster filter');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('playlist-tree-entry-track')),
            matching: find.byType(BackdropFilter)),
        findsNothing);
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacity('track'), inExclusiveRange(0, 1));
    expect(opacity('root'), 1);
    await capture(tester, 'expand-mid');
    await tester.pumpAndSettle();
    expect(opacity('track'), 1);
    await tester.tap(find.byKey(const ValueKey('playlist-tree-toggle-root')));
    await tester.pump();
    expect(opacity('track'), 1,
        reason: 'The song rail remains mounted while it retreats left');
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacity('track'), inExclusiveRange(0, 1));
    expect(slide.position.value.dx, lessThan(0));
    expect(opacity('root'), 1);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('playlist-tree-entry-track')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('playlist-tree-toggle-root')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacity('track'), inExclusiveRange(0, 1));
    addTearDown(
        tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pump();
    expect(opacity('track'), 1,
        reason: 'Reducing motion during entry must finish it immediately');
    await tester.pumpAndSettle();
    expect(opacity('track'), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('tree rows use only the group rise while other views keep entry',
      (tester) async {
    size(tester);
    final f = Fixture();
    await tester.pumpWidget(app(f.browser(), motion: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('playlist-tree-toggle-${f.root.id}')));
    await tester.pump();
    expect(find.byKey(ValueKey(('playlist-entry', f.child.id))), findsNothing);
    final entering = find.byKey(ValueKey('playlist-tree-entry-${f.child.id}'));
    expect(entering, findsOneWidget);
    final groupSlide = tester.widget<SlideTransition>(
        find.descendant(of: entering, matching: find.byType(SlideTransition)));
    expect(groupSlide.position.value.dy, lessThan(0));
    expect(groupSlide.position.value.dx, 0);
    final arrival = find.descendant(
        of: entering, matching: find.byType(PlaylistItemArrival));
    expect(arrival, findsOneWidget);
    final arrivalFade = tester.widget<FadeTransition>(find
        .descendant(of: arrival, matching: find.byType(FadeTransition))
        .first);
    expect(arrivalFade.opacity.value, 1,
        reason: 'Cover flights must not scale tree text during expansion');
    await capture(tester, 'browser-expand-start');
    await tester.pump(const Duration(milliseconds: 75));
    expect(groupSlide.position.value.dy, inExclusiveRange(-.10, 0));
    expect(arrivalFade.opacity.value, 1);
    await capture(tester, 'browser-expand-mid');
    await tester.pumpAndSettle();
    expect(groupSlide.position.value.dy, 0);
    await tester.tap(find.byKey(ValueKey('playlist-tree-toggle-${f.root.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(entering, findsOneWidget,
        reason: 'Child playlists stay mounted during downward exit');
    expect(groupSlide.position.value.dy, inExclusiveRange(-.10, 0));
    await tester.pumpAndSettle();
    expect(entering, findsNothing);
    await selectPlaylistView(tester, 'list');
    expect(find.byKey(ValueKey(('playlist-entry', f.root.id))), findsOneWidget);
  });

  testWidgets('rapid tree expansion reversals settle without stale rows',
      (tester) async {
    size(tester);
    var expanded = <String>{};
    final changes = <Set<String>>[];
    const nodes = [
      PlaylistTreeNode(
          id: 'root',
          parentId: null,
          depth: 0,
          branch: true,
          searchText: 'Root',
          value: 0),
      PlaylistTreeNode(
          id: 'child',
          parentId: 'root',
          depth: 1,
          branch: true,
          searchText: 'Child',
          value: 1),
      PlaylistTreeNode(
          id: 'track',
          parentId: 'root',
          depth: 1,
          branch: false,
          searchText: 'Track',
          value: 2),
    ];
    await tester.pumpWidget(app(
        StatefulBuilder(
            builder: (context, update) => PlaylistTreePane<int>(
                  nodes: nodes,
                  expanded: expanded,
                  onExpandedChanged: (next) {
                    changes.add({...next});
                    update(() => expanded = next);
                  },
                  itemBuilder: (_, node, toggle) =>
                      ListTile(title: Text(node.searchText), onTap: toggle),
                )),
        motion: true));
    await tester.pumpAndSettle();
    const toggle = ValueKey('playlist-tree-toggle-root');
    await tester.tap(find.byKey(toggle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byKey(toggle));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(expanded, isEmpty);
    expect(
        find.byKey(const ValueKey('playlist-tree-entry-child')), findsNothing);
    expect(
        find.byKey(const ValueKey('playlist-tree-entry-track')), findsNothing);
    expect(changes, [
      <String>{'root'},
      <String>{}
    ]);

    await tester.tap(find.byKey(toggle));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(toggle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byKey(toggle));
    await tester.pumpAndSettle();
    expect(expanded, {'root'});
    expect(
        changes,
        [
          <String>{'root'},
          <String>{},
          <String>{'root'}
        ],
        reason: 'Cancelling an exit must not persist a second expansion');
    for (final id in ['child', 'track']) {
      final entry = find.byKey(ValueKey('playlist-tree-entry-$id'));
      expect(entry, findsOneWidget);
      expect(tester.widget<FadeTransition>(entry).opacity.value, 1);
      expect(
          tester
              .widget<SlideTransition>(find.descendant(
                  of: entry, matching: find.byType(SlideTransition)))
              .position
              .value,
          Offset.zero);
    }
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('async expansion keeps both rapidly opened branches',
      (tester) async {
    size(tester);
    var expanded = <String>{};
    final firstCommit = Completer<void>();
    final changes = <Set<String>>[];
    const nodes = [
      PlaylistTreeNode(
          id: 'first',
          parentId: null,
          depth: 0,
          branch: true,
          searchText: 'First',
          value: 0),
      PlaylistTreeNode(
          id: 'second',
          parentId: null,
          depth: 0,
          branch: true,
          searchText: 'Second',
          value: 1),
      PlaylistTreeNode(
          id: 'one',
          parentId: 'first',
          depth: 1,
          branch: false,
          searchText: 'One',
          value: 2),
      PlaylistTreeNode(
          id: 'two',
          parentId: 'second',
          depth: 1,
          branch: false,
          searchText: 'Two',
          value: 3),
    ];
    await tester.pumpWidget(app(
        StatefulBuilder(
            builder: (context, update) => PlaylistTreePane<int>(
                  nodes: nodes,
                  expanded: expanded,
                  onExpandedChanged: (next) async {
                    changes.add({...next});
                    if (changes.length == 1) await firstCommit.future;
                    update(() => expanded = next);
                  },
                  itemBuilder: (_, node, toggle) =>
                      ListTile(title: Text(node.searchText), onTap: toggle),
                )),
        motion: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-tree-toggle-first')));
    await tester.pump();
    expect(changes, [
      <String>{'first'}
    ]);
    await tester.tap(find.byKey(const ValueKey('playlist-tree-toggle-second')));
    await tester.pump();
    firstCommit.complete();
    await tester.pumpAndSettle();
    expect(changes, [
      <String>{'first'},
      <String>{'first', 'second'}
    ]);
    expect(expanded, {'first', 'second'});
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
  });

  for (final policy in ['reduced', 'ticker-off']) {
    testWidgets('$policy finishes a pending tree collapse', (tester) async {
      size(tester);
      var expanded = <String>{'root'};
      var tickerEnabled = true;
      var commits = 0;
      late StateSetter update;
      const nodes = [
        PlaylistTreeNode(
            id: 'root',
            parentId: null,
            depth: 0,
            branch: true,
            searchText: 'Root',
            value: 0),
        PlaylistTreeNode(
            id: 'track',
            parentId: 'root',
            depth: 1,
            branch: false,
            searchText: 'Track',
            value: 1),
      ];
      addTearDown(tester
          .binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(app(StatefulBuilder(builder: (context, setter) {
        update = setter;
        return TickerMode(
            enabled: tickerEnabled,
            child: PlaylistTreePane<int>(
              nodes: nodes,
              expanded: expanded,
              onExpandedChanged: (next) {
                commits++;
                update(() => expanded = next);
              },
              itemBuilder: (_, node, toggle) =>
                  ListTile(title: Text(node.searchText), onTap: toggle),
            ));
      }), motion: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('playlist-tree-toggle-root')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Track'), findsOneWidget);
      if (policy == 'reduced') {
        tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
      } else {
        update(() => tickerEnabled = false);
      }
      await tester.pumpAndSettle();
      expect(expanded, isEmpty);
      expect(commits, 1);
      expect(find.text('Track'), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets('child cover and its song rail use independent directions',
      (tester) async {
    size(tester);
    var expanded = <String>{};
    const nodes = [
      PlaylistTreeNode(
          id: 'root',
          parentId: null,
          depth: 0,
          branch: true,
          searchText: 'Root',
          value: 0),
      PlaylistTreeNode(
          id: 'child',
          parentId: 'root',
          depth: 1,
          branch: true,
          searchText: 'Child',
          value: 1),
      PlaylistTreeNode(
          id: 'track',
          parentId: 'child',
          depth: 2,
          branch: false,
          searchText: 'Track',
          value: 2),
    ];
    await tester.pumpWidget(app(
        StatefulBuilder(
            builder: (context, update) => PlaylistTreePane<int>(
                  nodes: nodes,
                  expanded: expanded,
                  onExpandedChanged: (next) => update(() => expanded = next),
                  itemBuilder: (_, node, toggle) =>
                      ListTile(title: Text(node.searchText), onTap: toggle),
                )),
        motion: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-tree-expand-all')));
    await tester.pump();
    Offset slide(String id) => tester
        .widget<SlideTransition>(find.descendant(
            of: find.byKey(ValueKey('playlist-tree-entry-$id')),
            matching: find.byType(SlideTransition)))
        .position
        .value;
    expect(slide('child').dx, 0);
    expect(slide('child').dy, lessThan(0));
    expect(slide('track').dx, lessThan(0));
    expect(slide('track').dy, 0);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-tree-collapse-all')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(slide('child').dx, 0);
    expect(slide('child').dy, lessThan(0));
    expect(slide('track').dx, lessThan(0));
    expect(slide('track').dy, 0);
    await tester.pumpAndSettle();
    expect(find.text('Child'), findsNothing);
    expect(find.text('Track'), findsNothing);
  });

  testWidgets('reopening a parent keeps its descendants collapsed',
      (tester) async {
    size(tester);
    final f = Fixture();
    final grandchild = f.tree.createPlaylist('周末 · Weekend', parent: f.child);
    final childSong =
        f.child.entries.firstWhere((entry) => entry.audio != null);
    final rootSong = f.root.entries.firstWhere((entry) => entry.audio != null);
    await tester.pumpWidget(app(f.browser(), motion: true));
    await tester.pumpAndSettle();
    final rootToggle =
        find.byKey(ValueKey('playlist-tree-toggle-${f.root.id}'));
    final childToggle =
        find.byKey(ValueKey('playlist-tree-toggle-${f.child.id}'));
    final rootSongTile = find.byKey(ValueKey('playlist-open-${rootSong.id}'));
    final childSongTile = find.byKey(ValueKey('playlist-open-${childSong.id}'));

    await tester.tap(rootToggle);
    await tester.pumpAndSettle();
    expect(rootSongTile, findsOneWidget);
    expect(treeTile(f.child.name), findsOneWidget);
    expect(childSongTile, findsNothing);
    expect(treeTile(grandchild.name), findsNothing);
    await tester.tap(childToggle);
    await tester.pumpAndSettle();
    expect(childSongTile, findsOneWidget);
    expect(treeTile(grandchild.name), findsOneWidget);

    await tester.tap(rootToggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    Offset exitOffset(String id) => tester
        .widget<SlideTransition>(find.descendant(
            of: find.byKey(ValueKey('playlist-tree-entry-$id')),
            matching: find.byType(SlideTransition)))
        .position
        .value;
    expect(treeTile(f.child.name), findsOneWidget,
        reason: 'Expanded child remains mounted during parent exit');
    expect(treeTile(grandchild.name), findsOneWidget);
    expect(childSongTile, findsOneWidget);
    expect(exitOffset(f.child.id).dx, 0);
    expect(exitOffset(f.child.id).dy, lessThan(0));
    expect(exitOffset(grandchild.id).dx, 0);
    expect(exitOffset(grandchild.id).dy, lessThan(0));
    expect(exitOffset(childSong.id).dx, lessThan(0));
    expect(exitOffset(childSong.id).dy, 0);
    await tester.pumpAndSettle();
    expect(treeTile(f.child.name), findsNothing);
    await tester.tap(rootToggle);
    await tester.pumpAndSettle();
    expect(rootSongTile, findsOneWidget);
    expect(treeTile(f.child.name), findsOneWidget);
    expect(childSongTile, findsNothing);
    expect(treeTile(grandchild.name), findsNothing);

    await tester.tap(find.byKey(const ValueKey('playlist-tree-expand-all')));
    await tester.pumpAndSettle();
    expect(childSongTile, findsOneWidget);
    expect(treeTile(grandchild.name), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('playlist-tree-collapse-all')));
    await tester.pumpAndSettle();
    expect(treeTile(f.child.name), findsNothing);
  });

  testWidgets(
      'count action follows recycle bin and toggles wording and icon without checkmark',
      (tester) async {
    size(tester);
    var count = true;
    await tester.pumpWidget(app(StatefulBuilder(
        builder: (context, update) => PlaylistToolbar(
              isRoot: true,
              selecting: false,
              selectedCount: 0,
              hasItems: true,
              canPlay: true,
              onCreate: () {},
              onStartSelection: () {},
              onEndSelection: () {},
              onSelectAll: () {},
              onRemoveSelected: () {},
              onSortChanged: (_) {},
              onTrash: () {},
              countChildren: count,
              onToggleCountChildren: () => update(() => count = !count),
            ))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-current-settings')));
    await tester.pumpAndSettle();
    final item = find.byKey(const ValueKey('playlist-count-children'));
    expect(tester.getTopLeft(find.text('隐藏子歌单歌曲数量')).dy,
        greaterThan(tester.getTopLeft(find.text('歌单回收站')).dy));
    expect(find.descendant(of: item, matching: find.byIcon(Icons.check)),
        findsNothing);
    expect(
        find.descendant(
            of: item, matching: find.byIcon(Icons.visibility_off_outlined)),
        findsOneWidget);
    final labelRect = tester.getRect(find.text('隐藏子歌单歌曲数量'));
    final itemRect = tester.getRect(item);
    expect(itemRect.right - labelRect.right, inInclusiveRange(11, 14));
    await capture(tester, 'count-menu-under-trash');
    await tester.tap(item);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-current-settings')));
    await tester.pumpAndSettle();
    expect(find.text('显示子歌单歌曲数量'), findsOneWidget);
    expect(
        find.descendant(
            of: item, matching: find.byIcon(Icons.visibility_outlined)),
        findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'collapsed folders keep eight pixels between cards and leaf scope hides count action',
      (tester) async {
    size(tester);
    final f = Fixture();
    final second = f.tree.createPlaylist('Second root');
    await tester.pumpWidget(app(f.browser()));
    await tester.pumpAndSettle();
    final firstRect =
        tester.getRect(find.byKey(ValueKey('playlist-open-${f.root.id}')));
    final secondRect =
        tester.getRect(find.byKey(ValueKey('playlist-open-${second.id}')));
    expect(secondRect.top - firstRect.bottom, closeTo(8, .01));
    await capture(tester, 'collapsed-spacing');
    await tester.pumpWidget(app(f.browser(initialPlaylist: f.child)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-current-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('playlist-count-children')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('cover hierarchy and direct songs stay inside each parent band',
      (tester) async {
    size(tester);
    final f = Fixture();
    final grandchild = f.tree.createPlaylist('Grandchild', parent: f.child);
    final greatGrandchild =
        f.tree.createPlaylist('Great grandchild', parent: grandchild);
    final deeper = f.tree.createPlaylist('Deeper', parent: greatGrandchild);
    await tester.pumpWidget(app(f.browser()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-tree-expand-all')));
    await tester.pumpAndSettle();

    Finder tile(String id) => find.byKey(ValueKey('playlist-open-$id'));
    double cover(String id) =>
        tester.widget<PlaylistTreeItem>(tile(id)).coverSize;
    expect(cover(f.root.id), 112);
    expect(cover(f.child.id), 88);
    expect(cover(grandchild.id), 64);
    expect(cover(greatGrandchild.id), 48);
    expect(cover(deeper.id), 48);
    final directSong =
        f.root.entries.firstWhere((entry) => entry.audio == f.tail).id;
    final folder = tester.getRect(tile(f.root.id));
    final song = tester.getRect(tile(directSong));
    final scheme = Theme.of(tester.element(tile(f.root.id))).colorScheme;
    Material backing(String id) => tester.widget<Material>(
        find.descendant(of: tile(id), matching: find.byType(Material)).first);
    expect(backing(f.root.id).color,
        Color.lerp(scheme.surfaceContainerHigh, scheme.primaryContainer, .3));
    expect(backing(directSong).color, scheme.primaryContainer);
    expect(tester.getSize(tile(f.root.id)).width, 124);
    expect(
        tester
            .getSize(find.byKey(ValueKey('playlist-tree-toggle-${f.root.id}'))),
        const Size(40, 40));
    expect(
        tester.getSize(
            find.byKey(ValueKey('playlist-tree-toggle-frame-${f.root.id}'))),
        const Size(22, 24));
    expect(
        tester
            .getSize(find.descendant(
                of: tile(f.root.id), matching: find.byType(PlaylistCover)))
            .width,
        116);
    expect(song.left, greaterThan(folder.right));
    expect(song.top, greaterThanOrEqualTo(folder.top));
    expect(song.bottom, lessThanOrEqualTo(folder.bottom));
    expect(tester.getRect(tile(f.child.id)).top, greaterThan(folder.bottom));
    expect(find.text(f.root.name), findsNothing);
    expect(find.text(f.tail.displayTitle), findsNothing);
    final mouse =
        await tester.createGesture(kind: raster.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(tile(f.root.id)));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text(f.root.name), findsOneWidget);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('vertical wheel browses the bounded horizontal song rail',
      (tester) async {
    size(tester);
    final f = Fixture();
    for (var index = 0; index < 32; index++) {
      f.tree.addAudio(
          f.root,
          Audio.online(
              provider: 'qq',
              id: 'rail-$index',
              title: 'Rail $index',
              artist: 'Artist',
              album: 'Album',
              duration: 60));
    }
    final last = f.root.entries.last;
    await tester.pumpWidget(app(f.browser()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('playlist-tree-toggle-${f.root.id}')));
    await tester.pumpAndSettle();
    final rail = find.byKey(PageStorageKey('playlist-tree-songs-${f.root.id}'));
    final controller = tester.widget<ListView>(rail).controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));
    await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(rail), scrollDelta: const Offset(0, 240)));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final lastTile = find.byKey(ValueKey('playlist-open-${last.id}'));
    expect(lastTile, findsOneWidget);
    await tester.tap(lastTile);
    expect(f.played.last.queue.last, last.audio);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom drag reorders direct songs in the horizontal rail',
      (tester) async {
    size(tester);
    final f = Fixture();
    await tester.pumpWidget(app(f.browser(), motion: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('playlist-tree-toggle-${f.root.id}')));
    await tester.pumpAndSettle();
    final repeated =
        f.root.entries.firstWhere((entry) => entry.audio == f.repeated);
    final tail = f.root.entries.firstWhere((entry) => entry.audio == f.tail);
    final drag = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey('playlist-open-${repeated.id}'))),
        kind: raster.PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 270));
    await drag.moveBy(const Offset(16, 0));
    await tester.pump(const Duration(milliseconds: 180));
    final target = find.descendant(
      of: find.byKey(PageStorageKey('playlist-tree-songs-${f.root.id}')),
      matching: find.byKey(ValueKey('playlist-drop-slot-${f.root.id}-3')),
    );
    expect(target, findsOneWidget);
    await drag.moveTo(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 100));
    await drag.up();
    await tester.pumpAndSettle();
    final order = f.root.entries
        .where((entry) => entry.audio != null)
        .map((entry) => entry.id)
        .toList();
    expect(order, [tail.id, repeated.id]);
    expect(f.saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing direct songs retires their old horizontal rail',
      (tester) async {
    size(tester);
    const root = PlaylistTreeNode(
        id: 'root',
        parentId: null,
        depth: 0,
        branch: true,
        searchText: 'Root',
        value: 0);
    const song = PlaylistTreeNode(
        id: 'song',
        parentId: 'root',
        depth: 1,
        branch: false,
        searchText: 'Song',
        value: 1);
    var nodes = <PlaylistTreeNode<int>>[root, song];
    late StateSetter update;
    await tester.pumpWidget(app(StatefulBuilder(
      builder: (context, setState) {
        update = setState;
        return PlaylistTreePane<int>(
          nodes: nodes,
          expanded: const {'root'},
          onExpandedChanged: (_) {},
          itemBuilder: (_, node, __) => ListTile(title: Text(node.searchText)),
        );
      },
    )));
    await tester.pumpAndSettle();
    final rail = find.byKey(const PageStorageKey('playlist-tree-songs-root'));
    final oldController = tester.widget<ListView>(rail).controller!;
    update(() => nodes = [root]);
    await tester.pumpAndSettle();
    expect(rail, findsNothing);
    expect(oldController.hasClients, isFalse);
    update(() => nodes = [root, song]);
    await tester.pumpAndSettle();
    expect(
        tester.widget<ListView>(rail).controller, isNot(same(oldController)));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'count scope changes only numbers and persists per level and view',
      (tester) async {
    size(tester);
    final f = Fixture();
    await tester.pumpWidget(app(f.browser()));
    await tester.pumpAndSettle();
    expect(find.text('1 个顶层歌单 · 3 首歌曲引用\n总时长 8:11（含子歌单）'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('playlist-current-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('playlist-count-children')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await selectPlaylistView(tester, 'grid');
    expect(find.text('1 个顶层歌单 · 3 首歌曲引用\n总时长 8:11（含子歌单）'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('playlist-current-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('playlist-count-children')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await selectPlaylistView(tester, 'list');
    expect(find.text('1 个顶层歌单 · 3 首歌曲引用\n总时长 8:11（含子歌单）'), findsOneWidget);
    await tapPlaylistAction(tester, 'playlist-count-children');
    expect(find.text('1 个顶层歌单 · 2 首歌曲引用\n总时长 8:11（含子歌单）'), findsOneWidget);
    await selectPlaylistView(tester, 'tree');
    expect(find.text('1 个顶层歌单 · 3 首歌曲引用\n总时长 8:11（含子歌单）'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('playlist-tree-expand-all')));
    await tester.pumpAndSettle();
    expect(treeTile(f.repeated.displayTitle), findsNWidgets(2));
    await tester.tap(treeTile(f.repeated.displayTitle).first);
    expect(f.played.single.queue, [f.repeated, f.repeated, f.tail]);
    // Open the actual detail page through the existing list navigation.
    await selectPlaylistView(tester, 'list');
    await tester.tap(find.byKey(ValueKey('playlist-open-${f.root.id}')));
    await tester.pumpAndSettle();
    expect(find.text('4 个直接项目 · 3 首歌曲'), findsWidgets);
    await tapPlaylistAction(tester, 'playlist-count-children');
    expect(find.text('4 个直接项目 · 2 首歌曲'), findsWidgets);
    await selectPlaylistView(tester, 'tree');
    expect(find.text('4 个直接项目 · 3 首歌曲'), findsWidgets);
    await selectPlaylistView(tester, 'list');
    expect(find.text('4 个直接项目 · 2 首歌曲'), findsWidgets);
    f.tree.createPlaylist('Grandchild', parent: f.child);
    await tester.tap(find.byKey(ValueKey('playlist-open-${f.child.id}')));
    await tester.pumpAndSettle();
    await tapPlaylistAction(tester, 'playlist-count-children');
    final rootTiles =
        CategoryPresentation.fromMap(f.root.presentation['tiles']);
    final childTiles =
        CategoryPresentation.fromMap(f.child.presentation['tiles']);
    expect(rootTiles.countPlaylistChildren('list'), isFalse);
    expect(rootTiles.countPlaylistChildren('tree'), isTrue);
    expect(childTiles.countPlaylistChildren('list'), isFalse);
    await tapPlaylistAction(tester, 'playlist-count-children');
    expect(
        CategoryPresentation.fromMap(f.root.presentation['tiles'])
            .countPlaylistChildren('list'),
        isFalse);
    expect(
        CategoryPresentation.fromMap(f.child.presentation['tiles'])
            .countPlaylistChildren('list'),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy hidden counts cannot suppress tree or grid headers',
      (tester) async {
    size(tester);
    final f = Fixture();
    f.root.presentation['tiles'] = const CategoryPresentation(
      playlistCountChildren: {
        'tree': false,
        'grid': false,
        'list': false,
        'circular': false,
      },
    ).toMap();
    await tester.pumpWidget(app(f.browser(initialPlaylist: f.root)));
    await tester.pumpAndSettle();
    for (final view in ['tree', 'grid']) {
      await selectPlaylistView(tester, view);
      expect(find.text('4 个直接项目 · 3 首歌曲'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('playlist-current-settings')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('playlist-count-children')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
    for (final view in ['list', 'circular']) {
      await selectPlaylistView(tester, view);
      expect(find.text('4 个直接项目 · 2 首歌曲'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('playlist-current-settings')));
      await tester.pumpAndSettle();
      final item = find.byKey(const ValueKey('playlist-count-children'));
      expect(item, findsOneWidget);
      expect(find.text('显示子歌单歌曲数量'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('zero direct count retains nested playback and all four scopes',
      (tester) async {
    size(tester);
    final f = Fixture();
    // A folder containing only a subplaylist has zero direct tracks.
    final nestedOnly = f.tree.createPlaylist('Only nested');
    final nestedChild =
        f.tree.createPlaylist('Nested tracks', parent: nestedOnly);
    f.tree.addAudio(nestedChild, f.tail);
    await tester.pumpWidget(app(f.browser()));
    await tester.pumpAndSettle();
    for (final view in PlaylistViewMode.values) {
      await selectPlaylistView(tester, view.name);
      await tester.tap(find.byKey(const ValueKey('playlist-current-settings')));
      await tester.pumpAndSettle();
      final item = find.byKey(const ValueKey('playlist-count-children'));
      if (view == PlaylistViewMode.tree || view == PlaylistViewMode.grid) {
        expect(item, findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        continue;
      }
      expect(
          find.descendant(
              of: item, matching: find.byIcon(Icons.visibility_off_outlined)),
          findsOneWidget);
      await tester.tap(item);
      await tester.pumpAndSettle();
    }
    for (final view in PlaylistViewMode.values) {
      await selectPlaylistView(tester, view.name);
      await tester.tap(find.byKey(const ValueKey('playlist-current-settings')));
      await tester.pumpAndSettle();
      final item = find.byKey(const ValueKey('playlist-count-children'));
      if (view == PlaylistViewMode.tree || view == PlaylistViewMode.grid) {
        expect(item, findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        continue;
      }
      expect(
          find.descendant(
              of: item, matching: find.byIcon(Icons.visibility_outlined)),
          findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
    await selectPlaylistView(tester, 'list');
    expect(find.text('1 个直接项目 · 0 首歌曲'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('playlist-play-${nestedOnly.id}')));
    expect(f.played.last.queue, [f.tail]);
    await playVisiblePlaylistSelection(tester);
    expect(f.played.last.queue, [f.repeated, f.repeated, f.tail, f.tail]);
    expect(f.tree.roots, hasLength(2));
    expect(nestedOnly.entries.single.childPlaylist, nestedChild);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'expand/search/view switch preserve DFS queue and duplicate occurrence',
      (tester) async {
    size(tester);
    final f = Fixture();
    await tester.pumpWidget(app(f.browser()));
    await tester.pumpAndSettle();
    expect(treeTile('通勤 · Commute'), findsNothing);
    await tester.tap(find.byKey(ValueKey('playlist-open-${f.root.id}')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(ValueKey('playlist-tree-toggle-${f.child.id}')));
    await tester.pumpAndSettle();
    expect(treeTile(f.repeated.displayTitle), findsNWidgets(2));
    final directRepeat =
        f.root.entries.firstWhere((entry) => entry.audio == f.repeated).id;
    await tester.tap(find.byKey(ValueKey('playlist-open-$directRepeat')));
    await tester.pumpAndSettle();
    expect(f.played.single.index, 1);
    expect(f.played.single.queue, [f.repeated, f.repeated, f.tail]);
    await tester.enterText(
        find.byKey(const ValueKey('playlist-tree-search')), 'Evening');
    await tester.pumpAndSettle();
    expect(treeTile(f.tail.displayTitle), findsOneWidget);
    expect(treeTile(f.repeated.displayTitle), findsNothing);
    expect(treeTile('日常收藏 · Daily'), findsOneWidget);
    await tapPlaylistAction(tester, 'playlist-start-selection');
    await tapPlaylistAction(tester, 'playlist-select-all');
    await tapPlaylistAction(tester, 'playlist-play-selected');
    expect(f.played.last.queue, [f.tail]);
    await tapPlaylistAction(tester, 'playlist-end-selection');
    await tester.enterText(
        find.byKey(const ValueKey('playlist-tree-search')), '');
    await tester.pumpAndSettle();
    expect(treeTile(f.repeated.displayTitle), findsNWidgets(2));
    await selectPlaylistView(tester, 'list');
    await selectPlaylistView(tester, 'tree');
    expect(treeTile(f.repeated.displayTitle), findsNWidgets(2));
    expect(f.tree.roots.single, f.root);
    expect(f.played, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'selecting parent and descendants neither duplicates queue nor removes twice',
      (tester) async {
    size(tester);
    final f = Fixture();
    await tester.pumpWidget(app(f.browser()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-tree-expand-all')));
    await tester.pumpAndSettle();
    await tapPlaylistAction(tester, 'playlist-start-selection');
    await tapPlaylistAction(tester, 'playlist-select-all');
    await tapPlaylistAction(tester, 'playlist-play-selected');
    expect(f.played.single.queue, [f.repeated, f.repeated, f.tail]);
    await tapPlaylistAction(tester, 'playlist-remove-selected');
    await tester
        .tap(find.byKey(const ValueKey('playlist-confirm-remove-selected')));
    await tester.pumpAndSettle();
    expect(f.tree.roots, isEmpty);
    expect(f.saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'compact siblings share a row; whole-card drag and right-click retain actions',
      (tester) async {
    size(tester);
    final f = Fixture();
    await tester.pumpWidget(app(f.browser()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-tree-expand-all')));
    await tester.pumpAndSettle();
    final tailId = f.root.entries.firstWhere((e) => e.audio == f.tail).id;
    final repeatId = f.root.entries.firstWhere((e) => e.audio == f.repeated).id;
    final tail = find.byKey(ValueKey('playlist-open-$tailId'));
    final repeat = find.byKey(ValueKey('playlist-open-$repeatId'));
    expect(
        tester.getTopLeft(tail).dx, closeTo(tester.getTopLeft(repeat).dx, .1));
    expect(
        tester.getRect(tail).left,
        greaterThan(tester
            .getRect(find.byKey(ValueKey('playlist-open-${f.root.id}')))
            .right));
    expect(find.byKey(ValueKey('playlist-menu-$tailId')), findsNothing);
    expect(find.byKey(ValueKey('playlist-play-$tailId')), findsNothing);
    await tester.tap(tail,
        buttons: kSecondaryMouseButton, kind: raster.PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text(ui('移动到…')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final focus = tester
        .widget<Focus>(find.byKey(ValueKey('playlist-tree-focus-$tailId')))
        .focusNode!;
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(f.played.single.index, 2);
    Future<void> drag(String id, String destination) async {
      final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(ValueKey('playlist-open-$id'))),
          kind: raster.PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 270));
      await gesture.moveBy(const Offset(16, 0));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(
          find.byKey(ValueKey('playlist-drop-folder-$destination'))));
      await tester.pump(const Duration(milliseconds: 350));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await drag(tailId, f.child.id);
    expect(f.child.entries.any((e) => e.id == tailId), isTrue);
    expect(f.root.entries.any((e) => e.id == tailId), isFalse);
    expect(f.saves, 1);
    await drag(f.root.id, f.child.id);
    expect(f.root.parent, isNull);
    expect(f.child.parent, f.root);
    expect(f.saves, 1);
    expect(tester.takeException(), isNull);
  });

  for (final motion in [false, true]) {
    testWidgets(
        'tree drag gaps animate and restore after a no-op motion=$motion',
        (tester) async {
      size(tester);
      final f = Fixture();
      final second = f.tree.createPlaylist('Second root');
      await tester.pumpWidget(app(f.browser(), motion: motion));
      await tester.pumpAndSettle();
      final firstRow = find.byKey(ValueKey('playlist-open-${f.root.id}'));
      final secondRow = find.byKey(ValueKey('playlist-open-${second.id}'));
      double spacing() =>
          tester.getRect(secondRow).top - tester.getRect(firstRow).bottom;
      final restingSpace = spacing();

      final drag = await tester.startGesture(tester.getCenter(firstRow),
          kind: raster.PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 270));
      await drag.moveBy(const Offset(16, 0));
      await tester.pump();
      expect(find.byKey(const ValueKey('playlist-drop-slot-root-1')),
          findsOneWidget);
      if (motion) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(spacing(), greaterThan(restingSpace));
        expect(spacing(), lessThan(restingSpace + 10));
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(spacing(), closeTo(restingSpace + 10, .1));

      await drag.up();
      await tester.pump();
      expect(f.tree.roots, [f.root, second]);
      if (motion) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(spacing(), greaterThan(restingSpace));
        expect(spacing(), lessThan(restingSpace + 10));
      }
      await tester.pumpAndSettle();
      expect(spacing(), closeTo(restingSpace, .1));
      expect(find.byKey(const ValueKey('playlist-drop-slot-root-1')),
          findsNothing);
      expect(f.saves, 0);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tree custom gaps reset after same-slot drop, reorder and cancel',
      (tester) async {
    size(tester);
    final f = Fixture();
    final second = f.tree.createPlaylist('Second root');
    await tester.pumpWidget(app(f.browser(), motion: true));
    await tester.pumpAndSettle();
    final firstRow = find.byKey(ValueKey('playlist-open-${f.root.id}'));
    final secondRow = find.byKey(ValueKey('playlist-open-${second.id}'));
    double spacing() {
      final first = tester.getRect(firstRow);
      final next = tester.getRect(secondRow);
      return next.top > first.top
          ? next.top - first.bottom
          : first.top - next.bottom;
    }

    final restingSpace = spacing();
    TestGesture? activeDrag;
    Future<void> start() async {
      final gesture = await tester.startGesture(tester.getCenter(firstRow),
          kind: raster.PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 270));
      await gesture.moveBy(const Offset(16, 0));
      await tester.pump(const Duration(milliseconds: 150));
      expect(spacing(), closeTo(restingSpace + 10, .1));
      if (activeDrag != null) throw StateError('a drag is already active');
      activeDrag = gesture;
    }

    Future<void> drop(int slot) async {
      final target = find.byKey(ValueKey('playlist-drop-slot-root-$slot'));
      await activeDrag!.moveTo(tester.getCenter(target));
      await tester.pump();
      await activeDrag!.up();
      activeDrag = null;
      await tester.pumpAndSettle();
      expect(spacing(), closeTo(restingSpace, .1));
      expect(tester.binding.transientCallbackCount, 0);
    }

    await start();
    await drop(1);
    expect(f.tree.roots, [f.root, second]);
    expect(f.saves, 0);

    await start();
    await drop(2);
    expect(f.tree.roots, [second, f.root]);
    expect(f.saves, 1);

    await start();
    await activeDrag!.cancel();
    activeDrag = null;
    await tester.pumpAndSettle();
    expect(spacing(), closeTo(restingSpace, .1));
    expect(f.tree.roots, [second, f.root]);
    expect(f.saves, 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard branches, virtualized End, reveal and animation idle',
      (tester) async {
    size(tester);
    final nodes = [
      const PlaylistTreeNode(
          id: 'root',
          parentId: null,
          depth: 0,
          branch: true,
          searchText: 'Root',
          value: 0),
      for (var i = 1; i <= 180; i++)
        PlaylistTreeNode(
            id: '$i',
            parentId: 'root',
            depth: 1,
            branch: false,
            searchText: 'Song $i',
            value: i),
    ];
    var expanded = <String>{};
    await tester.pumpWidget(app(StatefulBuilder(
        builder: (context, update) => PlaylistTreePane<int>(
            nodes: nodes,
            expanded: expanded,
            revealId: () => '180',
            onExpandedChanged: (value) => update(() => expanded = value),
            itemBuilder: (_, node, toggle) =>
                ListTile(title: Text(node.searchText), onTap: toggle)))));
    await tester.pumpAndSettle();
    final rowFocus = find.byKey(const ValueKey('playlist-tree-focus-root'));
    tester.widget<Focus>(rowFocus).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(expanded, contains('root'));
    expect(find.text('Song 180'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('playlist-tree-reveal')));
    await tester.pumpAndSettle();
    expect(find.text('Song 180'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets('render tree ${language.code} narrow=$narrow',
          (tester) async {
        size(tester, narrow: narrow);
        final old = uiLanguage.value;
        uiLanguage.value = language;
        addTearDown(() => uiLanguage.value = old);
        final f = Fixture();
        await tester.pumpWidget(app(f.browser(), narrow: narrow));
        await tester.pumpAndSettle();
        await tester
            .tap(find.byKey(const ValueKey('playlist-tree-expand-all')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(treeTile(f.repeated.displayTitle), findsNWidgets(2));
        await capture(tester, '${language.code}-${narrow ? 'narrow' : 'wide'}');
        await tester
            .tap(find.byKey(const ValueKey('playlist-current-settings')));
        await tester.pumpAndSettle();
        expect(find.text(ui('隐藏子歌单歌曲数量')), findsNothing);
        await capture(
            tester, '${language.code}-menu-${narrow ? 'narrow' : 'wide'}');
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        final host = tester.widget<PlaylistCoverTransitionHost>(
            find.byType(PlaylistCoverTransitionHost));
        expect(host.controller.debugSnapshotCount, 0);
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }

  for (final narrow in [false, true]) {
    testWidgets('real song rows with tree cover motion narrow=$narrow',
        (tester) async {
      size(tester, narrow: narrow);
      final tree = PlaylistTree([]);
      final root = tree.createPlaylist('我的音乐');
      final child = tree.createPlaylist('通勤');
      tree.addAudio(root,
          CategoryTestAudio('清晨的风', artist: '演示歌手', album: '远方', online: true));
      tree.addAudio(child, CategoryTestAudio('旅途', online: true));
      await tester.pumpWidget(app(
          PlaylistBrowser(
              tree: tree,
              initialView: PlaylistViewMode.tree,
              persist: () async {},
              onPlay: (_, __) {}),
          narrow: narrow,
          motion: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('playlist-tree-toggle-${root.id}')));
      // Cover capture uses the real render layer before the shared flight begins.
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 16)));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      expect(treeTile('清晨的风'), findsOneWidget);
      await capture(tester, 'real-${narrow ? 'narrow' : 'wide'}');
      await selectPlaylistView(tester, 'circular');
      await selectPlaylistView(tester, 'tree');
      expect(treeTile('清晨的风'), findsOneWidget);
      final host = tester.widget<PlaylistCoverTransitionHost>(
          find.byType(PlaylistCoverTransitionHost));
      expect(host.controller.debugSnapshotCount, 0);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
