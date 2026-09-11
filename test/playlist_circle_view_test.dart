import 'dart:ui' show PointerDeviceKind;
import 'dart:io' show FileSystemException;

import 'package:dan_player/component/app_action_icon.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/music_grid.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_circle_tile.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';
import 'support/playlist_actions.dart';

class _MissingArtworkAudio extends CategoryTestAudio {
  _MissingArtworkAudio()
      : super('Missing source reference',
            path:
                'D:/code/codex/player/dan_player/build/missing-circle-fixture.mp3');
  int requests = 0;
  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) {
    requests++;
    return Future.error(
        const FileSystemException('Missing in-memory artwork fixture'));
  }
}

class _Fixture {
  final roots = <Playlist>[];
  late final tree = PlaylistTree(roots);
  late final parent = tree.createPlaylist('Parent · 歌单 / 音楽 / 음악 {0}');
  final views = <PlaylistViewMode>[];
  final navigated = <Playlist?>[];
  final played = <({int index, List<Audio> queue})>[];
  int saves = 0;

  Widget browser(
          {bool root = false,
          PlaylistViewMode view = PlaylistViewMode.circular}) =>
      PlaylistBrowser(
        tree: tree,
        initialPlaylist: root ? null : parent,
        initialView: view,
        onViewChanged: views.add,
        onNavigate: navigated.add,
        persist: () async => saves++,
        onPlay: (index, queue) =>
            played.add((index: index, queue: List.of(queue))),
        trackBuilder: (_, audio, play, action) => ListTile(
          title: Text(audio.displayTitle,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: play,
          trailing: action,
        ),
      );
}

Widget _app(Widget page, {double scale = 2}) =>
    ValueListenableBuilder<UiLanguage>(
      valueListenable: uiLanguage,
      child: Scaffold(body: page),
      builder: (_, language, child) => MaterialApp(
        scrollBehavior: const DanPlayerScrollBehavior(),
        locale: language.locale,
        supportedLocales: [for (final value in UiLanguage.values) value.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          platform: TargetPlatform.windows,
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: language == UiLanguage.ko
                  ? Brightness.dark
                  : Brightness.light),
        ),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale), disableAnimations: true),
          child: UiLanguageScope(child: UiLanguageTransition(child: child!)),
        ),
        home: child,
      ),
    );

