import 'dart:async';
import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/statistics/statistics_display_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  const output = String.fromEnvironment('DAN_STATISTICS_SESSION_RENDER');
  if (output.isEmpty) return;
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage();
    try {
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
          (await image.toByteData(format: raster.ImageByteFormat.png))!
              .buffer
              .asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    final koreanFont = File(
        '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/malgun.ttf');
    if (await koreanFont.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(koreanFont
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes))))
          .load();
    }
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
  });

  Audio local(String title) => Audio(title, 'Artist', 'Album', 1, 180, 320,
      44100, 'C:/Synthetic/$title.mp3', 1, 1, title,
      language: 'en');
  Audio online(String id) => Audio.online(
      provider: 'netease',
      id: id,
      title: id,
      artist: 'Artist',
      album: 'Album',
      duration: 180);
  Finder refresh() => find.byKey(const ValueKey('statistics-refresh'));
  Finder plays(String value) => find.descendant(
      of: find.byKey(const ValueKey('statistics-activity-plays')),
      matching: find.text(value));

  Future<GlobalKey<NavigatorState>> mountHost(
      WidgetTester tester, StatisticsDisplayService service, GlobalKey boundary,
      {double width = 1100, double scale = 1}) async {
    tester.view.physicalSize = Size(width, width < 600 ? 1200 : 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: UiLanguageScope(
            child: MaterialApp(
          navigatorKey: navigator,
          debugShowCheckedModeBanner: false,
          theme: Entry(welcome: false).fromSchemeAndFontFamily(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
              body: Center(
                  child: Builder(
                      builder: (context) => FilledButton(
                          key: const ValueKey('open-statistics'),
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => Scaffold(
                                      body: StatisticsPage(
                                          displayService: service)))),
                          child: const Text('Statistics'))))),
        ))));
    await tester.pumpAndSettle();
    return navigator;
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('open-statistics')));
    await tester.pumpAndSettle();
  }

  for (final language in UiLanguage.values) {
    testWidgets(
        'session display $language survives page exit while recording stays live',
        (tester) async {
      final previousLanguage = uiLanguage.value;
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = previousLanguage);
      var now = DateTime(2026, 9, 26, 10);
      var audios = [local('One')];
      var reads = 0;
      var revision = 1;
      final stats = PlaybackStatistics.inMemory(clock: () => now, initialData: {
        'version': 3,
        'playCountTrackingStartedOn': '2026-09-26',
      });
      final service = StatisticsDisplayService(
          statistics: stats,
          clock: () => now,
          readLibrary: () => audios,
          readLibraryRevision: () => revision,
          scanner: LibraryStatisticsScanner(inspectFile: (_) async {
            reads++;
            return const LocalAudioFileInfo.available(1024);
          }));
      addTearDown(stats.dispose);
      addTearDown(service.dispose);
      await service.prewarmOnce();
      final boundary = GlobalKey();
      final navigator = await mountHost(tester, service, boundary,
          width: language == UiLanguage.zh ? 1100 : 400,
          scale: language == UiLanguage.zh ? 1 : 1.6);
      await open(tester);
      expect(reads, 1);
      expect(plays(ui('{0} 次', [0])), findsOneWidget);
      final snapshot = service.snapshot;
      stats.start(online('first'));
      now = now.add(const Duration(seconds: 1));
      stats.tick(online('first'), PlayerState.playing);
      await tester.pumpAndSettle();
      expect(stats.totalPlayCount, 1);
      expect(stats.totalListenMilliseconds, 1000);
      expect(plays(ui('{0} 次', [0])), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      now = DateTime(2026, 9, 27, 11);
      stats.start(online('second'));
      audios = [local('One'), local('Two')];
      revision++;
      await open(tester);
      expect(reads, 1);
      expect(identical(service.snapshot, snapshot), isTrue);
      expect(plays(ui('{0} 次', [0])), findsOneWidget);
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('statistics-activity-range')))
              .data,
          endsWith('2026-09-26'));
      await _capture(tester, boundary, '${language.name}-reentered-stale');
      await tester.tap(refresh());
      await tester.pumpAndSettle();
      expect(reads, 3);
      expect(plays(ui('{0} 次', [2])), findsOneWidget);
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('statistics-activity-range')))
              .data,
          endsWith('2026-09-27'));
      expect(service.snapshot!.library.totalTracks, 2);
      expect(service.snapshot!.capturedAt, now);
      await _capture(tester, boundary, '${language.name}-manual-current');
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await open(tester);
      expect(reads, 3);
      expect(plays(ui('{0} 次', [2])), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a page entering a cold session does not launch filesystem work',
      (tester) async {
    final stats = PlaybackStatistics.inMemory();
    var reads = 0;
    final service = StatisticsDisplayService(
        statistics: stats,
        readLibrary: () => [local('One')],
        scanner: LibraryStatisticsScanner(inspectFile: (_) async {
          reads++;
          return const LocalAudioFileInfo.available(1024);
        }));
    addTearDown(stats.dispose);
    addTearDown(service.dispose);
    await mountHost(tester, service, GlobalKey());
    await open(tester);
    expect(reads, 0);
    expect(service.snapshot, isNull);
    expect(tester.widget<IconButton>(refresh()).onPressed, isNotNull);
    await service.prewarmOnce();
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(service.snapshot!.library.totalTracks, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh finishes into the session after initiating page is gone',
      (tester) async {
    final stats = PlaybackStatistics.inMemory(initialData: {
      'version': 3,
      'playCountTrackingStartedOn': '2026-09-26',
    }, clock: () => DateTime(2026, 9, 26));
    var reads = 0;
    Completer<void>? gate;
    final service = StatisticsDisplayService(
        statistics: stats,
        clock: () => DateTime(2026, 9, 26),
        readLibrary: () => [local('One')],
        scanner: LibraryStatisticsScanner(inspectFile: (_) async {
          reads++;
          if (gate != null) await gate.future;
          return const LocalAudioFileInfo.available(1024);
        }));
    addTearDown(stats.dispose);
    addTearDown(service.dispose);
    await service.prewarmOnce();
    final navigator = await mountHost(tester, service, GlobalKey());
    await open(tester);
    stats.start(online('first'));
    gate = Completer<void>();
    await tester.tap(refresh());
    await tester.pump();
    expect(tester.widget<IconButton>(refresh()).onPressed, isNull);
    expect(plays('0 次'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await open(tester);
    expect(reads, 2);
    expect(service.refreshing, isTrue);
    expect(plays('0 次'), findsOneWidget);
    expect(tester.widget<IconButton>(refresh()).onPressed, isNull);
    gate.complete();
    await tester.pumpAndSettle();
    expect(service.refreshing, isFalse);
    expect(plays('1 次'), findsOneWidget);
    expect(tester.widget<IconButton>(refresh()).onPressed, isNotNull);
    expect(reads, 2);
    expect(tester.takeException(), isNull);
  });
}
