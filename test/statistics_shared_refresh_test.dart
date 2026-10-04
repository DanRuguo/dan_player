import 'dart:async';
import 'dart:io';

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_data_storage_card.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/statistics/app_data_storage.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/statistics/statistics_display_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'support/playlist_feature_fixture.dart';

class _PendingStorage extends AppDataStorageScanner {
  final requests = <Completer<AppDataStorageSnapshot>>[];
  int active = 0, maximumActive = 0;
  Completer<void> _nextScan = Completer<void>.sync();
  Future<void> get nextScan => _nextScan.future;

  @override
  Future<AppDataStorageSnapshot> scan(Directory directory) {
    final request = Completer<AppDataStorageSnapshot>();
    requests.add(request);
    _nextScan.complete();
    _nextScan = Completer<void>.sync();
    active++;
    if (active > maximumActive) maximumActive = active;
    return request.future.whenComplete(() => active--);
  }

  void finish(int bytes) => requests.last.complete(AppDataStorageSnapshot(
      path: 'Fixture only',
      parts: [AppDataStoragePart('封面缓存', 3, bytes)],
      unreadable: 0,
      skippedLinks: 0,
      truncated: false));
}

class _Rig {
  _Rig() {
    display = StatisticsDisplayService(
        statistics: statistics,
        readLibrary: () => [
              Audio('Fixture', 'Artist', 'Album', 1, 120, 320, 44100,
                  r'J:\Fixture\Music\song.flac', 1, 1, 'shared-refresh',
                  language: 'en')
            ],
        readLibraryRevision: () => 1,
        scanner: LibraryStatisticsScanner(
            readLyrics: (_) async => null,
            inspectFile: (_) async {
              libraryReads++;
              return const LocalAudioFileInfo.available(4096);
            }));
  }
  final statistics = PlaybackStatistics.inMemory();
  final storage = _PendingStorage();
  late final StatisticsDisplayService display;
  int libraryReads = 0;
  Widget page({bool cacheEntry = false}) => StatisticsPage(
      displayService: display,
      storageScanner: storage,
      initialStorageSection: cacheEntry ? 'cache' : null);
  void dispose() {
    display.dispose();
    statistics.dispose();
  }
}

