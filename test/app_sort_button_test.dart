import 'dart:ui';

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/component/app_scrollbar.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture extends ChangeNotifier {
  int value = 0;
  SortDirection? direction = SortDirection.ascending;
  bool enabled = true;
  bool current = true;
  Object scope = 'first-page';
  final calls = <Object>[];
  List<AppSortOption<int>> options = const [
    AppSortOption(
        value: 0,
        label: '名称',
        icon: Icons.sort_by_alpha,
        key: ValueKey('method-name'),
        group: '歌曲信息'),
    AppSortOption(
        value: 1,
        label: '艺术家',
        icon: Icons.person_outline,
        key: ValueKey('method-artist'),
        group: '歌曲信息'),
    AppSortOption(
        value: 2,
        label: '文件大小',
        icon: Icons.storage_outlined,
        key: ValueKey('method-size'),
        group: '文件与来源'),
  ];

  void changed() => notifyListeners();

  Widget build() => AppSortButton<int>(
        key: const ValueKey('shared-sort'),
        value: value,
        direction: direction,
        scopeId: scope,
        options: options,
        enabled: enabled,
        isCurrent: () => current,
        helpText: '缺失信息始终排在最后。',
        onChanged: (next) {
          calls.add(next);
          value = next;
          notifyListeners();
        },
        onDirectionChanged: (next) {
          calls.add(next);
          direction = next;
          notifyListeners();
        },
      );
}

Widget _app(_Fixture fixture,
        {double scale = 1,
        bool reduced = false,
        bool ticker = true,
        Brightness brightness = Brightness.light,
        double? fontSize}) =>
    MaterialApp(
      scrollBehavior: const DanPlayerScrollBehavior(),
      theme: ThemeData(
        useMaterial3: true,
        platform: TargetPlatform.windows,
        visualDensity: VisualDensity.compact,
        textTheme: fontSize == null
            ? null
            : TextTheme(labelLarge: TextStyle(fontSize: fontSize, height: 1.5)),
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue, brightness: brightness),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale), disableAnimations: reduced),
        child: TickerMode(enabled: ticker, child: child!),
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListenableBuilder(
                listenable: fixture, builder: (_, __) => fixture.build()),
          ),
        ),
      ),
    );

