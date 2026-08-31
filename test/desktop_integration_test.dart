import 'dart:async';

import 'package:dan_player/app_shutdown.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('desktop integration without a real window or audio', () {
    late DesktopTestRig rig;
    setUp(() => rig = DesktopTestRig());
    tearDown(() => rig.dispose());

    test('constructor is passive and initialization never initializes BASS',
        () async {
      expect(rig.native.calls, isEmpty);
      expect(rig.playback.starts, 0);
      expect(PlayService.isInitialized, isFalse);
      await rig.initialize();
      await flushDesktopEvents();
      expect(rig.integration.isAvailable, isTrue);
      expect(rig.playback.starts, 1);
      expect(rig.playback.value.ready, isFalse);
      expect(PlayService.isInitialized, isFalse);
      expect(rig.native.calls.where((call) => call.$1 == 'configure'),
          hasLength(1));
      final state =
          rig.native.calls.lastWhere((call) => call.$1 == 'updatePlayback');
      expect(state.$2!['ready'], isFalse);
      expect(state.$2!.keys, isNot(contains('position')));
    });

    test('initialize is idempotent', () async {
      await Future.wait([rig.initialize(), rig.initialize()]);
      expect(rig.playback.starts, 1);
      expect(rig.native.calls.where((call) => call.$1 == 'configure'),
          hasLength(1));
    });

    test('native initialization failure leaves a reachable normal window',
        () async {
      rig.native.throwOn = 'configure';
      await rig.initialize();
      expect(rig.integration.isAvailable, isFalse);
      expect(await rig.integration.hideToTray(), isFalse);
      expect(rig.window.hideCalls, 0);
      expect(rig.playback.starts, 0);
      expect(rig.integration.lastError, contains('初始化失败'));
    });

    test('hide checks live tray availability, not only initial state',
        () async {
      await rig.initialize();
      rig.native.trayAvailable = false;
      expect(await rig.integration.hideToTray(), isFalse);
      expect(rig.window.hideCalls, 0);
      expect(rig.integration.isHidden.value, isFalse);
    });

    for (final (label, reply) in <(String, Object?)>[
      ('null', null),
      ('list', <Object>[]),
      ('missing confirmation', <String, Object>{'revision': 1000}),
      ('wrong confirmation type', <String, Object>{'trayAvailable': 'true'}),
    ]) {
      test('malformed $label cannot reuse old tray availability to hide',
          () async {
        await rig.initialize();
        await flushDesktopEvents();
        expect(rig.integration.isAvailable, isTrue);
        rig.native.intercept = (method, _) async =>
            method == 'prepareHide' ? reply : rig.native.state();
        expect(await rig.integration.hideToTray(), isFalse);
        expect(rig.window.hideCalls, 0);
        expect(rig.native.visible, isTrue);
      });
    }

    test('exit during tray confirmation prevents the pending window hide',
        () async {
      await rig.initialize();
      final confirmation = Completer<Object?>();
      rig.native.intercept = (method, _) async =>
          method == 'prepareHide' ? confirmation.future : rig.native.state();
      final hidden = rig.integration.hideToTray();
      await flushDesktopEvents();
      await rig.integration.dispatchAction('exit');
      confirmation.complete(rig.native.state());
      expect(await hidden, isFalse);
      expect(rig.exits, 1);
      expect(rig.window.hideCalls, 0);
    });

    test('successful hide leaves audio observer and queue running', () async {
      await rig.initialize();
      rig.playback.value = readyDesktopPlayback;
      expect(await rig.integration.hideToTray(), isTrue);
      expect(rig.integration.isHidden.value, isTrue);
      expect(rig.playback.stops, 0);
      expect(rig.playback.actions, isEmpty);
      await rig.integration.dispatchAction('toggle');
      expect(rig.playback.actions, ['toggle']);
      expect(rig.window.showModes, isEmpty);
    });

    test('hide failure returns false instead of claiming background success',
        () async {
      await rig.initialize();
      rig.window.throwOnHide = true;
      expect(await rig.integration.hideToTray(), isFalse);
      expect(rig.integration.isHidden.value, isFalse);
      expect(rig.native.visible, isTrue);
    });

    test('failure after hide makes its own window reachable again', () async {
      await rig.initialize();
      rig.native.throwOn = 'getState';
      expect(await rig.integration.hideToTray(), isFalse);
      expect(rig.window.hideCalls, 1);
      expect(rig.window.showModes, [null]);
      expect(rig.native.visible, isTrue);
    });

    test(
        'restore and normal/mini menu actions preserve the single window adapter',
        () async {
      await rig.initialize();
      await rig.integration.hideToTray();
      await rig.integration.dispatchAction('showMini');
      await rig.integration.dispatchAction('showMain');
      await rig.integration.dispatchAction('restore');
      expect(rig.window.showModes, [true, false, null]);
      expect(rig.integration.isHidden.value, isFalse);
      expect(rig.playback.actions, isEmpty);
    });

    test('hide and restore operations are serialized', () async {
      await rig.initialize();
      rig.window.holdHide = Completer<void>();
      final hide = rig.integration.hideToTray();
      await flushDesktopEvents();
      final show = rig.integration.showWindow(mini: true);
      expect(rig.window.showModes, isEmpty);
      rig.window.holdHide!.complete();
      expect(await hide, isTrue);
      await show;
      expect(rig.native.visible, isTrue);
      expect(rig.window.showModes, [true]);
    });

    test('exit bypasses the hide preference and is idempotent', () async {
      rig.preferences.value = rig.preferences.value.copyWith(closeToTray: true);
      await rig.initialize();
      await rig.integration.dispatchAction('exit');
      await rig.integration.dispatchAction('exit');
      await rig.integration.dispatchAction('showMain');
      expect(rig.exits, 1);
      expect(rig.window.hideCalls, 0);
      expect(rig.window.showModes, isEmpty);
    });

    test('failed exit before disposal remains reachable and retryable',
        () async {
      var attempts = 0;
      await rig.integration.initialize(onExit: () async {
        attempts++;
        if (attempts == 1) throw StateError('fake exit setup failed');
      });
      await rig.integration.hideToTray();
      await rig.integration.dispatchAction('exit');
      expect(rig.window.showModes, [null]);
      expect(rig.errors.single, contains('fake exit setup failed'));
      await rig.integration.dispatchAction('exit');
      await rig.integration.dispatchAction('exit');
      expect(attempts, 2);
    });

    test('unknown and cold native actions cannot construct or control playback',
        () async {
      await rig.initialize();
      for (final action in [
        'toggle',
        'previous',
        'next',
        'desktopLyrics',
        'deleteAll'
      ]) {
        await rig.integration.dispatchAction(action);
      }
      expect(rig.playback.actions, isEmpty);
      expect(PlayService.isInitialized, isFalse);
    });

    test('current capabilities reject stale Shell commands while buffering',
        () async {
      await rig.initialize();
      rig.playback.value = const DesktopPlaybackSnapshot(
          ready: true, hasTrack: true, hasQueue: true, buffering: true);
      for (final action in ['toggle', 'previous', 'next']) {
        await rig.integration.dispatchAction(action);
      }
      expect(rig.playback.actions, isEmpty);
      await rig.integration.dispatchAction('desktopLyrics');
      expect(rig.playback.actions, ['desktopLyrics']);
    });

    test('ready native menu and taskbar events call the existing transport',
        () async {
      await rig.initialize();
      rig.playback.value = readyDesktopPlayback;
      for (final action in ['toggle', 'previous', 'next', 'desktopLyrics']) {
        await rig.native.emit('action', action);
      }
      expect(rig.playback.actions,
          ['toggle', 'previous', 'next', 'desktopLyrics']);
    });

    test('native visibility gates hidden and minimized without pausing music',
        () async {
      await rig.initialize();
      rig.native.minimized = true;
      await rig.native.emit('stateChanged', rig.native.state());
      expect(rig.integration.isHidden.value, isTrue);
      rig.native.minimized = false;
      await rig.native.emit('stateChanged', rig.native.state());
      expect(rig.integration.isHidden.value, isFalse);
      expect(rig.playback.actions, isEmpty);
    });

    test('late older visibility status cannot overwrite a newer native event',
        () async {
      await rig.initialize();
      final old = rig.native.state();
      rig.native.visible = false;
      await rig.native.emit('stateChanged', rig.native.state());
      await rig.native.emit('stateChanged', old);
      expect(rig.integration.isHidden.value, isTrue);
    });

    test(
        'Explorer recovery failure restores hidden app instead of orphaning it',
        () async {
      await rig.initialize();
      await rig.integration.hideToTray();
      rig.native.trayAvailable = false;
      await rig.native.emit('stateChanged', rig.native.state());
      await flushDesktopEvents();
      expect(rig.window.showModes, [null]);
      expect(rig.native.visible, isTrue);
      expect(rig.integration.isAvailable, isFalse);
      expect(rig.playback.stops, 0);
    });

    test('successful Explorer recovery leaves background playback hidden',
        () async {
      await rig.initialize();
      await rig.integration.hideToTray();
      await rig.native.emit('stateChanged', rig.native.state());
      await flushDesktopEvents();
      expect(rig.window.showModes, isEmpty);
      expect(rig.integration.isHidden.value, isTrue);
    });

    test(
        'unrelated preferences and repeated snapshots do not reconfigure Shell',
        () async {
      await rig.initialize();
      await flushDesktopEvents();
      rig.native.calls.clear();
      rig.preferences.value =
          rig.preferences.value.copyWith(springLyrics: false);
      rig.playback.value = const DesktopPlaybackSnapshot();
      await flushDesktopEvents();
      expect(rig.native.calls, isEmpty);
      rig.preferences.value =
          rig.preferences.value.copyWith(taskbarControls: false);
      await flushDesktopEvents();
      expect(rig.native.calls.map((call) => call.$1), ['configure']);
      expect(
          rig.native.calls.single.$2, containsPair('taskbarControls', false));
      expect(
          rig.native.calls.single.$2, containsPair('trayMenuBlurRadius', 0.0));
    });

    test('same-turn playback changes are coalesced to latest metadata',
        () async {
      await rig.initialize();
      await flushDesktopEvents();
      rig.native.calls.clear();
      rig.playback.value = readyDesktopPlayback;
      rig.playback.value = const DesktopPlaybackSnapshot(
          ready: true,
          hasTrack: true,
          hasQueue: true,
          playing: true,
          title: 'latest');
      await flushDesktopEvents();
      final calls = rig.native.calls
          .where((call) => call.$1 == 'updatePlayback')
          .toList();
      expect(calls, hasLength(1));
      expect(calls.single.$2!['title'], 'latest');
    });

    test('preference change during initialization is not lost', () async {
      final gate = Completer<Object?>();
      rig.native.intercept = (method, _) async =>
          method == 'configure' && !gate.isCompleted
              ? gate.future
              : rig.native.state();
      final initialized = rig.initialize();
      rig.preferences.value =
          rig.preferences.value.copyWith(taskbarControls: false);
      gate.complete(rig.native.state());
      await initialized;
      await flushDesktopEvents();
      final calls =
          rig.native.calls.where((call) => call.$1 == 'configure').toList();
      expect(calls, hasLength(2));
      expect(calls.last.$2!['taskbarControls'], isFalse);
    });

    test('disposing pending initialization prevents late observer attachment',
        () async {
      final gate = Completer<Object?>();
      rig.native.intercept =
          (method, _) async => method == 'configure' ? gate.future : null;
      final initialized = rig.initialize();
      await rig.integration.dispose();
      gate.complete(rig.native.state());
      await initialized;
      expect(rig.playback.starts, 0);
      expect(rig.native.handler, isNull);
      expect(rig.integration.isAvailable, isFalse);
    });

    test('dispose unsubscribes once and ignores stale native callbacks',
        () async {
      await rig.initialize();
      final callback = rig.native.handler!;
      await rig.integration.dispose();
      await rig.integration.dispose();
      await callback(const MethodCall('action', 'showMain'));
      expect(rig.playback.stops, 1);
      expect(rig.window.showModes, isEmpty);
      expect(
          rig.native.calls.where((call) => call.$1 == 'dispose'), hasLength(1));
    });

    test('dispose publishes unavailable and hidden before async teardown',
        () async {
      await rig.initialize();
      final teardown = Completer<Object?>();
      rig.native.intercept = (method, _) async =>
          method == 'dispose' ? teardown.future : rig.native.state();
      final changes = <(bool, bool, bool)>[];
      void listener() => changes.add((
            rig.integration.isAvailable,
            rig.integration.taskbarAvailable,
            rig.integration.isHidden.value
          ));
      rig.integration.addListener(listener);
      final disposal = rig.integration.dispose();
      expect(changes, [(false, false, true)]);
      expect(rig.integration.isInitialized, isFalse);
      expect(identical(disposal, rig.integration.dispose()), isTrue);
      await flushDesktopEvents();
      expect(rig.playback.stops, 1);
      teardown.complete(null);
      await disposal;
      // Async disposal must not invalidate mounted consumers' detach calls.
      rig.integration.removeListener(listener);
      expect(changes, [(false, false, true)]);
      expect(
          rig.native.calls.where((call) => call.$1 == 'dispose'), hasLength(1));
    });

    test('unsubscribe error cannot prevent native icon cleanup', () async {
      await rig.initialize();
      rig.playback.throwOnStop = true;
      await rig.integration.dispose();
      expect(rig.native.calls.any((call) => call.$1 == 'dispose'), isTrue);
    });

    test('playback failure restores hidden window and reports a visible error',
        () async {
      await rig.initialize();
      rig.playback.value = readyDesktopPlayback;
      rig.playback.throwOnAction = true;
      await rig.integration.hideToTray();
      await rig.integration.dispatchAction('toggle');
      expect(rig.window.showModes, [null]);
      expect(rig.errors.single, contains('桌面操作失败'));
    });
  });

  test('unsupported platform keeps startup and UI passive', () async {
    final rig = DesktopTestRig(supported: false);
    await rig.initialize();
    expect(rig.native.calls, isEmpty);
    expect(await rig.integration.hideToTray(), isFalse);
    await rig.dispose();
    expect(rig.native.calls, isEmpty);
  });

  group('unified close coordinator', () {
    test('default close takes true exit path', () async {
      var hidden = 0;
      var exited = 0;
      final close = AppCloseCoordinator(
          closeToTray: () => false,
          hideToTray: () async {
            hidden++;
            return true;
          },
          exit: () async {
            exited++;
          });
      await close.requestClose();
      expect((hidden, exited), (0, 1));
    });

    test('successful close to tray never runs cleanup/exit', () async {
      var exited = 0;
      final close = AppCloseCoordinator(
          closeToTray: () => true,
          hideToTray: () async => true,
          exit: () async {
            exited++;
          });
      await close.requestClose();
      expect(exited, 0);
    });

    test('unavailable tray falls back to real exit', () async {
      var exited = 0;
      final close = AppCloseCoordinator(
          closeToTray: () => true,
          hideToTray: () async => false,
          exit: () async {
            exited++;
          });
      await close.requestClose();
      expect(exited, 1);
    });

    test('hide exception falls back to real exit', () async {
      var exited = 0;
      final close = AppCloseCoordinator(
          closeToTray: () => true,
          hideToTray: () async => throw StateError('fake'),
          exit: () async {
            exited++;
          });
      await close.requestClose();
      expect(exited, 1);
    });

    test('repeated close requests share the pending hide operation', () async {
      final gate = Completer<bool>();
      var hidden = 0;
      var exited = 0;
      final close = AppCloseCoordinator(
          closeToTray: () => true,
          hideToTray: () {
            hidden++;
            return gate.future;
          },
          exit: () async {
            exited++;
          });
      final first = close.requestClose();
      final second = close.requestClose();
      gate.complete(false);
      await Future.wait([first, second]);
      expect((hidden, exited), (1, 1));
    });

    test('repeated true-close requests do not interrupt pending cleanup',
        () async {
      final cleanup = Completer<void>();
      var started = 0;
      var completed = 0;
      final close = AppCloseCoordinator(
        closeToTray: () => false,
        hideToTray: () async => throw StateError('not the hide path'),
        exit: () async {
          started++;
          await cleanup.future;
          completed++;
        },
      );
      final first = close.requestClose();
      final second = close.requestClose();
      expect(identical(first, second), isTrue);
      expect((started, completed), (1, 0));
      cleanup.complete();
      await Future.wait([first, second]);
      expect((started, completed), (1, 1));
    });
  });

  testWidgets(
      'visibility host preserves subtree and text while gating focus/tickers',
      (tester) async {
    final hidden = ValueNotifier(false);
    final text = TextEditingController(text: 'preserved synthetic input');
    final key = GlobalKey<_TickerProbeState>();
    await tester.pumpWidget(MaterialApp(
        home: DesktopVisibilityHost(
      isHidden: hidden,
      child: _TickerProbe(key: key, text: text),
    )));
    await tester.pump(const Duration(milliseconds: 100));
    final state = key.currentState!;
    final oldTicks = state.ticks;
    hidden.value = true;
    await tester.pump();
    final hiddenTicks = state.ticks;
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.ticks, hiddenTicks);
    expect(identical(state, key.currentState), isTrue);
    expect(text.text, 'preserved synthetic input');
    hidden.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.ticks, greaterThan(oldTicks));
    expect(identical(state, key.currentState), isTrue);
    await tester.pumpWidget(const SizedBox());
    text.dispose();
    hidden.dispose();
  });
}

class _TickerProbe extends StatefulWidget {
  const _TickerProbe({super.key, required this.text});
  final TextEditingController text;
  @override
  State<_TickerProbe> createState() => _TickerProbeState();
}

class _TickerProbeState extends State<_TickerProbe>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation;
  int ticks = 0;
  @override
  void initState() {
    super.initState();
    animation =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..addListener(() => ticks++)
          ..repeat();
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: TextField(controller: widget.text));
  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }
}
