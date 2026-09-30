import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:desktop_lyric/app_edge_stretch.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

// Run with the Windows profile executable and edge_stretch_driver.dart.
// Each case uses the real AppSortButton/PopupMenuRoute raster path, with the
// option count and placement of the four sorting surfaces under comparison.
class _Scene {
  const _Scene(this.name, this.optionCount, this.alignment,
      {this.insideDialog = false});
  final String name;
  final int optionCount;
  final Alignment alignment;
  final bool insideDialog;
}

Widget _sortButton(_Scene scene) => AppSortButton<int>(
      key: ValueKey('sort-${scene.name}'),
      value: 0,
      direction: SortDirection.ascending,
      onDirectionChanged: (_) {},
      onChanged: (_) {},
      maxWidth: scene.insideDialog ? 220 : null,
      helpText: '相同值保留原有次序。',
      options: [
        for (var index = 0; index < scene.optionCount; index++)
          AppSortOption(
            value: index,
            key: ValueKey('native-sort-$index'),
            label: index == 0 ? 'f l a c 3' : '排序字段 $index',
            icon: Icons.sort,
            group: switch (index) {
              0 => '原始顺序',
              1 => '歌曲信息',
              2 || 3 => '时间',
              _ => '歌单信息',
            },
          ),
      ],
    );

Widget _host(_Scene scene, GlobalKey boundary) => RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        scrollBehavior: const DanPlayerScrollBehavior(),
        theme: ThemeData(
          platform: TargetPlatform.windows,
          colorScheme: const ColorScheme.light(
            surface: Colors.white,
            surfaceContainer: Colors.white,
            onSurface: Colors.black,
          ),
        ),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: scene.insideDialog
              ? Builder(
                  builder: (context) => Center(
                    child: TextButton(
                      key: const ValueKey('open-probe-dialog'),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => Dialog(
                          child: SizedBox(
                            width: 588,
                            height: 420,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Align(
                                alignment: Alignment.topRight,
                                child: _sortButton(scene),
                              ),
                            ),
                          ),
                        ),
                      ),
                      child: const Text('Open dialog'),
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(40),
                  child: Align(
                    alignment: scene.alignment,
                    child: _sortButton(scene),
                  ),
                ),
        ),
      ),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sorting popup glyphs stay fixed across four route geometries',
      (tester) async {
    expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
    final boundary = GlobalKey();
    var windowHidden = false;
    for (final scene in const [
      _Scene('music', 16, Alignment.topRight),
      _Scene('playlist-root', 5, Alignment.topRight),
      _Scene('playlist-child', 17, Alignment.centerRight),
      _Scene('picker', 16, Alignment.topRight, insideDialog: true),
    ]) {
      await tester.pumpWidget(_host(scene, boundary));
      if (scene.insideDialog) {
        await tester.tap(find.byKey(const ValueKey('open-probe-dialog')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(ValueKey('sort-${scene.name}')));
      await tester.pumpAndSettle();
      if (!windowHidden) {
        await windowManager.ensureInitialized();
        await windowManager.hide();
        windowHidden = true;
      }

      final item = find.byKey(const ValueKey('native-sort-0'));
      expect(ModalRoute.of(tester.element(item)), isA<PopupRoute>());
      expect(find.byType(AppStretchingOverscrollIndicator), findsOneWidget);
      final label =
          find.descendant(of: item, matching: find.byType(Text)).first;
      final scroll = find
          .ancestor(of: item, matching: find.byType(SingleChildScrollView))
          .first;
      final scrollPosition = tester
          .state<ScrollableState>(
              find.descendant(of: scroll, matching: find.byType(Scrollable)))
          .position;
      expect(scrollPosition.maxScrollExtent, greaterThan(0),
          reason: '${scene.name} must have a real overscroll edge.');
      final effect =
          find.descendant(of: scroll, matching: find.byType(AppStretchEffect));
      expect(effect, findsOneWidget);
      final filtered =
          find.descendant(of: effect, matching: find.byType(ImageFiltered));
      for (var attempt = 0;
          attempt < 30 && filtered.evaluate().isEmpty;
          attempt++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(filtered, findsOneWidget,
          reason: 'Capture only after the native shader asset is ready.');
      final rect = tester.getRect(label).inflate(12);
      final profiles = <List<double>>[];
      profiles.add(await _inkProfile(tester, boundary, rect));

      final pull = await tester.createGesture(kind: PointerDeviceKind.touch);
      await pull.down(tester.getCenter(scroll));
      await pull.moveBy(const Offset(0, 30));
      await tester.pump();
      await pull.moveBy(const Offset(0, 90));
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.widget<AppStretchEffect>(effect).stretchStrength.abs(),
          greaterThan(0));
      profiles.add(await _inkProfile(tester, boundary, rect));
      await pull.up();
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        profiles.add(await _inkProfile(tester, boundary, rect));
      }
      await tester.pumpAndSettle();
      expect(tester.widget<AppStretchEffect>(effect).stretchStrength, 0);
      profiles.add(await _inkProfile(tester, boundary, rect));

      final spans = _spans(profiles.first);
      expect(spans.length, greaterThanOrEqualTo(5));
      var worst = 0.0;
      for (final (start, end) in spans) {
        final centers = [
          for (final profile in profiles) _center(profile, start, end),
        ];
        worst = math.max(
            worst, centers.reduce(math.max) - centers.reduce(math.min));
      }
      expect(worst, lessThan(.15),
          reason:
              '${scene.name} glyphs must not wobble across pull and spring.');
      debugPrint(
          'Native sorting popup ${scene.name} cross-axis drift: $worst px');
      Navigator.of(tester.element(item)).pop();
      await tester.pumpAndSettle();
      if (scene.insideDialog) {
        Navigator.of(tester.element(find.byType(Dialog))).pop();
        await tester.pumpAndSettle();
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<List<double>> _inkProfile(
    WidgetTester tester, GlobalKey boundary, Rect rect) async {
  final result = await tester.runAsync(() async {
    final ratio = tester.view.devicePixelRatio;
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage(pixelRatio: ratio);
    try {
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
      final profile = List<double>.filled(image.width, 0);
      final top = math.max(0, (rect.top * ratio).floor());
      final bottom = math.min(image.height, (rect.bottom * ratio).ceil());
      final left = math.max(0, (rect.left * ratio).floor());
      final right = math.min(image.width, (rect.right * ratio).ceil());
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          profile[x] += 255 - bytes[(y * image.width + x) * 4];
        }
      }
      return profile;
    } finally {
      image.dispose();
    }
  });
  return result!;
}

List<(int, int)> _spans(List<double> profile) {
  final spans = <(int, int)>[];
  int? start;
  for (var x = 0; x < profile.length; x++) {
    if (profile[x] > 10 && start == null) start = x;
    if (profile[x] <= 10 && start != null) {
      spans.add((math.max(0, start - 1), x + 1));
      start = null;
    }
  }
  return spans;
}

double _center(List<double> profile, int start, int end) {
  var mass = 0.0;
  var moment = 0.0;
  for (var x = start; x < end; x++) {
    mass += profile[x];
    moment += x * profile[x];
  }
  expect(mass, greaterThan(0));
  return moment / mass;
}
