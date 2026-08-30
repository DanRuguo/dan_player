import 'dart:async';

import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FakeDesktopNative implements DesktopNativeAdapter {
  Future<void> Function(MethodCall)? handler;
  final calls = <(String, Map<String, Object>?)>[];
  bool trayAvailable = true;
  bool taskbarAvailable = true;
  bool visible = true;
  bool minimized = false;
  int revision = 0;
  String? throwOn;
  Future<Object?> Function(String, Map<String, Object>?)? intercept;

  Map<String, Object> state() => {
        'revision': ++revision,
        'trayAvailable': trayAvailable,
        'taskbarAvailable': taskbarAvailable,
        'windowVisible': visible,
        'minimized': minimized,
      };

  @override
  void setEventHandler(Future<void> Function(MethodCall call)? handler) =>
      this.handler = handler;

  @override
  Future<Object?> invoke(String method,
      [Map<String, Object>? arguments]) async {
    calls.add((method, arguments));
    if (throwOn == method) throw StateError('fake $method failure');
    if (intercept != null) return intercept!(method, arguments);
    return state();
  }

  Future<void> emit(String method, Object? value) async =>
      handler?.call(MethodCall(method, value));
}

class FakeDesktopWindow implements DesktopWindowAdapter {
  FakeDesktopWindow(this.native);
  final FakeDesktopNative native;
  final showModes = <bool?>[];
  int hideCalls = 0;
  bool throwOnHide = false;
  bool throwOnShow = false;
  Completer<void>? holdHide;
  Completer<void>? holdShow;

  @override
  Future<void> hide() async {
    hideCalls++;
    if (throwOnHide) throw StateError('fake hide failed');
    if (holdHide != null) await holdHide!.future;
    native.visible = false;
  }

  @override
  Future<void> show({bool? mini}) async {
    showModes.add(mini);
    if (throwOnShow) throw StateError('fake show failed');
    if (holdShow != null) await holdShow!.future;
    native.visible = true;
    native.minimized = false;
  }
}

class FakeDesktopPlayback extends ValueNotifier<DesktopPlaybackSnapshot>
    implements DesktopPlaybackAdapter {
  FakeDesktopPlayback() : super(const DesktopPlaybackSnapshot());
  int starts = 0;
  int stops = 0;
  final actions = <String>[];
  bool throwOnAction = false;
  bool throwOnStop = false;

  @override
  void startObserving() => starts++;

  @override
  Future<void> stopObserving() async {
    stops++;
    if (throwOnStop) throw StateError('fake unsubscribe failure');
  }

  @override
  Future<void> runAction(String action) async {
    actions.add(action);
    if (throwOnAction) throw StateError('fake playback failure');
  }
}

class DesktopTestRig {
  DesktopTestRig({bool supported = true}) {
    window = FakeDesktopWindow(native);
    integration = DesktopIntegration.forTesting(
      native: native,
      window: window,
      playback: playback,
      preferences: preferences,
      supported: supported,
      onError: errors.add,
    );
  }

  final native = FakeDesktopNative();
  final playback = FakeDesktopPlayback();
  final preferences = ValueNotifier(const PlayerExperiencePreferences());
  final errors = <String>[];
  late final FakeDesktopWindow window;
  late final DesktopIntegration integration;
  int exits = 0;

  Future<void> initialize() => integration.initialize(onExit: () async {
        exits++;
      });

  Future<void> dispose() async {
    await integration.dispose();
    playback.dispose();
    preferences.dispose();
  }
}

Future<void> flushDesktopEvents() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const readyDesktopPlayback = DesktopPlaybackSnapshot(
  ready: true,
  hasTrack: true,
  hasQueue: true,
  title: '合成曲目 — Synthetic Artist',
);
