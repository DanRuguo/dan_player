import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/src/bass/bass_player.dart' show PlayerState;
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _audio(String path, {String language = 'en'}) => Audio(
      'Fixture track',
      'Artist',
      'Album',
      1,
      180,
      320,
      44100,
      path,
      1,
      1,
      'test',
      language: language,
    );

List<Audio> _libraryFixture() => [
      _audio(r'C:\Music\同名文件夹\first.flac', language: 'zh'),
      _audio(r'D:\Music\同名文件夹\second.mp3', language: 'ja'),
      for (var index = 0; index < 7; index++)
        _audio(
            'E:\\Music\\Folder$index\\a moderately long directory name\\song.$index'),
      Audio.online(
          provider: 'qq',
          id: 'remote',
          title: 'Remote',
          artist: 'Artist',
          album: 'Album',
          duration: 180,
          bitrate: 320),
    ];

Widget _app({
  required PlaybackStatistics statistics,
  required LibraryStatisticsScanner scanner,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) =>
    MaterialApp(
      theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: brightness,
          )),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(
          body: StatisticsPage(statistics: statistics, scanner: scanner)),
    );

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    400,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 80,
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Finder _card(String name) => find.byKey(ValueKey('statistics-$name-card'));
Finder _chart(String name) => find.byKey(ValueKey('statistics-chart-$name'));

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
    for (final width in [320.0, 800.0, 1440.0]) {
      for (final textScale in [1.0, 2.0]) {
        testWidgets(
            'folder charts fit $brightness at $width, ${textScale}x text',
            (tester) async {
          _size(tester, Size(width, 1000));
          AudioLibrary.instance.audioCollection = _libraryFixture();
          final statistics = PlaybackStatistics.inMemory();
          addTearDown(statistics.dispose);
          var inspections = 0;
          final scanner = LibraryStatisticsScanner(
            windowsPaths: true,
            inspectFile: (_) async {
              inspections++;
              return const LocalAudioFileInfo.available(1024);
            },
            readLyrics: (_) async => null,
          );
          await tester.pumpWidget(_app(
            statistics: statistics,
            scanner: scanner,
            brightness: brightness,
            textScale: textScale,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await _show(tester,
              find.byKey(const ValueKey('statistics-local-folder-metric')));
          expect(find.text('本地文件夹'), findsOneWidget);
          final folderMetric =
              find.byKey(const ValueKey('statistics-local-folder-metric'));
          expect(find.descendant(of: folderMetric, matching: find.text('9')),
              findsOneWidget);
          expect(
              find.descendant(
                  of: folderMetric, matching: find.text('按完整路径区分直接父目录，不含联网曲目')),
              findsOneWidget);

          await _show(tester, _card('language'));
          final chartSizes = [
            for (final name in ['language', 'format', 'folders'])
              tester.getSize(_chart(name))
          ];
          expect(chartSizes[1], chartSizes.first);
          expect(chartSizes[2], chartSizes.first);
          if (width == 1440 && textScale == 1) {
            final heights = [
              for (final name in ['language', 'format', 'folder'])
                tester.getSize(_card(name)).height
            ];
            expect(heights[1], closeTo(heights.first, 0.01));
            expect(heights[2], closeTo(heights.first, 0.01));
            expect(tester.getTopLeft(_card('folder')).dy,
                closeTo(tester.getTopLeft(_card('language')).dy, 0.01));
          }
          await _show(
              tester, find.byKey(const ValueKey('folder-metric-count')));
          expect(find.byTooltip(r'C:\Music\同名文件夹'), findsOneWidget);
          expect(find.byTooltip(r'D:\Music\同名文件夹'), findsOneWidget);
          expect(find.text('其他文件夹（2 个）'), findsOneWidget);
          await _show(
              tester, find.byKey(const ValueKey('statistics-folder-scope')));
          final scopeRect = tester
              .getRect(find.byKey(const ValueKey('statistics-folder-scope')));
          final cardRect = tester.getRect(_card('folder'));
          expect(scopeRect.bottom, lessThanOrEqualTo(cardRect.bottom));
          expect(scopeRect.left, greaterThanOrEqualTo(cardRect.left));
          expect(scopeRect.right, lessThanOrEqualTo(cardRect.right));
          expect(tester.takeException(), isNull);
          expect(inspections, 9);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets(
      'metric changes keep counts and byte labels and do not rescan on playback ticks',
      (tester) async {
    _size(tester, const Size(1440, 1000));
    final first = _audio(r'D:\Small\one.mp3');
    AudioLibrary.instance.audioCollection = [
      first,
      _audio(r'D:\Small\two.mp3'),
      _audio(r'D:\Large\three.flac'),
    ];
    var clock = DateTime(2026, 1, 2, 12);
    final statistics = PlaybackStatistics.inMemory(clock: () => clock);
    addTearDown(statistics.dispose);
    var inspections = 0;
    final scanner = LibraryStatisticsScanner(
      windowsPaths: true,
      inspectFile: (path) async {
        inspections++;
        return LocalAudioFileInfo.available(path.contains('Large') ? 300 : 50);
      },
    );
    await tester.pumpWidget(_app(statistics: statistics, scanner: scanner));
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(const ValueKey('folder-metric-bytes')));
    expect(find.descendant(of: _card('folder'), matching: find.text('66.7%')),
        findsOneWidget);
    expect(find.descendant(of: _card('folder'), matching: find.text('33.3%')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('folder-metric-bytes')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _card('folder'), matching: find.text('75.0%')),
        findsOneWidget);
    expect(find.descendant(of: _card('folder'), matching: find.text('25.0%')),
        findsOneWidget);
    expect(find.descendant(of: _card('folder'), matching: find.text('300 B')),
        findsOneWidget);
    expect(
        find.descendant(
            of: _card('folder'), matching: find.text('2 首 · 已核实 2 首')),
        findsOneWidget);
    expect(inspections, 3);

    statistics.start(first);
    for (var tick = 0; tick < 12; tick++) {
      clock = clock.add(const Duration(seconds: 1));
      statistics.tick(first, PlayerState.playing);
      await tester.pump(const Duration(seconds: 1));
    }
    expect(inspections, 3);
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('folder-metric-bytes')))
            .selected,
        isTrue);
    // Responsive column/row changes must not reset the user's metric choice.
    tester.view.physicalSize = const Size(800, 1000);
    await tester.pumpWidget(
        _app(statistics: statistics, scanner: scanner, textScale: 2));
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(const ValueKey('folder-metric-bytes')));
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('folder-metric-bytes')))
            .selected,
        isTrue);
    expect(inspections, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'missing and denied songs are included in quantity but absent from space',
      (tester) async {
    _size(tester, const Size(1440, 1000));
    AudioLibrary.instance.audioCollection = [
      _audio(r'D:\Available\zero.mp3'),
      _audio(r'D:\Missing\gone.mp3'),
      _audio(r'D:\Denied\private.mp3'),
    ];
    final statistics = PlaybackStatistics.inMemory();
    addTearDown(statistics.dispose);
    final scanner = LibraryStatisticsScanner(
        windowsPaths: true,
        inspectFile: (path) async {
          if (path.contains('Missing')) {
            return const LocalAudioFileInfo.missing();
          }
          if (path.contains('Denied')) {
            return const LocalAudioFileInfo.inaccessible();
          }
          return const LocalAudioFileInfo.available(0);
        });
    await tester.pumpWidget(_app(statistics: statistics, scanner: scanner));
    await tester.pumpAndSettle();
    await _show(tester, find.byKey(const ValueKey('folder-metric-bytes')));
    expect(find.descendant(of: _card('folder'), matching: find.text('33.3%')),
        findsNWidgets(3));
    expect(find.textContaining('缺失 1 首，无权限/不可读 1 首未计入空间。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('folder-metric-bytes')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _card('folder'), matching: find.text('0.0%')),
        findsNWidgets(3));
    expect(find.text('暂无可核实字节'), findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty distribution cards are equal-height in a wide row',
      (tester) async {
    _size(tester, const Size(1440, 1000));
    final statistics = PlaybackStatistics.inMemory();
    addTearDown(statistics.dispose);
    final scanner = LibraryStatisticsScanner(
        inspectFile: (_) async => throw StateError('empty library'));
    await tester.pumpWidget(_app(statistics: statistics, scanner: scanner));
    await tester.pumpAndSettle();
    await _show(tester, _card('language'));
    final heights = [
      for (final name in ['language', 'format', 'folder'])
        tester.getSize(_card(name)).height
    ];
    expect(heights[1], closeTo(heights.first, 0.01));
    expect(heights[2], closeTo(heights.first, 0.01));
    expect(find.text('尚无本地文件夹'), findsOneWidget);
    expect(find.byTooltip(r'D:\Music'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
