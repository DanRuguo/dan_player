import 'package:dan_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:dan_player/play_service/queue_stop_boundary.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

class _StopPlayback extends PlaylistFeaturePlayback {
  _StopPlayback()
      : super([
          CategoryTestAudio('Active'),
          CategoryTestAudio('Stop A'),
          CategoryTestAudio('Stop B')
        ]);
  var cancelCalls = 0;
  @override
  void cancelQueueStop() {
    cancelCalls++;
    queueStopBoundary.cancel(QueueStopCancelReason.userCancelled);
  }
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final replacement in [
    'unchanged',
    'queue',
    'target',
    'same',
    'return'
  ]) {
    testWidgets('queue stop cancellation owns selected $replacement state',
        (tester) async {
      sizePlaylistFeature(tester);
      final playback = _StopPlayback();
      addTearDown(playback.dispose);
      playback.queueStopBoundary.arm(1);
      await tester.pumpWidget(
          playlistFeatureHost(CurrentPlaylistView(playbackService: playback)));
      await tester.pumpAndSettle();
      await tester
          .longPress(find.byKey(const ValueKey('current-playlist-item-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ui('取消停止目标')));
      expect(playback.cancelCalls, 0,
          reason: 'native MenuItemButton closes before its post-frame action');
      if (replacement == 'queue') {
        playback.replaceQueue(
            [CategoryTestAudio('New active'), CategoryTestAudio('New stop')]);
        // Reuse the fake occurrence ID deliberately: source identity must
        // also be checked rather than treating an old index as a new owner.
        playback.queueStopBoundary.arm(1);
      } else if (replacement == 'target') {
        playback.queueStopBoundary.arm(2);
      } else if (replacement == 'same') {
        playback.queueStopBoundary.arm(1);
      } else if (replacement == 'return') {
        playback.queueStopBoundary.arm(2);
        playback.queueStopBoundary.arm(1);
      }
      await tester.pumpAndSettle();
      if (replacement == 'unchanged') {
        expect(playback.cancelCalls, 1);
        expect(playback.queueStopBoundary.target, isNull);
      } else {
        expect(playback.cancelCalls, 0,
            reason: 'the late action cannot cancel a newly selected target');
        expect(
            playback.queueStopBoundary.target, replacement == 'target' ? 2 : 1);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
