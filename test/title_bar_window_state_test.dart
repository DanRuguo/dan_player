import 'dart:async';

import 'package:dan_player/component/title_bar.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final initialMaximized in [false, true]) {
    for (final fullScreen in [false, true]) {
      testWidgets(
          'maximize precedes fullscreen and keeps state at $initialMaximized/$fullScreen',
          (tester) async {
        var maximized = initialMaximized;
        final actions = <String>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'isMaximized':
              return maximized;
            case 'isFullScreen':
              return fullScreen;
            case 'maximize':
              maximized = true;
              actions.add(call.method);
              return null;
            case 'unmaximize':
              maximized = false;
              actions.add(call.method);
              return null;
            default:
              return null;
          }
        });
        await tester.pumpWidget(const MaterialApp(
            home: Scaffold(body: Center(child: WindowControlls()))));
        await tester.pumpAndSettle();
        final mini = find.byKey(const ValueKey('title-mini-control'));
        final maximize = find.byKey(const ValueKey('title-maximize-control'));
        final full = find.byKey(const ValueKey('title-fullscreen-control'));
        expect(tester.getRect(mini).right,
            lessThan(tester.getRect(maximize).left));
        expect(tester.getRect(maximize).right,
            lessThan(tester.getRect(full).left));
        expect(tester.getRect(maximize).top, tester.getRect(full).top);
        expect(tester.widget<IconButton>(maximize).onPressed,
            fullScreen ? isNull : isNotNull);
        expect(tester.widget<IconButton>(full).tooltip,
            fullScreen ? '退出全屏' : '全屏');
        expect(
            find.descendant(
                of: full,
                matching: find.byIcon(fullScreen
                    ? Symbols.close_fullscreen
                    : Symbols.open_in_full)),
            findsOneWidget);
        if (!fullScreen) {
          await tester.tap(maximize);
          await tester.pumpAndSettle();
          expect(actions, [initialMaximized ? 'unmaximize' : 'maximize']);
          expect(tester.widget<IconButton>(maximize).tooltip,
              maximized ? '还原' : '最大化');
          expect(
              find.descendant(
                  of: maximize,
                  matching: find.byIcon(maximized
                      ? Symbols.fullscreen_exit
                      : Symbols.fullscreen)),
              findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final failure in ['exception', 'timeout']) {
    testWidgets('window buttons recover after status read $failure',
        (tester) async {
      var actions = 0;
      var failStatus = false;
      final pending = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'maximize') {
          actions++;
          failStatus = true;
          return null;
        }
        if (call.method == 'isMaximized' || call.method == 'isFullScreen') {
          if (failStatus) {
            if (failure == 'exception') {
              throw PlatformException(code: 'fixture-status-unavailable');
            }
            return pending.future;
          }
          return false;
        }
        return null;
      });
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: Center(child: WindowControlls()))));
      await tester.pumpAndSettle();
      final maximize = find.byKey(const ValueKey('title-maximize-control'));
      await tester.tap(maximize);
      await tester.pump();
      if (failure == 'timeout') {
        expect(tester.widget<IconButton>(maximize).onPressed, isNull);
        await tester.pump(const Duration(seconds: 3));
      }
      await tester.pumpAndSettle();
      for (final key in [
        'title-mini-control',
        'title-maximize-control',
        'title-fullscreen-control'
      ]) {
        expect(tester.widget<IconButton>(find.byKey(ValueKey(key))).onPressed,
            isNotNull);
      }
      expect(actions, 1);
      failStatus = false;
      if (!pending.isCompleted) pending.complete(false);
      await tester.tap(maximize);
      await tester.pumpAndSettle();
      expect(actions, 2);
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
