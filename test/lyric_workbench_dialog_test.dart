import 'dart:io';
import 'dart:ui' as ui;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/lyric_workbench_dialog.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _export = bool.fromEnvironment('DAN_EXPORT_LYRIC_WORKBENCH_UI');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  late Directory directory;
  late LyricDocumentStore store;
  late Audio audio;
  setUp(() async {
    final parent = await Directory(
            '${Platform.environment['DAN_PLAYER_DATA_DIR'] ?? '${Directory.current.path}/build/test-data'}/lyric-workbench')
        .create(recursive: true);
    directory = await parent.createTemp('isolated-');
    audio = Audio('星灯 · 夜空中的旋律（虚构测试歌曲）', '示例歌手', '示例专辑', 0, 180, null, null,
        '${directory.path}\\星灯 · 夜空中的旋律（虚构测试歌曲）.wav', 0, 0, null);
    store = LyricDocumentStore(storageDirectory: directory);
    await store.load();
  });
  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  Widget host(
          {double scale = 1,
          Brightness brightness = Brightness.light,
          GlobalKey? capture}) =>
      MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: Entry(welcome: false).fromSchemeAndFontFamily(
              colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff995741), brightness: brightness)),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(scale)),
              child: child!),
          home: RepaintBoundary(
              key: capture,
              child: Scaffold(
                  backgroundColor: brightness == Brightness.light
                      ? const Color(0xffe8e2df)
                      : const Color(0xff151210),
                  body: LyricWorkbenchDialog(
                      audio: audio,
                      store: store,
                      currentLyric: () => Lrc.fromLrcText(
                          '[00:01.00]星光落在安静的夜里', LrcSource.web)))));

  Future<void> settleSave(WidgetTester tester) async {
    await tester.runAsync(store.load);
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSave(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(ValueKey(key)));
      await store.load();
    });
    await tester.pumpAndSettle();
  }

  testWidgets('confirm, offset and no-lyric controls save one shared document',
      (tester) async {
    await tester.pumpWidget(host());
    await settleSave(tester);
    await tapAndSave(tester, 'lyric-document-lock');
    expect(store.forAudio(audio)!.locked, isTrue);
    await tapAndSave(tester, 'lyric-offset-later');
    expect(store.forAudio(audio)!.offsetMs, 500);
    expect(find.text('500'), findsOneWidget);
    await tapAndSave(tester, 'lyric-document-no-lyrics');
    expect(store.forAudio(audio)!.noLyrics, isTrue);
    expect(find.text('无歌词 · 不再自动查找'), findsOneWidget);
    expect(File(audio.path).existsSync(), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'typed offset is separate from saving and reset remains available',
      (tester) async {
    await tester.pumpWidget(host());
    await settleSave(tester);
    final field = find.byKey(const ValueKey('lyric-offset-value'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '-1250');
    expect(store.forAudio(audio), isNull);
    await tapAndSave(tester, 'lyric-offset-save');
    expect(store.forAudio(audio)!.offsetMs, -1250);
    await tapAndSave(tester, 'lyric-offset-reset');
    expect(store.forAudio(audio)!.offsetMs, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'failed offset save stays visible and does not report changed value',
      (tester) async {
    await tester.pumpWidget(host());
    await settleSave(tester);
    Directory('${directory.path}\\lyric_documents.json.$pid.tmp').createSync();
    await tapAndSave(tester, 'lyric-offset-later');
    expect(find.byKey(const ValueKey('lyric-document-error')), findsOneWidget);
    expect(store.forAudio(audio), isNull);
    expect(find.text('0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'narrow window and large text keep workbench scrollable without overflow',
      (tester) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(430, 610);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(scale: 1.8));
    await settleSave(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('保存偏移'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final scenario in [
    (
      name: 'light-wide',
      size: const Size(760, 1000),
      scale: 1.0,
      brightness: Brightness.light
    ),
    (
      name: 'dark-wide',
      size: const Size(760, 1000),
      scale: 1.0,
      brightness: Brightness.dark
    ),
    (
      name: 'light-short',
      size: const Size(560, 460),
      scale: 1.0,
      brightness: Brightness.light
    ),
    (
      name: 'dark-narrow-large',
      size: const Size(400, 700),
      scale: 1.8,
      brightness: Brightness.dark
    ),
  ]) {
    testWidgets('production layout and reachable actions: ${scenario.name}',
        (tester) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (scenario.brightness == Brightness.dark) {
        await tester.runAsync(() async {
          await store.setLocked(audio, true,
              current: Lrc.fromLrcText('[00:01.00]原始歌词', LrcSource.web));
          await store.edit(audio, '[00:01.50]已校准的歌词');
        });
      }
      final capture = GlobalKey();
      await tester.pumpWidget(host(
          capture: capture,
          scale: scenario.scale,
          brightness: scenario.brightness));
      await settleSave(tester);
      expect(tester.takeException(), isNull);

      final title = find.text('歌词校准与锁定');
      final close = find.byTooltip('关闭');
      final titleRect = tester.getRect(title);
      expect(titleRect.overlaps(tester.getRect(close)), isFalse);
      expect(titleRect.center.dx, closeTo(scenario.size.width / 2, 1));
      expect(
          tester.widget<Text>(title).style!.fontSize, greaterThanOrEqualTo(22));
      if (scenario.scale > 1) {
        expect(titleRect.top, greaterThan(tester.getRect(close).bottom));
        expect(titleRect.height, lessThan(64),
            reason:
                'The full-width large heading should fit one balanced line.');
      }
      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar).first);
      expect(scrollbar.thumbVisibility, isTrue);
      if (scenario.size.height < 800) {
        expect(scrollbar.controller!.position.maxScrollExtent, greaterThan(0));
      }

      if (_export) {
        await _capture(tester, capture, scenario.name);
      }
      final input = find.byKey(const ValueKey('lyric-offset-value'));
      final save = find.byKey(const ValueKey('lyric-offset-save'));
      final reset = find.byKey(const ValueKey('lyric-offset-reset'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(tester.getRect(save).top - tester.getRect(input).bottom,
          greaterThanOrEqualTo(16));
      expect(tester.getRect(save).overlaps(tester.getRect(reset)), isFalse);
      expect(tester.getSize(save).height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
      if (_export && scenario.size.height < 800) {
        await _capture(tester, capture, '${scenario.name}-offset');
      }

      for (final action in [
        find.byKey(const ValueKey('lyric-document-lock')),
        find.byKey(const ValueKey('lyric-document-no-lyrics')),
        find.text('编辑修订'),
        find.text('切换歌词来源'),
        if (scenario.brightness == Brightness.dark) ...[
          find.text('恢复原始歌词'),
          find.text('恢复之前的版本'),
        ],
      ]) {
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      if (_export && scenario.size.height < 800) {
        await _capture(tester, capture, '${scenario.name}-content');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final workspace = Platform.environment['DAN_PLAYER_WORKSPACE'] ??
          Directory.current.parent.path;
      final file = File(
          '$workspace/tool/qa-2605-snapshot2/ui-final/lyric-workbench-$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
}
