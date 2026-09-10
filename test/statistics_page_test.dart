import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('idle local-library changes refresh once per frame',
      (tester) async {
    final previousNotification = AudioLibrary.changes.value;
    addTearDown(() => AudioLibrary.changes.value = previousNotification);
    final stats = PlaybackStatistics.inMemory();
    addTearDown(stats.dispose);
    Audio audio(String id) => Audio(id, 'Artist', 'Album', 1, 180, 320, 44100,
        'C:/Synthetic/$id.mp3', 1, 1, id);
    AudioLibrary.instance.audioCollection = [audio('one')];
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatisticsPage(
                statistics: stats,
                scanner: LibraryStatisticsScanner(
                    readLyrics: (_) async => null,
                    inspectFile: (_) async {
                      reads++;
                      return const LocalAudioFileInfo.available(1024);
                    })))));
    await tester.pumpAndSettle();
    expect(reads, 1);
    // Several notifications can describe one index update. No playback or
    // parent rebuild should be required, and only the latest list is scanned.
    for (var i = 0; i < 5; i++) {
      AudioLibrary.instance.audioCollection = [audio('one'), audio('two')];
      AudioLibrary.revision++;
      AudioLibrary.changes.value = AudioLibrary.revision;
    }
    await tester.pumpAndSettle();
    expect(reads, 3);
    await tester.pump(const Duration(seconds: 6));
    expect(reads, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    AudioLibrary.revision++;
    AudioLibrary.changes.value = AudioLibrary.revision;
    await tester.pumpAndSettle();
    expect(reads, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty statistics and all language categories fit a narrow window',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: StatisticsPage()),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('歌曲语言'),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('英文'), findsOneWidget);
    expect(find.text('日文'), findsOneWidget);
    expect(find.text('韩文'), findsOneWidget);
    expect(find.text('其他语言'), findsOneWidget);
    expect(find.text('未识别'), findsOneWidget);
    expect(find.text('0.0%'), findsNWidgets(6));
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('本地空间 · 文件格式'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无可核实文件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'ordinary rebuilds reuse a snapshot; manual refresh rereads files',
      (tester) async {
    final audio = Audio('Test', 'Artist', 'Album', 1, 180, 320, 44100,
        r'D:\Music\test.mp3', 1, 1, 'test',
        language: 'en');
    AudioLibrary.instance.audioCollection = [audio];
    var reads = 0;
    final scanner = LibraryStatisticsScanner(inspectFile: (_) async {
      reads++;
      return const LocalAudioFileInfo.available(1024);
    });
    Widget app() => MaterialApp(
          home: Scaffold(body: StatisticsPage(scanner: scanner)),
        );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(reads, 1);

    for (var index = 0; index < 4; index++) {
      await tester.pumpWidget(app());
      await tester.pump(const Duration(seconds: 5));
    }
    expect(reads, 1);
    await tester.tap(find.byTooltip('重新核实文件大小与语言'));
    await tester.pumpAndSettle();
    expect(reads, 2);

    AudioLibrary.revision++;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(reads, 3);
    expect(tester.takeException(), isNull);
  });
}
