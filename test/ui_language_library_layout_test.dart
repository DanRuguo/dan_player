import 'dart:ui' show PointerDeviceKind;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_action_icon.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/audio_columns.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_reorder_surface.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/ui_layout_preferences.dart';
import 'package:desktop_lyric/l10n/ui_catalog.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'support/music_category_fixtures.dart';
import 'support/playlist_actions.dart';

const _mediaTitle = '取消 {0} · 再生 · 음악 👩🏽‍🎤 e\u0301';
const _mediaAlbum = '专辑 {1} · Album / アルバム / 앨범';
const _mediaComposer = '作曲家 · Composer / 作曲者 / 작곡가';
const _folderPath = r'D:\Music\音乐 / アルバム\앨범\Collection {0}';
const _columns =
    UiLayoutPreferences(libraryRowLayout: LibraryRowLayout.columns);

// The production language scope/transition retains the exact same page child.
// FontLoader below avoids Ahem's artificial glyph widths and line metrics.
Widget _app(Widget child,
        {UiLayoutPreferences preferences = _columns,
        Color seed = Colors.teal,
        Brightness brightness = Brightness.light}) =>
    ValueListenableBuilder<UiLanguage>(
      valueListenable: uiLanguage,
      child: Scaffold(body: child),
      builder: (context, language, child) => MaterialApp(
        locale: language.locale,
        supportedLocales: [
          for (final language in UiLanguage.values) language.locale
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        themeAnimationDuration: Duration.zero,
        theme: ThemeData(
          platform: TargetPlatform.windows,
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback,
          colorScheme:
              ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: UiLanguageScope(
            child: UiLanguageTransition(
              child: UiLayoutScope(preferences: preferences, child: child!),
            ),
          ),
        ),
        home: child,
      ),
    );

void _size(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settle(WidgetTester tester, String phase) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: phase);
}

class _Library extends StatelessWidget {
  _Library(this.audios, {this.selection, this.reordered});
  final List<Audio> audios;
  final MultiSelectController<Audio>? selection;
  final void Function(List<Audio>)? reordered;
  final pref = PagePreference(0, SortOrder.ascending, ContentView.list);

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return UniPage<Audio>(
      pref: pref,
      title: ui('音乐'),
      contentList: audios,
      enableAudioColumns: true,
      contentBuilder: (context, audio, index, select) => AudioTile(
        audioIndex: index,
        playlist: audios,
        multiSelectController: select,
        columns: AudioColumnsScope.of(context),
      ),
      enableShufflePlay: false,
      enableSortMethod: reordered != null,
      enableSortOrder: false,
      enableContentViewSwitch: false,
      sortMethods: reordered == null
          ? null
          : [
              SortMethodDesc<Audio>(
                icon: Icons.drag_handle,
                name: ui('自定义'),
                usesSortOrder: false,
                supportsReorder: true,
                method: (_, __) {},
                onReorder: reordered,
              ),
            ],
      multiSelectController: selection,
      multiSelectViewActions: const [],
    );
  }
}

class _Playlists {
  final roots = <Playlist>[];
  late final tree = PlaylistTree(roots);
  late final parent = tree.createPlaylist(_mediaTitle);
  final played = <({int index, List<Audio> queue})>[];
  int saves = 0;

