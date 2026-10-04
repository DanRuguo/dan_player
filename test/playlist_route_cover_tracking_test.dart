import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_route_transition.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_cover_transition.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

Future<drawing.Image> _image() async {
  final recorder = drawing.PictureRecorder();
  Canvas(recorder).drawColor(Colors.red, BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(128, 128);
  } finally {
    picture.dispose();
  }
}

Future<Color> _pixel(
    WidgetTester tester, GlobalKey boundary, Offset point) async {
  return (await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage();
    try {
      final bytes = (await image.toByteData())!;
      final index = (point.dy.floor() * image.width + point.dx.floor()) * 4;
      return Color.fromARGB(bytes.getUint8(index + 3), bytes.getUint8(index),
          bytes.getUint8(index + 1), bytes.getUint8(index + 2));
    } finally {
      image.dispose();
    }
  }))!;
}

PageRoute<void> _route(Widget child) => PageRouteBuilder<void>(
    transitionDuration: AppRouteTransition.enterDuration,
    reverseTransitionDuration: AppRouteTransition.exitDuration,
    pageBuilder: (_, __, ___) => Scaffold(body: child),
    transitionsBuilder: (_, animation, __, child) =>
        AppRouteTransition(animation: animation, child: child));

Widget _app(Widget child,
        {GlobalKey<NavigatorState>? navigator,
        GlobalKey? boundary,
        double textScale = 1,
        bool reduce = false}) =>
    MaterialApp(
      navigatorKey: navigator,
      theme: applyAppControlTheme(ThemeData(
          useMaterial3: true,
          platform: TargetPlatform.windows,
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal))),
      builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  disableAnimations: reduce,
                  textScaler: TextScaler.linear(textScale)),
              child: child!)),
      home: Scaffold(body: child),
    );

