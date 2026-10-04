import 'package:dan_player/component/song_comment_match_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/online/song_comments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/song_comments_fixtures.dart';

const _open = ValueKey('match-owner-open');
const _owner = ValueKey('match-owner-page');

class _Pops extends NavigatorObserver {
  int count = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => count++;
}

void main() {
  for (final confirm in [false, true]) {
    testWidgets(
        'repeated ${confirm ? 'confirm' : 'cancel'} preserves match owner',
        (tester) async {
      final observer = _Pops();
      final candidate = commentAudio(title: 'Fixture candidate');
      Audio? selected;
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [observer],
        home: Builder(builder: (context) {
          return TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                key: _owner,
                body: Builder(builder: (context) {
                  return TextButton(
                    key: _open,
                    onPressed: () async {
                      selected = await showSongCommentMatchDialog(
                        context,
                        localAudio: localCommentAudio(),
                        search: (_) async => OnlineSearchResponse(
                            tracks: [candidate], failures: const {}),
                        commentsService: SongCommentsService(
                          transport:
                              FakeCommentsTransport((_) => neteaseComments([])),
                        ),
                      );
                    },
                    child: const Text('Open match'),
                  );
                }),
              ),
            )),
            child: const Text('Enter fixture'),
          );
        }),
      ));
      await tester.tap(find.text('Enter fixture'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_open));
      await tester.pumpAndSettle();
      VoidCallback dismiss;
      if (confirm) {
        await tester.tap(find.text('Fixture candidate'));
        await tester.pumpAndSettle();
        dismiss = tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('song-comment-match-confirm')))
            .onPressed!;
      } else {
        dismiss = tester
            .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
            .onPressed!;
      }
      // Both callbacks can be queued before the reverse route frame disables
      // hit testing. A second callback must not dismiss the owner page.
      dismiss();
      dismiss();
      await tester.pumpAndSettle();
      expect(observer.count, 1);
      expect(find.byKey(_owner), findsOneWidget);
      expect(selected, confirm ? same(candidate) : isNull);
      expect(find.byType(SongCommentMatchDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
