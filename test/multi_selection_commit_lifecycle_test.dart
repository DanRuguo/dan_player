import 'dart:async';

import 'package:dan_player/component/multi_selection_lifecycle.dart';
import 'package:dan_player/component/playlist_destination_dialog.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _add(WidgetTester tester) async {
  await tester.tap(_key('audio-selection-more'));
  await tester.pumpAndSettle();
  await tester.tap(_key('audio-selection-playlist'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    uiLanguage.value = UiLanguage.zh;
    playlistUiSaveError.value = null;
  });

  for (final committed in [false, true]) {
    testWidgets('a real menu commit=$committed preserves or exits its session',
        (tester) async {
      final a = CategoryTestAudio('A'), b = CategoryTestAudio('B');
      final selection = MultiSelectController<Audio>()
        ..useMultiSelectView(true)
        ..selectAll([b, a]);
      addTearDown(selection.dispose);
      final result = Completer<bool>();
      List<Audio>? snapshot;
      await tester.pumpWidget(playlistFeatureHost(AudioMultiSelectionActions(
          controller: selection,
          contentList: [a, b],
          onAddToPlaylistCommitted: (items) {
            snapshot = items;
            return result.future;
          })));
      await _add(tester);
      expect(snapshot, [a, b]);
      expect(selection.enableMultiSelectView, isTrue);
      expect(selection.selected, {a, b});
      result.complete(committed);
      await tester.pumpAndSettle();
      expect(selection.enableMultiSelectView, !committed);
      expect(selection.selected, committed ? isEmpty : {a, b});
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a thrown batch action retains selections for retry',
      (tester) async {
    final audio = CategoryTestAudio('A');
    final selection = MultiSelectController<Audio>()
      ..useMultiSelectView(true)
      ..select(audio);
    addTearDown(selection.dispose);
    await tester.pumpWidget(playlistFeatureHost(AudioMultiSelectionActions(
        controller: selection,
        contentList: [audio],
        onAddToPlaylistCommitted: (_) async =>
            throw StateError('fixture failure'))));
    await _add(tester);
    expect(selection.enableMultiSelectView, isTrue);
    expect(selection.selected, {audio});
    expect(find.byKey(const ValueKey('app-notice-bubble')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late success cannot clear a reentered selection session',
      (tester) async {
    final a = CategoryTestAudio('A'), b = CategoryTestAudio('B');
    final selection = MultiSelectController<Audio>()
      ..useMultiSelectView(true)
      ..select(a);
    addTearDown(selection.dispose);
    final result = Completer<bool>();
    await tester.pumpWidget(playlistFeatureHost(AudioMultiSelectionActions(
        controller: selection,
        contentList: [a, b],
        onAddToPlaylistCommitted: (_) => result.future)));
    await _add(tester);
    selection.exitMultiSelect();
    selection.useMultiSelectView(true);
    selection.select(b);
    await tester.pump();
    result.complete(true);
    await tester.pumpAndSettle();
    expect(selection.enableMultiSelectView, isTrue);
    expect(selection.selected, {b});
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy void actions do not assert a successful commit',
      (tester) async {
    final audio = CategoryTestAudio('A');
    final selection = MultiSelectController<Audio>()
      ..useMultiSelectView(true)
      ..select(audio);
    addTearDown(selection.dispose);
    var calls = 0;
    await tester.pumpWidget(playlistFeatureHost(AudioMultiSelectionActions(
        controller: selection,
        contentList: [audio],
        onAddToPlaylist: (_) {
          calls++;
        })));
    await _add(tester);
    expect(calls, 1);
    expect(selection.enableMultiSelectView, isTrue);
    expect(selection.selected, {audio});
  });

  testWidgets('successful selected playback exits and failed playback remains',
      (tester) async {
    final audio = CategoryTestAudio('A');
    final selection = MultiSelectController<Audio>()
      ..useMultiSelectView(true)
      ..select(audio);
    addTearDown(selection.dispose);
    var committed = false;
    await tester.pumpWidget(playlistFeatureHost(AudioMultiSelectionActions(
        controller: selection,
        contentList: [audio],
        onPlayCommitted: (_) async => committed)));
    await tester.tap(_key('audio-selection-play'));
    await tester.pumpAndSettle();
    expect(selection.enableMultiSelectView, isTrue);
    committed = true;
    await tester.tap(_key('audio-selection-play'));
    await tester.pumpAndSettle();
    expect(selection.enableMultiSelectView, isFalse);
    expect(selection.selected, isEmpty);
  });

  testWidgets(
      'playlist addition reports cancel, persisted success and no unsaved false success',
      (tester) async {
    sizePlaylistFeature(tester);
    final tree = PlaylistTree([]);
    final target = tree.createPlaylist('Destination');
    final audio = CategoryTestAudio('A');
    var saves = 0;
    var fail = true;
    bool? result;
    await tester.pumpWidget(playlistFeatureHost(Builder(
        builder: (context) => FilledButton(
            onPressed: () async {
              result = await showAddAudiosToPlaylistDialog(context, [audio],
                  tree: tree, persist: () async {
                saves++;
                if (fail) throw StateError('disk failure');
              });
            },
            child: const Text('Add')))));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(saves, 0);
    for (final failing in [true, false]) {
      fail = failing;
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Destination'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '添加'));
      await tester.pumpAndSettle();
      expect(result, !failing);
      expect(target.flattenAudios(), [audio]);
    }
    expect(saves, 2,
        reason: 'retry must persist the retained in-memory addition');
    expect(playlistUiSaveError.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'popup and hidden window retain selection while real push and replacement leave',
      (tester) async {
    final selection = MultiSelectController<String>()
      ..useMultiSelectView(true)
      ..select('A');
    addTearDown(selection.dispose);
    final navigator = GlobalKey<NavigatorState>();
    var ticks = true;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [MultiSelectionRouteObserver()],
        home: StatefulBuilder(builder: (context, setState) {
          update = setState;
          return SelectionPageLifecycle(
              onLeave: selection.exitMultiSelect,
              child: TickerMode(
                  enabled: ticks, child: const Scaffold(body: Text('Page'))));
        })));
    await tester.pumpAndSettle();
    unawaited(showDialog<void>(
        context: tester.element(find.text('Page')),
        builder: (_) => const AlertDialog(content: Text('Temporary'))));
    await tester.pumpAndSettle();
    expect(selection.enableMultiSelectView, isTrue);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    update(() => ticks = false);
    await tester.pump();
    expect(selection.enableMultiSelectView, isTrue);
    unawaited(navigator.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => const Text('Next'))));
    await tester.pumpAndSettle();
    expect(selection.enableMultiSelectView, isFalse);
    selection.useMultiSelectView(true);
    selection.select('B');
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(selection.selected, {'B'},
        reason: 'returning to a page must not clear a new session');
    unawaited(navigator.currentState!.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const Text('Replacement'))));
    await tester.pumpAndSettle();
    expect(selection.enableMultiSelectView, isFalse);
    expect(selection.selected, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Shell selection receives root page push and Shell go replacement only',
      (tester) async {
    final selection = MultiSelectController<String>()
      ..useMultiSelectView(true)
      ..select('A');
    addTearDown(selection.dispose);
    final root = GlobalKey<NavigatorState>();
    final shell = GlobalKey<NavigatorState>();
    final router =
        GoRouter(navigatorKey: root, initialLocation: '/library', observers: [
      MultiSelectionRouteObserver()
    ], routes: [
      ShellRoute(
          navigatorKey: shell,
          observers: [MultiSelectionRouteObserver()],
          builder: (_, __, child) => Scaffold(body: child),
          routes: [
            GoRoute(
                path: '/library',
                builder: (_, __) => SelectionPageLifecycle(
                    onLeave: selection.exitMultiSelect,
                    child: const Text('Library'))),
            GoRoute(path: '/other', builder: (_, __) => const Text('Other')),
          ]),
      GoRoute(
          path: '/playing',
          parentNavigatorKey: root,
          builder: (_, __) => const Text('Playing')),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    unawaited(showDialog<void>(
        context: tester.element(find.text('Library')),
        builder: (_) => const AlertDialog(content: Text('Temporary'))));
    await tester.pumpAndSettle();
    expect(selection.selected, {'A'});
    root.currentState!.pop();
    await tester.pumpAndSettle();
    unawaited(router.push('/playing'));
    await tester.pumpAndSettle();
    expect(selection.selected, isEmpty);
    selection.useMultiSelectView(true);
    selection.select('B');
    router.pop();
    await tester.pumpAndSettle();
    expect(selection.selected, {'B'});
    router.go('/other');
    await tester.pumpAndSettle();
    expect(selection.selected, isEmpty);
    expect(selection.enableMultiSelectView, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a disposed page unsubscribes without retaining its selection callback',
      (tester) async {
    final observer = MultiSelectionRouteObserver();
    final navigator = GlobalKey<NavigatorState>();
    var leaves = 0;
    var visible = true;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        home: StatefulBuilder(builder: (_, setState) {
          update = setState;
          return visible
              ? SelectionPageLifecycle(
                  onLeave: () => leaves++, child: const Text('Present'))
              : const Text('Removed');
        })));
    await tester.pumpAndSettle();
    update(() => visible = false);
    await tester.pumpAndSettle();
    unawaited(navigator.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => const Text('Next'))));
    await tester.pumpAndSettle();
    expect(leaves, 0);
    expect(tester.takeException(), isNull);
  });
}
