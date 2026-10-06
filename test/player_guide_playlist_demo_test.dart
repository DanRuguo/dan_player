import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/player_feature_guide.dart';
import 'package:dan_player/component/player_guide_demo.dart';
import 'package:dan_player/component/playlist_cover_transition.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/playlist_feature_fixture.dart';

final _qaRoot = path
    .normalize(path.join(Directory.current.parent.path, 'tool', 'qa-local'));

Widget _host(Widget child,
        {bool ticker = true,
        bool reduced = false,
        bool tracking = true,
        double scale = 1,
        bool dark = false,
        GlobalKey? boundary}) =>
    MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: applyAppControlTheme(ThemeData(
            platform: TargetPlatform.windows,
            useMaterial3: true,
            fontFamily: danEmbeddedFontFamily,
            fontFamilyFallback: danFontFamilyFallback,
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal,
                brightness: dark ? Brightness.dark : Brightness.light))),
        builder: (context, child) => UiLanguageScope(
            child: MotionPreferencesScope(
                preferences: MotionPreferences(
                    disabled: tracking ? {} : {MotionKind.tracking}),
                child: TickerMode(
                    enabled: ticker,
                    child: RepaintBoundary(
                        key: boundary,
                        child: MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                                disableAnimations: reduced,
                                textScaler: TextScaler.linear(scale)),
                            child: child!))))),
        home: Scaffold(body: child));

Widget _demo(ValueNotifier<bool> hidden) => Padding(
    padding: const EdgeInsets.all(16),
    child:
        PlayerGuideDemo(kind: PlayerGuideDemoKind.playlists, isHidden: hidden));

PlaylistCoverTransitionController _controller(WidgetTester tester) => tester
    .widget<PlaylistCoverTransitionHost>(
        find.byType(PlaylistCoverTransitionHost))
    .controller;

Future<void> _ready(WidgetTester tester) async {
  // Asset decoding uses the real engine codec. Settle it before testing the
  // decoded-image fast path rather than replacing production covers with mocks.
  await tester.runAsync(() => precacheImage(
      const AssetImage('assets/images/RCE_logo_transparent.png'),
      tester.element(find.byType(PlayerGuideDemo)),
      onError: (error, stack) => fail('Sample artwork decode failed: $error')));
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, PlaylistViewMode mode) async {
  await tester.tap(find.byKey(const ValueKey('guide-demo-playlist-menu')));
  await tester.pumpAndSettle();
  await tester
      .tap(find.byKey(ValueKey('guide-demo-playlist-select-${mode.name}')));
  await tester.pump();
}

