import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/category_pointer_glow.dart';
import 'package:dan_player/component/category_tile_grid.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

Future<int> _pixel(WidgetTester tester, GlobalKey key, int x) async =>
    (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      try {
        final bytes =
            await image.toByteData(format: drawing.ImageByteFormat.rawRgba);
        return bytes!.getUint8((80 * image.width + x) * 4);
      } finally {
        image.dispose();
      }
    }))!;

// Isolate the real card's foreground layer from its ink/drag opacity. The
// painter still resolves the mounted card's current global transform.
Future<Uint8List> _foreground(WidgetTester tester, Finder card) async {
  final glow =
      find.descendant(of: card, matching: find.byType(CategoryPointerGlow));
  final paint = tester
      .widgetList<CustomPaint>(find.descendant(
        of: glow,
        matching: find.byType(CustomPaint),
      ))
      .singleWhere((widget) => widget.foregroundPainter != null);
  final size = tester.getSize(glow);
  return (await tester.runAsync(() async {
    final recorder = drawing.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(Colors.black, BlendMode.src);
    paint.foregroundPainter!.paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    try {
      return Uint8List.fromList(
          (await image.toByteData())!.buffer.asUint8List());
    } finally {
      image.dispose();
      picture.dispose();
    }
  }))!;
}

Widget _host(Widget body) => MaterialApp(
    theme: ThemeData(platform: TargetPlatform.windows),
    home: Scaffold(body: body));

void main() {
  late Directory data;
  setUpAll(() async {
    data = await Directory.systemTemp.createTemp('cover-pressed-motion-');
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

  for (final shared in [false, true]) {
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.stylus]) {
      testWidgets(
          'pressed ${kind.name} follows and retires outside shared=$shared',
          (tester) async {
        final boundary = GlobalKey();
        Widget body =
            const CategoryPointerGlow(child: ColoredBox(color: Colors.black));
        if (shared) body = CoverPointerScope(child: body);
        await tester.pumpWidget(_host(Center(
            child: RepaintBoundary(
                key: boundary,
                child: SizedBox(width: 420, height: 160, child: body)))));
        await tester.pumpAndSettle();
        final origin = tester.getTopLeft(find.byKey(boundary));
        final pointer = await tester.createGesture(kind: kind);
        await pointer.addPointer(location: Offset.zero);
        await pointer.moveTo(origin + const Offset(80, 80));
        await tester.pump();
        expect(await _pixel(tester, boundary, 80), greaterThan(20));
        await pointer.down(origin + const Offset(80, 80));
        await pointer.moveTo(origin + const Offset(340, 80));
        await tester.pump();
        expect(await _pixel(tester, boundary, 340), greaterThan(20));
        expect(await _pixel(tester, boundary, 80), 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await pointer.moveTo(origin + const Offset(500, 80));
        await tester.pump();
        expect(await _pixel(tester, boundary, 340), 0);
        await pointer.up();
        await pointer.removePointer();
        await tester.pumpAndSettle();
        // Touch remains free of hover feedback and continues to reach its
        // existing gesture recognizers.
        final touch = await tester.startGesture(origin + const Offset(80, 80));
        await touch.moveTo(origin + const Offset(340, 80));
        await tester.pump();
        expect(await _pixel(tester, boundary, 340), 0);
        await touch.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final category in [true, false]) {
    testWidgets(
        'held glow keeps real ${category ? 'category' : 'playlist'} drag and drop ownership',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tree = PlaylistTree([]);
      final parent = tree.createPlaylist('Parent');
      final first = tree.createPlaylist('First', parent: parent);
      final last = tree.createPlaylist('Last', parent: parent);
      final groups = MusicCategories([
        CategoryTestAudio('One', artist: 'First'),
        CategoryTestAudio('Two', artist: 'Last'),
      ]).groups(MusicCategoryKind.artist);
      final covers = CategoryCoverStore(dataDirectory: () async => data);
      addTearDown(covers.dispose);
      var presentation = const CategoryPresentation(
          shape: CategoryCoverShape.rounded,
          sort: CategorySort.custom,
          showTitle: false,
          showDetails: false);
      final opened = <Object>[];
      var saves = 0;
      await tester.pumpWidget(_host(StatefulBuilder(builder: (_, setState) {
        if (!category) {
          return PlaylistBrowser(
              tree: tree,
              initialPlaylist: parent,
              initialView: PlaylistViewMode.grid,
              persist: () async => saves++,
              onNavigate: (playlist) => opened.add(playlist!));
        }
        return CoverPointerScope(
            child: CustomScrollView(slivers: [
          CategoryTileGrid(
              groups: groups,
              presentation: presentation,
              covers: covers,
              changing: const {},
              icon: Icons.person,
              onOpen: opened.add,
              onChanged: (next) => setState(() => presentation = next),
              onChangeCover: (_) {},
              onRemoveCover: (_) {}),
        ]));
      })));
      await tester.pumpAndSettle();
      final card = category
          ? find.byKey(ValueKey(('category-group', groups.last.id)))
          : find.byKey(ValueKey('playlist-card-drag-${first.id}'));
      final bounds = tester.getRect(card);
      final initial = Offset(bounds.left + 18, bounds.top + 24);
      final moved = Offset(bounds.right - 18, bounds.top + 24);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(moved);
      await tester.pump();
      final hovered = await _foreground(tester, card);
      await mouse.moveTo(initial);
      await tester.pump();
      expect(await _foreground(tester, card), isNot(orderedEquals(hovered)));
      await mouse.down(initial);
      await mouse.moveTo(moved);
      await tester.pump(const Duration(milliseconds: 16));
      expect(await _foreground(tester, card), orderedEquals(hovered),
          reason: 'held and ordinary pointer positions must paint identically');
      await tester.pump(const Duration(milliseconds: 260));
      await mouse.moveTo(moved + const Offset(1, 0));
      await tester.pump();
      final destination = category
          ? find.byKey(ValueKey(('category-group', groups.first.id)))
          : find.byKey(ValueKey('playlist-drop-folder-${last.id}'));
      await mouse.moveTo(tester.getCenter(destination));
      await tester.pump();
      await mouse.up();
      await mouse.removePointer();
      await tester.pumpAndSettle();
      if (category) {
        expect(presentation.orders[MusicCategoryKind.artist.name],
            [groups.last.persistenceKey, groups.first.persistenceKey]);
      } else {
        expect(first.parent, same(last));
        expect(saves, 1);
      }
      expect(opened, isEmpty,
          reason: 'the listener cannot turn a drag into tap');
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
