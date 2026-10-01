import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/song_comments_dialog.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/online/song_comments.dart';
import 'package:dan_player/online/song_comments_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/song_comments_fixtures.dart';

class _MemoryCache extends SongCommentsCache {
  _MemoryCache({this.initial})
      : super(directory: () async => throw StateError('No filesystem fixture'));

  final SongCommentsPage? initial;
  final committed = <SongCommentsPage>[];

  @override
  Future<SongCommentsPage?> read(
          SongCommentsTarget target, SongCommentSort sort, int page) async =>
      initial;

  @override
  Future<void> write(
      SongCommentsTarget target, SongCommentSort sort, SongCommentsPage result,
      {bool replaceSort = false, bool Function()? stillCurrent}) async {
    if (stillCurrent?.call() != false) committed.add(result);
  }
}

Future<void> _open(WidgetTester tester, SongCommentsService service,
    ValueNotifier<bool> hidden) async {
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => DesktopVisibilityHost(
      isHidden: hidden,
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
            onPressed: () => showSongCommentsDialog(context, commentAudio(),
                service: service),
            child: const Text('Open comments')),
      ),
    ),
  ));
  await tester.tap(find.text('Open comments'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void _restoreLifecycle(WidgetTester tester, AppLifecycleState? original) {
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  final restored = original ?? AppLifecycleState.resumed;
  if (tester.binding.lifecycleState != restored) {
    tester.binding.handleAppLifecycleStateChanged(restored);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final automatic in [true, false]) {
    for (final revoke in ['permission', 'visibility', 'lifecycle', 'route']) {
      testWidgets(
          '${automatic ? 'automatic' : 'manual'} pending comments retain '
          'their owner when $revoke changes', (tester) async {
        final preference = AppSettings.instance.automaticOnlineLyrics;
        final original = preference.value;
        preference.value = automatic;
        final hidden = ValueNotifier(false);
        final initialLifecycle = tester.binding.lifecycleState;
        NavigatorState? coveredNavigator;
        final pending = Completer<Map<String, dynamic>>();
        final transport = FakeCommentsTransport((_) => pending.future);
        final cache = _MemoryCache(
            initial: SongCommentsPage(comments: const [
          SongComment(
              id: 'saved',
              author: 'Cached',
              content: 'Saved comments',
              likeCount: 0)
        ], hasMore: false, page: 0));
        addTearDown(() {
          hidden.dispose();
          preference.value = original;
          _restoreLifecycle(tester, initialLifecycle);
        });

        await _open(tester,
            SongCommentsService(transport: transport, cache: cache), hidden);
        if (!automatic) {
          await tester.tap(find.byKey(const ValueKey('song-comments-refresh')));
          await tester.pump();
          // A manual owner remains manual even if opt-in changes around it.
          preference.value = true;
        }
        expect(transport.requests, hasLength(1));
        if (revoke == 'permission') {
          preference.value = false;
        } else if (revoke == 'visibility') {
          hidden.value = true;
        } else if (revoke == 'lifecycle') {
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        } else {
          coveredNavigator =
              Navigator.of(tester.element(find.byType(SongCommentsDialog)));
          unawaited(coveredNavigator.push(MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Text('A different route')))));
        }
        await tester.pump();
        final cancelled = transport.requests.single.cancellation.isCancelled;
        pending.complete(neteaseComments([neteaseComment(91)]));
        await tester.pumpAndSettle();
        hidden.value = false;
        _restoreLifecycle(tester, initialLifecycle);
        coveredNavigator?.pop();
        await tester.pumpAndSettle();

        expect((
          cancelled,
          cache.committed.length,
          find.text('测试评论 91').evaluate().length
        ), (
          automatic,
          automatic ? 0 : 1,
          automatic ? 0 : 1
        ),
            reason: 'Cancellation, cache commits and late visible responses '
                'follow the automatic/manual owner');
        expect(find.text('Saved comments'),
            automatic ? findsOneWidget : findsNothing);
        expect(transport.requests, hasLength(1),
            reason: 'Restoring visibility must not silently reconnect');
        if (automatic) {
          transport.handler = (_) => neteaseComments([neteaseComment(92)]);
          await tester.tap(find.byKey(const ValueKey('song-comments-refresh')));
          await tester.pumpAndSettle();
          expect(transport.requests, hasLength(2));
          expect(find.text('测试评论 92'), findsOneWidget);
          expect(cache.committed, hasLength(1),
              reason:
                  'Cancelling an automatic owner keeps manual retry usable');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
