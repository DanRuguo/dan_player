import 'dart:math' as math;
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/local_lyric_preferences.dart';
import 'package:dan_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:dan_player/page/now_playing_page/component/now_playing_progress.dart';
import 'package:dan_player/page/now_playing_page/component/queue_stop_status.dart';
import 'package:dan_player/page/now_playing_page/component/sleep_timer_submenu.dart';
import 'package:dan_player/page/now_playing_page/component/waveform_progress.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String name) => find.byKey(ValueKey(name));
Audio _audio(String id) => Audio.online(
    provider: 'qq',
    id: id,
    title: id,
    artist: 'Artist',
    album: 'Album',
    duration: 180);

Future<void> _openQueue(WidgetTester tester, ListeningStatusPlayback service,
    {bool dialog = false,
    double scale = 1,
    GlobalKey? boundary,
    Brightness brightness = Brightness.light}) async {
  final view = CurrentPlaylistView(
      playbackService: service,
      immersive: !dialog,
      showTitle: !dialog,
      shrinkWrap: dialog);
  await tester.pumpWidget(listeningStatusHost(
      dialog
          ? Builder(
              builder: (context) => TextButton(
                  onPressed: () => showAppDialog<void>(
                      context: context,
                      builder: (context) {
                        final size = MediaQuery.sizeOf(context);
                        return AlertDialog(
                            insetPadding: const EdgeInsets.all(16),
                            titlePadding:
                                const EdgeInsets.fromLTRB(20, 20, 20, 8),
                            contentPadding:
                                const EdgeInsets.fromLTRB(20, 8, 20, 0),
                            actionsPadding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 12),
                            title: Text(ui('播放列表')),
                            content: AppDialogContent(
                                width: math.min(
                                    520, math.max(160, size.width - 88)),
                                maxHeight: math.min(
                                    440, math.max(160, size.height - 220)),
                                child: view),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text(ui('关闭')))
                            ]);
                      }),
                  child: const Text('Queue')))
          : view,
      scale: scale,
      boundary: boundary,
      brightness: brightness));
  if (dialog) await tester.tap(find.text('Queue'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets('timeline never hosts any sleep or stop status while active',
      (tester) async {
    sizePlaylistFeature(tester);
    final service = ListeningStatusPlayback([_audio('Night')]);
    addTearDown(service.dispose);
    for (final state in ['timer', 'paused', 'current', 'target', 'blocked']) {
      service.startSleepTimer(const Duration(minutes: 22));
      service.sleepTimerPaused.value = state == 'paused';
      service.stopAfterCurrent.value = state == 'current';
      if (state == 'target' || state == 'blocked') {
        service.queueStopBoundary.arm(3);
      }
      service.blocked = state == 'blocked';
      await tester.pumpWidget(listeningStatusHost(NowPlayingProgress(
          playbackService: service,
          waveformEnabled: false,
          waveformDensity: WaveformBarDensity.automatic)));
      await tester.pumpAndSettle();
      expect(find.byType(QueueStopStatus), findsNothing);
      for (final name in [
        'sleep-timer-status',
        'sleep-status-pause',
        'sleep-status-cancel',
        'queue-stop-target',
        'queue-cancel-stop'
      ]) {
        expect(_key(name), findsNothing, reason: state);
      }
      final waveform =
          tester.widget<WaveformProgress>(find.byType(WaveformProgress));
      expect(waveform.audio, same(service.nowPlaying));
      expect(waveform.duration, service.length);
      expect(waveform.trackIdentity, (service.nowPlaying!.path, 9));
      waveform.onSeek(42);
      expect(service.lastSeek, 42);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  for (final dialog in [false, true]) {
    testWidgets(
        'real queue ${dialog ? 'dialog' : 'lyrics'} shares timer and stop actions',
        (tester) async {
      sizePlaylistFeature(tester, width: 1100, height: 900);
      final service = ListeningStatusPlayback([_audio('Night'), _audio('Last')])
        ..startSleepTimer(const Duration(minutes: 22))
        ..stopAfterQueueRound();
      addTearDown(service.dispose);
      await _openQueue(tester, service, dialog: dialog);
      expect(find.byType(QueueStopStatus), findsOneWidget);
      expect(_key('sleep-timer-status'), findsOneWidget);
      expect(_key('queue-stop-target'), findsOneWidget);
      await tester.tap(_key('sleep-status-pause'));
      await tester.pump();
      expect(service.sleepTimerPaused.value, isTrue);
      expect(tester.widget<Text>(_key('sleep-timer-status')).data,
          ui('倒计时已暂停 {0}', ['22:00']));
      await tester.tap(_key('sleep-status-cancel'));
      await tester.pump();
      expect(service.sleepTimerRemaining.value, isNull);
      expect(_key('queue-stop-target'), findsOneWidget);
      service.startSleepTimer(const Duration(minutes: 7));
      await tester.pump();
      await tester.tap(_key('queue-cancel-stop'));
      await tester.pump();
      expect(service.queueStopBoundary.active, isFalse);
      expect(_key('sleep-timer-status'), findsOneWidget);
      service.stopAfterCurrent.value = true;
      await tester.pump();
      expect(_key('queue-stop-target'), findsOneWidget);
      await tester.tap(_key('queue-cancel-stop'));
      await tester.pump();
      expect(service.stopAfterCurrent.value, isFalse);
      expect(_key('sleep-timer-status'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final language in UiLanguage.values) {
    for (final width in [380.0, 1000.0]) {
      final narrow = width < 500;
      testWidgets(
          'all sleep menu text follows live theme ${language.name}/$width',
          (tester) async {
        sizePlaylistFeature(tester, width: width, height: 900);
        uiLanguage.value = language;
        final service = ListeningStatusPlayback([_audio('Night')])
          ..blocked = true
          ..startSleepTimer(const Duration(minutes: 3));
        addTearDown(service.dispose);
        final seed = ValueNotifier(Colors.teal);
        addTearDown(seed.dispose);
        final boundary = GlobalKey();
        await tester.pumpWidget(ValueListenableBuilder(
            valueListenable: seed,
            builder: (_, color, __) => listeningStatusHost(
                Center(child: SleepTimerSubmenu(playbackService: service)),
                seed: color,
                scale: narrow ? 2 : 1.25,
                brightness: narrow ? Brightness.light : Brightness.dark,
                boundary: boundary)));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(SubmenuButton));
        await tester.pumpAndSettle();
        for (final color in [Colors.teal, Colors.deepOrange]) {
          seed.value = color;
          await tester.pumpAndSettle();
          final scheme =
              Theme.of(tester.element(find.byType(SubmenuButton))).colorScheme;
          final texts = find.descendant(
              of: find.byType(MenuItemButton), matching: find.byType(Text));
          expect(texts.evaluate().length, greaterThan(10));
          for (final element in texts.evaluate()) {
            final text = element.widget as Text;
            final item =
                element.findAncestorWidgetOfExactType<MenuItemButton>()!;
            final expected = item.onPressed == null
                ? scheme.onSurface.withValues(alpha: .38)
                : scheme.primary;
            expect(DefaultTextStyle.of(element).style.merge(text.style).color,
                expected,
                reason: text.data);
          }
          final trigger = find
              .descendant(
                  of: find.byType(SubmenuButton), matching: find.byType(Text))
              .first;
          expect(DefaultTextStyle.of(tester.element(trigger)).style.color,
              scheme.primary);
          for (final element in find.byType(SleepPresetIcon).evaluate()) {
            expect(IconTheme.of(element).color, scheme.primary);
          }
        }
        expect(tester.takeException(), isNull);
        await captureListeningStatus(
            tester, boundary, 'menu-${language.name}-${width.toInt()}-top');
        await tester.ensureVisible(_key('sleep-stop-after-count'));
        await tester.pumpAndSettle();
        await captureListeningStatus(
            tester, boundary, 'menu-${language.name}-${width.toInt()}-bottom');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets(
          'queue status fits ${language.name}/$width in real presentation',
          (tester) async {
        sizePlaylistFeature(tester, width: width, height: 900);
        uiLanguage.value = language;
        final service =
            ListeningStatusPlayback([_audio('Night'), _audio('Last')])
              ..startSleepTimer(const Duration(minutes: 22))
              ..stopAfterQueueRound()
              ..blocked = true;
        addTearDown(service.dispose);
        final boundary = GlobalKey();
        await _openQueue(tester, service,
            dialog: narrow,
            scale: narrow ? 2 : 1.25,
            boundary: boundary,
            brightness: narrow ? Brightness.light : Brightness.dark);
        expect(_key('sleep-status-pause').hitTestable(), findsOneWidget);
        expect(_key('sleep-status-cancel').hitTestable(), findsOneWidget);
        expect(_key('queue-cancel-stop').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await captureListeningStatus(
            tester, boundary, 'queue-${language.name}-${width.toInt()}');
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
