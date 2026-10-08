import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:dan_player/component/app_fonts.dart';
import 'package:desktop_lyric/app_edge_stretch.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('hover shadow and focused border do not move dialog neighbours',
      (tester) async {
    expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    final boundary = GlobalKey(), label = GlobalKey();
    final fieldFocus = FocusNode();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                fontFamily: danEmbeddedFontFamily,
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
            home: Scaffold(
                backgroundColor: Colors.white,
                body: Center(
                    child: Transform.translate(
                        offset: const Offset(.35, .2),
                        child: Material(
                            color: Colors.white,
                            child: SizedBox(
                                width: 480,
                                height: 380,
                                child: ClipRect(
                                    clipper: const AppStretchViewportClipper(
                                        Axis.vertical),
                                    child: AppStretchEffect(
                                        axis: Axis.vertical,
                                        stretchStrength: 0,
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const SizedBox(height: 20),
                                              const Text(
                                                  '保存喜欢的位置或 A-B 片段，下次打开这首歌仍可使用。'),
                                              const SizedBox(height: 30),
                                              TextField(
                                                  focusNode: fieldFocus,
                                                  decoration: const InputDecoration(
                                                      labelText: '书签名称（可选）',
                                                      border:
                                                          OutlineInputBorder())),
                                              const SizedBox(height: 16),
                                              FilledButton(
                                                  onPressed: () {},
                                                  child: const Text('保存所选时间')),
                                              const SizedBox(height: 24),
                                              Text('还没有书签，先保存一个喜欢的位置吧。',
                                                  key: label,
                                                  style: const TextStyle(
                                                      fontSize: 16,
                                                      color: Colors.black)),
                                              const SizedBox(height: 16),
                                              SizedBox(
                                                  width: double.infinity,
                                                  child: OutlinedButton(
                                                      onPressed: () {},
                                                      child:
                                                          const Text('导出歌词'))),
                                            ])))))))))));
    await tester.pumpAndSettle();
    await windowManager.ensureInitialized();
    await windowManager.hide();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    final profiles = <List<double>>[];
    final edgeRatios = <double>[];
    for (var frame = 0; frame < 49; frame++) {
      if (frame == 1) {
        await mouse.moveTo(tester.getCenter(find.byType(FilledButton)));
      }
      if (frame == 13) await mouse.moveTo(const Offset(1, 1));
      if (frame == 25) fieldFocus.requestFocus();
      if (frame == 37) fieldFocus.unfocus();
      await tester.pump(const Duration(milliseconds: 16));
      final rect = tester.getRect(find.byKey(label)).inflate(8);
      final borders = [
        tester.getRect(find.byType(TextField)),
        tester.getRect(find.byType(OutlinedButton))
      ];
      final profile = await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
        final ink = List<double>.filled(image.width, 0);
        if (frame == 24 || frame == 36 || frame == 48) {
          for (final field in borders) {
            // Integrate all antialiasing texels on the straight side strokes.
            // Removing the viewport ink guard loses ~37% of the left border.
            double side(double edge) {
              var mass = 0.0;
              for (var y = field.center.dy.floor() - 5;
                  y < field.center.dy.floor() + 5;
                  y++) {
                for (var x = edge.floor() - 4; x <= edge.ceil() + 4; x++) {
                  mass += 255 - bytes[(y * image.width + x) * 4];
                }
              }
              return mass;
            }

            final left = side(field.left), right = side(field.right);
            expect(left, greaterThan(0));
            expect(right, greaterThan(0));
            final ratio = left / right;
            edgeRatios.add(ratio);
            expect(ratio, closeTo(1, .03),
                reason:
                    'Both side borders must survive idle/focus/blur ($frame)');
          }
        }
        for (var y = rect.top.floor(); y < rect.bottom.ceil(); y++) {
          for (var x = rect.left.floor(); x < rect.right.ceil(); x++) {
            ink[x] += 255 - bytes[(y * image.width + x) * 4];
          }
        }
        const output = String.fromEnvironment('DAN_DIALOG_FILTER_RENDER');
        if (output.isNotEmpty && [0, 7, 12, 24, 31, 36, 48].contains(frame)) {
          final file = File('$output/frame-$frame.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(
              (await image.toByteData(format: ui.ImageByteFormat.png))!
                  .buffer
                  .asUint8List());
        }
        image.dispose();
        return ink;
      });
      profiles.add(profile!);
    }
    double shift(List<double> current) {
      double c(int delta) {
        var s = 0.0;
        for (var x = 3; x < current.length - 3; x++) {
          s += profiles.first[x] * current[x + delta];
        }
        return s;
      }

      var peak = 0;
      for (var i = -2; i <= 2; i++) {
        if (c(i) > c(peak)) peak = i;
      }
      return peak +
          .5 *
              (c(peak - 1) - c(peak + 1)) /
              (c(peak - 1) - 2 * c(peak) + c(peak + 1));
    }

    final shifts = profiles.map(shift).toList();
    final worst = shifts.map((v) => v.abs()).reduce(math.max);
    debugPrint('Dialog neighbour displacement=$worst');
    const output = String.fromEnvironment('DAN_DIALOG_FILTER_RENDER');
    if (output.isNotEmpty) {
      await File('$output/metrics.json').writeAsString(jsonEncode(
          {'worst': worst, 'shifts': shifts, 'borderRatios': edgeRatios}));
    }
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    fieldFocus.dispose();
    if (!const bool.fromEnvironment('DAN_RECORD_BASELINE')) {
      expect(worst, lessThan(.05));
    }
  });
}
