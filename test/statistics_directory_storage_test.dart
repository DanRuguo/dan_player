import 'dart:async';
import 'dart:io';

import 'package:dan_player/component/app_data_storage_card.dart';
import 'package:dan_player/component/statistics_bar_row.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/statistics/app_data_storage.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/statistics/player_directory_storage.dart';
import 'package:dan_player/statistics/statistics_display_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

AppDataStorageSnapshot _snapshot(String path, int bytes) =>
    AppDataStorageSnapshot(
        path: path,
        parts: [AppDataStoragePart('其他文件', 1, bytes)],
        unreadable: 0,
        skippedLinks: 0,
        truncated: false);

class _PendingCache extends AppDataStorageScanner {
  final requests = <Completer<AppDataStorageSnapshot>>[];
  final directories = <String>[];
  @override
  Future<AppDataStorageSnapshot> scan(Directory directory) {
    directories.add(directory.path);
    final request = Completer<AppDataStorageSnapshot>();
    requests.add(request);
    return request.future;
  }

  void finish(int bytes) =>
      requests.last.complete(_snapshot('Cache fixture', bytes));
}

class _PendingPlayer extends PlayerDirectoryStorageScanner {
  final requests = <Completer<AppDataStorageSnapshot>>[];
  final directories = <String>[];
  final cancellations = <bool Function()?>[];
  int active = 0, maximumActive = 0;
  @override
  Future<AppDataStorageSnapshot> scan(Directory directory,
      {bool Function()? isCancelled}) {
    directories.add(directory.path);
    cancellations.add(isCancelled);
    final request = Completer<AppDataStorageSnapshot>();
    requests.add(request);
    active++;
    if (active > maximumActive) maximumActive = active;
    return request.future.whenComplete(() => active--);
  }

  void finish(int bytes) =>
      requests.last.complete(_snapshot('Player fixture', bytes));
}

class _Rig {
  _Rig(this.playerDirectory) {
    display = StatisticsDisplayService(
        statistics: statistics,
        readLibrary: () => tracks,
        readLibraryRevision: () => 1,
        scanner: LibraryStatisticsScanner(
            readLyrics: (_) async => null,
            inspectFile: (path) async {
              libraryReads++;
              return LocalAudioFileInfo.available(path.endsWith('one.flac')
                  ? 100
                  : path.endsWith('two.flac')
                      ? 250
                      : 25);
            }));
  }
  final Directory playerDirectory;
  final statistics = PlaybackStatistics.inMemory();
  final cache = _PendingCache();
  final player = _PendingPlayer();
  final tracks = [
    Audio(
        'First track',
        '合作 Artist / アーティスト 아티스트',
        '长专辑 Collection 作品集 모음 é 👨‍👩‍👧‍👦',
        1,
        120,
        320,
        44100,
        r'C:\Fixture\one.flac',
        1,
        1,
        'storage-one',
        language: 'en'),
    Audio(
        'Second track',
        '合作 Artist / アーティスト 아티스트',
        '长专辑 Collection 作品集 모음 é 👨‍👩‍👧‍👦',
        2,
        120,
        320,
        44100,
        r'C:\Fixture\two.flac',
        1,
        1,
        'storage-two',
        language: 'en'),
    Audio('Third track', 'Other', 'Other album', 3, 120, 320, 44100,
        r'C:\Fixture\three.flac', 1, 1, 'storage-three',
        language: 'en'),
  ];
  late final StatisticsDisplayService display;
  int libraryReads = 0;
  Widget get page => StatisticsPage(
      displayService: display,
      storageScanner: cache,
      playerStorageScanner: player,
      playerDirectory: playerDirectory);
  void dispose() {
    display.dispose();
    statistics.dispose();
  }
}

final _card = find.byType(AppDataStorageCard, skipOffstage: false);
final _directorySelector =
    find.byKey(const ValueKey('directory-storage-scope'), skipOffstage: false);
final _storageSelector =
    find.byKey(const ValueKey('statistics-storage-group'), skipOffstage: false);
final _refresh =
    find.byKey(const ValueKey('statistics-refresh'), skipOffstage: false);

