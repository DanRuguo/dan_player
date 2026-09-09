import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/playback_diagnostics_panel.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/page/audio_detail_page.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';

class _DetailAudio extends CategoryTestAudio {
  _DetailAudio()
      : super('晨光与海 · Northern Lights · 夜の散歩',
            artist: 'Demo Ensemble', album: 'Four Seasons');
  @override
  Future<ImageProvider?> get mediumCover => Future.value(null);
}

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

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'song details and diagnostic groups ${language.name} narrow=$narrow',
          (tester) async {
        tester.view.physicalSize = Size(narrow ? 400 : 1100, 860);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        uiLanguage.value = language;
        addTearDown(() => uiLanguage.value = UiLanguage.zh);
        final audio = _DetailAudio();
        for (final detail in [true, false]) {
          final key = GlobalKey();
          await tester.pumpWidget(RepaintBoundary(
              key: key,
              child: UiLanguageScope(
                  child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: Entry(welcome: false).fromSchemeAndFontFamily(
                    colorScheme: ColorScheme.fromSeed(
                        seedColor: Colors.teal,
                        brightness:
                            narrow ? Brightness.dark : Brightness.light)),
                locale: language.locale,
                supportedLocales: UiLanguage.values.map((v) => v.locale),
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(narrow ? 1.4 : 1)),
                    child: child!),
                home: Scaffold(
                  body: detail
                      ? AudioDetailPage(audio: audio)
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(ui('播放详情'),
                                    style: const TextStyle(fontSize: 24)),
                                const SizedBox(height: 16),
                                PlaybackDiagnosticsContent(snapshot: const {
                                  'phase': 'paused',
                                  'output': {
                                    'session': 4,
                                    'requestedOutput': 'exclusive',
                                    'streamOutput': 'exclusive',
                                    'source': {
                                      'sampleRate': 44100,
                                      'channels': 2,
                                      'sampleFormat': 'Float32',
                                      'originalBits': 16
                                    },
                                    'deviceFormat': {
                                      'sampleRate': 48000,
                                      'channels': 2,
                                      'sampleFormat': 'Float32',
                                      'exclusive': true
                                    },
                                    'deviceNumber': 1,
                                    'replayGainRequested': 'album',
                                    'replayGainApplied': 'album',
                                    'replayGainEffectiveDb': -3.4,
                                    'effectiveDspMultiplier': .6761,
                                    'eqRequested': true,
                                    'eqAppliedBands': 10,
                                    'eqSettingsApplied': true,
                                    'playbackRate': 1.0,
                                  }
                                }, onRefresh: () {}, onExport: (_) async {}),
                              ])),
                ),
              ))));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (!detail && !narrow) {
            final outputRect = tester.getRect(
                find.byKey(ValueKey('diagnostic-group-${ui('音频输出')}')));
            final processingRect = tester.getRect(
                find.byKey(ValueKey('diagnostic-group-${ui('音频处理')}')));
            expect(outputRect.top, processingRect.top);
            expect(outputRect.bottom, processingRect.bottom);
          }

          const output = String.fromEnvironment('DAN_DETAIL_RENDER');
          if (output.isNotEmpty) {
            await tester.runAsync(() async {
              final image = await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              final data =
                  await image.toByteData(format: drawing.ImageByteFormat.png);
              final file = File(
                  '$output/${detail ? "song" : "diagnostics"}-${language.name}-$narrow.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      });
    }
  }
}
