import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_scrollbar.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

Widget _host(ScrollController controller,
    {bool explicit = true,
    bool reduced = false,
    bool horizontal = false,
    int count = 100,
    Brightness brightness = Brightness.light,
    GlobalKey? capture}) {
  final list = ListView.builder(
    controller: controller,
    itemExtent: 64,
    scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
    itemCount: count,
    itemBuilder: (_, index) => horizontal
        ? Center(child: Text('${index + 1}'))
        : ListTile(
            leading: const Icon(Symbols.music_note),
            title: Text('Song ${index + 1}'),
            trailing: const Icon(Symbols.more_vert),
          ),
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    scrollBehavior: const DanPlayerScrollBehavior(),
    theme: ThemeData(
        fontFamily: danEmbeddedFontFamily,
        platform: TargetPlatform.windows,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: brightness)),
    builder: (_, child) => MediaQuery(
        data: MediaQueryData(disableAnimations: reduced), child: child!),
    home: RepaintBoundary(
      key: capture,
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: explicit
              ? AppScrollbar(controller: controller, child: list)
              : list,
        ),
      ),
    ),
  );
}

ScrollbarPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.foregroundPainter)
    .whereType<ScrollbarPainter>()
    .single;

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  const output = String.fromEnvironment('DAN_SCROLLBAR_RENDER');
  if (output.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: raster.ImageByteFormat.png);
      final destination = File('$output/$name.png');
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
          ..addFont(rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
        .load();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'scroll, idle fade, hover and drag remain usable in $brightness',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final capture = GlobalKey();
      await tester.pumpWidget(
          _host(controller, brightness: brightness, capture: capture));
      await tester.pumpAndSettle();
      expect(find.byType(AppScrollbar), findsOneWidget,
          reason: 'an explicit scrollbar must suppress the automatic one');
      final painter = _painter(tester);
      expect(painter.fadeoutOpacityAnimation.value, 0);
      controller.jumpTo(120);
      await tester.pump();
      await tester.pump(AppMotion.standard);
      expect(painter.fadeoutOpacityAnimation.value, 1);
      await _capture(tester, capture, '${brightness.name}-scrolling');
      await tester.pump(AppScrollbar.idleDelay);
      await tester.pump(AppMotion.standard);
      expect(painter.fadeoutOpacityAnimation.value, 0);
      expect(controller.offset, 120);
      await _capture(tester, capture, '${brightness.name}-idle');

      final bounds = tester.getRect(find.byType(AppScrollbar));
      final hover = Offset(bounds.right - 5, bounds.top + 24);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: hover - const Offset(40, 0));
      await mouse.moveTo(hover);
      await tester.pumpAndSettle();
      expect(painter.fadeoutOpacityAnimation.value, 1);
      expect(
          painter.color,
          Theme.of(tester.element(find.byType(AppScrollbar)))
              .colorScheme
              .primary
              .withValues(alpha: .8));
      await tester.pump(const Duration(seconds: 2));
      expect(painter.fadeoutOpacityAnimation.value, 1,
          reason: 'the thumb must remain available under the pointer');
      await mouse.down(hover);
      await mouse.moveBy(const Offset(0, 100));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(painter.fadeoutOpacityAnimation.value, 1);
      await mouse.up();
      expect(controller.offset, greaterThan(120));
      await mouse.moveTo(bounds.center);
      await tester.pump(AppScrollbar.idleDelay);
      await tester.pump(AppMotion.standard);
      expect(painter.fadeoutOpacityAnimation.value, 0);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('automatic desktop scrollbar keeps the same idle behavior',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, explicit: false));
    await tester.pumpAndSettle();
    expect(find.byType(AppScrollbar), findsOneWidget);
    controller.jumpTo(160);
    await tester.pump();
    await tester.pump(AppMotion.standard);
    expect(_painter(tester).fadeoutOpacityAnimation.value, 1);
    await tester.pump(AppScrollbar.idleDelay);
    await tester.pump(AppMotion.standard);
    expect(_painter(tester).fadeoutOpacityAnimation.value, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('no overflow and automatic horizontal views do not paint bars',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, count: 2));
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(AppScrollbar));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: bounds.center);
    await mouse.moveTo(Offset(bounds.right - 5, bounds.top + 24));
    await tester.pumpAndSettle();
    expect(_painter(tester).fadeoutOpacityAnimation.value, 0);
    await mouse.removePointer();
    await tester
        .pumpWidget(_host(controller, explicit: false, horizontal: true));
    await tester.pumpAndSettle();
    expect(find.byType(AppScrollbar), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion can change without replacing scroll position',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();
    controller.jumpTo(160);
    await tester.pumpAndSettle();
    final position = controller.position;
    await tester.pumpWidget(_host(controller, reduced: true));
    expect(controller.position, same(position));
    expect(controller.offset, 160);
    final animation =
        _painter(tester).fadeoutOpacityAnimation as CurvedAnimation;
    expect((animation.parent as AnimationController).duration, Duration.zero);
    await tester.pump(AppScrollbar.idleDelay);
    await tester.pump();
    expect(animation.value, 0);
    controller.jumpTo(200);
    await tester.pump();
    expect(animation.value, 1);
    await tester.pumpWidget(_host(controller));
    expect(
        (animation.parent as AnimationController).duration, AppMotion.standard);
    expect(controller.position, same(position));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('independent nested views retain their own automatic scrollbar',
      (tester) async {
    final outer = ScrollController();
    final inner = ScrollController();
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    await tester.pumpWidget(MaterialApp(
      scrollBehavior: const DanPlayerScrollBehavior(),
      theme: ThemeData(platform: TargetPlatform.windows),
      home: Scaffold(
        body: ListView(controller: outer, children: [
          SizedBox(
              height: 240,
              child: ListView.builder(
                controller: inner,
                itemCount: 100,
                itemExtent: 48,
                itemBuilder: (_, i) => Text('Nested $i'),
              )),
          const SizedBox(height: 1000),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AppScrollbar), findsNWidgets(2));
    inner.jumpTo(120);
    await tester.pumpAndSettle();
    expect(inner.offset, 120);
    expect(outer.offset, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('explicit horizontal thumb fades and can be dragged after idle',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, horizontal: true));
    await tester.pumpAndSettle();
    expect(find.byType(AppScrollbar), findsOneWidget);
    final bounds = tester.getRect(find.byType(AppScrollbar));
    final hover = Offset(bounds.left + 24, bounds.bottom - 5);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: bounds.center);
    await mouse.moveTo(hover);
    await tester.pumpAndSettle();
    expect(_painter(tester).fadeoutOpacityAnimation.value, 1);
    await mouse.down(hover);
    await mouse.moveBy(const Offset(100, 0));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(100));
    await mouse.moveTo(bounds.center);
    await tester.pump(AppScrollbar.idleDelay);
    await tester.pump(AppMotion.standard);
    expect(_painter(tester).fadeoutOpacityAnimation.value, 0);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('runtime platform reduceMotion changes scrollbar duration',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_host(controller));
    await tester.pumpAndSettle();
    final animation =
        _painter(tester).fadeoutOpacityAnimation as CurvedAnimation;
    expect(
        (animation.parent as AnimationController).duration, AppMotion.standard);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();
    expect((animation.parent as AnimationController).duration, Duration.zero);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