Future<void> _waitFor(WidgetTester tester, bool Function() arrived) async {
  final deadline = Stopwatch()..start();
  while (!arrived() && deadline.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  expect(arrived(), isTrue,
      reason: 'Injected filesystem continuation must finish');
}

Future<void> _choose(WidgetTester tester, Finder selector, String label) async {
  await tester.ensureVisible(selector);
  await tester.pumpAndSettle();
  final chip = find.descendant(
      of: selector, matching: find.widgetWithText(ChoiceChip, label));
  expect(chip, findsOneWidget);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  expect(chip.hitTestable(), findsOneWidget);
  expect(
      tester
          .widget<RawChip>(
              find.descendant(of: chip, matching: find.byType(RawChip)))
          .showCheckmark,
      isTrue);
  await tester.tap(chip);
  await tester.pumpAndSettle();
  expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
}

Future<void> _revealRefresh(WidgetTester tester) async {
  await tester.ensureVisible(_refresh);
  await tester.pumpAndSettle();
  expect(_refresh.hitTestable(), findsOneWidget);
}

void main() {
  late Directory fixture;
  setUpAll(() async {
    fixture = await Directory.systemTemp.createTemp('statistics-directory-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => fixture.path);
    await loadPlaylistFeatureFonts();
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await fixture.delete(recursive: true);
  });
  setUp(() {
    final previous = uiLanguage.value;
    uiLanguage.value = UiLanguage.zh;
    addTearDown(() => uiLanguage.value = previous);
  });

  Future<void> mount(WidgetTester tester, _Rig rig,
      {double width = 1080, double scale = 1, GlobalKey? boundary}) async {
    sizePlaylistFeature(tester, width: width, height: 1100);
    addTearDown(rig.dispose);
    await tester.runAsync(rig.display.prewarmOnce);
    await tester.pumpWidget(
        playlistFeatureHost(rig.page, textScale: scale, boundary: boundary));
    await _waitFor(tester, () => rig.cache.requests.length == 1);
    rig.cache.finish(111);
    await tester.pumpAndSettle();
    expect(_card, findsOneWidget);
    expect(rig.cache.directories.single, contains(fixture.path));
    expect(rig.player.requests, isEmpty);
  }

  testWidgets(
      'cache entry and manual refresh never scan an unselected player directory',
      (tester) async {
    final rig = _Rig(Directory('${fixture.path}/injected-player'));
    await mount(tester, rig);
    final state = tester.state(_card);
    await tester.ensureVisible(_card);
    await tester.pumpAndSettle();
    expect(rig.player.requests, isEmpty);
    await _revealRefresh(tester);
    await tester.tap(_refresh);
    await _waitFor(tester, () => rig.cache.requests.length == 2);
    rig.cache.finish(222);
    await tester.pumpAndSettle();
    expect(rig.player.requests, isEmpty);
    expect(rig.libraryReads, 6);
    expect(tester.state(_card), same(state));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'first player selection is injected and repeated pending or completed switches reuse it',
      (tester) async {
    final rig = _Rig(Directory('${fixture.path}/injected-player'));
    await mount(tester, rig);
    final state = tester.state(_card);
    await _choose(tester, _directorySelector, ui('播放器目录'));
    expect(rig.player.requests, hasLength(1));
    expect(rig.player.directories.single, rig.playerDirectory.path);
    expect(rig.player.cancellations.single!.call(), isFalse);
    expect(find.descendant(of: _card, matching: find.textContaining('111 B')),
        findsNothing);
    await _choose(tester, _directorySelector, ui('缓存与播放器数据'));
    expect(find.descendant(of: _card, matching: find.textContaining('111 B')),
        findsWidgets);
    await _choose(tester, _directorySelector, ui('播放器目录'));
    expect(rig.player.requests, hasLength(1));
    rig.player.finish(777);
    await tester.pumpAndSettle();
    expect(find.descendant(of: _card, matching: find.textContaining('777 B')),
        findsWidgets);
    await _choose(tester, _directorySelector, ui('缓存与播放器数据'));
    await _choose(tester, _directorySelector, ui('播放器目录'));
    expect(rig.player.requests, hasLength(1));
    expect(rig.cache.requests, hasLength(1));
    expect(rig.libraryReads, 3);
    expect(tester.state(_card), same(state));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(rig.player.cancellations.single!.call(), isTrue);
  });

  testWidgets(
      'shared refresh serializes an active player scan and repeated actions stay single flight',
      (tester) async {
    final rig = _Rig(Directory('${fixture.path}/injected-player'));
    await mount(tester, rig);
    await _choose(tester, _directorySelector, ui('播放器目录'));
    await _revealRefresh(tester);
    final action = tester.widget<IconButton>(_refresh).onPressed!;
    action();
    action();
    await _waitFor(tester, () => rig.cache.requests.length == 2);
    expect(rig.player.requests, hasLength(1));
    expect(tester.widget<IconButton>(_refresh).onPressed, isNull);
    rig.player.finish(101);
    await _waitFor(tester, () => rig.player.requests.length == 2);
    expect(rig.player.maximumActive, 1);
    rig.cache.finish(222);
    rig.player.finish(303);
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(_refresh).onPressed, isNotNull);
    expect(rig.libraryReads, 6);
    expect(rig.player.active, 0);
    await tester.ensureVisible(_card);
    await tester.pumpAndSettle();
    expect(find.descendant(of: _card, matching: find.textContaining('303 B')),
        findsWidgets);
    expect(find.descendant(of: _card, matching: find.textContaining('101 B')),
        findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'player refresh retains its completed result and cache switching never leaks the other root',
      (tester) async {
    final rig = _Rig(Directory('${fixture.path}/injected-player'));
    await mount(tester, rig);
    await _choose(tester, _directorySelector, ui('播放器目录'));
    rig.player.finish(777);
    await tester.pumpAndSettle();
    await _revealRefresh(tester);
    await tester.tap(_refresh);
    await _waitFor(
        tester,
        () =>
            rig.player.requests.length == 2 && rig.cache.requests.length == 2);
    await tester.ensureVisible(_card);
    await tester.pumpAndSettle();
    expect(find.descendant(of: _card, matching: find.textContaining('777 B')),
        findsWidgets);
    expect(find.descendant(of: _card, matching: find.textContaining('111 B')),
        findsNothing);
    rig.player.finish(888);
    rig.cache.finish(222);
    await tester.pumpAndSettle();
    expect(find.descendant(of: _card, matching: find.textContaining('888 B')),
        findsWidgets);
    await _choose(tester, _directorySelector, ui('缓存与播放器数据'));
    expect(find.descendant(of: _card, matching: find.textContaining('222 B')),
        findsWidgets);
    expect(find.descendant(of: _card, matching: find.textContaining('888 B')),
        findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'disposing during a queued player refresh cancels ownership without starting another scan',
      (tester) async {
    final rig = _Rig(Directory('${fixture.path}/injected-player'));
    await mount(tester, rig);
    await _choose(tester, _directorySelector, ui('播放器目录'));
    await _revealRefresh(tester);
    await tester.tap(_refresh);
    await _waitFor(tester, () => rig.cache.requests.length == 2);
    expect(rig.player.requests, hasLength(1));
    final cancelled = rig.player.cancellations.single!;
    expect(cancelled(), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(cancelled(), isTrue);
    rig.player.requests.single
        .completeError(const DirectoryStorageScanCancelled());
    rig.cache.finish(222);
    await tester.pumpAndSettle();
    expect(rig.player.requests, hasLength(1));
    expect(rig.player.active, 0);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed player reading is cached until the top refresh explicitly retries it',
      (tester) async {
    final rig = _Rig(Directory('${fixture.path}/injected-player'));
    await mount(tester, rig);
    await _choose(tester, _directorySelector, ui('播放器目录'));
    rig.player.requests.single
        .completeError(StateError('Injected directory failure'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _card, matching: find.text(ui('无法读取此目录的占用信息'))),
        findsOneWidget);
    await _choose(tester, _directorySelector, ui('缓存与播放器数据'));
    await _choose(tester, _directorySelector, ui('播放器目录'));
    expect(rig.player.requests, hasLength(1));
    await _revealRefresh(tester);
    await tester.tap(_refresh);
    await _waitFor(
        tester,
        () =>
            rig.player.requests.length == 2 && rig.cache.requests.length == 2);
    rig.player.finish(999);
    rig.cache.finish(222);
    await tester.pumpAndSettle();
    await tester.ensureVisible(_card);
    await tester.pumpAndSettle();
    expect(find.descendant(of: _card, matching: find.textContaining('999 B')),
        findsWidgets);
    expect(find.descendant(of: _card, matching: find.text(ui('无法读取此目录的占用信息'))),
        findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final language in UiLanguage.values) {
    testWidgets(
        'storage album and artist ranking ${language.code} narrow large text uses frozen totals',
        (tester) async {
      final rig = _Rig(Directory('${fixture.path}/injected-player'));
      final boundary = GlobalKey();
      uiLanguage.value = language;
      await mount(tester, rig, width: 360, scale: 2, boundary: boundary);
      final chips = find.descendant(
          of: _storageSelector,
          matching: find.byType(ChoiceChip, skipOffstage: false),
          skipOffstage: false);
      expect(chips, findsNWidgets(3));
      final heading = find.text(ui('占用空间最多'), skipOffstage: false);
      await tester.ensureVisible(_storageSelector);
      await tester.pumpAndSettle();
      expect(tester.getRect(_storageSelector).top,
          greaterThan(tester.getRect(heading).bottom));
      final contentColumn = find
          .ancestor(
              of: _storageSelector,
              matching: find.byType(Column, skipOffstage: false))
          .first;
      expect(tester.getRect(_storageSelector).right,
          closeTo(tester.getRect(contentColumn).right, 1),
          reason: 'The second-line choices align with the card content end');
      final rowEnds = <double, double>{};
      for (final label in ['歌曲', '专辑', '艺术家']) {
        final chip = find.descendant(
            of: _storageSelector,
            matching: find.widgetWithText(ChoiceChip, ui(label)));
        expect(chip.hitTestable(), findsOneWidget);
        final data = tester.widget<ChoiceChip>(chip);
        expect(
            tester
                .widget<RawChip>(
                    find.descendant(of: chip, matching: find.byType(RawChip)))
                .showCheckmark,
            isTrue);
        expect(data.selected, label == '歌曲');
        final rect = tester.getRect(chip);
        final containerRect = tester.getRect(_storageSelector);
        expect(rect.left, greaterThanOrEqualTo(containerRect.left - 1));
        expect(rect.right, lessThanOrEqualTo(containerRect.right + 1));
        rowEnds.update(
            rect.top, (right) => right > rect.right ? right : rect.right,
            ifAbsent: () => rect.right);
        final text = find.descendant(of: chip, matching: find.text(ui(label)));
        final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: text, matching: find.byType(RichText)));
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.text.toPlainText(), ui(label));
        final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: ui(label).length));
        expect(boxes, isNotEmpty);
        for (final box in boxes) {
          final glyph =
              box.toRect().shift(paragraph.localToGlobal(Offset.zero));
          expect(glyph.left, greaterThanOrEqualTo(rect.left - 1));
          expect(glyph.right, lessThanOrEqualTo(rect.right + 1));
          expect(glyph.top, greaterThanOrEqualTo(rect.top - 3));
          expect(glyph.bottom, lessThanOrEqualTo(rect.bottom + 3));
        }
      }
      expect(rowEnds.length, greaterThan(1),
          reason: 'Narrow large-text choices must wrap onto real rows');
      for (final end in rowEnds.values) {
        expect(end, closeTo(tester.getRect(_storageSelector).right, 1),
            reason: 'Each wrapped choice row stays aligned at the content end');
      }
      final rankingCard = find
          .ancestor(of: _storageSelector, matching: find.byType(Card))
          .first;
      await tester.ensureVisible(rankingCard);
      await tester.pumpAndSettle();
      await capturePlaylistFeature(
          tester, boundary, 'storage-choice-chips-${language.code}-360-200');
      for (final (group, label) in [('albums', '专辑'), ('artists', '艺术家')]) {
        await _choose(tester, _storageSelector, ui(label));
        final selected =
            tester.widgetList<ChoiceChip>(chips).where((chip) => chip.selected);
        expect(selected, hasLength(1));
        expect((selected.single.label as Text).data, ui(label));
        final targetLabel = group == 'albums'
            ? rig.tracks.first.album
            : rig.tracks.first.artist;
        final row = find.byWidgetPredicate((widget) =>
            widget is StatisticsBarRow && widget.label == targetLabel);
        expect(row, findsOneWidget);
        final data = tester.widget<StatisticsBarRow>(row);
        expect(data.value, 350);
        expect(data.valueLabel, '350 B');
        expect(data.detail, contains(ui('{0} 个文件', [2])));
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        final text = find.descendant(of: row, matching: find.text(targetLabel));
        final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: text, matching: find.byType(RichText)));
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.text.toPlainText(), targetLabel);
        final glyphBoxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: targetLabel.length));
        expect(glyphBoxes, isNotEmpty);
        for (final box in glyphBoxes) {
          final rect = box.toRect().shift(paragraph.localToGlobal(Offset.zero));
          expect(rect.left, greaterThanOrEqualTo(-1));
          expect(rect.right, lessThanOrEqualTo(361));
          expect(rect.top, greaterThanOrEqualTo(-3));
          expect(rect.bottom, lessThanOrEqualTo(1103));
        }
        await capturePlaylistFeature(
            tester, boundary, 'storage-$group-${language.code}-360-200');
        expect(rig.libraryReads, 3);
        expect(rig.player.requests, isEmpty);
        expect(rig.cache.requests, hasLength(1));
        expect(tester.takeException(), isNull);
      }
      // Resizing the actual mounted page preserves the frozen snapshot and
      // selected group. A wide heading uses the same row as its controls.
      sizePlaylistFeature(tester, width: 1080, height: 1100);
      await tester.pumpWidget(
          playlistFeatureHost(rig.page, textScale: 1, boundary: boundary));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_storageSelector);
      await tester.pumpAndSettle();
      expect(tester.getRect(heading).center.dy,
          closeTo(tester.getRect(_storageSelector).center.dy, 1));
      expect(tester.getRect(heading).right,
          lessThan(tester.getRect(_storageSelector).left));
      expect(tester.getRect(_storageSelector).right,
          closeTo(tester.getRect(contentColumn).right, 1));
      final wideRows = tester
          .widgetList<ChoiceChip>(chips)
          .map((chip) => tester.getRect(find.byWidget(chip)).top)
          .toSet();
      expect(wideRows, hasLength(1));
      expect(rig.libraryReads, 3);
      expect(rig.player.requests, isEmpty);
      expect(rig.cache.requests, hasLength(1));
      await capturePlaylistFeature(
          tester, boundary, 'storage-choice-chips-${language.code}-1080-100');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}
