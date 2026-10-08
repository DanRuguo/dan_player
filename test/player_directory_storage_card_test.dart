import 'dart:async';
import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_data_storage_card.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/directory_storage_card.dart';
import 'package:dan_player/component/statistics_bar_row.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/statistics/app_data_storage.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

const _scope = '播放器目录内的实际文件字节；不包含外部音乐、用户数据或外部工具。链接不跟随，首次选择或手动刷新时读取。';
const _root =
    'J:/temp/codex/software/danplayer/tool/qa-local/font-release-oct8/storage-ui/fixture-player';
const _labels = [
  '主程序',
  'Flutter引擎与运行库',
  '字体',
  '界面资源',
  'BASS音频组件',
  'FFmpeg工具',
  '更新与安装辅助',
  '说明与许可证',
  '其他文件',
];

const _empty = AppDataStorageSnapshot(
    path: 'injected cache',
    parts: [],
    unreadable: 0,
    skippedLinks: 0,
    truncated: false);

Widget _card(Future<AppDataStorageSnapshot> reading) => DirectoryStorageCard(
    cacheReading: Future.value(_empty),
    playerReading: reading,
    onPlayerSelected: () => fail('An injected player future must not rescan'));

Future<void> _selectScope(
    WidgetTester tester, DirectoryStorageScope scope) async {
  final key = ValueKey('directory-storage-scope-${scope.name}');
  expect(find.byType(ChoiceChip), findsNWidgets(2));
  final wrap = tester
      .widget<Wrap>(find.byKey(const ValueKey('directory-storage-scope')));
  expect(wrap.spacing, 8);
  expect(wrap.runSpacing, 8);
  expect(wrap.alignment, WrapAlignment.end);
  for (final item in [
    (DirectoryStorageScope.cache, ui('缓存与播放器数据')),
    (DirectoryStorageScope.player, ui('播放器目录')),
  ]) {
    final chip =
        find.byKey(ValueKey('directory-storage-scope-${item.$1.name}'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    final bounds = tester.getRect(chip);
    expect(bounds.left, greaterThanOrEqualTo(-.1));
    expect(
        bounds.right, lessThanOrEqualTo(tester.view.physicalSize.width + .1));
    expect(tester.widget<ChoiceChip>(chip).showCheckmark, isTrue);
    _completeLabel(tester, chip, item.$2);
    final widget = tester.widget<ChoiceChip>(chip);
    final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: chip, matching: find.text(item.$2)));
    final line = TextPainter(
        text: paragraph.text,
        textDirection: paragraph.textDirection,
        textScaler: paragraph.textScaler,
        maxLines: 1)
      ..layout();
    final markSize = widget.selected ? line.height : 0.0;
    expect(widget.avatarBoxConstraints!.maxHeight, closeTo(markSize, .1));
    expect(widget.avatarBoxConstraints!.maxWidth, closeTo(markSize, .1));
    line.dispose();
  }
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  expect(tester.widget<ChoiceChip>(find.byKey(key)).selected, isTrue);
  final other = scope == DirectoryStorageScope.cache ? 'player' : 'cache';
  expect(
      tester
          .widget<ChoiceChip>(
              find.byKey(ValueKey('directory-storage-scope-$other')))
          .selected,
      isFalse);
  final header =
      tester.getRect(find.byKey(const ValueKey('app-data-storage-heading')));
  final card = tester.getRect(find.byType(AppDataStorageCard));
  final chips = [
    tester.getRect(find.byKey(const ValueKey('directory-storage-scope-cache'))),
    tester
        .getRect(find.byKey(const ValueKey('directory-storage-scope-player'))),
  ];
  if (tester.view.physicalSize.width >= 800) {
    final controls =
        tester.getRect(find.byKey(const ValueKey('directory-storage-scope')));
    expect(header.center.dy, closeTo(controls.center.dy, .1));
    expect(header.right + 12, lessThanOrEqualTo(chips.first.left + .1));
  } else {
    for (final chip in chips) {
      expect(chip.top, greaterThan(header.bottom));
    }
  }
  // Each wrapped row, rather than only the Wrap box, ends at the content edge.
  for (var index = 0; index < chips.length; index++) {
    if (index == chips.length - 1 || chips[index + 1].top > chips[index].top) {
      expect(chips[index].right, closeTo(card.right - 18, .1));
    }
  }
}

