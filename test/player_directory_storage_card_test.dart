import 'dart:async';
import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_data_storage_card.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/directory_storage_card.dart';
import 'package:dan_player/component/statistics_bar_row.dart';
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
  if (find.byKey(key).hitTestable().evaluate().isEmpty) {
    final control = find.byKey(const ValueKey('directory-storage-scope'));
    await tester.ensureVisible(control);
    await tester.tap(control);
    await tester.pumpAndSettle();
    for (final label in [ui('缓存与播放器数据'), ui('播放器目录')]) {
      final row = find.widgetWithText(MenuItemButton, label);
      final panel = tester.getRect(find
          .ancestor(
              of: row,
              matching: find.byWidgetPredicate((widget) =>
                  widget is Material && widget.type == MaterialType.canvas))
          .first);
      expect(panel.left, greaterThanOrEqualTo(-.1));
      expect(
          panel.right, lessThanOrEqualTo(tester.view.physicalSize.width + .1));
      _completeLabel(tester, row, label);
    }
  }
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
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
          reason: 'The complete category must fit its painted row: $label');
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
    expect(find.byType(StatisticsBarRow), findsNothing);
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

  testWidgets(
      'empty installation reports zero rather than fabricated categories',
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
    expect(find.byType(StatisticsBarRow), findsNothing);
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
}
