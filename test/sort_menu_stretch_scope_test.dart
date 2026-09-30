import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/component/playlist_song_picker.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/audio_sort_methods.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:desktop_lyric/app_edge_stretch.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _audio = Audio.online(
  provider: 'qq',
  id: 'sort-scope',
  title: 'Sort scope song',
  artist: 'Artist',
  album: 'Album',
  duration: 120,
);

Widget _host(Widget Function(BuildContext) controls) => MaterialApp(
      scrollBehavior: const DanPlayerScrollBehavior(),
      theme: ThemeData(platform: TargetPlatform.windows),
      home: Scaffold(
        body: Stack(children: [
          ListView.builder(
            key: const ValueKey('page-scroll'),
            itemExtent: 40,
            itemCount: 40,
            itemBuilder: (_, index) => Text('Page $index'),
          ),
          Align(
            alignment: Alignment.topRight,
            child: Builder(builder: controls),
          ),
        ]),
      ),
    );

Widget _playlistToolbar(bool isRoot, ValueChanged<PlaylistSortMode> onSort) =>
    SizedBox(
      width: 900,
      child: PlaylistToolbar(
        isRoot: isRoot,
        hasItems: true,
        canPlay: true,
        sortMode: PlaylistSortMode.nameAscending,
        onCreate: () {},
        onStartSelection: () {},
        onEndSelection: () {},
        onSelectAll: () {},
        onRemoveSelected: () {},
        onSortChanged: onSort,
      ),
    );

void main() {
  testWidgets('scoped sorting shader does not change a sibling popup',
      (tester) async {
    await tester.pumpWidget(_host((context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSortButton<int>(
              key: const ValueKey('scoped-sort'),
              value: 0,
              onChanged: (_) {},
              options: [
                for (var index = 0; index < 20; index++)
                  AppSortOption(
                      value: index, label: 'Sort $index', icon: Icons.sort),
              ],
            ),
            PopupMenuButton<int>(
              key: const ValueKey('ordinary-popup'),
              itemBuilder: (_) => [
                for (var index = 0; index < 20; index++)
                  PopupMenuItem(value: index, child: Text('Other $index')),
              ],
            ),
          ],
        )));
    await tester.tap(find.byKey(const ValueKey('ordinary-popup')));
    await tester.pumpAndSettle();
    expect(find.byType(AppStretchingOverscrollIndicator), findsNothing);
    expect(find.byType(StretchingOverscrollIndicator), findsNWidgets(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scoped-sort')));
    await tester.pumpAndSettle();
    expect(find.byType(AppStretchingOverscrollIndicator), findsOneWidget);
    expect(find.byType(StretchingOverscrollIndicator), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AppStretchingOverscrollIndicator), findsNothing);
  });

  for (final source in ['music', 'playlist-root', 'playlist-child', 'picker']) {
    testWidgets(
        '$source sort popup keeps local shader stretch and quick reveal',
        (tester) async {
      tester.view.physicalSize = const Size(900, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final selected = <Object>[];
      final custom = SortMethodDesc<Audio>(
        icon: Icons.drag_handle,
        name: '自定义',
        method: (list, order) {},
      );
      await tester.pumpWidget(_host((context) => switch (source) {
            'music' => SortMethodComboBox<Audio>(
                contentList: [_audio],
                sortMethods:
                    audioSortMethods(AudioSortProfile.library, custom: custom),
                currSortMethod:
                    audioSortMethods(AudioSortProfile.library, custom: custom)
                        .first,
                setSortMethod: selected.add,
                sortOrder: SortOrder.ascending,
                setSortOrder: selected.add,
              ),
            'playlist-root' => _playlistToolbar(true, selected.add),
            'playlist-child' => _playlistToolbar(false, selected.add),
            _ => TextButton(
                key: const ValueKey('open-picker'),
                onPressed: () => showPlaylistSongPicker(
                  context,
                  existingPaths: const {},
                  library: [_audio],
                  replaceSelection: true,
                ),
                child: const Text('Open picker'),
              ),
          }));
      expect(find.byType(StretchingOverscrollIndicator), findsOneWidget,
          reason: 'The ordinary page must retain its native stretch.');
      expect(find.byType(AppStretchingOverscrollIndicator), findsNothing);

      if (source == 'picker') {
        await tester.tap(find.byKey(const ValueKey('open-picker')));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
      }
      final backgroundStableCount =
          find.byType(AppStretchingOverscrollIndicator).evaluate().length;
      final sort = source == 'picker'
          ? find.byKey(const ValueKey('playlist-song-sort'))
          : source == 'music'
              ? find.byType(AppSortButton<int>)
              : find.byKey(const ValueKey('playlist-sort'));
      await tester.tap(sort);
      await tester.pumpAndSettle();

      final optionKey = switch (source) {
        'music' => const ValueKey('sort-method-1'),
        'playlist-root' ||
        'playlist-child' =>
          const ValueKey('playlist-sort-songCount'),
        _ => const ValueKey('playlist-picker-sort-artist'),
      };
      final option = find.byKey(optionKey);
      expect(option, findsOneWidget);
      final route = ModalRoute.of(tester.element(option));
      expect(route, isA<PopupRoute>());
      expect(route!.transitionDuration, const Duration(milliseconds: 120));
      final viewport = find
          .ancestor(of: option, matching: find.byType(SingleChildScrollView))
          .first;
      final stable = find.descendant(
          of: viewport,
          matching: find.byType(AppStretchingOverscrollIndicator));
      expect(stable, findsOneWidget,
          reason:
              'Only the sorting popup scroll viewport opts into the shader.');
      expect(find.byType(AppStretchingOverscrollIndicator),
          findsNWidgets(backgroundStableCount + 1));
      expect(find.byType(StretchingOverscrollIndicator), findsOneWidget);
      final effect =
          find.descendant(of: stable, matching: find.byType(AppStretchEffect));
      expect(effect, findsOneWidget);
      final scrollPosition = tester
          .state<ScrollableState>(
              find.descendant(of: viewport, matching: find.byType(Scrollable)))
          .position;
      expect(scrollPosition.maxScrollExtent, greaterThan(0),
          reason: 'This source must reach an actual overscroll edge.');
      expect(scrollPosition.pixels, 0);

      final pull = await tester.startGesture(tester.getCenter(viewport),
          kind: PointerDeviceKind.touch);
      await pull.moveBy(const Offset(0, 30));
      await tester.pump();
      await pull.moveBy(const Offset(0, 90));
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.widget<AppStretchEffect>(effect).stretchStrength.abs(),
          greaterThan(0));
      expect(selected, isEmpty);
      await pull.up();
      await tester.pumpAndSettle();
      expect(tester.widget<AppStretchEffect>(effect).stretchStrength, 0);

      await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(viewport),
        scrollDelta: const Offset(0, 320),
      ));
      await tester.pumpAndSettle();
      expect(scrollPosition.pixels, greaterThan(0));
      expect(selected, isEmpty);
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(find.byType(AppStretchingOverscrollIndicator),
          findsNWidgets(backgroundStableCount),
          reason: 'The popup shader must leave with its route.');
      expect(find.byType(StretchingOverscrollIndicator), findsOneWidget);
      if (source == 'picker') {
        expect(find.text('艺术家 · 升序'), findsOneWidget);
      } else {
        expect(selected, hasLength(1));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
