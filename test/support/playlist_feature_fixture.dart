import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/queue_stop_boundary.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class PlaylistFeaturePlayback extends ChangeNotifier
    implements PlaybackService {
  PlaylistFeaturePlayback(List<Audio> queue, {this.currentIndex = 0})
      : playlist = ValueNotifier(List<Audio>.from(queue)),
        nowPlaying = queue.isEmpty ? null : queue[currentIndex];

  @override
  final ValueNotifier<List<Audio>> playlist;
  @override
  Audio? nowPlaying;
  int currentIndex;
  @override
  int get playlistIndex => currentIndex;
  @override
  final resolvingAudioPath = ValueNotifier<String?>(null);
  @override
  final isChangingOutput = ValueNotifier(false);
  @override
  final segmentLoop = SegmentLoopController();
  @override
  final queueStopBoundary = QueueStopBoundary();
  @override
  final playMode = ValueNotifier(PlayMode.loop);
  @override
  final sleepTimerRemaining = ValueNotifier<Duration?>(null);
  @override
  final sleepTimerPaused = ValueNotifier(false);
  @override
  final stopAfterCurrent = ValueNotifier(false);
  @override
  bool get canEditQueue => true;
  @override
  bool get canUndoQueueEdit => false;
  @override
  bool get canRedoQueueEdit => false;
  @override
  String? get queueStopTargetLabel => null;
  @override
  String? get queueStopBlockedReason => null;
  @override
  int? queueOccurrenceId(int index) => index;
  @override
  String queueHistoryReason({bool redo = false}) => '没有可撤销的队列操作';

  void replaceQueue(List<Audio> items) {
    currentIndex = items.isEmpty ? -1 : 0;
    nowPlaying = items.firstOrNull;
    playlist.value = List<Audio>.from(items);
    notifyListeners();
  }

  @override
  void dispose() {
    playlist.dispose();
    resolvingAudioPath.dispose();
    isChangingOutput.dispose();
    segmentLoop.dispose();
    queueStopBoundary.dispose();
    playMode.dispose();
    sleepTimerRemaining.dispose();
    sleepTimerPaused.dispose();
    stopAfterCurrent.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> loadPlaylistFeatureFonts() async {
  for (final font in [
    (danEmbeddedFontFamily, 'packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf'),
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
}

Widget playlistFeatureHost(Widget child,
        {double textScale = 1, GlobalKey? boundary}) =>
    MaterialApp(
      theme: applyAppControlTheme(ThemeData(
        platform: TargetPlatform.windows,
        useMaterial3: true,
        fontFamily: danEmbeddedFontFamily,
        fontFamilyFallback: danFontFamilyFallback,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      )),
      builder: (context, child) => RepaintBoundary(
        key: boundary,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
      home: Scaffold(body: child),
    );

void sizePlaylistFeature(WidgetTester tester,
    {double width = 1000, double height = 850}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> capturePlaylistFeature(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final directory = Platform.environment['DAN_PLAYLIST_FEATURE_RENDER_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    await Directory(directory).create(recursive: true);
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage();
    try {
      final bytes = await image.toByteData(format: raster.ImageByteFormat.png);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
