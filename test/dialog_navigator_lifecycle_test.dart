import 'dart:async';

import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_window_mode_host.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/window_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_window_mode_adapter.dart';

// Real presentation/navigation widgets, with no player/native/plugin I/O.
void main() {
  testWidgets(
      'shortcut help remains reopenable after the mini navigator leaves',
      (tester) async {
    final mode = WindowModeController(adapter: FakeWindowModeAdapter());
    addTearDown(mode.dispose);
    final miniKey = GlobalKey<NavigatorState>();
    var firstCompleted = false;
    var normalPresses = 0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => AppPresentationHost(
        child: AppWindowModeHost(
          controller: mode,
          navigatorKey: miniKey,
          compactBuilder: (context) => TextButton(
            key: const ValueKey('mini-help'),
            onPressed: () => unawaited(HotkeysHelper.showShortcuts(context)
                .then((_) => firstCompleted = true)),
            child: const Text('Open synthetic mini help'),
          ),
          child: child!,
        ),
      ),
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    key: const ValueKey('normal-help'),
                    onPressed: () {
                      normalPresses++;
                      unawaited(HotkeysHelper.showShortcuts(context));
                    },
                    child: const Text('Open synthetic normal help'),
                  ))),
    ));
    await tester.pumpAndSettle();
    await mode.enter();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mini-help')));
    await tester.pumpAndSettle();
    expect(find.text('快捷键'), findsOneWidget);
    expect(miniKey.currentState!.canPop(), isTrue);

    // Same controller operation used by tray showMain while a modal is open.
    await mode.exit();
    await tester.pumpAndSettle();
    expect(miniKey.currentState, isNull);
    expect(find.text('快捷键'), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    await tester.tap(find.byKey(const ValueKey('normal-help')));
    await tester.pumpAndSettle();
    // The click arrives, but the static guard can remain latched indefinitely.
    expect(normalPresses, 1);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
    expect(firstCompleted, isTrue);
    expect(find.text('快捷键'), findsOneWidget,
        reason: 'Disposed mini navigator must not permanently latch help');
    await tester.tap(find.byTooltip('关闭快捷键说明'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('normal-help')));
    await tester.pumpAndSettle();
    expect(find.text('快捷键'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭快捷键说明'));
    await tester.pumpAndSettle();
  });

  for (final buildDialog in [false, true]) {
    testWidgets('teardown completes an abandoned dialog, built=$buildDialog',
        (tester) async {
      late BuildContext caller;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        caller = context;
        return const Scaffold();
      })));
      var completed = false;
      String? result = 'pending';
      unawaited(showAppDialog<String>(
          context: caller,
          builder: (_) =>
              const AlertDialog(title: Text('Synthetic dialog'))).then((value) {
        completed = true;
        result = value;
      }));
      if (buildDialog) await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(completed, isTrue);
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'normal pop keeps its result and a new dialog remains independent',
      (tester) async {
    late BuildContext caller;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      caller = context;
      return const Scaffold();
    })));
    final first = showAppDialog<String>(
        context: caller,
        builder: (context) => AlertDialog(actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, 'saved'),
                  child: const Text('Save synthetic'))
            ]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save synthetic'));
    expect(await first, 'saved');
    var secondCompleted = false;
    final second = showAppDialog<String>(
        context: caller,
        barrierDismissible: false,
        builder: (context) =>
            const AlertDialog(title: Text('Next synthetic'))).then((value) {
      secondCompleted = true;
      return value;
    });
    // The old route is disposed while the new one is still open.
    await tester.pumpAndSettle();
    expect(secondCompleted, isFalse);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(secondCompleted, isFalse);
    Navigator.of(caller).pop('second');
    expect(await second, 'second');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