void _quiet(WidgetTester tester, PlaylistCoverTransitionController controller) {
  expect(controller.busy, isFalse);
  expect(controller.active, isFalse);
  expect(controller.debugSnapshotCount, 0);
  expect(tester.binding.transientCallbackCount, 0);
  expect(tester.takeException(), isNull);
}

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final output = Platform.environment['DAN_PLAYER_GUIDE_PLAYLIST_RENDER_DIR'];
  if (output == null) return;
  final directory = Directory(path.normalize(path.absolute(output)));
  expect(path.isWithin(_qaRoot, directory.path), isTrue);
  await tester.runAsync(() async {
    await directory.create(recursive: true);
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: raster.ImageByteFormat.png);
      await File(path.join(directory.path, '$name.png'))
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main({Set<String>? onlyCases}) {
  final registered = <String>{};
  void widgetCase(String name, Future<void> Function(WidgetTester) callback) {
    if (onlyCases != null && !onlyCases.contains(name)) return;
    registered.add(name);
    testWidgets(name, callback);
  }

  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadPlaylistFeatureFonts();
    final windows = Platform.environment['WINDIR'];
    if (windows != null) {
      final japanese = File(path.join(windows, 'Fonts', 'YuGothR.ttc'));
      if (await japanese.exists()) {
        await (FontLoader('Yu Gothic UI')
              ..addFont(Future.value(
                  ByteData.sublistView(await japanese.readAsBytes()))))
            .load();
      }
    }
  });
  late UiLanguage previous;
  setUp(() => previous = uiLanguage.value);
  tearDown(() => uiLanguage.value = previous);

  if (onlyCases == null) {
    test(
        'playlist demo and continuous listening guide have four complete languages',
        () {
      final source = File('lib/component/player_guide_playlist_demo.dart')
          .readAsStringSync();
      final keys = <String>{
        '试一试：歌单视图',
        '“最长连续收听”只看最近 24 小时已记录的连续播放片段；暂停或缺失记录不会拼接，未观测时间不补算。',
        ...RegExp(r"'((?:\\.|[^'\\])*)'")
            .allMatches(source)
            .map((match) => match.group(1)!)
            .where((text) => RegExp(r'[\u4e00-\u9fff]').hasMatch(text)),
      };
      expect(keys.length, greaterThanOrEqualTo(6));
      for (final key in keys) {
        for (final language in UiLanguage.values) {
          expect(translateUi(key, language).trim(), isNotEmpty);
          if (language != UiLanguage.zh) {
            expect(translateUi(key, language), isNot(key));
          }
        }
      }
    });
  }

  widgetCase(
      'four view selections reuse the actual bounded tracker and settle once',
      (tester) async {
    sizePlaylistFeature(tester, width: 760, height: 650);
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(_demo(hidden), boundary: boundary));
    await _ready(tester);
    final controller = _controller(tester);
    final ids = tester
        .widgetList<PlaylistCoverTransitionMarker>(
            find.byType(PlaylistCoverTransitionMarker))
        .map((marker) => marker.entryId)
        .toSet();
    expect(ids, hasLength(3));
    for (final mode in [
      PlaylistViewMode.grid,
      PlaylistViewMode.circular,
      PlaylistViewMode.tree,
      PlaylistViewMode.list
    ]) {
      await _select(tester, mode);
      await tester.pump(const Duration(milliseconds: 35));
      await tester.pump(const Duration(milliseconds: 70));
      await tester.pump(const Duration(milliseconds: 70));
      expect(controller.busy, isTrue, reason: mode.name);
      expect(controller.active, isTrue, reason: mode.name);
      expect(controller.debugSnapshotCount, 3);
      expect(find.byKey(ValueKey('guide-demo-playlist-layout-${mode.name}')),
          findsOneWidget);
      await _capture(
          tester, boundary, 'guide-playlists-${mode.name}-wide-moving');
      await tester.pumpAndSettle();
      expect(
          tester
              .widgetList<PlaylistCoverTransitionMarker>(
                  find.byType(PlaylistCoverTransitionMarker))
              .map((marker) => marker.entryId)
              .toSet(),
          ids);
      _quiet(tester, controller);
    }
    expect(controller.debugReusedImageCount, greaterThanOrEqualTo(12));
    expect(controller.debugRasterCaptureCount, 0);
    expect(PlayService.isInitialized, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  widgetCase(
      'rapid view retarget including return to the old layout keeps the last request',
      (tester) async {
    sizePlaylistFeature(tester, width: 760, height: 650);
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(_host(_demo(hidden)));
    await _ready(tester);
    final controller = _controller(tester);
    await tester.tap(find.byKey(const ValueKey('guide-demo-playlist-menu')));
    await tester.pumpAndSettle();
    final actions = {
      for (final mode in PlaylistViewMode.values)
        mode: tester
            .widget<MenuItemButton>(
                find.byKey(ValueKey('guide-demo-playlist-select-${mode.name}')))
            .onPressed!,
    };
    actions[PlaylistViewMode.grid]!();
    actions[PlaylistViewMode.circular]!();
    actions[PlaylistViewMode.list]!();
    tester
        .widget<OutlinedButton>(
            find.byKey(const ValueKey('guide-demo-playlist-menu')))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-demo-playlist-layout-list')),
        findsOneWidget);
    _quiet(tester, controller);
    await _select(tester, PlaylistViewMode.tree);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-demo-playlist-layout-tree')),
        findsOneWidget);
    _quiet(tester, controller);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final gate in [
    'hidden',
    'tracking',
    'media',
    'ticker',
    'native',
    'lifecycle'
  ]) {
    widgetCase(
        'playlist flight $gate gate settles and retains selection without restarting',
        (tester) async {
      sizePlaylistFeature(tester, width: 760, height: 650);
      final hidden = ValueNotifier(false);
      addTearDown(hidden.dispose);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final child = _demo(hidden);
      await tester.pumpWidget(_host(child));
      await _ready(tester);
      final controller = _controller(tester);
      await _select(tester, PlaylistViewMode.grid);
      await tester.pump(const Duration(milliseconds: 30));
      expect(controller.busy, isTrue);
      switch (gate) {
        case 'hidden':
          hidden.value = true;
        case 'tracking':
          await tester.pumpWidget(_host(child, tracking: false));
        case 'media':
          await tester.pumpWidget(_host(child, reduced: true));
        case 'ticker':
          await tester.pumpWidget(_host(child, ticker: false));
        case 'native':
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(reduceMotion: true);
        case 'lifecycle':
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('guide-demo-playlist-layout-grid')),
          findsOneWidget);
      _quiet(tester, controller);
      hidden.value = false;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(_host(child));
      await tester.pumpAndSettle();
      _quiet(tester, controller);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  widgetCase('pending capture hidden by the parent keeps its requested layout',
      (tester) async {
    sizePlaylistFeature(tester, width: 760, height: 650);
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(_host(_demo(hidden)));
    await _ready(tester);
    final controller = _controller(tester);
    await tester.tap(find.byKey(const ValueKey('guide-demo-playlist-menu')));
    await tester.pumpAndSettle();
    tester
        .widget<MenuItemButton>(
            find.byKey(const ValueKey('guide-demo-playlist-select-tree')))
        .onPressed!();
    expect(controller.busy, isTrue);
    hidden.value = true;
    tester
        .widget<OutlinedButton>(
            find.byKey(const ValueKey('guide-demo-playlist-menu')))
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-demo-playlist-layout-tree')),
        findsOneWidget);
    _quiet(tester, controller);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  widgetCase('playlist view menu accepts touch and keyboard selection',
      (tester) async {
    sizePlaylistFeature(tester, width: 760, height: 650);
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(_host(_demo(hidden)));
    await _ready(tester);
    final menu = find.byKey(const ValueKey('guide-demo-playlist-menu'));
    await tester.tap(menu, kind: raster.PointerDeviceKind.touch);
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const ValueKey('guide-demo-playlist-select-circular')),
        kind: raster.PointerDeviceKind.touch);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-demo-playlist-layout-circular')),
        findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab,
        physicalKey: PhysicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter,
        physicalKey: PhysicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
        find
            .byKey(const ValueKey('guide-demo-playlist-select-list'))
            .hitTestable(),
        findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown,
        physicalKey: PhysicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter,
        physicalKey: PhysicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    // Opening by keyboard starts on the trigger; Down focuses the first item.
    expect(find.byKey(const ValueKey('guide-demo-playlist-layout-list')),
        findsOneWidget);
    _quiet(tester, _controller(tester));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final replaceOuter in [false, true]) {
    widgetCase(
        'nested outer scroll${replaceOuter ? " replacement" : ""} retires the clipped playlist flight',
        (tester) async {
      sizePlaylistFeature(tester, width: 760, height: 850);
      final hidden = ValueNotifier(false);
      addTearDown(hidden.dispose);
      final innerController = ScrollController();
      final firstOuter = ScrollController();
      final secondOuter = TrackingScrollController();
      addTearDown(innerController.dispose);
      addTearDown(firstOuter.dispose);
      addTearDown(secondOuter.dispose);
      final inner = SizedBox(
          height: 500,
          child: SingleChildScrollView(
              controller: innerController,
              child: Column(
                  children: [_demo(hidden), const SizedBox(height: 700)])));
      Widget nested(ScrollController outer) => _host(Column(children: [
            const SizedBox(height: 260),
            SizedBox(
                height: 300,
                child: SingleChildScrollView(
                    controller: outer,
                    child: Column(
                        children: [inner, const SizedBox(height: 900)]))),
          ]));
      await tester.pumpWidget(nested(firstOuter));
      await _ready(tester);
      final controller = _controller(tester);
      if (replaceOuter) {
        final originalPosition = firstOuter.position;
        await tester.pumpWidget(nested(secondOuter));
        await _ready(tester);
        expect(secondOuter.position, isNot(same(originalPosition)),
            reason:
                'Different controller type must create a new outer position');
        expect(_controller(tester), same(controller),
            reason: 'Retain the existing inner/demo subtree');
      }
      await _select(tester, PlaylistViewMode.grid);
      await tester.pump(const Duration(milliseconds: 30));
      expect(controller.busy, isTrue);
      (replaceOuter ? secondOuter : firstOuter).jumpTo(400);
      // Body remains on screen and in the inner viewport, above the outer clip.
      await tester.pump();
      await tester.pump();
      expect(controller.busy, isFalse);
      await tester.pumpAndSettle();
      _quiet(tester, controller);
      (replaceOuter ? secondOuter : firstOuter).jumpTo(0);
      await tester.pumpAndSettle();
      _quiet(tester, controller);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  widgetCase(
      'closing the playlist guide chapter retires its tracker before reopening',
      (tester) async {
    sizePlaylistFeature(tester, width: 1080, height: 950);
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    await tester
        .pumpWidget(_host(PlayerFeatureGuideDialog(demoIsHidden: hidden)));
    final menu = find.byKey(const ValueKey('guide-demo-playlist-menu'));
    await tester.ensureVisible(menu);
    await _ready(tester);
    final controller = _controller(tester);
    await _select(tester, PlaylistViewMode.grid);
    await tester.pump(const Duration(milliseconds: 30));
    expect(controller.busy, isTrue);
    final tile = tester.widget<ExpansionTile>(
        find.byKey(const ValueKey('guide-section-playlists')));
    tile.controller!.collapse();
    await tester.pump();
    expect(controller.active, isFalse);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-demo-playlists')), findsNothing);
    tile.controller!.expand();
    await tester.pumpAndSettle();
    await tester.ensureVisible(menu);
    await _ready(tester);
    await _select(tester, PlaylistViewMode.tree);
    await tester.pumpAndSettle();
    _quiet(tester, _controller(tester));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  widgetCase(
      'scrolling the playlist demo out of view retires its clock and disposal stays quiet',
      (tester) async {
    sizePlaylistFeature(tester, width: 760, height: 450);
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_host(SingleChildScrollView(
        controller: scroll,
        child:
            Column(children: [_demo(hidden), const SizedBox(height: 1400)]))));
    await _ready(tester);
    final controller = _controller(tester);
    await _select(tester, PlaylistViewMode.grid);
    await tester.pump(const Duration(milliseconds: 30));
    expect(controller.busy, isTrue);
    scroll.jumpTo(700);
    await tester.pumpAndSettle();
    _quiet(tester, controller);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    _quiet(tester, controller);
    await _select(tester, PlaylistViewMode.circular);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(const SizedBox.shrink());
    hidden.value = true;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  widgetCase(
      'a covering route retires the playlist flight while retaining its mode',
      (tester) async {
    sizePlaylistFeature(tester, width: 760, height: 650);
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(_host(_demo(hidden)));
    await _ready(tester);
    final controller = _controller(tester);
    await _select(tester, PlaylistViewMode.tree);
    await tester.pump(const Duration(milliseconds: 30));
    expect(controller.busy, isTrue);
    final navigator =
        Navigator.of(tester.element(find.byType(PlayerGuideDemo)));
    navigator.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('route'))));
    await tester.pumpAndSettle();
    _quiet(tester, controller);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-demo-playlist-layout-tree')),
        findsOneWidget);
    _quiet(tester, controller);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final language in UiLanguage.values) {
    widgetCase(
        'playlist demo ${language.name} narrow large real fonts keeps all four menu choices reachable',
        (tester) async {
      uiLanguage.value = language;
      final hidden = ValueNotifier(false);
      addTearDown(hidden.dispose);
      final boundary = GlobalKey();
      for (final width in [320.0, 360.0]) {
        for (final scale in [1.5, 2.0]) {
          sizePlaylistFeature(tester, width: width, height: 1050);
          await tester.pumpWidget(_host(
              PlayerFeatureGuideDialog(demoIsHidden: hidden),
              scale: scale,
              dark: true,
              boundary: boundary));
          final demo = find.byKey(const ValueKey('guide-demo-playlists'));
          expect(demo, findsOneWidget,
              reason:
                  'Initially expanded playlist chapter also enables its demo');
          await tester.ensureVisible(
              find.byKey(const ValueKey('guide-demo-playlist-menu')));
          await _ready(tester);
          final controller = _controller(tester);
          for (final mode in PlaylistViewMode.values) {
            await _select(tester, mode);
            await tester.pumpAndSettle();
            expect(
                find.byKey(ValueKey('guide-demo-playlist-layout-${mode.name}')),
                findsOneWidget);
            final menu = find.byKey(const ValueKey('guide-demo-playlist-menu'));
            expect(menu.hitTestable(), findsOneWidget);
            final rect = tester.getRect(menu);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            for (final name in ['晨光', '午后', '夜色']) {
              final paragraph =
                  tester.renderObject<RenderParagraph>(find.text(ui(name)));
              expect(paragraph.didExceedMaxLines, isFalse,
                  reason: '${language.name}/$width/$scale/${mode.name}/$name');
            }
            expect(
                tester
                    .getSize(
                        find.byKey(const ValueKey('guide-demo-playlist-body')))
                    .height,
                208);
            _quiet(tester, controller);
            await _capture(tester, boundary,
                'guide-playlists-${language.name}-${mode.name}-${width.toInt()}-${scale}x');
          }
          expect(PlayService.isInitialized, isFalse);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    });
  }
  if (onlyCases != null && registered.length != onlyCases.length) {
    throw ArgumentError(
        'Unknown playlist guide test selection: ${onlyCases.difference(registered)}');
  }
}
