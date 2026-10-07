import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/now_playing_page/component/sleep_timer_submenu.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/queue_stop_boundary.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

class _Playback extends ChangeNotifier implements PlaybackService {
  @override
  final playlist = ValueNotifier<List<Audio>>([]);
  @override
  final sleepTimerRemaining = ValueNotifier<Duration?>(null);
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
  String? get queueStopBlockedReason => null;
  @override
  int get remainingQueueStopCount => 0;

  var cancellations = 0;

  @override
  void cancelQueueStop() {
    cancellations++;
    queueStopBoundary.cancel(QueueStopCancelReason.userCancelled);
  }

  @override
  void dispose() {
    playlist.dispose();
    sleepTimerRemaining.dispose();
    sleepTimerPaused.dispose();
    sleepTimerFinishCurrent.dispose();
    stopAfterCurrent.dispose();
    queueStopBoundary.dispose();
    segmentLoop.dispose();
    playMode.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(WidgetTester tester, _Playback service) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
          body: Center(
              child: MenuAnchor(
                  menuChildren: [SleepTimerSubmenu(playbackService: service)],
                  builder: (context, menu, _) => FilledButton(
                      onPressed: menu.open, child: const Text('More')))))));
  await tester.tap(find.text('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(SubmenuButton));
  await tester.pumpAndSettle();
}

Future<void> _clickCancel(WidgetTester tester) => tester.tap(find.ancestor(
    of: find.text(ui('取消停止目标')), matching: find.byType(MenuItemButton)));

Rect _panelRect(WidgetTester tester) => tester.getRect(find
    .ancestor(
        of: find.byKey(const ValueKey('sleep-stop-after-count')),
        matching: find.byWidgetPredicate((widget) =>
            widget is Material && widget.type == MaterialType.canvas))
    .first);

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets('clicked sleep menu cancellation still cancels its shown target',
      (tester) async {
    final service = _Playback()..queueStopBoundary.arm(101);
    addTearDown(service.dispose);
    await _open(tester, service);
    await _clickCancel(tester);
    expect(service.cancellations, 0,
        reason: 'The real MenuItemButton defers selection until post-frame.');
    await tester.pumpAndSettle();
    expect(service.cancellations, 1);
    expect(service.queueStopBoundary.active, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clicked sleep menu cancellation cannot cancel a newer target',
      (tester) async {
    final service = _Playback()..queueStopBoundary.arm(101);
    addTearDown(service.dispose);
    await _open(tester, service);
    await _clickCancel(tester);
    expect(service.cancellations, 0);
    service.queueStopBoundary.arm(202);
    await tester.pumpAndSettle();
    expect(service.cancellations, 0);
    expect(service.queueStopBoundary.target, 202);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'clicked sleep menu cancellation cannot cancel a replacement queue target',
      (tester) async {
    final service = _Playback()..queueStopBoundary.arm(101);
    addTearDown(service.dispose);
    await _open(tester, service);
    await _clickCancel(tester);
    expect(service.cancellations, 0);
    service.queueStopBoundary.cancel(QueueStopCancelReason.sourceReplaced);
    service.playlist.value = [
      Audio.online(
          provider: 'qq',
          id: 'replacement',
          title: 'Replacement',
          artist: '',
          album: '',
          duration: 60)
    ];
    service.queueStopBoundary.arm(303);
    await tester.pumpAndSettle();
    expect(service.cancellations, 0);
    expect(service.queueStopBoundary.target, 303);
    expect(tester.takeException(), isNull);
  });

  for (final command in ['same target', 'A-B-A target']) {
    testWidgets('clicked sleep menu cancellation preserves rearmed $command',
        (tester) async {
      final service = _Playback()..queueStopBoundary.arm(101);
      addTearDown(service.dispose);
      await _open(tester, service);
      await _clickCancel(tester);
      expect(service.cancellations, 0);
      if (command == 'A-B-A target') {
        service.queueStopBoundary.arm(202);
      }
      service.queueStopBoundary.arm(101);
      await tester.pumpAndSettle();
      expect(service.cancellations, 0);
      expect(service.queueStopBoundary.target, 101);
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in UiLanguage.values) {
    testWidgets('expanded sleep submenu follows changed rows ${language.name}',
        (tester) async {
      uiLanguage.value = language;
      final service = _Playback();
      addTearDown(service.dispose);
      sizePlaylistFeature(tester, height: 1800);
      for (final width in [420.0, 1100.0]) {
        tester.view.physicalSize = Size(width, 1800);
        final boundary = GlobalKey();
        await tester.pumpWidget(UiLanguageScope(
            child: playlistFeatureHost(
                Padding(
                    padding: const EdgeInsets.all(24),
                    child: Align(
                        alignment: Alignment.bottomLeft,
                        child: SleepTimerSubmenu(playbackService: service))),
                textScale: 1.75,
                boundary: boundary)));
        await tester.pumpAndSettle();
        final trigger = find.byType(SubmenuButton);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        final before = _panelRect(tester);
        expect(before.bottom, closeTo(tester.getRect(trigger).bottom, .01));
        expect(before.left, greaterThanOrEqualTo(0));
        expect(before.right, lessThanOrEqualTo(width));

        service.sleepTimerRemaining.value = const Duration(minutes: 20);
        service.queueStopBoundary.arm(101);
        await tester.pumpAndSettle();
        final expanded = _panelRect(tester);
        expect(expanded.height, greaterThan(before.height));
        expect(expanded.bottom, closeTo(tester.getRect(trigger).bottom, .01));
        expect(find.byKey(const ValueKey('sleep-adjust-more')).hitTestable(),
            findsOneWidget);
        expect(
            find.byKey(const ValueKey('sleep-stop-after-count')).hitTestable(),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(tester.binding.hasScheduledFrame, isFalse,
            reason: 'OverlayPortal keeps a layout callback without scheduling '
                'another frame while its menu is idle.');
        await capturePlaylistFeature(tester, boundary,
            'sleep-dynamic-${language.name}-${width.toInt()}-expanded');

        service.sleepTimerRemaining.value = null;
        service.queueStopBoundary.cancel(QueueStopCancelReason.userCancelled);
        await tester.pumpAndSettle();
        final contracted = _panelRect(tester);
        expect(contracted.height, closeTo(before.height, .01));
        expect(contracted.bottom, closeTo(tester.getRect(trigger).bottom, .01));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      }
    });
  }
}
