import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/settings_page/desktop_integration_settings.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
  });

  for (final language in UiLanguage.values) {
    for (final brightness in Brightness.values) {
      testWidgets('taskbar settings ${language.code} ${brightness.name}',
          (tester) async {
        final rig = DesktopTestRig();
        addTearDown(rig.dispose);
        final previousLanguage = uiLanguage.value;
        uiLanguage.value = language;
        addTearDown(() => uiLanguage.value = previousLanguage);
        tester.view.physicalSize = const Size(420, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        await tester.pumpWidget(UiLanguageScope(
            child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: applyAppControlTheme(ThemeData(
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: danFontFamilyFallback,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.orange, brightness: brightness))),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.2)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: RepaintBoundary(
                          key: boundary,
                          child: DesktopIntegrationSettings(
                            preferences: rig.preferences,
                            integration: rig.integration,
                            persist: () async {},
                          ))))),
        )));
        await tester.pumpAndSettle();
        const title = '任务栏播放进度';
        const detail = '在任务栏图标上显示播放与暂停进度。关闭后仍显示下载、处理任务的进度及加载状态。';
        for (final text in [title, detail]) {
          expect(find.text(translateUi(text, language)), findsOneWidget);
          if (language != UiLanguage.zh) {
            expect(translateUi(text, language), isNot(text));
          }
        }
        final progress =
            find.byKey(const ValueKey('taskbar-playback-progress-setting'));
        await tester.ensureVisible(progress);
        await tester.pumpAndSettle();
        final switchTile = tester.widget<SwitchListTile>(progress);
        expect(switchTile.value, isTrue);
        expect(switchTile.visualDensity, VisualDensity.standard);
        expect(tester.takeException(), isNull);
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(rig.native.calls, isEmpty);

        const output = String.fromEnvironment('DAN_TASKBAR_SETTINGS_RENDER');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: drawing.ImageByteFormat.png);
            await Directory(output).create(recursive: true);
            await File(
                    '$output/settings-${language.code}-${brightness.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
