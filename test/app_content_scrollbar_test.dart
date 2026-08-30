import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MaterialApp(
      scrollBehavior: const DanPlayerScrollBehavior(),
      theme: ThemeData(
        platform: TargetPlatform.windows,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: Directionality(
        textDirection: direction,
        child: Scaffold(body: child),
      ),
    );

Widget _list(ScrollController controller, {VoidCallback? onAction}) =>
    ListView.builder(
      controller: controller,
      itemExtent: 64,
      itemCount: 100,
      itemBuilder: (_, index) => SizedBox(
        key: ValueKey('row-$index'),
        child: Row(
          children: [
            Expanded(child: Text('Song $index')),
            IconButton(
              key: ValueKey('menu-$index'),
              onPressed: onAction ?? () {},
              icon: const Icon(Icons.more_vert),
            ),
          ],
        ),
      ),
    );

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('Material thumb has a separate lane in $direction',
        (tester) async {
      await tester.pumpWidget(_host(
        AppContentScrollbar(builder: (_, controller) => _list(controller)),
        direction: direction,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(Scrollbar), findsOneWidget,
          reason: 'the Windows automatic scrollbar must not duplicate it');
      final outer = tester.getRect(find.byType(AppContentScrollbar));
      final row = tester.getRect(find.byKey(const ValueKey('row-0')));
      final menu = tester.getRect(find.byKey(const ValueKey('menu-0')));
      if (direction == TextDirection.ltr) {
        expect(outer.right - row.right, AppContentScrollbar.gutter);
        expect(menu.right, lessThanOrEqualTo(row.right));
        expect(row.left, outer.left);
      } else {
        expect(row.left - outer.left, AppContentScrollbar.gutter);
        expect(menu.left, greaterThanOrEqualTo(row.left));
        expect(row.right, outer.right);
      }
      final scrollContext = tester.element(find.byType(ListView));
      final theme = ScrollbarTheme.of(scrollContext);
      expect(theme.thickness!.resolve({}), AppContentScrollbar.thumbThickness);
      expect(theme.thickness!.resolve({WidgetState.hovered}),
          AppContentScrollbar.activeThumbThickness);
      expect(theme.crossAxisMargin, AppContentScrollbar.crossAxisMargin);
      expect(
          AppContentScrollbar.gutter -
              AppContentScrollbar.crossAxisMargin -
              AppContentScrollbar.activeThumbThickness,
          greaterThanOrEqualTo(12));
      expect(theme.thumbColor!.resolve({WidgetState.dragged}),
          Theme.of(scrollContext).colorScheme.primary.withValues(alpha: .95));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('thumb drag scrolls without triggering the trailing menu',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var actions = 0;
    await tester.pumpWidget(_host(AppContentScrollbar(
      controller: controller,
      builder: (_, controller) => _list(controller, onAction: () => actions++),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-0')));
    expect(actions, 1);
    final bounds = tester.getRect(find.byType(AppContentScrollbar));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset(bounds.right - 7, bounds.top + 20));
    await tester.pumpAndSettle();
    await mouse.down(Offset(bounds.right - 7, bounds.top + 20));
    await mouse.moveBy(const Offset(0, 130));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(100));
    expect(actions, 1);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('controller replacement, disposal and input policy stay safe',
      (tester) async {
    final first = ScrollController();
    final second = ScrollController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget app(ScrollController controller) => _host(AppContentScrollbar(
          controller: controller,
          builder: (_, controller) => _list(controller),
        ));
    await tester.pumpWidget(app(first));
    await tester.pumpAndSettle();
    final behavior =
        ScrollConfiguration.of(tester.element(find.byType(ListView)));
    expect(behavior.dragDevices, contains(PointerDeviceKind.touch));
    expect(behavior.dragDevices, contains(PointerDeviceKind.trackpad));
    expect(behavior.dragDevices, isNot(contains(PointerDeviceKind.mouse)));
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(first.offset, greaterThan(0));
    await tester.pumpWidget(app(second));
    await tester.pumpAndSettle();
    expect(first.hasClients, isFalse);
    expect(second.positions, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    // The wrapper owns only its fallback, never a caller's controller.
    first.addListener(() {});
    second.addListener(() {});
    expect(second.hasClients, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final mode in ['list', 'grid', 'reorder']) {
    testWidgets('UniPage $mode keeps its content inside the shared lane',
        (tester) async {
      final reorder = mode == 'reorder';
      await tester.pumpWidget(_host(UniPage<int>(
        pref: PagePreference(0, SortOrder.ascending,
            mode == 'grid' ? ContentView.table : ContentView.list),
        title: 'Library fixture',
        contentList: List.generate(50, (index) => index),
        contentBuilder: (_, item, index, selection) => ListTile(
          key: ValueKey('library-$item'),
          title: Text('Song $item'),
          trailing: IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_vert),
          ),
        ),
        enableShufflePlay: false,
        enableSortMethod: false,
        enableSortOrder: false,
        enableContentViewSwitch: false,
        sortMethods: reorder
            ? [
                SortMethodDesc<int>(
                  icon: Icons.sort,
                  name: 'Custom',
                  method: (_, order) {},
                  supportsReorder: true,
                ),
              ]
            : null,
      )));
      await tester.pumpAndSettle();
      expect(find.byType(AppContentScrollbar), findsOneWidget);
      final scrollbar = find.descendant(
          of: find.byType(AppContentScrollbar),
          matching: find.byType(Scrollbar));
      expect(scrollbar, findsOneWidget);
      final outer = tester.getRect(scrollbar);
      final content = tester.getRect(find.byKey(const ValueKey('library-0')));
      expect(content.right,
          lessThanOrEqualTo(outer.right - AppContentScrollbar.gutter));
      if (reorder) {
        final handle = find.byType(ReorderableDragStartListener).first;
        expect(tester.getRect(handle).right,
            lessThanOrEqualTo(outer.right - AppContentScrollbar.gutter));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
