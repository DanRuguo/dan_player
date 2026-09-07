import 'dart:async';
import 'dart:ui';

import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_destination_dialog.dart';
import 'package:dan_player/component/playlist_name_dialog.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_actions.dart';

Audio _song(String id) => Audio.online(
      provider: 'qq',
      id: id,
      title: id,
      artist: 'Artist',
      album: 'Album',
      duration: 60,
    );

class _Fixture {
  final roots = <Playlist>[];
  late final tree = PlaylistTree(roots);
  late final root = tree.createPlaylist('Root');
  late final child = tree.createPlaylist('Child', parent: root);
  int saves = 0;
  final played = <({int index, List<Audio> queue})>[];

  Future<void> save() async => saves++;

  Widget browser(
          {Playlist? current,
          bool atRoot = false,
          Future<void> Function()? persist,
          List<Audio>? library,
          ContentView contentView = ContentView.list}) =>
      PlaylistBrowser(
        tree: tree,
        initialPlaylist: atRoot ? null : current ?? root,
        persist: persist ?? save,
        initialContentView: contentView,
        library: library,
        onPlay: (index, queue) => played.add((index: index, queue: queue)),
        trackBuilder: (context, audio, play, actions) => ListTile(
          key: ValueKey('song-${audio.path}'),
          title: Text(audio.displayTitle),
          onTap: play,
          trailing: actions,
        ),
      );
}

Widget _app(Widget child, {double textScale = 1}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

void _size(WidgetTester tester, {double width = 1100, double height = 950}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openMenu(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('playlist-menu-$id')));
  await tester.pumpAndSettle();
}

Future<void> _tapPageAction(WidgetTester tester, String key) async {
  await tapPlaylistAction(tester, key);
}

Future<TestGesture> _dragTo(
    WidgetTester tester, String id, Finder target) async {
  final handle = find.byKey(ValueKey('playlist-drag-$id'));
  final pointer = await tester.startGesture(tester.getCenter(handle),
      kind: PointerDeviceKind.mouse);
  await pointer.moveBy(const Offset(12, 0));
  await tester.pump();
  await pointer.moveTo(tester.getCenter(target));
  await tester.pump();
  return pointer;
}

