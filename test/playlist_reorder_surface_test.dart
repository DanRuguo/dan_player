import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/playlist_reorder_surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture extends StatefulWidget {
  const _Fixture({
    super.key,
    required this.controller,
    this.ids = const ['a', 'folder', 'b', 'c'],
    this.enabled = true,
  });

  final PlaylistReorderController controller;
  final List<String> ids;
  final bool enabled;

  @override
  State<_Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<_Fixture> {
  late final ids = List<String>.of(widget.ids);
  late bool enabled = widget.enabled;
  bool cancelDuringBuild = false;
  Key surfaceKey = const ValueKey('surface');
  final scroll = ScrollController();
  final reorders = <(String, int)>[];
  final moves = <(String, String)>[];
  final initializations = <String, int>{};
  final disposals = <String, int>{};
  var plays = 0;
  var longPresses = 0;
  var accepting = true;

  void rebuild() => setState(() {});

  void setEnabled(bool value) => setState(() => enabled = value);

  void removeExternally(String id) => setState(() => ids.remove(id));

  void navigate(String page, List<String> entries) => setState(() {
        surfaceKey = PageStorageKey(page);
        ids
          ..clear()
          ..addAll(entries);
      });

  void _move(PlaylistDragData data, String target) {
    moves.add((data.entryId, target));
    setState(() => ids.remove(data.entryId));
  }

  Widget _target(String id, Widget child) => PlaylistReorderDropZone(
        key: ValueKey('zone-$id'),
        controller: widget.controller,
        id: id,
        canDrop: (data) => accepting && data.entryId != id && id != 'blocked',
        rejectionReason: (_) => '不能把歌单移入自身或子级',
        onDrop: (data) => _move(data, id),
        child: child,
      );

  Widget _row(BuildContext context, int index) {
    final id = ids[index];
    final name = Expanded(
      child: _target(
        id == 'folder' ? 'folder' : 'blocked-$id',
        _StatefulName(
          key: ValueKey('name-$id'),
          id: id,
          fixture: this,
        ),
      ),
    );
    return AppEntrance(
      key: ValueKey('row-$id'),
      identity: ('reorder-test-row', id),
      order: index,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => plays++,
          onLongPress: () => longPresses++,
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                name,
                MenuAnchor(
                  menuChildren: [
                    MenuItemButton(
                      onPressed: () {},
                      child: Text('管理 $id'),
                    ),
                  ],
                  builder: (context, menu, _) => PlaylistReorderHandle(
                    key: ValueKey('handle-$id'),
                    controller: widget.controller,
                    index: index,
                    enabled: enabled,
                    child: IconButton(
                      key: ValueKey('menu-$id'),
                      tooltip: '项目操作 $id',
                      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                      icon: const Icon(Icons.more_vert),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cancelDuringBuild) widget.controller.cancel();
    return AppEntranceScope(
      child: Column(
        children: [
          Row(
            children: [
              _target(
                'ancestor',
                const SizedBox(
                    width: 190, height: 64, child: Center(child: Text('父歌单'))),
              ),
              _target(
                'blocked',
                const SizedBox(
                    width: 190, height: 64, child: Center(child: Text('禁止移入'))),
              ),
            ],
          ),
          Expanded(
            child: PlaylistReorderSurface(
              key: surfaceKey,
              controller: widget.controller,
              enabled: enabled,
              items: [
                for (final id in ids)
                  PlaylistDragData(entryId: id, sourceParent: null, label: id),
              ],
              scrollController: scroll,
              padding: const EdgeInsets.only(bottom: 80),
              itemExtent: 72,
              itemBuilder: _row,
              onReorder: (data, index) {
                reorders.add((data.entryId, index));
                setState(() {
                  ids.remove(data.entryId);
                  ids.insert(index, data.entryId);
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }
}

class _StatefulName extends StatefulWidget {
  const _StatefulName({
    super.key,
    required this.id,
    required this.fixture,
  });

  final String id;
  final _FixtureState fixture;

  @override
  State<_StatefulName> createState() => _StatefulNameState();
}

class _StatefulNameState extends State<_StatefulName> {
  @override
  void initState() {
    super.initState();
    widget.fixture.initializations
        .update(widget.id, (n) => n + 1, ifAbsent: () => 1);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 72,
        child: Row(
          children: [
            const SizedBox(
              width: 52,
              height: 52,
              child: ColoredBox(color: Color(0xff427ab3)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child:
                  Text(widget.id, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );

  @override
  void dispose() {
    widget.fixture.disposals.update(widget.id, (n) => n + 1, ifAbsent: () => 1);
    super.dispose();
  }
}

Future<({PlaylistReorderController controller, _FixtureState fixture})> _mount(
  WidgetTester tester, {
  List<String> ids = const ['a', 'folder', 'b', 'c'],
  double height = 650,
  bool enabled = true,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(820, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = PlaylistReorderController();
  final key = GlobalKey<_FixtureState>();
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(platform: TargetPlatform.windows),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: _Fixture(
          key: key, controller: controller, ids: ids, enabled: enabled),
    ),
  ));
  await tester.pumpAndSettle();
  addTearDown(controller.dispose);
  return (controller: controller, fixture: key.currentState!);
}

Future<TestGesture> _start(
  WidgetTester tester,
  String id, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) async {
  final position = tester.getCenter(find.byKey(ValueKey('handle-$id')));
  final gesture = await tester.startGesture(position, kind: kind);
  await gesture.moveBy(const Offset(-2, 24));
  await tester.pump();
  return gesture;
}

Future<void> _finish(WidgetTester tester, TestGesture gesture) async {
  await gesture.up();
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('only the trailing three dots remain, and a short tap opens menu',
      (tester) async {
    final h = await _mount(tester);
    expect(find.byIcon(Icons.more_vert), findsNWidgets(4));
    expect(find.byIcon(Icons.drag_indicator), findsNothing);
    await tester.tap(find.byKey(const ValueKey('menu-a')));
    await tester.pumpAndSettle();
    expect(find.text('管理 a'), findsOneWidget);
    expect(h.controller.isDragging, isFalse);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.moves, isEmpty);
    expect(h.fixture.plays, 0);
  });

  testWidgets('native gap moves before release; final index is corrected once',
      (tester) async {
    final h = await _mount(tester);
    final sourceState = tester.state(find.byKey(const ValueKey('name-a')));
    final beforeFolder =
        tester.getTopLeft(find.byKey(const ValueKey('row-folder')));
    final end = tester.getCenter(find.byKey(const ValueKey('handle-c')));
    final gesture = await _start(tester, 'a');
    await gesture.moveTo(end + const Offset(0, 90));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.controller.isDragging, isTrue);
    expect(h.fixture.ids, ['a', 'folder', 'b', 'c']);
    expect(h.fixture.reorders, isEmpty);
    expect(tester.getTopLeft(find.byKey(const ValueKey('row-folder'))).dy,
        lessThan(beforeFolder.dy));
    expect(
        tester.state(find.byKey(const ValueKey('name-a'))), same(sourceState));
    expect(h.fixture.initializations['a'], 1);
    await _finish(tester, gesture);
    expect(h.fixture.ids, ['folder', 'b', 'c', 'a']);
    expect(h.fixture.reorders, [('a', 3)]);
    expect(h.fixture.moves, isEmpty);
    expect(h.controller.isDragging, isFalse);
    expect(
        h.fixture.initializations.values.every((count) => count == 1), isTrue);
    expect(h.fixture.disposals, isEmpty);
    expect(
        tester.state(find.byKey(const ValueKey('name-a'))), same(sourceState));
  });

  testWidgets('touch can drag the same trailing button without playing a row',
      (tester) async {
    final h = await _mount(tester);
    final end = tester.getCenter(find.byKey(const ValueKey('handle-a')));
    final gesture = await _start(tester, 'c', kind: PointerDeviceKind.touch);
    await gesture.moveTo(end);
    await tester.pump(const Duration(milliseconds: 300));
    await _finish(tester, gesture);
    expect(h.fixture.ids, ['c', 'a', 'folder', 'b']);
    expect(h.fixture.reorders, [('c', 0)]);
    expect(h.fixture.plays, 0);
  });

  testWidgets('row long press keeps its context action and starts no reorder',
      (tester) async {
    final h = await _mount(tester);
    await tester.longPress(find.byKey(const ValueKey('name-a')));
    await tester.pumpAndSettle();
    expect(h.fixture.longPresses, 1);
    expect(h.controller.isDragging, isFalse);
    expect(h.fixture.reorders, isEmpty);
  });

  testWidgets('touch swipe on name scrolls instead of dragging a relationship',
      (tester) async {
    final h = await _mount(tester,
        ids: List.generate(30, (i) => 'song-$i'), height: 440);
    await tester.drag(
        find.byKey(const ValueKey('name-song-3')), const Offset(0, -220),
        touchSlopY: 20);
    await tester.pumpAndSettle();
    expect(h.fixture.scroll.offset, greaterThan(0));
    expect(h.controller.isDragging, isFalse);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.moves, isEmpty);
  });

  testWidgets('native edge auto-scroll continues while the pointer stays still',
      (tester) async {
    final h = await _mount(tester,
        ids: List.generate(40, (i) => 'song-$i'), height: 440);
    final x = tester.getCenter(find.byKey(const ValueKey('handle-song-0'))).dx;
    final bottom =
        tester.getBottomRight(find.byKey(const ValueKey('surface'))).dy;
    final gesture = await _start(tester, 'song-0');
    await gesture.moveTo(Offset(x, bottom - 2));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.fixture.scroll.offset, greaterThan(72));
    expect(h.fixture.reorders, isEmpty);
    h.controller.cancel();
    await _finish(tester, gesture);
    expect(h.fixture.reorders, isEmpty);
    expect(h.controller.isDragging, isFalse);
  });

  testWidgets('folder centre stays reachable during dwell and moves only once',
      (tester) async {
    final h = await _mount(tester);
    final zone = find.byKey(const ValueKey('zone-folder'));
    final target = tester.getCenter(zone);
    final gesture = await _start(tester, 'a');
    await gesture.moveTo(target);
    await tester.pump();
    expect(
        h.controller.hoverStateFor('folder'), PlaylistDropHoverState.pending);
    expect(find.text('稍作停留移入'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 499));
    expect(
        h.controller.hoverStateFor('folder'), PlaylistDropHoverState.pending);
    await tester.pump(const Duration(milliseconds: 2));
    expect(h.controller.hoverStateFor('folder'), PlaylistDropHoverState.ready);
    expect(find.text('松开移入'), findsOneWidget);
    expect(tester.getCenter(zone), target);
    await _finish(tester, gesture);
    expect(h.fixture.moves, [('a', 'folder')]);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.ids, ['folder', 'b', 'c']);
  });

  testWidgets(
      'breadcrumb move commits even when native reorder index is unchanged',
      (tester) async {
    final h = await _mount(tester);
    final gesture = await _start(tester, 'a');
    await gesture
        .moveTo(tester.getCenter(find.byKey(const ValueKey('zone-ancestor'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 501));
    expect(
        h.controller.hoverStateFor('ancestor'), PlaylistDropHoverState.ready);
    await _finish(tester, gesture);
    expect(h.fixture.moves, [('a', 'ancestor')]);
    expect(h.fixture.reorders, isEmpty);
  });

  testWidgets(
      'passing a folder briefly never performs an accidental nested move',
      (tester) async {
    final h = await _mount(tester);
    final gesture = await _start(tester, 'a');
    await gesture
        .moveTo(tester.getCenter(find.byKey(const ValueKey('zone-folder'))));
    await tester.pump(const Duration(milliseconds: 150));
    await _finish(tester, gesture);
    expect(h.fixture.moves, isEmpty);
    expect(h.fixture.reorders.length, lessThanOrEqualTo(1));
  });

  testWidgets(
      'reject reason is visible and drop commits neither move nor reorder',
      (tester) async {
    final h = await _mount(tester);
    final gesture = await _start(tester, 'c');
    await gesture
        .moveTo(tester.getCenter(find.byKey(const ValueKey('zone-blocked'))));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('不能把歌单移入自身或子级'), findsOneWidget);
    await _finish(tester, gesture);
    expect(h.fixture.moves, isEmpty);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.ids, ['a', 'folder', 'b', 'c']);
  });

  testWidgets(
      'drop revalidates an already armed target after model rules change',
      (tester) async {
    final h = await _mount(tester);
    final gesture = await _start(tester, 'a');
    await gesture
        .moveTo(tester.getCenter(find.byKey(const ValueKey('zone-folder'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 501));
    expect(h.controller.hoverStateFor('folder'), PlaylistDropHoverState.ready);
    h.fixture.accepting = false;
    h.fixture.rebuild();
    await tester.pump();
    await _finish(tester, gesture);
    expect(h.fixture.moves, isEmpty);
    expect(h.fixture.reorders, isEmpty);
  });

  testWidgets(
      'leaving an armed folder restores native dragging and reorders once',
      (tester) async {
    final h = await _mount(tester);
    final end = tester.getCenter(find.byKey(const ValueKey('handle-c')));
    final gesture = await _start(tester, 'a');
    await gesture
        .moveTo(tester.getCenter(find.byKey(const ValueKey('zone-folder'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 501));
    await gesture.moveTo(end + const Offset(0, 90));
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.controller.hoverStateFor('folder'), PlaylistDropHoverState.idle);
    await _finish(tester, gesture);
    expect(h.fixture.moves, isEmpty);
    expect(h.fixture.reorders, [('a', 3)]);
  });

  testWidgets(
      'Escape cancels a native drag and prevents a later pointer-up save',
      (tester) async {
    final h = await _mount(tester);
    final end = tester.getCenter(find.byKey(const ValueKey('handle-c')));
    final gesture = await _start(tester, 'a');
    await gesture.moveTo(end);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.controller.isDragging, isFalse);
    await _finish(tester, gesture);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.moves, isEmpty);
    expect(h.fixture.ids, ['a', 'folder', 'b', 'c']);
  });

  testWidgets('pointer cancellation releases hover timers and makes no changes',
      (tester) async {
    final h = await _mount(tester);
    final gesture = await _start(tester, 'a');
    await gesture
        .moveTo(tester.getCenter(find.byKey(const ValueKey('zone-folder'))));
    await tester.pump();
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(h.controller.isDragging, isFalse);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.moves, isEmpty);
    expect(find.text('松开移入'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('release outside the list and registered targets cancels safely',
      (tester) async {
    final h = await _mount(tester);
    final gesture = await _start(tester, 'a');
    await gesture.moveTo(const Offset(1100, 500));
    await tester.pump();
    await _finish(tester, gesture);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.moves, isEmpty);
  });

  testWidgets('a second touch cannot replace the active relationship drag',
      (tester) async {
    final h = await _mount(tester);
    final secondStart =
        tester.getCenter(find.byKey(const ValueKey('handle-c')));
    final first = await _start(tester, 'a', kind: PointerDeviceKind.touch);
    final second = await tester.startGesture(secondStart,
        pointer: 9, kind: PointerDeviceKind.touch);
    await second.moveBy(const Offset(0, -100));
    await tester.pump();
    expect(h.controller.dragData?.entryId, 'a');
    await second.cancel();
    h.controller.cancel();
    await _finish(tester, first);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.moves, isEmpty);
  });

  testWidgets(
      'an external relationship change cancels instead of using stale indices',
      (tester) async {
    final h = await _mount(tester);
    final gesture = await _start(tester, 'a');
    h.fixture.removeExternally('b');
    await tester.pump();
    expect(h.controller.isDragging, isFalse);
    await _finish(tester, gesture);
    expect(h.fixture.ids, ['a', 'folder', 'c']);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.moves, isEmpty);
  });

  testWidgets(
      'unrelated parent rebuild does not cancel a drag or replay entrance',
      (tester) async {
    final h = await _mount(tester);
    final before = tester.state(find.byKey(const ValueKey('name-a')));
    final gesture = await _start(tester, 'a');
    h.fixture.rebuild();
    await tester.pump();
    expect(h.controller.isDragging, isTrue);
    expect(tester.state(find.byKey(const ValueKey('name-a'))), same(before));
    final opacities = tester.widgetList<Opacity>(find.descendant(
        of: find.byKey(const ValueKey('row-a')),
        matching: find.byType(Opacity)));
    expect(opacities.every((opacity) => opacity.opacity == 1), isTrue);
    h.controller.cancel();
    await _finish(tester, gesture);
    expect(h.fixture.initializations['a'], 1);
  });

  testWidgets('a no-op drop cleans up the session and permits the next drag',
      (tester) async {
    final h = await _mount(tester);
    final start = tester.getCenter(find.byKey(const ValueKey('handle-a')));
    final first = await _start(tester, 'a');
    await first.moveTo(start);
    await tester.pump(const Duration(milliseconds: 300));
    await _finish(tester, first);
    expect(h.controller.isDragging, isFalse);
    expect(h.fixture.reorders, isEmpty);
    final second = await _start(tester, 'a');
    expect(h.controller.isDragging, isTrue);
    h.controller.cancel();
    await _finish(tester, second);
  });

  testWidgets('disabled/custom-sort-off surface keeps the menu but cannot drag',
      (tester) async {
    final h = await _mount(tester, enabled: false, textScale: 2);
    final handle = find.byKey(const ValueKey('handle-a'));
    expect(tester.getSize(handle).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(handle).height, greaterThanOrEqualTo(48));
    final gesture = await _start(tester, 'a');
    expect(h.controller.isDragging, isFalse);
    await _finish(tester, gesture);
    expect(h.fixture.reorders, isEmpty);
    await tester.tap(find.byKey(const ValueKey('menu-a')));
    await tester.pumpAndSettle();
    expect(find.text('管理 a'), findsOneWidget);
  });

  testWidgets('secondary mouse button cannot initiate the native reorder',
      (tester) async {
    final h = await _mount(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('handle-a'))),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.moveBy(const Offset(0, 160));
    await tester.pump();
    await _finish(tester, gesture);
    expect(h.controller.isDragging, isFalse);
    expect(h.fixture.reorders, isEmpty);
  });

  testWidgets(
      'unmount during dwell leaves no pointer route or delayed callbacks',
      (tester) async {
    final h = await _mount(tester);
    final gesture = await _start(tester, 'a');
    await gesture
        .moveTo(tester.getCenter(find.byKey(const ValueKey('zone-folder'))));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 700));
    expect(h.controller.isDragging, isFalse);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.moves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabling a live reorder cancels without changing source state',
      (tester) async {
    final h = await _mount(tester);
    final source = tester.state(find.byKey(const ValueKey('name-a')));
    final end = tester.getCenter(find.byKey(const ValueKey('handle-c')));
    final gesture = await _start(tester, 'a');
    await gesture.moveTo(end);
    await tester.pump();
    h.fixture.setEnabled(false);
    await tester.pumpAndSettle();
    expect(h.controller.isDragging, isFalse);
    await _finish(tester, gesture);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.moves, isEmpty);
    expect(tester.state(find.byKey(const ValueKey('name-a'))), same(source));
  });

  testWidgets('parent build can cancel and mutate before the surface updates',
      (tester) async {
    final h = await _mount(tester);
    final gesture = await _start(tester, 'a');
    h.fixture.cancelDuringBuild = true;
    h.fixture.removeExternally('b');
    await tester.pumpAndSettle();
    await _finish(tester, gesture);
    expect(h.fixture.ids, ['a', 'folder', 'c']);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.moves, isEmpty);
    expect(h.controller.isDragging, isFalse);
  });

  testWidgets(
      'a modal route cancels the underlying drag without global-key errors',
      (tester) async {
    final h = await _mount(tester);
    final gesture = await _start(tester, 'a');
    final dialog = showDialog<void>(
      context: h.fixture.context,
      builder: (_) => const AlertDialog(content: Text('正在编辑')),
    );
    await tester.pumpAndSettle();
    expect(h.controller.isDragging, isFalse);
    await _finish(tester, gesture);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.moves, isEmpty);
    Navigator.of(h.fixture.context).pop();
    await tester.pumpAndSettle();
    await dialog;
  });

  testWidgets(
      'folding back out of a target flushes net delta, not every old leg',
      (tester) async {
    final h = await _mount(tester);
    final source = tester.getCenter(find.byKey(const ValueKey('handle-a')));
    final target = tester.getCenter(find.byKey(const ValueKey('zone-folder')));
    final gesture = await _start(tester, 'a');
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 501));
    expect(h.controller.hoverStateFor('folder'), PlaylistDropHoverState.ready);
    await gesture.moveTo(source);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _finish(tester, gesture);
    expect(h.fixture.ids, ['a', 'folder', 'b', 'c']);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.moves, isEmpty);
  });

  testWidgets('sub-frame down move up safely cancels an unpainted native proxy',
      (tester) async {
    final h = await _mount(tester);
    final source = tester.getCenter(find.byKey(const ValueKey('handle-a')));
    final gesture =
        await tester.startGesture(source, kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(0, 24));
    await gesture.moveTo(source);
    await _finish(tester, gesture);
    expect(h.controller.isDragging, isFalse);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.moves, isEmpty);
    final next = await _start(tester, 'a');
    expect(h.controller.isDragging, isTrue);
    h.controller.cancel();
    await _finish(tester, next);
  });

  testWidgets('one controller can replace differently keyed playlist surfaces',
      (tester) async {
    final h = await _mount(tester);
    final original = tester.state(find.byType(PlaylistReorderSurface));
    h.fixture
        .navigate('child-page', ['nested', 'folder', 'child-b', 'child-c']);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.state(find.byType(PlaylistReorderSurface)),
        isNot(same(original)));
    expect(h.fixture.scroll.positions, hasLength(1));
    expect(h.controller.isDragging, isFalse);
    final childGesture = await _start(tester, 'nested');
    expect(h.controller.dragData?.entryId, 'nested');
    h.controller.cancel();
    await _finish(tester, childGesture);
    h.fixture.navigate('root-page', ['a', 'folder', 'b', 'c']);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final rootGesture = await _start(tester, 'a');
    expect(h.controller.dragData?.entryId, 'a');
    h.controller.cancel();
    await _finish(tester, rootGesture);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.moves, isEmpty);
  });

  testWidgets('child and root navigation cancel pending and armed folder drops',
      (tester) async {
    final h = await _mount(tester);
    final rootGesture = await _start(tester, 'a');
    await rootGesture
        .moveTo(tester.getCenter(find.byKey(const ValueKey('zone-folder'))));
    await tester.pump(const Duration(milliseconds: 150));
    h.fixture
        .navigate('child-page', ['nested', 'folder', 'child-b', 'child-c']);
    await tester.pumpAndSettle();
    expect(h.controller.isDragging, isFalse);
    expect(h.controller.dragData, isNull);
    expect(find.byKey(const ValueKey('row-a')), findsNothing);
    await _finish(tester, rootGesture);
    expect(h.fixture.scroll.positions, hasLength(1));

    final childGesture = await _start(tester, 'nested');
    await childGesture
        .moveTo(tester.getCenter(find.byKey(const ValueKey('zone-folder'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 501));
    expect(h.controller.hoverStateFor('folder'), PlaylistDropHoverState.ready);
    h.fixture.navigate('root-page', ['a', 'folder', 'b', 'c']);
    await tester.pumpAndSettle();
    expect(h.controller.isDragging, isFalse);
    expect(h.controller.dragData, isNull);
    expect(find.byKey(const ValueKey('row-nested')), findsNothing);
    await _finish(tester, childGesture);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('松开移入'), findsNothing);
    expect(h.fixture.ids, ['a', 'folder', 'b', 'c']);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.moves, isEmpty);
    expect(tester.takeException(), isNull);
    final next = await _start(tester, 'a');
    expect(h.controller.isDragging, isTrue);
    h.controller.cancel();
    await _finish(tester, next);
  });

  testWidgets(
      'navigation stops the old native auto-scroller and ignores its up',
      (tester) async {
    final h = await _mount(tester,
        ids: List.generate(40, (index) => 'entry-$index'), height: 440);
    final gesture = await _start(tester, 'entry-0');
    await gesture.moveTo(const Offset(790, 425));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.fixture.scroll.offset, greaterThan(0));
    h.fixture
        .navigate('child-page', ['nested', 'folder', 'child-b', 'child-c']);
    await tester.pumpAndSettle();
    expect(h.controller.isDragging, isFalse);
    expect(h.fixture.scroll.positions, hasLength(1));
    final childOffset = h.fixture.scroll.offset;
    await tester.pump(const Duration(milliseconds: 700));
    expect(h.fixture.scroll.offset, childOffset);
    await _finish(tester, gesture);
    expect(h.fixture.reorders, isEmpty);
    expect(h.fixture.moves, isEmpty);
    expect(find.byKey(const ValueKey('row-entry-0')), findsNothing);
  });

  testWidgets(
      'GlobalKey reactivation rebinds and cancels the captured old drag',
      (tester) async {
    final controller = PlaylistReorderController();
    addTearDown(controller.dispose);
    final surfaceKey = GlobalKey();
    final reorders = <(String, int)>[];
    var onRight = false;
    late StateSetter relocate;
    const ids = ['a', 'b', 'c'];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          relocate = setState;
          final surface = PlaylistReorderSurface(
            key: surfaceKey,
            controller: controller,
            itemExtent: 72,
            items: [
              for (final id in ids)
                PlaylistDragData(entryId: id, sourceParent: null, label: id),
            ],
            onReorder: (data, index) => reorders.add((data.entryId, index)),
            itemBuilder: (context, index) => SizedBox(
              height: 72,
              child: ListTile(
                title: Text(ids[index]),
                trailing: PlaylistReorderHandle(
                  key: ValueKey('handle-${ids[index]}'),
                  controller: controller,
                  index: index,
                  child: IconButton(
                      onPressed: () {}, icon: const Icon(Icons.more_vert)),
                ),
              ),
            ),
          );
          return Row(children: [
            Expanded(child: onRight ? const SizedBox() : surface),
            Expanded(child: onRight ? surface : const SizedBox()),
          ]);
        }),
      ),
    ));
    await tester.pumpAndSettle();
    final state = surfaceKey.currentState;
    final sourceState = tester.state(find.byKey(const ValueKey('handle-a')));
    final siblingState = tester.state(find.byKey(const ValueKey('handle-b')));
    final first = await _start(tester, 'a');
    expect(controller.isDragging, isTrue);
    relocate(() => onRight = true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(surfaceKey.currentState, same(state));
    expect(tester.state(find.byKey(const ValueKey('handle-a'))),
        same(sourceState));
    expect(tester.state(find.byKey(const ValueKey('handle-b'))),
        same(siblingState));
    expect(controller.isDragging, isFalse);
    await _finish(tester, first);
    final next = await _start(tester, 'a');
    expect(controller.isDragging, isTrue);
    controller.cancel();
    await _finish(tester, next);
    expect(reorders, isEmpty);
  });
}
