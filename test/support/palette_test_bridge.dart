import 'dart:async';

import 'package:desktop_lyric/appearance_palette_bridge.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:flutter/services.dart';

/// Runs the actual two-engine protocol with deterministic, isolated transport.
/// It never creates a native window or emulates resizing the lyric window.
class PaletteLoopbackChannel extends MethodChannel {
  PaletteLoopbackChannel(super.name);
  Future<Object?> Function(MethodCall)? receiver;
  Future<Object?> Function(MethodCall)? request;
  @override
  void setMethodCallHandler(Future<dynamic> Function(MethodCall)? handler) =>
      receiver = handler;
  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async =>
      await request?.call(MethodCall(method, arguments)) as T?;
}

class PaletteTestBridge {
  PaletteTestBridge(
      {required DesktopLyricController source,
      required DesktopLyricWindowLayout layout}) {
    owner.request = _ownerRequest;
    child.request = _childRequest;
    host = DesktopLyricPaletteHost(
        controller: source, layout: layout, channel: owner);
  }
  final owner = PaletteLoopbackChannel('test/palette_owner');
  final child = PaletteLoopbackChannel('test/palette_child');
  late final DesktopLyricPaletteHost host;
  DesktopLyricPaletteClient? client;
  Map<Object?, Object?> snapshot = {};
  int opens = 0;
  int closes = 0;
  final edits = <Object?>[];
  Object? openError;
  Completer<void>? openGate;

  Future<Object?> _ownerRequest(MethodCall call) async {
    switch (call.method) {
      case 'open':
        opens++;
        snapshot = Map<Object?, Object?>.from(call.arguments as Map);
        if (openError != null) throw openError!;
        await openGate?.future;
      case 'update':
        snapshot = Map<Object?, Object?>.from(call.arguments as Map);
        client?.applySnapshot(snapshot);
      case 'close':
        await closeNative();
    }
    return null;
  }

  Future<Object?> _childRequest(MethodCall call) async {
    if (call.method == 'ready') return snapshot;
    if (call.method == 'close') {
      await closeNative();
      return null;
    }
    if (call.method == 'edit') edits.add(call.arguments);
    final reply = await owner.receiver?.call(call);
    if (reply is Map) snapshot = Map<Object?, Object?>.from(reply);
    return reply;
  }

  Future<DesktopLyricPaletteClient> connectClient() async {
    final value = client = DesktopLyricPaletteClient(channel: child);
    await value.initialize();
    return value;
  }

  Future<void> closeNative() async {
    closes++;
    await owner.receiver?.call(MethodCall('closed', {
      'session': snapshot['session'],
      'ownerHover': false,
    }));
  }

  void dispose() {
    client?.dispose();
    client = null;
    host.dispose();
  }
}
