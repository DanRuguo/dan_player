import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  for (final language in UiLanguage.values) {
    testWidgets(
        'handoff ${language.name} fades, releases timeline and animates only the loading status',
        (tester) async {
      tester.view.physicalSize = const Size(900, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      uiLanguage.value = language;
      final clock = StreamController<double>.broadcast(sync: true);
      final controls = LyricViewController()..lyricFontSize = 28;
      final prefs =
          ValueNotifier(const RenderingPreferences(pauseWhenHidden: false));
      addTearDown(clock.close);
      addTearDown(controls.dispose);
      addTearDown(prefs.dispose);
      final old = Lrc.fromLrcText(
          '[00:00.00]上一首 · Previous song\n[00:05.00]星空に届くように\n[00:10.00]다시 만날 그날까지',
          LrcSource.web)!;
      Future<Lyric?> future = Future.value(old);
      final boundary = GlobalKey();
      Widget app() => UiLanguageScope(
          child: MaterialApp(
              theme: ThemeData(
                  colorScheme: ColorScheme.fromSeed(
                      seedColor: Colors.deepPurple,
                      brightness: language == UiLanguage.en
                          ? Brightness.light
                          : Brightness.dark),
                  fontFamily: danEmbeddedFontFamily,
                  fontFamilyFallback: danFontFamilyFallback),
              home: RenderingPreferencesScope(
                  preferences: prefs,
                  child: RepaintBoundary(
                      key: boundary,
                      child: Scaffold(
                          body: Padding(
                              padding: const EdgeInsets.all(32),
                              child: ChangeNotifierProvider.value(
                                  value: controls,
                                  child: VerticalLyricContent(
                                      lyricFuture: future,
                                      positionStream: clock.stream,
                                      readPosition: () => 5,
                                      onSeek: (_) {}))))))));
      Future<void> capture(String stage) async {
        const output = String.fromEnvironment('DAN_HANDOFF_RENDER');
        if (output.isEmpty) return;
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          try {
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('$output/${language.name}-$stage.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      await tester.pumpWidget(app());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final entrance = tester.widget<FadeTransition>(find
          .ancestor(
              of: find.byType(VerticalLyricScrollView),
              matching: find.byType(FadeTransition))
          .first);
      expect(entrance.opacity.value, greaterThan(0));
      expect(entrance.opacity.value, lessThan(1));
      await tester.pumpAndSettle();
      await capture('before');
      final priorBlur = tester
          .widgetList<LyricFollowEffects>(find.byType(LyricFollowEffects))
          .map((row) => (row.blurEnabled, row.blur))
          .toList();
      final pending = Completer<Lyric?>();
      future = pending.future;
      await tester.pumpWidget(app());
      await tester.pump(const Duration(milliseconds: 120));
      expect(clock.hasListener, isFalse,
          reason:
              'Outgoing lyrics must stop even when hidden-page updates are allowed');
      expect(
          tester
              .widgetList<LyricViewTile>(find.byType(LyricViewTile))
              .every((row) => !row.reducedMotion),
          isTrue);
      expect(
          tester
              .widgetList<LyricFollowEffects>(find.byType(LyricFollowEffects))
              .map((row) => (row.blurEnabled, row.blur))
              .toList(),
          priorBlur);
      await capture('fading');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(VerticalLyricScrollView), findsNothing);
      final loading = find.text(translateUi('正在加载歌词', language));
      expect(loading, findsOneWidget);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      final loadingTop = tester.getTopLeft(loading).dy;
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.getTopLeft(loading).dy, lessThan(loadingTop - 1));
      await capture('loading');
      pending.complete(Lrc.fromLrcText(
          '[00:00.00]下一首 · Next song\n[00:05.00]新的旋律，继续播放', LrcSource.web));
      await tester.pumpAndSettle();
      await capture('ready');
      expect(find.byType(VerticalLyricScrollView), findsOneWidget);
      expect(clock.hasListener, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
