import 'dart:ui' show SemanticsAction;

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PlaybackStatistics _recordedStatistics() {
  final hours = List<int>.filled(24, 0)
    ..[14] = const Duration(minutes: 30).inMilliseconds
    ..[20] = const Duration(hours: 1).inMilliseconds
    ..[23] = const Duration(hours: 1).inMilliseconds;
  return PlaybackStatistics.inMemory(initialData: {
    'version': 1,
    'tracks': [
      TrackPlaybackStatistics(
        id: 'online:netease:history',
        title: 'History',
        artist: 'Artist',
        album: 'Album',
        online: true,
        playCount: 42,
        completedCount: 8,
        skippedCount: 3,
        listenMilliseconds: hours.fold(0, (sum, value) => sum + value),
      ).toMap(),
    ],
    'days': {'2025-03-01': hours.fold(0, (sum, value) => sum + value)},
    'hours': hours,
  });
}

Widget _app({
  required PlaybackStatistics statistics,
  required ColorScheme scheme,
  double textScale = 1,
  LibraryStatisticsScanner? scanner,
}) =>
    MaterialApp(
      theme: ThemeData(useMaterial3: true, colorScheme: scheme),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: StatisticsPage(statistics: statistics, scanner: scanner),
      ),
    );

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _showChart(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('listening-hours-scroll')),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  expect(tester.takeException(), isNull);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 3),
  );
}

