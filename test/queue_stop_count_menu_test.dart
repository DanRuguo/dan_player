import 'package:dan_player/component/player_number_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/now_playing_page/component/sleep_timer_submenu.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/queue_stop_boundary.dart';
import 'package:dan_player/play_service/queue_stop_count_selection.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

Audio _song(String id) => Audio.online(
    provider: 'qq', id: id, title: id, artist: '', album: '', duration: 60);

class _Playback extends ChangeNotifier implements PlaybackService {
  _Playback(List<Audio> items, {this.currentIndex = 1})
      : playlist = ValueNotifier(List<Audio>.from(items));

  int currentIndex;
  int sourceSession = 7;
  int confirmations = 0;
  int staleConfirmations = 0;
  bool blocked = false;
  @override
  final ValueNotifier<List<Audio>> playlist;
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
  String? get queueStopBlockedReason => blocked ? '歌曲正在加载，请稍后重试' : null;
  @override
  int get remainingQueueStopCount => blocked || playlist.value.isEmpty
      ? 0
      : playlist.value.length - currentIndex;

  @override
  QueueStopCountSelection? captureQueueStopCountSelection() =>
      remainingQueueStopCount == 0
          ? null
          : QueueStopCountSelection.capture(
              queueIdentity: playlist.value,
              sourceSession: sourceSession,
              currentIndex: currentIndex,
              queueLength: playlist.value.length);