Future<void> _decode(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

class _Browser {
  _Browser(this.path, {String title = 'Playlist'}) {
    playlist = tree.createPlaylist(title);
    tree.setImagePath(playlist, path);
    tree.createPlaylist('Child', parent: playlist);
  }
  final String path;
  final tree = PlaylistTree([]);
  final navigator = GlobalKey<NavigatorState>();
  late final Playlist playlist;

  Widget browser(PlaylistViewMode view, {Playlist? current}) => PlaylistBrowser(
        tree: tree,
        initialPlaylist: current,
        initialView: view,
        library: const [],
        persist: () async {},
        trackBuilder: (_, __, ___, ____) => const SizedBox.shrink(),
        onNavigate: (next) {
          if (next != null) {
            navigator.currentState!.push(_route(browser(view, current: next)));
          }
        },
      );

  Future<void> open(WidgetTester tester, PlaylistViewMode view) async {
    if (view == PlaylistViewMode.tree) {
      await tester
          .longPress(find.byKey(ValueKey('playlist-open-${playlist.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, ui('打开歌单')));
      // MenuItemButton restores focus before invoking the action post-frame.
      await tester.pump();
    } else {
      final prefix = switch (view) {
        PlaylistViewMode.grid => 'playlist-rectangle-',
        PlaylistViewMode.circular => 'playlist-circle-open-',
        _ => 'playlist-open-',
      };
      await tester.tap(find.byKey(ValueKey('$prefix${playlist.id}')));
    }
    await tester.pump();
    await tester.pump();
  }
}

void main() {
  late Directory data;
  late String imagePath;
  setUpAll(() async {
    data = await Directory.systemTemp.createTemp('playlist-route-cover-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => data.path);
    final image = await _image();
    try {
      final png =
          (await image.toByteData(format: drawing.ImageByteFormat.png))!;
      imagePath = '${data.path}/cover.png';
      await File(imagePath).writeAsBytes(png.buffer.asUint8List());
    } finally {
      image.dispose();
    }
    await loadPlaylistFeatureFonts();
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await data.delete(recursive: true);
  });

  testWidgets('late header image retains source artwork after route arrival',
      (tester) async {
    sizePlaylistFeature(tester, width: 500, height: 500);
    final image = (await tester.runAsync(_image))!;
    addTearDown(image.dispose);
    final pending = Completer<drawing.Image>();
    final navigator = GlobalKey<NavigatorState>();
    final boundary = GlobalKey();
    final source = Positioned(
        left: 320,
        top: 250,
        child: SizedBox.square(
            dimension: 48,
            child: PlaylistCoverRouteFlight(
                playlistId: 'late',
                borderRadius: AppShape.smallRadius,
                child: RawImage(image: image, fit: BoxFit.cover))));
    await tester.pumpWidget(_app(Stack(children: [source]),
        navigator: navigator, boundary: boundary));
    await tester.pumpAndSettle();
    navigator.currentState!.push(_route(Stack(children: [
      Positioned(
          left: 20,
          top: 20,
          child: SizedBox.square(
              key: const ValueKey('late-header'),
              dimension: 112,
              child: PlaylistCoverRouteFlight(
                  playlistId: 'late',
                  borderRadius: AppShape.smallRadius,
                  child: FutureBuilder<drawing.Image>(
                      future: pending.future,
                      builder: (_, snapshot) => snapshot.data == null
                          ? const ColoredBox(color: Colors.blue)
                          : RawImage(
                              image: snapshot.data, fit: BoxFit.cover))))),
    ])));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect((await _pixel(tester, boundary, const Offset(76, 76))).toARGB32(),
        Colors.red.toARGB32(),
        reason: 'A slower destination codec must not flash its placeholder');
    expect(tester.binding.transientCallbackCount, 0);
    pending.complete(image);
    await tester.pump();
    await tester.pumpAndSettle();
    expect((await _pixel(tester, boundary, const Offset(76, 76))).toARGB32(),
        Colors.red.toARGB32());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final view in PlaylistViewMode.values) {
    testWidgets('${view.name} folder flies to detail header and back',
        (tester) async {
      sizePlaylistFeature(tester, width: 1080, height: 900);
      final browser = _Browser(imagePath);
      await tester.pumpWidget(
          _app(browser.browser(view), navigator: browser.navigator));
      await _decode(tester);
      await tester.pumpAndSettle();
      final tag = ('playlist-route-cover', browser.playlist.id);
      final hero = find.byWidgetPredicate((w) => w is Hero && w.tag == tag);
      expect(hero, findsOneWidget);
      final start = tester.getRect(hero);
      await browser.open(tester, view);
      final target =
          tester.getRect(find.byKey(const ValueKey('playlist-header-cover')));
      await tester.pump(const Duration(milliseconds: 100));
      final flight = find.byKey(const ValueKey('playlist-route-flight-image'));
      expect(flight, findsOneWidget);
      final middle = tester.getRect(flight);
      expect((middle.center - start.center).distance, greaterThan(1));
      expect((middle.center - target.center).distance,
          lessThan((start.center - target.center).distance));
      await tester.pump(const Duration(milliseconds: 120));
      final liveTarget =
          tester.getRect(find.byKey(const ValueKey('playlist-header-cover')));
      expect((tester.getRect(flight).center - liveTarget.center).distance,
          lessThan(2),
          reason:
              'The header has its own entrance; the Hero must track its live geometry');
      await _decode(tester);
      await tester.pumpAndSettle();
      expect(flight, findsNothing);
      expect(
          tester
              .getRect(find.byKey(const ValueKey('playlist-header-cover')))
              .center,
          liveTarget.center);
      browser.navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(flight, findsOneWidget);
      await tester.pumpAndSettle();
      expect(hero, findsOneWidget);
      expect(tester.getRect(hero), start);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('rapid reverse navigation retires old flight without idle work',
      (tester) async {
    sizePlaylistFeature(tester);
    final browser = _Browser(imagePath);
    await tester.pumpWidget(_app(browser.browser(PlaylistViewMode.circular),
        navigator: browser.navigator));
    await _decode(tester);
    await tester.pumpAndSettle();
    await browser.open(tester, PlaylistViewMode.circular);
    await tester.pump(const Duration(milliseconds: 80));
    browser.navigator.currentState!.pop();
    await tester.pump();
    await tester.pumpAndSettle();
    await browser.open(tester, PlaylistViewMode.circular);
    await _decode(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('playlist-header-cover')), findsOneWidget);
    expect(find.byKey(const ValueKey('playlist-route-flight-image')),
        findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tracking gate removes route placeholders and preserves content',
      (tester) async {
    final image = (await tester.runAsync(_image))!;
    addTearDown(image.dispose);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    var builds = 0;
    final artwork = StatefulBuilder(builder: (_, __) {
      builds++;
      return RawImage(image: image, fit: BoxFit.cover);
    });
    await tester.pumpWidget(_app(SizedBox.square(
        dimension: 48,
        child: PlaylistCoverRouteFlight(
            playlistId: 'gate',
            borderRadius: AppShape.smallRadius,
            child: artwork))));
    expect(find.byType(Hero), findsOneWidget);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pumpAndSettle();
    expect(find.byType(Hero), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    await tester.pumpAndSettle();
    expect(find.byType(Hero), findsOneWidget);
    for (final child in [
      MotionPreferencesScope(
          preferences: const MotionPreferences(disabled: {MotionKind.tracking}),
          child: artwork),
    ]) {
      await tester.pumpWidget(_app(MotionPreferencesScope(
          preferences: const MotionPreferences(disabled: {MotionKind.tracking}),
          child: SizedBox.square(
              dimension: 48,
              child: PlaylistCoverRouteFlight(
                  playlistId: 'gate',
                  borderRadius: AppShape.smallRadius,
                  child: child)))));
      expect(find.byType(Hero), findsNothing);
    }
    await tester.pumpWidget(_app(TickerMode(
        enabled: false,
        child: SizedBox.square(
            dimension: 48,
            child: PlaylistCoverRouteFlight(
                playlistId: 'gate',
                borderRadius: AppShape.smallRadius,
                child: artwork)))));
    expect(find.byType(Hero), findsNothing);
    await tester.pumpAndSettle();
    expect(builds, greaterThan(0));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets('route header ${language.name} narrow=$narrow',
          (tester) async {
        final oldLanguage = uiLanguage.value;
        addTearDown(() => uiLanguage.value = oldLanguage);
        uiLanguage.value = language;
        sizePlaylistFeature(tester, width: narrow ? 360 : 1080, height: 1000);
        final title = switch (language) {
          UiLanguage.zh => '喜欢的音乐与现场录音',
          UiLanguage.en => 'Favorite music and live recordings',
          UiLanguage.ja => 'お気に入りの音楽とライブ録音',
          UiLanguage.ko => '좋아하는 음악과 라이브 녹음',
        };
        final browser = _Browser(imagePath, title: title);
        final boundary = GlobalKey();
        await tester.pumpWidget(_app(browser.browser(PlaylistViewMode.circular),
            navigator: browser.navigator,
            boundary: boundary,
            textScale: narrow ? 2 : 1,
            reduce: true));
        await _decode(tester);
        await tester.pumpAndSettle();
        await browser.open(tester, PlaylistViewMode.circular);
        await _decode(tester);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('playlist-help')), findsNothing);
        expect(find.byKey(const ValueKey('playlist-header-cover')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePlaylistFeature(tester, boundary,
            'route-header-${language.name}-${narrow ? 'narrow-large' : 'wide'}');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
