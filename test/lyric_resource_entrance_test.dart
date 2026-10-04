import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/title_bar.dart';
import 'package:dan_player/page/now_playing_page/page.dart';
import 'package:dan_player/process_resource_coordinator.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';
import 'support/process_resource_fixture.dart';

const _resources = ValueKey('lyrics-process-resources');

class _TitleFixture {
  _TitleFixture() {
    final saved = AppSettings.instance.processResources.value;
    AppSettings.instance.processResources.value =
        const ProcessResourcePreferences(
            enabled: true,
            showInLyrics: true,
            display: ProcessResourceDisplay.bar);
    addTearDown(() {
      AppSettings.instance.processResources.value = saved;
      uiLanguage.value = UiLanguage.zh;
    });
  }
  final rig = ResourceTestRig();
  late final coordinator =
      ProcessResourceCoordinator.forTesting(service: rig.service);
  final boundary = GlobalKey();
  final state = ValueNotifier((
    ready: true,
    visible: true,
    width: 400.0,
    reduced: false,
    entrance: true,
    scale: 1.0,
  ));

  Animation<double> motion(WidgetTester tester) =>
      AppEntrance.motionOf(tester.element(find.byKey(_resources)))!;

  void update(
      {bool? ready,
      bool? visible,
      double? width,
      bool? reduced,
      bool? entrance,
      double? scale}) {
    final v = state.value;
    state.value = (
      ready: ready ?? v.ready,
      visible: visible ?? v.visible,
      width: width ?? v.width,
      reduced: reduced ?? v.reduced,
      entrance: entrance ?? v.entrance,
      scale: scale ?? v.scale,
    );
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(UiLanguageScope(
        child: MaterialApp(
            theme: ThemeData(
                platform: TargetPlatform.windows,
                useMaterial3: true,
                fontFamily: danEmbeddedFontFamily,
                fontFamilyFallback: danFontFamilyFallback,
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
            home: Scaffold(
                body: ValueListenableBuilder(
                    valueListenable: state,
                    builder: (context, value, _) {
                      final title = RepaintBoundary(
                          key: boundary,
                          child: SizedBox(
                              width: value.width,
                              height: 56,
                              child: NowPlayingResourceTitleBar(
                                  resourceCoordinator: coordinator)));
                      return MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                              disableAnimations: value.reduced,
                              textScaler: TextScaler.linear(value.scale)),
                          child: MotionPreferencesScope(
                              preferences: MotionPreferences(
                                  disabled: value.entrance
                                      ? const {}
                                      : const {MotionKind.entrance}),
                              child: AppEntranceScope(
                                  ready: value.ready,
                                  child: TickerMode(
                                      enabled: value.visible,
                                      child: Offstage(
                                          offstage: !value.visible,
                                          child: Align(
                                              alignment: Alignment.topLeft,
                                              child: title))))));
                    })))));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    coordinator.dispose();
    await rig.close();
    state.dispose();
  }
}

Finder _metric(String name) =>
    find.byKey(ValueKey('compact-resource-lyrics-$name'));
