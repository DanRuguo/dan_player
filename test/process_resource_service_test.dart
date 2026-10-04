import 'dart:async';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:dan_player/process_resource_service.dart';
import 'package:desktop_lyric/l10n/catalog_process_resources.dart';
import 'package:desktop_lyric/l10n/ui_catalog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/process_resource_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('old preferences default and strict malformed values', () {
    expect(ProcessResourcePreferences.fromMap(null),
        const ProcessResourcePreferences());
    expect(ProcessResourcePreferences.fromMap({'enabled': 'true'}).enabled,
        isFalse);
    expect(ProcessResourcePreferences.fromMap({'enabled': 1}).enabled, isFalse);
    expect(
        ProcessResourcePreferences.fromMap({'enabled': true}).enabled, isTrue);
    for (final value in [0, 2, -1, 1.0, '10', double.infinity]) {
      expect(
          ProcessResourcePreferences.fromMap(
              {'intervalSeconds': value, 'display': 'wrong'}),
          const ProcessResourcePreferences());
    }
    for (final interval in ProcessResourcePreferences.intervals) {
      for (final display in ProcessResourceDisplay.values) {
        final model = ProcessResourcePreferences(
            intervalSeconds: interval, display: display);
        expect(ProcessResourcePreferences.fromMap(model.toMap()), model);
        expect(model.copyWith().hashCode, model.hashCode);
      }
    }
  });
  test('new catalog has three complete translations and matching placeholders',
      () {
    final placeholders = RegExp(r'\{\d+\}');
    for (final entry in catalogProcessResources.entries) {
      expect(entry.value, hasLength(3));
      expect(uiCatalog[entry.key], entry.value);
      for (final text in entry.value) {
        expect(text.trim(), isNotEmpty);
        expect(placeholders.allMatches(text).map((m) => m.group(0)).toSet(),
            placeholders.allMatches(entry.key).map((m) => m.group(0)).toSet());
      }
    }
  });
  test('invalid data remains unknown and real zero remains zero', () {
    final sample = ProcessResourceSample.fromMap({
      'cpuPercent': double.nan,
      'gpuPercent': double.infinity,
      'workingSetBytes': -1
    }, DateTime(2026));
    expect(sample.cpuPercent, isNull);
    expect(sample.gpuPercent, isNull);
    expect(sample.workingSetBytes, isNull);
    final idle = ProcessResourceSample.fromMap(
        {'cpuPercent': 0, 'gpuPercent': 0, 'workingSetBytes': 0},
        DateTime(2026));
    expect(idle.cpuPercent, 0);
    expect(idle.gpuPercent, 0);
    expect(idle.gpuStatus, 'ready');
    expect(idle.workingSetBytes, 0);
  });
  test('cold service has no native calls or sampling', () async {
    final rig = ResourceTestRig();
    expect(rig.calls, isEmpty);
    expect(rig.service.active, isFalse);
    await rig.service.setActive(false);
    expect(rig.calls, isEmpty);
    await rig.close();
    expect(rig.calls, isEmpty);
  });
  test(
      'replacement monitor waits for old stop and old disposal cannot remove new handler',
      () async {
    final rig = ResourceTestRig();
    await rig.service.setActive(true);
    final stopped = Completer<void>();
    rig.onCall = (call) async {
      if (call.method == 'stop') await stopped.future;
    };
    final closing = rig.service.setActive(false);
    await Future<void>.delayed(Duration.zero);
    final replacement = ProcessResourceService(channel: rig.channel);
    final opening = replacement.setActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(rig.calls.map((c) => c.method), ['start', 'stop'],
        reason: 'New worker must wait for old PDH shutdown');
    rig.service.dispose();
    stopped.complete();
    await closing;
    await opening;
    await rig.service.settled;
    final session = rig.session;
    await rig.sample(session: session);
    expect(replacement.latest?.cpuPercent, 12.5);
    replacement.dispose();
    await replacement.settled;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(rig.channel, null);
  });
  test(
      'hide during pending start rejects sample then closes before new interval',
      () async {
    final rig = ResourceTestRig();
    final opened = Completer<void>();
    rig.onCall = (call) async {
      if (call.method == 'start' && rig.calls.length == 1) await opened.future;
    };
    final start = rig.service.setActive(true, intervalSeconds: 1);
    await Future<void>.delayed(Duration.zero);
    final old = rig.session;
    final stop = rig.service.setActive(false);
    await rig.sample(session: old);
    expect(rig.service.history, isEmpty);
    opened.complete();
    await start;
    await stop;
    await rig.service.setActive(true, intervalSeconds: 10);
    expect(rig.calls.map((c) => c.method), ['start', 'stop', 'start']);
    expect(rig.session, isNot(old));
    await rig.sample(session: old);
    expect(rig.service.history, isEmpty);
    await rig.sample();
    expect(rig.service.latest!.cpuPercent, 12.5);
    await rig.close();
    expect(rig.calls.last.method, 'stop');
  });
  test('latest rapid requests win and format-only refresh does not restart',
      () async {
    final rig = ResourceTestRig();
    final a = rig.service.setActive(true, intervalSeconds: 1);
    final b = rig.service.setActive(false);
    final c = rig.service.setActive(true, intervalSeconds: 5);
    await Future.wait([a, b, c]);
    expect(rig.calls.map((c) => c.method), ['start']);
    expect((rig.calls.single.arguments as Map)['intervalSeconds'], 5);
    await rig.service.setActive(true, intervalSeconds: 5);
    expect(rig.calls, hasLength(1));
    for (var index = 0; index < 65; index++) {
      await rig.sample(cpu: index.toDouble());
    }
    expect(rig.service.history, hasLength(60));
    expect(rig.service.history.first.cpuPercent, 5);
    await rig.close();
  });
  test('backend failure is visible and dispose ignores late completion',
      () async {
    final rig = ResourceTestRig();
    rig.onCall = (call) async {
      throw PlatformException(code: 'UNAVAILABLE');
    };
    await rig.service.setActive(true);
    expect(rig.service.unavailable, isTrue);
    expect(rig.service.active, isFalse);
    await rig.close();
    final late = ResourceTestRig();
    final pending = Completer<void>();
    late.onCall = (call) async {
      if (call.method == 'start') await pending.future;
    };
    final started = late.service.setActive(true);
    await Future<void>.delayed(Duration.zero);
    late.service.dispose();
    pending.complete();
    await started;
    await late.service.settled;
    expect(late.calls.map((c) => c.method), ['start', 'stop']);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(late.channel, null);
  });
}
