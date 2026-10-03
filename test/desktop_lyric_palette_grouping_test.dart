import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/appearance_palette_app.dart';
import 'package:desktop_lyric/appearance_palette_bridge.dart';
import 'package:desktop_lyric/component/desktop_lyric_appearance_options.dart';
import 'package:desktop_lyric/component/desktop_lyric_taskbar_options.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/desktop_lyric_test_support.dart';
import 'support/palette_test_bridge.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String name) => find.byKey(ValueKey(name));

class _Palette {
  final source = DesktopLyricController.detached(
      sendMessage: (_) {}, clock: PlaybackClock(automaticTicks: false));
  final window = FakeDesktopLyricWindow();
  late final layout = DesktopLyricWindowLayout(adapter: window);
  late final bridge = PaletteTestBridge(source: source, layout: layout);
  late DesktopLyricPaletteClient client;
  final calls = <String>[];
  Future<void>? opening;

  Future<void> initialize(
      {UiLanguage language = UiLanguage.zh, bool dark = false}) async {
    uiLanguage.value = language;
    source.appearance.value =
        DesktopLyricAppearance.defaults.copyWith(taskbarMode: true);
    source.theme.value = ThemeChangedMessage(dark ? 0xffe9b97c : 0xff397651,
        dark ? 0xff222723 : 0xfff6faf7, dark ? 0xffedf2ee : 0xff19241b);
    source.isDarkMode.value = dark;
    await layout.initialize(vertical: false);
    final request = bridge.child.request!;
    bridge.child.request = (call) {
      calls.add(call.method);
      // Only the native window transport is substituted; do not send stdout.
      if (call.method == 'taskbarLyrics') return Future.value(null);
      return request(call);
    };
    opening = bridge.host.open();
    await Future<void>.value();
    client = await bridge.connectClient();
    calls.clear();
  }

  void dispose() {
    bridge.dispose();
    layout.dispose();
    source.dispose();
  }
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  late MotionPreferences previousMotion;
  setUp(() {
    previousMotion = desktopMotionPreferences.value;
    desktopMotionPreferences.value = const MotionPreferences().all(false);
  });
  tearDown(() {
    desktopMotionPreferences.value = previousMotion;
    uiLanguage.value = UiLanguage.zh;
    Tooltip.dismissAllToolTips();
  });

