import 'dart:async';

import 'package:dan_player/process_resource_coordinator.dart';
import 'package:dan_player/process_resource_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/process_resource_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('three cold surface leases do not start the native worker', () async {
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final leases = List.generate(3, (_) => coordinator.acquire());
    expect(
        leases.map((lease) => lease.service), everyElement(same(rig.service)));
    for (final lease in leases) {
      await lease.setActive(false);
      lease.dispose();
    }
    await coordinator.settled;
    expect(rig.calls, isEmpty);
    coordinator.dispose();
    await rig.close();
  });

  test('overlapping surfaces share samples and only their last close stops',
      () async {
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final backup = coordinator.acquire();
    final sidebar = coordinator.acquire();
    final lyrics = coordinator.acquire();
    await backup.setActive(true);
    await sidebar.setActive(true);
    await lyrics.setActive(true);
    expect(rig.calls.map((call) => call.method), ['start']);
    await rig.sample(cpu: 24);
    expect(backup.service.history, hasLength(1));
    expect(sidebar.service.latest, same(lyrics.service.latest));
    await backup.setActive(false);
    sidebar.dispose();
    await coordinator.settled;
    expect(rig.service.active, isTrue);
    expect(rig.calls.map((call) => call.method), ['start']);
    await rig.sample(cpu: 31);
    expect(lyrics.service.history, hasLength(2));
    lyrics.dispose();
    await lyrics.settled;
    expect(rig.calls.map((call) => call.method), ['start', 'stop']);
    expect(rig.service.active, isFalse);
    coordinator.dispose();
    await rig.close();
  });

  test('synchronous route handoff retains the worker and history', () async {
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final backup = coordinator.acquire();
    final lyrics = coordinator.acquire();
    await backup.setActive(true, intervalSeconds: 1);
    final originalSession = rig.session;
    await rig.sample();
    final closing = backup.setActive(false, intervalSeconds: 1);
    final opening = lyrics.setActive(true, intervalSeconds: 1);
    backup.dispose();
    await Future.wait([closing, opening]);
    expect(rig.calls.map((call) => call.method), ['start']);
    expect(rig.session, originalSession);
    expect(lyrics.service.history, hasLength(1));
    coordinator.dispose();
    await rig.close();
  });

  test('last surface closes reject late events before native acknowledgement',
      () async {
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final lease = coordinator.acquire();
    await lease.setActive(true);
    final originalSession = rig.session;
    await rig.sample(cpu: 22);
    final stop = Completer<void>();
    rig.onCall = (call) async {
      if (call.method == 'stop') await stop.future;
    };
    lease.dispose();
    expect(rig.service.active, isFalse);
    await rig.sample(session: originalSession, cpu: 88);
    expect(rig.service.latest!.cpuPercent, 22);
    stop.complete();
    await lease.settled;
    await lease.setActive(true);
    expect(rig.calls.map((call) => call.method), ['start', 'stop']);
    await rig.sample(session: originalSession, cpu: 89);
    expect(rig.service.history, hasLength(1));
    coordinator.dispose();
    expect(() => coordinator.acquire(), throwsStateError);
    await rig.close();
  });

  test(
      'shared interval update replaces one worker and ignores hidden old value',
      () async {
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final sidebar = coordinator.acquire();
    final lyrics = coordinator.acquire();
    final backup = coordinator.acquire();
    await sidebar.setActive(true, intervalSeconds: 5);
    await lyrics.setActive(true, intervalSeconds: 5);
    final originalSession = rig.session;
    await rig.sample(cpu: 19);
    final sidebarChange = sidebar.setActive(true, intervalSeconds: 1);
    final lyricsChange = lyrics.setActive(true, intervalSeconds: 1);
    final hiddenOldValue = backup.setActive(false, intervalSeconds: 5);
    await Future.wait([sidebarChange, lyricsChange, hiddenOldValue]);
    expect(rig.calls.map((call) => call.method), ['start', 'stop', 'start']);
    expect((rig.calls.last.arguments as Map)['intervalSeconds'], 1);
    expect(rig.session, isNot(originalSession));
    await rig.sample(session: originalSession, cpu: 80);
    expect(rig.service.history, isEmpty);
    await rig.sample(cpu: 7);
    expect(rig.service.history, hasLength(1));
    expect(sidebar.service.latest, same(lyrics.service.latest));
    sidebar.dispose();
    await coordinator.settled;
    expect(rig.calls, hasLength(3));
    coordinator.dispose();
    await rig.close();
  });

  test('RAM percent uses physical total and preserves unknown or real zero',
      () {
    ProcessResourceSample sample(Object? memory, Object? total) =>
        ProcessResourceSample.fromMap({
          'workingSetBytes': memory,
          'totalPhysicalMemoryBytes': total,
        }, DateTime(2026, 10, 4));
    expect(sample(64, 1024).ramPercent, 6.25);
    expect(sample(0, 1024).ramPercent, 0);
    for (final invalid in [null, 0, -1, 1024.0, '1024']) {
      expect(sample(64, invalid).ramPercent, isNull);
      expect(sample(64, invalid).totalPhysicalMemoryBytes, isNull);
    }
    for (final invalid in [null, -1, 1025, 64.0, '64']) {
      expect(sample(invalid, 1024).ramPercent, isNull);
    }
    expect(
        ProcessResourceSample(
                time: DateTime(2026),
                workingSetBytes: 5,
                totalPhysicalMemoryBytes: 0)
            .ramPercent,
        isNull);
  });
}