AppDataStorageSnapshot _snapshot({bool partial = false}) =>
    AppDataStorageSnapshot(
        path: _root,
        parts: [
          for (var index = 0; index < _labels.length; index++)
            AppDataStoragePart(_labels[index], index + 1, (index + 1) * 1024,
                paths: ['$_root/组件-$index- Music player resources']),
        ],
        unreadable: partial ? 2 : 0,
        skippedLinks: partial ? 3 : 0,
        truncated: partial);

Widget _host(Widget child,
        {UiLanguage language = UiLanguage.zh,
        double scale = 1,
        GlobalKey? boundary}) =>
    UiLanguageScope(
        child: MaterialApp(
            locale: language.locale,
            supportedLocales: UiLanguage.values.map((value) => value.locale),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: applyAppControlTheme(ThemeData(
                fontFamily: AppFontPolicy.defaults(language: language).uiFamily,
                fontFamilyFallback: danFontFamilyFallback,
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal))),
            builder: (context, child) => RepaintBoundary(
                key: boundary,
                child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: AppFontScope(
                        policy: AppFontPolicy.defaults(language: language),
                        child: child!))),
            home: Scaffold(
                body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child))));

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final directory = Platform.environment['DAN_DIRECTORY_STORAGE_RENDER_DIR'];
  if (directory == null) return;
  if (name.endsWith('-top') || name.endsWith('-choices')) {
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(0);
    await tester.pumpAndSettle();
  }
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage();
    try {
      final bytes = await image.toByteData(format: raster.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void _completeLabel(WidgetTester tester, Finder row, String label) {
  final bounds = tester.getRect(row).inflate(.5);
  final text = find.descendant(of: row, matching: find.text(label));
  final paragraph = tester.renderObject<RenderParagraph>(text);
  expect(paragraph.didExceedMaxLines, isFalse);
  for (final run in RegExp(r'\S+').allMatches(label)) {
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: run.start, extentOffset: run.end));
    expect(boxes, isNotEmpty);
    for (final box in boxes) {
      final glyphs = MatrixUtils.transformRect(
          paragraph.getTransformTo(null), box.toRect());
      expect(bounds.contains(glyphs.topLeft), isTrue);
      expect(bounds.contains(glyphs.bottomRight), isTrue,
          reason: 'The complete category must fit its painted row: $label '
              '(row $bounds, glyphs $glyphs)');
    }
  }
}

