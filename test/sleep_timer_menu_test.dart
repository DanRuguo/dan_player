import 'dart:io';
import 'dart:ui' as raster;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/now_playing_page/component/sleep_timer_submenu.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/queue_stop_boundary.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

class _Playback extends ChangeNotifier implements PlaybackService {
  @override
  final sleepTimerRemaining = ValueNotifier<Duration?>(null);
  @override
  final stopAfterCurrent = ValueNotifier(false);
  @override
  final queueStopBoundary = QueueStopBoundary();
  @override
  final segmentLoop = SegmentLoopController();
  @override
  final playMode = ValueNotifier(PlayMode.forward);
  @override
  final playlist = ValueNotifier<List<Audio>>([]);
  @override
  void setStopAfterCurrent(bool value) => stopAfterCurrent.value = value;
  @override
  void dispose() {
    sleepTimerRemaining.dispose();
    stopAfterCurrent.dispose();
    queueStopBoundary.dispose();
    segmentLoop.dispose();
    playMode.dispose();
    playlist.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    final windows = Platform.environment['WINDIR'];
    if (windows != null) {
      final font = File('$windows/Fonts/malgun.ttf');
      if (await font.exists()) {
        await (FontLoader('Malgun Gothic')
              ..addFont(
                  Future.value(ByteData.sublistView(await font.readAsBytes()))))
            .load();
      }
    }
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  for (final language in UiLanguage.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'sleep actions align and follow theme: ${language.name} ${brightness.name}',
          (tester) async {
        tester.view.physicalSize = const Size(1000, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        uiLanguage.value = language;
        final service = _Playback();
        addTearDown(service.dispose);
        final boundary = GlobalKey();
        for (final seed in [Colors.blue, Colors.orange]) {
          final theme = Entry(welcome: false).fromSchemeAndFontFamily(
              colorScheme:
                  ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
              fontFamily: danEmbeddedFontFamily);
          await tester.pumpWidget(UiLanguageScope(
              child: RepaintBoundary(
                  key: boundary,
                  child: MaterialApp(
                      theme: theme,
                      builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                              textScaler: const TextScaler.linear(1.5)),
                          child: child!),
                      home: Scaffold(
                          body: Center(
                              child: SleepTimerSubmenu(
                                  playbackService: service)))))));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(SubmenuButton));
          await tester.pumpAndSettle();
          expect(find.byType(Checkbox), findsNothing);
          final current = find.byIcon(Symbols.music_note);
          final timer = find.byIcon(Symbols.timer).first;
          expect(tester.getCenter(current).dx,
              closeTo(tester.getCenter(timer).dx, .1));
          expect(IconTheme.of(tester.element(current)).color,
              theme.colorScheme.primary);
          final item =
              find.ancestor(of: current, matching: find.byType(MenuItemButton));
          expect(tester.getCenter(current).dy,
              closeTo(tester.getCenter(item).dy, .1));
          expect(tester.takeException(), isNull);
          for (final active in [true, false]) {
            await tester.tap(item);
            await tester.pumpAndSettle();
            expect(service.stopAfterCurrent.value, active);
            await tester.tap(find.byType(SubmenuButton));
            await tester.pumpAndSettle();
            expect(find.byIcon(Symbols.check),
                active ? findsOneWidget : findsNothing);
          }
          const renderDir =
              String.fromEnvironment('DAN_PLAYER_MENU_RENDER_DIR');
          if (renderDir.isNotEmpty && seed == Colors.blue) {
            await tester.runAsync(() async {
              final image = await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
              final bytes =
                  await image.toByteData(format: raster.ImageByteFormat.png);
              final file = File(
                  '$renderDir/sleep-${language.name}-${brightness.name}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.tap(find.byType(SubmenuButton));
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
