import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/data/cache_backup_service.dart';
import 'package:dan_player/page/settings_page/backup_selection_dialog.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
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
  const contents = BackupContents(components: {
    ...BackupComponent.values
  }, musicFolders: [
    BackupMusicFolder(
        id: 'f01',
        name: r'J:\Music\日本語のアルバムと長いフォルダー名 — 中文音乐收藏',
        songCount: 645,
        bytes: 5200000000),
    BackupMusicFolder(
        id: 'f02',
        name: r'C:\Users\Listener\Music\Soundtracks',
        songCount: 32,
        bytes: 860000000),
  ]);
  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets('${language.code} backup and restore dialogs narrow=$narrow',
          (tester) async {
        final previous = uiLanguage.value;
        uiLanguage.value = language;
        addTearDown(() => uiLanguage.value = previous);
        tester.view.physicalSize =
            Size(narrow ? 440 : 1120, narrow ? 900 : 1050);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        final theme = applyAppControlTheme(ThemeData(
            fontFamily: danEmbeddedFontFamily,
            fontFamilyFallback: const ['Malgun Gothic'],
            colorScheme: ColorScheme.fromSeed(
                seedColor: narrow ? Colors.teal : Colors.pink,
                brightness: narrow ? Brightness.light : Brightness.dark)));
        Future<void> show(bool restoring) async {
          await tester.pumpWidget(UiLanguageScope(
              child: MaterialApp(
                  theme: theme,
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(narrow ? 1.65 : 1)),
                      child: child!),
                  home: RepaintBoundary(
                      key: boundary,
                      child: Scaffold(
                          body: BackupSelectionDialog(
                              key: ValueKey(restoring),
                              contents: contents,
                              firstUse: restoring,
                              restoring: restoring))))));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        Future<void> capture(String suffix) async {
          const destination = String.fromEnvironment('DAN_BACKUP_RENDER');
          if (destination.isEmpty) return;
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
            await Directory(destination).create(recursive: true);
            await File('$destination/${language.code}-$narrow-$suffix.png')
                .writeAsBytes((await image.toByteData(
                        format: drawing.ImageByteFormat.png))!
                    .buffer
                    .asUint8List());
            image.dispose();
          });
        }

        await show(false);
        await capture('export');
        await tester.ensureVisible(find.text(ui('密码加密')));
        await tester.tap(find.text(ui('密码加密')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
            find.byKey(const ValueKey('backup-password-confirm')));
        await tester.enterText(
            find.byKey(const ValueKey('backup-password')), ' 密码 🔑 & # ');
        await tester.enterText(
            find.byKey(const ValueKey('backup-password-confirm')),
            ' 密码 🔑 & # ');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture('password');
        await show(true);
        await capture('restore-overview');
        await tester.ensureVisible(
            find.byKey(const ValueKey('backup-component-settings')));
        await tester
            .tap(find.byKey(const ValueKey('backup-component-settings')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture('restore');
      });
    }
  }
}