Finder _sort() => find.byKey(const ValueKey('shared-sort'));
Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _open(WidgetTester tester) async {
  await tester.tap(_sort());
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows field and direction, with one menu and a 44px target',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture));
    expect(find.text('名称 · 升序'), findsOneWidget);
    expect(find.byTooltip('排序：名称 · 升序'), findsOneWidget);
    expect(tester.getSize(_sort()).height, 44);
    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(button.style!.shape!.resolve({}), AppShape.control);
    expect(button.style!.visualDensity, VisualDensity.standard);
    await _open(tester);
    expect(find.text('歌曲信息'), findsOneWidget);
    expect(find.text('文件与来源'), findsOneWidget);
    for (final key in [
      'method-name',
      'method-artist',
      'method-size',
      'app-sort-direction-ascending',
      'app-sort-direction-descending'
    ]) {
      expect(tester.getSize(_key(key)).height, greaterThanOrEqualTo(48));
    }
    await _choose(tester, 'method-artist');
    expect(fixture.calls, [1]);
    expect(find.text('艺术家 · 升序'), findsOneWidget);
    await _open(tester);
    await _choose(tester, 'app-sort-direction-descending');
    expect(fixture.calls, [1, SortDirection.descending]);
    expect(find.text('艺术家 · 降序'), findsOneWidget);
  });

  testWidgets(
      'null direction preserves custom order without fake direction rows',
      (tester) async {
    final fixture = _Fixture()
      ..direction = null
      ..options = const [
        AppSortOption(value: 0, label: '自定义', icon: Icons.drag_handle)
      ];
    await tester.pumpWidget(_app(fixture));
    expect(find.text('自定义'), findsOneWidget);
    await _open(tester);
    expect(_key('app-sort-direction-ascending'), findsNothing);
    expect(_key('app-sort-direction-descending'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(fixture.calls, isEmpty);
  });

  testWidgets('keyboard opens, focuses an option, selects, and dismisses',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture));
    Focus.of(tester.element(find.text('名称 · 升序'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_key('method-artist'), findsOneWidget);
    Focus.of(tester.element(find.text('艺术家'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fixture.calls, [1]);
    await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_key('method-artist'), findsNothing);
    expect(fixture.calls, [1]);
  });

  testWidgets('right click and long press open the same actionable menu',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture));
    await tester.tap(_sort(),
        buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await _choose(tester, 'method-artist');
    await tester.longPress(_sort());
    await tester.pumpAndSettle();
    await _choose(tester, 'method-name');
    expect(fixture.calls, [1, 0]);
  });

  for (final condition in [
    'disabled',
    'scope',
    'method',
    'mode',
    'removed-option'
  ]) {
    testWidgets('late popup result cannot cross $condition changes',
        (tester) async {
      final fixture = _Fixture();
      await tester.pumpWidget(_app(fixture));
      await _open(tester);
      switch (condition) {
        case 'disabled':
          fixture.enabled = false;
        case 'scope':
          fixture.scope = 'next-page';
        case 'method':
          fixture.value = 2;
        case 'mode':
          fixture.current = false;
        case 'removed-option':
          fixture.options = [fixture.options.first];
      }
      fixture.changed();
      await tester.pump();
      await _choose(tester, 'method-artist');
      expect(fixture.calls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'ordinary rebuild with recreated options keeps current menu valid',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture));
    await _open(tester);
    fixture.options = [
      for (final option in fixture.options)
        AppSortOption(
            value: option.value,
            label: option.label,
            icon: option.icon,
            key: option.key,
            group: option.group)
    ];
    fixture.changed();
    await tester.pump();
    await _choose(tester, 'method-artist');
    expect(fixture.calls, [1]);
  });

  testWidgets(
      'disabled capsule has no tap, secondary tap, or long press action',
      (tester) async {
    final fixture = _Fixture()..enabled = false;
    await tester.pumpWidget(_app(fixture));
    await tester.tap(_sort());
    await tester.tap(_sort(),
        buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.longPress(_sort());
    await tester.pumpAndSettle();
    expect(_key('method-name'), findsNothing);
    expect(fixture.calls, isEmpty);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'bounded scroll menu and unscaled 200% labels in ${brightness.name}',
        (tester) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(640, 960);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fixture = _Fixture()
        ..options = [
          for (var index = 0; index < 25; index++)
            AppSortOption(
                value: index,
                label: '非常长的真实排序字段 $index',
                icon: Icons.sort,
                key: ValueKey('long-$index'),
                group: index < 12 ? '歌曲信息' : '文件与来源')
        ];
      await tester.pumpWidget(
          _app(fixture, scale: 2, brightness: brightness, fontSize: 20));
      final bounds = tester.getRect(_sort());
      expect(bounds.width, lessThanOrEqualTo(288));
      expect(bounds.height, greaterThan(60));
      final text = find.descendant(of: _sort(), matching: find.byType(Text));
      final textRect = tester.getRect(text.first);
      expect(textRect.top, greaterThanOrEqualTo(bounds.top));
      expect(textRect.bottom, lessThanOrEqualTo(bounds.bottom));
      await _open(tester);
      expect(_key('app-sort-scroll-hint'), findsOneWidget);
      final scroll = find.byType(SingleChildScrollView).last;
      expect(tester.getSize(scroll).height, lessThanOrEqualTo(432));
      final scrollbars =
          find.descendant(of: scroll, matching: find.byType(AppScrollbar));
      expect(scrollbars, findsOneWidget);
      final scrollbarTheme = ScrollbarTheme.of(tester.element(scrollbars));
      expect(scrollbarTheme.thumbVisibility?.resolve({}), isNot(isTrue));
      await _choose(tester, 'long-24');
      expect(fixture.calls, [24]);
      expect(tester.takeException(), isNull);
    });
  }

  for (final mode in [
    'media',
    'platform-disable',
    'platform-reduce',
    'ticker'
  ]) {
    testWidgets('$mode reduced motion renders final control and instant popup',
        (tester) async {
      final fixture = _Fixture();
      if (mode.startsWith('platform')) {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(
                disableAnimations: mode == 'platform-disable',
                reduceMotion: mode == 'platform-reduce');
        addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      }
      await tester.pumpWidget(
          _app(fixture, reduced: mode == 'media', ticker: mode != 'ticker'));
      expect(find.byType(AnimatedRotation), findsNothing);
      expect(
          tester
              .widget<OutlinedButton>(find.byType(OutlinedButton))
              .style!
              .animationDuration,
          Duration.zero);
      await _open(tester);
      final route = ModalRoute.of(tester.element(_key('method-name')))!;
      expect(route.transitionDuration, Duration.zero);
      await _choose(tester, 'method-artist');
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets('normal popup uses the shared quick motion duration',
      (tester) async {
    await tester.pumpWidget(_app(_Fixture()));
    await _open(tester);
    final route = ModalRoute.of(tester.element(_key('method-name')))!;
    expect(route.transitionDuration, AppMotion.quick);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('disposing with an open overlay drops callback and all tickers',
      (tester) async {
    final fixture = _Fixture();
    await tester.pumpWidget(_app(fixture));
    await _open(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.calls, isEmpty);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
