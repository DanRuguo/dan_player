import 'dart:async';

import 'package:dan_player/app_paths.dart' as paths;
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/online/online_source_preferences.dart';
import 'package:dan_player/page/search_page/search_page.dart';
import 'package:dan_player/page/search_page/search_result_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

UnionSearchResult emptyResult(String query) => UnionSearchResult(query)
  ..online = Future.value(const OnlineSearchResponse(tracks: [], failures: {}));

void main() {
  testWidgets(
      'early provider failure stays observed and is later shown by results',
      (tester) async {
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () => const OnlineSourcePreferences(
          qqEnabled: false, neteaseEnabled: false),
      qqSearch: (_, __) async => throw StateError('Disabled QQ must not run'),
      neteaseSearch: (_, __) async =>
          throw StateError('Disabled NetEase must not run'),
    );
    final provider = service.search('demo');
    final result = UnionSearchResult('demo')..online = provider;
    // Deliberately allow the real all-sources-disabled failure to complete
    // before navigation creates any FutureBuilder listener.
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(result.online, same(provider));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SearchResultPage(searchResult: result))));
    await tester.pumpAndSettle();
    expect(find.textContaining(onlineSourcesDisabledMessage), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await expectLater(result.online, throwsA(isA<OnlineMusicException>()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mouse search deduplicates Enter and discards a replaced query',
      (tester) async {
    final requests = <String, Completer<UnionSearchResult>>{};
    final cancellations = <String, OnlineSearchCancellation>{};
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: SearchPage(search: (query, {onlineCancellation}) {
            expect(requests.containsKey(query), isFalse);
            cancellations[query] = onlineCancellation!;
            return (requests[query] = Completer<UnionSearchResult>()).future;
          }),
        ),
      ),
      GoRoute(
        path: paths.SEARCH_RESULT_PAGE,
        builder: (_, state) => Scaffold(
          body: Text('Result ${(state.extra! as UnionSearchResult).query}'),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'first');
    await tester.pump();
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    expect(requests.keys, ['first']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'second');
    await tester.pump();
    expect(cancellations['first']!.isCancelled, isTrue);
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    final stale = emptyResult('first');
    requests['first']!.complete(stale);
    await tester.pump();
    expect(stale.onlineCancellation.isCancelled, isTrue);
    expect(find.text('Result first'), findsNothing);
    requests['second']!.complete(emptyResult('second'));
    await tester.pumpAndSettle();
    expect(find.text('Result second'), findsOneWidget);
    expect(cancellations['second']!.isCancelled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed search remains editable and fits a short enlarged window',
      (tester) async {
    tester.view.physicalSize = const Size(360, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(body: SearchPage(search: (_, {onlineCancellation}) async {
        throw StateError('index unavailable');
      })),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'demo');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('搜索暂时不可用，请重试。'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.ensureVisible(find.byTooltip('清除搜索'));
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(find.text('搜索暂时不可用，请重试。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library refresh cannot discard a newly submitted result query',
      (tester) async {
    final pending = Completer<UnionSearchResult>();
    final old = emptyResult('old');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: SearchResultPage(
          searchResult: old,
          search: (_, {onlineCancellation}) => pending.future),
    )));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'new');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    AudioLibrary.searchRevision++;
    AudioLibrary.changes.value++;
    await tester.pump();
    pending.complete(emptyResult('new'));
    await tester.pumpAndSettle();
    expect(old.onlineCancellation.isCancelled, isTrue,
        reason: 'The new result takes ownership after it is ready.');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('new-all')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
