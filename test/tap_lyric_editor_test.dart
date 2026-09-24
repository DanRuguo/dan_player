import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/component/tap_lyric_editor.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric_preview.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/tap_lyric_session.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:desktop_lyric/l10n/catalog_tap_lyric_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'lyric_preview_test.dart' show ProcessFake;

final song = Audio('爱如火 · Love song', '歌手 Artist', 'Album', 0, 8, null, null,
    'test.mp3', 0, 0, null);
TapLyricSession fixture(TapStage stage) {
  final s = TapLyricSession()
    ..text = '你好吗 Hello world|How are you? 你好|ni hao ma\n青い鳥|蓝色的鸟|aoi tori';
  if (stage == TapStage.text) return s;
  s.beginLines();
  if (stage == TapStage.lines) return s;
  s.mark(.5);
  s.mark(3);
  if (stage == TapStage.lineReview) return s;
  s.accept();
  s.mark(4);
  s.mark(7);
  s.accept();
  if (stage == TapStage.lineDone) return s;
  s.beginWords();
  s.wordStarted = true;
  s.mark(1);
  if (stage == TapStage.words) return s;
  while (s.stage == TapStage.words) {
    s.mark(s.row.wordEnds.last + .4);
  }
  if (stage == TapStage.wordReview) return s;
  s.accept();
  s.wordStarted = true;
  s.mark(5);
  s.mark(6);
  s.mark(7);
  s.accept();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      danEmbeddedFontFamily: 'assets/fonts/PingFangSC-Regular.ttf',
      'packages/material_symbols_icons/MaterialSymbolsOutlined':
          'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value)))
          .load();
    }
    for (final entry in {
      'Malgun Gothic': 'malgun.ttf',
      'Segoe UI Emoji': 'seguiemj.ttf'
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
  test('tap workflow messages cover four languages with matching placeholders',
      () {
    for (final e in catalogTapLyricEditor.entries) {
      expect(e.value.length, 3);
      for (final translated in e.value) {
        expect(translated.trim(), isNotEmpty);
        expect(
            RegExp(r'\{\d+\}').allMatches(translated).map((m) => m[0]).toSet(),
            RegExp(r'\{\d+\}').allMatches(e.key).map((m) => m[0]).toSet());
      }
    }
  });
  Future<void> pumpEditor(WidgetTester tester, TapLyricSession session,
      {LyricAudioPreview? preview,
      Future<bool> Function(Lyric)? saveLyric,
      GlobalKey? boundary,
      ValueNotifier<RenderingPreferences>? rendering}) async {
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: applyAppControlTheme(ThemeData(
                fontFamily: danEmbeddedFontFamily,
                fontFamilyFallback: danFontFamilyFallback,
                colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.orange, brightness: Brightness.dark))),
            home: RenderingPreferencesScope(
                preferences: rendering ??
                    const AlwaysStoppedAnimation(RenderingPreferences()),
                child: UiLanguageScope(
                    child: Scaffold(
                        body: TapLyricEditor(
                            audio: song,
                            initialSession: session,
                            preview: preview ??
                                LyricAudioPreview(song,
                                    mainPlayback: () => null,
                                    launch: (_, __, ___, ____) async =>
                                        ProcessFake()),
                            ensureTools: () async => true,
                            fetchOnline: () async => null,
                            saveLyric: saveLyric ?? (_) async => false)))))));
    await tester.pumpAndSettle();
  }

  testWidgets('plain-text save strips auxiliary columns after confirmation',
      (tester) async {
    final session = TapLyricSession()..text = '你好|Hello|ni hao\n世界||shi jie';
    PlainLyric? saved;
    await pumpEditor(tester, session, saveLyric: (lyric) async {
      saved = lyric as PlainLyric;
      return false;
    });
    await tester.tap(find.text('保存纯文本歌词'));
    await tester.pumpAndSettle();
    expect(find.text('仅保存正文？'), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(saved, isNull);
    await tester.tap(find.text('保存纯文本歌词'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅保存正文'));
    await tester.pumpAndSettle();
    expect(saved?.text, '你好\n世界');
  });

  for (final lang in UiLanguage.values) {
    testWidgets(
        'tap ${lang.name} renders every stage, method and exit at narrow and wide sizes',
        (tester) async {
      uiLanguage.value = lang;
      addTearDown(() => uiLanguage.value = UiLanguage.zh);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      Future<void> capture(GlobalKey key, String name) async {
        expect(tester.takeException(), isNull);
        const dir = String.fromEnvironment('DAN_TAP_RENDER');
        if (dir.isEmpty) return;
        await tester.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final data =
              await image.toByteData(format: drawing.ImageByteFormat.png);
          final file = File('$dir/${lang.name}-$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      for (final size in [const Size(1100, 850), const Size(480, 640)]) {
        tester.view.physicalSize = size;
        for (final stage in TapStage.values) {
          final key = GlobalKey();
          await pumpEditor(tester, fixture(stage), boundary: key);
          await capture(key, '${stage.name}-${size.width.toInt()}');
          if (stage == TapStage.words && size.width == 480) {
            await tester.tap(find.byKey(const ValueKey('tap-rate')));
            await tester.pumpAndSettle();
            await capture(key, 'rate-menu');
            await tester.tap(find.text('0.75x'));
            await tester.pumpAndSettle();
            expect(
                find.descendant(
                    of: find.byKey(const ValueKey('tap-rate')),
                    matching: find.text('0.75x')),
                findsOneWidget);
          }
          if (stage == TapStage.lines) {
            expect(
                tester.getRect(find.byKey(const ValueKey('tap-mark'))).bottom,
                lessThan(tester
                    .getRect(find.byKey(const ValueKey('tap-save-progress')))
                    .top));
          }
          expect(
              find.byKey(const ValueKey('tap-save-progress')), findsOneWidget);
          expect(
              tester
                  .getRect(find.byKey(const ValueKey('tap-save-progress')))
                  .bottom,
              lessThanOrEqualTo(size.height));
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        }
      }
      final key = GlobalKey();
      await pumpEditor(tester, fixture(TapStage.text), boundary: key);
      final context = tester.element(find.byType(TapLyricEditor));
      final selection = chooseLyricEditingMethod(context);
      await tester.pumpAndSettle();
      await capture(key, 'method');
      await tester.tap(find.text(translateUi('取消', lang)).last);
      await tester.pumpAndSettle();
      await selection;
      await tester.tap(find.text(translateUi('退出', lang)));
      await tester.pumpAndSettle();
      await capture(key, 'exit');
      await tester.tap(find.text(translateUi('继续编辑', lang)));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('tap-text')))
              .controller!
              .text,
          fixture(TapStage.text).text);
    });
  }
  testWidgets(
      'Space freezes recording, Enter ignores pause and review starts at previous end',
      (tester) async {
    final s = TapLyricSession()..text = 'one\ntwo';
    s.beginLines();
    late void Function(double) clock;
    final launches = <(double, double)>[];
    final player = LyricAudioPreview(song,
        mainPlayback: () => null,
        launch: (_, start, duration, c) async {
          launches.add((start, duration));
          clock = c;
          return ProcessFake();
        });
    await pumpEditor(tester, s, preview: player);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(player.playing, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
        s.row.start, isNull); // No timestamp before the audio clock is ready.
    clock(.5);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(s.row.start, .5);
    clock(1);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(player.playing, isFalse);
    expect(s.position, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(s.row.end, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(launches.last.$1, 1);
    clock(2);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(s.stage, TapStage.lineReview);
    expect(launches.last, (0, 2.5));
    await tester.tap(find.byKey(const ValueKey('tap-accept')));
    await tester.pumpAndSettle();
    expect(s.index, 1);
    expect(s.position, 1.5);
    expect(player.playing, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(launches.last.$1, 1.5);
    clock(3);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    clock(4);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final view = tester
        .widget<VerticalLyricScrollView>(find.byType(VerticalLyricScrollView));
    expect(lyricLineText(view.lyric.lines.single), 'two');
    expect(launches.last, (2, 2.5));
  });
  testWidgets(
      'word highlight advances by Enter and end of song never completes unfinished text',
      (tester) async {
    final s = fixture(TapStage.words);
    late void Function(double) clock;
    late ProcessFake process;
    final player = LyricAudioPreview(song,
        mainPlayback: () => null,
        launch: (_, __, ___, c) async {
          clock = c;
          return process = ProcessFake();
        });
    await pumpEditor(tester, s, preview: player);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    clock(1.4);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(s.row.wordEnds, [1, 1.4]);
    process.done.complete(0);
    await tester.pumpAndSettle();
    expect(s.stage, TapStage.words);
    expect(s.row.wordEnds.length, 2);
    expect(find.text('音乐已到句尾，请重录本句；未完成的字不会自动确认。'), findsOneWidget);
  });
  testWidgets(
      'saved paused word progress resumes without restarting text or auto-playing',
      (tester) async {
    late Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('tap-ui-');
    });
    addTearDown(() async {
      await dir.delete(recursive: true);
    });
    final store = TapProgressStore(dir, 'resume-song');
    final saved = fixture(TapStage.words)
      ..position = 1.25
      ..rate = .5
      ..mediaDuration = 8;
    await tester.runAsync(() => store.save(saved));
    final player = LyricAudioPreview(song,
        mainPlayback: () => null,
        launch: (_, __, ___, ____) async => ProcessFake());
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TapLyricEditor(
                audio: song,
                preview: player,
                progressStore: store,
                ensureTools: () async => true,
                fetchOnline: () async => null,
                saveLyric: (_) async => false))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('加载上次进度'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('加载上次进度'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tap-text')), findsNothing);
    expect(player.playing, isFalse);
    expect(find.text('00:01.250 / 00:08.000'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('tap-rate')),
            matching: find.text('0.5x')),
        findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('tap-save-progress')));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    late TapLyricSession restored;
    await tester.runAsync(() async {
      restored = (await store.load())!;
    });
    expect(restored.stage, TapStage.words);
    expect(restored.index, 0);
    expect(restored.row.wordEnds, [1]);
    expect(restored.position, 1.25);
    expect(restored.wordStarted, isTrue);
  });
  testWidgets(
      'song EOF warns about text and version, editing text needs confirmation',
      (tester) async {
    final s = TapLyricSession()..text = 'one\ntwo';
    s.beginLines();
    late ProcessFake process;
    final player = LyricAudioPreview(song,
        mainPlayback: () => null,
        launch: (_, __, ___, ____) async => process = ProcessFake());
    await pumpEditor(tester, s, preview: player);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    process.done.complete(0);
    await tester.pumpAndSettle();
    expect(s.stage, TapStage.lines);
    expect(s.row.start, isNull);
    expect(
        find.text('歌曲已结束，但歌词尚未完成。请检查歌词文本与歌曲版本是否一致，或本句打点是否有误。'), findsOneWidget);
    await tester.tap(find.byTooltip('返回修改文本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tap-text')), findsNothing);
    await tester.tap(find.byTooltip('返回修改文本'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '返回修改文本'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('tap-text')))
            .controller!
            .text,
        'one\ntwo');
  });
  testWidgets(
      'animation preferences change feedback immediately without changing tap times',
      (tester) async {
    final prefs = ValueNotifier(const RenderingPreferences());
    addTearDown(prefs.dispose);
    final s = fixture(TapStage.words);
    late void Function(double) clock;
    final player = LyricAudioPreview(song,
        mainPlayback: () => null,
        launch: (_, __, ___, c) async {
          clock = c;
          return ProcessFake();
        });
    await pumpEditor(tester, s, preview: player, rendering: prefs);
    final word = find.descendant(
        of: find.byKey(const ValueKey('tap-word-1')),
        matching: find.byType(AnimatedContainer));
    expect(tester.widget<AnimatedContainer>(word).duration, AppMotion.quick);
    prefs.value =
        prefs.value.copyWith(animations: const MotionPreferences().all(false));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedContainer>(word).duration, Duration.zero);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    clock(1.337);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(s.row.wordEnds.last, 1.337);
    prefs.value = prefs.value.copyWith(animations: const MotionPreferences());
    await tester.pumpAndSettle();
    clock(1.751);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(s.row.wordEnds.last, 1.751);
  });
}
