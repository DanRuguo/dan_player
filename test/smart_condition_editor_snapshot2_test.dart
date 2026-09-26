import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/smart_condition_editor.dart';
import 'package:dan_player/component/smart_playlist_dialog.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/smart_condition.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends SmartPlaylistStore {
  _Store(this.rule) : super(File('unused-smart-snapshot2-store'));
  final SmartPlaylist rule;
  @override
  Future<List<SmartPlaylist>> list() async => [rule];
}

Widget host(Widget child, {bool dark = false, double scale = 1}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: Entry(welcome: false).fromSchemeAndFontFamily(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: dark ? Brightness.dark : Brightness.light),
        fontFamily: danEmbeddedFontFamily),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: UiLanguageScope(child: child!)),
    home: Scaffold(body: child));

void main() {
  setUpAll(() async {
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
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      final bytes = await korean.readAsBytes();
      await (FontLoader('Malgun Gothic')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets(
      'new grouped count rules refresh on history changes and cancel on close',
      (tester) async {
    final stats = PlaybackStatistics.inMemory();
    addTearDown(stats.dispose);
    final audio = Audio.fromMap({
      'path': r'C:\synthetic\piano.flac',
      'title': 'Piano',
      'duration': 180
    });
    var evaluations = 0;
    const rule = SmartPlaylist(
        id: 'count',
        name: 'Listen again',
        condition: SmartCondition.term(SmartField.playCountAtLeast, '1'));
    await tester.pumpWidget(host(SmartPlaylistsDialog(
        loadStore: () async => _Store(rule),
        library: () => [audio],
        statistics: stats,
        evaluate: (_, __) async {
          evaluations++;
          return [];
        })));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('smart-rule-count')));
    await tester.pumpAndSettle();
    expect(evaluations, 1);
    stats.start(audio);
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pumpAndSettle();
    expect(evaluations, 2);
    await tester.tap(find.byTooltip(ui('返回')));
    await tester.pumpAndSettle();
    await stats.initialize();
    await tester.pump(const Duration(milliseconds: 550));
    expect(evaluations, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('nested condition buttons respect the whole rule leaf budget',
      (tester) async {
    await tester.pumpWidget(host(SingleChildScrollView(
        child: SmartConditionEditor(
            value: SmartCondition.group([
              const SmartCondition.group(
                  [SmartCondition.term(SmartField.titleContains, 'night')]),
              ...List.generate(
                  31,
                  (_) =>
                      const SmartCondition.term(SmartField.formatIs, 'flac')),
            ]),
            onChanged: (_) {}))));
    await tester.pumpAndSettle();
    final addButtons = find.ancestor(
        of: find.byIcon(Icons.add), matching: find.byType(OutlinedButton));
    expect(addButtons, findsNWidgets(2));
    for (final button in tester.widgetList<OutlinedButton>(addButtons)) {
      expect(button.onPressed, isNull);
    }
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'grouped metadata ${language.name} ${narrow ? 'narrow' : 'wide'} layout',
          (tester) async {
        uiLanguage.value = language;
        tester.view.physicalSize =
            narrow ? const Size(380, 700) : const Size(840, 980);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final capture = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: capture,
            child: host(
                AlertDialog(
                  title: AppDialogTitle(ui('筛选规则')),
                  content: SizedBox(
                      width: 640,
                      child: SingleChildScrollView(
                          child: SmartConditionEditor(
                              value: const SmartCondition.group([
                                SmartCondition.term(
                                    SmartField.titleContains, 'Night'),
                                SmartCondition.term(
                                    SmartField.folderWithin, r'C:\Music\Piano'),
                                SmartCondition.term(
                                    SmartField.playCountAtMost, '3',
                                    exclude: true),
                                SmartCondition.term(
                                    SmartField.sampleRateAtLeast, '48000'),
                              ], any: true),
                              onChanged: (_) {}))),
                  actions: [
                    FilledButton(onPressed: () {}, child: Text(ui('保存规则')))
                  ],
                ),
                dark: narrow,
                scale: narrow ? 1.6 : 1)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(ui('位于文件夹（含子目录）')), findsOneWidget);
        for (final label in ['标题包含', '位于文件夹（含子目录）']) {
          final paragraph =
              tester.renderObject<RenderParagraph>(find.text(ui(label)));
          expect(paragraph.didExceedMaxLines, isFalse);
        }
        const export = String.fromEnvironment('DAN_SMART_S2_RENDER');
        Future<void> render(String suffix) async {
          if (export.isEmpty) return;
          await tester.runAsync(() async {
            final image = await (capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: raster.ImageByteFormat.png);
            final file = File('$export/smart-${language.name}-$suffix.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await render(narrow ? 'narrow' : 'wide');
        if (narrow) {
          await tester.ensureVisible(find.text(ui('位于文件夹（含子目录）')));
          await tester.pumpAndSettle();
          await render('narrow-folder');
          await tester.ensureVisible(
              find.byType(DropdownButtonFormField<SmartField>).first);
          await tester.pumpAndSettle();
          await tester
              .tap(find.byType(DropdownButtonFormField<SmartField>).first);
          await tester.pumpAndSettle();
          final folder = find.text(ui('位于文件夹（含子目录）')).last;
          await tester.ensureVisible(folder);
          await tester.pumpAndSettle();
          final menuScroll = tester
              .stateList<ScrollableState>(find.byType(Scrollable))
              .reduce((a, b) =>
                  a.position.maxScrollExtent > b.position.maxScrollExtent
                      ? a
                      : b);
          menuScroll.position.jumpTo(menuScroll.position.maxScrollExtent * .5);
          await tester.pumpAndSettle();
          final paragraph = tester.renderObject<RenderParagraph>(folder);
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(tester.getRect(folder).right, lessThanOrEqualTo(380));
          expect(tester.takeException(), isNull);
          await render('menu');
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
