import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
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

List<Audio> _fixture(int categories) {
  const extensions = [
    'mp3',
    'flac',
    'wav',
    'ogg',
    'opus',
    'm4a',
    'aac',
    'wma',
    'aif'
  ];
  const languages = ['en', 'ja', 'zh', 'ko', 'fr'];
  final count = categories == 1 ? 3 : (categories == 2 ? 4 : 11);
  return [
    for (var i = 0; i < count; i++)
      Audio(
        'Sample $i',
        'Ensemble',
        'Seasons',
        1,
        180,
        320,
        44100,
        'C:/Music/Collection ${categories == 1 ? 0 : i % categories}/'
            'A long album folder with English 日本語 한국어 中文/'
            'Original recording and alternate performances/$i.${extensions[categories == 1 ? 0 : (categories == 2 ? (i == 3 ? 1 : 0) : i % extensions.length)]}',
        1,
        1,
        'test',
        language: languages[i %
            (categories == 1 ? 1 : (categories == 2 ? 2 : languages.length))],
      ),
  ];
}

Widget _host(Widget child, UiLanguage language, Brightness brightness,
        double scale) =>
    UiLanguageScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: language.locale,
        supportedLocales: UiLanguage.values.map((v) => v.locale),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: Entry(welcome: false).fromSchemeAndFontFamily(
          colorScheme: ColorScheme.fromSeed(
            seedColor: brightness == Brightness.light
                ? Colors.deepOrange
                : Colors.teal,
            brightness: brightness,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Scaffold(body: child),
      ),
    );

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

  // Capture the actual card widgets constructed by StatisticsPage, using the
  // same width and snapshot. The isolated repaint boundary includes the whole
  // card even when a large-text card needs vertical scrolling in the player.
  for (final language in UiLanguage.values) {
    for (final brightness in Brightness.values) {
      for (final scenario in [
        (320.0, 2.0, 9),
        (400.0, 1.0, 2),
        (1120.0, 1.0, 9),
        (1120.0, 1.0, 1),
        (1120.0, 2.0, 2),
      ]) {
        final (width, scale, categories) = scenario;
        final name =
            '${language.name}-${brightness.name}-${width.toInt()}-${scale}x-$categories';
        testWidgets('distribution comparisons $name', (tester) async {
          final previous = AudioLibrary.instance.audioCollection;
          final revision = AudioLibrary.revision;
          AudioLibrary.instance.audioCollection = _fixture(categories);
          AudioLibrary.revision++;
          uiLanguage.value = language;
          addTearDown(() {
            AudioLibrary.instance.audioCollection = previous;
            AudioLibrary.revision = revision;
            uiLanguage.value = UiLanguage.zh;
          });
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final statistics = PlaybackStatistics.inMemory();
          addTearDown(statistics.dispose);
          final scanner = LibraryStatisticsScanner(
            windowsPaths: true,
            readLyrics: (_) async => null,
            inspectFile: (path) async => LocalAudioFileInfo.available(
              path.endsWith('.flac') ? 60 * 1024 * 1024 : 4 * 1024 * 1024,
            ),
          );
          await tester.pumpWidget(_host(
            StatisticsPage(statistics: statistics, scanner: scanner),
            language,
            brightness,
            scale,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('statistics-language-card')),
            400,
            scrollable: find.byType(Scrollable).first,
            maxScrolls: 100,
          );
          await tester.pumpAndSettle();
          final cards = <String, Widget>{
            for (final id in ['language', 'format', 'folder'])
              id: tester.widget(find.byKey(ValueKey('statistics-$id-card'))),
          };
          for (final entry in cards.entries) {
            final key = GlobalKey();
            await tester.pumpWidget(_host(
              SingleChildScrollView(
                child: RepaintBoundary(
                    key: key,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: entry.value,
                    )),
              ),
              language,
              brightness,
              scale,
            ));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull,
                reason: '${entry.key} $name');
            final id = entry.key == 'folder' ? 'folders' : entry.key;
            final legend = find.byKey(ValueKey('statistics-legend-$id'));
            final chart = find.byKey(ValueKey('statistics-chart-$id'));
            final legendRect = tester.getRect(legend);
            final cardRect = tester
                .getRect(find.byKey(ValueKey('statistics-${entry.key}-card')));
            expect(legendRect.right, closeTo(cardRect.right - 18, .1));
            expect(legendRect.left, greaterThanOrEqualTo(cardRect.left + 18));
            final bars = find.descendant(
                of: legend, matching: find.byType(FractionallySizedBox));
            expect(bars, findsWidgets);
            for (final bar in tester.widgetList<FractionallySizedBox>(bars)) {
              expect(bar.widthFactor, inInclusiveRange(0.0, 1.0));
            }
            if (width == 1120 && scale == 1) {
              expect(legendRect.left, greaterThan(tester.getRect(chart).right));
              expect(legendRect.width, greaterThan(700));
            }
            if (categories == 1) {
              expect(tester.getSize(chart).width, 132);
              expect(find.descendant(of: legend, matching: find.text('100.0%')),
                  entry.key == 'format' ? findsNWidgets(2) : findsOneWidget);
            }
            if (entry.key == 'format' && categories == 2) {
              final fractions = tester
                  .widgetList<FractionallySizedBox>(bars)
                  .map((bar) => bar.widthFactor!)
                  .toList();
              // FLAC is 1/4 of the source files but 5/6 of their bytes.
              expect(fractions[0], closeTo(5 / 6, .0001));
              expect(fractions[1], .25);
              expect(fractions[2], closeTo(1 / 6, .0001));
              expect(fractions[3], .75);
            }
            const output = String.fromEnvironment('DAN_DISTRIBUTION_RENDER');
            if (output.isNotEmpty) {
              await tester.runAsync(() async {
                final image = await (key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
                final bytes =
                    await image.toByteData(format: drawing.ImageByteFormat.png);
                final file = File('$output/$name-${entry.key}.png');
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
}
