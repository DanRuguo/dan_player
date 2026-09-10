import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/statistics_bar_row.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

  testWidgets('bars compare magnitudes using a shared scale and handle zero',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      for (final value in [100.0, 25.0, 0.0])
        StatisticsBarRow(
            label: 'Track',
            detail: 'fixture',
            valueLabel: '$value',
            value: value,
            maximum: 100),
    ])));
    expect(
        tester
            .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
            .map((v) => v.widthFactor),
        [1.0, .25, 0.0]);
    expect(tester.getSize(find.byType(FractionallySizedBox).first).height, 8);
    expect(tester.getSize(find.byType(FractionallySizedBox).first).width,
        greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rank colors distinguish magnitudes and update with the theme',
      (tester) async {
    List<Color> renderedColors() => tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .map((bar) => (bar.child! as ColoredBox).color)
        .toList();
    List<Color>? previous;
    for (final brightness in Brightness.values) {
      for (final seed in [Colors.deepOrange, Colors.teal]) {
        final scheme =
            ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: Column(children: [
              for (final value in [100.0, 75.0, 50.0, 25.0])
                StatisticsBarRow(
                    label: 'Track',
                    detail: 'fixture',
                    valueLabel: '$value',
                    value: value,
                    maximum: 100),
            ])));
        await tester.pumpAndSettle();
        final colors = renderedColors();
        expect(colors.toSet(), hasLength(4));
        expect(colors.first, scheme.primary);
        double contrast(Color color) {
          final foreground = color.computeLuminance();
          final background = scheme.surfaceContainerLow.computeLuminance();
          return foreground > background
              ? (foreground + .05) / (background + .05)
              : (background + .05) / (foreground + .05);
        }

        final contrastLevels = colors.map(contrast).toList();
        for (var i = 1; i < contrastLevels.length; i++) {
          expect(contrastLevels[i - 1], greaterThan(contrastLevels[i]));
        }
        if (previous != null) {
          for (var i = 0; i < colors.length; i++) {
            expect(colors[i], isNot(previous[i]));
          }
        }
        previous = colors;
      }
    }
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets('statistics render ${language.name} narrow=$narrow',
          (tester) async {
        final old = AudioLibrary.instance.audioCollection;
        final revision = AudioLibrary.revision;
        const titles = [
          '晨光与海',
          'Northern Lights',
          '夜の散歩',
          '달빛 산책',
          'Rain on Glass',
          '远方来信'
        ];
        AudioLibrary.instance.audioCollection = [
          for (var i = 0; i < titles.length; i++)
            Audio(
                titles[i],
                'Demo Ensemble',
                'Seasons',
                1,
                180,
                320,
                44100,
                'C:/Demo/Album${i % 3}/$i.${i.isEven ? "flac" : "mp3"}',
                1,
                1,
                'demo',
                language: ['zh', 'en', 'ja', 'ko'][i % 4])
        ];
        AudioLibrary.revision++;
        uiLanguage.value = language;
        addTearDown(() {
          AudioLibrary.instance.audioCollection = old;
          AudioLibrary.revision = revision;
          uiLanguage.value = UiLanguage.zh;
        });
        tester.view.physicalSize = Size(narrow ? 400 : 1120, 880);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final stats = PlaybackStatistics.inMemory(initialData: {
          'version': 1,
          'tracks': [
            for (var i = 0; i < titles.length; i++)
              TrackPlaybackStatistics(
                      id: 'demo-$i',
                      title: titles[i],
                      artist: 'Demo Ensemble',
                      album: 'Seasons',
                      online: false,
                      playCount: 30 - i * 4,
                      completedCount: 20 - i * 2,
                      listenMilliseconds: (3600 - i * 500) * 1000)
                  .toMap()
          ],
          'hours':
              List.generate(24, (i) => i >= 12 ? (24 - i) * 180000 : i * 60000),
        });
        addTearDown(stats.dispose);
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: UiLanguageScope(
                child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: Entry(welcome: false).fromSchemeAndFontFamily(
                  colorScheme: ColorScheme.fromSeed(
                      seedColor: narrow ? Colors.teal : Colors.deepOrange,
                      brightness: narrow ? Brightness.dark : Brightness.light)),
              locale: language.locale,
              supportedLocales: UiLanguage.values.map((v) => v.locale),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(narrow ? 1.4 : 1)),
                  child: child!),
              home: Scaffold(
                  body: StatisticsPage(
                      statistics: stats,
                      scanner: LibraryStatisticsScanner(
                          windowsPaths: true,
                          inspectFile: (path) async =>
                              LocalAudioFileInfo.available((72 -
                                      int.parse(path
                                              .replaceAll('\\', '/')
                                              .split('/')
                                              .last
                                              .split('.')
                                              .first) *
                                          9) *
                                  1024 *
                                  1024),
                          readLyrics: (_) async => null))),
            ))));
        await tester.pumpAndSettle();
        for (final section in ['音乐统计', '24 小时收听分布', '歌曲语言', '占用空间最多', '播放最多']) {
          if (section != '音乐统计') {
            await tester.scrollUntilVisible(find.text(ui(section)), 250,
                scrollable: find.byType(Scrollable).first, maxScrolls: 100);
            await tester.ensureVisible(find.text(ui(section)));
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          const output = String.fromEnvironment('DAN_STATISTICS_RENDER');
          if (output.isNotEmpty) {
            await tester.runAsync(() async {
              final image = await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              final bytes =
                  await image.toByteData(format: drawing.ImageByteFormat.png);
              final file =
                  File('$output/${language.name}-$narrow-$section.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      });
    }
  }
}
