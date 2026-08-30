import 'dart:async';

import 'package:desktop_lyric/appearance_palette_app.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/desktop_lyric_test_support.dart';
import 'support/palette_test_bridge.dart';

const _titles = {
  UiLanguage.zh: '歌词外观',
  UiLanguage.en: 'Lyrics appearance',
  UiLanguage.ja: '歌詞の外観',
  UiLanguage.ko: '가사 모양',
};

void main() {
  for (final mode in ['horizontal', 'vertical', 'taskbar']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'independent four-language palette retains edits $mode / $scale',
          (tester) async {
        final previousLanguage = uiLanguage.value;
        uiLanguage.value = UiLanguage.zh;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(507, 320);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        final messages = <String>[];
        final source = DesktopLyricController.detached(
            clock: PlaybackClock(automaticTicks: false),
            sendMessage: messages.add);
        final native = FakeDesktopLyricWindow();
        final layout = DesktopLyricWindowLayout(adapter: native);
        source.vertical.value = mode == 'vertical';
        source.appearance.value = source.appearance.value.copyWith(
            lyricFontSize: 32,
            translationFontSize: 24,
            customColor: Colors.pink.toARGB32(),
            textOpacity: .55,
            backgroundOpacity: .2,
            strokeEnabled: true,
            taskbarMode: mode == 'taskbar',
            taskbarHeight: 48);
        await layout.initialize(
            vertical: source.vertical.value,
            appearance: source.appearance.value);
        native.operations.clear();
        final transport = PaletteTestBridge(source: source, layout: layout);
        unawaited(transport.host.open());
        await tester.pump();
        final client = await transport.connectClient();
        await tester.pumpWidget(DesktopLyricAppearanceApp(client: client));
        await tester.pumpAndSettle();
        final dialog = find.byKey(const ValueKey('desktop-appearance-dialog'));
        final panelState = tester.state<ScaffoldState>(dialog);
        final opacity = find.byKey(const ValueKey('desktop-text-opacity'));
        await tester.ensureVisible(opacity);
        await tester.pumpAndSettle();
        tester.widget<Slider>(opacity).onChanged!(.63);
        await tester.pump(const Duration(milliseconds: 40));
        await tester.pumpAndSettle();
        final editedAppearance = source.appearance.value;
        expect(editedAppearance.textOpacity, .63);
        final savedMessages = messages.length;

        for (final language in UiLanguage.values) {
          uiLanguage.value = language;
          final dark = language.index.isOdd;
          source.isDarkMode.value = dark;
          final primary =
              dark ? const Color(0xfff4dc91) : const Color(0xffb75424);
          final foreground =
              dark ? const Color(0xffeee8e1) : const Color(0xff24201c);
          source.handleMessage(ThemeChangedMessage(primary.toARGB32(),
                  dark ? 0xff222222 : 0xfff6ede8, foreground.toARGB32())
              .buildMessageJson());
          await tester.pumpAndSettle();
          expect(tester.state<ScaffoldState>(dialog), same(panelState));
          expect(source.appearance.value, editedAppearance);
          expect(messages.length, savedMessages,
              reason: 'Snapshots must never echo edits to the player.');
          final title = find.text(_titles[language]!);
          expect(title, findsOneWidget);
          expect(tester.widget<Text>(title).style!.color, foreground);
          expect(tester.getCenter(title).dx, closeTo(507 / 2, .01));
          final close = tester.widget<IconButton>(
              find.byKey(const ValueKey('desktop-appearance-close')));
          expect(close.color, foreground);
          expect(close.tooltip, translateUi('关闭歌词外观', language));
          expect(tester.getRect(dialog), const Rect.fromLTWH(0, 0, 507, 320));
          for (final id in [
            'desktop-lyric-font-size',
            'desktop-translation-font-size',
            'desktop-text-opacity',
            'desktop-background-opacity',
            if (mode == 'taskbar') ...[
              'desktop-taskbar-gap',
              'desktop-taskbar-height',
              'desktop-taskbar-minimum-font'
            ],
          ]) {
            final slider = find.byKey(ValueKey(id));
            await tester.ensureVisible(slider);
            await tester.pumpAndSettle();
            final colors = SliderTheme.of(tester.element(slider));
            expect(colors.thumbColor, primary);
            expect(colors.valueIndicatorColor, primary);
            expect(tester.getRect(slider).width, greaterThan(0));
            expect(tester.takeException(), isNull,
                reason: '$mode $language $scale $id');
          }
          final stroke = find.byKey(const ValueKey('desktop-lyric-stroke'));
          await tester.ensureVisible(stroke);
          await tester.pumpAndSettle();
          expect(
              tester.widget<SwitchListTile>(stroke).activeThumbColor, primary);
        }

        // Color edits no longer close the palette; inspect/save remains usable.
        final follow = find.byKey(const ValueKey('desktop-color-follow-theme'));
        await tester.ensureVisible(follow);
        await tester.pumpAndSettle();
        await tester.tap(follow);
        await tester.pump(const Duration(milliseconds: 40));
        await tester.pumpAndSettle();
        expect(dialog, findsOneWidget);
        expect(source.appearance.value.customColor, isNull);
        expect(transport.host.isOpen.value, isTrue);
        final close = find.byKey(const ValueKey('desktop-appearance-close'));
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(transport.host.isOpen.value, isFalse);
        expect(native.operations, isEmpty);
        expect(source.appearance.value.textOpacity, .63);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        transport.dispose();
        source.dispose();
        layout.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        uiLanguage.value = previousLanguage;
      });
    }
  }

  testWidgets('save ACK leaves independent layout errors visible',
      (tester) async {
    tester.view.physicalSize = const Size(507, 320);
    tester.view.devicePixelRatio = 1;
    final source = DesktopLyricController.detached(
        clock: PlaybackClock(automaticTicks: false), sendMessage: (_) {});
    final native = FakeDesktopLyricWindow();
    final layout = DesktopLyricWindowLayout(adapter: native);
    final transport = PaletteTestBridge(source: source, layout: layout);
    unawaited(transport.host.open());
    await tester.pump();
    final client = await transport.connectClient();
    await tester.pumpWidget(DesktopLyricAppearanceApp(client: client));
    layout.lastError.value = 'layout remains retryable';
    source.appearanceSaveError.value = 'save failed';
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('desktop-appearance-save-error')),
        findsOneWidget);
    source.appearanceSaveError.value = null;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('desktop-appearance-save-error')),
        findsNothing);
    expect(find.text('layout remains retryable'), findsOneWidget);
    await client.close();
    await tester.pumpWidget(const SizedBox.shrink());
    transport.dispose();
    source.dispose();
    layout.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    expect(tester.takeException(), isNull);
  });
}
