import 'package:dan_player/app_shutdown.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';

void main() {
  for (final pauseWhenHidden in [true, false]) {
    testWidgets(
        'failed close restores real Host retry pointer/focus without resources (pause=$pauseWhenHidden)',
        (tester) async {
      final rig = DesktopTestRig();
      final rendering =
          ValueNotifier(RenderingPreferences(pauseWhenHidden: pauseWhenHidden));
      final retryFocus = FocusNode();
      addTearDown(rig.dispose);
      addTearDown(rendering.dispose);
      addTearDown(retryFocus.dispose);
      await tester.runAsync(rig.initialize);
      final coordinator = AppShutdownCoordinator();
      var closeCalls = 0;
      var retryClicks = 0;
      var hiddenBeforePresentationRestore = false;

      Future<void> closeWindow() async {
        await prepareWindowForShutdown(
          hideWindow: rig.window.hide,
          disposeDesktop: rig.integration.dispose,
          onHideError: (_, __) {},
        );
        try {
          if (++closeCalls == 1) {
            throw StateError('synthetic native close failure');
          }
        } catch (_) {
          await rig.window.show();
          // A shown native window alone does not clear the real Host's
          // IgnorePointer/ExcludeFocus gate. This is the regression boundary.
          hiddenBeforePresentationRestore = rig.integration.isHidden.value;
          rig.integration.restorePresentationAfterFailedShutdown();
          rethrow;
        }
      }

      await tester.pumpWidget(MaterialApp(
        home: RenderingPreferencesScope(
          preferences: rendering,
          child: DesktopVisibilityHost(
            isHidden: rig.integration.isHidden,
            child: Scaffold(
              body: Center(
                child: FilledButton(
                  key: const ValueKey('retry-exit'),
                  focusNode: retryFocus,
                  onPressed: () async {
                    retryClicks++;
                    await coordinator.run(closeWindow, throwOnError: true);
                  },
                  child: const Text('Retry exit'),
                ),
              ),
            ),
          ),
        ),
      ));

      await tester.runAsync(() async {
        await expectLater(
            coordinator.run(closeWindow, throwOnError: true), throwsStateError);
      });
      await tester.pump();
      expect(hiddenBeforePresentationRestore, isTrue);
      expect(rig.native.visible, isTrue);
      expect(rig.integration.isHidden.value, isFalse);
      expect(coordinator.isShuttingDown, isFalse);
      final retry = find.byKey(const ValueKey('retry-exit'));
      expect(TickerMode.valuesOf(tester.element(retry)).enabled, isTrue);
      retryFocus.requestFocus();
      await tester.pump();
      expect(retryFocus.hasPrimaryFocus, isTrue);
      await tester.tap(retry);
      await tester.pump();
      // The cached disposal future was created by the native-style runAsync
      // operation above. Let its real-zone continuation finish on retry too.
      await tester.runAsync(flushDesktopEvents);
      await tester.pump();
      expect(retryClicks, 1);
      expect(closeCalls, 2);
      expect(coordinator.isShuttingDown, isTrue);
      expect(rig.integration.isInitialized, isFalse);
      expect(rig.integration.isAvailable, isFalse);
      expect(rig.integration.taskbarAvailable, isFalse);
      expect(rig.playback.starts, 1);
      expect(rig.playback.stops, 1);
      expect(rig.native.handler, isNull);
      expect(rig.native.calls.where((call) => call.$1 == 'configure'),
          hasLength(1));
      expect(
          rig.native.calls.where((call) => call.$1 == 'dispose'), hasLength(1));
      expect(PlayService.hasFacade, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('shutdown presentation restore cannot unhide a live tray player',
      () async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    await rig.initialize();
    expect(await rig.integration.hideToTray(), isTrue);
    final nativeCalls = rig.native.calls.length;
    rig.integration.restorePresentationAfterFailedShutdown();
    expect(rig.integration.isHidden.value, isTrue);
    expect(rig.native.visible, isFalse);
    expect(rig.window.showModes, isEmpty);
    expect(rig.native.calls, hasLength(nativeCalls));
    expect(rig.playback.stops, 0);
  });
}
