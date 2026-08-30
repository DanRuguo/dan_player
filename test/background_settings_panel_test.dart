import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/page/settings_page/background_settings.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 520.0, 1100.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('background choices fit $width at text $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final preferences = ValueNotifier(const BackgroundPreferences());
        final status = ValueNotifier(
            const WindowBackdropStatus(available: true, effect: 'blur'));
        addTearDown(preferences.dispose);
        addTearDown(status.dispose);
        var saves = 0;
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 1100),
                  textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                  body: SingleChildScrollView(
                      child: BackgroundSettingsPanel(
                preferences: preferences,
                status: status,
                onSave: () async => saves++,
              )))),
        ));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
            find.byKey(const ValueKey('background-source-artwork')));
        await tester
            .tap(find.byKey(const ValueKey('background-source-artwork')));
        await tester.pumpAndSettle();
        expect(preferences.value.main.source, BackgroundSource.artwork);
        final slider = tester
            .widget<Slider>(find.byKey(const ValueKey('background-blur')));
        slider.onChanged!(90);
        await tester.pump();
        expect(preferences.value.main.blur, 90);
        expect(saves, 1,
            reason: 'Slider movement previews without writing on every frame');
        slider.onChangeEnd!(90);
        await tester.pump();
        expect(saves, 2);
        await tester
            .ensureVisible(find.byKey(const ValueKey('background-scene-mini')));
        await tester.tap(find.byKey(const ValueKey('background-scene-mini')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('background-blur')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('background-source-solid')));
        await tester.pumpAndSettle();
        expect(preferences.value.mini.source, BackgroundSource.solid);
        expect(preferences.value.main.blur, 90);
        expect(
            tester
                .widget<Slider>(
                    find.byKey(const ValueKey('background-opacity')))
                .onChanged,
            isNull);
        await tester
            .ensureVisible(find.byKey(const ValueKey('background-reset')));
        await tester.tap(find.byKey(const ValueKey('background-reset')));
        await tester.pumpAndSettle();
        expect(preferences.value.mini, const BackgroundPreferences().mini);
        expect(preferences.value.main.blur, 90,
            reason: 'Reset affects the selected scene only');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
