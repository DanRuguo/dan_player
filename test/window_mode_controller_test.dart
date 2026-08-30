import 'dart:async';

import 'package:dan_player/window_mode_controller.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _normalBounds = Rect.fromLTWH(120, 80, 1100, 760);
const _maximizedBounds = Rect.fromLTWH(0, 0, 1920, 1040);
const _fullScreenBounds = Rect.fromLTWH(0, 0, 1920, 1080);
const _normalMinimum = Size(507, 320);
const _miniMinimum = Size(440, 280);
const _miniBounds = Rect.fromLTWH(120, 80, 520, 300);

class _FakeWindow implements WindowModeAdapter {
  _FakeWindow({
    Rect initialBounds = _normalBounds,
    this.maximized = false,
    this.fullScreen = false,
    this.alwaysOnTop = false,
  })  : restoredBounds = initialBounds,
        bounds = fullScreen
            ? _fullScreenBounds
            : maximized
                ? _maximizedBounds
                : initialBounds,
        _beforeFullScreenMaximized = maximized;

  Rect bounds;
  Rect restoredBounds;
  bool maximized;
  bool fullScreen;
  bool alwaysOnTop;
  bool _beforeFullScreenMaximized;
  Size minimumSize = _normalMinimum;
  final calls = <String>[];
  final counts = <String, int>{};
  final failBefore = <String>{};
  final failAfter = <String>{};
  final Map<String, Completer<void>> gates = {};
  int activeCalls = 0;
  int maximumActiveCalls = 0;

  Future<T> _call<T>(String name, T Function() body) async {
    final number = (counts[name] ?? 0) + 1;
    counts[name] = number;
    final invocation = '$name:$number';
    calls.add(invocation);
    activeCalls++;
    if (activeCalls > maximumActiveCalls) maximumActiveCalls = activeCalls;
    try {
      final gate = gates[invocation];
      if (gate != null) await gate.future;
      if (failBefore.remove(invocation)) throw StateError(invocation);
      final result = body();
      if (failAfter.remove(invocation)) throw StateError(invocation);
      return result;
    } finally {
      activeCalls--;
    }
  }

  List<String> get writes => calls
      .where((value) =>
          value.startsWith('set') ||
          value.startsWith('maximize:') ||
          value.startsWith('unmaximize:'))
      .toList();

  @override
  Future<Rect> getBounds() => _call('getBounds', () => bounds);
  @override
  Future<bool> isMaximized() => _call('isMaximized', () => maximized);
  @override
  Future<bool> isFullScreen() => _call('isFullScreen', () => fullScreen);
  @override
  Future<bool> isAlwaysOnTop() => _call('isAlwaysOnTop', () => alwaysOnTop);

  @override
  Future<void> setBounds(Rect value) => _call('setBounds', () {
        bounds = value;
        if (!maximized && !fullScreen) restoredBounds = value;
      });
  @override
  Future<void> maximize() => _call('maximize', () {
        if (!maximized && !fullScreen) restoredBounds = bounds;
        maximized = true;
        bounds = _maximizedBounds;
      });
  @override
  Future<void> unmaximize() => _call('unmaximize', () {
        maximized = false;
        bounds = restoredBounds;
      });
  @override
  Future<void> setFullScreen(bool value) => _call('setFullScreen', () {
        if (value && !fullScreen) {
          _beforeFullScreenMaximized = maximized;
          if (!maximized) restoredBounds = bounds;
          fullScreen = true;
          bounds = _fullScreenBounds;
        } else if (!value && fullScreen) {
          fullScreen = false;
          maximized = _beforeFullScreenMaximized;
          bounds = maximized ? _maximizedBounds : restoredBounds;
        }
      });
  @override
  Future<void> setAlwaysOnTop(bool value) =>
      _call('setAlwaysOnTop', () => alwaysOnTop = value);
  @override
  Future<void> setMinimumSize(Size value) =>
      _call('setMinimumSize', () => minimumSize = value);
}