  @override
  bool stopAfterQueueCount(int count,
      {required QueueStopCountSelection selection}) {
    confirmations++;
    if (!selection.isCurrent(
        queueIdentity: playlist.value,
        sourceSession: sourceSession,
        currentIndex: currentIndex,
        queueLength: playlist.value.length)) {
      staleConfirmations++;
      return false;
    }
    final index = selection.targetIndex(count);
    if (index == null) return false;
    stopAfterCurrent.value = false;
    queueStopBoundary.arm(index + 100);
    return true;
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

Future<void> _open(WidgetTester tester, _Playback service,
    {double scale = 1, GlobalKey? boundary}) async {
  await tester.pumpWidget(playlistFeatureHost(
      Center(
          child: MenuAnchor(
              menuChildren: [SleepTimerSubmenu(playbackService: service)],
              builder: (context, controller, _) => FilledButton(
                  onPressed: controller.open, child: const Text('More')))),
      textScale: scale,
      boundary: boundary));
  await tester.tap(find.text('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(SubmenuButton));
  await tester.pumpAndSettle();
}

Future<void> _openCount(WidgetTester tester) async {
  final count = find.byKey(const ValueKey('sleep-stop-after-count'));
  await tester.ensureVisible(count);
  await tester.tap(count);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final count in [1, 3]) {
    testWidgets(
        'count $count includes current and survives outer menu disposal',
        (tester) async {
      final repeated = _song('same');
      final service =
          _Playback([_song('before'), repeated, _song('middle'), repeated]);
      addTearDown(service.dispose);
      service.stopAfterCurrent.value = true;
      await _open(tester, service);
      await _openCount(tester);
      expect(find.byType(SleepTimerSubmenu), findsNothing);
      expect(find.byType(PlayerNumberDialog), findsOneWidget);
      expect(find.text(ui('首数（包含当前歌曲）')), findsOneWidget);
      expect(find.text(ui('确认后固定目标歌曲；重排或插入歌曲后仍在该曲结束时停止。')), findsOneWidget);
      final dialog =
          tester.widget<PlayerNumberDialog>(find.byType(PlayerNumberDialog));
      expect(dialog.minimum, 1);
      expect(dialog.maximum, 3);
      await tester.enterText(
          find.byKey(const ValueKey('player-number-input')), '$count');
      service.notifyListeners(); // A normal UI notification is not a new queue.
      await tester.tap(find.text(ui('确定')));
      await tester.pumpAndSettle();
      expect(service.queueStopBoundary.target,
          100 + service.currentIndex + count - 1);
      expect(service.stopAfterCurrent.value, isFalse);
      expect(service.confirmations, 1);
      expect(service.staleConfirmations, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invalid count stays editable and cancellation preserves target',
      (tester) async {
    final service =
        _Playback([_song('before'), _song('current'), _song('last')]);
    addTearDown(service.dispose);
    service.queueStopBoundary.arm(100);
    await _open(tester, service);
    await _openCount(tester);
    expect(
        tester
            .widget<PlayerNumberDialog>(find.byType(PlayerNumberDialog))
            .value,
        2);
    for (final invalid in ['0', '3']) {
      await tester.enterText(
          find.byKey(const ValueKey('player-number-input')), invalid);
      await tester.tap(find.text(ui('确定')));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerNumberDialog), findsOneWidget);
      expect(find.text(ui('请输入 {0} 到 {1} 之间的整数', [1, 2])), findsOneWidget);
      expect(service.confirmations, 0);
    }
    await tester.tap(find.text(ui('取消')));
    await tester.pumpAndSettle();
    expect(service.queueStopBoundary.target, 100);
    expect(service.confirmations, 0);
    expect(tester.takeException(), isNull);
  });

  for (final change in ['queue', 'current', 'source ABA']) {
    testWidgets('dialog confirmation rejects changed $change', (tester) async {
      final service =
          _Playback([_song('before'), _song('current'), _song('last')]);
      addTearDown(service.dispose);
      service.queueStopBoundary.arm(100);
      await _open(tester, service);
      await _openCount(tester);
      if (change == 'queue') {
        service.playlist.value = List<Audio>.from(service.playlist.value);
      } else if (change == 'current') {
        service.currentIndex = 2;
        service.sourceSession++;
      } else {
        service.sourceSession += 2;
      }
      service.notifyListeners();
      await tester.tap(find.text(ui('确定')));
      await tester.pumpAndSettle();
      expect(service.confirmations, 1);
      expect(service.staleConfirmations, 1);
      expect(service.queueStopBoundary.target, 100);
      expect(tester.takeException(), isNull);
    });
  }

  for (final empty in [false, true]) {
    testWidgets('count entry disables for ${empty ? 'empty' : 'blocked'} queue',
        (tester) async {
      final service =
          _Playback(empty ? [] : [_song('current')], currentIndex: 0)
            ..blocked = !empty;
      addTearDown(service.dispose);
      await _open(tester, service);
      expect(
          tester
              .widget<MenuItemButton>(
                  find.byKey(const ValueKey('sleep-stop-after-count')))
              .onPressed,
          isNull);
      expect(tester.takeException(), isNull);
    });
  }

  for (final timerActive in [false, true]) {
    for (final targetActive in [false, true]) {
      testWidgets(
          'count entry stays last timer=$timerActive target=$targetActive',
          (tester) async {
        final service =
            _Playback([_song('before'), _song('current'), _song('last')]);
        addTearDown(service.dispose);
        if (timerActive) {
          service.sleepTimerRemaining.value = const Duration(minutes: 20);
        }
        if (targetActive) service.queueStopBoundary.arm(101);
        await _open(tester, service);
        final submenu =
            tester.widget<SubmenuButton>(find.byType(SubmenuButton));
        expect(submenu.menuChildren.last.key,
            const ValueKey('sleep-stop-after-count'));
        final count = find.byKey(const ValueKey('sleep-stop-after-count'));
        expect(find.text(ui('按当前播放数量停止')), findsOneWidget);
        expect(
            tester.getRect(count).top,
            greaterThanOrEqualTo(tester
                .getRect(find.byKey(const ValueKey('sleep-stop-after-queue')))
                .bottom));
        if (targetActive) {
          expect(
              tester.getRect(count).top,
              greaterThanOrEqualTo(
                  tester.getRect(find.text(ui('取消停止目标'))).bottom));
        }
        if (timerActive) {
          expect(
              tester.getRect(count).top,
              greaterThanOrEqualTo(tester
                  .getRect(find.byKey(const ValueKey('sleep-menu-cancel')))
                  .bottom));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets('render count menu/dialog ${language.name} narrow=$narrow',
          (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          sizePlaylistFeature(tester, width: narrow ? 360 : 1000, height: 850);
          uiLanguage.value = language;
          if (language != UiLanguage.zh) {
            for (final key in [
              '按当前播放数量停止',
              '按当前队列设置停止目标',
              '首数（包含当前歌曲）',
              '确认后固定目标歌曲；重排或插入歌曲后仍在该曲结束时停止。',
              '当前队列或歌曲已改变，请重新设置停止目标',
            ]) {
              expect(ui(key), isNot(key),
                  reason:
                      'The actual ui() lookup must not use Chinese fallback.');
            }
          }
          final service =
              _Playback([_song('before'), _song('current'), _song('last')]);
          addTearDown(service.dispose);
          final boundary = GlobalKey();
          await _open(tester, service, scale: 2, boundary: boundary);
          expect(tester.takeException(), isNull);
          await capturePlaylistFeature(
              tester, boundary, 'stop-count-menu-${language.name}-$narrow');
          await _openCount(tester);
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('player-number-input')),
              findsOneWidget);
          final data = tester
              .getSemantics(
                  find.byKey(const ValueKey('player-number-description-input')))
              .getSemanticsData();
          expect(data.label, '${ui('首数（包含当前歌曲）')}\n1 – 2');
          expect(data.flagsCollection.isTextField, isTrue);
          expect(data.value, '2');
          expect(find.text(ui('首数（包含当前歌曲）')), findsOneWidget);
          await capturePlaylistFeature(
              tester, boundary, 'stop-count-dialog-${language.name}-$narrow');
          await tester.tap(find.text(ui('取消')));
          await tester.pumpAndSettle();
          expect(service.confirmations, 0);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
