import 'package:dan_player/component/compact_process_resource_monitor.dart';
import 'package:dan_player/component/process_resource_monitor.dart';
import 'package:dan_player/process_resource_coordinator.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';
import 'support/process_resource_fixture.dart';

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  testWidgets(
      'expanded line sidebar exposes its range without replacing the icon',
      (tester) async {
    sizePlaylistFeature(tester, width: 800, height: 600);
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final preferences = ValueNotifier(const ProcessResourcePreferences(
        enabled: true,
        showInSidebar: true,
        display: ProcessResourceDisplay.line));
    final hidden = ValueNotifier(false);
    var compact = false;
    late StateSetter update;
    await tester.pumpWidget(listeningStatusHost(
        Center(child: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return SizedBox(
          width: compact ? 80 : 260,
          child: CompactProcessResourceMonitor(
              surface: ProcessResourceSurface.sidebar,
              compactSidebar: compact,
              preferences: preferences,
              coordinator: coordinator,
              isHidden: hidden));
    }))));
    await tester.pumpAndSettle();
    await rig.sample(cpu: .2);
    await tester.pump();
    final cpu = find.byKey(const ValueKey('compact-resource-sidebar-CPU'));
    final icon = find.descendant(of: cpu, matching: find.byType(Icon));
    final originalIcon = tester.element(icon);
    final tooltip = find.descendant(of: cpu, matching: find.byType(Tooltip));
    final range = ui('自动量程：{0}–{1}；分度：{2}', ['0.0%', '1.0%', '0.5%']);
    expect(tester.widget<Tooltip>(tooltip).message, 'CPU: 0.2%\n$range');
    update(() => compact = true);
    await tester.pumpAndSettle();
    expect(tester.element(icon), same(originalIcon));
    expect(tester.widget<Tooltip>(tooltip).message, 'CPU: 0.2%\n$range');
    update(() => compact = false);
    await tester.pumpAndSettle();
    expect(tester.element(icon), same(originalIcon));
    await tester.pumpWidget(const SizedBox());
    coordinator.dispose();
    await rig.close();
    preferences.dispose();
    hidden.dispose();
  });
  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'adaptive ranges ${language.code} ${narrow ? 'narrow 200%' : 'wide'}',
          (tester) async {
        uiLanguage.value = language;
        sizePlaylistFeature(tester,
            width: narrow ? 360 : 1000, height: narrow ? 1800 : 1100);
        final rig = ResourceTestRig();
        final preferences = ValueNotifier(const ProcessResourcePreferences(
            enabled: true, display: ProcessResourceDisplay.line));
        final hidden = ValueNotifier(false);
        final scroll = ScrollController();
        final boundary = GlobalKey();
        await tester.pumpWidget(listeningStatusHost(
            SingleChildScrollView(
                controller: scroll,
                child: ProcessResourceMonitor(
                    preferences: preferences,
                    controller: rig.service,
                    isHidden: hidden)),
            scale: narrow ? 2 : 1,
            brightness: narrow ? Brightness.dark : Brightness.light,
            boundary: boundary));
        await tester.pumpAndSettle();
        await rig.sample(cpu: .2, gpu: 98.2, memory: 128 * 1024 * 1024);
        await tester.pump();
        await rig.sample(cpu: .5, gpu: 98.6, memory: 128.5 * 1024 * 1024 ~/ 1);
        await tester.pump();
        await rig.sample(cpu: .3, gpu: 98.3, memory: 128.2 * 1024 * 1024 ~/ 1);
        await tester.pumpAndSettle();
        expect(find.text('0.3%'), findsOneWidget);
        expect(find.text('98.3%'), findsOneWidget);
        expect(find.text('128.2 MiB'), findsOneWidget);
        expect(find.text(ui('自动量程：{0}–{1}；分度：{2}', ['0.0%', '1.0%', '0.5%'])),
            findsOneWidget);
        expect(
            find.text(ui(
                '自动量程：{0}–{1}；分度：{2}', ['127.5 MiB', '129.0 MiB', '0.5 MiB'])),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
        await captureListeningStatus(tester, boundary,
            'adaptive-resources-${language.code}-${narrow ? 'narrow' : 'wide'}');
        if (narrow) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(
              find
                  .text(ui('自动量程：{0}–{1}；分度：{2}',
                      ['127.5 MiB', '129.0 MiB', '0.5 MiB']))
                  .hitTestable(),
              findsOneWidget);
          await captureListeningStatus(tester, boundary,
              'adaptive-resources-${language.code}-narrow-bottom');
        }
        await tester.pumpWidget(const SizedBox());
        await rig.close();
        preferences.dispose();
        hidden.dispose();
        scroll.dispose();
      });
    }
  }
}
