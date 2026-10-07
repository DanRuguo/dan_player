import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_route_transition.dart';
import 'package:dan_player/component/artwork_handoff.dart';
import 'package:dan_player/component/category_tile_grid.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/uni_detail_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

class _Audio extends CategoryTestAudio {
  _Audio(this.image) : super('One', artist: 'Artist', album: 'Album');
  final ImageProvider image;
  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) =>
      SynchronousFuture(image);
}

Future<Uint8List> _png(Color color) async {
  final recorder = drawing.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 64);
  try {
    return (await image.toByteData(format: drawing.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _decode(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

Future<Color> _pixel(WidgetTester tester, GlobalKey boundary, Offset point,
        String stage) async =>
    (await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      try {
        final rgba = (await image.toByteData())!;
        final offset = (point.dy.floor() * image.width + point.dx.floor()) * 4;
        final color = Color.fromARGB(
            rgba.getUint8(offset + 3),
            rgba.getUint8(offset),
            rgba.getUint8(offset + 1),
            rgba.getUint8(offset + 2));
        const output = String.fromEnvironment('DAN_CATEGORY_SOURCE_RENDER');
        if (output.isNotEmpty) {
          await Directory(output).create(recursive: true);
          await File('$output/$stage.png').writeAsBytes(
              (await image.toByteData(format: drawing.ImageByteFormat.png))!
                  .buffer
                  .asUint8List());
        }
        debugPrint(
            'CATEGORY_SOURCE_HANDOFF $stage RGBA=${rgba.getUint8(offset)},${rgba.getUint8(offset + 1)},${rgba.getUint8(offset + 2)},${rgba.getUint8(offset + 3)}');
        return color;
      } finally {
        image.dispose();
      }
    }))!;

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  testWidgets('category source cover fade keeps newest flight at landing',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 800);
    final data = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('category-source-handoff-')))!;
    final store = (await tester.runAsync(
        () async => CategoryCoverStore(dataDirectory: () async => data)))!;
    addTearDown(() async {
      store.dispose();
      await data.delete(recursive: true);
    });
    final red = MemoryImage((await tester.runAsync(() => _png(Colors.red)))!);
    final blueBytes = (await tester.runAsync(() => _png(Colors.blue)))!;
    final blue = MemoryImage(blueBytes);
    final sourceFile = File('${data.path}/blue.png');
    await tester.runAsync(() => sourceFile.writeAsBytes(blueBytes));
    final group =
        MusicCategories([_Audio(red)]).groups(MusicCategoryKind.album).single;
    final pending = Completer<ImageProvider?>();
    addTearDown(() {
      if (!pending.isCompleted) pending.complete(null);
    });
    final navigator = GlobalKey<NavigatorState>();
    final boundary = GlobalKey();
    late StateSetter change;
    void refresh() => change(() {});
    store.addListener(refresh);
    addTearDown(() => store.removeListener(refresh));
    Widget detail() => UniDetailPage<String, String, String>(
          pref: PagePreference(0, SortOrder.ascending, ContentView.list),
          primaryContent: group.id,
          primaryPic: pending.future,
          backgroundPic: Future.value(null),
          coverFlightTag: ('category-detail-cover', group.persistenceKey),
          picShape: PicShape.rrect,
          title: group.title,
          subtitle: '1 song',
          secondaryContent: const [],
          secondaryContentBuilder: (_, __, ___, ____, _____) =>
              const SizedBox.shrink(),
          tertiaryContentTitle: '',
          tertiaryContent: const [],
          tertiaryContentBuilder: (_, __, ___, ____) => const SizedBox.shrink(),
          enableShufflePlay: false,
          enableSortMethod: false,
          enableSortOrder: false,
          enableSecondaryContentViewSwitch: false,
        );
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          navigatorKey: navigator,
          theme: ThemeData(
              platform: TargetPlatform.windows,
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: danFontFamilyFallback),
          home: Scaffold(body: StatefulBuilder(builder: (_, setState) {
            change = setState;
            return CustomScrollView(slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(top: 260, left: 400),
                sliver: CategoryTileGrid(
                  groups: [group],
                  presentation: const CategoryPresentation(
                      showTitle: false, showDetails: false),
                  covers: store,
                  changing: const {},
                  icon: Icons.album,
                  persistLayout: false,
                  onChanged: (_) {},
                  onChangeCover: (_) {},
                  onRemoveCover: (_) {},
                  onOpen: (_) =>
                      navigator.currentState!.push(PageRouteBuilder<void>(
                    transitionDuration: AppRouteTransition.enterDuration,
                    reverseTransitionDuration: AppRouteTransition.exitDuration,
                    pageBuilder: (_, __, ___) => Scaffold(body: detail()),
                    transitionsBuilder: (_, animation, __, child) =>
                        AppRouteTransition(animation: animation, child: child),
                  )),
                ),
              )
            ]);
          })),
        )));
    await _decode(tester);
    await tester.pumpAndSettle();
    final source = find.byKey(ValueKey(('category-cover', group.id)));
    expect(
        (await _pixel(tester, boundary, tester.getCenter(source), 'initial'))
            .toARGB32(),
        Colors.red.toARGB32());
    final handoff =
        find.descendant(of: source, matching: find.byType(ArtworkHandoff));
    final sourceState = tester.state(handoff);
    // Real import/revision publication updates the same keyed category tile.
    await tester.runAsync(() => store
        .setCover(group, sourceFile.path)
        .timeout(const Duration(seconds: 8)));
    await tester.runAsync(() => store.imageFor(group));
    // Stop when the newly decoded provider joins its previous image. Native
    // pumps use real time, so a fixed decode delay could skip the finite fade.
    for (var i = 0; i < 80; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 4)));
      await tester.pump();
      if (find
              .descendant(of: source, matching: find.byType(Image))
              .evaluate()
            .length ==
            2) {
        break;
      }
    }
    expect(find.descendant(of: source, matching: find.byType(Image)),
        findsNWidgets(2));
    await tester.pump(const Duration(milliseconds: 50));
    final mixed = await _pixel(
        tester, boundary, tester.getCenter(source), 'source-mixed');
    expect(tester.state(handoff), same(sourceState));
    expect(mixed.toARGB32(), isNot(Colors.red.toARGB32()));
    expect(mixed.toARGB32(), isNot(Colors.blue.toARGB32()));
    await tester.tap(find.byKey(ValueKey(('category-card', group.id))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final flight = find.byKey(const ValueKey('category-flight-image'));
    expect(flight, findsOneWidget);
    final flying =
        await _pixel(tester, boundary, tester.getCenter(flight), 'flying');
    await tester.pump(const Duration(milliseconds: 480));
    await tester.pump();
    final target = find.byKey(const ValueKey('uni-detail-cover'));
    final arrival =
        await _pixel(tester, boundary, tester.getCenter(target), 'arrival');
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.runAsync(() async => pending.complete(blue));
    await _decode(tester);
    await tester.pumpAndSettle();
    final ready =
        await _pixel(tester, boundary, tester.getCenter(target), 'ready');
    expect(flying.toARGB32(), Colors.blue.toARGB32());
    expect(ready.toARGB32(), Colors.blue.toARGB32());
    expect(arrival.toARGB32(), flying.toARGB32(),
        reason:
            'arrival cannot revert from newest flying artwork to the previous source');
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await _decode(tester);
  });
}
