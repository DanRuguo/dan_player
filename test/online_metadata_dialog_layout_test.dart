import 'dart:async';

import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/online_metadata_lookup_dialog.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';
import 'support/song_comments_fixtures.dart';

void main() {
  late BuildContext pageContext;
  final controls = find.byKey(const ValueKey('metadata-lookup-controls'));
  final results = find.byKey(const ValueKey('metadata-lookup-results'));
  final query = find.byKey(const ValueKey('metadata-lookup-query'));
  final compact = find.byKey(const ValueKey('metadata-lookup-compact'));
  Finder viewportFor(Finder view) =>
      compact.evaluate().isNotEmpty ? compact : view;

  Future<void> mount(WidgetTester tester, Size size, double scale) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: AppPresentationHost(child: child!),
      ),
      home: Scaffold(
          body: Padding(
        padding: const EdgeInsets.only(top: 48, right: 12, bottom: 12),
        child: AppContentRegion(child: Builder(builder: (context) {
          pageContext = context;
          return const SizedBox.expand();
        })),
      )),
    ));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      expect(PlayService.isInitialized, isFalse);
    });
  }

  Future<void> reach(
      WidgetTester tester, Finder viewport, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      40,
      scrollable: find
          .descendant(
              of: viewportFor(viewport), matching: find.byType(Scrollable))
          .first,
      maxScrolls: 300,
    );
    // The initial search intentionally stays pending; don't pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 100));
  }

  for (final size in [const Size(1000, 800), const Size(507, 320)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'metadata controls persist across results/focus at $size/$scale',
          (tester) async {
        await mount(tester, size, scale);
        final pending = Completer<OnlineSearchResponse>();
        showOnlineMetadataLookupDialog(pageContext,
            audio: CategoryTestAudio('原歌曲'), search: (_) => pending.future);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await reach(tester, controls, query);
        final inputVisible = tester
            .getRect(query)
            .intersect(tester.getRect(viewportFor(controls)));
        await tester.tapAt(inputVisible.center);
        await tester.pump(const Duration(milliseconds: 100));
        final album = find.widgetWithText(FilterChip, '专辑');
        await reach(tester, controls, album);
        final shared = compact.evaluate().isNotEmpty;
        final controlPosition = shared
            ? tester.widget<CustomScrollView>(compact).controller!.position
            : tester
                .widget<SingleChildScrollView>(controls)
                .controller!
                .position;
        final beforePixels = controlPosition.pixels;
        final beforeAlbum = tester.getRect(album);
        final beforeControls = tester.getRect(viewportFor(controls));
        final beforeResults = tester.getRect(viewportFor(results));
        for (final field in ['标题', '艺术家', '专辑', '封面']) {
          expect(find.widgetWithText(FilterChip, field), findsOneWidget);
        }
        if (size.width > 600) {
          expect(query.hitTestable(), findsOneWidget);
          for (final field in ['标题', '艺术家', '专辑', '封面']) {
            expect(find.widgetWithText(FilterChip, field).hitTestable(),
                findsOneWidget);
          }
        }
        final candidates =
            List.generate(24, (i) => commentAudio(id: '$i', title: '结果$i'));
        pending
            .complete(OnlineSearchResponse(tracks: candidates, failures: {}));
        await tester.pumpAndSettle();
        expect(tester.getRect(viewportFor(controls)).size, beforeControls.size);
        expect(tester.getRect(viewportFor(results)).height,
            greaterThanOrEqualTo(beforeResults.height));
        expect(
            tester.getTopLeft(album) - tester.getTopLeft(viewportFor(controls)),
            beforeAlbum.topLeft - beforeControls.topLeft);
        expect(controlPosition.pixels, beforePixels);

        final last =
            find.byKey(ValueKey('metadata-candidate-${candidates.last.path}'));
        await reach(tester, results, last);
        await tester.pumpAndSettle();
        expect(
            shared
                ? tester.widget<CustomScrollView>(compact).controller!.offset
                : tester.widget<ListView>(results).controller!.offset,
            greaterThan(0));
        if (!shared) {
          expect(controlPosition.pixels, beforePixels,
              reason: 'candidate scrolling must not move query/field controls');
          expect(
              tester.getTopLeft(album) -
                  tester.getTopLeft(viewportFor(controls)),
              beforeAlbum.topLeft - beforeControls.topLeft);
          expect(
              tester.getRect(album).overlaps(tester.getRect(controls)), isTrue);
        } else {
          await Scrollable.ensureVisible(tester.element(last), alignment: .5);
          await tester.pump();
          final viewport = tester.getRect(compact);
          final candidate = tester.getRect(last);
          expect(candidate.top, greaterThanOrEqualTo(viewport.top));
          expect(candidate.bottom, lessThanOrEqualTo(viewport.bottom));
        }
        expect(find.text('取消').hitTestable(), findsOneWidget);
        expect(find.text('填入编辑器').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('resizing keeps lookup query, choices and candidate selection',
      (tester) async {
    await mount(tester, const Size(507, 320), 2);
    final candidates = List.generate(
        12, (i) => commentAudio(provider: 'qq', id: '$i', title: '候选歌曲$i'));
    final result = showOnlineMetadataLookupDialog(pageContext,
        audio: CategoryTestAudio('原歌曲'),
        search: (_) async =>
            OnlineSearchResponse(tracks: candidates, failures: {}));
    await tester.pumpAndSettle();
    expect(compact, findsOneWidget);
    await reach(tester, controls, query);
    await tester.enterText(query, '保留的搜索草稿');
    final album = find.widgetWithText(FilterChip, '专辑');
    await reach(tester, controls, album);
    await Scrollable.ensureVisible(tester.element(album), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(album);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(album).selected, isFalse);
    final selected =
        find.byKey(ValueKey('metadata-candidate-${candidates.last.path}'));
    await reach(tester, results, selected);
    await tester.tapAt(
        tester.getRect(selected).intersect(tester.getRect(compact)).center);
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(selected).selected, isTrue);

    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpAndSettle();
    expect(compact, findsNothing);
    expect(tester.widget<TextField>(query).controller!.text, '保留的搜索草稿');
    expect(tester.widget<FilterChip>(album).selected, isFalse);
    expect(
        tester
            .widget<SingleChildScrollView>(controls)
            .controller!
            .positions
            .length,
        1);
    expect(tester.widget<ListView>(results).controller!.positions.length, 1);
    await reach(tester, results, selected);
    expect(tester.widget<ListTile>(selected).selected, isTrue);

    tester.view.physicalSize = const Size(507, 320);
    await tester.pumpAndSettle();
    expect(compact, findsOneWidget);
    expect(
        tester.widget<CustomScrollView>(compact).controller!.positions.length,
        1);
    await reach(tester, controls, query);
    expect(tester.widget<TextField>(query).controller!.text, '保留的搜索草稿');
    await reach(tester, controls, album);
    expect(tester.widget<FilterChip>(album).selected, isFalse);
    await tester.tap(find.text('填入编辑器'));
    await tester.pumpAndSettle();
    final value = await result;
    expect(value?.title, candidates.last.title);
    expect(value?.album, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'field choices survive a new search; selection only returns editor data',
      (tester) async {
    await mount(tester, const Size(1000, 800), 1);
    final original = CategoryTestAudio('原歌曲', artist: '原艺术家', album: '原专辑');
    final first = commentAudio(id: '1', title: '首次结果');
    final second = commentAudio(id: '2', title: '新的结果');
    final queries = <String>[];
    final result = showOnlineMetadataLookupDialog(pageContext, audio: original,
        search: (value) async {
      queries.add(value);
      return OnlineSearchResponse(
          tracks: [queries.length == 1 ? first : second], failures: {});
    });
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '专辑'));
    await tester.enterText(query, '修改后的关键词');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(queries.last, '修改后的关键词');
    expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '专辑'))
            .selected,
        isFalse);
    await tester.tap(find.text('新的结果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('填入编辑器'));
    await tester.pumpAndSettle();
    final selected = await result;
    expect(selected?.title, second.title);
    expect(selected?.album, isNull);
    expect(original.title, '原歌曲');
    expect(original.artist, '原艺术家');
    expect(original.album, '原专辑');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'new query ignores a late old result without resetting field choices',
      (tester) async {
    await mount(tester, const Size(1000, 800), 1);
    final first = Completer<OnlineSearchResponse>();
    final second = Completer<OnlineSearchResponse>();
    var calls = 0;
    showOnlineMetadataLookupDialog(pageContext,
        audio: CategoryTestAudio('原歌曲'),
        search: (_) => ++calls == 1 ? first.future : second.future);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilterChip, '艺术家'));
    await tester.enterText(query, '新的关键词');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    second.complete(OnlineSearchResponse(
        tracks: [commentAudio(id: '2', title: '新结果')], failures: {}));
    await tester.pumpAndSettle();
    first.complete(OnlineSearchResponse(
        tracks: [commentAudio(id: '1', title: '旧结果')], failures: {}));
    await tester.pumpAndSettle();
    expect(find.text('新结果'), findsOneWidget);
    expect(find.text('旧结果'), findsNothing);
    expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '艺术家'))
            .selected,
        isFalse);
    expect(tester.takeException(), isNull);
  });
}
