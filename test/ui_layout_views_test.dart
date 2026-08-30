import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/audio_columns.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_reorder_surface.dart';
import 'package:dan_player/component/ui_layout_options.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/ui_layout_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

const _columns =
    UiLayoutPreferences(libraryRowLayout: LibraryRowLayout.columns);

Widget _app(Widget child,
        {UiLayoutPreferences prefs = _columns,
        double scale = 1,
        Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal, brightness: brightness)),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale), disableAnimations: true),
          child: UiLayoutScope(preferences: prefs, child: child!)),
      home: Scaffold(body: child),
    );

void _size(WidgetTester tester, double width, {double height = 760}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _library(List<Audio> audios,
        {MultiSelectController<Audio>? selection,
        void Function(List<Audio>)? reordered}) =>
    UniPage<Audio>(
      pref: PagePreference(0, SortOrder.ascending, ContentView.list),
      title: '测试曲库',
      contentList: audios,
      enableAudioColumns: true,
      contentBuilder: (context, audio, index, select) => AudioTile(
          audioIndex: index,
          playlist: audios,
          multiSelectController: select,
          columns: AudioColumnsScope.of(context)),
      enableShufflePlay: false,
      enableSortMethod: reordered != null,
      enableSortOrder: false,
      enableContentViewSwitch: false,
      sortMethods: reordered == null
          ? null
          : [
              SortMethodDesc<Audio>(
                  icon: Icons.drag_handle,
                  name: '自定义',
                  usesSortOrder: false,
                  supportsReorder: true,
                  method: (_, __) {},
                  onReorder: reordered)
            ],
      multiSelectController: selection,
      multiSelectViewActions: const [],
    );

void main() {
  test('layout preferences round-trip, defaults and malformed values', () {
    const legacy = UiLayoutPreferences();
    expect(UiLayoutPreferences.fromMap(null), legacy);
    expect(UiLayoutPreferences.fromMap(const {}), legacy);
    expect(
        UiLayoutPreferences.fromMap(
            const {'libraryRowLayout': 'future', 'compactPlaylists': 4}),
        legacy);
    for (final layout in LibraryRowLayout.values) {
      for (final compact in [true, false]) {
        final value = UiLayoutPreferences(
            libraryRowLayout: layout, compactPlaylists: compact);
        expect(UiLayoutPreferences.fromMap(value.toMap()), value);
        expect(value.copyWith().hashCode, value.hashCode);
      }
    }
  });

  test('folder identities retain roots and separate duplicate names', () {
    expect(folderDisplayName(r'C:\Music\Albums'), 'Albums');
    expect(folderDisplayName(r'D:\Music\Albums\'), 'Albums');
    expect(folderDisplayName(r'\\nas\music\Albums'), 'Albums');
    expect(folderDisplayName(r'C:\'), r'C:\');
    expect(folderDisplayName(''), '未命名文件夹');
  });

  for (final width in [320.0, 507.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('folder identity fits $width/$scale/$brightness',
            (tester) async {
          _size(tester, width);
          const path = r'D:\音乐收藏\游戏原声与多语言专辑\Albums';
          final folder =
              AudioFolder([CategoryTestAudio('song')], path, 100000, 0);
          await tester.pumpWidget(_app(
              Builder(
                  builder: (context) => Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                          height: folderTileExtent(context),
                          child: AudioFolderTile(audioFolder: folder)))),
              scale: scale,
              brightness: brightness));
          expect(find.text('Albums'), findsOneWidget);
          expect(find.textContaining('1 首歌曲'), findsOneWidget);
          expect(find.textContaining(' › '), findsOneWidget);
          expect(find.byTooltip(path), findsOneWidget);
          expect(
              tester
                  .widget<InkWell>(
                      find.byKey(const ValueKey('folder-open-$path')))
                  .onTap,
              isNotNull);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final width in [320.0, 507.0, 1280.0, 1800.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('columns fall back safely at $width/$scale', (tester) async {
        _size(tester, width);
        final audios = <Audio>[
          CategoryTestAudio('Long title · 多语言 👩🏽‍🎤',
              composer: 'Composer', artist: 'Artist', album: 'Album')
        ];
        await tester.pumpWidget(_app(_library(audios), scale: scale));
        await tester.pumpAndSettle();
        final columns = width - 56 >= 700 * scale;
        expect(find.byType(AudioColumnsHeader),
            columns ? findsOneWidget : findsNothing);
        expect(find.byKey(const ValueKey('audio-columns-row')),
            columns ? findsOneWidget : findsNothing);
        if (columns) {
          expect(find.text('Composer'), findsOneWidget);
          expect(find.text('Album'), findsOneWidget);
          await tester.tap(
              find.byKey(ValueKey('audio-columns-menu-${audios.first.path}')));
          await tester.pumpAndSettle();
          expect(find.text('编辑歌曲信息'), findsOneWidget);
          expect(find.text('加入歌单…'), findsOneWidget);
        }
        expect(PlayService.isInitialized, false);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'column selection and custom order retain the original audio mapping',
      (tester) async {
    _size(tester, 1280);
    final audios = <Audio>[
      for (var i = 0; i < 3; i++) CategoryTestAudio('Song$i')
    ];
    final selection = MultiSelectController<Audio>()..useMultiSelectView(true);
    addTearDown(selection.dispose);
    await tester.pumpWidget(_app(_library(audios, selection: selection)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Song1'));
    expect(selection.selected, {audios[1]});
    selection.useMultiSelectView(false);
    List<Audio>? saved;
    await tester.pumpWidget(
        _app(_library(audios, reordered: (value) => saved = List.of(value))));
    await tester.pumpAndSettle();
    final reorder =
        tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    reorder.onReorderItem!(0, 2);
    await tester.pumpAndSettle();
    expect(audios.map((audio) => audio.title), ['Song1', 'Song2', 'Song0']);
    expect(saved, audios);
    expect(find.byType(AudioColumnsHeader), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing presentation retains scroll controller and offset',
      (tester) async {
    _size(tester, 1280);
    final audios = <Audio>[
      for (var i = 0; i < 70; i++) CategoryTestAudio('Song$i')
    ];
    await tester
        .pumpWidget(_app(_library(audios), prefs: const UiLayoutPreferences()));
    await tester.pumpAndSettle();
    final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
    scroll.jumpTo(600);
    await tester.pump();
    await tester.pumpWidget(_app(_library(audios)));
    await tester.pumpAndSettle();
    expect(tester.widget<ListView>(find.byType(ListView)).controller,
        same(scroll));
    expect(scroll.offset, 600);
    expect(find.byType(AudioColumnsHeader), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings choices keep unrelated preferences and fit large text',
      (tester) async {
    _size(tester, 320);
    var value = const UiLayoutPreferences();
    await tester.pumpWidget(_app(
        StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
                child: UiLayoutOptions(
                    value: value,
                    onChanged: (next) => setState(() => value = next)))),
        scale: 2));
    // At 320px / 200% the same explicit alternatives live in a readable menu.
    await tester.tap(find.byTooltip('音乐列表样式 · 经典列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('资源管理器分栏'));
    await tester.pumpAndSettle();
    expect(value.libraryRowLayout, LibraryRowLayout.columns);
    expect(value.compactPlaylists, true);
    expect(tester.takeException(), isNull);
  });

  for (final width in [507.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'compact playlist preserves menus/queue/row order $width/$scale',
          (tester) async {
        _size(tester, width, height: 900);
        final roots = <Playlist>[];
        final tree = PlaylistTree(roots);
        final parent = tree.createPlaylist('Parent');
        final child = tree.createPlaylist('Child', parent: parent);
        tree.addAudio(child, CategoryTestAudio('Song'));
        final second = tree.createPlaylist('Second', parent: parent);
        final played = <Audio>[];
        Widget browser() => PlaylistBrowser(
            tree: tree,
            initialPlaylist: parent,
            persist: () async {},
            onPlay: (_, queue) => played.addAll(queue),
            trackBuilder: (_, audio, play, actions) => ListTile(
                title: Text(audio.title), onTap: play, trailing: actions));
        await tester.pumpWidget(_app(browser(), scale: scale));
        await tester.pumpAndSettle();
        expect(
            tester.getSize(find.byKey(const ValueKey('playlist-header-cover'))),
            const Size.square(64));
        expect(find.byType(PlaylistReorderSurface), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('playlist-play-${child.id}')));
        expect(played.single.title, 'Song');
        final surface = tester.widget<PlaylistReorderSurface>(
            find.byType(PlaylistReorderSurface));
        surface.onReorder(surface.items.first, 1);
        await tester.pumpAndSettle();
        expect(parent.entries.first.childPlaylist, same(second));
        await tester.tap(find.byKey(ValueKey('playlist-menu-${child.id}')));
        await tester.pumpAndSettle();
        expect(find.text('重命名'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
