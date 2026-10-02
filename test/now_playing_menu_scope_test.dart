import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/page/now_playing_page/page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/listening_status_fixture.dart';
import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  for (final online in [false, true]) {
    testWidgets(
        'more menu retains song tools without duplicate comments online=$online',
        (tester) async {
      sizePlaylistFeature(tester, width: 1080, height: 1000);
      final playback =
          ListeningStatusPlayback([CategoryTestAudio('Track', online: online)]);
      addTearDown(playback.dispose);
      await tester.pumpWidget(listeningStatusHost(AppPresentationHost(
          child: ChangeNotifierProvider<PlaybackService>.value(
              value: playback,
              child: const Center(child: NowPlayingMoreAction())))));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(ui('更多')));
      await tester.pumpAndSettle();
      final labels = ['本曲播放设置', '响度与峰值分析', '音频文件校验'];
      for (final label in labels) {
        final entry = find.text(ui(label));
        if (online && label != '本曲播放设置') {
          expect(entry, findsNothing);
        } else {
          expect(entry, findsOneWidget);
          await tester.ensureVisible(entry);
          expect(entry.hitTestable(), findsOneWidget);
          expect(
              tester
                  .widget<MenuItemButton>(find.ancestor(
                      of: entry, matching: find.byType(MenuItemButton)))
                  .onPressed,
              isNotNull);
        }
      }
      expect(find.text(ui('歌曲评论')), findsNothing);
      expect(find.text(ui('详细信息')), findsOneWidget);
      expect(PlayService.hasFacade, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