void main() {
  setUpAll(() async {
    await ensureAppFontsLoaded(AppFontPolicy.defaults());
    for (final font in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  for (final language in UiLanguage.values) {
    testWidgets(
        '${language.code} pending scopes reserve complete category layout',
        (tester) async {
      final previous = uiLanguage.value;
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = previous);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final layout in [(1000.0, 1.0), (360.0, 2.0)]) {
        tester.view.physicalSize = Size(layout.$1, 800);
        final cache = Completer<AppDataStorageSnapshot>();
        final player = Completer<AppDataStorageSnapshot>();
        final boundary = GlobalKey();
        await tester.pumpWidget(_host(
            Column(children: [
              DirectoryStorageCard(
                  cacheReading: cache.future,
                  playerReading: player.future,
                  onPlayerSelected: () =>
                      fail('Injected futures must not scan')),
              const Text('below-directory'),
            ]),
            language: language,
            scale: layout.$2,
            boundary: boundary));
        await tester.pumpAndSettle();
        final card = find.byType(AppDataStorageCard);
        final height = tester.getSize(card).height;
        await _capture(tester, boundary,
            'storage-pending-${language.code}-${layout.$1.toInt()}-top');
        final scroll =
            tester.state<ScrollableState>(find.byType(Scrollable).first);
        scroll.position
            .jumpTo(scroll.position.maxScrollExtent.clamp(0.0, 60.0));
        await tester.pumpAndSettle();
        final pixels = scroll.position.pixels;
        final positions = [
          for (final row in find.byType(StatisticsBarRow).evaluate())
            tester.getTopLeft(find.byWidget(row.widget)).dy,
        ];
        expect(positions, hasLength(AppDataStorageScanner.categories.length));
        for (final row in tester
            .widgetList<StatisticsBarRow>(find.byType(StatisticsBarRow))) {
          expect(row.valueLabel, '—');
          expect(row.value, 0);
        }
        cache.complete(AppDataStorageSnapshot(
            path: 'injected cache',
            parts: [
              for (final label in AppDataStorageScanner.categories)
                AppDataStoragePart(label, 50, 1024 * 1024),
            ],
            unreadable: 2,
            skippedLinks: 3,
            truncated: true));
        await tester.pumpAndSettle();
        expect(tester.getSize(card).height, closeTo(height, .1));
        expect(scroll.position.pixels, closeTo(pixels, .1));
        final cachePositions = [
          for (final row in find.byType(StatisticsBarRow).evaluate())
            tester.getTopLeft(find.byWidget(row.widget)).dy,
        ];
        expect(cachePositions, orderedEquals(positions));
        await tester
            .tap(find.byKey(const ValueKey('directory-storage-scope-player')));
        await tester.pump();
        expect(tester.getSize(card).height, closeTo(height, .1),
            reason: 'First selection must not shorten the lower page');
        expect(scroll.position.pixels, closeTo(pixels, .1));
        final pendingPositions = [
          for (final row in find.byType(StatisticsBarRow).evaluate())
            tester.getTopLeft(find.byWidget(row.widget)).dy,
        ];
        expect(pendingPositions, orderedEquals(positions));
        player.complete(_snapshot(partial: true));
        await tester.pumpAndSettle();
        expect(tester.getSize(card).height, closeTo(height, .1));
        expect(scroll.position.pixels, closeTo(pixels, .1));
        expect(tester.getTopLeft(find.text('below-directory')).dy,
            closeTo(tester.getRect(card).bottom, .1));
        for (final row in find.byType(StatisticsBarRow).evaluate()) {
          final widget = row.widget as StatisticsBarRow;
          _completeLabel(tester, find.byWidget(widget), widget.label);
        }
        await _capture(tester, boundary,
            'storage-fixed-${language.code}-${layout.$1.toInt()}-top');
        await tester.pump();
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets('boundary widths retain pending rows after large amounts arrive',
      (tester) async {
    final previous = uiLanguage.value;
    uiLanguage.value = UiLanguage.en;
    addTearDown(() => uiLanguage.value = previous);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final layout in [
      (667.0, 1.0),
      (669.0, 1.0),
      (1267.0, 2.0),
      (1269.0, 2.0)
    ]) {
      tester.view.physicalSize = Size(layout.$1, 900);
      final pending = Completer<AppDataStorageSnapshot>();
      await tester.pumpWidget(_host(_card(pending.future),
          language: UiLanguage.en, scale: layout.$2));
      await _selectScope(tester, DirectoryStorageScope.player);
      final height = tester.getSize(find.byType(AppDataStorageCard)).height;
      final rows = [
        for (final row in find.byType(StatisticsBarRow).evaluate())
          tester.getRect(find.byWidget(row.widget))
      ];
      pending.complete(AppDataStorageSnapshot(
          path: _root,
          parts: [
            for (final label in _labels)
              AppDataStoragePart(label, 20000, 1 << 50),
          ],
          unreadable: 200000,
          skippedLinks: 200000,
          truncated: true));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AppDataStorageCard)).height,
          closeTo(height, .1));
      final readyRows = [
        for (final row in find.byType(StatisticsBarRow).evaluate())
          tester.getRect(find.byWidget(row.widget))
      ];
      expect(readyRows, orderedEquals(rows));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('bar reveal is finite shared and retires on visual gates',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = ValueNotifier(const RenderingPreferences());
    addTearDown(preferences.dispose);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final cache = Future.value(_empty);
    var pending = Completer<AppDataStorageSnapshot>();
    var visible = true;
    late StateSetter rebuild;
    await tester.pumpWidget(_host(StatefulBuilder(builder: (context, setState) {
      rebuild = setState;
      return RenderingPreferencesScope(
          preferences: preferences,
          child: TickerMode(
              enabled: visible,
              child: DirectoryStorageCard(
                  cacheReading: cache,
                  playerReading: pending.future,
                  onPlayerSelected: () => fail('No scan is needed'))));
    })));
    await _selectScope(tester, DirectoryStorageScope.player);
    List<StatisticsBarRow> rows() => tester
        .widgetList<StatisticsBarRow>(find.byType(StatisticsBarRow))
        .toList();
    Future<void> complete() async {
      pending.complete(_snapshot());
      await tester.pump();
      // Future completion can start the ticker after the preceding frame's
      // transient callbacks. Establish its first (zero elapsed) real frame.
      await tester.pump();
    }

    await complete();
    final initialRows = rows();
    final progress = initialRows.first.progress!;
    expect(progress.value, 0);
    expect(
        initialRows.every((row) => identical(row.progress, progress)), isTrue,
        reason: 'Nine bars use one finite owner, not nine controllers');
    await tester.pump(const Duration(milliseconds: 90));
    expect(progress.value, inExclusiveRange(0.0, 1.0));
    for (var index = 0; index < initialRows.length; index++) {
      expect(rows()[index], same(initialRows[index]),
          reason: 'Animation ticks must not remeasure or rebuild row text');
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(progress.value, 1);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);

    for (final gate in ['ticker', 'feedback', 'native-reduce', 'hidden']) {
      rebuild(() => pending = Completer<AppDataStorageSnapshot>());
      await tester.pump();
      await complete();
      expect(rows().first.progress!.value, 0);
      await tester.pump(const Duration(milliseconds: 60));
      expect(rows().first.progress!.value, inExclusiveRange(0.0, 1.0));
      if (gate == 'ticker') rebuild(() => visible = false);
      if (gate == 'feedback') {
        preferences.value = const RenderingPreferences(
            animations: MotionPreferences(disabled: {MotionKind.feedback}));
      }
      if (gate == 'native-reduce') {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(reduceMotion: true);
      }
      if (gate == 'hidden') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      }
      await tester.pump();
      expect(rows().first.progress!.value, 1);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      if (gate == 'ticker') rebuild(() => visible = true);
      if (gate == 'feedback') preferences.value = const RenderingPreferences();
      if (gate == 'native-reduce') {
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      }
      if (gate == 'hidden') {
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
      await tester.pump();
      expect(rows().first.progress!.value, 1,
          reason: 'Restoring visibility must not replay a retired reveal');
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    testWidgets(
        '${language.code} directory totals and complete labels wide/narrow',
        (tester) async {
      final previous = uiLanguage.value;
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = previous);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = _snapshot(partial: true);
      final reading = Future.value(data);
      for (final layout in [(1000.0, 1.0), (360.0, 2.0)]) {
        tester.view.physicalSize = Size(layout.$1, 1100);
        final boundary = GlobalKey();
        await tester.pumpWidget(_host(_card(reading),
            language: language, scale: layout.$2, boundary: boundary));
        await tester.pumpAndSettle();
        await _selectScope(tester, DirectoryStorageScope.cache);
        await _capture(tester, boundary,
            'storage-${language.code}-${layout.$1.toInt()}-choices');
        await _selectScope(tester, DirectoryStorageScope.player);
        expect(find.text(ui('播放器组件目录占用')), findsOneWidget);
        expect(find.text(ui('缓存与播放器数据占用')), findsNothing);
        expect(
            find.text('${formatLibraryBytes(data.bytes)} · '
                '${ui('{0} 个文件', [data.files])}'),
            findsOneWidget);
        expect(
            find.byWidgetPredicate(
                (widget) => widget is Tooltip && widget.message == _root),
            findsOneWidget);
        expect(find.text(_root), findsNothing);
        await _capture(tester, boundary,
            'storage-${language.code}-${layout.$1.toInt()}-top');
        for (final part in data.parts) {
          final label = ui(part.label);
          final row = find.byWidgetPredicate(
              (widget) => widget is StatisticsBarRow && widget.label == label);
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
          expect(find.text(label).hitTestable(), findsOneWidget);
          _completeLabel(tester, row, label);
          expect(tester.widget<StatisticsBarRow>(row).maximum, data.bytes);
          expect(
              find.byWidgetPredicate((widget) =>
                  widget is Tooltip &&
                  widget.message ==
                      '$label\n${ui('{0} 个文件', [
                            part.files
                          ])}\n${part.paths.single}'),
              findsOneWidget);
          expect(find.text(part.paths.single), findsNothing);
        }
        expect(find.text(ui(_scope)), findsOneWidget);
        expect(
            find.text(
                ui('统计未包含：不可读 {0} 项、链接 {1} 项{2}', [2, 3, ui('；已达到扫描上限')])),
            findsOneWidget);
        await tester.ensureVisible(find.text(ui(_scope)));
        await tester.pumpAndSettle();
        await _capture(tester, boundary,
            'storage-${language.code}-${layout.$1.toInt()}-bottom');
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.delete), findsNothing);
        expect(find.byIcon(Symbols.delete), findsNothing);
      }
    });
  }

  testWidgets(
      'provided futures retain ownership across refresh and late errors',
      (tester) async {
    final previous = uiLanguage.value;
    uiLanguage.value = UiLanguage.zh;
    addTearDown(() => uiLanguage.value = previous);
    final stale = Completer<AppDataStorageSnapshot>();
    final current = Completer<AppDataStorageSnapshot>();
    await tester.pumpWidget(_host(_card(stale.future)));
    await _selectScope(tester, DirectoryStorageScope.player);
    expect(find.text(ui('正在读取占用信息…')), findsOneWidget);
    expect(find.byIcon(Symbols.hourglass_empty), findsOneWidget);
    final state = tester.state(find.byType(AppDataStorageCard));
    await tester.pumpWidget(_host(_card(current.future)));
    expect(tester.state(find.byType(AppDataStorageCard)), same(state));
    stale.complete(_snapshot());
    await tester.pumpAndSettle();
    expect(find.byType(StatisticsBarRow), findsNWidgets(_labels.length));
    expect(
        tester
            .widgetList<StatisticsBarRow>(find.byType(StatisticsBarRow))
            .every((row) => row.valueLabel == '—' && row.value == 0),
        isTrue);
    current.completeError(const FileSystemException('injected inaccessible'));
    await tester.pumpAndSettle();
    expect(find.text(ui('无法读取此目录的占用信息')), findsOneWidget);
    expect(find.byIcon(Symbols.folder), findsWidgets);
    expect(find.text(ui(_scope)), findsOneWidget);
    final repaired = _snapshot();
    await tester.pumpWidget(_host(_card(Future.value(repaired))));
    await tester.pumpAndSettle();
    expect(find.byType(StatisticsBarRow), findsNWidgets(_labels.length));
    expect(find.text(ui('无法读取此目录的占用信息')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty installation retains all known categories with zero bytes',
      (tester) async {
    const data = AppDataStorageSnapshot(
        path: _root,
        parts: [],
        unreadable: 0,
        skippedLinks: 0,
        truncated: false);
    await tester.pumpWidget(_host(_card(Future.value(data))));
    await tester.pumpAndSettle();
    await _selectScope(tester, DirectoryStorageScope.player);
    expect(find.text('0 B · ${ui('{0} 个文件', [0])}'), findsOneWidget);
    expect(find.byType(StatisticsBarRow), findsNWidgets(_labels.length));
    expect(
        tester
            .widgetList<StatisticsBarRow>(find.byType(StatisticsBarRow))
            .every((row) => row.valueLabel == '0 B' && row.value == 0),
        isTrue);
    expect(find.byIcon(Symbols.folder), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared base preserves the original cache card presentation',
      (tester) async {
    await tester.pumpWidget(
        _host(AppDataStorageCard(reading: Future.value(_snapshot()))));
    await tester.pumpAndSettle();
    expect(find.text(ui('缓存与播放器数据占用')), findsOneWidget);
    expect(find.byIcon(Symbols.database), findsOneWidget);
    expect(find.text(ui('实际文件字节；用户资料、自选图片与可重建缓存分别统计。链接不跟随，仅打开此页或手动刷新时读取。')),
        findsOneWidget);
    expect(find.text(ui('播放器组件目录占用')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'scope switching lazily requests once and never relabels old data',
      (tester) async {
    final previous = uiLanguage.value;
    uiLanguage.value = UiLanguage.zh;
    addTearDown(() => uiLanguage.value = previous);
    final cache = Future.value(const AppDataStorageSnapshot(
        path: 'injected cache',
        parts: [AppDataStoragePart('封面缓存', 7, 70)],
        unreadable: 0,
        skippedLinks: 0,
        truncated: false));
    final pending = Completer<AppDataStorageSnapshot>();
    Future<AppDataStorageSnapshot>? player;
    var requests = 0;
    await tester.pumpWidget(_host(StatefulBuilder(builder: (context, rebuild) {
      return DirectoryStorageCard(
          cacheReading: cache,
          playerReading: player,
          onPlayerSelected: () => rebuild(() {
                requests++;
                player = pending.future;
              }));
    })));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(AppDataStorageCard));
    final control =
        tester.element(find.byKey(const ValueKey('directory-storage-scope')));
    expect(requests, 0);
    expect(find.byType(AppDataStorageCard), findsOneWidget);
    expect(find.text(ui('封面缓存')), findsOneWidget);
    await _selectScope(tester, DirectoryStorageScope.player);
    expect(requests, 1);
    expect(tester.state(find.byType(AppDataStorageCard)), same(state));
    expect(
        tester.element(find.byKey(const ValueKey('directory-storage-scope'))),
        same(control));
    expect(find.text(ui('封面缓存')), findsNothing);
    expect(find.text(ui('正在读取占用信息…')), findsOneWidget);
    await _selectScope(tester, DirectoryStorageScope.cache);
    expect(find.text(ui('封面缓存')), findsOneWidget);
    pending.complete(_snapshot());
    await tester.pumpAndSettle();
    expect(find.text(ui('主程序')), findsNothing,
        reason: 'A late player result cannot replace the current cache');
    await _selectScope(tester, DirectoryStorageScope.player);
    expect(requests, 1);
    expect(find.text(ui('主程序')), findsOneWidget);
    expect(find.text(ui('封面缓存')), findsNothing);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'Storage selection starts no sampling or polling clock');
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed scopes keep data height and scroll on the first frame',
      (tester) async {
    tester.view.physicalSize = const Size(800, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cache = AppDataStorageSnapshot(
        path: 'injected cache',
        parts: [
          for (var index = 0;
              index < AppDataStorageScanner.categories.length;
              index++)
            AppDataStoragePart(AppDataStorageScanner.categories[index],
                index + 1, (index + 1) * 1024),
        ],
        unreadable: 0,
        skippedLinks: 0,
        truncated: false);
    final player = AppDataStorageSnapshot(
        path: 'injected player',
        parts: [
          for (var index = 0; index < _labels.length; index++)
            AppDataStoragePart(_labels[index], index + 1, (index + 1) * 2048),
        ],
        unreadable: 0,
        skippedLinks: 0,
        truncated: false);
    await tester.pumpWidget(_host(DirectoryStorageCard(
        cacheReading: Future.value(cache),
        playerReading: Future.value(player),
        onPlayerSelected: () => fail('No scan is required'))));
    await tester.pumpAndSettle();
    await _selectScope(tester, DirectoryStorageScope.player);
    final card = find.byType(AppDataStorageCard);
    final heights = <DirectoryStorageScope, double>{
      DirectoryStorageScope.player: tester.getSize(card).height,
    };
    await _selectScope(tester, DirectoryStorageScope.cache);
    heights[DirectoryStorageScope.cache] = tester.getSize(card).height;
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(50);
    await tester.pumpAndSettle();
    final pixels = scroll.position.pixels;
    for (final scope in [
      DirectoryStorageScope.player,
      DirectoryStorageScope.cache,
      DirectoryStorageScope.player,
    ]) {
      await tester
          .tap(find.byKey(ValueKey('directory-storage-scope-${scope.name}')));
      await tester.pump();
      final data = scope == DirectoryStorageScope.player ? player : cache;
      expect(
          find.text('${formatLibraryBytes(data.bytes)} · '
              '${ui('{0} 个文件', [data.files])}'),
          findsOneWidget,
          reason: 'A completed scope must paint its own result immediately');
      expect(find.text(ui('正在读取占用信息…')), findsNothing);
      expect(tester.getSize(card).height, closeTo(heights[scope]!, .1));
      expect(scroll.position.pixels, closeTo(pixels, .1),
          reason: 'A one-frame empty body must not clamp page scrolling');
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive completion is cached without a frame and returns ready',
      (tester) async {
    final pending = Completer<AppDataStorageSnapshot>();
    final data = _snapshot();
    await tester.pumpWidget(_host(DirectoryStorageCard(
        cacheReading: Future.value(_empty),
        playerReading: pending.future,
        onPlayerSelected: () =>
            fail('The player future is already injected'))));
    await tester.pumpAndSettle();
    await _selectScope(tester, DirectoryStorageScope.player);
    expect(find.text(ui('正在读取占用信息…')), findsOneWidget);
    await _selectScope(tester, DirectoryStorageScope.cache);
    pending.complete(data);
    await tester.idle();
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'An inactive completion only stores data; it schedules no UI');
    expect(find.byType(StatisticsBarRow), findsNWidgets(_labels.length));
    expect(find.text(ui('主程序')), findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('directory-storage-scope-player')));
    await tester.pump();
    expect(find.byType(StatisticsBarRow), findsNWidgets(data.parts.length));
    expect(find.text(ui('正在读取占用信息…')), findsNothing);
    expect(find.byIcon(Symbols.hourglass_empty), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh errors clear only their scope and retire stale owners',
      (tester) async {
    final cache = Future.value(const AppDataStorageSnapshot(
        path: 'injected cache',
        parts: [AppDataStoragePart('封面缓存', 3, 7)],
        unreadable: 0,
        skippedLinks: 0,
        truncated: false));
    final data = _snapshot();
    Widget card(Future<AppDataStorageSnapshot> player) =>
        _host(DirectoryStorageCard(
            cacheReading: cache,
            playerReading: player,
            onPlayerSelected: () => fail('No scan is required')));
    await tester.pumpWidget(card(Future.value(data)));
    await tester.pumpAndSettle();
    await _selectScope(tester, DirectoryStorageScope.player);
    final stale = Completer<AppDataStorageSnapshot>();
    final latest = Completer<AppDataStorageSnapshot>();
    await tester.pumpWidget(card(stale.future));
    expect(find.byType(StatisticsBarRow), findsNWidgets(data.parts.length));
    expect(find.byIcon(Symbols.hourglass_empty), findsOneWidget);
    await tester.pumpWidget(card(latest.future));
    stale.complete(_empty);
    await tester.pumpAndSettle();
    expect(find.byType(StatisticsBarRow), findsNWidgets(data.parts.length));
    latest.completeError(const FileSystemException('injected refresh failure'));
    await tester.pumpAndSettle();
    expect(find.byType(StatisticsBarRow), findsNWidgets(_labels.length));
    expect(
        tester
            .widgetList<StatisticsBarRow>(find.byType(StatisticsBarRow))
            .every((row) => row.valueLabel == '—' && row.value == 0),
        isTrue);
    expect(
        find.text('${formatLibraryBytes(data.bytes)} · ${ui('{0} 个文件', [
              data.files
            ])}'),
        findsNothing);
    expect(find.text(ui('无法读取此目录的占用信息')), findsOneWidget);
    expect(find.byIcon(Symbols.hourglass_empty), findsNothing);
    await _selectScope(tester, DirectoryStorageScope.cache);
    expect(find.text(ui('封面缓存')), findsOneWidget,
        reason: 'A failed player refresh must not clear the cache snapshot');
    await tester
        .tap(find.byKey(const ValueKey('directory-storage-scope-player')));
    await tester.pump();
    expect(find.byType(StatisticsBarRow), findsNWidgets(_labels.length));
    expect(
        tester
            .widgetList<StatisticsBarRow>(find.byType(StatisticsBarRow))
            .every((row) => row.valueLabel == '—' && row.value == 0),
        isTrue);
    expect(find.text(ui('无法读取此目录的占用信息')), findsOneWidget,
        reason: 'Returning to a failed scope must not revive its old data');
    final abandoned = Completer<AppDataStorageSnapshot>();
    await tester.pumpWidget(card(abandoned.future));
    expect(find.text(ui('无法读取此目录的占用信息')), findsNothing,
        reason: 'A new reading must not inherit a retired FutureBuilder error');
    expect(find.text(ui('正在读取占用信息…')), findsOneWidget);
    expect(find.byIcon(Symbols.hourglass_empty), findsOneWidget);
    expect(find.byType(StatisticsBarRow), findsNWidgets(_labels.length));
    expect(
        tester
            .widgetList<StatisticsBarRow>(find.byType(StatisticsBarRow))
            .every((row) => row.valueLabel == '—' && row.value == 0),
        isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    abandoned.completeError(const FileSystemException('after unmount'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('native chips expose selection and retain keyboard focus',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final cache = find.byKey(const ValueKey('directory-storage-scope-cache'));
      final player =
          find.byKey(const ValueKey('directory-storage-scope-player'));
      await tester.pumpWidget(_host(_card(Future.value(_snapshot()))));
      await tester.pumpAndSettle();
      expect(
          tester.getSemantics(cache),
          matchesSemantics(
              isSelected: true,
              hasSelectedState: true,
              isButton: true,
              hasEnabledState: true,
              isEnabled: true,
              isFocusable: true,
              hasTapAction: true,
              hasFocusAction: true,
              label: ui('缓存与播放器数据')));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focus = FocusManager.instance.primaryFocus;
      expect(focus, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(player).selected, isTrue);
      expect(FocusManager.instance.primaryFocus, same(focus),
          reason: 'Scope-specific data replacement must not recreate controls');
      expect(tester.getSemantics(player).flagsCollection.isSelected,
          raster.Tristate.isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('multiline native check has no artificial avatar background',
      (tester) async {
    final previous = uiLanguage.value;
    uiLanguage.value = UiLanguage.en;
    addTearDown(() => uiLanguage.value = previous);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    final cache = find.byKey(const ValueKey('directory-storage-scope-cache'));
    await tester.pumpWidget(_host(_card(Future.value(_snapshot())),
        language: UiLanguage.en, scale: 2, boundary: boundary));
    await tester.pumpAndSettle();
    final chip = tester.widget<ChoiceChip>(cache);
    // RawChip's AnimatedSwitcher centers the empty child in its avatar slot.
    final avatar = Rect.fromCenter(
        center: tester.getCenter(
            find.descendant(of: cache, matching: find.byWidget(chip.avatar!))),
        width: chip.avatarBoxConstraints!.maxWidth,
        height: chip.avatarBoxConstraints!.maxHeight);
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final origin = render.localToGlobal(Offset.zero);
    await _capture(tester, boundary, 'storage-native-check-360-200');
    await tester.runAsync(() async {
      final image = await render.toImage();
      try {
        final bytes =
            await image.toByteData(format: raster.ImageByteFormat.rawRgba);
        final rgba = bytes!.buffer.asUint8List();
        List<int> pixel(Offset point) {
          final offset = point - origin;
          final index =
              (offset.dy.floor() * image.width + offset.dx.floor()) * 4;
          return rgba.sublist(index, index + 4);
        }

        final background = pixel(
            avatar.topLeft + Offset(avatar.width * .05, avatar.height * .05));
        // Above the native check strokes, but inside the circular scrim that
        // RawChip would otherwise paint for a dummy avatar.
        expect(
            pixel(avatar.topLeft +
                Offset(avatar.width * .5, avatar.height * .12)),
            background);
        var ink = 0;
        for (var y = avatar.top.ceil(); y < avatar.bottom.floor(); y++) {
          for (var x = avatar.left.ceil(); x < avatar.right.floor(); x++) {
            final color = pixel(Offset(x.toDouble(), y.toDouble()));
            if (color.toString() != background.toString()) ink++;
          }
        }
        expect(ink, greaterThan(10),
            reason: 'The SDK check strokes must still be genuinely painted');
      } finally {
        image.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('unselected chips match native spacing throughout switches',
      (tester) async {
    final previous = uiLanguage.value;
    addTearDown(() => uiLanguage.value = previous);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const referenceKey = ValueKey('native-unselected-chip');
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final layout in [(1000.0, 1.0), (360.0, 2.0)]) {
        tester.view.physicalSize = Size(layout.$1, 1400);
        final boundary = GlobalKey();
        await tester.pumpWidget(_host(
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(
                  alignment: Alignment.centerRight,
                  child: ChoiceChip(
                      key: referenceKey,
                      label: const Text('Native control'),
                      selected: false,
                      onSelected: (_) {})),
              _card(Future.value(_empty)),
            ]),
            language: language,
            scale: layout.$2,
            boundary: boundary));
        await tester.pumpAndSettle();
        final reference = tester.getRect(find.byKey(referenceKey));
        final referenceText = tester.getRect(find.descendant(
            of: find.byKey(referenceKey),
            matching: find.text('Native control')));
        final nativeInset = referenceText.left - reference.left;
        void check() {
          for (final item in [
            (DirectoryStorageScope.cache, ui('缓存与播放器数据')),
            (DirectoryStorageScope.player, ui('播放器目录')),
          ]) {
            final finder =
                find.byKey(ValueKey('directory-storage-scope-${item.$1.name}'));
            final chip = tester.widget<ChoiceChip>(finder);
            _completeLabel(tester, finder, item.$2);
            if (!chip.selected) {
              final bounds = tester.getRect(finder);
              final text = tester.getRect(
                  find.descendant(of: finder, matching: find.text(item.$2)));
              expect(text.left - bounds.left, closeTo(nativeInset, .1),
                  reason: 'An unselected ${language.code} chip must have '
                      'native padding, with no invisible check slot');
              expect(text.center.dx, closeTo(bounds.center.dx, .1));
            }
          }
          expect(tester.takeException(), isNull);
        }

        check();
        for (final scope in [
          DirectoryStorageScope.player,
          DirectoryStorageScope.cache,
        ]) {
          await tester.tap(
              find.byKey(ValueKey('directory-storage-scope-${scope.name}')));
          await tester.pump();
          check();
          final first = [
            for (final item in DirectoryStorageScope.values)
              tester.getRect(
                  find.byKey(ValueKey('directory-storage-scope-${item.name}'))),
          ];
          await _capture(tester, boundary,
              'check-${language.code}-${layout.$1.toInt()}-${scope.name}-first');
          await tester.pump(const Duration(milliseconds: 75));
          check();
          for (final item in DirectoryStorageScope.values) {
            expect(
                tester.getRect(find
                    .byKey(ValueKey('directory-storage-scope-${item.name}'))),
                first[item.index],
                reason: 'No reverse drawer may expand to multiline height');
          }
          await _capture(tester, boundary,
              'check-${language.code}-${layout.$1.toInt()}-${scope.name}-middle');
          await tester.pump(const Duration(milliseconds: 160));
          check();
          for (final item in DirectoryStorageScope.values) {
            expect(
                tester.getRect(find
                    .byKey(ValueKey('directory-storage-scope-${item.name}'))),
                first[item.index]);
          }
          await tester.pumpAndSettle();
        }
      }
    }
  });
}
