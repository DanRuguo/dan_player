import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:dan_player/page/now_playing_page/component/detail_playback_layout.dart';
import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:dan_player/page/now_playing_page/component/detail_transport_button.dart';
import 'package:dan_player/page/now_playing_page/component/queue_stop_status.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/queue_stop_boundary.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

class _Playback extends ChangeNotifier implements PlaybackService {
  @override
  final sleepTimerRemaining =
      ValueNotifier<Duration?>(const Duration(minutes: 15));
  @override
  final sleepTimerPaused = ValueNotifier(false);
  @override
  final sleepTimerFinishCurrent = ValueNotifier(false);
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
  String? get queueStopBlockedReason => null;
  @override
  String? get queueStopTargetLabel => null;
  @override
  void toggleSleepTimerPaused() =>
      sleepTimerPaused.value = !sleepTimerPaused.value;
  @override
  void cancelSleepTimer() => sleepTimerRemaining.value = null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  void dispose() {
    sleepTimerRemaining.dispose();
    sleepTimerPaused.dispose();
    sleepTimerFinishCurrent.dispose();
    stopAfterCurrent.dispose();
    queueStopBoundary.dispose();
    segmentLoop.dispose();
    playMode.dispose();
    playlist.dispose();
    super.dispose();
  }
}

void main() {
  const output = String.fromEnvironment('DAN_TIMELINE_RENDER');
  late _Playback playback;
  late StreamController<double> positions;
  setUp(() {
    playback = _Playback();
    positions = StreamController.broadcast();
  });
  tearDown(() async {
    playback.dispose();
    await positions.close();
    uiLanguage.value = UiLanguage.zh;
  });
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
          ..addFont(rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
        .load();
    for (final pair in [
      (
        'MaterialIcons',
        '../tool/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
      ),
      ('Malgun Gothic', 'C:/Windows/Fonts/malgun.ttf')
    ]) {
      final file = File(pair.$2);
      if (await file.exists()) {
        await (FontLoader(pair.$1)
              ..addFont(
                  Future.value(ByteData.sublistView(await file.readAsBytes()))))
            .load();
      }
    }
  });

  Widget host(
          {double scale = 1,
          GlobalKey? boundary,
          VoidCallback? onMore,
          FocusNode? moreFocus,
          double duration = 2700}) =>
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: Entry(welcome: false).fromSchemeAndFontFamily(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true),
              child: child!),
          home: Scaffold(
              appBar: const PreferredSize(
                  preferredSize: Size.fromHeight(56),
                  child: SizedBox(height: 56)),
              body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DetailPlaybackLayout(
                    display: Column(children: [
                      Text(ui('歌词'),
                          key: const ValueKey('fixture-display'),
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      const Text('Dan Player · Album',
                          maxLines: 1, style: TextStyle(fontSize: 14)),
                      const SizedBox(height: 16),
                      const Expanded(
                          child: Center(
                              child: FittedBox(
                                  child: Icon(Symbols.album, size: 32)))),
                    ]),
                    controls: Column(mainAxisSize: MainAxisSize.min, children: [
                      DetailProgressSlider(
                          positions: positions.stream,
                          readPosition: () => 420,
                          duration: duration,
                          trackIdentity: 'fixture',
                          onSeek: (_) {},
                          waveform: List.generate(512, (i) => (i % 31) / 30),
                          bookmarks: const [
                            PlaybackBookmark(
                                id: 'one',
                                track: 'fixture',
                                label: '片段',
                                positionMs: 1200000)
                          ],
                          loopStart: 360,
                          loopEnd: 520,
                          loopEnabled: true),
                      QueueStopStatus(playbackService: playback),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            DetailTransportButton(
                                tooltip: ui('上一曲'),
                                onPressed: () {},
                                icon: Symbols.skip_previous),
                            DetailTransportButton(
                                tooltip: ui('播放'),
                                onPressed: () {},
                                icon: Symbols.play_arrow),
                            DetailTransportButton(
                                tooltip: ui('下一曲'),
                                onPressed: () {},
                                icon: Symbols.skip_next),
                          ]),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            IconButton(
                                onPressed: () {},
                                icon: const Icon(Symbols.repeat),
                                tooltip: ui('播放模式')),
                            IconButton(
                                onPressed: () {},
                                icon: const Icon(Symbols.volume_up),
                                tooltip: ui('音量')),
                            IconButton(
                                onPressed: () {},
                                icon: const Icon(Symbols.speed),
                                tooltip: ui('播放速度')),
                            IconButton(
                                onPressed: () {},
                                icon: const Icon(Symbols.lyrics),
                                tooltip: ui('桌面歌词')),
                            IconButton(
                                key: const ValueKey('fixture-more'),
                                focusNode: moreFocus,
                                onPressed: onMore ?? () {},
                                icon: const Icon(Symbols.more_vert),
                                tooltip: ui('更多')),
                          ]),
                    ]),
                  ))),
        ),
      );

  ScrollPosition scrollPosition(WidgetTester tester) => tester
      .state<ScrollableState>(find
          .descendant(
              of: find.byKey(const ValueKey('detail-playback-controls-scroll')),
              matching: find.byType(Scrollable))
          .first)
      .position;

  testWidgets(
      'short-height controls scroll while display remains visible and all actions stay reachable',
      (tester) async {
    tester.view.physicalSize = const Size(507, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var more = 0;
    await tester.pumpWidget(host(scale: 2, onMore: () => more++));
    await tester.pumpAndSettle();
    expect(scrollPosition(tester).maxScrollExtent, greaterThan(0));
    expect(tester.getRect(find.byKey(const ValueKey('fixture-display'))).top,
        greaterThanOrEqualTo(16));
    final scroll =
        find.byKey(const ValueKey('detail-playback-controls-scroll'));
    await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(scroll), scrollDelta: const Offset(0, 180)));
    await tester.pumpAndSettle();
    expect(scrollPosition(tester).pixels, greaterThan(0));
    await tester.ensureVisible(find.byKey(const ValueKey('fixture-more')));
    await tester.tap(find.byKey(const ValueKey('fixture-more')));
    await tester.pumpAndSettle();
    expect(more, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'touch scrolling and keyboard traversal reveal short-window controls',
      (tester) async {
    tester.view.physicalSize = const Size(507, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var more = 0;
    await tester
        .pumpWidget(host(scale: 2, moreFocus: focus, onMore: () => more++));
    await tester.pumpAndSettle();
    final rect = tester
        .getRect(find.byKey(const ValueKey('detail-playback-controls-scroll')));
    await tester.dragFrom(
        Offset(rect.left + 8, rect.bottom - 12), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(scrollPosition(tester).pixels, greaterThan(0));
    scrollPosition(tester).jumpTo(0);
    await tester.pumpAndSettle();
    for (var index = 0; index < 20 && !focus.hasFocus; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(focus.hasFocus, isTrue);
    expect(focus.rect.bottom, lessThanOrEqualTo(304),
        reason:
            'keyboard reveals the focused painted control; IconButton adds a transparent 4px tap-target margin');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(more, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'normal windows keep natural footer height and no needless scroll space',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(scrollPosition(tester).maxScrollExtent, 0);
    final more = tester.getRect(find.byKey(const ValueKey('fixture-more')));
    expect(more.bottom, closeTo(704, 1));
    final before = tester.getRect(find.byType(Slider));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(before.center);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Slider)), before,
        reason: 'preview must not relayout the page');
    expect(find.byKey(const ValueKey('detail-progress-hover-time')),
        findsOneWidget);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'short and normal production footer compositions render in four languages',
      (tester) async {
    if (output.isEmpty) return;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final size in [const Size(507, 320), const Size(1280, 720)]) {
        final key = GlobalKey();
        tester.view.physicalSize = size;
        await tester
            .pumpWidget(host(scale: size.width == 507 ? 2 : 1, boundary: key));
        await tester.pumpAndSettle();
        Future<void> capture(String suffix) async {
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final image = await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            try {
              final bytes = (await image.toByteData(
                  format: drawing.ImageByteFormat.png))!;
              final file = File(
                  '$output/${language.name}-${size.width.toInt()}-footer-$suffix.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }

        await capture('top');
        await tester.ensureVisible(find.byKey(const ValueKey('fixture-more')));
        await tester.pumpAndSettle();
        await capture('bottom');
      }
    }
  });
}
