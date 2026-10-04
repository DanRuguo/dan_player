import 'dart:async';
import 'package:dan_player/process_resource_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class _RecordingChannel extends MethodChannel {
  const _RecordingChannel() : super('dan_player/process_resources');
  static int lastSession = 0;
  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) {
    if (method == 'start') lastSession = (arguments as Map)['session'] as int;
    return super.invokeMethod<T>(method, arguments);
  }
}

class _Heartbeat extends StatefulWidget {
  const _Heartbeat({super.key});
  @override
  State<_Heartbeat> createState() => _HeartbeatState();
}

class _HeartbeatState extends State<_Heartbeat>
    with SingleTickerProviderStateMixin {
  late final AnimationController clock =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));
  int frames = 0;
  @override
  void initState() {
    super.initState();
    clock.addListener(() => frames++);
    clock.repeat();
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: clock, builder: (context, _) => Text('$frames'));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
      'real worker channel samples own process without blocking frames and closes sessions',
      (tester) async {
    final heartbeat = GlobalKey<_HeartbeatState>();
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: _Heartbeat(key: heartbeat))));
    const channel = _RecordingChannel();
    final service = ProcessResourceService(channel: channel);
    Future<void> until(bool Function() condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('Native resource snapshot');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    try {
      await tester.runAsync(() async {
        final before = heartbeat.currentState!.frames;
        var uiTicks = 0;
        final responsive =
            Timer.periodic(const Duration(milliseconds: 20), (_) => uiTicks++);
        final firstClock = Stopwatch()..start();
        late final int oldSession;
        try {
          await service.setActive(true, intervalSeconds: 1);
          oldSession = _RecordingChannel.lastSession;
          await until(() => service.latest?.workingSetBytes != null);
        } finally {
          responsive.cancel();
        }
        if (firstClock.elapsedMilliseconds >= 80) {
          expect(uiTicks, greaterThanOrEqualTo(2),
              reason: 'UI events must run during a slow first PDH query');
        }
        debugPrint(
            'Resource first snapshot ${firstClock.elapsedMilliseconds}ms / $uiTicks UI heartbeats');
        await until(() => service.latest?.cpuPercent != null);
        expect(service.unavailable, isFalse);
        expect(service.latest!.workingSetBytes, greaterThan(0));
        expect(service.latest!.cpuPercent, inInclusiveRange(0, 100));
        if (service.latest!.gpuPercent != null) {
          expect(service.latest!.gpuPercent, inInclusiveRange(0, 100));
        } else {
          expect(service.latest!.gpuStatus, 'unavailable');
        }
        expect(heartbeat.currentState!.frames - before, greaterThan(5),
            reason: 'PDH must not block UI frames');
        await service.setActive(false);
        final closed = service.history.length;
        await Future<void>.delayed(const Duration(milliseconds: 1150));
        expect(service.history, hasLength(closed));
        final one = service.setActive(true, intervalSeconds: 10);
        final two = service.setActive(false);
        final three = service.setActive(true, intervalSeconds: 1);
        await Future.wait([one, two, three]);
        expect(_RecordingChannel.lastSession, isNot(oldSession));
        await channel.invokeMethod<void>('stop', {'session': oldSession});
        await until(() => service.latest?.cpuPercent != null);
        expect(service.active, isTrue);
        expect(service.latest!.workingSetBytes, greaterThan(0));
        await service.setActive(false);
      });
    } finally {
      await tester.runAsync(() async {
        service.dispose();
        await service.settled;
      });
      await tester.pumpWidget(const SizedBox());
    }
  });
}
