import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/app_item_ink_well.dart';
import 'package:dan_player/component/category_tile_grid.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

class _Store extends CategoryCoverStore {
  _Store() : super(dataDirectory: () async => Directory.systemTemp);
  @override
  Future<ImageProvider?> imageFor(MusicCategoryGroup group) async => null;
}

Future<int> _pixel(
  WidgetTester tester,
  GlobalKey boundary,
  Offset global,
) async =>
    (await tester.runAsync(() async {
      final box =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final point = box.globalToLocal(global);
      final image = await box.toImage();
      try {
        final data = (await image.toByteData(
          format: raster.ImageByteFormat.rawRgba,
        ))!;
        return data.getUint32(
          (point.dy.floor() * image.width + point.dx.floor()) * 4,
        );
      } finally {
        image.dispose();
      }
    }))!;

void main() {
  for (final cancel in [true, false]) {
    testWidgets(
      'secondary touch ${cancel ? "cancel" : "release"} keeps active category press ink',
      (tester) async {
        final store = _Store();
        addTearDown(store.dispose);
        final group = MusicCategories([CategoryTestAudio('Song')])
            .groups(MusicCategoryKind.artist)
            .single;
        var opened = 0;
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                body: CustomScrollView(
                  slivers: [
                    CategoryTileGrid(
                      groups: [group],
                      presentation: const CategoryPresentation(
                          shape: CategoryCoverShape.rounded),
                      onChanged: (_) {},
                      onOpen: (_) => opened++,
                      covers: store,
                      changing: const {},
                      onChangeCover: (_) {},
                      onRemoveCover: (_) {},
                      icon: Icons.person,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = find.byKey(ValueKey(('category-card', group.id)));
        expect(tester.widget(card), isA<AppItemInkWell>());
        final ink = tester.widget<InkWell>(
          find.descendant(of: card, matching: find.byType(InkWell)),
        );
        final origin = tester.getTopLeft(card) + const Offset(12, 12);
        final idlePixel = await _pixel(tester, boundary, origin);
        final primary = await tester.startGesture(
          origin,
          pointer: 1,
          kind: PointerDeviceKind.touch,
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(ink.statesController!.value, contains(WidgetState.pressed));
        final pressedPixel = await _pixel(tester, boundary, origin);
        expect(pressedPixel, isNot(idlePixel));
        final secondary = await tester.startGesture(
          origin + const Offset(20, 20),
          pointer: 2,
          kind: PointerDeviceKind.touch,
        );
        await tester.pump();
        expect(
          ink.statesController!.value,
          contains(WidgetState.pressed),
          reason:
              'The secondary touch must not itself cancel the primary press',
        );
        if (cancel) {
          await secondary.cancel();
        } else {
          await secondary.up();
        }
        await tester.pump();
        expect(
          ink.statesController!.value,
          contains(WidgetState.pressed),
          reason:
              'Primary touch remains down; another pointer cannot release its ink',
        );
        expect(await _pixel(tester, boundary, origin), pressedPixel);
        await primary.up();
        await tester.pumpAndSettle();
        expect(
          ink.statesController!.value,
          isNot(contains(WidgetState.pressed)),
        );
        expect(opened, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
      'primary cancel clears its ink while a secondary touch is still down',
      (tester) async {
    var activated = 0;
    await tester.pumpWidget(_plain(() => activated++));
    final target = find.byType(AppItemInkWell);
    final ink = tester.widget<InkWell>(
        find.descendant(of: target, matching: find.byType(InkWell)));
    final center = tester.getCenter(target);
    final primary = await tester.startGesture(center, pointer: 1);
    await tester.pump(const Duration(milliseconds: 120));
    final secondary =
        await tester.startGesture(center + const Offset(20, 0), pointer: 2);
    await tester.pump();
    expect(ink.statesController!.value, contains(WidgetState.pressed));
    await primary.cancel();
    await tester.pumpAndSettle();
    expect(ink.statesController!.value, isNot(contains(WidgetState.pressed)));
    await secondary.up();
    await tester.pumpAndSettle();
    expect(activated, 0);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a cancelled pointer cleanup cannot clear a new press in the same packet',
      (tester) async {
    var activated = 0;
    await tester.pumpWidget(_plain(() => activated++));
    final target = find.byType(AppItemInkWell);
    final ink = tester.widget<InkWell>(
        find.descendant(of: target, matching: find.byType(InkWell)));
    final center = tester.getCenter(target);
    final first = TestPointer(1);
    final next = TestPointer(2);
    tester.binding.handlePointerEvent(first.down(center));
    await tester.pump(const Duration(milliseconds: 120));
    expect(ink.statesController!.value, contains(WidgetState.pressed));
    // A native pointer packet may finish one sequence and start the next before
    // its queued microtask runs. These are real pointer events, not state writes.
    tester.binding.handlePointerEvent(first.cancel());
    tester.binding.handlePointerEvent(next.down(center));
    await tester.pump(const Duration(milliseconds: 120));
    expect(ink.statesController!.value, contains(WidgetState.pressed));
    tester.binding.handlePointerEvent(next.up());
    await tester.pumpAndSettle();
    expect(activated, 1);
    expect(ink.statesController!.value, isNot(contains(WidgetState.pressed)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unmount during a pressed pointer drops queued cleanup safely',
      (tester) async {
    var activated = 0;
    await tester.pumpWidget(_plain(() => activated++));
    final pointer = await tester
        .startGesture(tester.getCenter(find.byType(AppItemInkWell)));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpWidget(const SizedBox.shrink());
    await pointer.cancel();
    await tester.pumpAndSettle();
    expect(activated, 0);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'keyboard and semantics still activate without a physical pointer owner',
      (tester) async {
    var activated = 0;
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_plain(() => activated++));
      final ink = tester.widget<InkWell>(find.byType(InkWell));
      ink.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(activated, 1);
      final node = tester.getSemantics(find.bySemanticsLabel('Item action'));
      node.owner!.performAction(node.id, raster.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(activated, 2);
      expect(ink.statesController!.value, isNot(contains(WidgetState.pressed)));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}

Widget _plain(VoidCallback activate) => MaterialApp(
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!),
    home: Scaffold(
        body: Align(
            alignment: Alignment.topLeft,
            child: Material(
                color: Colors.white,
                child: Semantics(
                    label: 'Item action',
                    child: AppItemInkWell(
                        onTap: activate,
                        child: const SizedBox(width: 220, height: 80)))))));
