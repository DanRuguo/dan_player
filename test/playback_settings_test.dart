import 'package:dan_player/page/settings_page/playback_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_rate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(WidgetTester tester, Widget panel,
      {double width = 720, double scale = 1}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: panel)),
    ));
  }

  testWidgets('opening the real settings does not initialize BASS or SMTC',
      (tester) async {
    expect(PlayService.isInitialized, isFalse);
    await mount(tester, const PlaybackSettings());
    expect(PlayService.isInitialized, isFalse);
    expect(PlayService.playbackReady.value, isFalse);
    expect(find.textContaining('将在开始播放时应用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rate choices and exclusive switch dispatch independent changes',
      (tester) async {
    final rates = <double>[];
    final exclusive = <bool>[];
    await mount(
        tester,
        PlaybackSettingsPanel(
          playbackRate: 1,
          exclusive: false,
          onRateChanged: rates.add,
          onExclusiveChanged: exclusive.add,
        ));
    expect(find.byType(ChoiceChip), findsNWidgets(7));
    for (final rate in PlaybackRate.presets) {
      await tester
          .tap(find.widgetWithText(ChoiceChip, PlaybackRate.label(rate)));
    }
    await tester.tap(find.byType(SwitchListTile));
    expect(rates, PlaybackRate.presets);
    expect(exclusive, [true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing component disables speed only and explains fallback',
      (tester) async {
    await mount(
        tester,
        PlaybackSettingsPanel(
          playbackRate: 1,
          exclusive: false,
          rateAvailable: false,
          unavailableReason: '缺少 bass_fx.dll，请使用完整安装包。',
          onRateChanged: (_) =>
              fail('Unavailable extension must not be called'),
          onExclusiveChanged: (_) {},
        ));
    expect(find.textContaining('缺少 bass_fx.dll'), findsOneWidget);
    for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) {
      expect(chip.onSelected, isNull);
    }
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNotNull);
  });

  testWidgets('compact rate label follows the generated theme accent',
      (tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.purple).copyWith(
      surface: const Color(0xFF172030),
      onSurface: const Color(0xFFF4E8FF),
    );
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: const Scaffold(
        body: PlaybackRateLabel(rate: 1.25),
      ),
    ));
    final label = tester.widget<Text>(find.text('1.25×'));
    expect(label.style?.color, scheme.primary);
    expect(label.style?.fontWeight, FontWeight.w700);
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets('mode switching disables reentry and save failures are retryable',
      (tester) async {
    var retries = 0;
    await mount(
        tester,
        PlaybackSettingsPanel(
          playbackRate: 1.5,
          exclusive: true,
          changingOutput: true,
          error: '当前会话已应用，但设置保存失败：test',
          onRateChanged: (_) {},
          onExclusiveChanged: (_) => fail('Concurrent mode switch'),
          onRetrySave: () => retries++,
        ));
    expect(find.text('正在切换输出模式…'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull);
    await tester.tap(find.text('重试保存'));
    expect(retries, 1);
  });

  for (final width in [320.0, 440.0, 900.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('rate/output panel fits width $width at text scale $scale',
          (tester) async {
        await mount(
            tester,
            PlaybackSettingsPanel(
              playbackRate: 1.25,
              exclusive: false,
              deferred: true,
              error: '设置保存失败，当前会话仍然有效。',
              onRateChanged: (_) {},
              onExclusiveChanged: (_) {},
            ),
            width: width,
            scale: scale);
        expect(tester.takeException(), isNull);
        for (final rate in PlaybackRate.presets) {
          final chip =
              find.widgetWithText(ChoiceChip, PlaybackRate.label(rate));
          await tester.ensureVisible(chip);
          await tester.pumpAndSettle();
          expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
        }
        await tester.ensureVisible(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
