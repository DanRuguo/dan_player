import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'dart:async';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_lookup_status.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_source_view.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
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
    testWidgets(
        'manual unscored results and no-match status render ${language.name}',
        (tester) async {
      tester.view.physicalSize = const Size(800, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = UiLanguage.zh);
      final boundary = GlobalKey();
      final track = Audio('白い鳥 赤い鳥', '高梨康治', '地獄少女', 0, 180, null, null,
          'fixture.flac', 0, 0, null);
      Widget host(Widget child) => MaterialApp(
          theme: applyAppControlTheme(ThemeData(
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: danFontFamilyFallback,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.orange, brightness: Brightness.dark))),
          home: UiLanguageScope(
              child: RepaintBoundary(
                  key: boundary, child: Scaffold(body: child))));
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

      final missing = Completer<Lyric?>();
      await tester.pumpWidget(host(VerticalLyricContent(
          lyricFuture: missing.future,
          positionStream: const Stream.empty(),
          readPosition: () => 0,
          onSeek: (_) {})));
      missing.completeError(const NoMatchingOnlineLyric());
      await tester.pumpAndSettle();
      expect(find.text(ui(NoMatchingOnlineLyric.message)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture('no-match');
      final profile = CustomMusicSourceProfile.legacyLyric(
          'https://fixture.example/lyrics')!;
      await tester.pumpWidget(host(LyricSourceDialog(
          audio: track,
          currentTrackPath: () => track.path,
          search: (_) async => LyricSearchResponse(candidates: [
                SongSearchResult(ResultSource.qq, track.title, track.artist,
                    track.album, .95,
                    qqSongId: 1),
                SongSearchResult(
                    ResultSource.netease, 'Hidden weak result', '', '', .5,
                    neteaseSongId: '2'),
                SongSearchResult(ResultSource.kugou, track.title, track.artist,
                    track.album, 0,
                    scoreVerified: false,
                    customProfile: profile,
                    customAudio: track),
              ], failures: {}))));
      await tester.pumpAndSettle();
      expect(find.text('Hidden weak result'), findsNothing);
      expect(tester.takeException(), isNull);
      await capture('manual');
    });
  }
}
