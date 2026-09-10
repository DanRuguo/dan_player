import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/appearance_palette_app.dart';
import 'package:desktop_lyric/appearance_palette_bridge.dart';
import 'package:desktop_lyric/component/desktop_lyric_body.dart';
import 'package:desktop_lyric/component/lyric_line_display_area.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_theme_transition.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/desktop_lyric_test_support.dart';
import 'support/palette_test_bridge.dart';

const first = ThemeChangedMessage(0xff116655, 0xffeeeeee, 0xff223322);
const second = ThemeChangedMessage(0xffddaaff, 0xff332244, 0xffeeeeff);
const third = ThemeChangedMessage(0xffeedd99, 0xff332211, 0xffeeddcc);

Map<String, Object?> _snapshot(int revision, ThemeChangedMessage colors) => {
      'session': 1,
      'revision': revision,
      'editAck': 0,
      'appearance': DesktopLyricAppearance.defaults.toJson(),
      'darkMode': false,
      'primary': colors.primary,
      'surfaceContainer': colors.surfaceContainer,
      'onSurface': colors.onSurface,
      'language': 'zh',
    };

Color _between(int a, int b, double t) =>
    Color(Color.lerp(Color(a), Color(b), AppMotion.standardCurve.transform(t))!
        .toARGB32());

void main() {
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets('visible lyric ink and backdrop use one 180ms colour clock',
      (tester) async {
    final source = DesktopLyricController.detached();
    final layout = DesktopLyricWindowLayout(adapter: FakeDesktopLyricWindow());
    addTearDown(source.dispose);
    addTearDown(layout.dispose);
    source.theme.value = first;
    source.appearance.value =
        DesktopLyricAppearance.defaults.copyWith(backgroundOpacity: .5);
    source.lyricLine.value =
        const LyricLineChangedMessage('Test lyric', Duration(seconds: 3));
    Widget host({bool reduced = false, bool ticker = true}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: TickerMode(
              enabled: ticker,
              child: ValueListenableBuilder<ThemeChangedMessage>(
                valueListenable: source.theme,
                builder: (context, colors, _) => DesktopLyricThemeTransition(
                  colors: colors,
                  builder: (context, current, _) =>
                      Provider<ThemeChangedMessage>.value(
                    value: current,
                    child: DesktopLyricBody(
                        controller: source,
                        windowLayout: layout,
                        sendMessage: (_) {}),
                  ),
                ),
              ),
            ),
          ),
        );
    Color ink() => tester
        .widget<DesktopLyricLineContent>(find.byType(DesktopLyricLineContent))
        .color;
    Color surface() => (tester
            .widget<DecoratedBox>(
                find.byKey(const ValueKey('desktop-lyric-background')))
            .decoration as BoxDecoration)
        .color!;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(ink(), Color(first.primary));
    source.theme.value = second;
    await tester.pump();
    expect(ink(), Color(first.primary));
    await tester.pump(const Duration(milliseconds: 90));
    expect(ink(), _between(first.primary, second.primary, .5));
    expect(
        surface(),
        _between(first.surfaceContainer, second.surfaceContainer, .5)
            .withValues(alpha: .5));
    final middle = ink();
    source.theme.value = third;
    await tester.pump();
    expect(ink(), middle,
        reason: 'A rapid replacement starts at the painted colour');
    await tester.pump(AppMotion.standard);
    expect(ink(), Color(third.primary));
    source.theme.value = first;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(host(reduced: true));
    expect(ink(), Color(first.primary));
    source.theme.value = second;
    await tester.pumpWidget(host(ticker: false));
    expect(ink(), Color(second.primary));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'palette surface, controls and ink interpolate together while visible',
      (tester) async {
    final client = DesktopLyricPaletteClient(
        channel: PaletteLoopbackChannel('test/palette_transition'));
    addTearDown(client.dispose);
    client.applySnapshot(_snapshot(1, first));
    await tester.pumpWidget(DesktopLyricAppearanceApp(client: client));
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('desktop-appearance-dialog'));
    Color surface() => tester.widget<Scaffold>(panel).backgroundColor!;
    Color primary() => Theme.of(tester.element(panel)).colorScheme.primary;
    Color closeInk() => tester
        .widget<IconButton>(
            find.byKey(const ValueKey('desktop-appearance-close')))
        .color!;
    client.applySnapshot(_snapshot(2, second));
    await tester.pump();
    expect(primary(), Color(first.primary));
    await tester.pump(const Duration(milliseconds: 90));
    expect(primary(), _between(first.primary, second.primary, .5));
    expect(surface(),
        _between(first.surfaceContainer, second.surfaceContainer, .5));
    expect(closeInk(), _between(first.onSurface, second.onSurface, .5));
    await tester.pump(const Duration(milliseconds: 90));
    expect(primary(), Color(second.primary));
    expect(surface(), Color(second.surfaceContainer));
    expect(closeInk(), Color(second.onSurface));
    client.applySnapshot(_snapshot(3, third));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    client.suspend();
    await tester.pump();
    expect(primary(), Color(third.primary),
        reason: 'Hidden panels finish pending colour interpolation');
    final next = _snapshot(1, first)..['session'] = 2;
    client.applySnapshot(next, beginSession: true);
    await tester.pump();
    expect(primary(), Color(first.primary),
        reason: 'Warm present paints the new theme on its first frame');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'platform reduced motion snaps an in-progress desktop colour change',
      (tester) async {
    ThemeChangedMessage? painted;
    Widget host(ThemeChangedMessage colors) => MaterialApp(
            home: DesktopLyricThemeTransition(
          colors: colors,
          builder: (_, current, __) {
            painted = current;
            return const SizedBox();
          },
        ));
    await tester.pumpWidget(host(first));
    await tester.pumpWidget(host(second));
    await tester.pump(const Duration(milliseconds: 30));
    expect(painted!.primary, isNot(second.primary));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(painted!.primary, second.primary);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'inactive desktop continues colours and hidden desktop snaps them',
      (tester) async {
    ThemeChangedMessage? painted;
    Widget host(ThemeChangedMessage colors) => MaterialApp(
          home: DesktopLyricThemeTransition(
            colors: colors,
            builder: (_, current, __) {
              painted = current;
              return const SizedBox();
            },
          ),
        );
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await tester.pumpWidget(host(first));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpWidget(host(second));
    await tester.pump(const Duration(milliseconds: 90));
    expect(
        Color(painted!.primary), _between(first.primary, second.primary, .5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(painted!.primary, second.primary);
    await tester.pumpWidget(host(third));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(painted!.primary, third.primary);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
