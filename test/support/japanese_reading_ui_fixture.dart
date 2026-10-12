import 'dart:async';
import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/japanese_dictionary_module_install.dart';
import 'package:dan_player/library/japanese_dictionary_runtime.dart';
import 'package:dan_player/lyric/japanese_reading_batch.dart';
import 'package:dan_player/lyric/japanese_reading_analyzer.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final japaneseUiQa = p.join(Directory.current.parent.path, 'tool', 'qa-local',
    'lyric-settings-feedback-oct11', 'ui', 'japanese');
const _provider = MethodChannel('plugins.flutter.io/path_provider');

Future<void> setUpJapaneseUiFixture() async {
  expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
  expect(Directory.systemTemp.absolute.path.replaceAll('\\', '/'),
      contains('/tool/qa-local/'));
  final data = Directory(p.join(japaneseUiQa, 'data'));
  await data.create(recursive: true);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_provider, (_) async => data.path);
  expect(p.isWithin(data.path, (await getAppDataDir()).path), isTrue);
  for (final language in UiLanguage.values) {
    await ensureAppFontsLoaded(AppFontPolicy.defaults(language: language));
  }
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

void tearDownJapaneseUiFixture() =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_provider, null);

Future<void> mountJapaneseUi(WidgetTester tester, Widget child,
    {UiLanguage language = UiLanguage.zh,
    double width = 1000,
    double scale = 1,
    bool reduced = true,
    GlobalKey<NavigatorState>? navigator,
    GlobalKey? boundary}) async {
  uiLanguage.value = language;
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final policy = AppFontPolicy.defaults(language: language);
  await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      debugShowCheckedModeBanner: false,
      theme: Entry(welcome: false)
          .fromSchemeAndFontFamily(
              fontFamily: policy.uiFamily,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.blue,
                  brightness: width > 560 ? Brightness.dark : Brightness.light))
          .copyWith(platform: TargetPlatform.windows),
      builder: (context, content) => RepaintBoundary(
          key: boundary,
          child: UiLanguageScope(
              child: AppFontScope(
                  policy: policy,
                  child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(scale),
                          disableAnimations: reduced),
                      child: content!)))),
      home: Scaffold(
          body: SingleChildScrollView(
              child:
                  Padding(padding: const EdgeInsets.all(16), child: child)))));
  await tester.pumpAndSettle();
}

Future<void> captureJapaneseUi(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final output = Platform.environment['DAN_JAPANESE_UI_RENDER_DIR'];
  if (output == null || output.isEmpty) return;
  final directory = p.normalize(p.absolute(output));
  expect(p.isWithin(p.normalize(japaneseUiQa), directory), isTrue);
  await tester.runAsync(() async {
    await Directory(directory).create(recursive: true);
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: raster.ImageByteFormat.png);
      await File(p.join(directory, '$name.png'))
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

/// Inspect actual graphemes in user text, including supplementary characters.
/// Selection line metrics may extend outside a paragraph's tight height; the
/// real dialog viewport is the clipping boundary.
Future<void> expectJapaneseUiText(WidgetTester tester, Finder scope) async {
  final texts = find.descendant(of: scope, matching: find.byType(Text));
  for (final element in texts.evaluate().toList()) {
    final widget = element.widget as Text;
    final value = widget.data;
    if (value == null || value.trim().isEmpty) continue;
    final finder = find.byWidget(widget);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: finder, matching: find.byType(RichText)));
    // Material input hints can be explicitly single-line. Check the rendered
    // glyphs and actual overflow, rather than rejecting a harmless text style.
    expect(paragraph.didExceedMaxLines, isFalse, reason: value);
    final paragraphRect = MatrixUtils.transformRect(
        paragraph.getTransformTo(null), Offset.zero & paragraph.size);
    var offset = 0;
    for (final cluster in value.characters) {
      final start = offset;
      offset += cluster.length;
      if (cluster.trim().isEmpty) continue;
      final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: offset));
      expect(boxes, isNotEmpty, reason: '$value: $cluster');
      for (final box in boxes) {
        final rect = MatrixUtils.transformRect(
            paragraph.getTransformTo(null), box.toRect());
        expect(rect.width, greaterThan(0), reason: value);
        expect(rect.left, greaterThanOrEqualTo(paragraphRect.left - .5),
            reason: value);
        expect(rect.right, lessThanOrEqualTo(paragraphRect.right + .5),
            reason: value);
        expect(rect.left, greaterThanOrEqualTo(-.5), reason: value);
        expect(
            rect.right, lessThanOrEqualTo(tester.view.physicalSize.width + .5),
            reason: value);
        expect(rect.top, greaterThanOrEqualTo(-.5), reason: value);
        expect(rect.bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height + .5),
            reason: value);
      }
    }
  }
  expect(tester.takeException(), isNull);
}

class UiBatch extends JapaneseReadingBatch {
  int starts = 0, cancels = 0, disposals = 0;
  JapaneseReadingRequestMode? lastMode;

  @override
  Future<void> start(
      {JapaneseReadingRequestMode mode =
          JapaneseReadingRequestMode.automatic}) async {
    if (running) return;
    starts++;
    lastMode = mode;
    running = scanning = true;
    cancelling = false;
    status = '正在读取已缓存歌词…';
    notifyListeners();
  }

  @override
  void cancel() {
    if (!running || cancelling) return;
    cancels++;
    running = scanning = false;
    cancelling = true;
    status = '已取消，已生成的假名缓存会保留。';
    notifyListeners();
  }

  void missingDictionary() {
    running = scanning = cancelling = false;
    status = '需要日语假名字典组件';
    notifyListeners();
  }

  void finish() {
    running = scanning = cancelling = false;
    total = completed = 4;
    generated = 1;
    skipped = 2;
    failed = 1;
    status = '批量生成日语假名完成';
    notifyListeners();
  }

  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

class UiDictionaryRuntime extends JapaneseDictionaryRuntime {
  bool ready = false;
  int inspections = 0;
  Completer<bool>? inspection;

  @override
  Future<Directory> get installDirectory async =>
      Directory(p.join(japaneseUiQa, 'dictionary'));

  @override
  Future<bool> inspect() async {
    inspections++;
    if (inspection != null) return await inspection!.future;
    return ready;
  }
}

class UiDictionaryInstaller extends JapaneseDictionaryModuleInstaller {
  UiDictionaryInstaller(UiDictionaryRuntime runtime) : super(runtime: runtime);
  final completion = Completer<void>();
  int starts = 0, cancels = 0;
  void Function(double?)? reportProgress;
  void Function(String)? reportStage;

  @override
  Future<void> install(
      {required void Function(double?) progress,
      void Function(String)? onStage}) async {
    starts++;
    reportProgress = progress;
    reportStage = onStage;
    onStage?.call('正在下载日语假名字典…');
    await completion.future;
  }

  @override
  void cancel() => cancels++;
}