  testWidgets(
      'palette groups choices switches and sliders with one button shape',
      (tester) async {
    sizePlaylistFeature(tester, width: 720, height: 1000);
    final fixture = _Palette();
    addTearDown(fixture.dispose);
    await fixture.initialize();
    await tester.pumpWidget(DesktopLyricAppearanceApp(client: fixture.client));
    await tester.pumpAndSettle();
    final switchButton = _key('desktop-switch-taskbar-lyrics');
    final followButton = _key('desktop-color-follow-theme');
    final shape =
        tester.widget<FilledButton>(switchButton).style!.shape!.resolve({});
    expect(shape, desktopLyricAppearanceControlShape);
    expect(tester.widget<FilledButton>(followButton).style!.shape!.resolve({}),
        shape);
    expect(tester.getRect(followButton).bottom,
        lessThan(tester.getRect(_key('desktop-taskbar-mode')).top));
    expect(tester.getRect(_key('desktop-taskbar-translation')).bottom,
        lessThanOrEqualTo(tester.getRect(_key('desktop-lyric-stroke')).top));
    expect(tester.getRect(_key('desktop-lyric-stroke')).bottom,
        lessThan(tester.getRect(_key('desktop-lyric-font-size')).top));
    expect(tester.getRect(_key('desktop-background-opacity')).bottom,
        lessThan(tester.getRect(_key('desktop-taskbar-gap')).top));

    await tester.ensureVisible(_key('desktop-lyric-stroke'));
    await tester.tap(_key('desktop-lyric-stroke'));
    await tester.pump();
    expect(fixture.client.appearance.value.strokeEnabled, isTrue);
    await tester.ensureVisible(_key('desktop-lyric-font-size'));
    await tester.drag(_key('desktop-lyric-font-size'), const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(fixture.client.appearance.value.lyricFontSize,
        isNot(DesktopLyricAppearance.defaults.lyricFontSize));
    await fixture.client.flush();
    expect(fixture.source.appearance.value.strokeEnabled, isTrue);
    expect(fixture.source.appearance.value.lyricFontSize,
        fixture.client.appearance.value.lyricFontSize);
    await tester.ensureVisible(switchButton);
    await tester.tap(switchButton);
    await tester.pumpAndSettle();
    expect(fixture.calls.where((method) => method == 'taskbarLyrics'),
        hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'shared default sections retain the main settings order and controls',
      (tester) async {
    sizePlaylistFeature(tester, width: 720, height: 1800);
    var appearance =
        DesktopLyricAppearance.defaults.copyWith(taskbarMode: true);
    await tester.pumpWidget(playlistFeatureHost(StatefulBuilder(
        builder: (_, update) => SingleChildScrollView(
                child: Column(children: [
              DesktopLyricAppearanceOptions(
                  appearance: appearance,
                  onChanged: (value) => update(() => appearance = value)),
              DesktopLyricTaskbarOptions(
                  appearance: appearance,
                  onChanged: (value) => update(() => appearance = value)),
            ])))));
    await tester.pumpAndSettle();
    expect(tester.getRect(_key('desktop-background-opacity')).bottom,
        lessThanOrEqualTo(tester.getRect(_key('desktop-lyric-stroke')).top));
    expect(tester.getRect(_key('desktop-lyric-stroke')).bottom,
        lessThan(tester.getRect(_key('desktop-color-follow-theme')).top));
    expect(
        tester.getRect(_key('desktop-taskbar-minimum-font')).bottom,
        lessThanOrEqualTo(
            tester.getRect(_key('desktop-taskbar-translation')).top));
    await tester.tap(_key('desktop-taskbar-translation'));
    await tester.pump();
    expect(appearance.taskbarTranslation, isTrue);
    await tester.tap(_key('desktop-taskbar-mode'));
    await tester.pump();
    expect(appearance.taskbarMode, isFalse);
    expect(_key('desktop-taskbar-gap'), findsNothing);
    expect(_key('desktop-lyric-font-size'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets('grouped palette ${language.code} narrow=$narrow real fonts',
          (tester) async {
        final width = narrow ? 360.0 : 720.0;
        sizePlaylistFeature(tester, width: width, height: 1000);
        tester.platformDispatcher.textScaleFactorTestValue = narrow ? 2 : 1;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final fixture = _Palette();
        addTearDown(fixture.dispose);
        await fixture.initialize(language: language, dark: narrow);
        final boundary = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: DesktopLyricAppearanceApp(client: fixture.client)));
        await tester.pumpAndSettle();
        final scheme =
            Theme.of(tester.element(_key('desktop-switch-taskbar-lyrics')))
                .colorScheme;
        for (final name in [
          'desktop-switch-taskbar-lyrics',
          'desktop-color-follow-theme'
        ]) {
          final rect = tester.getRect(_key(name));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(
              tester.widget<FilledButton>(_key(name)).style!.shape!.resolve({}),
              desktopLyricAppearanceControlShape);
        }
        expect(scheme.primary,
            narrow ? const Color(0xffe9b97c) : const Color(0xff397651));
        await capturePlaylistFeature(tester, boundary,
            'grouped-${language.code}-${narrow ? 'narrow-large' : 'wide'}-choices-switches');
        await tester.ensureVisible(_key('desktop-taskbar-minimum-font'));
        await tester.pumpAndSettle();
        final last = tester.getRect(_key('desktop-taskbar-minimum-font'));
        expect(last.left, greaterThanOrEqualTo(0));
        expect(last.right, lessThanOrEqualTo(width));
        expect(last.bottom, lessThanOrEqualTo(1000));
        await capturePlaylistFeature(tester, boundary,
            'grouped-${language.code}-${narrow ? 'narrow-large' : 'wide'}-sliders');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }
}
