import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_cover_transition.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';

class _PaintedAudio extends CategoryTestAudio {
  _PaintedAudio(super.id, this.image)
      : super(artist: 'Studio', album: 'Color studies', online: true);
  final ImageProvider image;
  Future<ImageProvider?> Function()? pending;
  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) async =>
      pending == null ? image : await pending!();
}

Future<Uint8List> _art(Color color) async {
  final recorder = drawing.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(color, BlendMode.src);
  canvas.drawCircle(const Offset(34, 30), 16,
      Paint()..color = Colors.white.withValues(alpha: .85));
  canvas.drawLine(
      const Offset(10, 230),
      const Offset(246, 210),
      Paint()
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: .6));
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  final bytes = (await image.toByteData(format: drawing.ImageByteFormat.png))!
      .buffer
      .asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

class _Pixels {
  _Pixels(this.width, this.data);
  final int width;
  final ByteData data;
  int at(Offset point) {
    final offset = (point.dy.round() * width + point.dx.round()) * 4;
    return Color.fromARGB(data.getUint8(offset + 3), data.getUint8(offset),
            data.getUint8(offset + 1), data.getUint8(offset + 2))
        .toARGB32();
  }
}

Future<_Pixels> _capture(
    WidgetTester tester, GlobalKey key, String name) async {
  late _Pixels pixels;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    pixels = _Pixels(image.width,
        (await image.toByteData(format: drawing.ImageByteFormat.rawRgba))!);
    const output = String.fromEnvironment('DAN_PLAYLIST_TRANSITION_RENDER');
    if (output.isNotEmpty) {
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(
          (await image.toByteData(format: drawing.ImageByteFormat.png))!
              .buffer
              .asUint8List());
    }
    image.dispose();
  });
  return pixels;
}

Finder _marker(Object id) => find.byWidgetPredicate((widget) =>
    widget is PlaylistCoverTransitionMarker && widget.entryId == id);

