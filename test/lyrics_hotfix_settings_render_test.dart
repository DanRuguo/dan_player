import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/settings_page/other_settings.dart';
import 'package:dan_player/page/settings_page/lyric_cache_batch_settings.dart';
import 'package:dan_player/page/settings_page/custom_music_source_settings.dart';
import 'package:dan_player/lyric/lyric_cache_batch.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
          ..addFont(rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
        .load();
    for (final entry in {
      'Malgun Gothic': 'malgun.ttf',
      'Segoe UI Emoji': 'seguiemj.ttf'
    }.entries) {
      final file = File('C:/Windows/Fonts/${entry.value}');
      if (await file.exists()) {
        await (FontLoader(entry.key)
              ..addFont(
                  Future.value(ByteData.sublistView(await file.readAsBytes()))))
            .load();
      }
    }
  });

  for (final language in UiLanguage.values) {
    testWidgets('folder picker polish ${language.name}', (tester) async {
      tester.view.physicalSize = const Size(900, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = UiLanguage.zh);
      final task = LyricCacheBatch(scan: (_, __) async => [])
        ..folder = 'J:/Music/收藏';
      addTearDown(task.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              theme: applyAppControlTheme(ThemeData(
                  fontFamily: danEmbeddedFontFamily,
                  fontFamilyFallback: danFontFamilyFallback,
                  colorScheme: ColorScheme.fromSeed(
                      seedColor: Colors.orange, brightness: Brightness.dark))),
              home: Scaffold(
                  body: SingleChildScrollView(
                      child:
                          LyricCacheBatchSettings(task: task, folders: const [
                'J:/Music/收藏',
                'J:/download/onedrive/OneDrive - wsd123/FengPuai Files/音乐/Original Soundtracks and Concert Recordings',
                'J:/Music/日本語・한국어・Français'
              ]))))));
      await tester.tap(find.byKey(const ValueKey('lyric-batch-folder')));
      await tester.pumpAndSettle();
      for (final width in [900.0, 420.0]) {
        tester.view.physicalSize = Size(width, 760);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        const output = String.fromEnvironment('DAN_SETTING_RENDER');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: drawing.ImageByteFormat.png);
            final file =
                File('$output/folders-${language.name}-${width.toInt()}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      await tester.tap(find.text('日本語・한국어・Français'));
      await tester.pumpAndSettle();
      expect(find.text('J:/Music/日本語・한국어・Français'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lyric-batch-start')));
      await tester.pumpAndSettle();
      expect(task.folder, 'J:/Music/日本語・한국어・Français');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('lyric-batch-start')), findsNothing);
    });
  }

  for (final language in UiLanguage.values) {
    testWidgets(
        'hotfix settings ${language.name} real-font layout and moving source cards',
        (tester) async {
      tester.view.physicalSize = const Size(920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = UiLanguage.zh);
      final profiles = ValueNotifier(
          CustomMusicSourceProfile.builtInPresets().take(2).toList());
      addTearDown(profiles.dispose);
      final task = LyricCacheBatch(scan: (_, __) async => []);
      addTearDown(task.dispose);
      var saves = 0;
      final boundary = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          theme: applyAppControlTheme(ThemeData(
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: danFontFamilyFallback,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.orange, brightness: Brightness.dark))),
          home: UiLanguageScope(
              child: RepaintBoundary(
                  key: boundary,
                  child: Scaffold(
                      body: SingleChildScrollView(
                          child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const AutomaticOnlineLyricsSwitch(),
                                    const SizedBox(height: 12),
                                    LyricCacheBatchSettings(
                                        task: task,
                                        folders: const ['J:/Music/Imported']),
                                    const SizedBox(height: 12),
                                    CustomMusicSourceSettings(
                                        profiles: profiles,
                                        persist: () async => saves++),
                                  ]))))))));
      await tester.pumpAndSettle();
      final first = profiles.value.first.id, second = profiles.value.last.id;
      final firstCard = find.byKey(ValueKey('custom-source-profile-$first'));
      final before = tester.getRect(firstCard);
      await tester.tap(find.byKey(ValueKey('custom-source-down-$first')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(tester.getRect(firstCard).top, greaterThan(before.top));
      expect(profiles.value.first.id, first);
      await tester.pumpAndSettle();
      expect(profiles.value.first.id, second);
      expect(saves, 1);
      expect(tester.takeException(), isNull);
      Future<void> capture(String stage) async {
        const output = String.fromEnvironment('DAN_SETTING_RENDER');
        if (output.isEmpty) return;
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes =
              await image.toByteData(format: drawing.ImageByteFormat.png);
          final file = File('$output/${language.name}-$stage.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('wide');
      await tester.tap(find.byKey(const ValueKey('lyric-batch-folder')));
      await tester.pumpAndSettle();
      expect(find.text('J:/Music/Imported'), findsOneWidget);
      await tester.tap(find.text('J:/Music/Imported'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('lyric-batch-start')))
              .onPressed,
          isNotNull);
      await tester.tap(find.byKey(const ValueKey('lyric-batch-start')));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(460, 1400);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('narrow');
    });
  }
}
