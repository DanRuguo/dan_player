import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/lyric/local_lyric_reader.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_source_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:desktop_lyric/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<void> _finishIo(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 60; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
    if (done()) return;
  }
  fail('Local file operation did not complete');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory fixture;
  late Audio audio;
  late LyricDocumentStore store;
  setUpAll(() async {
    final data = Platform.environment['DAN_PLAYER_DATA_DIR'];
    if (data == null ||
        !p.isWithin(
            p.join(Directory.current.parent.path, 'tool', 'qa-local'), data)) {
      throw StateError('Use independent workspace QA data');
    }
    root = await Directory(data).create(recursive: true);
    await TrackIdentityRegistry.instance.initialize(directory: root);
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
          ..addFont(rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
        .load();
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    } else if (const String.fromEnvironment('DAN_LYRIC_VARIANT_RENDER')
        .isNotEmpty) {
      throw StateError(
          'Render QA requires the real production Korean fallback');
    }
  });
  setUp(() async {
    fixture = await root.createTemp('variant-source-');
    store = LyricDocumentStore(storageDirectory: fixture);
    await store.load();
    audio = Audio('星辰與海 · Song', 'Artist', 'Album', 0, 60, null, null,
        p.join(fixture.path, '星辰與海.flac'), 0, 0, null);
    await File(audio.localFilePath).writeAsBytes([0]);
    await File(p.setExtension(audio.localFilePath, '.ja.lrc'))
        .writeAsString('[00:01.00]日本語の歌詞');
    await File(p.setExtension(audio.localFilePath, '.zh-CN.lrc'))
        .writeAsString('[00:01.00]中文歌词');
    clearLocalLyricMemoryCache();
  });
  tearDown(() async {
    uiLanguage.value = UiLanguage.zh;
    clearLocalLyricMemoryCache();
    store.dispose();
    await fixture.delete(recursive: true);
  });

  Future<LyricSearchResponse> noSources(Audio _) async => LyricSearchResponse(
      candidates: const [], failures: const {}, sourcesDisabled: true);
  Widget host(
          {String? Function()? currentTrackPath,
          Listenable? playbackListenable,
          GlobalKey? boundary,
          double textScale = 1}) =>
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!),
          theme: applyAppControlTheme(ThemeData(
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: danFontFamilyFallback,
              colorScheme:
                  ColorScheme.fromSeed(seedColor: const Color(0xffaa6475)))),
          home: UiLanguageScope(
              child: Scaffold(
                  body: Builder(
                      builder: (context) => Center(
                          child: FilledButton(
                              key: const ValueKey('open-variant-source'),
                              onPressed: () => showDialog<void>(
                                  context: context,
                                  builder: (_) => LyricSourceDialog(
                                      audio: audio,
                                      documentStore: store,
                                      currentTrackPath:
                                          currentTrackPath ?? () => audio.path,
                                      playbackListenable: playbackListenable,
                                      search: noSources)),
                              child: const Text('Open')))))),
        ),
      );
  Future<void> open(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    await tester.tap(find.byKey(const ValueKey('open-variant-source')));
    await tester.pump(const Duration(milliseconds: 300));
    await _finishIo(
        tester,
        () => find
            .byKey(const ValueKey('lyric-local-variant-星辰與海.ja.lrc'))
            .evaluate()
            .isNotEmpty);
    await tester.pumpAndSettle();
  }

  final japanese =
      find.byKey(const ValueKey('lyric-local-variant-星辰與海.ja.lrc'));

  testWidgets('explicit variant entry durably selects the full lyric document',
      (tester) async {
    await open(tester, host());
    await tester.ensureVisible(japanese);
    await tester.tap(japanese);
    await _finishIo(
        tester, () => find.byType(LyricSourceDialog).evaluate().isEmpty);
    await tester.pumpAndSettle();
    expect(find.byType(LyricSourceDialog), findsNothing);
    final selected = store.forAudio(audio)!;
    expect(lyricLineText(selected.effective!.toLyric().lines.single), '日本語の歌詞');
    final reopened = LyricDocumentStore(storageDirectory: fixture);
    addTearDown(reopened.dispose);
    await tester.runAsync(reopened.load);
    expect(
        lyricLineText(
            reopened.forAudio(audio)!.effective!.toLyric().lines.single),
        '日本語の歌詞');
  });

  testWidgets(
      'deleted explicit version preserves the previously selected document',
      (tester) async {
    await tester.runAsync(() => store.select(audio,
        Lrc.fromLrcText('[00:01.00]Previously saved', LrcSource.local)!));
    final revision = store.revisionFor(audio);
    await open(tester, host());
    await tester
        .runAsync(() => File(p.setExtension(audio.path, '.ja.lrc')).delete());
    await tester.ensureVisible(japanese);
    await tester.tap(japanese);
    await _finishIo(
        tester,
        () => find
            .byKey(const ValueKey('lyric-source-operation-error'))
            .evaluate()
            .isNotEmpty);
    expect(store.revisionFor(audio), revision);
    expect(
        lyricLineText(store.forAudio(audio)!.effective!.toLyric().lines.single),
        'Previously saved');
    expect(find.byType(LyricSourceDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lyric-source-close')));
    await tester.pumpAndSettle();
  });

  testWidgets('track change before a variant file read prevents a stale save',
      (tester) async {
    var current = audio.path;
    final notifier = ValueNotifier(0);
    addTearDown(notifier.dispose);
    await open(tester,
        host(currentTrackPath: () => current, playbackListenable: notifier));
    await tester.ensureVisible(japanese);
    await tester.tap(japanese);
    current = 'another-track.flac';
    notifier.value++;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
    expect(store.forAudio(audio), isNull);
    expect(find.byKey(const ValueKey('lyric-source-track-changed')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lyric-source-close')));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'explicit refresh discovers newly added language without restarting online search',
      (tester) async {
    await open(tester, host());
    await tester.runAsync(() => File(p.setExtension(audio.path, '.ko.lrc'))
        .writeAsString('[00:01.00]한국어 가사'));
    final korean =
        find.byKey(const ValueKey('lyric-local-variant-星辰與海.ko.lrc'));
    expect(korean, findsNothing);
    final refresh = find.byKey(const ValueKey('lyric-local-variants-refresh'));
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await _finishIo(tester, () => korean.evaluate().isNotEmpty);
    expect(korean, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lyric-source-close')));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'local version loading respects motion and never announces a percentage',
      (tester) async {
    final saveGate = Completer<void>();
    addTearDown(() {
      if (!saveGate.isCompleted) saveGate.complete();
    });
    store.dispose();
    store = LyricDocumentStore(
        storageDirectory: fixture, persistIdentity: () => saveGate.future);
    await tester.runAsync(store.load);
    final semantics = tester.ensureSemantics();
    try {
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      var feedback = true;
      var ticker = true;
      late StateSetter update;
      await tester.pumpWidget(StatefulBuilder(builder: (_, setState) {
        update = setState;
        return MotionPreferencesScope(
          preferences:
              const MotionPreferences().withKind(MotionKind.feedback, feedback),
          child: TickerMode(enabled: ticker, child: host()),
        );
      }));
      await tester.tap(find.byKey(const ValueKey('open-variant-source')));
      await tester.pumpAndSettle();
      final scan = find.text(ui('正在查找本地语言版本…'));
      expect(scan, findsOneWidget);
      expect(tester.getSemantics(scan).getSemanticsData().value, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
      await _finishIo(tester, () => japanese.evaluate().isNotEmpty);
      await tester.ensureVisible(japanese);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      await tester.pump();
      await tester.tap(japanese);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      final progress =
          find.byKey(const ValueKey('lyric-local-variant-progress'));
      final loading = find.byKey(const ValueKey('lyric-local-variant-loading'));
      expect(tester.widget<CircularProgressIndicator>(progress).value, isNull);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      Future<void> expectStatic() async {
        // Let the existing finite tap/scroll feedback finish while file I/O
        // remains pending. An indeterminate spinner cannot settle in this bound.
        await tester.pumpAndSettle(const Duration(milliseconds: 20),
            EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
        expect(tester.widget<CircularProgressIndicator>(progress).value, 0);
        expect(tester.binding.transientCallbackCount, 0);
        final data = tester.getSemantics(loading).getSemanticsData();
        expect(data.label, ui('正在加载歌词…'));
        expect(data.value, isEmpty);
      }

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await expectStatic();
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      update(() => feedback = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await expectStatic();
      update(() {
        feedback = true;
        ticker = false;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await expectStatic();
      update(() {
        ticker = true;
        feedback = false;
      });
      await tester.pump();
      saveGate.complete();
      await _finishIo(
          tester, () => find.byType(LyricSourceDialog).evaluate().isEmpty);
      expect(
          lyricLineText(
              store.forAudio(audio)!.effective!.toLyric().lines.single),
          '日本語の歌詞');
    } finally {
      semantics.dispose();
    }
  });

  for (final language in UiLanguage.values) {
    testWidgets('local variant source renders ${language.name} wide and narrow',
        (tester) async {
      uiLanguage.value = language;
      if (language != UiLanguage.zh) expect(ui('本地语言版本'), isNot('本地语言版本'));
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.runAsync(() => File(p.setExtension(audio.path, '.ko.lrc'))
          .writeAsString('[00:01.00]한국어 가사'));
      for (final width in [760.0, 440.0]) {
        tester.view.physicalSize = Size(width, 760);
        final boundary = GlobalKey();
        await open(tester,
            host(boundary: boundary, textScale: width == 440 ? 1.3 : 1));
        await Scrollable.ensureVisible(
            tester.element(
                find.byKey(const ValueKey('lyric-local-variants-refresh'))),
            alignment: 0);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(japanese, findsOneWidget);
        const output = String.fromEnvironment('DAN_LYRIC_VARIANT_RENDER');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: drawing.ImageByteFormat.png);
            final file =
                File(p.join(output, '${language.name}-${width.toInt()}.png'));
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.byKey(const ValueKey('lyric-source-close')));
        await tester.pumpAndSettle();
      }
    });
  }
}
