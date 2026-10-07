import 'package:dan_player/component/playlist_exchange_dialog.dart';
import 'package:dan_player/component/playlist_folder_export_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:dan_player/play_service/queue_order.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

class _DispatchPlayback extends PlaylistFeaturePlayback {
  _DispatchPlayback()
      : super([
          CategoryTestAudio('Original active'),
          CategoryTestAudio('Original Zulu'),
          CategoryTestAudio('Original Alpha')
        ]);

  final dispatchedQueues = <List<Audio>>[];

  @override
  int trimQueue({required bool before}) {
    dispatchedQueues.add(playlist.value);
    return 1;
  }

  @override
  bool orderUpcomingQueue({AudioSortField? field, bool reverse = false}) {
    dispatchedQueues.add(playlist.value);
    return true;
  }

  @override
  bool arrangeUpcomingQueue(UpcomingQueueOrder order) {
    dispatchedQueues.add(playlist.value);
    return true;
  }
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final action in ['trim', 'sort', 'arrange', 'm3u', 'folder']) {
    for (final replaced in [false, true]) {
      testWidgets(
          '$action menu owns ${replaced ? 'replaced' : 'unchanged'} queue before native dispatch',
          (tester) async {
        sizePlaylistFeature(tester, height: 1000);
        final playback = _DispatchPlayback();
        addTearDown(playback.dispose);
        final original = playback.playlist.value;
        var folderPicks = 0, filePicks = 0;
        await tester.pumpWidget(playlistFeatureHost(CurrentPlaylistView(
          playbackService: playback,
          pickFolderDirectory: () {
            folderPicks++;
            return null;
          },
          pickM3uFile: (_) {
            filePicks++;
            return null;
          },
        )));
        await tester.pumpAndSettle();
        await tester.tap(_key(action == 'm3u' || action == 'folder'
            ? 'queue-export-m3u'
            : 'queue-organize'));
        await tester.pumpAndSettle();
        if (action == 'sort' || action == 'arrange') {
          await tester.tap(_key('queue-extra-$action'));
          await tester.pumpAndSettle();
        }
        final choice = switch (action) {
          'trim' => 'queue-trim-after',
          'sort' => 'queue-sort-name',
          'arrange' => 'queue-order-shuffle',
          'm3u' => 'queue-export-m3u-all',
          _ => 'queue-export-folder-all',
        };
        await tester.tap(_key(choice));
        expect(playback.dispatchedQueues, isEmpty);
        expect(find.byType(M3uExportDialog), findsNothing);
        expect(find.byType(PlaylistFolderExportConfirmation), findsNothing);
        expect(folderPicks, 0,
            reason:
                'native menu action has not reached its post-frame dispatch');
        if (replaced) {
          playback.replaceQueue([
            CategoryTestAudio('Replacement active'),
            CategoryTestAudio('Replacement Zulu'),
            CategoryTestAudio('Replacement Alpha'),
            CategoryTestAudio('Replacement extra')
          ]);
        }
        final selected = playback.playlist.value;
        await tester.pumpAndSettle();
        if (action == 'm3u') {
          expect(find.byType(M3uExportDialog),
              replaced ? findsNothing : findsOneWidget,
              reason: 'an old menu cannot open export options for a new queue');
          if (!replaced) {
            expect(
                tester
                    .widget<M3uExportDialog>(find.byType(M3uExportDialog))
                    .count,
                original.length);
          }
        } else if (action == 'folder') {
          expect(find.byType(PlaylistFolderExportConfirmation),
              replaced ? findsNothing : findsOneWidget,
              reason: 'an old menu cannot ask to export a replacement queue');
          if (!replaced) {
            expect(
                tester
                    .widget<PlaylistFolderExportConfirmation>(
                        find.byType(PlaylistFolderExportConfirmation))
                    .plan
                    .entries
                    .length,
                original.length);
          }
        } else {
          expect(playback.dispatchedQueues, replaced ? isEmpty : hasLength(1),
              reason:
                  'native menu callback must retain its clicked queue owner');
          if (!replaced) {
            expect(playback.dispatchedQueues.single, same(original));
          }
        }
        expect(filePicks, 0, reason: 'no export is confirmed or written');
        expect(folderPicks, 0,
            reason: 'no folder export is confirmed or copied');
        expect(playback.playlist.value, same(selected));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
