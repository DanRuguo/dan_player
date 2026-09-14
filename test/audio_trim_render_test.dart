import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/audio_trim_dialog.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'audio_trim_dialog_test.dart' show FakeTrimPreview, trimTestInfo;
import 'support/music_category_fixtures.dart';

void main() {
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf')
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
    for (final narrow in [false, true]) {
      testWidgets('trim form ${language.code} narrow=$narrow', (tester) async {
        final previous = uiLanguage.value;
        uiLanguage.value = language;
        addTearDown(() => uiLanguage.value = previous);
        tester.view.physicalSize =
            Size(narrow ? 360 : 1000, narrow ? 950 : 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        final preview = FakeTrimPreview();
        await tester.pumpWidget(UiLanguageScope(
            child: MaterialApp(
          theme: applyAppControlTheme(ThemeData(
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: const ['Malgun Gothic'],
              colorScheme: ColorScheme.fromSeed(
                  seedColor: narrow ? Colors.indigo : Colors.teal,
                  brightness: narrow ? Brightness.dark : Brightness.light))),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(narrow ? 1.8 : 1)),
              child: child!),
          home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                  body: AudioTrimDialog(
                audio: CategoryTestAudio('Song of the Wind · 風の歌',
                    artist: 'Artist / アーティスト',
                    album: 'A long album name · 音楽のアルバム',
                    path: 'J:/Music/風の歌.mp3'),
                inspect: (_) async => trimTestInfo,
                preview: preview,
                save: (_, request, {onProgress, cancellation}) async =>
                    AudioTrimResult(
                        path: request.destinationPath, duration: 123),
              ))),
        )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.binding.hasScheduledFrame, isFalse);
        Future<void> capture(String part) async {
          const output = String.fromEnvironment('DAN_TRIM_RENDER');
          if (output.isEmpty) return;
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
            await Directory(output).create(recursive: true);
            await File(
                    '$output/${language.code}-${narrow ? 'narrow' : 'wide'}-$part.png')
                .writeAsBytes((await image.toByteData(
                        format: drawing.ImageByteFormat.png))!
                    .buffer
                    .asUint8List());
            image.dispose();
          });
        }

        await capture('selection');
        await tester
            .ensureVisible(find.byKey(const ValueKey('trim-edit-metadata')));
        await tester.tap(find.byKey(const ValueKey('trim-edit-metadata')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('trim-album')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture('save');
        await tester.pumpWidget(const SizedBox.shrink());
        preview.dispose();
      });
    }
  }
}
