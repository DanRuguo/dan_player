import 'dart:async';
import 'package:dan_player/process_resource_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class ResourceTestRig {
  ResourceTestRig() {
    service = ProcessResourceService(channel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (onCall != null) await onCall!(call);
      return null;
    });
  }
  static int _next = 0;
  final channel = MethodChannel('resource-test-${++_next}');
  late final ProcessResourceService service;
  final List<MethodCall> calls = [];
  Future<void> Function(MethodCall)? onCall;
  int get session =>
      (calls.lastWhere((c) => c.method == 'start').arguments as Map)['session']
          as int;
  Future<void> sample(
      {int? session,
      double? cpu = 12.5,
      double? gpu,
      int? memory = 64 * 1024 * 1024,
      String cpuStatus = 'ready',
      String gpuStatus = 'unavailable'}) async {
    final done = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(MethodCall('sample', {
              'session': session ?? this.session,
              'cpuPercent': cpu,
              'gpuPercent': gpu,
              'workingSetBytes': memory,
              'cpuStatus': cpuStatus,
              'gpuStatus': gpuStatus,
            })),
            (_) => done.complete());
    await done.future;
  }

  Future<void> close() async {
    service.dispose();
    await service.settled;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
}
