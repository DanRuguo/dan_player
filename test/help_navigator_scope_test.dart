import 'dart:async';

import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_window_mode_host.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/window_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_window_mode_adapter.dart';

void main() {
  testWidgets(
      'help is deduplicated per navigator while normal help survives mini mode',
      (tester) async {
    final mode = WindowModeController(adapter: FakeWindowModeAdapter());
    final miniKey = GlobalKey<NavigatorState>();
    late BuildContext normalContext;
    late BuildContext miniContext;
    var normalCompleted = false;
    var miniCompleted = false;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      mode.dispose();
    });
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => AppPresentationHost(
        child: AppWindowModeHost(
          controller: mode,
          navigatorKey: miniKey,
          compactBuilder: (context) {
            miniContext = context;
            return const SizedBox.expand();
          },
          child: child!,
        ),
      ),
      home: Builder(builder: (context) {
        normalContext = context;
        return const Scaffold();
      }),
    ));
    await tester.pumpAndSettle();
    unawaited(HotkeysHelper.showShortcuts(normalContext)
        .then((_) => normalCompleted = true));
    await tester.pumpAndSettle();
    expect(find.text('快捷键'), findsOneWidget);

    // The tray's showMini action can enter mini mode while a normal modal is
    // open. The main navigator intentionally remains mounted but offstage.
    await mode.enter();
    await tester.pumpAndSettle();
    expect(normalCompleted, isFalse);
    expect(find.text('快捷键'), findsNothing);
    unawaited(HotkeysHelper.showShortcuts(miniContext)
        .then((_) => miniCompleted = true));
    await tester.pumpAndSettle();
    expect(find.text('快捷键'), findsOneWidget,
        reason: 'An offstage normal dialog must not lock the mini navigator');
    expect(miniCompleted, isFalse);

    // Repeated commands in each navigator still cannot stack duplicate help.
    await HotkeysHelper.showShortcuts(miniContext);
    await HotkeysHelper.showShortcuts(normalContext);
    await tester.pumpAndSettle();
    expect(find.text('快捷键', skipOffstage: false), findsNWidgets(2));

    await mode.exit();
    await tester.pumpAndSettle();
    expect(miniCompleted, isTrue);
    expect(normalCompleted, isFalse,
        reason: 'Destroying mini help cannot release the normal dialog guard');
    await HotkeysHelper.showShortcuts(normalContext);
    await tester.pumpAndSettle();
    expect(find.text('快捷键', skipOffstage: false), findsOneWidget);
    await tester.tap(find.byTooltip('关闭快捷键说明'));
    await tester.pumpAndSettle();
    expect(normalCompleted, isTrue);

    unawaited(HotkeysHelper.showShortcuts(normalContext));
    await tester.pumpAndSettle();
    expect(find.text('快捷键'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭快捷键说明'));
    await tester.pumpAndSettle();
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
  });
}
