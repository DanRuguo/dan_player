import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/app_route_transition.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/category_cover_flight.dart';
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
  _Audio(this.image)
      : super('Late detail artwork',
            artist: 'Performer 艺术家 アーティスト 아티스트',
            album: 'Album / 专辑 / アルバム / 앨범');
  final ImageProvider image;
  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) =>
      SynchronousFuture(image);
}

Future<ImageProvider> _image(Color color) async {
  final recorder = drawing.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final frame = await picture.toImage(64, 64);
  try {
    final bytes = await frame.toByteData(format: drawing.ImageByteFormat.png);
    return MemoryImage(bytes!.buffer.asUint8List());
  } finally {
    frame.dispose();
    picture.dispose();
  }
}

Future<void> _decode(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

Future<int> _pixel(
    WidgetTester tester, GlobalKey boundary, Offset point, String stage) async {
  return (await tester.runAsync(() async {
    final frame = await (boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary)
        .toImage();
    try {
      final bytes = await frame.toByteData();
      final offset = (point.dy.floor() * frame.width + point.dx.floor()) * 4;
      const output = String.fromEnvironment('DAN_CATEGORY_LANDING_RENDER');
      if (output.isNotEmpty) {
        await Directory(output).create(recursive: true);
        await File('$output/$stage.png').writeAsBytes(
            (await frame.toByteData(format: drawing.ImageByteFormat.png))!
                .buffer
                .asUint8List());
      }
      return Color.fromARGB(bytes!.getUint8(offset + 3), bytes.getUint8(offset),
              bytes.getUint8(offset + 1), bytes.getUint8(offset + 2))
          .toARGB32();
    } finally {
      frame.dispose();
    }
  }))!;
}

void main({bool includePlaceholderCase = true}) {
  setUpAll(loadPlaylistFeatureFonts);
  for (final kind in [MusicCategoryKind.artist, MusicCategoryKind.album]) {
    testWidgets('late ${kind.name} detail preserves its arrived source cover',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('category-late-landing-')))!;
      final store = CategoryCoverStore(dataDirectory: () async => data);
      addTearDown(() async {
        store.dispose();
        await data.delete(recursive: true);
      });
      final sourceImage = (await tester.runAsync(() => _image(Colors.red)))!;
      final destinationImage =
          (await tester.runAsync(() => _image(Colors.blue)))!;
      final pending = Completer<ImageProvider?>();
      addTearDown(() {
        if (!pending.isCompleted) pending.complete(null);
      });
      final group = MusicCategories([_Audio(sourceImage)]).groups(kind).single;
      final navigator = GlobalKey<NavigatorState>();
      final boundary = GlobalKey();
      Widget detail() => UniDetailPage<String, String, String>(
          pref: PagePreference(0, SortOrder.ascending, ContentView.list),
          primaryContent: group.id,
          primaryPic: pending.future,
          backgroundPic: Future.value(null),
          coverFlightTag: ('category-detail-cover', group.persistenceKey),
          picShape:
              kind == MusicCategoryKind.artist ? PicShape.oval : PicShape.rrect,
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
          enableSecondaryContentViewSwitch: false);
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              navigatorKey: navigator,
              theme: ThemeData(
                  platform: TargetPlatform.windows,
                  fontFamily: danEmbeddedFontFamily,
                  fontFamilyFallback: danFontFamilyFallback,
                  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(
                          MediaQuery.sizeOf(context).width < 500 ? 2 : 1)),
                  child: child!),
              home: Scaffold(
                  body: CustomScrollView(slivers: [
                SliverPadding(
                    padding: const EdgeInsets.only(top: 260, left: 400),
                    sliver: CategoryTileGrid(
                        groups: [group],
                        presentation: const CategoryPresentation(),
                        onChanged: (_) {},
                        onOpen: (_) => navigator.currentState!.push(
                            PageRouteBuilder<void>(
                                transitionDuration:
                                    AppRouteTransition.enterDuration,
                                reverseTransitionDuration:
                                    AppRouteTransition.exitDuration,
                                pageBuilder: (_, __, ___) =>
                                    Scaffold(body: detail()),
                                transitionsBuilder: (_, animation, __, child) =>
                                    AppRouteTransition(
                                        animation: animation, child: child))),
                        covers: store,
                        changing: const {},
                        onChangeCover: (_) {},
                        onRemoveCover: (_) {},
                        icon: Icons.album,
                        persistLayout: false))
              ])))));
      await _decode(tester);
      await tester.pumpAndSettle();
      final cover = find.byKey(ValueKey(('category-cover', group.id)));
      expect(
          await _pixel(
              tester, boundary, tester.getCenter(cover), '${kind.name}-source'),
          Colors.red.toARGB32());
      await tester.tap(find.byKey(ValueKey(('category-card', group.id))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final flight = find.byKey(const ValueKey('category-flight-image'));
      expect(flight, findsOneWidget);
      expect(
          await _pixel(tester, boundary, tester.getCenter(flight),
              '${kind.name}-flying'),
          Colors.red.toARGB32());
      await tester.pump(const Duration(milliseconds: 480));
      await tester.pump();
      final target = find.byKey(const ValueKey('uni-detail-cover'));
      expect(find.byKey(const ValueKey('category-flight-image')), findsNothing);
      expect(
          await _pixel(tester, boundary, tester.getCenter(target),
              '${kind.name}-waiting'),
          Colors.red.toARGB32(),
          reason: 'the already decoded source survives a slower detail image');
      expect(
          await _pixel(
              tester,
              boundary,
              tester.getTopLeft(target) + const Offset(3, 3),
              '${kind.name}-waiting-corner'),
          isNot(Colors.red.toARGB32()),
          reason: 'the retained texture follows the target circle or corners');
      expect(tester.binding.transientCallbackCount, 0,
          reason: 'the hidden loading spinner must not keep ticking');
      expect(tester.binding.hasScheduledFrame, isFalse);
      // Narrow-window relayout keeps the same destination and retained handle,
      // while adopting its current natural cover bounds and artist radius.
      tester.view.physicalSize = const Size(360, 1000);
      await tester.pump();
      await tester.pump();
      expect(
          await _pixel(tester, boundary, tester.getCenter(target),
              '${kind.name}-waiting-narrow'),
          Colors.red.toARGB32());
      expect(
          await _pixel(
              tester,
              boundary,
              tester.getTopLeft(target) + const Offset(3, 3),
              '${kind.name}-waiting-narrow-corner'),
          isNot(Colors.red.toARGB32()));
      await tester.runAsync(() async => pending.complete(destinationImage));
      await _decode(tester);
      await tester.pumpAndSettle();
      expect(
          await _pixel(
              tester, boundary, tester.getCenter(target), '${kind.name}-ready'),
          Colors.blue.toARGB32());
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _decode(tester);
    });
  }

  if (includePlaceholderCase) {
    testWidgets(
        'missing source provider flies its placeholder without duplicate keys',
        (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      const destination = Scaffold(
          body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox.square(
                  dimension: 80,
                  child: CategoryCoverFlight(
                      tag: 'missing',
                      radius: 12,
                      child: ColoredBox(color: Colors.blue)))));
      await tester.pumpWidget(MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
              body: Center(
                  child: GestureDetector(
                      key: const ValueKey('missing-source-click'),
                      onTap: () => navigator.currentState!.push(
                          MaterialPageRoute<void>(builder: (_) => destination)),
                      child: const SizedBox.square(
                          dimension: 120,
                          child: CategoryCoverFlight(
                              tag: 'missing',
                              radius: 60,
                              child: ColoredBox(color: Colors.red))))))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('missing-source-click')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(CoverFlightMotionGate), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(CoverFlightMotionGate), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