void main() {
  setUp(() {
    playlistUiSaveError.value = null;
    playlistUiSaving.value = false;
  });

  testWidgets(
      'mixed order playback uses DFS occurrence, not visible row or path',
      (tester) async {
    _size(tester);
    final fixture = _Fixture();
    final repeated = _song('Repeated');
    fixture.tree.addAudio(fixture.child, repeated);
    fixture.tree.addAudio(fixture.child, _song('Child second'));
    fixture.tree.addAudio(fixture.root, repeated);
    fixture.tree.addAudio(fixture.root, _song('Tail'));
    await tester.pumpWidget(_app(fixture.browser()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('song-${repeated.path}')));
    expect(fixture.played.single.index, 2);
    expect(fixture.played.single.queue.map((audio) => audio.title),
        ['Repeated', 'Child second', 'Repeated', 'Tail']);
    await tester.tap(find.byKey(ValueKey('playlist-play-${fixture.child.id}')));
    expect(fixture.played.last.index, 0);
    expect(fixture.played.last.queue.length, 2);
    await playVisiblePlaylistSelection(tester);
    expect(fixture.played.last.index, 0);
    expect(fixture.played.last.queue.length, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested navigation and breadcrumbs return to any ancestor',
      (tester) async {
    _size(tester);
    final fixture = _Fixture();
    final grandchild =
        fixture.tree.createPlaylist('Grandchild', parent: fixture.child);
    await tester.pumpWidget(_app(fixture.browser(atRoot: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('playlist-open-${fixture.root.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('playlist-open-${fixture.child.id}')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(ValueKey('playlist-open-${grandchild.id}')), findsOneWidget);
    await tester
        .tap(find.byKey(ValueKey('playlist-breadcrumb-${fixture.root.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('playlist-open-${fixture.child.id}')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('playlist-breadcrumb-root')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('playlist-open-${fixture.root.id}')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('right handle reorders mixed siblings with native moving gaps',
      (tester) async {
    _size(tester);
    final fixture = _Fixture();
    final first = fixture.tree.addAudio(fixture.root, _song('First'));
    final child = fixture.child;
    final last = fixture.tree.addAudio(fixture.root, _song('Last'));
    await tester.pumpWidget(_app(fixture.browser()));
    await tester.pumpAndSettle();
    final start =
        tester.getCenter(find.byKey(ValueKey('playlist-drag-${first.id}')));
    final grabOffset = start.dy -
        tester
            .getTopLeft(find.byKey(ValueKey(('playlist-entry', first.id))))
            .dy;
    final pointer =
        await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await pointer.moveBy(const Offset(0, 12));
    await tester.pump();
    final lastBottom = tester
        .getBottomRight(find.byKey(ValueKey(('playlist-entry', last.id))));
    // Native reordering compares the proxy's edges, not just the pointer. Move
    // its top beyond the last row while retaining the original right-hand X.
    final end = Offset(start.dx, lastBottom.dy + grabOffset + 4);
    for (var step = 1; step <= 4; step++) {
      await pointer.moveTo(Offset.lerp(start, end, step / 4)!);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    await pointer.up();
    await tester.pumpAndSettle();
    expect(fixture.root.entries.map((entry) => entry.id),
        [child.id, last.id, first.id]);
    expect(fixture.saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'drop into child provides feedback and persists one relationship move',
      (tester) async {
    _size(tester);
    final fixture = _Fixture();
    final child = fixture.child;
    final track = fixture.tree.addAudio(fixture.root, _song('Move me'));
    await tester.pumpWidget(_app(fixture.browser()));
    await tester.pumpAndSettle();
    final pointer = await _dragTo(tester, track.id,
        find.byKey(ValueKey('playlist-drop-folder-${child.id}')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('松开移入'), findsOneWidget);
    await pointer.up();
    await tester.pumpAndSettle();
    expect(child.entries.single.id, track.id);
    expect(fixture.root.entries.single.id, child.id);
    expect(fixture.saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('self-drop is visibly rejected and never mutates or saves',
      (tester) async {
    _size(tester);
    final fixture = _Fixture();
    final child = fixture.child;
    await tester
        .pumpWidget(_app(fixture.browser(contentView: ContentView.table)));
    await tester.pumpAndSettle();
    final pointer = await _dragTo(tester, child.id,
        find.byKey(ValueKey('playlist-drop-folder-${child.id}')));
    expect(find.text('不能把歌单移入自身'), findsOneWidget);
    await pointer.up();
    await tester.pumpAndSettle();
    expect(child.parent, same(fixture.root));
    expect(fixture.saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Alt arrows reorder focused entries without starting playback',
      (tester) async {
    _size(tester);
    final fixture = _Fixture();
    final first = fixture.tree.addAudio(fixture.root, _song('First'));
    final second = fixture.tree.addAudio(fixture.root, _song('Second'));
    await tester.pumpWidget(_app(fixture.browser()));
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.byKey(ValueKey('playlist-drag-${second.id}'))))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(
        fixture.root.entries.map((entry) => entry.id), [second.id, first.id]);
    expect(fixture.played, isEmpty);
    expect(fixture.saves, 1);
  });

  testWidgets('folder long press opens menu without beginning a drag',
      (tester) async {
    _size(tester);
    final fixture = _Fixture();
    final child = fixture.child;
    await tester.pumpWidget(_app(fixture.browser()));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(ValueKey('playlist-open-${child.id}')));
    await tester.pumpAndSettle();
    expect(find.text('移动到…'), findsOneWidget);
    expect(find.text('删除歌单…'), findsOneWidget);
    expect(fixture.saves, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('menu move reaches another root and retains child identity',
      (tester) async {
    _size(tester);
    final fixture = _Fixture();
    final child = fixture.child;
    final target = fixture.tree.createPlaylist('Target');
    await tester.pumpWidget(_app(fixture.browser()));
    await tester.pumpAndSettle();
    await _openMenu(tester, child.id);
    await tester.tap(find.text('移动到…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('playlist-destination-${target.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '移动'));
    await tester.pumpAndSettle();
    expect(target.entries.single.childPlaylist, same(child));
    expect(target.entries.single.id, child.id);
    expect(fixture.root.entries, isEmpty);
  });

  testWidgets('target picker disables descendants before committing a cycle',
      (tester) async {
    _size(tester);
    final fixture = _Fixture();
    final child = fixture.child;
    await tester.pumpWidget(_app(PlaylistDestinationDialog(
      tree: fixture.tree,
      title: 'Move root',
      confirmLabel: 'Move',
      allowRoot: true,
      disabledReason: (target) => fixture.tree.moveError(
        sourceParent: null,
        entryId: fixture.root.id,
        targetParent: target,
      ),
    )));
    final item = tester.widget<ListTile>(
        find.byKey(ValueKey('playlist-destination-${child.id}')));
    expect(item.enabled, isFalse);
    expect(item.onTap, isNull);
    expect(find.text('不能把歌单移入自己的子歌单'), findsOneWidget);
    expect(fixture.saves, 0);
  });

  testWidgets('destination picker shows hierarchy and a clear selected target',
      (tester) async {
    _size(tester, width: 720, height: 650);
    final fixture = _Fixture();
    final root = fixture.root;
    final child = fixture.child;
    await tester.pumpWidget(_app(
      PlaylistDestinationDialog(
        tree: fixture.tree,
        title: '加入歌单',
        confirmLabel: '添加',
        allowCreate: true,
      ),
      textScale: 1.5,
    ));
    await tester.pumpAndSettle();

    expect(find.text('请选择一个目标歌单'), findsOneWidget);
    expect(
      find.byKey(ValueKey('playlist-destination-${root.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('playlist-destination-${child.id}')),
      findsOneWidget,
    );
    expect(find.text('2 个歌单'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('playlist-destination-${child.id}')));
    await tester.pump();

    expect(find.text('已选择目标歌单'), findsOneWidget);
    expect(find.text('Root / Child'), findsWidgets);
    expect(
      tester
          .widget<FilledButton>(
              find.byKey(const ValueKey('playlist-destination-confirm')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'destination picker cannot be dismissed while a new playlist is saving',
      (tester) async {
    _size(tester, width: 720, height: 650);
    final fixture = _Fixture();
    final saving = Completer<void>();
    var completed = false;
    await tester.pumpWidget(_app(Builder(
      builder: (context) => FilledButton(
        key: const ValueKey('open-playlist-destination'),
        onPressed: () {
          showPlaylistDestinationDialog(
            context,
            tree: fixture.tree,
            title: '加入歌单',
            confirmLabel: '添加',
            allowCreate: true,
            persist: () => saving.future,
          ).then((_) => completed = true);
        },
        child: const Text('Open'),
      ),
    )));

    await tester.tap(find.byKey(const ValueKey('open-playlist-destination')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-destination-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('playlist-name-input')),
      'Pending destination',
    );
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pump();

    expect(find.byType(PlaylistDestinationDialog), findsOneWidget);
    expect(fixture.tree.allPlaylists.last.name, 'Pending destination');
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('playlist-destination-close')),
          )
          .onPressed,
      isNull,
    );

    await tester.tapAt(const Offset(2, 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(PlaylistDestinationDialog), findsOneWidget);
    expect(completed, isFalse);

    saving.complete();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PlaylistDestinationDialog), findsNothing);
    expect(completed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stalled playlist save eventually allows safe dismissal',
      (tester) async {
    _size(tester, width: 720, height: 650);
    final fixture = _Fixture();
    final saving = Completer<void>();
    var completed = false;
    await tester.pumpWidget(_app(Builder(
      builder: (context) => FilledButton(
        onPressed: () {
          showPlaylistDestinationDialog(
            context,
            tree: fixture.tree,
            title: '加入歌单',
            confirmLabel: '添加',
            allowCreate: true,
            persist: () => saving.future,
          ).then((_) => completed = true);
        },
        child: const Text('Open'),
      ),
    )));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-destination-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('playlist-name-input')),
      'Slow destination',
    );
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));

    expect(
      find.text('保存时间较长，操作仍在后台继续。你可以取消并稍后查看结果。'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('playlist-destination-close')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('playlist-destination-confirm')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('playlist-destination-close')));
    await tester.pumpAndSettle();
    expect(find.byType(PlaylistDestinationDialog), findsNothing);
    expect(completed, isTrue);

    saving.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty destination stays usable in a short large-text window',
      (tester) async {
    _size(tester, width: 380, height: 420);
    final fixture = _Fixture();
    await tester.pumpWidget(_app(
      PlaylistDestinationDialog(
        tree: fixture.tree,
        title: '加入歌单',
        confirmLabel: '添加',
        allowCreate: true,
      ),
      textScale: 2,
    ));
    await tester.pumpAndSettle();

    expect(find.byType(PlaylistDestinationDialog), findsOneWidget);
    expect(find.text('还没有歌单，请先新建一个。'), findsOneWidget);
    expect(find.byKey(const ValueKey('playlist-destination-create')),
        findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'subtree deletion needs confirmation and only removes relationships',
      (tester) async {
    _size(tester);
    final fixture = _Fixture();
    final child = fixture.child;
    final original = _song('Keep my source');
    fixture.tree.addAudio(child, original);
    fixture.tree.createPlaylist('Grandchild', parent: child);
    await tester.pumpWidget(_app(fixture.browser()));
    await tester.pumpAndSettle();
    await _openMenu(tester, child.id);
    await tester.tap(find.text('删除歌单…'));
    await tester.pumpAndSettle();
    expect(find.textContaining('不会删除磁盘音乐'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(fixture.root.entries.single.childPlaylist, same(child));
    await _openMenu(tester, child.id);
    await tester.tap(find.text('删除歌单…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除歌单'));
    await tester.pumpAndSettle();
    expect(fixture.root.entries, isEmpty);
    expect(original.onlineId, 'Keep my source');
    expect(original.path, startsWith('online://'));
    expect(fixture.saves, 1);
  });

  testWidgets(
      'rename starts with current name, validates empty input and trims',
      (tester) async {
    _size(tester);
    final fixture = _Fixture();
    final child = fixture.child;
    await tester.pumpWidget(_app(fixture.browser()));
    await tester.pumpAndSettle();
    await _openMenu(tester, child.id);
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('playlist-name-input'));
    expect(tester.widget<TextField>(field).controller!.text, 'Child');
    await tester.enterText(field, '   ');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入歌单名称'), findsOneWidget);
    await tester.enterText(field, '  Renamed  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(child.name, 'Renamed');
    expect(fixture.saves, 1);
    expect(find.byType(PlaylistNameDialog), findsNothing);
  });

  testWidgets(
      'failed save keeps edits visible and retry clears unsaved warning',
      (tester) async {
    _size(tester);
    final fixture = _Fixture();
    var attempts = 0;
    await tester.pumpWidget(_app(fixture.browser(persist: () async {
      attempts++;
      if (attempts == 1) throw StateError('Disk unavailable');
    })));
    await tester.pumpAndSettle();
    await tapPlaylistAction(tester, 'playlist-create');
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('playlist-name-input')), 'New child');
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();
    expect(fixture.root.entries.single.childPlaylist!.name, 'New child');
    expect(find.textContaining('歌单更改尚未保存'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('playlist-retry-save')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(playlistUiSaveError.value, isNull);
    expect(fixture.root.entries.length, 1);
  });

  testWidgets(
      'add songs picker adds local and online descriptors in library order',
      (tester) async {
    _size(tester);
    final fixture = _Fixture();
    final local = Audio('Local', 'Artist', 'Album', 0, 60, null, null,
        r'D:\test-fixture-not-read.mp3', 0, 0, null);
    final online = _song('Online');
    await tester.pumpWidget(_app(fixture.browser(library: [local, online])));
    await tester.pumpAndSettle();
    await tapPlaylistAction(tester, 'playlist-add-songs');
    await tester.pumpAndSettle();
    expect(find.text('选择当前搜索结果'), findsNothing);
    await tester.tap(find.byKey(ValueKey('playlist-pick-${local.path}')));
    await tester.tap(find.byKey(ValueKey('playlist-pick-${online.path}')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '添加 2 首'));
    await tester.pumpAndSettle();
    expect(fixture.root.flattenAudios(), [local, online]);
    expect(fixture.saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'multi-select mixes folders and songs without navigating or playing',
      (tester) async {
    _size(tester);
    final fixture = _Fixture();
    final child = fixture.child;
    final nestedSource = _song('Nested source');
    fixture.tree.addAudio(child, nestedSource);
    final directSource = _song('Direct source');
    final direct = fixture.tree.addAudio(fixture.root, directSource);
    final retained = fixture.tree.addAudio(fixture.root, _song('Keep'));
    await tester.pumpWidget(_app(fixture.browser()));
    await tester.pumpAndSettle();
    await tapPlaylistAction(tester, 'playlist-start-selection');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('playlist-open-${child.id}')));
    await tester.tap(find.byKey(ValueKey('song-${directSource.path}')));
    await tester.pumpAndSettle();
    expect(fixture.played, isEmpty);
    expect(
      tester
          .widget<Checkbox>(find.byKey(ValueKey('playlist-select-${child.id}')))
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<Checkbox>(
              find.byKey(ValueKey('playlist-select-${direct.id}')))
          .value,
      isTrue,
    );
    expect(find.byKey(ValueKey('playlist-drag-${direct.id}')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('playlist-remove-selected')));
    await tester.pumpAndSettle();
    expect(find.textContaining('不会删除磁盘音乐'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(fixture.root.entries.length, 3);
    expect(fixture.saves, 0);
    await tester.tap(find.byKey(const ValueKey('playlist-remove-selected')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('playlist-confirm-remove-selected')));
    await tester.pumpAndSettle();
    expect(fixture.root.entries.single.id, retained.id);
    expect(fixture.saves, 1);
    expect(nestedSource.onlineId, 'Nested source');
    expect(directSource.onlineId, 'Direct source');
    expect(find.byKey(const ValueKey('playlist-current-settings')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('select all acts only on the current layer and can be dismissed',
      (tester) async {
    _size(tester);
    final fixture = _Fixture();
    fixture.child;
    final secondRoot = fixture.tree.createPlaylist('Second root');
    await tester.pumpWidget(_app(fixture.browser(atRoot: true)));
    await tester.pumpAndSettle();
    await tapPlaylistAction(tester, 'playlist-start-selection');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-select-all')));
    await tester.pumpAndSettle();
    expect(find.text('移除所选（2）'), findsOneWidget);
    expect(find.byKey(ValueKey('playlist-select-${fixture.child.id}')),
        findsNothing);
    expect(
      tester
          .widget<Checkbox>(
              find.byKey(ValueKey('playlist-select-${secondRoot.id}')))
          .value,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('playlist-end-selection')));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    expect(fixture.roots.length, 2);
    expect(fixture.saves, 0);
    expect(tester.takeException(), isNull);
  });

  for (final width in [440.0, 1000.0]) {
    testWidgets('empty/nested playlist remains usable at width $width',
        (tester) async {
      _size(tester, width: width, height: 1000);
      final fixture = _Fixture();
      fixture.child;
      await tester.pumpWidget(_app(fixture.browser()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester
          .tap(find.byKey(ValueKey('playlist-open-${fixture.child.id}')));
      await tester.pumpAndSettle();
      expect(find.textContaining('这里还没有项目'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'nested playlist and selection controls fit large text at narrow width',
      (tester) async {
    _size(tester, width: 440, height: 1100);
    final fixture = _Fixture();
    fixture.child;
    await tester.pumpWidget(_app(fixture.browser(), textScale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _tapPageAction(tester, 'playlist-start-selection');
    expect(tester.takeException(), isNull);
    await _tapPageAction(tester, 'playlist-select-all');
    expect(tester.takeException(), isNull);
  });

  test('a late older save cannot clear the most recent save failure', () async {
    final older = Completer<void>();
    final newer = Completer<void>();
    final first = savePlaylistUiChanges(persist: () => older.future);
    final second = savePlaylistUiChanges(persist: () => newer.future);
    final secondResult = expectLater(second, throwsStateError);
    newer.completeError(StateError('Latest snapshot failed'));
    await secondResult;
    older.complete();
    await first;
    expect(playlistUiSaveError.value, contains('Latest snapshot failed'));
    expect(playlistUiSaving.value, isFalse);
  });
}
