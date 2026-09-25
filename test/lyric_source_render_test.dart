import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/krc.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_source_view.dart';
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
      'Segoe UI Emoji': 'seguiemj.ttf',
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
    testWidgets('default lyric dialog renders ${language.name} wide and narrow',
        (tester) async {
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = UiLanguage.zh);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final audio = Audio(
        '愛立刻有',
        'Bell玲惠 · Artist',
        '星辰與海 · Album',
        0,
        180,
        null,
        null,
        r'C:\Music\愛立刻有.mp3',
        0,
        0,
        null,
      );
      final candidates = [
        SongSearchResult(ResultSource.qq, '愛立刻有', 'Bell玲惠', '星辰與海', 1,
            qqSongId: 1, qqSongMid: 'one'),
        SongSearchResult(ResultSource.netease, '愛立刻有', 'Bell玲惠', '星辰與海', .96,
            neteaseSongId: 'two'),
        SongSearchResult(
            ResultSource.lrclib, '愛立刻有 · Live Session', 'Bell玲惠', '星辰與海', .89,
            lrclibId: 3),
        SongSearchResult(
            ResultSource.kugou, '愛立刻有 · 现场录音', 'Bell玲惠', '星辰與海', .78,
            kugouSongHash: 'four'),
      ];
      final lyrics = <String, Lyric>{
        candidates[0].identity: Qrc([
          QrcLine(const Duration(seconds: 10), const Duration(seconds: 4), [
            QrcWord(
                const Duration(seconds: 10), const Duration(seconds: 2), '跟着你'),
            QrcWord(const Duration(seconds: 12), const Duration(seconds: 2),
                '的步伐和浪漫 🌙'),
          ]),
        ]),
        candidates[1].identity: Krc([
          KrcLine(const Duration(seconds: 10), const Duration(seconds: 4), [
            KrcWord(
                const Duration(seconds: 10), const Duration(seconds: 2), '星光'),
            KrcWord(
                const Duration(seconds: 12), const Duration(seconds: 2), '陪伴你'),
          ]),
        ]),
        candidates[2].identity: Lrc([
          LrcLine(const Duration(seconds: 10), '愛立刻有，唱給你聽', isBlank: false),
        ], LrcSource.web),
        candidates[3].identity: PlainLyric('即使没有时间轴，也保留完整歌词'),
      };
      for (final width in [760.0, 440.0]) {
        tester.view.physicalSize = Size(width, 760);
        final boundary = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: applyAppControlTheme(ThemeData(
                fontFamily: danEmbeddedFontFamily,
                fontFamilyFallback: danFontFamilyFallback,
                colorScheme:
                    ColorScheme.fromSeed(seedColor: const Color(0xffaa6475)))),
            home: UiLanguageScope(
              child: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: FilledButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => LyricSourceDialog(
                          audio: audio,
                          currentTrackPath: () => audio.path,
                          readPosition: () => 11,
                          search: (_) async => LyricSearchResponse(
                            candidates: candidates,
                            failures: const {},
                          ),
                          loadCandidate: (candidate) async =>
                              lyrics[candidate.identity],
                        ),
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('QRC/YRC'), findsOneWidget);
        expect(find.text('KRC'), findsOneWidget);
        expect(find.text('LRC'), findsOneWidget);
        expect(find.text('TXT'), findsOneWidget);
        const output = String.fromEnvironment('DAN_LYRIC_SOURCE_RENDER');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: drawing.ImageByteFormat.png);
            final file = File('$output/${language.name}-${width.toInt()}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    });
  }
}
