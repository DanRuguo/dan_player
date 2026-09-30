import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/cover_caption_colors.dart';
import 'package:dan_player/component/playlist_cover_transition.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

Future<ui.Image> _art([Color color = Colors.red]) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(112, 112);
  } finally {
    picture.dispose();
  }
}

Future<Uint8List> _pixels(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        return Uint8List.fromList(
            (await image.toByteData())!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    }))!;

int _at(Uint8List bytes, Offset point, {int width = 300}) {
  final index = (point.dy.floor() * width + point.dx.floor()) * 4;
  return Color.fromARGB(
          bytes[index + 3], bytes[index], bytes[index + 1], bytes[index + 2])
      .toARGB32();
}

int _redTop(Uint8List bytes, int x) {
  for (var y = 0; y < 300; y++) {
    final index = (y * 300 + x) * 4;
    if (bytes[index] > 225 && bytes[index + 1] < 100) return y;
  }
  throw StateError('The tracked red cover disappeared');
}

class _CoverAudio extends CategoryTestAudio {
  _CoverAudio(super.id, this.image) : super(online: true);
  final ImageProvider image;
  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) async => image;
}

void main({String? onlyCase}) {
  void register(String name, WidgetTesterCallback body) {
    if (onlyCase == null || onlyCase == name) testWidgets(name, body);
  }

  for (final (lateArtwork, disposeDuringEntrance) in [
    (false, false),
    (true, false),
    (true, true),
  ]) {
    register(
        'first circular entrance remains aligned before image handoff (late=$lateArtwork, dispose=$disposeDuringEntrance)',
        (tester) async {
      final art = (await tester.runAsync(_art))!;
      addTearDown(art.dispose);
      final controller = PlaylistCoverTransitionController();
      addTearDown(controller.dispose);
      final boundary = GlobalKey();
      var circle = false;
      var loaded = true;
      var builds = 0;
      late StateSetter update;
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: SizedBox.square(
                  dimension: 300,
                  child: AppEntranceScope(
                      child: StatefulBuilder(builder: (context, setState) {
                    builds++;
                    update = setState;
                    final cover = SizedBox.square(
                        dimension: circle ? 112 : 48,
                        child: PlaylistCoverTransitionMarker(
                            entryId: 'a',
                            borderRadius: circle
                                ? BorderRadius.circular(56)
                                : BorderRadius.zero,
                            child: loaded
                                ? RawImage(image: art, fit: BoxFit.cover)
                                : const ColoredBox(color: Colors.blue)));
                    return RepaintBoundary(
                        key: boundary,
                        child: ColoredBox(
                            color: Colors.black,
                            child: PlaylistCoverTransitionHost(
                                controller: controller,
                                child: Stack(children: [
                                  Positioned(
                                      left: circle ? 150 : 20,
                                      top: circle ? 100 : 20,
                                      child: circle
                                          ? AppEntrance(
                                              identity: 'first-circular-card',
                                              order: 6,
                                              child: cover)
                                          : cover),
                                ]))));
                  }))))));
      await tester.pumpAndSettle();
      await controller.transition(() => update(() {
            circle = true;
            loaded = !lateArtwork;
          }));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 154));
      expect(controller.active, isTrue);
      final marker = find.byType(PlaylistCoverTransitionMarker);
      final target = tester.getRect(marker);
      final hostOrigin = tester.getTopLeft(find.byKey(boundary));
      final topSample = target.topCenter - hostOrigin + const Offset(0, 2);
      expect(_at(await _pixels(tester, boundary), topSample),
          Colors.red.toARGB32(),
          reason:
              'The flight must follow the circular card that is still rising');
      if (disposeDuringEntrance) {
        await tester.pumpWidget(const SizedBox.shrink());
        expect(controller.busy, isFalse);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pump();
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
        return;
      }
      if (!lateArtwork) {
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(
              _at(await _pixels(tester, boundary),
                  tester.getRect(marker).center - hostOrigin),
              Colors.red.toARGB32(),
              reason: 'Handoff must preserve the fading cover at frame $frame');
        }
      }
      if (lateArtwork) {
        final entranceBuilds = builds;
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final current = tester.getRect(marker).shift(-hostOrigin);
          expect(
              _redTop(
                  await _pixels(tester, boundary), current.center.dx.floor()),
              closeTo(current.top, 1),
              reason: 'The existing entrance keeps tracking after 220 ms');
        }
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(builds, entranceBuilds,
            reason: 'Following an entrance only repaints the tracking layer');
        expect(tester.binding.transientCallbackCount, 0);
        update(() => loaded = true);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(controller.busy, isFalse);
      expect(tester.getRect(marker).top - hostOrigin.dy, 100);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      // The page's remembered identity has no entrance on the repeated visit.
      update(() {
        circle = false;
        loaded = true;
      });
      await tester.pumpAndSettle();
      await controller.transition(() => update(() => circle = true));
      await tester.pump();
      await tester.pump();
      expect(tester.getRect(marker).top - hostOrigin.dy, 100);
      await tester.pump(const Duration(milliseconds: 154));
      final repeatedTarget = tester.getRect(marker);
      expect(
          _at(await _pixels(tester, boundary),
              repeatedTarget.topCenter - hostOrigin + const Offset(0, 2)),
          Colors.red.toARGB32());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  register('real tree to circular first visit follows the staggered last cover',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<MemoryImage> image(Color color) async {
      final art = await _art(color);
      try {
        return MemoryImage(Uint8List.fromList(
            (await art.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List()));
      } finally {
        art.dispose();
      }
    }

    final images = (await tester.runAsync(() async => [
          await image(Colors.blue),
          await image(Colors.red),
        ]))!;
    // Complete the real asynchronous color samples outside the fake clock;
    // their independent timeout is not part of the tracking timeline.
    await tester.runAsync(() => Future.wait(images
        .map((image) => CoverCaptionCache.resolve(image, 1, revision: 0))));
    final tree = PlaylistTree([]);
    final parent = tree.createPlaylist('First circular visit');
    final entries = [
      for (var index = 0; index < 7; index++)
        tree.addAudio(
            parent, _CoverAudio('Cover $index', images[index == 6 ? 1 : 0])),
    ];
    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RepaintBoundary(
                key: boundary,
                child: PlaylistBrowser(
                    tree: tree,
                    initialPlaylist: parent,
                    initialView: PlaylistViewMode.tree,
                    persist: () async {},
                    onPlay: (_, __) {})))));
    await tester.pumpAndSettle();
    for (var frame = 0; frame < 8; frame++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final controller = tester
        .widget<PlaylistCoverTransitionHost>(
            find.byType(PlaylistCoverTransitionHost))
        .controller;
    await tester.runAsync(() async {
      tester
          .widget<PlaylistToolbar>(find.byType(PlaylistToolbar))
          .onViewChanged!(PlaylistViewMode.circular);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 154));
    expect(controller.active, isTrue);
    final marker = find.byWidgetPredicate((widget) =>
        widget is PlaylistCoverTransitionMarker &&
        widget.entryId == entries.last.id);
    final target = tester.getRect(marker);
    final origin = tester.getTopLeft(find.byKey(boundary));
    expect(
        _at(await _pixels(tester, boundary),
            target.topCenter - origin + const Offset(0, 2),
            width: 1000),
        Colors.red.toARGB32(),
        reason: 'The real browser must hand off at its moving circular marker');
    await tester.pumpAndSettle();
    expect(controller.busy, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
