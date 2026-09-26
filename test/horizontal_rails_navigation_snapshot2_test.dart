import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_horizontal_wheel_region.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/search_category_tabs.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:dan_player/page/now_playing_page/component/equalizer_dialog.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/page/search_page/search_page.dart';
import 'package:dan_player/page/search_page/search_result_page.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/search_history_fixture.dart';

class EqFixture extends ChangeNotifier implements PlaybackService {
  @override
  final eqEnabled = ValueNotifier(true);
  @override
  final eqGains = List<double>.filled(10, 0);
  @override
  int eqEditRevision = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  void dispose() {
    eqEnabled.dispose();
    super.dispose();
  }
}

Future<void> render(
    WidgetTester tester, GlobalKey boundary, String name) async {
  const output = String.fromEnvironment('DAN_HORIZONTAL_RAIL_RENDER');
  if (output.isEmpty) return;
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary)
        .toImage();
    try {
      final data = await image.toByteData(format: raster.ImageByteFormat.png);
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> wheel(WidgetTester tester, Finder rail, Offset delta) async {
  await tester.sendEventToBinding(
      PointerScrollEvent(position: tester.getCenter(rail), scrollDelta: delta));
}

ScrollPosition railPosition(WidgetTester tester, Finder rail) => tester
    .state<ScrollableState>(
        find.descendant(of: rail, matching: find.byType(Scrollable)).first)
    .position;

Widget host(Widget child,
        {bool reduced = false,
        bool feedback = true,
        bool visible = true,
        bool narrow = false,
        TextDirection direction = TextDirection.ltr}) =>
    MaterialApp(
        debugShowCheckedModeBanner: false,
        scrollBehavior: const DanPlayerScrollBehavior(),
        themeAnimationDuration: Duration.zero,
        locale: uiLanguage.value.locale,
        supportedLocales: const [
          Locale('zh'),
          Locale('en'),
          Locale('ja'),
          Locale('ko')
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: Entry(welcome: false).fromSchemeAndFontFamily(
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal,
                brightness: narrow ? Brightness.dark : Brightness.light)),
        builder: (context, content) => MotionPreferencesScope(
            preferences: const MotionPreferences()
                .withKind(MotionKind.feedback, feedback),
            child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: reduced,
                    textScaler: TextScaler.linear(narrow ? 2 : 1)),
                child: Directionality(
                    textDirection: direction,
                    child: TickerMode(enabled: visible, child: content!)))),
        home: Scaffold(body: child));

void viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
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
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets(
      'wheel accumulates finite movement and reverses before first frame',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    const railKey = ValueKey('fixture-rail');
    final rail = find.byKey(railKey);
    Widget content() => AppHorizontalWheelRegion(
        controller: controller,
        child: SingleChildScrollView(
            key: railKey,
            controller: controller,
            scrollDirection: Axis.horizontal,
            child: const SizedBox(width: 1500, height: 64)));
    await tester.pumpWidget(host(content()));
    await wheel(tester, rail, const Offset(0, 100));
    await wheel(tester, rail, const Offset(0, 100));
    expect(controller.offset, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(controller.offset, inExclusiveRange(0, 200));
    await tester.pumpAndSettle();
    expect(controller.offset, 200);
    await wheel(tester, rail, const Offset(0, 120));
    await wheel(tester, rail, const Offset(0, -30));
    await tester.pumpAndSettle();
    expect(controller.offset, 170);
    await wheel(tester, rail, const Offset(0, 140));
    await wheel(tester, rail, const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(controller.offset, 210,
        reason: 'native dx cancels the unvisited wheel target');
    await wheel(tester, rail, const Offset(0, 100));
    await tester.pumpWidget(host(content(), feedback: false));
    await tester.pumpAndSettle();
    expect(controller.offset, 310);
    await wheel(tester, rail, const Offset(0, 40));
    await tester.pump();
    expect(controller.offset, 350);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'native direction, shift-wheel and touch retain their scroll owner',
      (tester) async {
    final controller = ScrollController(initialScrollOffset: 200);
    addTearDown(controller.dispose);
    const railKey = ValueKey('fixture-rail');
    final rail = find.byKey(railKey);
    await tester.pumpWidget(host(
        AppHorizontalWheelRegion(
            controller: controller,
            child: SingleChildScrollView(
                key: railKey,
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: const SizedBox(width: 1500, height: 64))),
        reduced: true,
        direction: TextDirection.rtl));
    await wheel(tester, rail, const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(controller.offset, 160);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await wheel(tester, rail, const Offset(0, 40));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(controller.offset, 120);
    await wheel(tester, rail, const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(controller.offset, 80);
    await tester.drag(rail, const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(80));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'rail edges yield to vertical page and replacement cancels activity',
      (tester) async {
    final outer = ScrollController();
    final inner = ScrollController();
    final replacement = ScrollController();
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    addTearDown(replacement.dispose);
    const railKey = ValueKey('fixture-rail');
    final rail = find.byKey(railKey);
    Widget content(ScrollController horizontal) => SingleChildScrollView(
        controller: outer,
        child: Column(children: [
          AppHorizontalWheelRegion(
              controller: horizontal,
              child: SingleChildScrollView(
                  key: railKey,
                  controller: horizontal,
                  scrollDirection: Axis.horizontal,
                  child: const SizedBox(width: 1500, height: 64))),
          const SizedBox(height: 2000)
        ]));
    await tester.pumpWidget(host(content(inner), reduced: true));
    await wheel(tester, rail, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(inner.offset, 100);
    expect(outer.offset, 0);
    inner.jumpTo(inner.position.maxScrollExtent);
    await wheel(tester, rail, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(outer.offset, 100);
    outer.jumpTo(0);
    inner.jumpTo(0);
    await tester.pumpWidget(host(content(inner)));
    await wheel(tester, rail, const Offset(0, 100));
    await tester.pumpWidget(host(content(replacement), visible: false));
    await tester.pumpAndSettle();
    expect(replacement.offset, 0);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
      'native search tabs reveal hidden labels by wheel touch and keyboard',
      (tester) async {
    viewport(tester, const Size(320, 500));
    await tester.pumpWidget(host(
        DefaultTabController(
            length: 7,
            child: Column(children: [
              const SearchCategoryTabs(),
              Expanded(
                  child: TabBarView(children: [
                for (var i = 0; i < 7; i++) Center(child: Text('page-$i'))
              ])),
            ])),
        narrow: true,
        reduced: true));
    final tabs = find.byType(TabBar);
    final position = railPosition(tester, tabs);
    await wheel(tester, tabs, const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(position.pixels, position.maxScrollExtent);
    await tester.tap(find.descendant(of: tabs, matching: find.text(ui('设置'))));
    await tester.pumpAndSettle();
    expect(find.text('page-6').hitTestable(), findsOneWidget);
    await tester.drag(find.byType(TabBarView), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(DefaultTabController.of(tester.element(tabs)).index, 5);
    await tester.drag(tabs, const Offset(700, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, lessThan(position.maxScrollExtent));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(DefaultTabController.of(tester.element(tabs)).index, 6);
    tester.view.physicalSize = const Size(800, 500);
    await tester.pumpAndSettle();
    expect(DefaultTabController.of(tester.element(tabs)).index, 6);
    expect(
        find.descendant(of: tabs, matching: find.text(ui('设置'))).hitTestable(),
        findsOneWidget);
    tester.view.physicalSize = const Size(300, 500);
    await tester.pumpAndSettle();
    await wheel(tester, tabs, const Offset(0, -4000));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: tabs, matching: find.text(ui('所有'))));
    await tester.pumpAndSettle();
    expect(DefaultTabController.of(tester.element(tabs)).index, 0);
    expect(find.text('page-0').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'implicit outer position ignores nested rails and stops when hidden',
      (tester) async {
    final outer = ScrollController();
    final inner = ScrollController();
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    const railKey = ValueKey('implicit-rail');
    final rail = find.byKey(railKey);
    Widget content() => AppHorizontalWheelRegion(
        child: SingleChildScrollView(
            key: railKey,
            controller: outer,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
                width: 1500,
                height: 64,
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                        width: 200,
                        child: SingleChildScrollView(
                            controller: inner,
                            scrollDirection: Axis.horizontal,
                            child: const SizedBox(width: 500, height: 30)))))));
    await tester.pumpWidget(host(content()));
    await wheel(tester, rail, const Offset(0, 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(outer.offset, inExclusiveRange(0, 100));
    expect(inner.offset, 0);
    final paused = outer.offset;
    await tester.pumpWidget(host(content(), visible: false));
    await tester.pumpAndSettle();
    expect(outer.offset, paused);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(host(content(), reduced: true));
    await wheel(tester, rail, const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(outer.offset, paused + 60);
    expect(inner.offset, 0);
  });

  testWidgets(
      'category chips expose the final category by wheel in four languages',
      (tester) async {
    viewport(tester, const Size(800, 700));
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final narrow in [false, true]) {
        tester.view.physicalSize = Size(narrow ? 320 : 800, 700);
        final boundary = GlobalKey();
        await tester.pumpWidget(host(
            RepaintBoundary(
                key: boundary, child: const CategoriesPage(audios: [])),
            narrow: narrow,
            reduced: narrow));
        await tester.pumpAndSettle();
        final rail = find.byKey(const ValueKey('category-kind-scroll'));
        final position = railPosition(tester, rail);
        await wheel(tester, rail, const Offset(0, 4000));
        await tester.pumpAndSettle();
        expect(position.pixels, position.maxScrollExtent);
        expect(
            find.byKey(const ValueKey('category-kind-personal')).hitTestable(),
            findsOneWidget);
        final source = find.byKey(const ValueKey('category-kind-source'));
        await wheel(tester, rail,
            Offset(0, tester.getCenter(source).dx - tester.getCenter(rail).dx));
        await tester.pumpAndSettle();
        await tester.tap(source);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(source).selected, isTrue);
        expect(tester.takeException(), isNull);
        await render(tester, boundary,
            'categories-${language.name}-${narrow ? 'narrow' : 'wide'}');
      }
    }
  });

  testWidgets(
      'long playlist breadcrumbs reveal ancestors by wheel without edits',
      (tester) async {
    viewport(tester, const Size(800, 700));
    final tree = PlaylistTree([]);
    final root = tree.createPlaylist('Fixture root');
    final middle =
        tree.createPlaylist('Fixture second long folder', parent: root);
    final last =
        tree.createPlaylist('Fixture third long folder', parent: middle);
    var saves = 0;
    Playlist? navigated;
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final narrow in [false, true]) {
        tester.view.physicalSize = Size(narrow ? 320 : 800, 700);
        final boundary = GlobalKey();
        await tester.pumpWidget(host(
            RepaintBoundary(
                key: boundary,
                child: PlaylistBrowser(
                    tree: tree,
                    initialPlaylist: last,
                    persist: () async {
                      saves++;
                    },
                    onNavigate: (value) => navigated = value,
                    onPlay: (_, __) {})),
            narrow: narrow,
            reduced: narrow));
        await tester.pumpAndSettle();
        final rail = find.byKey(const ValueKey('playlist-breadcrumb-scroll'));
        final position = railPosition(tester, rail);
        await wheel(tester, rail, const Offset(0, 4000));
        await tester.pumpAndSettle();
        expect(position.pixels, position.maxScrollExtent);
        await render(tester, boundary,
            'breadcrumbs-${language.name}-${narrow ? 'narrow' : 'wide'}');
        await wheel(tester, rail, const Offset(0, -200));
        await tester.pumpAndSettle();
        final ancestor =
            find.byKey(ValueKey('playlist-breadcrumb-${middle.id}'));
        await tester.ensureVisible(ancestor);
        await tester.tap(ancestor);
        await tester.pumpAndSettle();
        expect(navigated, same(middle));
        expect(saves, 0);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('all EQ bands remain reachable by wheel without changing gains',
      (tester) async {
    viewport(tester, const Size(800, 700));
    final playback = EqFixture();
    addTearDown(playback.dispose);
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final narrow in [false, true]) {
        tester.view.physicalSize = Size(narrow ? 320 : 800, 700);
        final boundary = GlobalKey();
        await tester.pumpWidget(host(
            RepaintBoundary(
                key: boundary,
                child: EqualizerDialog(playbackService: playback)),
            narrow: narrow,
            reduced: narrow));
        await tester.pumpAndSettle();
        final rail = find.byKey(const ValueKey('equalizer-bands-scroll'));
        await tester.ensureVisible(rail);
        await tester.pumpAndSettle();
        final position = railPosition(tester, rail);
        await wheel(tester, rail, const Offset(0, 4000));
        await tester.pumpAndSettle();
        expect(position.pixels, position.maxScrollExtent);
        expect(find.text('16k').hitTestable(), findsOneWidget);
        expect(playback.eqGains, everyElement(0));
        expect(playback.eqEditRevision, 0);
        expect(tester.takeException(), isNull);
        await render(tester, boundary,
            'eq-${language.name}-${narrow ? 'narrow' : 'wide'}');
      }
    }
  });

  for (final language in UiLanguage.values) {
    testWidgets(
        'real search result hidden categories stay usable ${language.name}',
        (tester) async {
      uiLanguage.value = language;
      const output = String.fromEnvironment('DAN_HORIZONTAL_RAIL_RENDER');
      final history = MemorySearchHistory();
      addTearDown(history.dispose);
      viewport(tester, const Size(800, 640));
      for (final narrow in [false, true]) {
        tester.view.physicalSize = Size(narrow ? 320 : 800, 640);
        final boundary = GlobalKey();
        final result = UnionSearchResult('title:fixture')
          ..online = Future.value(
              const OnlineSearchResponse(tracks: [], failures: {}));
        await tester.pumpWidget(host(
            RepaintBoundary(
                key: boundary,
                child:
                    SearchResultPage(searchResult: result, history: history)),
            narrow: narrow,
            reduced: narrow));
        await tester.pumpAndSettle();
        final tabs = find.byType(TabBar);
        final position = railPosition(tester, tabs);
        final area = tester.getRect(tabs);
        expect(area.width, greaterThan(narrow ? 180 : 450));
        for (final stage in ['first', 'last']) {
          if (stage == 'last') {
            await wheel(tester, tabs, const Offset(0, 4000));
            await tester.pumpAndSettle();
            expect(position.pixels, position.maxScrollExtent);
            await tester
                .tap(find.descendant(of: tabs, matching: find.text(ui('设置'))));
            await tester.pumpAndSettle();
            expect(DefaultTabController.of(tester.element(tabs)).index, 6);
          }
          expect(tester.takeException(), isNull);
          if (output.isNotEmpty) {
            await tester.runAsync(() async {
              final image = await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              try {
                final data =
                    await image.toByteData(format: raster.ImageByteFormat.png);
                final file = File(
                    '$output/search-${language.name}-${narrow ? 'narrow' : 'wide'}-$stage.png');
                await file.parent.create(recursive: true);
                await file.writeAsBytes(data!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }
        }
      }
    });
  }
}