  Widget browser({bool root = false}) => PlaylistBrowser(
        tree: tree,
        initialPlaylist: root ? null : parent,
        persist: () async => saves++,
        onPlay: (index, queue) =>
            played.add((index: index, queue: List.of(queue))),
        // Playlist cards, toolbar, menus, scroll, selection and reorder are all
        // production widgets. Inject only the track leaf/playback boundary.
        trackBuilder: (_, audio, play, actions) => ListTile(
          title:
              Text(audio.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: play,
          trailing: actions,
        ),
      );
}

void _folderFixture({int count = 1, ContentView view = ContentView.list}) {
  final library = AudioLibrary.instance;
  final previousFolders = library.folders;
  final previousPreference = AppPreference.instance.foldersPagePref;
  library.folders = [
    for (var i = 0; i < count; i++)
      AudioFolder(
          [CategoryTestAudio(_mediaTitle)],
          count == 1
              ? _folderPath
              : 'D:\\Music\\Collection ${i.toString().padLeft(3, '0')}',
          0,
          0),
  ];
  AppPreference.instance.foldersPagePref =
      PagePreference(0, SortOrder.ascending, view);
  addTearDown(() {
    library.folders = previousFolders;
    AppPreference.instance.foldersPagePref = previousPreference;
  });
}

ColorScheme _scheme(WidgetTester tester, Finder finder) =>
    Theme.of(tester.element(finder)).colorScheme;

void _checkActionTheme(WidgetTester tester, Finder finder) {
  final iconButton =
      find.descendant(of: finder, matching: find.byType(IconButton));
  final button = tester.widget<IconButton>(iconButton);
  final scheme = _scheme(tester, finder);
  expect(button.style!.foregroundColor!.resolve({}), scheme.primary,
      reason: 'action icons follow the same live accent as player controls');
  expect(button.style!.foregroundColor!.resolve({WidgetState.disabled}),
      scheme.onSurface.withValues(alpha: .38));
  expect(tester.getSize(finder).width, 44);
  expect(tester.getSize(finder).height, greaterThanOrEqualTo(44));
}

Future<void> _openAudioMenu(
    WidgetTester tester, bool columns, Audio audio) async {
  if (columns) {
    final menu = find.byKey(ValueKey('audio-columns-menu-${audio.path}'));
    _checkActionTheme(tester, menu);
    await tester.tap(menu);
  } else {
    await tester.tap(find.text(audio.title), buttons: kSecondaryMouseButton);
  }
  await _settle(tester, 'translated audio menu');
  expect(find.text(ui('编辑歌曲信息')), findsOneWidget);
  expect(find.text(ui('加入歌单…')), findsOneWidget);
  // Closing a menu must not activate the row or initialize native playback.
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await _settle(tester, 'close audio menu');
}

ScrollController _playlistScroll(WidgetTester tester) => tester
    .widget<CustomScrollView>(find.descendant(
      of: find.byType(PlaylistReorderSurface),
      matching: find.byType(CustomScrollView),
    ))
    .controller!;

Future<void> _switch(WidgetTester tester, UiLanguage language) async {
  uiLanguage.value = language;
  await _settle(tester, 'live language switch to ${language.code}');
  expect(Localizations.localeOf(tester.element(find.byType(Scaffold))),
      language.locale);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader(danEmbeddedFontFamily)
      ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf'));
    await loader.load();
  });
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() {
    uiLanguage.value = UiLanguage.zh;
    expect(PlayService.isInitialized, isFalse,
        reason: 'In-memory layout fixtures must not start native playback');
  });

  test('matrix uses explicit translations rather than Chinese fallback', () {
    for (final key in [
      '文件夹',
      '音乐',
      '歌名',
      '作曲家',
      '专辑',
      '时长',
      '播放此歌单（含子歌单）',
      '编辑歌曲信息',
      '加入歌单…',
      '重命名'
    ]) {
      expect(uiCatalog[key], hasLength(3), reason: key);
      for (final language in UiLanguage.values.skip(1)) {
        expect(translateUi(key, language), isNotEmpty);
      }
    }
    expect(translateUi('文件夹', UiLanguage.en), 'Folders');
    expect(translateUi('文件夹', UiLanguage.ja), 'フォルダー');
    expect(translateUi('文件夹', UiLanguage.ko), '폴더');
  });

  for (final language in UiLanguage.values) {
    for (final width in [320.0, 507.0, 1800.0]) {
      final label = '${language.code} ${width.toInt()}px 200%';
      final brightness = width == 507 ? Brightness.dark : Brightness.light;

      for (final view in ContentView.values) {
        testWidgets('folder ${view.name} $label', (tester) async {
          _size(tester, width);
          _folderFixture(view: view);
          uiLanguage.value = language;
          await tester
              .pumpWidget(_app(const FoldersPage(), brightness: brightness));
          await _settle(tester, 'folder ${view.name} $label');
          expect(find.text(ui('文件夹')), findsOneWidget);
          expect(find.text('Collection {0}'), findsOneWidget);
          expect(find.byTooltip(_folderPath), findsOneWidget);
          expect(find.textContaining(' › '), findsOneWidget);
          final summary = ui('{0} 首歌曲 · 修改于 {1}', [1, ui('未知日期')]);
          expect(find.text(summary), findsOneWidget);
          final tile = find.byType(AudioFolderTile);
          final scheme = _scheme(tester, tile);
          expect(tester.widget<Text>(find.text('Collection {0}')).style!.color,
              scheme.onSurface);
          expect(tester.widget<Text>(find.text(summary)).style!.color,
              scheme.primary);
          expect(tester.widget<Icon>(find.byIcon(Symbols.folder_open)).color,
              scheme.onPrimaryContainer);
          expect(
              tester
                  .widget<InkWell>(
                      find.byKey(const ValueKey('folder-open-$_folderPath')))
                  .onTap,
              isNotNull);
          expect(tester.getSize(tile).width, greaterThan(0));
        });
      }

      for (final layout in LibraryRowLayout.values) {
        testWidgets('library ${layout.name} $label', (tester) async {
          _size(tester, width);
          uiLanguage.value = language;
          final audio = CategoryTestAudio(_mediaTitle,
              composer: _mediaComposer, album: _mediaAlbum);
          final audios = <Audio>[audio];
          await tester.pumpWidget(_app(_Library(audios),
              preferences: UiLayoutPreferences(libraryRowLayout: layout),
              brightness: brightness));
          await _settle(tester, 'library ${layout.name} $label');
          final columns = layout == LibraryRowLayout.columns && width == 1800;
          expect(find.byType(AudioColumnsHeader),
              columns ? findsOneWidget : findsNothing);
          expect(find.text(ui('音乐')), findsOneWidget);
          expect(find.text(_mediaTitle), findsOneWidget);
          final tile = tester.widget<AudioTile>(find.byType(AudioTile));
          expect(tile.playlist, same(audios));
          expect(tile.audioIndex, 0);
          expect(tile.columns, columns);
          final scheme = _scheme(tester, find.byType(AudioTile));
          expect(tester.widget<Text>(find.text(_mediaTitle)).style!.color,
              scheme.onSurface);
          if (columns) {
            expect(find.text(_mediaComposer), findsOneWidget);
            expect(find.text(_mediaAlbum), findsOneWidget);
            for (final key in ['歌名', '作曲家', '专辑', '时长']) {
              expect(
                  find.descendant(
                      of: find.byType(AudioColumnsHeader),
                      matching: find.text(ui(key))),
                  findsOneWidget);
            }
            expect(tester.widget<Text>(find.text(_mediaComposer)).style!.color,
                scheme.onSurfaceVariant);
          } else {
            expect(find.text('${audio.artist} - $_mediaAlbum'), findsOneWidget);
          }
          await _openAudioMenu(tester, columns, audio);
        });
      }

      for (final root in [false, true]) {
        testWidgets('compact playlist ${root ? 'root' : 'nested'} $label',
            (tester) async {
          _size(tester, width);
          uiLanguage.value = language;
          final fixture = _Playlists();
          final child =
              fixture.tree.createPlaylist(_mediaAlbum, parent: fixture.parent);
          final audio = CategoryTestAudio(_mediaTitle);
          fixture.tree.addAudio(child, audio);
          final target = root ? fixture.parent : child;
          await tester.pumpWidget(
              _app(fixture.browser(root: root), brightness: brightness));
          await _settle(tester, 'compact playlist $label');
          expect(find.text(target.name), findsWidgets);
          if (!root) {
            expect(
                tester.getSize(
                    find.byKey(const ValueKey('playlist-header-cover'))),
                const Size.square(64));
            expect(
                tester
                    .widget<Text>(
                        find.byKey(const ValueKey('playlist-header-title')))
                    .data,
                _mediaTitle);
          } else {
            expect(find.text(ui('歌单')), findsOneWidget);
          }
          final play = find.byKey(ValueKey('playlist-play-${target.id}'));
          _checkActionTheme(tester, play);
          expect(tester.widget<AppIconActionButton>(play).tooltip,
              ui('播放此歌单（含子歌单）'));
          await tester.tap(play);
          await _settle(tester, 'playlist play $label');
          expect(fixture.played.single.index, 0);
          expect(fixture.played.single.queue.single, same(audio));
          final menu = find.byKey(ValueKey('playlist-menu-${target.id}'));
          _checkActionTheme(tester, menu);
          await tester.tap(menu);
          await _settle(tester, 'playlist menu $label');
          expect(find.text(ui('重命名')), findsWidgets);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _settle(tester, 'close playlist menu');
          expect(fixture.saves, 0);
        });
      }
    }
  }

  for (final layout in LibraryRowLayout.values) {
    testWidgets(
        'live four-language switch preserves library ${layout.name} selection, scroll and order',
        (tester) async {
      _size(tester, 1800);
      final audios = <Audio>[
        for (var i = 0; i < 70; i++) CategoryTestAudio('$_mediaTitle $i')
      ];
      final original = List<Audio>.of(audios);
      final selection = MultiSelectController<Audio>()
        ..useMultiSelectView(true);
      addTearDown(selection.dispose);
      final saves = <List<Audio>>[];
      await tester.pumpWidget(_app(
          _Library(audios,
              selection: selection,
              reordered: (value) => saves.add(List.of(value))),
          preferences: UiLayoutPreferences(libraryRowLayout: layout)));
      await _settle(tester, 'library selection setup');
      await tester.tap(find.text(audios[1].title));
      await tester.pump();
      final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
      scroll.jumpTo(480);
      await tester.pump();
      final state = tester.state(find.byType(UniPage<Audio>));
      for (final language in UiLanguage.values) {
        await _switch(tester, language);
        expect(tester.state(find.byType(UniPage<Audio>)), same(state));
        expect(tester.widget<ListView>(find.byType(ListView)).controller,
            same(scroll));
        expect(scroll.offset, 480);
        expect(selection.selected, {original[1]});
        expect(selection.enableMultiSelectView, isTrue);
        expect(audios, original);
        expect(find.text(ui('音乐')), findsOneWidget);
      }
      selection.useMultiSelectView(false);
      await _settle(tester, 'return to reorder');
      expect(scroll.offset, 480,
          reason: 'Changing the list/reorder host retains the viewport');
      expect(
          tester
              .widget<ReorderableListView>(find.byType(ReorderableListView))
              .scrollController,
          same(scroll));
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(0, 2);
      await _settle(tester, 'reorder after localization');
      final reordered = [
        original[1],
        original[2],
        original[0],
        ...original.skip(3)
      ];
      expect(audios, reordered);
      expect(saves.single, reordered);
      for (final language in UiLanguage.values.reversed) {
        await _switch(tester, language);
        expect(audios, reordered);
        expect(scroll.offset, 480);
        expect(saves, hasLength(1));
      }
    });
  }

  testWidgets(
      'live language and theme switches keep folder scroll and source paths',
      (tester) async {
    _size(tester, 507);
    _folderFixture(count: 60);
    const page = FoldersPage();
    await tester.pumpWidget(_app(page));
    await _settle(tester, 'folder scroll setup');
    final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
    scroll.jumpTo(500);
    await tester.pump();
    final paths = [
      for (final folder in AudioLibrary.instance.folders) folder.path
    ];
    for (final language in UiLanguage.values) {
      await _switch(tester, language);
      expect(tester.widget<ListView>(find.byType(ListView)).controller,
          same(scroll));
      expect(scroll.offset, 500);
      expect(find.text(ui('文件夹')), findsOneWidget);
      expect([for (final folder in AudioLibrary.instance.folders) folder.path],
          paths);
    }
    final before =
        tester.widget<Icon>(find.byIcon(Symbols.folder_open).first).color;
    await tester.pumpWidget(
        _app(page, seed: Colors.deepOrange, brightness: Brightness.dark));
    await _settle(tester, 'folder live theme change');
    expect(scroll.offset, 500);
    expect(tester.widget<ListView>(find.byType(ListView)).controller,
        same(scroll));
    final icon = find.byIcon(Symbols.folder_open).first;
    expect(tester.widget<Icon>(icon).color,
        _scheme(tester, icon).onPrimaryContainer);
    expect(tester.widget<Icon>(icon).color, isNot(before));
  });

  testWidgets(
      'live four-language switch keeps playlist selection, scroll and reorder controller',
      (tester) async {
    _size(tester, 507);
    final fixture = _Playlists();
    final children = [
      for (var i = 0; i < 45; i++)
        fixture.tree.createPlaylist('Album {0} $i', parent: fixture.parent)
    ];
    await tester.pumpWidget(_app(fixture.browser()));
    await _settle(tester, 'playlist selection setup');
    final state = tester.state(find.byType(PlaylistBrowser));
    final surfaceController = tester
        .widget<PlaylistReorderSurface>(find.byType(PlaylistReorderSurface))
        .controller;
    await tapPlaylistAction(tester, 'playlist-start-selection');
    final selectionItem =
        find.byKey(ValueKey('playlist-select-${children.first.id}'));
    await tester.tap(selectionItem);
    await _settle(tester, 'playlist select item');
    final scroll = _playlistScroll(tester);
    scroll.jumpTo(420);
    await tester.pump();
    for (final language in UiLanguage.values) {
      await _switch(tester, language);
      expect(tester.state(find.byType(PlaylistBrowser)), same(state));
      expect(_playlistScroll(tester), same(scroll));
      expect(scroll.offset, 420);
      final toolbar =
          tester.widget<PlaylistToolbar>(find.byType(PlaylistToolbar));
      expect(toolbar.selecting, isTrue);
      expect(toolbar.selectedCount, 1);
      expect(
          tester
              .widget<PlaylistReorderSurface>(
                  find.byType(PlaylistReorderSurface))
              .controller,
          same(surfaceController));
      expect(fixture.parent.entries.map((e) => e.childPlaylist), children);
    }
    scroll.jumpTo(0);
    await tester.pump();
    expect(tester.widget<Semantics>(selectionItem).properties.selected, isTrue);
    await tapPlaylistAction(tester, 'playlist-end-selection');
    final surface = tester
        .widget<PlaylistReorderSurface>(find.byType(PlaylistReorderSurface));
    surface.onReorder(surface.items.first, 2);
    await _settle(tester, 'playlist reorder after switching');
    final expected = [
      children[1],
      children[2],
      children[0],
      ...children.skip(3)
    ];
    expect(fixture.parent.entries.map((e) => e.childPlaylist), expected);
    expect(fixture.saves, 1);
    for (final language in UiLanguage.values.reversed) {
      await _switch(tester, language);
      expect(fixture.parent.entries.map((e) => e.childPlaylist), expected);
      expect(fixture.saves, 1);
    }
  });

  testWidgets(
      'active mouse reorder survives a language switch without replacing its surface',
      (tester) async {
    _size(tester, 1800);
    final fixture = _Playlists();
    final children = [
      for (var i = 0; i < 3; i++)
        fixture.tree.createPlaylist('Album $i', parent: fixture.parent)
    ];
    await tester.pumpWidget(_app(fixture.browser()));
    await _settle(tester, 'active drag setup');
    final surface = tester
        .widget<PlaylistReorderSurface>(find.byType(PlaylistReorderSurface));
    final handle = find.byKey(ValueKey('playlist-drag-${children.first.id}'));
    final row = find.byKey(ValueKey(('playlist-entry', children.first.id)));
    final last = find.byKey(ValueKey(('playlist-entry', children.last.id)));
    final start = tester.getCenter(handle);
    final grab = start.dy - tester.getTopLeft(row).dy;
    final drag =
        await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await drag.moveBy(const Offset(0, 16));
    await tester.pump(const Duration(milliseconds: 80));
    expect(surface.controller.isDragging, isTrue);
    await _switch(tester, UiLanguage.ko);
    expect(
        tester
            .widget<PlaylistReorderSurface>(find.byType(PlaylistReorderSurface))
            .controller,
        same(surface.controller));
    expect(surface.controller.isDragging, isTrue);
    final end = Offset(start.dx, tester.getBottomRight(last).dy + grab + 4);
    for (var step = 1; step <= 4; step++) {
      await drag.moveTo(Offset.lerp(start, end, step / 4)!);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await drag.up();
    await _settle(tester, 'complete localized active drag');
    expect(fixture.parent.entries.map((e) => e.childPlaylist),
        [children[1], children[2], children[0]]);
    expect(fixture.saves, 1);
    expect(surface.controller.isDragging, isFalse);
  });
}
