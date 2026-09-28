import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_route_transition.dart';
import 'package:dan_player/component/app_shell.dart';
import 'package:desktop_lyric/app_edge_stretch.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:dan_player/page/page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

// Compare the production scroll/filter/entrance order with GitHub's original
// resting scroll path. Do not substitute a coloured shell for the page header.
class _GithubScrollBehavior extends DanPlayerScrollBehavior {
  const _GithubScrollBehavior();
  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      StretchingOverscrollIndicator(
          axisDirection: details.direction, child: child);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('production page entrance retains its raster origin',
      (tester) async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await windowManager.ensureInitialized();
    await windowManager.hide();
    final boundary = GlobalKey();
    final route = AnimationController(vsync: tester);
    addTearDown(route.dispose);
    final results = <String, Object>{};
    for (final current in [true, false]) {
      for (final ratio in [1.0, 1.25, 1.5]) {
        await tester.pumpWidget(const SizedBox());
        route.value = 0;
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                scrollBehavior: current
                    ? const DanPlayerScrollBehavior()
                    : const _GithubScrollBehavior(),
                theme: ThemeData(
                    fontFamily: danEmbeddedFontFamily,
                    colorScheme: ColorScheme.fromSeed(seedColor: Colors.red)
                        .copyWith(
                            surface: Colors.white, onSurface: Colors.black)),
                home: Scaffold(
                    body: Transform.translate(
                        offset: const Offset(.35, .2),
                        child: Padding(
                            padding: const EdgeInsets.only(left: 75, top: 48),
                            child: AppContentSurface(
                                child: AppRouteTransition(
                                    animation: route,
                                    child: const PageScaffold(
                                        title: '音乐 Music 分类',
                                        subtitle: '666 首歌曲',
                                        actions: [],
                                        body: SizedBox())))))))));
        debugPrint('filter support=${ui.ImageFilter.isShaderFilterSupported} '
            'current=$current effects=${find.byType(AppStretchEffect).evaluate().length}');
        final progress = tester
            .widget<AnimatedBuilder>(find
                .descendant(
                  of: find.byType(AppEntrance).first,
                  matching: find.byType(AnimatedBuilder),
                )
                .first)
            .animation as AnimationWithParentMixin<double>;
        final clock = progress.parent as AnimationController;
        // Native screenshot readback consumes wall time. Freeze the actual
        // production controller so no entry frames disappear during capture.
        clock.stop();
        final profiles = <List<double>>[];
        final vertical = <List<double>>[];
        final label = '${current ? 'current' : 'github'}-$ratio';
        for (var frame = 0; frame < 24; frame++) {
          clock.value = frame / 23;
          route.value = frame / 23;
          await tester.pump();
          final sample = await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: tester.view.devicePixelRatio * ratio);
            try {
              final pixels =
                  (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                      .buffer
                      .asUint8List();
              final dpr = tester.view.devicePixelRatio * ratio;
              final xProfile = List<double>.filled(image.width, 0);
              final yProfile = List<double>.filled(image.height, 0);
              for (var y = (64 * dpr).floor(); y < (158 * dpr).floor(); y++) {
                for (var x = (99 * dpr).floor(); x < (395 * dpr).floor(); x++) {
                  final ink = 255 - pixels[(y * image.width + x) * 4];
                  xProfile[x] += ink;
                  yProfile[y] += ink;
                }
              }
              const output = String.fromEnvironment('DAN_ORIGIN_RENDER');
              if (output.isNotEmpty) {
                final file = File('$output/$label-$frame.png');
                await file.parent.create(recursive: true);
                await file.writeAsBytes(
                    (await image.toByteData(format: ui.ImageByteFormat.png))!
                        .buffer
                        .asUint8List());
              }
              return (xProfile, yProfile);
            } finally {
              image.dispose();
            }
          });
          profiles.add(sample!.$1);
          vertical.add(sample.$2);
        }
        final xShifts = [
          for (final profile in profiles.skip(2)) _shift(profiles.last, profile)
        ];
        final yShifts = [
          for (final profile in vertical.skip(2))
            _shift(vertical.last, profile, radius: 15)
        ];
        final worst = xShifts.map((v) => v.abs()).reduce(math.max);
        debugPrint('$label X=$xShifts Y=$yShifts');
        results[label] = {'maxX': worst, 'x': xShifts, 'y': yShifts};
      }
    }
    const output = String.fromEnvironment('DAN_ORIGIN_RENDER');
    if (output.isNotEmpty) {
      await File('$output/metrics.json').writeAsString(jsonEncode(results));
    }
    if (!const bool.fromEnvironment('DAN_ORIGIN_DIAGNOSE')) {
      for (final result
          in results.entries.where((r) => r.key.startsWith('current'))) {
        expect((result.value as Map)['maxX'], lessThan(.05),
            reason: result.key);
      }
    }
  });
}

double _shift(List<double> reference, List<double> current, {int radius = 3}) {
  double correlation(int delta) {
    var sum = 0.0;
    for (var i = radius + 1; i < reference.length - radius - 1; i++) {
      sum += reference[i] * current[i + delta];
    }
    return sum;
  }

  var best = 0;
  for (var delta = -radius; delta <= radius; delta++) {
    if (correlation(delta) > correlation(best)) best = delta;
  }
  final left = correlation(best - 1),
      center = correlation(best),
      right = correlation(best + 1);
  final denominator = left - 2 * center + right;
  return best + (denominator == 0 ? 0 : .5 * (left - right) / denominator);
}
