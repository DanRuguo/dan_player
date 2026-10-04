import 'package:dan_player/component/process_resource_monitor.dart';
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
      'monitor defaults off and explicit real switch alone starts sampling',
      (tester) async {
    sizePlaylistFeature(tester, width: 800, height: 900);
    final rig = ResourceTestRig();
    final prefs = ValueNotifier(const ProcessResourcePreferences());
    final hidden = ValueNotifier(false);
    await tester.pumpWidget(listeningStatusHost(SingleChildScrollView(
        child: ProcessResourceMonitor(
            preferences: prefs,
            controller: rig.service,
            isHidden: hidden,
            onPreferencesChanged: (value) async => prefs.value = value))));
    await tester.pumpAndSettle();
    expect(rig.calls, isEmpty);
    expect(find.byKey(const ValueKey('resource-interval')), findsNothing);
    expect(find.text(ui('CPU')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('resource-enabled')));
    await tester.pumpAndSettle();
    expect(prefs.value.enabled, isTrue);
    expect(rig.calls.last.method, 'start');
    await rig.sample();
    await tester.pump();
    expect(find.text('12.5%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('resource-enabled')));
    await tester.pumpAndSettle();
    expect(prefs.value.enabled, isFalse);
    expect(rig.calls.last.method, 'stop');
    expect(find.text('12.5%'), findsNothing);
    final count = rig.service.history.length;
    await rig.sample();
    expect(rig.service.history, hasLength(count));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 30));
    expect(rig.calls, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    await rig.close();
    prefs.dispose();
    hidden.dispose();
  });
  testWidgets(
      'growing preceding section stops monitor without rebuilding its child',
      (tester) async {
    sizePlaylistFeature(tester, width: 800, height: 600);
    final rig = ResourceTestRig();
    final prefs =
        ValueNotifier(const ProcessResourcePreferences(enabled: true));
    final hidden = ValueNotifier(false);
    final height = ValueNotifier(0.0);
    final monitor = ProcessResourceMonitor(
        controller: rig.service, preferences: prefs, isHidden: hidden);
    await tester.pumpWidget(listeningStatusHost(SingleChildScrollView(
        child: ValueListenableBuilder<double>(
            valueListenable: height,
            child: monitor,
            builder: (context, value, child) =>
                Column(children: [SizedBox(height: value), child!])))));
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'start');
    height.value = 900;
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'stop');
    height.value = 0;
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'start');
    await tester.pumpWidget(const SizedBox());
    await rig.close();
    prefs.dispose();
    hidden.dispose();
    height.dispose();
  });
  testWidgets(
      'viewport reveal, scroll away, native hide and TickerMode stop actual channel',
      (tester) async {
    sizePlaylistFeature(tester, width: 800, height: 600);
    final rig = ResourceTestRig();
    final prefs =
        ValueNotifier(const ProcessResourcePreferences(enabled: true));
    final hidden = ValueNotifier(false);
    final scroll = ScrollController();
    Widget host(bool tickers) => listeningStatusHost(TickerMode(
        enabled: tickers,
        child: SingleChildScrollView(
            controller: scroll,
            child: Column(children: [
              const SizedBox(height: 900),
              ProcessResourceMonitor(
                  preferences: prefs, controller: rig.service, isHidden: hidden)
            ]))));
    await tester.pumpWidget(host(true));
    await tester.pumpAndSettle();
    expect(rig.calls, isEmpty);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'start');
    await rig.sample();
    await tester.pump();
    hidden.value = true;
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'stop');
    final before = rig.service.history.length;
    await rig.sample();
    expect(rig.service.history, hasLength(before));
    hidden.value = false;
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'start');
    await tester.pumpWidget(host(false));
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'stop');
    await tester.pumpWidget(host(true));
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'start');
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'stop');
    await tester.pumpWidget(const SizedBox());
    await rig.close();
    prefs.dispose();
    hidden.dispose();
    scroll.dispose();
  });
  testWidgets(
      'real menus switch interval and display with truthful unavailable metrics and save failure',
      (tester) async {
    sizePlaylistFeature(tester, width: 800, height: 900);
    final rig = ResourceTestRig();
    final prefs =
        ValueNotifier(const ProcessResourcePreferences(enabled: true));
    final hidden = ValueNotifier(false);
    bool fail = false;
    await tester.pumpWidget(listeningStatusHost(SingleChildScrollView(
        child: ProcessResourceMonitor(
            controller: rig.service,
            preferences: prefs,
            isHidden: hidden,
            onPreferencesChanged: (value) async {
              prefs.value = value;
              if (fail) throw StateError('fixture');
            }))));
    await tester.pumpAndSettle();
    await rig.sample(cpu: null, cpuStatus: 'warming');
    await tester.pump();
    expect(find.text(ui('等待采样')), findsOneWidget);
    expect(find.text(ui('不可用')), findsOneWidget);
    for (final id in ['resource-interval', 'resource-display']) {
      await tester.tap(find.byKey(ValueKey(id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(id == 'resource-interval'
          ? 'resource-interval-1'
          : 'resource-display-line')));
      await tester.pumpAndSettle();
    }
    expect(prefs.value.intervalSeconds, 1);
    expect(prefs.value.display, ProcessResourceDisplay.line);
    expect(
        (rig.calls.lastWhere((c) => c.method == 'start').arguments
            as Map)['intervalSeconds'],
        1);
    final count = rig.calls.length;
    fail = true;
    await tester.tap(find.byKey(const ValueKey('resource-display')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('resource-display-bar')));
    await tester.pumpAndSettle();
    expect(rig.calls, hasLength(count));
    expect(find.text(ui('设置保存失败，本次会话仍保留当前选择')), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 30));
    expect(rig.calls, hasLength(count));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await rig.close();
    prefs.dispose();
    hidden.dispose();
  });
  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'resources ${language.code} ${narrow ? 'narrow 200%' : 'wide'} all three displays',
          (tester) async {
        uiLanguage.value = language;
        sizePlaylistFeature(tester,
            width: narrow ? 360 : 1000, height: narrow ? 1800 : 1100);
        final rig = ResourceTestRig();
        final prefs =
            ValueNotifier(const ProcessResourcePreferences(enabled: true));
        final hidden = ValueNotifier(false);
        final boundary = GlobalKey();
        await tester.pumpWidget(listeningStatusHost(
            SingleChildScrollView(
                child: ProcessResourceMonitor(
                    controller: rig.service,
                    preferences: prefs,
                    isHidden: hidden,
                    onPreferencesChanged: (value) async =>
                        prefs.value = value)),
            scale: narrow ? 2 : 1,
            brightness: narrow ? Brightness.dark : Brightness.light,
            boundary: boundary));
        await tester.pumpAndSettle();
        await rig.sample(cpu: 10, gpu: 26);
        await tester.pump();
        await rig.sample(cpu: 25, gpu: null);
        await tester.pump();
        await rig.sample(cpu: 18, gpu: 42, memory: 80 * 1024 * 1024);
        await tester.pump();
        final starts = rig.calls.length;
        for (final display in ProcessResourceDisplay.values) {
          prefs.value = prefs.value.copyWith(display: display);
          await tester.pumpAndSettle();
          expect(find.text('18.0%'), findsOneWidget);
          expect(find.text('42.0%'), findsOneWidget);
          expect(find.text('80.0 MiB'), findsOneWidget);
          expect(find.byKey(const ValueKey('resource-interval')).hitTestable(),
              findsOneWidget);
          expect(find.byKey(const ValueKey('resource-display')).hitTestable(),
              findsOneWidget);
          expect(rig.calls, hasLength(starts));
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
          await captureListeningStatus(tester, boundary,
              'resources-${language.code}-${narrow ? 'narrow' : 'wide'}-${display.name}');
        }
        await tester.pumpWidget(const SizedBox());
        await rig.close();
        prefs.dispose();
        hidden.dispose();
      });
    }
  }
}
