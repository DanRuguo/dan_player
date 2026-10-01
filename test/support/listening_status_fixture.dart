import 'dart:io';
import 'package:dan_player/entry.dart';
import 'package:dan_player/play_service/queue_stop_boundary.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'lyric_share_fixture.dart';
import 'playlist_feature_fixture.dart';

class ListeningStatusPlayback extends PlaylistFeaturePlayback {
  ListeningStatusPlayback(super.queue);
  @override
  final sleepTimerFinishCurrent = ValueNotifier(false);
  final _isBuffering = ValueNotifier(false);
  @override
  ValueNotifier<bool> get isBuffering => _isBuffering;
  bool blocked = false;
  String targetName = 'Night 最後 마지막';
  double? lastSeek;
  @override
  String? get queueStopBlockedReason => blocked ? '请先关闭 A-B 循环，再设置停止目标' : null;
  @override
  String? get queueStopTargetLabel =>
      queueStopBoundary.active ? '3 · $targetName' : null;
  @override
  int get remainingQueueStopCount => playlist.value.length;
  @override
  double get position => 37.0;
  @override
  double get length => 180.0;
  @override
  int get playbackSessionToken => 9;
  @override
  Stream<double> get positionStream => const Stream.empty();
  @override
  void seek(double seconds) => lastSeek = seconds;
  @override
  void startSleepTimer(Duration duration) {
    sleepTimerRemaining.value = duration;
    sleepTimerPaused.value = false;
  }

  @override
  void toggleSleepTimerPaused() =>
      sleepTimerPaused.value = !sleepTimerPaused.value;
  @override
  void cancelSleepTimer() {
    sleepTimerRemaining.value = null;
    sleepTimerPaused.value = false;
  }

  @override
  void setStopAfterCurrent(bool value) => stopAfterCurrent.value = value;
  @override
  void cancelQueueStop() =>
      queueStopBoundary.cancel(QueueStopCancelReason.userCancelled);
  @override
  bool stopAfterQueueRound() {
    queueStopBoundary.arm(3);
    return true;
  }

  @override
  void dispose() {
    sleepTimerFinishCurrent.dispose();
    isBuffering.dispose();
    super.dispose();
  }
}

Widget listeningStatusHost(Widget child,
        {double scale = 1,
        Color seed = Colors.teal,
        Brightness brightness = Brightness.light,
        GlobalKey? boundary}) =>
    UiLanguageScope(
        child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: Entry(welcome: false).fromSchemeAndFontFamily(
                    colorScheme: ColorScheme.fromSeed(
                        seedColor: seed, brightness: brightness)),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        disableAnimations: true),
                    child: child!),
                home: Scaffold(body: child))));

Future<void> captureListeningStatus(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final directory = Platform.environment['DAN_LISTENING_STATUS_RENDER_DIR'];
  if (directory == null) return;
  final bytes = await captureLyricShare(tester, boundary);
  await tester.runAsync(() async {
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(bytes);
  });
}