Future<void> _decode(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

Future<void> _openEntryMenu(WidgetTester tester, Object entryId) async {
  final mouse = await tester.startGesture(tester.getCenter(_marker(entryId)),
      kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
  await mouse.up();
  await tester.pumpAndSettle();
}

void main() {
  late Directory data;
  late List<Uint8List> images;
  const colors = [Color(0xff7e57c2), Color(0xff00838f), Color(0xffe65100)];
  setUpAll(() async {
    data = Directory(
            '.dart_tool/test-data/playlist-view-transition-${DateTime.now().microsecondsSinceEpoch}')
        .absolute;
    await data.create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => data.path);
    images = await Future.wait(colors.map(_art));
    await File('${data.path}/folder.png').writeAsBytes(images[0]);
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  tearDownAll(() async {
    await AppPreference.instance.save();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    if (await data.exists()) await data.delete(recursive: true);
  });

  for (final from in PlaylistViewMode.values) {
    for (final to in PlaylistViewMode.values.where((value) => value != from)) {
      for (final depth in [.5, 1.0]) {
        testWidgets('scrolled ${from.name} to ${to.name} at $depth',
            (tester) async {
          tester.view.physicalSize = const Size(1100, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final tree = PlaylistTree([]);
          final parent = tree.createPlaylist('Scroll anchors');
          for (var i = 0; i < 150; i++) {
            tree.addAudio(
                parent, _PaintedAudio('Song $i', MemoryImage(images[i % 3])));
          }
          await tester.pumpWidget(MaterialApp(
              home: Scaffold(
                  body: PlaylistBrowser(
                      tree: tree,
                      initialPlaylist: parent,
                      initialView: from,
                      persist: () async {},
                      onPlay: (_, __) {}))));
          await tester.pumpAndSettle();
          final host = find.byType(PlaylistCoverTransitionHost);
          final scroll = tester.state<ScrollableState>(find
              .descendant(of: host, matching: find.byType(Scrollable))
              .first);
          scroll.position.jumpTo(scroll.position.maxScrollExtent * depth);
          await tester.pumpAndSettle();
          await _decode(tester);
          await tester.pumpAndSettle();
          final viewport = tester.getRect(host);
          final visible = find
              .byType(PlaylistCoverTransitionMarker)
              .evaluate()
              .where((e) =>
                  tester.getRect(find.byWidget(e.widget)).overlaps(viewport))
              .toList()
            ..sort((a, b) {
              final ar = tester.getRect(find.byWidget(a.widget));
              final br = tester.getRect(find.byWidget(b.widget));
              final vertical = ar.top.compareTo(br.top);
              return vertical != 0 ? vertical : ar.left.compareTo(br.left);
            });
          expect(visible, isNotEmpty);
          final id =
              (visible.first.widget as PlaylistCoverTransitionMarker).entryId;
          final controller =
              tester.widget<PlaylistCoverTransitionHost>(host).controller;
          final toolbar =
              tester.widget<PlaylistToolbar>(find.byType(PlaylistToolbar));
          await tester.runAsync(() async {
            toolbar.onViewChanged!(to);
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          for (var i = 0; i < 10; i++) {
            await tester.pump();
          }
          expect(controller.active, isTrue);
          expect(_marker(id), findsOneWidget);
          expect(tester.getRect(_marker(id)).overlaps(viewport), isTrue);
          await _decode(tester);
          await tester.pumpAndSettle();
          expect(controller.busy, isFalse);
          expect(tester.takeException(), isNull);
        });
      }
      testWidgets(
          'real playlist ${from.name} to ${to.name} keeps song and folder artwork',
          (tester) async {
        tester.view.physicalSize = const Size(1100, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final tree = PlaylistTree([]);
        final parent = tree.createPlaylist('Color studies');
        final custom = tree.createPlaylist('Cover from file',
            parent: parent, imagePath: '${data.path}/folder.png');
        final fallback =
            tree.createPlaylist('Cover from a song', parent: parent);
        final shared = _PaintedAudio('Morning tide', MemoryImage(images[1]));
        final orange = _PaintedAudio('Golden hour', MemoryImage(images[2]));
        tree.addAudio(fallback, shared);
        final sharedEntry = tree.addAudio(parent, shared);
        final trackedEntry = tree.addAudio(parent, orange);
        final ids = [custom.id, fallback.id, sharedEntry.id, trackedEntry.id];
        final expected = [colors[0], colors[1], colors[1], colors[2]];
        final boundary = GlobalKey();
        await tester.pumpWidget(MaterialApp(
          theme: applyAppControlTheme(ThemeData(
              fontFamily: danEmbeddedFontFamily,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.teal, brightness: Brightness.dark))),
          home: Scaffold(
              body: RepaintBoundary(
                  key: boundary,
                  child: AppEntranceScope(
                      child: PlaylistBrowser(
                    tree: tree,
                    initialPlaylist: parent,
                    initialView: from,
                    persist: () async {},
                    onPlay: (_, __) {},
                  )))),
        ));
        await tester.pumpAndSettle();
        await _decode(tester);
        await tester.pumpAndSettle();
        // All presentations share AudioTile's full song context menu.
        expect(find.byType(AudioTile), findsNWidgets(2));
        final startRects = [for (final id in ids) tester.getRect(_marker(id))];
        final start = await _capture(
            tester, boundary, '${from.name}-to-${to.name}-start');
        for (var i = 0; i < ids.length; i++) {
          expect(start.at(startRects[i].center), expected[i].toARGB32(),
              reason: 'source ${ids[i]}');
        }
        final controller = tester
            .widget<PlaylistCoverTransitionHost>(
                find.byType(PlaylistCoverTransitionHost))
            .controller;
        final toolbar =
            tester.widget<PlaylistToolbar>(find.byType(PlaylistToolbar));
        await tester.runAsync(() async {
          toolbar.onViewChanged!(to);
          for (var i = 0;
              i < 80 && parent.presentation['view'] != to.name;
              i++) {
            await Future<void>.delayed(const Duration(milliseconds: 4));
          }
        });
        expect(parent.presentation['view'], to.name);
        await tester.pump();
        await _decode(tester);
        expect(controller.active, isTrue);
        expect(controller.debugSnapshotCount, ids.length,
            reason: 'same-song folder and song retain independent entry IDs');
        final targets = [for (final id in ids) tester.getRect(_marker(id))];
        await tester.pump(const Duration(milliseconds: 110));
        final middle = await _capture(
            tester, boundary, '${from.name}-to-${to.name}-middle');
        // This last item stays above its peers when trajectories cross.
        final midpoint = Rect.lerp(startRects.last, targets.last, .5)!.center;
        expect(middle.at(midpoint), expected.last.toARGB32(),
            reason: 'moving cover center must contain real artwork');
        await tester.pumpAndSettle();
        final settled =
            await _capture(tester, boundary, '${from.name}-to-${to.name}-end');
        for (var i = 0; i < ids.length; i++) {
          expect(settled.at(tester.getCenter(_marker(ids[i]))),
              expected[i].toARGB32(),
              reason: 'target ${ids[i]} must not show fallback artwork');
        }
        expect(controller.busy, isFalse);
        expect(controller.debugSnapshotCount, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets(
      'late real song artwork holds snapshot without idle polling then hands off',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tree = PlaylistTree([]);
    final parent = tree.createPlaylist('Slow cover handoff');
    final song = _PaintedAudio('Golden hour', MemoryImage(images[2]));
    final entry = tree.addAudio(parent, song);
    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RepaintBoundary(
                key: boundary,
                child: AppEntranceScope(
                    child: PlaylistBrowser(
                        tree: tree,
                        initialPlaylist: parent,
                        initialView: PlaylistViewMode.list,
                        persist: () async {},
                        onPlay: (_, __) {}))))));
    await tester.pumpAndSettle();
    await _decode(tester);
    await tester.pumpAndSettle();
    final pending = Completer<ImageProvider?>();
    song.pending = () => pending.future;
    final controller = tester
        .widget<PlaylistCoverTransitionHost>(
            find.byType(PlaylistCoverTransitionHost))
        .controller;
    await tester.runAsync(() async {
      tester
          .widget<PlaylistToolbar>(find.byType(PlaylistToolbar))
          .onViewChanged!(PlaylistViewMode.grid);
      for (var i = 0; i < 80 && !controller.active; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
    });
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(controller.active, isTrue);
    expect(controller.debugSnapshotCount, 1);
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'pending image does not poll or tick');
    final waiting = await _capture(tester, boundary, 'slow-image-held');
    expect(
        waiting.at(tester.getCenter(_marker(entry.id))), colors[2].toARGB32());
    await tester.runAsync(() async {
      pending.complete(song.image);
    });
    await _decode(tester);
    await tester.pumpAndSettle();
    expect(controller.active, isFalse);
    final settled = await _capture(tester, boundary, 'slow-image-ready');
    expect(
        settled.at(tester.getCenter(_marker(entry.id))), colors[2].toARGB32());
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final action in [
    'size',
    'auto fill',
    'root auto fill',
    'sort',
    'grid drag',
    'list drag',
    'remove',
    'move',
    'passive layout save',
  ]) {
    testWidgets('slow cover transition handles $action without stale snapshots',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tree = PlaylistTree([]);
      final outer = tree.createPlaylist('Outer');
      final parent = tree.createPlaylist('Slow edits', parent: outer);
      final song = _PaintedAudio('Golden hour', MemoryImage(images[2]));
      final entry = tree.addAudio(parent, song);
      final root = action == 'root auto fill';
      final listDrag = action == 'list drag';
      final passive = action == 'passive layout save';
      if (passive) {
        parent.presentation['tiles'] =
            const CategoryPresentation(autoFill: false).toMap();
      }
      var saves = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: AppEntranceScope(
                  child: PlaylistBrowser(
                      tree: tree,
                      initialPlaylist: root ? null : parent,
                      initialView: listDrag
                          ? PlaylistViewMode.grid
                          : PlaylistViewMode.list,
                      persist: () async => saves++,
                      onPlay: (_, __) {})))));
      await tester.pumpAndSettle();
      await _decode(tester);
      await tester.pumpAndSettle();
      final pending = Completer<ImageProvider?>();
      song.pending = () => pending.future;
      addTearDown(() {
        if (!pending.isCompleted) pending.complete(null);
      });
      final controller = tester
          .widget<PlaylistCoverTransitionHost>(
              find.byType(PlaylistCoverTransitionHost))
          .controller;
      final target = listDrag ? PlaylistViewMode.list : PlaylistViewMode.grid;
      await tester.runAsync(() async {
        tester
            .widget<PlaylistToolbar>(find.byType(PlaylistToolbar))
            .onViewChanged!(target);
        for (var i = 0; i < 80 && !controller.active; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 4));
        }
      });
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(controller.active, isTrue,
          reason: 'view persistence must retain the slow artwork flight');
      expect(controller.debugSnapshotCount, 1);
      if (!root) expect(parent.presentation['view'], target.name);
      final toolbar =
          tester.widget<PlaylistToolbar>(find.byType(PlaylistToolbar));

      switch (action) {
        case 'size':
          await _openEntryMenu(tester, entry.id);
          await tester.tap(find.widgetWithText(SubmenuButton, ui('封面尺寸')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey(
              ('playlist-tile-size', entry.id, CategoryTileSize.large.name))));
          await tester.pumpAndSettle();
          expect(
              CategoryPresentation.fromMap(parent.presentation['tiles'])
                  .sizes[entry.id],
              CategoryTileSize.large);
        case 'auto fill':
        case 'root auto fill':
          toolbar.onAutoFillChanged!(!toolbar.autoFill);
          await tester.pumpAndSettle();
          expect(
              tester
                  .widget<PlaylistToolbar>(find.byType(PlaylistToolbar))
                  .autoFill,
              !toolbar.autoFill);
        case 'sort':
          toolbar.onSortChanged(PlaylistSortMode.nameAscending);
          await tester.pumpAndSettle();
          expect(
              tester
                  .widget<PlaylistToolbar>(find.byType(PlaylistToolbar))
                  .sortMode,
              PlaylistSortMode.nameAscending);
        case 'grid drag':
        case 'list drag':
          final source = listDrag
              ? find.byKey(ValueKey('playlist-drag-${entry.id}'))
              : _marker(entry.id);
          final mouse = await tester.startGesture(tester.getCenter(source),
              kind: PointerDeviceKind.mouse);
          await mouse.moveBy(const Offset(42, 38));
          await tester.pump(const Duration(milliseconds: 20));
          expect(controller.active, isFalse,
              reason: 'release the flight when dragging starts, before drop');
          await mouse.cancel();
          await tester.pumpAndSettle();
        case 'remove':
          await _openEntryMenu(tester, entry.id);
          await tester.tap(find.widgetWithText(MenuItemButton, ui('从当前歌单移除')));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, ui('移除')));
          await tester.pumpAndSettle();
          expect(parent.entries, isEmpty);
        case 'move':
          await _openEntryMenu(tester, entry.id);
          await tester.tap(find.widgetWithText(MenuItemButton, ui('移到上一级')));
          await tester.pumpAndSettle();
          expect(parent.entries, isEmpty);
          expect(outer.entries.any((item) => item.id == entry.id), isTrue);
        case 'passive layout save':
          expect(
              CategoryPresentation.fromMap(parent.presentation['tiles'])
                  .layouts[entry.id],
              isNotNull);
          expect(saves, greaterThanOrEqualTo(2),
              reason: 'both view and initial free layout are persisted');
          expect(controller.active, isTrue,
              reason: 'passive coordinate recording does not change geometry');
      }
      if (!passive) {
        expect(controller.busy, isFalse);
        expect(controller.debugSnapshotCount, 0,
            reason: 'no old target survives until the 10-second image timeout');
      }
      await tester.runAsync(() async => pending.complete(song.image));
      await _decode(tester);
      await tester.pumpAndSettle();
      expect(controller.busy, isFalse);
      expect(controller.debugSnapshotCount, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'real playlist with reduced motion directly changes all three views',
      (tester) async {
    final tree = PlaylistTree([]);
    final parent = tree.createPlaylist('Reduced motion');
    final song = _PaintedAudio('Morning tide', MemoryImage(images[1]));
    final entry = tree.addAudio(parent, song);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
                body: AppEntranceScope(
                    child: PlaylistBrowser(
                        tree: tree,
                        initialPlaylist: parent,
                        initialView: PlaylistViewMode.list,
                        persist: () async {},
                        onPlay: (_, __) {}))))));
    await tester.pumpAndSettle();
    await _decode(tester);
    for (final target in [
      PlaylistViewMode.grid,
      PlaylistViewMode.circular,
      PlaylistViewMode.list
    ]) {
      tester
          .widget<PlaylistToolbar>(find.byType(PlaylistToolbar))
          .onViewChanged!(target);
      await tester.pumpAndSettle();
      await _decode(tester);
      final controller = tester
          .widget<PlaylistCoverTransitionHost>(
              find.byType(PlaylistCoverTransitionHost))
          .controller;
      expect(controller.busy, isFalse);
      expect(controller.debugSnapshotCount, 0);
      expect(
          find.descendant(of: _marker(entry.id), matching: find.byType(Image)),
          findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('ordinary missing covers finish without waiting for an image',
      (tester) async {
    final tree = PlaylistTree([]);
    final parent = tree.createPlaylist('No cover');
    tree.addAudio(parent, CategoryTestAudio('No image', online: true));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AppEntranceScope(
                child: PlaylistBrowser(
                    tree: tree,
                    initialPlaylist: parent,
                    initialView: PlaylistViewMode.list,
                    persist: () async {},
                    onPlay: (_, __) {})))));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<PlaylistCoverTransitionHost>(
            find.byType(PlaylistCoverTransitionHost))
        .controller;
    await tester.runAsync(() async {
      tester
          .widget<PlaylistToolbar>(find.byType(PlaylistToolbar))
          .onViewChanged!(PlaylistViewMode.circular);
      for (var i = 0;
          i < 80 && parent.presentation['view'] != 'circular';
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
    });
    await tester.pumpAndSettle();
    expect(controller.active, isFalse);
    expect(controller.debugSnapshotCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
