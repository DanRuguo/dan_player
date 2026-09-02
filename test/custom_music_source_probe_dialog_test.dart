import 'dart:async';

import 'package:dan_player/component/custom_music_source_probe_dialog.dart';
import 'package:dan_player/online/custom_music_source_probe.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final profile = CustomMusicSourceProfile.tryCreate(
      id: 'fixture',
      name: 'Fixture',
      baseUrl: 'https://example.test',
      capabilities: const {CustomMusicSourceCapability.search})!;
  late BuildContext context;
  Future<void> mount(WidgetTester tester,
      {Size size = const Size(900, 700), double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Builder(builder: (value) {
        context = value;
        return const Scaffold();
      }),
    ));
  }

  testWidgets(
      'does not auto probe and applies only after explicit confirmation',
      (tester) async {
    await mount(tester);
    final service = _ControlledProbe();
    Set<CustomMusicSourceCapability>? applied;
    showCustomMusicSourceProbeDialog(context,
        profile: profile,
        service: service,
        onApplyCapabilities: (value) => applied = value);
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    await tester.tap(find.byKey(const ValueKey('custom-source-probe-start')));
    await tester.pump();
    expect(service.title, '卡农');
    service.complete();
    await tester.pumpAndSettle();
    expect(applied, isNull);
    await tester.tap(find.byKey(const ValueKey('custom-source-probe-apply')));
    await tester.pumpAndSettle();
    expect(applied, {
      CustomMusicSourceCapability.search,
      CustomMusicSourceCapability.lyrics
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing cancels immediately and ignores late result callbacks',
      (tester) async {
    await mount(tester);
    final service = _ControlledProbe();
    showCustomMusicSourceProbeDialog(context,
        profile: profile, service: service);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('custom-source-probe-start')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('custom-source-probe-close')));
    await tester.pump();
    expect(service.token?.isCancelled, isTrue);
    service.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('custom-source-probe-results')),
        findsNothing);
  });

  testWidgets('blank title is rejected without requests', (tester) async {
    await mount(tester);
    final service = _ControlledProbe();
    showCustomMusicSourceProbeDialog(context,
        profile: profile, service: service);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('custom-source-probe-title')), '  ');
    await tester.tap(find.byKey(const ValueKey('custom-source-probe-start')));
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    expect(find.text('请填写歌曲名'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('custom-source-probe-close')));
    await tester.pumpAndSettle();
  });

  testWidgets('short enlarged window keeps dialog within constraints',
      (tester) async {
    await mount(tester, size: const Size(507, 360), scale: 1.6);
    showCustomMusicSourceProbeDialog(context,
        profile: profile, service: _ControlledProbe());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('custom-source-probe-close')));
    await tester.pumpAndSettle();
  });
}

class _ControlledProbe extends CustomMusicSourceProbeService {
  final _pending = Completer<CustomMusicSourceProbeReport>();
  int calls = 0;
  String? title;
  CustomMusicSourceCancellation? token;
  void Function(CustomMusicSourceProbeResult)? progress;

  @override
  Future<CustomMusicSourceProbeReport> run(CustomMusicSourceProfile profile,
      {required String title,
      String artist = '',
      String album = '',
      CustomMusicSourceCancellation? cancellation,
      void Function(CustomMusicSourceProbeResult result)? onResult}) {
    calls++;
    this.title = title;
    token = cancellation;
    progress = onResult;
    return _pending.future;
  }

  void complete() {
    const result = CustomMusicSourceProbeResult(
        CustomMusicSourceCapability.lyrics,
        CustomMusicSourceProbeStatus.success,
        '已取得歌词内容');
    progress?.call(result);
    _pending.complete(CustomMusicSourceProbeReport(
        results: const [result],
        elapsed: const Duration(milliseconds: 100),
        sampleTitle: '卡农'));
  }
}