void main() {
  late _FakeWindow window;
  late WindowModeController controller;

  setUp(() {
    window = _FakeWindow();
    controller = WindowModeController(adapter: window);
  });
  tearDown(() => controller.dispose());

  void replaceWindow(_FakeWindow replacement) {
    controller.dispose();
    window = replacement;
    controller = WindowModeController(adapter: window);
  }

  void expectNormal() {
    expect(window.bounds, _normalBounds);
    expect(window.restoredBounds, _normalBounds);
    expect(window.minimumSize, _normalMinimum);
    expect(window.maximized, isFalse);
    expect(window.fullScreen, isFalse);
    expect(window.alwaysOnTop, isFalse);
    expect(controller.isMini, isFalse);
    expect(controller.isBusy, isFalse);
  }

  test('enter stores normal bounds, shrinks min size, never forces pin',
      () async {
    final enter = controller.enter();
    expect(controller.isBusy, isTrue);
    await enter;
    expect(controller.isMini, isTrue);
    expect(controller.isBusy, isFalse);
    expect(controller.isPinned, isFalse);
    expect(controller.normalWindowSnapshot!.bounds, _normalBounds);
    expect(controller.normalWindowSnapshot!.minimumSize, _normalMinimum);
    expect(window.bounds, _miniBounds);
    expect(window.minimumSize, _miniMinimum);
    expect(window.counts['setAlwaysOnTop'], isNull);
    expect(window.writes, ['setMinimumSize:1', 'setBounds:1']);
    await controller.exit();
    expectNormal();
    expect(controller.normalWindowSnapshot, isNull);
  });

  test('repeated enter/exit are idempotent', () async {
    await controller.exit();
    expect(window.calls, isEmpty);
    await Future.wait([controller.enter(), controller.enter()]);
    expect(window.counts['setBounds'], 1);
    await Future.wait([controller.exit(), controller.exit()]);
    expect(window.counts['setBounds'], 2);
    expectNormal();
  });

  test('mini move/resize does not replace the saved normal rectangle',
      () async {
    await controller.enter();
    window.bounds = const Rect.fromLTWH(400, 300, 620, 250);
    window.restoredBounds = window.bounds;
    await controller.exit();
    expectNormal();
  });

  test('negative monitor coordinates and user normal size survive', () async {
    const custom = Rect.fromLTWH(-1410, -80, 930, 690);
    replaceWindow(_FakeWindow(initialBounds: custom));
    await controller.enter();
    expect(window.bounds.topLeft, custom.topLeft);
    expect(controller.normalWindowSnapshot!.bounds, custom);
    await controller.exit();
    expect(window.bounds, custom);
  });

  for (final fullScreen in [false, true]) {
    for (final maximized in [false, true]) {
      test('restores maximized=$maximized fullscreen=$fullScreen', () async {
        replaceWindow(
            _FakeWindow(maximized: maximized, fullScreen: fullScreen));
        await controller.enter();
        final saved = controller.normalWindowSnapshot!;
        expect(saved.bounds, _normalBounds);
        expect(saved.maximized, maximized);
        expect(saved.fullScreen, fullScreen);
        expect(window.bounds, _miniBounds);
        expect(window.fullScreen, isFalse);
        expect(window.maximized, isFalse);
        await controller.exit();
        expect(window.restoredBounds, _normalBounds);
        expect(window.maximized, maximized);
        expect(window.fullScreen, fullScreen);
        expect(
            window.bounds,
            fullScreen
                ? _fullScreenBounds
                : maximized
                    ? _maximizedBounds
                    : _normalBounds);
      });
    }
  }

  test('pin is opt-in and the previous normal topmost flag is restored',
      () async {
    await controller.togglePinned();
    expect(window.calls, isEmpty);
    await controller.enter();
    await controller.togglePinned();
    expect(window.alwaysOnTop, isTrue);
    expect(controller.isPinned, isTrue);
    expect(controller.normalWindowSnapshot!.alwaysOnTop, isFalse);
    await controller.exit();
    expectNormal();
  });

  test('an originally pinned normal window remains pinned after mini',
      () async {
    replaceWindow(_FakeWindow(alwaysOnTop: true));
    await controller.enter();
    expect(controller.isPinned, isTrue);
    expect(window.counts['setAlwaysOnTop'], isNull);
    await controller.togglePinned();
    expect(window.alwaysOnTop, isFalse);
    await controller.exit();
    expect(window.alwaysOnTop, isTrue);
    expect(controller.isPinned, isTrue);
  });

  test('rapid toggles and pin are serialized with no overlapping native calls',
      () async {
    final gate = Completer<void>();
    window.gates['isFullScreen:1'] = gate;
    final first = controller.toggle();
    final pin = controller.togglePinned();
    final second = controller.toggle();
    await Future<void>.delayed(Duration.zero);
    expect(window.calls, ['isFullScreen:1']);
    expect(controller.isBusy, isTrue);
    gate.complete();
    await Future.wait([first, pin, second]);
    expect(window.maximumActiveCalls, 1);
    expectNormal();
  });

  test('reentrant listener commands retain invocation order', () async {
    Future<void>? requestedExit;
    controller.addListener(() {
      if (controller.isBusy && requestedExit == null) {
        requestedExit = controller.exit();
      }
    });
    await controller.enter();
    await requestedExit;
    expectNormal();
  });

  test('read failure before mutation does not write window state', () async {
    window.failBefore.add('isAlwaysOnTop:1');
    await expectLater(controller.enter(), throwsA(isA<WindowModeException>()));
    expect(window.writes, isEmpty);
    expectNormal();
  });

  test('invalid native bounds never reach a resize operation', () async {
    window.bounds = const Rect.fromLTWH(0, 0, double.nan, 200);
    await expectLater(controller.enter(), throwsA(isA<WindowModeException>()));
    expect(window.writes, isEmpty);
    expect(controller.isBusy, isFalse);
  });

  for (final failure in ['setMinimumSize:1', 'setBounds:1']) {
    test('enter mutation failure at $failure rolls back every normal setting',
        () async {
      window.failAfter.add(failure);
      await expectLater(
          controller.enter(), throwsA(isA<WindowModeException>()));
      expectNormal();
      expect(controller.normalWindowSnapshot, isNull);
      await controller.enter();
      expect(controller.isMini, isTrue);
    });
  }

  test('failed read after unmaximize does not save work-area as normal bounds',
      () async {
    replaceWindow(_FakeWindow(maximized: true, fullScreen: true));
    window.failBefore.add('getBounds:2');
    await expectLater(controller.enter(), throwsA(isA<WindowModeException>()));
    expect(window.restoredBounds, _normalBounds);
    expect(window.maximized, isTrue);
    expect(window.fullScreen, isTrue);
    expect(window.counts['setBounds'], isNull);
  });

  test('exit failure rolls back to moved, resized, pinned mini state',
      () async {
    await controller.enter();
    await controller.togglePinned();
    const movedMini = Rect.fromLTWH(500, 400, 600, 240);
    window.bounds = movedMini;
    window.restoredBounds = movedMini;
    window.failAfter.add('setBounds:2');
    await expectLater(controller.exit(), throwsA(isA<WindowModeException>()));
    expect(controller.isMini, isTrue);
    expect(controller.isBusy, isFalse);
    expect(controller.isPinned, isTrue);
    expect(window.bounds, movedMini);
    expect(window.minimumSize, _miniMinimum);
    expect(window.alwaysOnTop, isTrue);
    expect(controller.normalWindowSnapshot!.bounds, _normalBounds);
    await controller.exit();
    expectNormal();
  });

  test('failed maximize on exit is reversible and a later exit still works',
      () async {
    replaceWindow(_FakeWindow(maximized: true));
    await controller.enter();
    window.failAfter.add('maximize:1');
    await expectLater(controller.exit(), throwsA(isA<WindowModeException>()));
    expect(window.bounds, _miniBounds);
    expect(window.maximized, isFalse);
    expect(window.minimumSize, _miniMinimum);
    expect(controller.isMini, isTrue);
    await controller.exit();
    expect(window.maximized, isTrue);
    expect(window.restoredBounds, _normalBounds);
  });

  test('failed fullscreen on exit rolls back and retains original state',
      () async {
    replaceWindow(_FakeWindow(fullScreen: true));
    await controller.enter();
    window.failAfter.add('setFullScreen:2');
    await expectLater(controller.exit(), throwsA(isA<WindowModeException>()));
    expect(window.fullScreen, isFalse);
    expect(window.bounds, _miniBounds);
    expect(controller.normalWindowSnapshot!.fullScreen, isTrue);
    await controller.exit();
    expect(window.fullScreen, isTrue);
    expect(window.restoredBounds, _normalBounds);
  });

  test('pin failure restores the previous flag', () async {
    await controller.enter();
    window.failAfter.add('setAlwaysOnTop:1');
    await expectLater(
        controller.togglePinned(), throwsA(isA<WindowModeException>()));
    expect(window.alwaysOnTop, isFalse);
    expect(controller.isPinned, isFalse);
    expect(controller.isBusy, isFalse);
  });

  test(
      'partial rollback reports failures and preserves a usable Restore action',
      () async {
    window.failAfter.add('setBounds:1');
    window.failBefore.add('setBounds:2');
    await expectLater(
      controller.enter(),
      throwsA(isA<WindowModeException>().having(
          (error) => error.rollbackErrors, 'rollbackErrors', hasLength(1))),
    );
    expect(window.calls.last, 'setAlwaysOnTop:1');
    expect(controller.isMini, isTrue);
    expect(controller.normalWindowSnapshot!.bounds, _normalBounds);
    await controller.exit();
    expectNormal();
  });

  test('a failed queued command does not poison later commands', () async {
    window.failAfter.add('setBounds:1');
    final rejected = controller.enter();
    final recovery = controller.enter();
    await expectLater(rejected, throwsA(isA<WindowModeException>()));
    await recovery;
    expect(controller.isMini, isTrue);
    expect(controller.normalWindowSnapshot!.bounds, _normalBounds);
    expect(controller.isBusy, isFalse);
  });

  test('dispose blocks queued commands and does not notify after disposal',
      () async {
    final gate = Completer<void>();
    window.gates['isFullScreen:1'] = gate;
    var notifications = 0;
    controller.addListener(() => notifications++);
    final active = controller.enter();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    final before = notifications;
    gate.complete();
    await active;
    expect(notifications, before);
    await expectLater(controller.toggle(), throwsStateError);
    // Keep tearDown owning a fresh notifier rather than disposing twice.
    controller = WindowModeController(adapter: window);
  });
}
