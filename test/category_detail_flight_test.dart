import 'dart:io';
import 'dart:ui' as drawing;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/category_tile_grid.dart';
import 'package:dan_player/component/artwork_handoff.dart';
import 'package:dan_player/component/category_cover_flight.dart';
import 'package:dan_player/component/app_route_transition.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/uni_detail_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'support/music_category_fixtures.dart';

class _Audio extends CategoryTestAudio {
  _Audio(this.image) : super('sample');
  final ImageProvider image;
  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) =>
      SynchronousFuture(image);
}

void main() {
  for (final kind in [MusicCategoryKind.artist, MusicCategoryKind.album]) {
    for (final shape in CategoryCoverShape.values) {
      testWidgets('real grid to detail ${kind.name} ${shape.name}',
          (tester) async {
        final root = (await tester.runAsync(() async =>
            (await Directory('build/test-data').create(recursive: true))
                .createTemp('detail-flight-')))!;
        final store = CategoryCoverStore(dataDirectory: () async => root);
        addTearDown(() async {
          store.dispose();
          await root.delete(recursive: true);
        });
        final bytes = await tester.runAsync(() async {
          final recorder = drawing.PictureRecorder();
          final canvas = Canvas(recorder)
            ..drawColor(Colors.teal, BlendMode.src);
          canvas.drawCircle(
              const Offset(50, 50), 35, Paint()..color = Colors.amber);
          final picture = recorder.endRecording();
          final image = await picture.toImage(100, 100);
          final data =
              await image.toByteData(format: drawing.ImageByteFormat.png);
          image.dispose();
          picture.dispose();
          return data!.buffer.asUint8List();
        });
        final image = MemoryImage(bytes!);
        final group = MusicCategories([_Audio(image)]).groups(kind).single;
        final nav = GlobalKey<NavigatorState>();
        final boundary = GlobalKey();
        final pic = Future<ImageProvider?>.value(image);
        Widget detail() => UniDetailPage<String, String, String>(
            pref: PagePreference(0, SortOrder.ascending, ContentView.list),
            primaryContent: group.id,
            primaryPic: pic,
            backgroundPic: pic,
            coverFlightTag: ('category-detail-cover', group.persistenceKey),
            picShape: kind == MusicCategoryKind.artist
                ? PicShape.oval
                : PicShape.rrect,
            title: group.title,
            subtitle: '1 song',
            secondaryContent: const [],
            secondaryContentBuilder: (_, __, ___, ____, _____) =>
                const SizedBox(),
            tertiaryContentTitle: '',
            tertiaryContent: const [],
            tertiaryContentBuilder: (_, __, ___, ____) => const SizedBox(),
            enableShufflePlay: false,
            enableSortMethod: false,
            enableSortOrder: false,
            enableSecondaryContentViewSwitch: false);
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                navigatorKey: nav,
                home: Scaffold(
                    body: CustomScrollView(slivers: [
                  SliverPadding(
                      padding: const EdgeInsets.only(top: 260, left: 400),
                      sliver: CategoryTileGrid(
                          groups: [group],
                          presentation: CategoryPresentation(shape: shape),
                          onChanged: (_) {},
                          onOpen: (_) => nav.currentState!.push(
                              PageRouteBuilder<void>(
                                  transitionDuration:
                                      AppRouteTransition.enterDuration,
                                  reverseTransitionDuration:
                                      AppRouteTransition.exitDuration,
                                  pageBuilder: (_, __, ___) =>
                                      Scaffold(body: detail()),
                                  transitionsBuilder:
                                      (_, animation, __, child) =>
                                          AppRouteTransition(
                                              animation: animation,
                                              child: child))),
                          covers: store,
                          changing: const {},
                          onChangeCover: (_) {},
                          onRemoveCover: (_) {},
                          icon: Icons.album,
                          persistLayout: false))
                ])))));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
        Future<void> render(String stage) async {
          const output = String.fromEnvironment('DAN_ROUTE_RENDER');
          if (output.isEmpty) return;
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final data =
                await image.toByteData(format: drawing.ImageByteFormat.png);
            image.dispose();
            await File('$output/${kind.name}-${shape.name}-$stage.png')
                .writeAsBytes(data!.buffer.asUint8List());
          });
        }

        Future<void> expectCoverPixel(Offset point) async {
          final pixel = await tester.runAsync(() async {
            final frame = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final data = await frame.toByteData();
            final offset =
                (point.dy.floor() * frame.width + point.dx.floor()) * 4;
            final result = [
              data!.getUint8(offset),
              data.getUint8(offset + 1),
              data.getUint8(offset + 2)
            ];
            frame.dispose();
            return result;
          });
          // The amber center must stay painted through the exact overlay to
          // page handoff; a spinner/placeholder or one blank frame fails this.
          expect(pixel![0], greaterThan(240));
          expect(pixel[1], inInclusiveRange(175, 210));
          expect(pixel[2], lessThan(35));
        }

        await render('before');
        final handoffs = find.descendant(
            of: find.byType(CategoryCoverFlight, skipOffstage: false),
            matching: find.byType(ArtworkHandoff, skipOffstage: false),
            skipOffstage: false);
        final sourceState = tester.state(handoffs.first);
        await tester.tapAt(tester
            .getRect(find.byKey(ValueKey(('category-cover', group.id))))
            .center);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        // The hidden destination must keep decoding instead of being unmounted
        // until landing. Both endpoints retain their exact State on return too.
        expect(handoffs, findsNWidgets(2));
        final destinationState = tester.state(handoffs.last);
        expect(find.byKey(const ValueKey('category-flight-image')),
            findsOneWidget);
        await render('during');
        await tester.pump(AppRouteTransition.enterDuration -
            const Duration(milliseconds: 121));
        final lastFlight =
            tester.getRect(find.byKey(const ValueKey('category-flight-image')));
        await expectCoverPixel(lastFlight.center);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 1));
          await expectCoverPixel(lastFlight.center);
        }
        await tester.pumpAndSettle();
        expect(tester.state(handoffs.last), same(destinationState));
        expect(
            find.byKey(const ValueKey('category-flight-image')), findsNothing);
        expect(find.byKey(const ValueKey('uni-detail-cover')), findsOneWidget);
        final settled =
            tester.getRect(find.byKey(const ValueKey('uni-detail-cover')));
        expect((lastFlight.center - settled.center).distance, lessThan(3));
        await render('after');
        expect(tester.takeException(), isNull);
        nav.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.state(handoffs.first), same(sourceState));
        await tester.pump(AppRouteTransition.exitDuration -
            const Duration(milliseconds: 121));
        final returnRect =
            tester.getRect(find.byKey(const ValueKey('category-flight-image')));
        await expectCoverPixel(returnRect.center);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 1));
          await expectCoverPixel(returnRect.center);
        }
        await tester.pumpAndSettle();
        expect(tester.state(handoffs.first), same(sourceState));
        // Returning the visible grid starts a resized caption sample. Let its
        // image/readback complete before disposing the test's raster fixture.
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 40));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
