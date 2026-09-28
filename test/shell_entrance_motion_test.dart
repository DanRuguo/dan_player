import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Colour patches expose movement of the entire surface, independently of text
// shaping. Rendered pixels also catch Material's snapshot painter transforms,
// which are invisible to a descendant RenderBox.localToGlobal probe.
Widget _page(String id) => ColoredBox(
    color: Colors.white,
    child: AppEntranceScope(
        child: AppEntrance(
            identity: id,
            child: Stack(children: [
              Positioned(
                  left: 32,
                  top: 180,
                  width: 150,
                  height: 64,
                  child: ColoredBox(
                      color: id == 'lyrics'
                          ? const Color(0xff00ff00)
                          : const Color(0xff0000ff))),
            ]))));

Widget _chrome(Widget page) => ColoredBox(
    color: Colors.white,
    child: Stack(fit: StackFit.expand, children: [
      const Positioned(
          left: 16,
          top: 16,
          width: 24,
          height: 70,
          child: ColoredBox(color: Color(0xffff0000))),
      Positioned.fill(left: 64, top: 100, child: page),
    ]));

Future<Map<String, Rect>> _pixels(
        WidgetTester tester, GlobalKey key, String name) async =>
    (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      try {
        final pixels =
            (await image.toByteData(format: drawing.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
        const output = String.fromEnvironment('DAN_SHELL_RENDER');
        if (output.isNotEmpty) {
          final file = File('$output/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(
              (await image.toByteData(format: drawing.ImageByteFormat.png))!
                  .buffer
                  .asUint8List());
        }
        final bounds = <String, Rect>{};
        for (var y = 0; y < image.height; y++) {
          for (var x = 0; x < image.width; x++) {
            final at = (y * image.width + x) * 4;
            final r = pixels[at], g = pixels[at + 1], b = pixels[at + 2];
            final kind = r - g > 10 && r - b > 10
                ? 'chrome'
                : g - r > 10 && g - b > 10
                    ? 'lyrics'
                    : b - r > 10 && b - g > 10
                        ? 'content'
                        : null;
            if (kind != null) {
              final pixel = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1);
              bounds[kind] = bounds[kind]?.expandToInclude(pixel) ?? pixel;
            }
          }
        }
        return bounds;
      } finally {
        image.dispose();
      }
    }))!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('shell, peer pages and lyric route never move horizontally',
      (tester) async {
    const baseline = bool.fromEnvironment('DAN_SHELL_BASELINE');
    final entry = Entry(welcome: false);
    final productionShell =
        entry.config.configuration.routes.first as ShellRoute;
    addTearDown(entry.config.dispose);
    final router = GoRouter(initialLocation: '/outside', routes: [
      GoRoute(
          path: '/outside',
          pageBuilder: (_, state) => SlideTransitionPage(
              key: state.pageKey,
              child: const ColoredBox(color: Colors.white))),
      ShellRoute(
        pageBuilder: (context, state, page) {
          if (baseline) {
            return MaterialPage(key: state.pageKey, child: _chrome(page));
          }
          // Exercise the production shell page builder, substituting only the
          // chrome's native audio/window consumers with deterministic patches.
          final shellPage = productionShell.pageBuilder!(context, state, page);
          if (shellPage is! AppShellPage) {
            throw StateError(
                'The production shell must bypass platform motion');
          }
          return AppShellPage(key: shellPage.key, child: _chrome(page));
        },
        routes: [
          for (final id in ['music', 'settings'])
            GoRoute(
                path: '/$id',
                pageBuilder: (_, state) =>
                    SlideTransitionPage(key: state.pageKey, child: _page(id))),
        ],
      ),
      GoRoute(
          path: '/lyrics',
          pageBuilder: (_, state) =>
              SlideTransitionPage(key: state.pageKey, child: _page('lyrics'))),
    ]);
    addTearDown(router.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(platform: TargetPlatform.windows),
        routerConfig: router,
        builder: (_, child) => RepaintBoundary(key: boundary, child: child!)));
    await tester.pumpAndSettle();

    Future<void> sample(String stage,
        {required double contentLeft,
        bool chrome = true,
        String contentKind = 'content'}) async {
      final frames = <Map<String, Rect>>[];
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 24));
        frames.add(await _pixels(tester, boundary, '$stage-$i'));
      }
      await tester.pumpAndSettle();
      final finalPixels = await _pixels(tester, boundary, '$stage-settled');
      final contentFrames =
          frames.where((frame) => frame.containsKey(contentKind)).toList();
      expect(contentFrames.length, greaterThan(2));
      final content = finalPixels[contentKind]!;
      expect(content.left, closeTo(contentLeft, 1));
      final shifts = [
        for (final frame in contentFrames)
          (frame[contentKind]!.left - content.left).abs()
      ];
      debugPrint('$stage content horizontal drift: ${shifts.reduce(math.max)}');
      expect(shifts.reduce(math.max), lessThanOrEqualTo(1));
      for (final frame in contentFrames) {
        expect(frame[contentKind]!.width, closeTo(150, 1));
      }
      if (chrome) {
        final chromeFrames =
            frames.where((frame) => frame.containsKey('chrome')).toList();
        expect(chromeFrames.length, greaterThan(2));
        final drift = [
          for (final frame in chromeFrames) (frame['chrome']!.left - 16).abs()
        ].reduce(math.max);
        debugPrint('$stage shell horizontal drift: $drift');
        expect(drift, lessThanOrEqualTo(1));
        for (final frame in chromeFrames) {
          expect(frame['chrome']!.width, closeTo(24, 1));
        }
      }
      expect(tester.takeException(), isNull);
    }

    router.go('/music');
    await sample('startup', contentLeft: 96);
    router.go('/settings');
    await sample('sidebar', contentLeft: 96);
    router.push('/lyrics');
    await sample('lyrics',
        contentLeft: 32, chrome: false, contentKind: 'lyrics');
    router.pop();
    await sample('return', contentLeft: 96);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
