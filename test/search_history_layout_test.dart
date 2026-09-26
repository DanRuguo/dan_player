import 'package:dan_player/app_paths.dart' as paths;
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/now_playing_bar_metrics.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/page/search_page/search_history_capsules.dart';
import 'package:dan_player/page/search_page/search_page.dart';
import 'package:dan_player/page/search_page/search_result_page.dart';
import 'package:dan_player/search/search_history.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:go_router/go_router.dart';
import 'support/search_history_fixture.dart';

void main() {
  late SearchHistoryStore history;
  setUp(() {
    history = MemorySearchHistory([
      for (var i = 11; i >= 0; i--) 'song $i',
    ]);
  });
  tearDown(() {
    history.dispose();
    uiLanguage.value = UiLanguage.zh;
  });
  Finder capsule(String query) =>
      find.byKey(ValueKey(('search-history', query)));
  Finder capsules() => find.descendant(
      of: find.byType(SearchHistoryCapsules),
      matching: find.byType(TextButton));

  Future<void> mount(WidgetTester tester,
      {Size size = const Size(900, 760), double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => UiLanguageScope(
          child: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      )),
      home: Scaffold(body: SearchPage(history: history)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'normal window centers each row and reserves the real player area',
      (tester) async {
    await mount(tester);
    final field = tester.getRect(find.byType(TextField));
    expect(field.center.dy, lessThan(760 * .45));
    expect(capsules(), findsNWidgets(12));
    final rows = <double, List<Rect>>{};
    for (final query in history.value) {
      final rect = tester.getRect(capsule(query));
      rows.putIfAbsent(rect.top, () => []).add(rect);
      expect(rect.top, greaterThan(field.bottom));
      final context = tester.element(find.byType(SearchPage));
      expect(
          rect.bottom,
          lessThanOrEqualTo(
              760 - NowPlayingBarMetrics.reservedSpace(context) - 16));
      expect(rect.left, greaterThanOrEqualTo(32));
      expect(rect.right, lessThanOrEqualTo(900 - 32));
    }
    for (final row in rows.values) {
      expect((row.first.left + row.last.right) / 2, closeTo(450, .1));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'narrow windows hide oldest terms without deleting and restore all on enlargement',
      (tester) async {
    await mount(tester);
    final original = [...history.value];
    tester.view.physicalSize = const Size(320, 430);
    await tester.pumpAndSettle();
    final count = capsules().evaluate().length;
    expect(count, inExclusiveRange(0, 12));
    expect(capsule('song 11'), findsOneWidget);
    expect(capsule('song 0'), findsNothing);
    expect(history.value, original);
    tester.view.physicalSize = const Size(900, 760);
    await tester.pumpAndSettle();
    expect(capsules(), findsNWidgets(12));
    expect(history.value, original);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'long Unicode terms ellipsize and normal area drops old full rows',
      (tester) async {
    await mount(tester);
    final context = tester.element(find.byType(SearchPage));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => rememberSearch(context, history, '$i ${'长い曲名🎵한국어 ' * 20}'));
    }
    await tester.pumpAndSettle();
    expect(history.value.length, 4);
    for (final query in history.value) {
      final rect = tester.getRect(capsule(query));
      expect(rect.width, SearchHistoryLayout.normalWidth);
      final text = tester.widget<Text>(find
          .descendant(of: capsule(query), matching: find.byType(Text))
          .last);
      expect(text.data, query);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(rect.center.dx, closeTo(450, .1));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'right click arms a stable accent capsule and the next tap deletes it',
      (tester) async {
    await mount(tester);
    final target = capsule('song 11');
    final before = tester.getRect(target);
    await tester.tap(target,
        buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.descendant(of: target, matching: find.byIcon(Symbols.close)),
        findsOneWidget);
    expect(tester.getRect(target), before);
    final button = tester.widget<TextButton>(
        find.descendant(of: target, matching: find.byType(TextButton)));
    final scheme = Theme.of(tester.element(target)).colorScheme;
    expect(button.style!.backgroundColor!.resolve({}), scheme.primary);
    expect(history.value.first, 'song 11');
    await tester.runAsync(() async {
      await tester.tap(target);
      await history.flush();
    });
    await tester.pumpAndSettle();
    expect(capsule('song 11'), findsNothing);
    expect(history.value.contains('song 11'), isFalse);
  });

  testWidgets(
      'long press only arms, repeated long press cancels, short tap deletes',
      (tester) async {
    await mount(tester);
    final target = capsule('song 10');
    await tester.longPress(target);
    await tester.pumpAndSettle();
    expect(history.value.contains('song 10'), isTrue);
    expect(find.descendant(of: target, matching: find.byIcon(Symbols.close)),
        findsOneWidget);
    await tester.longPress(target);
    await tester.pumpAndSettle();
    expect(find.descendant(of: target, matching: find.text('song 10')),
        findsOneWidget);
    await tester.longPress(target);
    await tester.runAsync(() async {
      await tester.tap(target);
      await history.flush();
    });
    await tester.pumpAndSettle();
    expect(history.value.contains('song 10'), isFalse);
  });

  testWidgets(
      'history activates the exact query and result-page searches update history',
      (tester) async {
    final requested = <String>[];
    Future<UnionSearchResult> search(String query,
        {OnlineSearchCancellation? onlineCancellation}) async {
      requested.add(query);
      return UnionSearchResult(query)
        ..online =
            Future.value(const OnlineSearchResponse(tracks: [], failures: {}));
    }

    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) =>
              Scaffold(body: SearchPage(history: history, search: search))),
      GoRoute(
          path: paths.SEARCH_RESULT_PAGE,
          builder: (_, state) => Scaffold(
                  body: SearchResultPage(
                searchResult: state.extra! as UnionSearchResult,
                search: search,
                history: history,
              ))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(capsule('song 9'));
    await tester.pumpAndSettle();
    expect(requested, ['song 9']);
    expect(history.value.first, 'song 11');
    expect(history.value.where((q) => q == 'song 9').length, 1);
    await tester.enterText(find.byType(TextField), 'résultat 🎶');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(history.value.first, 'résultat 🎶');
    expect(requested.last, 'résultat 🎶');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'four languages and enlarged text stay within the history allocation',
      (tester) async {
    await mount(tester, size: const Size(540, 600), scale: 2);
    final context = tester.element(find.byType(SearchPage));
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      await tester.pumpAndSettle();
      final newest = capsule('song 11');
      expect(newest, findsOneWidget);
      final rect = tester.getRect(newest);
      expect(
          rect.bottom,
          lessThanOrEqualTo(
              600 - NowPlayingBarMetrics.reservedSpace(context) - 16));
      expect(translateUi('再次点击删除', language), isNotEmpty);
      if (language != UiLanguage.zh) {
        expect(translateUi('再次点击删除', language), isNot('再次点击删除'));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('reduced motion keeps armed-state feedback immediate',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: MotionPreferencesScope(
      preferences: const MotionPreferences(disabled: {MotionKind.feedback}),
      child: Scaffold(body: SearchPage(history: history)),
    )));
    await tester.pumpAndSettle();
    await tester.longPress(capsule('song 11'));
    await tester.pump();
    final button = tester.widget<TextButton>(find.descendant(
        of: capsule('song 11'), matching: find.byType(TextButton)));
    expect(button.style!.animationDuration, Duration.zero);
    expect(find.byIcon(Symbols.close), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
