import 'dart:ui' show PointerDeviceKind;

import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/component/side_nav_layout.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/playlist_feature_fixture.dart';

const _audioPath = app_paths.AUDIOS_PAGE;
final _audioButton = find.byKey(const ValueKey('continuous-nav-$_audioPath'));
final _label = find.byKey(const ValueKey('nav-label-opacity-$_audioPath'));
Finder get _icon =>
    find.descendant(of: _audioButton, matching: find.byType(Icon));

class _Fixture {
  final state = ValueNotifier((width: 300.0, resizing: false, visible: true));
  final boundary = GlobalKey();
  late GoRouter router;
  double threshold = 0;
  double get width => state.value.width;
  double opacity(WidgetTester tester) => tester.widget<Opacity>(_label).opacity;
  void update({double? width, bool? resizing, bool? visible}) => state.value = (
        width: width ?? state.value.width,
        resizing: resizing ?? state.value.resizing,
        visible: visible ?? state.value.visible,
      );
}

Future<_Fixture> _mount(WidgetTester tester,
    {UiLanguage language = UiLanguage.zh,
    double scale = 1,
    bool disabled = false,
    bool reduced = false}) async {
  sizePlaylistFeature(tester, width: 1200, height: 850);
  uiLanguage.value = language;
  final fixture = _Fixture();
  addTearDown(fixture.state.dispose);
  final startPage = AppPreference.instance.startPage;
  addTearDown(() => AppPreference.instance.startPage = startPage);
  fixture.router = GoRouter(initialLocation: _audioPath, routes: [
    for (final destination in destinations)
      GoRoute(
        path: destination.desPath,
        builder: (_, __) => Scaffold(
          body: ValueListenableBuilder(
            valueListenable: fixture.state,
            builder: (context, value, _) {
              fixture.threshold = sideNavCompactThreshold(context,
                  destinations.map((destination) => destination.label));
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RepaintBoundary(
                      key: destination.desPath == _audioPath
                          ? fixture.boundary
                          : null,
                      child: SizedBox(
                        width: value.width,
                        child: TickerMode(
                          enabled: value.visible,
                          child: SideNav(
                              desktopWidth: value.width,
                              resizing: value.resizing),
                        ),
                      ),
                    ),
                    const Expanded(child: SizedBox()),
                  ]);
            },
          ),
        ),
      ),
  ]);
  addTearDown(fixture.router.dispose);
  await tester.pumpWidget(UiLanguageScope(
    child: MotionPreferencesScope(
      preferences: disabled
          ? const MotionPreferences(disabled: {MotionKind.layout})
          : const MotionPreferences(),
      child: MaterialApp.router(
        theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
        routerConfig: fixture.router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale), disableAnimations: reduced),
          child: AppEntranceScope(child: child!),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return fixture;
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final language in UiLanguage.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('${language.code}/$scale measures labels and restores color',
          (tester) async {
        final fixture = await _mount(tester, language: language, scale: scale);
        if (language == UiLanguage.zh && scale == 1) {
          expect(fixture.threshold, lessThan(156),
              reason:
                  'normal Chinese labels collapse later than the old cutoff');
        }
        fixture.update(width: fixture.threshold + 12, resizing: true);
        await tester.pumpAndSettle();
        expect(fixture.opacity(tester), closeTo(.25, .001));
        fixture.update(resizing: false);
        await tester.pump();
        expect(fixture.opacity(tester), closeTo(.25, .001));
        await tester.pump(const Duration(milliseconds: 70));
        expect(fixture.opacity(tester), inExclusiveRange(.25, 1));
        await tester.pumpAndSettle();
        expect(fixture.opacity(tester), 1);
        fixture.update(width: fixture.threshold + .1);
        await tester.pumpAndSettle();
        for (final destination in destinations) {
          final label = find.text(destination.label);
          final paragraph = tester.renderObject<RenderParagraph>(label);
          expect(paragraph.getMaxIntrinsicWidth(double.infinity),
              lessThanOrEqualTo(paragraph.size.width + .05),
              reason: 'the cutoff must use the exact rendered label style');
        }
        expect(find.text(ui('文件夹')), findsOneWidget);
        await capturePlaylistFeature(tester, fixture.boundary,
            'sidebar-${language.code}-$scale-restored');
        fixture.update(width: fixture.threshold - 4, resizing: true);
        await tester.pumpAndSettle();
        expect(find.text(ui('音乐')), findsNothing);
        expect(tester.getCenter(_icon).dx, closeTo(fixture.width / 2, .01));
        expect(find.byTooltip(ui('音乐')), findsOneWidget);
        await capturePlaylistFeature(tester, fixture.boundary,
            'sidebar-${language.code}-$scale-compact');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('icons move both ways, reverse continuously and finish idle',
      (tester) async {
    final fixture = await _mount(tester);
    fixture.update(width: fixture.threshold + 24, resizing: true);
    await tester.pumpAndSettle();
    final expanded = tester.getCenter(_icon).dx;
    fixture.update(width: fixture.threshold - 4);
    await tester.pump();
    expect(tester.getCenter(_icon).dx, closeTo(expanded, .01));
    await tester.pump(const Duration(milliseconds: 60));
    final inward = tester.getCenter(_icon).dx;
    expect(inward, inExclusiveRange(expanded, fixture.width / 2));
    await capturePlaylistFeature(
        tester, fixture.boundary, 'sidebar-inward-mid');
    fixture.update(width: fixture.threshold + 4);
    await tester.pump();
    expect((tester.getCenter(_icon).dx - inward).abs(), lessThan(5));
    await tester.pumpAndSettle();
    expect(tester.getCenter(_icon).dx, closeTo(expanded, .01));
    fixture.update(width: fixture.threshold - 4);
    await tester.pumpAndSettle();
    fixture.update(width: fixture.threshold + 24, resizing: false);
    await tester.pump();
    final starting = tester.getCenter(_icon).dx;
    await tester.pump(const Duration(milliseconds: 140));
    expect(tester.getCenter(_icon).dx, inExclusiveRange(expanded, starting));
    expect(fixture.opacity(tester), inExclusiveRange(0, 1));
    await capturePlaylistFeature(
        tester, fixture.boundary, 'sidebar-outward-mid');
    await tester.pumpAndSettle();
    expect(tester.getCenter(_icon).dx, closeTo(expanded, .01));
    expect(fixture.opacity(tester), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing system reduceMotion finishes an active transition',
      (tester) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final fixture = await _mount(tester);
    fixture.update(width: fixture.threshold - 4, resizing: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getCenter(_icon).dx, lessThan(fixture.width / 2));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();
    expect(tester.getCenter(_icon).dx, closeTo(fixture.width / 2, .01));
    fixture.update(width: fixture.threshold + 12, resizing: false);
    await tester.pump();
    expect(fixture.opacity(tester), 1);
    expect(tester.getCenter(_icon).dx, closeTo(40, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact and expanded destinations accept pointer and keyboard',
      (tester) async {
    final fixture = await _mount(tester);
    fixture.update(width: fixture.threshold - 4);
    await tester.pumpAndSettle();
    final folder =
        find.byKey(const ValueKey('continuous-nav-${app_paths.FOLDERS_PAGE}'));
    await tester.tap(folder);
    await tester.pumpAndSettle();
    expect(fixture.router.routeInformationProvider.value.uri.path,
        app_paths.FOLDERS_PAGE);
    fixture.update(width: fixture.threshold + 12);
    await tester.pumpAndSettle();
    Focus.of(tester.element(_icon)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(fixture.router.routeInformationProvider.value.uri.path, _audioPath);
    expect(tester.takeException(), isNull);
  });

  for (final policy in ['disabled', 'reduced', 'hidden']) {
    testWidgets('$policy commits the final state without lingering motion',
        (tester) async {
      final fixture = await _mount(tester,
          disabled: policy == 'disabled', reduced: policy == 'reduced');
      fixture.update(width: fixture.threshold + 12, resizing: true);
      await tester.pumpAndSettle();
      fixture.update(width: fixture.threshold - 4);
      await tester.pump();
      if (policy == 'hidden') {
        await tester.pump(const Duration(milliseconds: 60));
        fixture.update(visible: false, resizing: false);
        await tester.pump();
      }
      expect(tester.getCenter(_icon).dx, closeTo(fixture.width / 2, .01));
      fixture.update(width: fixture.threshold + 12, resizing: false);
      await tester.pump();
      expect(tester.getCenter(_icon).dx, closeTo(40, .01));
      expect(fixture.opacity(tester), 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('$kind real resize release and cancel restore readable labels',
        (tester) async {
      sizePlaylistFeature(tester, width: 1200, height: 850);
      final preferences = ValueNotifier(const PlayerExperiencePreferences());
      addTearDown(preferences.dispose);
      var saves = 0;
      final router = GoRouter(initialLocation: _audioPath, routes: [
        GoRoute(
            path: _audioPath,
            builder: (_, __) => Scaffold(
                  body: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ResizableSideNav(
                            preferences: preferences,
                            persist: () async {
                              saves++;
                            }),
                        const Expanded(child: SizedBox()),
                      ]),
                )),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(
          UiLanguageScope(child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
          tester
              .getCenter(find.byKey(const ValueKey('side-nav-resize-handle'))),
          kind: kind);
      await gesture.moveBy(const Offset(-145, 0));
      await tester.pump();
      final faded = tester.widget<Opacity>(_label).opacity;
      expect(faded, inExclusiveRange(0, 1));
      expect(saves, 0);
      if (kind == PointerDeviceKind.mouse) {
        await gesture.up();
      } else {
        await gesture.cancel();
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(
          tester.widget<Opacity>(_label).opacity, inExclusiveRange(faded, 1));
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(_label).opacity, 1);
      expect(saves, 1);
      expect(preferences.value.sidebarWidth, 155);
      expect(tester.takeException(), isNull);
    });
  }
}