Widget _host(Widget child, {GlobalKey? boundary}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: applyAppControlTheme(ThemeData(
        useMaterial3: true,
        platform: TargetPlatform.windows,
        fontFamily: danEmbeddedFontFamily,
        fontFamilyFallback: danFontFamilyFallback,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal))),
    builder: (context, child) => RepaintBoundary(
        key: boundary,
        child: MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!)),
    home: Scaffold(body: child));

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('statistics-refresh-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.path);
    await loadPlaylistFeatureFonts();
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await directory.delete(recursive: true);
  });

  Future<void> waitForScan(WidgetTester tester, Future<void> started) async {
    var arrived = false;
    started.then((_) => arrived = true);
    final deadline = Stopwatch()..start();
    while (!arrived && deadline.elapsed < const Duration(seconds: 5)) {
      // Each filesystem await queues its continuation in the widget zone.
      // Advance the real IO events and widget microtasks until scanner arrival.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(arrived, isTrue, reason: 'Isolated path resolution must reach scan');
  }

  Future<void> mount(WidgetTester tester, _Rig rig,
      {bool cacheEntry = false, GlobalKey? boundary}) async {
    uiLanguage.value = UiLanguage.zh;
    sizePlaylistFeature(tester, width: 1080, height: 1000);
    addTearDown(rig.dispose);
    await tester.runAsync(rig.display.prewarmOnce);
    final started = rig.storage.nextScan;
    await tester.pumpWidget(
        _host(rig.page(cacheEntry: cacheEntry), boundary: boundary));
    // Path resolution contains real filesystem futures; let the injected
    // scanner signal completion outside the widget clock.
    await waitForScan(tester, started);
    await tester.pumpAndSettle();
    expect(rig.storage.requests, hasLength(1));
  }

  final refresh =
      find.byKey(const ValueKey('statistics-refresh'), skipOffstage: false);
  final card = find.byType(AppDataStorageCard, skipOffstage: false);

  testWidgets(
      'one top refresh updates library and cache while preserving data height and anchor',
      (tester) async {
    final rig = _Rig();
    final boundary = GlobalKey();
    await mount(tester, rig, cacheEntry: true, boundary: boundary);
    rig.storage.finish(111);
    await tester.pumpAndSettle();
    final previousState = tester.state(card);
    final previousHeight = tester.getSize(card).height;
    expect(
        find.descendant(
            of: card, matching: find.byType(IconButton), skipOffstage: false),
        findsNothing);
    expect(refresh, findsOneWidget);
    await tester.ensureVisible(refresh);
    await tester.pumpAndSettle();
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final previousOffset = position.pixels;
    final refreshed = rig.storage.nextScan;
    await tester.tap(refresh);
    await waitForScan(tester, refreshed);
    await tester.pumpAndSettle();
    expect(rig.libraryReads, 2);
    expect(rig.storage.requests, hasLength(2));
    expect(tester.widget<IconButton>(refresh).onPressed, isNull);
    expect(find.textContaining('111 B', skipOffstage: false), findsWidgets);
    expect(tester.getSize(card).height, previousHeight);
    expect(
        find.descendant(
            of: card,
            matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Tooltip && widget.message == ui('正在读取占用信息…'),
                skipOffstage: false),
            skipOffstage: false),
        findsOneWidget);
    expect(
        find.descendant(
            of: card,
            matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Icon && widget.icon == Symbols.hourglass_empty,
                skipOffstage: false),
            skipOffstage: false),
        findsOneWidget);
    rig.storage.finish(222);
    await tester.pumpAndSettle();
    expect(find.textContaining('222 B', skipOffstage: false), findsWidgets);
    expect(find.textContaining('111 B', skipOffstage: false), findsNothing);
    expect(tester.state(card), same(previousState));
    expect(position.pixels, previousOffset,
        reason: 'Refreshing an entered cache section must not navigate again');
    expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
    await capturePlaylistFeature(tester, boundary, 'shared-refresh-top-wide');
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    expect(find.text(ui('缓存与播放器数据占用')).hitTestable(), findsOneWidget);
    await capturePlaylistFeature(tester, boundary, 'shared-refresh-cache-wide');
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'pending initial scan is serialized and rapid refreshes cannot publish its late data',
      (tester) async {
    final rig = _Rig();
    await mount(tester, rig);
    final originalAction = tester.widget<IconButton>(refresh).onPressed!;
    await tester.tap(refresh);
    originalAction();
    originalAction();
    await tester.pumpAndSettle();
    expect(rig.storage.requests, hasLength(1));
    expect(tester.widget<IconButton>(refresh).onPressed, isNull);
    final refreshed = rig.storage.nextScan;
    rig.storage.finish(111);
    await tester.pump();
    await waitForScan(tester, refreshed);
    await tester.pumpAndSettle();
    expect(rig.storage.requests, hasLength(2));
    expect(find.textContaining('111 B', skipOffstage: false), findsNothing);
    expect(find.text(ui('正在读取占用信息…'), skipOffstage: false), findsOneWidget);
    originalAction();
    await tester.pump();
    expect(rig.storage.requests, hasLength(2));
    rig.storage.finish(222);
    await tester.pumpAndSettle();
    expect(find.textContaining('222 B', skipOffstage: false), findsWidgets);
    expect(rig.storage.maximumActive, 1);
    expect(rig.libraryReads, 2);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cache failure is shown and the same top action retries it',
      (tester) async {
    final rig = _Rig();
    await mount(tester, rig);
    rig.storage.finish(111);
    await tester.pumpAndSettle();
    var refreshed = rig.storage.nextScan;
    await tester.tap(refresh);
    await waitForScan(tester, refreshed);
    await tester.pumpAndSettle();
    rig.storage.requests.last.completeError(StateError('fixture read failure'));
    await tester.pumpAndSettle();
    expect(find.text(ui('无法读取此目录的占用信息'), skipOffstage: false), findsOneWidget);
    expect(find.textContaining('111 B', skipOffstage: false), findsNothing);
    expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
    refreshed = rig.storage.nextScan;
    await tester.tap(refresh);
    await waitForScan(tester, refreshed);
    await tester.pumpAndSettle();
    rig.storage.finish(333);
    await tester.pumpAndSettle();
    expect(find.textContaining('333 B', skipOffstage: false), findsWidgets);
    expect(find.text(ui('无法读取此目录的占用信息'), skipOffstage: false), findsNothing);
    expect(rig.storage.requests, hasLength(3));
    expect(rig.storage.maximumActive, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposing a queued refresh never starts a second cache scan',
      (tester) async {
    final rig = _Rig();
    await mount(tester, rig);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(rig.storage.requests, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    rig.storage.finish(111);
    await tester.pumpAndSettle();
    expect(rig.storage.requests, hasLength(1));
    expect(rig.storage.active, 0);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
