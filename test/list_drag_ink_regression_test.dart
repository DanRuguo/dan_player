import 'dart:ui' as ui;

import 'package:dan_player/component/app_item_ink_well.dart';
import 'package:dan_player/component/playlist_reorder_surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Rows extends StatefulWidget {
  const _Rows({required this.playlist, required this.boundary});
  final bool playlist;
  final GlobalKey boundary;
  @override
  State<_Rows> createState() => _RowsState();
}

class _RowsState extends State<_Rows> {
  final ids = ['a', 'b', 'c'];
  final reorder = PlaylistReorderController();

  Widget _row(BuildContext context, int index) {
    final id = ids[index];
    final action = SizedBox(
      width: 48,
      height: 64,
      child: IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
    );
    return Material(
      key: ValueKey(id),
      color: Colors.white,
      child: AppItemInkWell(
        onTap: () {},
        child: SizedBox(
          height: 64,
          child: Row(children: [
            Expanded(child: Text(id)),
            if (widget.playlist)
              PlaylistReorderHandle(
                  key: ValueKey('handle-$id'),
                  controller: reorder,
                  index: index,
                  child: action)
            else
              ReorderableDragStartListener(
                  key: ValueKey('handle-$id'), index: index, child: action),
          ]),
        ),
      ),
    );
  }

  void _reorder(int from, int to) => setState(() {
        final id = ids.removeAt(from);
        ids.insert(to, id);
      });

  @override
  Widget build(BuildContext context) => RepaintBoundary(
      key: widget.boundary,
      child: SizedBox(
        width: 360,
        height: 270,
        child: widget.playlist
            ? PlaylistReorderSurface(
                controller: reorder,
                padding: EdgeInsets.zero,
                items: [
                  for (final id in ids)
                    PlaylistDragData(
                        entryId: id, sourceParent: null, label: id),
                ],
                itemBuilder: _row,
                onReorder: (data, to) =>
                    _reorder(ids.indexOf(data.entryId), to))
            : ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: ids.length,
                itemBuilder: _row,
                onReorderItem: _reorder),
      ));

  @override
  void dispose() {
    reorder.dispose();
    super.dispose();
  }
}

Future<int> _pixel(
        WidgetTester tester, GlobalKey boundary, Offset global) async =>
    (await tester.runAsync(() async {
      final box =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final point = box.globalToLocal(global);
      final image = await box.toImage();
      final data =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final at = (point.dy.floor() * image.width + point.dx.floor()) * 4;
      final color = data.getUint32(at);
      image.dispose();
      return color;
    }))!;

void main() {
  testWidgets(
      'row keyboard focus remains visible, descendant focus stays local',
      (tester) async {
    final previous = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = previous);
    var activated = 0;
    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RepaintBoundary(
      key: boundary,
      child: Material(
          color: Colors.white,
          child: AppItemInkWell(
            onTap: () => activated++,
            child: SizedBox(
                width: 360,
                height: 64,
                child: Row(children: [
                  const Expanded(child: Text('Song')),
                  IconButton(
                      onPressed: () {}, icon: const Icon(Icons.more_vert)),
                ])),
          )),
    ))));
    await tester.pumpAndSettle();
    final ink = tester.widget<InkWell>(find
        .descendant(
            of: find.byType(AppItemInkWell), matching: find.byType(InkWell))
        .first);
    ink.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(await _pixel(tester, boundary, const Offset(100, 30)),
        isNot(0xffffffff));
    Focus.of(tester.element(find.byIcon(Icons.more_vert))).requestFocus();
    await tester.pumpAndSettle();
    expect(ink.focusNode!.hasFocus, isTrue);
    expect(ink.focusNode!.hasPrimaryFocus, isFalse);
    expect(await _pixel(tester, boundary, const Offset(100, 30)), 0xffffffff);
    ink.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(activated, 1);
    expect(tester.takeException(), isNull);
  });

  for (final playlist in [false, true]) {
    for (final cancel in [false, true]) {
      testWidgets(
          'released ${playlist ? 'playlist' : 'music'} drag ink clears '
          '${cancel ? 'on cancel' : 'after reorder'}', (tester) async {
        final boundary = GlobalKey();
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: Scaffold(
                body: Align(
                    alignment: Alignment.topLeft,
                    child: _Rows(playlist: playlist, boundary: boundary)))));
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        final handle = tester.getCenter(find.byKey(const ValueKey('handle-a')));
        await mouse.addPointer(location: const Offset(500, 350));
        await mouse.moveTo(handle);
        await tester.pumpAndSettle();
        final rowPoint = tester.getTopLeft(find.byKey(const ValueKey('a'))) +
            const Offset(100, 30);
        expect(await _pixel(tester, boundary, rowPoint), isNot(0xffffffff),
            reason: 'Real hover feedback must remain visible before dragging');
        await mouse.down(handle);
        await mouse.moveBy(const Offset(0, 16));
        await tester.pump();
        await mouse.moveBy(const Offset(0, 130));
        await tester.pump(const Duration(milliseconds: 350));
        if (cancel) {
          await mouse.cancel();
        } else {
          await mouse.up();
        }
        await mouse.moveTo(const Offset(500, 350));
        await tester.pumpAndSettle();
        final after = tester.getTopLeft(find.byKey(const ValueKey('a'))) +
            const Offset(100, 30);
        expect(await _pixel(tester, boundary, after), 0xffffffff,
            reason:
                'A completed or cancelled drag must not paint stale row ink');
        expect(tester.takeException(), isNull);
        await mouse.removePointer();
      });
    }
  }
}
