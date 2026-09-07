import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/page/settings_page/replay_gain_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/replay_gain.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  Future<void> host(WidgetTester tester, Widget child,
      {double width = 900, double scale = 1}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('real settings open without initializing audio', (tester) async {
    expect(PlayService.isInitialized, isFalse);
    await host(tester, const ReplayGainSettings());
    expect(PlayService.isInitialized, isFalse);
    expect(find.byKey(const ValueKey('replay-gain-mode')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode and peak protection dispatch independently',
      (tester) async {
    var preferences = const ReplayGainPreferences();
    await host(
        tester,
        StatefulBuilder(
            builder: (context, setState) => ReplayGainSettingsPanel(
                preferences: preferences,
                onChanged: (next) => setState(() => preferences = next))));
    final peak = find.byKey(const ValueKey('replay-gain-prevent-clipping'));
    expect(tester.widget<SwitchListTile>(peak).onChanged, isNull);
    await tester.tap(find.text(ui('专辑均衡')));
    await tester.pumpAndSettle();
    expect(preferences.mode, ReplayGainMode.album);
    expect(preferences.preventClipping, isTrue);
    await tester.tap(peak);
    await tester.pumpAndSettle();
    expect(preferences.mode, ReplayGainMode.album);
    expect(preferences.preventClipping, isFalse);
    await tester.tap(find.text(ui('关闭')).first);
    await tester.pumpAndSettle();
    expect(preferences.mode, ReplayGainMode.off);
    expect(tester.widget<SwitchListTile>(peak).onChanged, isNull);
  });

  testWidgets('narrow large-text translated settings expose all choices',
      (tester) async {
    uiLanguage.value = UiLanguage.en;
    await host(
        tester,
        ReplayGainSettingsPanel(
            preferences: const ReplayGainPreferences(), onChanged: (_) {}),
        width: 320,
        scale: 2);
    final control = find.byType(AppSegmentedControl<ReplayGainMode>);
    final button =
        find.descendant(of: control, matching: find.byType(IconButton));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Track gain'), findsOneWidget);
    expect(find.text('Album gain'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
