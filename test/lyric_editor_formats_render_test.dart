import 'package:dan_player/component/lyric_playback_preview.dart';
import 'package:dan_player/lyric/lyric_preview.dart';
import 'lyric_preview_test.dart' show ProcessFake;
import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/component/lyric_editor_dialog.dart';
import 'package:dan_player/component/lyric_timing_dialog.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:desktop_lyric/l10n/catalog_lyric_editor_formats.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
          ..addFont(rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
        .load();
    for (final entry in {
      'Malgun Gothic': 'malgun.ttf',
      'Segoe UI Emoji': 'seguiemj.ttf',
      'Segoe UI Symbol': 'seguisym.ttf'
    }.entries) {
      final file = File('C:/Windows/Fonts/${entry.value}');
      if (await file.exists()) {
        await (FontLoader(entry.key)
              ..addFont(
                  Future.value(ByteData.sublistView(await file.readAsBytes()))))
            .load();
      }
    }
  });

  test('new editor messages cover all four languages', () {
    for (final entry in catalogLyricEditorFormats.entries) {
      expect(entry.value.length, 3);
      for (final language
          in UiLanguage.values.where((l) => l != UiLanguage.zh)) {
        expect(translateUi(entry.key, language).isNotEmpty, isTrue,
            reason: '${language.name}: ${entry.key}');
      }
    }
  });
  for (final language in UiLanguage.values) {
    testWidgets(
        'editor ${language.name} aligned wide, narrow, preview, picker and timing',
        (tester) async {
      tester.view.physicalSize = const Size(1120, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = UiLanguage.zh);
      final boundary = GlobalKey();
      final theme = applyAppControlTheme(ThemeData(
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.orange, brightness: Brightness.dark)));
      final audio = Audio('光と夜 · Love song', '歌手 Artist', '专辑 Album', 0, 180,
          null, null, 'fixture.mp3', 0, 0, null);
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: UiLanguageScope(
                  child: Scaffold(
                      body: Builder(
                          builder: (context) => Center(
                              child: FilledButton(
                                  onPressed: () => showDialog<void>(
                                      context: context,
                                      builder: (_) => LyricEditorDialog(
                                          audio: audio,
                                          initialFormat: LyricEditFormat.qrc,
                                          localLyricLoader: (_) async =>
                                              '[00:01.001]光と夜\n[00:03.000]你好世界')),
                                  child: const Text('Open')))))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('lyric-editor-field'));
      await tester.enterText(field,
          '[1001,1499]光と(1001,499)夜🌙(1500,1000)\n[3000,1000]Hello (3000,400)world(3400,600)');
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        expect(tester.takeException(), isNull);
        const output = String.fromEnvironment('DAN_EDITOR_RENDER');
        if (output.isEmpty) return;
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes =
              await image.toByteData(format: drawing.ImageByteFormat.png);
          final file = File('$output/${language.name}-$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      void expectAuditionBelowEditor() {
        final editor = tester
            .getRect(find.byKey(const ValueKey('lyric-editor-compact-scroll')));
        final audition = tester.getRect(
            find.byKey(const ValueKey('lyric-editor-audition-visible')));
        final save =
            tester.getRect(find.byKey(const ValueKey('lyric-editor-save')));
        expect(editor.bottom, lessThanOrEqualTo(audition.top + 1));
        expect(audition.bottom, lessThanOrEqualTo(save.top));
      }

      Future<void> tapTab(int tab) async {
        final target = find.byKey(ValueKey('lyric-editor-tab-$tab'));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tester.testTextInput.receiveAction(TextInputAction.done);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await capture('wide');
      expectAuditionBelowEditor();
      await tapTab(1);
      await tester.enterText(find.byKey(const ValueKey('lyric-editor-aux-1')),
          '[00:01.001]光与夜\n[00:03.000]你好，世界');
      await tapTab(2);
      await tester.enterText(find.byKey(const ValueKey('lyric-editor-aux-2')),
          '[00:01.001]hikari to yoru');
      await tapTab(0);
      expect(tester.widget<TextField>(field).controller!.text,
          contains('夜🌙(1500,1000)'));
      await tapTab(3);
      await capture('preview');
      expect(find.text('hikari to yoru'), findsOneWidget);
      expect(find.text('光与夜'), findsOneWidget);
      await tapTab(1);
      tester.view.physicalSize = const Size(480, 740);
      await tester.pumpAndSettle();
      await capture('narrow');
      tester
          .widget<SingleChildScrollView>(
              find.byKey(const ValueKey('lyric-editor-compact-scroll')))
          .controller!
          .jumpTo(0);
      await tester.pumpAndSettle();
      await capture('audition-narrow');
      expectAuditionBelowEditor();
      final narrowEditor = tester
          .getRect(find.byKey(const ValueKey('lyric-editor-compact-scroll')));
      final narrowField =
          tester.getRect(find.byKey(const ValueKey('lyric-editor-aux-1')));
      expect(narrowField.top + 40, lessThan(narrowEditor.bottom));
      final saveRect =
          tester.getRect(find.byKey(const ValueKey('lyric-editor-save')));
      expect(saveRect.bottom, lessThanOrEqualTo(740));
      expect(saveRect.top, greaterThan(100));
      final formatButton = find.byKey(const ValueKey('lyric-editor-format'));
      await tester.ensureVisible(formatButton);
      await tester.tap(formatButton);
      await tester.pumpAndSettle();
      await capture('formats');
      // Choosing a lossy format must ask before replacing word timing.
      await tester.tap(find.byKey(const ValueKey('lyric-format-lrc')));
      await tester.pumpAndSettle();
      expect(find.text(translateUi('转换歌词格式？', language)), findsOneWidget);
      await capture('conversion-back');
      await tester.tap(find.byKey(const ValueKey('lyric-conversion-back')));
      await tester.pumpAndSettle();
      expect(find.text(translateUi('选择歌词编辑格式', language)), findsOneWidget);
      await tester.tap(find.text(translateUi('取消', language)).last);
      await tester.pumpAndSettle();
      await tapTab(0);
      expect(tester.widget<TextField>(field).controller!.text,
          contains('夜🌙(1500,1000)'));
      await tester.ensureVisible(formatButton);
      await tester.tap(formatButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lyric-format-lrc')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(translateUi('保留完整内容', language)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(formatButton);
      expect(find.text(translateUi(LyricEditFormat.qrc.label, language)),
          findsOneWidget);
      final context = tester.element(find.byType(LyricEditorDialog));
      final timeResult =
          showLyricTimingDialog(context, startMs: 1001, endMs: 2500);
      await tester.pumpAndSettle();
      await capture('timing');
      await tester.enterText(
          find.byKey(const ValueKey('lyric-time-end')), '900');
      await tester.tap(find.text(translateUi('应用', language)));
      await tester.pumpAndSettle();
      expect(find.text(translateUi('请输入有效起止时间（0 至 86400000 毫秒）', language)),
          findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('lyric-time-end')), '2500');
      await tester.tap(find.text(translateUi('应用', language)));
      await tester.pumpAndSettle();
      expect(await timeResult, (1001, 2500));
      tester.view.physicalSize = const Size(640, 420);
      await tester.pumpAndSettle();
      await capture('short');
      tester
          .widget<SingleChildScrollView>(
              find.byKey(const ValueKey('lyric-editor-compact-scroll')))
          .controller!
          .jumpTo(0);
      await tester.pumpAndSettle();
      await capture('audition-short');
      expectAuditionBelowEditor();
      final editorScroll = tester.widget<SingleChildScrollView>(
          find.byKey(const ValueKey('lyric-editor-compact-scroll')));
      editorScroll.controller!
          .jumpTo(editorScroll.controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
          tester.getRect(field).bottom,
          lessThanOrEqualTo(tester
                  .getRect(
                      find.byKey(const ValueKey('lyric-editor-compact-scroll')))
                  .bottom +
              1));
      await capture('audition-short-bottom');
      final save =
          tester.getRect(find.byKey(const ValueKey('lyric-editor-save')));
      expect(save.bottom, lessThanOrEqualTo(420));
      expect(
          save.overlaps(
              tester.getRect(find.byKey(const ValueKey('lyric-editor-close')))),
          isFalse);
      tester.view.physicalSize = const Size(700, 760);
      await tester.pumpAndSettle();
      final preview = LyricAudioPreview(audio,
          probeDuration: (_) async => audio.duration.toDouble(),
          mainPlayback: () => null,
          launch: (_, __, ___, clock) async {
            clock(1.6);
            return ProcessFake();
          });
      addTearDown(preview.dispose);
      final dialog = showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => LyricPlaybackPreview(
              audio: audio,
              lyric: lyricEditingExample(LyricEditFormat.qrc).parse(),
              line: 0,
              preview: preview,
              ensureTools: () async => true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
      await preview.pause();
      await tester.pump(const Duration(milliseconds: 400));
      await capture('live-preview');
      tester.view.physicalSize = const Size(560, 420);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      await capture('live-short');
      expect(find.text(translateUi('逐句试听', language)), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lyric-preview-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await dialog;
    });
  }
  testWidgets('entry point asks for a format before reading any lyrics',
      (tester) async {
    final audio = Audio('Song', 'Artist', 'Album', 0, 120, null, null,
        'missing.mp3', 0, 0, null);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showLyricEditorDialog(context, audio),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('你想如何编辑歌词😋？'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lyric-method-text')));
    await tester.pumpAndSettle();
    expect(find.text('选择歌词编辑格式'), findsOneWidget);
    expect(find.byType(LyricEditorDialog), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(LyricEditorDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'plain text hides timing and preview, example requires confirmation before replacing edits',
      (tester) async {
    final audio = Audio(
        'Song', 'Artist', 'Album', 0, 10, null, null, 'demo.mp3', 0, 0, null);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LyricEditorDialog(
                audio: audio,
                initialFormat: LyricEditFormat.plain,
                localLyricLoader: (_) async => ''))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyric-editor-tab-3')), findsNothing);
    expect(
        find.byKey(const ValueKey('lyric-editor-insert-time')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('lyric-editor-example')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('lyric-editor-field'));
    expect(tester.widget<TextField>(field).controller!.text,
        contains('Hello world'));
    await tester.enterText(field, 'My draft');
    await tester
        .ensureVisible(find.byKey(const ValueKey('lyric-editor-example')));
    await tester.tap(find.byKey(const ValueKey('lyric-editor-example')));
    await tester.pumpAndSettle();
    expect(find.text('替换编辑中的内容？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, 'My draft');
  });
}