void _size(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Finder _key(String value) => find.byKey(ValueKey(value));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader(danEmbeddedFontFamily)
      ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf'));
    await font.load();
  });
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() {
    uiLanguage.value = UiLanguage.zh;
    expect(PlayService.isInitialized, isFalse);
  });

  test('view values remain stable and legacy grid names migrate', () {
    expect(PlaylistViewMode.values.map((view) => view.name),
        ['list', 'grid', 'circular']);
    expect(PlaylistViewMode.parse('table'), PlaylistViewMode.grid);
    expect(
        PlaylistViewMode.resolve(null, legacy: 'table'), PlaylistViewMode.grid);
    expect(PlaylistViewMode.resolve('circular', legacy: 'list'),
        PlaylistViewMode.circular);
    for (final invalid in [null, 3, 'future', false]) {
      expect(PlaylistViewMode.parse(invalid), isNull);
      expect(PlaylistViewMode.resolve(invalid, legacy: 'list'),
          PlaylistViewMode.list);
    }
    for (final language in UiLanguage.values.skip(1)) {
      expect(translateUi('圆形封面', language), isNot('圆形封面'));
      expect(translateUi('更新于 {0}', language, ['2026-08-30']),
          contains('2026-08-30'));
    }
  });

  for (final language in UiLanguage.values) {
    for (final width in [320.0, 507.0, 1800.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final root in [false, true]) {
          testWidgets(
              'circle ${language.code}/$width/$scale/${root ? 'root' : 'mixed'}',
              (tester) async {
            _size(tester, width);
            uiLanguage.value = language;
            final fixture = _Fixture();
            final child = fixture.tree.createPlaylist(
                'Collection / 专辑 / 앨범 {1}',
                parent: fixture.parent);
            final audio = CategoryTestAudio('原文 · 再生 · 음악 👩🏽‍🎤 {0}',
                artist: 'Composer {1}', album: 'Album · アルバム');
            fixture.tree.addAudio(child, audio);
            final direct = fixture.tree.addAudio(fixture.parent, audio);
            final displayed = root ? fixture.parent : child;
            await tester
                .pumpWidget(_app(fixture.browser(root: root), scale: scale));
            await _settle(tester);
            final cover = _key('playlist-circle-cover-${displayed.id}');
            expect(tester.widget(cover), isA<ClipOval>());
            expect(tester.getSize(cover), const Size.square(112));
            expect(find.text(displayed.name), findsWidgets);
            expect(find.byType(AppSegmentedControl<PlaylistViewMode>),
                findsOneWidget);
            final tile = _key('playlist-circle-${displayed.id}');
            final scheme = Theme.of(tester.element(tile)).colorScheme;
            final name =
                find.descendant(of: tile, matching: find.text(displayed.name));
            expect(tester.widget<Text>(name).style!.color, scheme.onSurface);
            final play = _key('playlist-play-${displayed.id}');
            expect(tester.widget<AppIconActionButton>(play).glyph,
                AppActionGlyph.play);
            await tester.tap(play);
            await _settle(tester);
            expect(
                fixture.played.single.queue, root ? [audio, audio] : [audio]);
            await tester.tap(_key('playlist-menu-${displayed.id}'));
            await _settle(tester);
            expect(find.text(ui('重命名')), findsWidgets);
            // Pointer-opened menus need not have keyboard focus. Dismiss using
            // the real outside-tap region before exercising the underlying row.
            await tester.tapAt(const Offset(4, 4));
            await _settle(tester);
            expect(find.text(ui('重命名')), findsNothing);
            await tester.tap(_key('playlist-circle-open-${displayed.id}'));
            expect(fixture.navigated.single, same(displayed));
            if (!root) {
              final songPlay = _key('playlist-play-${direct.id}');
              await tester.ensureVisible(songPlay);
              await _settle(tester);
              await tester.tap(songPlay);
              await _settle(tester);
              expect(fixture.played.last.index, 1);
              expect(fixture.played.last.queue, [audio, audio]);
            }
            expect(fixture.saves, 0);
          });
        }
      }
    }
  }

  for (final width in [320.0, 1800.0]) {
    testWidgets('three explicit choices retain each view scroll $width',
        (tester) async {
      _size(tester, width);
      final fixture = _Fixture();
      for (var i = 0; i < 80; i++) {
        fixture.tree.createPlaylist('Playlist $i', parent: fixture.parent);
      }
      await tester.pumpWidget(_app(fixture.browser()));
      await _settle(tester);
      final circleScroll =
          tester.widget<GridView>(find.byType(GridView)).controller!;
      circleScroll.jumpTo(520);
      await tester.pump();
      await selectPlaylistView(tester, 'grid');
      expect(find.byType(PlaylistCircleTile), findsNothing);
      expect(find.byType(MusicGridTileBody), findsWidgets);
      final squareScroll =
          tester.widget<GridView>(find.byType(GridView)).controller!;
      squareScroll.jumpTo(240);
      await tester.pump();
      await selectPlaylistView(tester, 'list');
      expect(find.byType(GridView), findsNothing);
      await selectPlaylistView(tester, 'circular');
      expect(tester.widget<GridView>(find.byType(GridView)).controller!.offset,
          520);
      await selectPlaylistView(tester, 'grid');
      expect(tester.widget<GridView>(find.byType(GridView)).controller!.offset,
          240);
      expect(fixture.views, [
        PlaylistViewMode.grid,
        PlaylistViewMode.list,
        PlaylistViewMode.circular,
        PlaylistViewMode.grid
      ]);
      expect(fixture.saves, 0);
      await _settle(tester);
    });
  }

  testWidgets(
      'circle selection and scroll survive all four languages and theme change',
      (tester) async {
    _size(tester, 507);
    final fixture = _Fixture();
    final children = [
      for (var i = 0; i < 40; i++)
        fixture.tree.createPlaylist('Keep {0} $i', parent: fixture.parent)
    ];
    await tester.pumpWidget(_app(fixture.browser()));
    await _settle(tester);
    await tapPlaylistAction(tester, 'playlist-start-selection');
    await tester.tap(_key('playlist-select-${children.first.id}'));
    await _settle(tester);
    final state = tester.state(find.byType(PlaylistBrowser));
    final scroll = tester.widget<GridView>(find.byType(GridView)).controller!;
    scroll.jumpTo(420);
    await tester.pump();
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      await _settle(tester);
      expect(tester.state(find.byType(PlaylistBrowser)), same(state));
      expect(tester.widget<GridView>(find.byType(GridView)).controller,
          same(scroll));
      expect(scroll.offset, 420);
      expect(
          tester
              .widget<PlaylistToolbar>(find.byType(PlaylistToolbar))
              .selectedCount,
          1);
      expect(
          fixture.parent.entries.map((entry) => entry.childPlaylist), children);
    }
    scroll.jumpTo(0);
    await tester.pump();
    expect(
        tester
            .widget<Semantics>(_key('playlist-select-${children.first.id}'))
            .properties
            .selected,
        isTrue);
    expect(fixture.views, isEmpty);
    expect(fixture.saves, 0);
  });

  testWidgets('moving short mouse click opens circle and square playlists',
      (tester) async {
    _size(tester, 1200);
    for (final view in [PlaylistViewMode.circular, PlaylistViewMode.grid]) {
      final fixture = _Fixture();
      final child =
          fixture.tree.createPlaylist('Click me', parent: fixture.parent);
      await tester.pumpWidget(_app(fixture.browser(view: view)));
      await _settle(tester);
      final source = _key('playlist-card-drag-${child.id}');
      final gesture = await tester.startGesture(tester.getCenter(source),
          kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(6, 2));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await _settle(tester);
      expect(fixture.navigated, contains(child));
      expect(fixture.saves, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'circle cover or title reorder still uses exact ids after language switch',
      (tester) async {
    _size(tester, 1800);
    final fixture = _Fixture();
    final children = [
      for (var i = 0; i < 3; i++)
        fixture.tree.createPlaylist('Playlist $i', parent: fixture.parent)
    ];
    await tester.pumpWidget(_app(fixture.browser()));
    await _settle(tester);
    final identity = _key('playlist-card-drag-${children.first.id}');
    final gesture = await tester.startGesture(tester.getCenter(identity),
        kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 260));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    uiLanguage.value = UiLanguage.ja;
    await _settle(tester);
    final destination = _key('playlist-drop-slot-${fixture.parent.id}-3');
    await gesture.moveTo(tester.getCenter(destination));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await _settle(tester);
    expect(fixture.parent.entries.map((entry) => entry.childPlaylist),
        [children[1], children[2], children[0]]);
    expect(fixture.saves, 1);
    expect(fixture.played, isEmpty);
  });

  testWidgets(
      'playlist circle keeps auto-scrolling while held at its lower edge',
      (tester) async {
    _size(tester, 1000);
    final fixture = _Fixture();
    final children = [
      for (var i = 0; i < 80; i++)
        fixture.tree.createPlaylist('Playlist $i', parent: fixture.parent),
    ];
    await tester.pumpWidget(_app(fixture.browser()));
    await _settle(tester);
    final gridFinder = find.byType(GridView);
    final grid = tester.widget<GridView>(gridFinder);
    final gesture = await tester.startGesture(
        tester.getCenter(_key('playlist-card-drag-${children.first.id}')),
        kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 260));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    final rect = tester.getRect(gridFinder);
    await gesture.moveTo(Offset(rect.center.dx, rect.bottom - 4));
    await tester.pump(const Duration(milliseconds: 16));
    final before = grid.controller!.offset;
    await tester.pump(const Duration(milliseconds: 500));
    expect(grid.controller!.offset, greaterThan(before + 40));
    await gesture.cancel();
    await _settle(tester);
    expect(
        fixture.parent.entries.map((entry) => entry.childPlaylist), children);
    expect(fixture.saves, 0);
  });

  testWidgets(
      'playlist circle touch swipe scrolls and long press alone can reorder',
      (tester) async {
    _size(tester, 1000);
    final fixture = _Fixture();
    final children = [
      for (var i = 0; i < 30; i++)
        fixture.tree.createPlaylist('Playlist $i', parent: fixture.parent),
    ];
    await tester.pumpWidget(_app(fixture.browser()));
    await _settle(tester);
    final grid = tester.widget<GridView>(find.byType(GridView));
    final source = _key('playlist-card-drag-${children.first.id}');
    final swipe = await tester.startGesture(tester.getCenter(source),
        kind: PointerDeviceKind.touch);
    for (var i = 0; i < 8; i++) {
      await swipe.moveBy(const Offset(0, -28));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await swipe.up();
    await tester.pumpAndSettle();
    expect(grid.controller!.offset, greaterThan(0));
    expect(
        fixture.parent.entries.map((entry) => entry.childPlaylist), children);
    expect(fixture.saves, 0);

    grid.controller!.jumpTo(0);
    await tester.pump();
    final reorder = await tester.startGesture(tester.getCenter(source),
        kind: PointerDeviceKind.touch);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await reorder.moveBy(const Offset(20, 0));
    await tester.pump();
    final destination = _key('playlist-drop-slot-${fixture.parent.id}-3');
    await reorder.moveTo(tester.getCenter(destination));
    await tester.pump();
    await reorder.up();
    await _settle(tester);
    expect(fixture.parent.entries.take(3).map((entry) => entry.childPlaylist),
        [children[1], children[2], children[0]]);
    expect(fixture.saves, 1);
  });

  testWidgets(
      'circle cover remains a folder drop target without duplicate entries',
      (tester) async {
    _size(tester, 1800);
    final fixture = _Fixture();
    final source =
        fixture.tree.createPlaylist('Source', parent: fixture.parent);
    final target =
        fixture.tree.createPlaylist('Target', parent: fixture.parent);
    final gesturePage = fixture.browser();
    await tester.pumpWidget(_app(gesturePage));
    await _settle(tester);
    final gesture = await tester.startGesture(
        tester.getCenter(_key('playlist-drag-${source.id}')),
        kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 260));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture
        .moveTo(tester.getCenter(_key('playlist-drop-folder-${target.id}')));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await _settle(tester);
    expect(source.parent, same(target));
    expect(fixture.parent.entries.single.childPlaylist, same(target));
    expect(target.entries.single.childPlaylist, same(source));
    expect(fixture.saves, 1);
  });

  testWidgets(
      'legacy browser list/table arguments retain the old presentations',
      (tester) async {
    _size(tester, 1000);
    final fixture = _Fixture();
    fixture.tree.createPlaylist('Old root');
    for (final legacy in ContentView.values) {
      await tester.pumpWidget(_app(PlaylistBrowser(
        tree: fixture.tree,
        initialContentView: legacy,
        persist: () async {},
        trackBuilder: (_, audio, play, action) => Text(audio.title),
      )));
      await _settle(tester);
      expect(find.byType(PlaylistCircleTile), findsNothing);
      expect(find.byType(GridView),
          legacy == ContentView.table ? findsOneWidget : findsNothing);
    }
  });

  testWidgets('empty circle and list playlists share disabled playback',
      (tester) async {
    _size(tester, 1000);
    final fixture = _Fixture();
    final empty = fixture.tree.createPlaylist('Empty', parent: fixture.parent);
    for (final view in [PlaylistViewMode.circular, PlaylistViewMode.list]) {
      await tester.pumpWidget(_app(fixture.browser(view: view)));
      await _settle(tester);
      expect(
          tester
              .widget<AppIconActionButton>(_key('playlist-play-${empty.id}'))
              .onPressed,
          isNull);
      expect(
          tester.widget<PlaylistToolbar>(find.byType(PlaylistToolbar)).canPlay,
          isFalse);
      expect(fixture.played, isEmpty);
      expect(fixture.saves, 0);
    }
  });

  testWidgets(
      'missing custom cover preserves its path and keeps circle actions',
      (tester) async {
    _size(tester, 1000);
    final fixture = _Fixture();
    final audio = _MissingArtworkAudio();
    final entry = fixture.tree.addAudio(fixture.parent, audio);
    final nested =
        fixture.tree.createPlaylist('Missing cover', parent: fixture.parent);
    fixture.tree.addAudio(nested, audio);
    const imagePath =
        'D:/code/codex/player/dan_player/build/missing-circle-cover-fixture.png';
    fixture.tree.setImagePath(nested, imagePath);
    final ids = fixture.parent.entries.map((entry) => entry.id).toList();
    await tester.pumpWidget(_app(PlaylistBrowser(
      tree: fixture.tree,
      initialPlaylist: fixture.parent,
      initialView: PlaylistViewMode.circular,
      persist: () async => fixture.saves++,
      onPlay: (index, queue) =>
          fixture.played.add((index: index, queue: List.of(queue))),
    )));
    await _settle(tester);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(audio.requests, greaterThan(0));
    expect(find.text(audio.displayTitle), findsOneWidget);
    expect(find.byIcon(Icons.music_note), findsWidgets);
    expect(fixture.parent.entries.map((entry) => entry.id), ids);
    expect(nested.imagePath, imagePath);
    expect(
        tester
            .widget<AppIconActionButton>(_key('playlist-play-${entry.id}'))
            .onPressed,
        isNotNull);
    await tester.tap(_key('playlist-menu-${entry.id}'));
    await _settle(tester);
    expect(find.text(ui('从当前歌单移除')), findsWidgets);
    expect(fixture.saves, 0);
    expect(fixture.played, isEmpty);
  });
}