Finder _icon(String name) =>
    find.descendant(of: _metric(name), matching: find.byType(Icon));

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('window_manager'),
            (call) async =>
                call.method == 'isFullScreen' || call.method == 'isMaximized'
                    ? false
                    : null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });

  for (final language in UiLanguage.values) {
    testWidgets(
        '${language.name} title resources rise and fade as one finite group',
        (tester) async {
      sizePlaylistFeature(tester, width: 700, height: 300);
      final fixture = _TitleFixture();
      uiLanguage.value = language;
      fixture.update(scale: language == UiLanguage.ko ? 2 : 1);
      try {
        await fixture.mount(tester);
        final resources = find.byKey(_resources);
        final originalElement = resources.evaluate().single;
        final motion = fixture.motion(tester);
        final before = tester.getCenter(_icon('CPU'));
        expect(motion.value, 0);
        expect(find.ancestor(of: resources, matching: find.byType(AppEntrance)),
            findsOneWidget);
        await tester.pump(const Duration(milliseconds: 20));
        expect(motion.value, 0,
            reason: 'the resource group follows the back icon');
        await tester.pump(const Duration(milliseconds: 50));
        final partial = motion.value;
        expect(partial, inExclusiveRange(0, 1));
        expect(tester.getCenter(_icon('CPU')).dy, lessThan(before.dy));
        await fixture.coordinator.settled;
        expect(fixture.rig.calls.map((c) => c.method), ['start']);
        await fixture.rig.sample(cpu: 23.4, gpu: 11.2);
        await tester.pump();
        expect(identical(resources.evaluate().single, originalElement), isTrue);
        expect(identical(fixture.motion(tester), motion), isTrue,
            reason: 'sampling must not restart the appearance');
        expect(motion.value, partial);
        await capturePlaylistFeature(tester, fixture.boundary,
            'lyric-resources-${language.name}-entering');
        await tester.pumpAndSettle();
        expect(motion.value, 1);
        expect(before.dy - tester.getCenter(_icon('CPU')).dy,
            AppEntrance.distance);
        for (final metric in ['CPU', 'GPU', 'RAM']) {
          expect(tester.getSize(_metric(metric)).width, 40);
          expect(tester.widget<Icon>(_icon(metric)).size, 24);
        }
        final windowIcons = find.descendant(
            of: find.byType(WindowControlls), matching: find.byType(Icon));
        expect(tester.getCenter(windowIcons.first).dy, 28);
        expect(tester.takeException(), isNull);
        await capturePlaylistFeature(tester, fixture.boundary,
            'lyric-resources-${language.name}-settled');
        await tester.pump(const Duration(seconds: 1));
        expect(tester.binding.transientCallbackCount, 0);
        expect(fixture.rig.calls.map((c) => c.method), ['start']);
      } finally {
        await fixture.close(tester);
      }
      expect(fixture.rig.calls.map((c) => c.method), ['start', 'stop']);
    });
  }

  testWidgets('title resources defer entrance behind startup readiness',
      (tester) async {
    sizePlaylistFeature(tester, width: 700, height: 300);
    final fixture = _TitleFixture()..update(ready: false);
    try {
      await fixture.mount(tester);
      expect(fixture.motion(tester).value, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      expect(fixture.motion(tester).value, 0);
      fixture.update(ready: true);
      await tester.pump();
      expect(fixture.motion(tester).value, 0);
      await tester.pump(const Duration(milliseconds: 80));
      expect(fixture.motion(tester).value, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(fixture.motion(tester).value, 1);
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets(
      'hidden title stops motion and sampling without replay on restoration',
      (tester) async {
    sizePlaylistFeature(tester, width: 700, height: 300);
    final fixture = _TitleFixture();
    try {
      await fixture.mount(tester);
      await tester.pump(const Duration(milliseconds: 60));
      expect(fixture.motion(tester).value, inExclusiveRange(0, 1));
      fixture.update(visible: false);
      await tester.pump();
      await fixture.coordinator.settled;
      expect(fixture.coordinator.service.active, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      fixture.update(visible: true);
      await tester.pumpAndSettle();
      expect(fixture.motion(tester).value, 1);
      fixture.update(width: 350);
      await tester.pumpAndSettle();
      expect(find.byKey(_resources), findsNothing);
      expect(fixture.coordinator.service.active, isFalse);
      fixture.update(width: 400);
      await tester.pump();
      expect(fixture.motion(tester).value, 1,
          reason:
              'reappearing in the same route must reuse its remembered identity');
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    } finally {
      await fixture.close(tester);
    }
  });

  for (final method in ['setting', 'media-query', 'native-accessibility']) {
    testWidgets('$method immediately finishes title resource entrance',
        (tester) async {
      sizePlaylistFeature(tester, width: 700, height: 300);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final fixture = _TitleFixture();
      try {
        await fixture.mount(tester);
        await tester.pump(const Duration(milliseconds: 60));
        expect(fixture.motion(tester).value, inExclusiveRange(0, 1));
        switch (method) {
          case 'setting':
            fixture.update(entrance: false);
          case 'media-query':
            fixture.update(reduced: true);
          case 'native-accessibility':
            tester.platformDispatcher.accessibilityFeaturesTestValue =
                const FakeAccessibilityFeatures(reduceMotion: true);
        }
        await tester.pump();
        expect(fixture.motion(tester).value, 1);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.binding.transientCallbackCount, 0);
        await fixture.coordinator.settled;
        expect(fixture.rig.calls.map((c) => c.method), ['start']);
      } finally {
        await fixture.close(tester);
      }
    });
  }
}
