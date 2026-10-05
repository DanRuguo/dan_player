import 'package:dan_player/component/process_resource_monitor.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';
import 'support/process_resource_fixture.dart';

void main() {
  setUpAll(loadPlaylistFeatureFonts);

  testWidgets(
      'retained monitor rebinds worker and visibility owners atomically',
      (tester) async {
    sizePlaylistFeature(tester, width: 800, height: 1000);
    final oldRig = ResourceTestRig(), newRig = ResourceTestRig();
    final oldPrefs = ValueNotifier(
        const ProcessResourcePreferences(enabled: true, intervalSeconds: 5));
    final newPrefs = ValueNotifier(
        const ProcessResourcePreferences(enabled: true, intervalSeconds: 1));
    final oldHidden = ValueNotifier(false), newHidden = ValueNotifier(false);
    Widget host(bool replacement) => playlistFeatureHost(Scaffold(
            body: SingleChildScrollView(
                child: ProcessResourceMonitor(
          key: const ValueKey('retained-settings-monitor'),
          controller: replacement ? newRig.service : oldRig.service,
          preferences: replacement ? newPrefs : oldPrefs,
          isHidden: replacement ? newHidden : oldHidden,
        ))));

    await tester.pumpWidget(host(false));
    await tester.pumpAndSettle();
    expect(oldRig.service.active, isTrue);
    await tester.pumpWidget(host(true));
    await tester.pumpAndSettle();
    expect(oldRig.service.active, isFalse,
        reason: 'The retained settings State must release its former worker.');
    expect(newRig.service.active, isTrue);
    expect((newRig.calls.last.arguments as Map)['intervalSeconds'], 1);
    await newRig.sample(cpu: 18);
    await tester.pump();
    expect(find.text('18.0%'), findsOneWidget);
    oldHidden.value = true;
    oldPrefs.value = const ProcessResourcePreferences();
    await tester.pumpAndSettle();
    expect(newRig.service.active, isTrue);
    expect(find.text('18.0%'), findsOneWidget);
    newHidden.value = true;
    await tester.pumpAndSettle();
    expect(newRig.service.active, isFalse);
    await tester.pumpWidget(const SizedBox());
    await oldRig.close();
    await newRig.close();
    for (final notifier in [oldPrefs, newPrefs, oldHidden, newHidden]) {
      notifier.dispose();
    }
  });
}