void main() {
  late List<Audio> previousLibrary;
  late int previousRevision;

  setUp(() {
    previousLibrary = AudioLibrary.instance.audioCollection;
    previousRevision = AudioLibrary.revision;
    AudioLibrary.instance.audioCollection = [];
    AudioLibrary.revision++;
  });

  tearDown(() {
    AudioLibrary.instance.audioCollection = previousLibrary;
    AudioLibrary.revision = previousRevision;
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 800.0, 1400.0]) {
      for (final textScale in [1.0, 2.0]) {
        testWidgets(
            'listening behavior fits $brightness at $width and ${textScale}x text',
            (tester) async {
          _size(tester, Size(width, 1000));
          final statistics = _recordedStatistics();
          addTearDown(statistics.dispose);
          await tester.pumpWidget(_app(
            statistics: statistics,
            scheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: brightness,
            ),
            textScale: textScale,
          ));
          expect(tester.takeException(), isNull);
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 3),
          );
          expect(find.text('听歌行为'), findsOneWidget);
          expect(find.text('全部记录'), findsOneWidget);
          expect(find.text('听歌时长'), findsOneWidget);
          expect(find.text('播放次数'), findsOneWidget);
          expect(find.text('最活跃时段'), findsOneWidget);
          expect(find.text('42 次'), findsWidgets);
          expect(find.text('近7天'), findsNothing);
          expect(find.text('近30天'), findsNothing);
          expect(tester.takeException(), isNull);

          await _showChart(tester);
          for (var hour = 0; hour < 24; hour++) {
            expect(
                find.byKey(ValueKey('listening-hour-$hour')), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets('empty history has no fabricated peak or positive-height bars',
      (tester) async {
    _size(tester, const Size(1400, 1000));
    final statistics = PlaybackStatistics.inMemory();
    addTearDown(statistics.dispose);
    await tester.pumpWidget(_app(
      statistics: statistics,
      scheme: ColorScheme.fromSeed(seedColor: Colors.blue),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listening-empty')), findsOneWidget);
    expect(find.text('播放后显示高峰时段'), findsOneWidget);
    for (var hour = 0; hour < 24; hour++) {
      expect(tester.getSize(find.byKey(ValueKey('listening-bar-$hour'))).height,
          0);
    }
    expect(find.textContaining(' · 最高时段'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'all tied peaks use the current theme and bar ratios are accurate',
      (tester) async {
    _size(tester, const Size(1400, 1000));
    final statistics = _recordedStatistics();
    addTearDown(statistics.dispose);
    final lightScheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    await tester.pumpWidget(_app(statistics: statistics, scheme: lightScheme));
    await tester.pumpAndSettle();

    Color barColor(int hour) => (tester
            .widget<DecoratedBox>(find.byKey(ValueKey('listening-bar-$hour')))
            .decoration as BoxDecoration)
        .color!;
    expect(barColor(20).toARGB32(), lightScheme.primary.toARGB32());
    expect(barColor(23).toARGB32(), lightScheme.primary.toARGB32());
    expect(barColor(14).a, closeTo(0.45, 0.001));
    expect(
        tester.getSize(find.byKey(const ValueKey('listening-bar-20'))).height,
        168);
    expect(
        tester.getSize(find.byKey(const ValueKey('listening-bar-14'))).height,
        84);
    expect(tester.getSize(find.byKey(const ValueKey('listening-bar-0'))).height,
        0);
    expect(find.textContaining('2 个并列时段'), findsOneWidget);

    final darkScheme = ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: Brightness.dark,
    );
    await tester.pumpWidget(_app(statistics: statistics, scheme: darkScheme));
    await tester.pumpAndSettle();
    expect(barColor(20).toARGB32(), darkScheme.primary.toARGB32());
    expect(barColor(23).toARGB32(), darkScheme.primary.toARGB32());
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap selects an hour and long press exposes its exact duration',
      (tester) async {
    _size(tester, const Size(1400, 1000));
    final statistics = _recordedStatistics();
    addTearDown(statistics.dispose);
    await tester.pumpWidget(_app(
      statistics: statistics,
      scheme: ColorScheme.fromSeed(seedColor: Colors.blue),
    ));
    await tester.pumpAndSettle();
    final hour = find.byKey(const ValueKey('listening-hour-14'));
    await tester.tap(hour);
    await tester.pumpAndSettle();
    final selection = find.byKey(const ValueKey('listening-hour-selection'));
    expect(find.descendant(of: selection, matching: find.text('14:00–15:00')),
        findsOneWidget);
    expect(find.descendant(of: selection, matching: find.text('30 分 0 秒')),
        findsOneWidget);
    await tester.longPress(hour);
    await tester.pumpAndSettle();
    expect(find.text('14:00–15:00 · 30 分 0 秒'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hour controls wrap around and reveal the selected narrow bar',
      (tester) async {
    _size(tester, const Size(320, 1000));
    final statistics = PlaybackStatistics.inMemory();
    addTearDown(statistics.dispose);
    await tester.pumpWidget(_app(
      statistics: statistics,
      scheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      textScale: 2,
    ));
    await tester.pumpAndSettle();
    await _showChart(tester);
    await tester.ensureVisible(find.byTooltip('前一个时段'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('前一个时段'));
    await tester.pumpAndSettle();
    final selection = find.byKey(const ValueKey('listening-hour-selection'));
    expect(find.descendant(of: selection, matching: find.text('23:00–24:00')),
        findsOneWidget);
    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('listening-hours-scroll')),
    );
    expect(scroll.controller!.offset, greaterThan(0));
    await tester.tap(find.byTooltip('后一个时段'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: selection, matching: find.text('00:00–01:00')),
        findsOneWidget);
    expect(scroll.controller!.offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every bar exposes an actionable screen-reader time and duration',
      (tester) async {
    _size(tester, const Size(1400, 1100));
    final statistics = _recordedStatistics();
    addTearDown(statistics.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_app(
        statistics: statistics,
        scheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ));
      await tester.pumpAndSettle();
      final node = tester.getSemantics(
        find.byKey(const ValueKey('listening-hour-20')),
      );
      expect(node.label, contains('20:00–21:00'));
      expect(node.label, contains('1 小时 0 分 0 秒'));
      expect(node.label, contains('最高时段'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('live playback updates preserve the cached library scan',
      (tester) async {
    _size(tester, const Size(1400, 1100));
    final audio = Audio('Local', 'Artist', 'Album', 1, 180, 320, 44100,
        r'D:\Music\statistics-cache.mp3', 1, 1, 'statistics-cache',
        language: 'en');
    AudioLibrary.instance.audioCollection = [audio];
    var now = DateTime(2026, 8, 27, 14);
    final statistics = PlaybackStatistics.inMemory(clock: () => now);
    addTearDown(statistics.dispose);
    var reads = 0;
    final scanner = LibraryStatisticsScanner(inspectFile: (_) async {
      reads++;
      return const LocalAudioFileInfo.available(2048);
    });
    await tester.pumpWidget(_app(
      statistics: statistics,
      scheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      scanner: scanner,
    ));
    await tester.pumpAndSettle();
    expect(reads, 1);
    statistics.start(audio);
    for (var second = 0; second < 5; second++) {
      now = now.add(const Duration(seconds: 1));
      statistics.tick(audio, PlayerState.playing);
    }
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.text('5 秒'), findsWidgets);
    await tester.tap(find.byTooltip('重新核实文件大小与语言'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(tester.takeException(), isNull);
  });
}
