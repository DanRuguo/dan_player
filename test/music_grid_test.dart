import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/music_grid.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/page/uni_detail_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

class _GridAudio extends CategoryTestAudio {
  _GridAudio(super.id, {super.online})
      : super(
            artist: 'HIDDEN ARTIST',
            album: 'HIDDEN ALBUM',
            composer: 'HIDDEN COMPOSER');

  final requests = <ArtworkSize>[];

  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) {
    requests.add(size);
    return super.artworkForSize(size);
  }
}

void _viewport(WidgetTester tester, {double width = 900, double dpr = 1}) {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = Size(width * dpr, 760 * dpr);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
      theme: ThemeData(
        platform: TargetPlatform.windows,
        visualDensity: VisualDensity.compact,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

Widget _page(
  String kind,
  List<Audio> songs, {
  PagePreference? preference,
  List<SortMethodDesc<Audio>>? methods,
  Audio? locateTo,
  ContentView view = ContentView.table,
}) {
  final pref = preference ?? PagePreference(0, SortOrder.ascending, view);
  Widget row(BuildContext context, Audio audio, int index,
          MultiSelectController<Audio>? selection) =>
      AudioTile(audioIndex: index, playlist: songs);
  Widget detailRow(BuildContext context, Audio audio, int index,
          List<Audio> visible, MultiSelectController<Audio>? selection) =>
      AudioTile(audioIndex: index, playlist: visible);
  if (kind == 'playlist') {
    final tree = PlaylistTree([]);
    final parent = tree.createPlaylist('Grid fixture');
    for (final song in songs) {
      tree.addAudio(parent, song);
    }
    tree.createPlaylist('Child fixture', parent: parent);
    return PlaylistBrowser(
      tree: tree,
      initialPlaylist: parent,
      initialContentView: view,
      persist: () async {},
    );
  }
  if (kind == 'detail') {
    return UniDetailPage<String, Audio, String>(
      pref: pref,
      primaryContent: 'fixture',
      primaryPic: Future.value(null),
      backgroundPic: Future.value(null),
      picShape: PicShape.oval,
      title: 'Grid fixture',
      subtitle: 'Synthetic metadata only',
      secondaryContent: songs,
      secondaryContentBuilder: detailRow,
      tertiaryContentTitle: '',
      tertiaryContent: const [],
      tertiaryContentBuilder: (_, item, __, ___) => Text(item),
      enableShufflePlay: false,
      enableSortMethod: methods != null,
      enableSortOrder: methods != null,
      enableSecondaryContentViewSwitch: false,
      sortMethods: methods,
    );
  }
  return UniPage<Audio>(
    pref: pref,
    title: 'Grid fixture',
    contentList: songs,
    contentBuilder: row,
    locateTo: locateTo,
    enableShufflePlay: false,
    enableSortMethod: methods != null,
    enableSortOrder: methods != null,
    enableContentViewSwitch: false,
    sortMethods: methods,
  );
}

Finder _gridTile(Audio audio) => find.byWidgetPredicate((widget) =>
    widget is AudioTile &&
    identical(widget.playlist[widget.audioIndex], audio));

void main() {
  tearDown(() => expect(PlayService.isInitialized, isFalse));

  test('shared delegate uses logical width with safe columns and row offsets',
      () {
    const grid = CompactMusicGridDelegate(mainAxisExtent: 64);
    expect(grid.columnCount(0), 1);
    expect(grid.columnCount(240), 1);
    expect(grid.columnCount(520), 2);
    expect(grid.columnCount(900), 3);
    expect(grid.offsetForIndex(8, 900), 144);
    expect(grid.offsetForIndex(-1, 900), 0);
  });

  for (final kind in ['library', 'detail', 'playlist']) {
    for (final scale in [1.0, 2.0]) {
      for (final dpr in [1.0, 2.0]) {
        testWidgets(
            '$kind grid is compact, title-only and DPR-aware at $scale/$dpr',
            (tester) async {
          _viewport(tester, dpr: dpr);
          final song = _GridAudio('A long title for a compact song card');
          await tester.pumpWidget(_host(_page(kind, [song]), scale: scale));
          await tester.pumpAndSettle();
          final tile = _gridTile(song);
          final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
          final delegate = grid.gridDelegate as CompactMusicGridDelegate;
          expect(tester.getSize(tile).height, delegate.mainAxisExtent);
          expect(delegate.mainAxisExtent, scale == 1 ? 64 : greaterThan(64));
          expect(delegate.mainAxisExtent,
              lessThanOrEqualTo(scale == 1 ? 64 : 100));
          expect(find.text('HIDDEN ARTIST - HIDDEN ALBUM'), findsNothing);
          expect(find.text('HIDDEN COMPOSER'), findsNothing);
          expect(find.text('0:02:00'), findsNothing);
          final artwork =
              find.descendant(of: tile, matching: find.byType(AudioArtwork));
          expect(tester.getSize(artwork), const Size.square(48));
          expect(tester.widget<AudioArtwork>(artwork).size, 48);
          expect(
              song.requests,
              contains(ArtworkSize.forDisplay(
                  logicalWidth: 48, logicalHeight: 48, devicePixelRatio: dpr)));
          final action =
              find.descendant(of: tile, matching: find.byType(IconButton));
          expect(action, findsOneWidget);
          expect(tester.getSize(action), const Size.square(44));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
      'grid menu and touch long press preserve local and online capabilities',
      (tester) async {
    _viewport(tester);
    final local = _GridAudio('Local fixture');
    final online = _GridAudio('Online fixture', online: true);
    await tester.pumpWidget(_host(_page('library', [local, online])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('audio-grid-menu-${local.path}')));
    await tester.pumpAndSettle();
    expect(find.text('编辑歌曲信息'), findsOneWidget);
    expect(find.text('编辑歌词'), findsOneWidget);
    expect(find.text('加入歌单…'), findsOneWidget);
    await tester.tap(find.text('Grid fixture'));
    await tester.pumpAndSettle();
    await tester.longPress(_gridTile(online));
    await tester.pumpAndSettle();
    expect(find.text('编辑歌曲信息'), findsNothing);
    expect(find.text('编辑歌词'), findsNothing);
    expect(find.text('联网歌曲详情'), findsOneWidget);
    expect(find.text('来源：QQ音乐'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact selection and keyboard menu do not start playback',
      (tester) async {
    _viewport(tester, width: 320);
    final song = _GridAudio('Selection fixture');
    var toggles = 0;
    await tester.pumpWidget(_host(
        MusicGridScope(
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              child: AudioTile(
                audioIndex: 0,
                playlist: [song],
                selection: AudioTileSelection(
                  enabled: true,
                  selected: false,
                  onToggle: () => toggles++,
                  onStart: () {},
                ),
              ),
            ),
          ),
        ),
        scale: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text(song.displayTitle));
    await tester.pumpAndSettle();
    expect(toggles, 1);
    await tester.pumpWidget(_host(_page('library', [song])));
    await tester.pumpAndSettle();
    final menu = find.byKey(ValueKey('audio-grid-menu-${song.path}'));
    final icon = find.descendant(of: menu, matching: find.byType(Icon));
    Focus.of(tester.element(icon)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('编辑歌曲信息'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dpr in [1.0, 2.0]) {
    testWidgets(
        'library grid locate and virtualization use logical pixels at $dpr',
        (tester) async {
      _viewport(tester, dpr: dpr);
      final songs = List.generate(200, (i) => _GridAudio('Fixture $i'));
      await tester
          .pumpWidget(_host(_page('library', songs, locateTo: songs[100])));
      await tester.pumpAndSettle();
      final gridFinder = find.byType(GridView);
      final grid = tester.widget<GridView>(gridFinder);
      final delegate = grid.gridDelegate as CompactMusicGridDelegate;
      expect(grid.controller!.offset,
          delegate.offsetForIndex(100, tester.getSize(gridFinder).width));
      expect(
          tester
              .getRect(_gridTile(songs[100]))
              .overlaps(tester.getRect(gridFinder)),
          isTrue);
      expect(songs.where((song) => song.requests.isNotEmpty).length,
          lessThan(100));
      expect(tester.takeException(), isNull);
    });
  }

  for (final kind in ['library', 'detail']) {
    testWidgets('$kind keeps valid sort indices after descriptor recreation',
        (tester) async {
      _viewport(tester);
      final song = _GridAudio('Sort fixture');
      final pref = PagePreference(99, SortOrder.ascending, ContentView.table);
      List<SortMethodDesc<Audio>> methods() => [
            SortMethodDesc(icon: Icons.sort, name: 'First', method: (_, __) {}),
            SortMethodDesc(
                icon: Icons.title, name: 'Second', method: (_, __) {}),
          ];
      final original = methods();
      await tester.pumpWidget(
          _host(_page(kind, [song], preference: pref, methods: original)));
      await tester.pumpAndSettle();
      SortMethodComboBox<Audio> control() =>
          tester.widget<SortMethodComboBox<Audio>>(
              find.byType(SortMethodComboBox<Audio>));
      expect(control().currSortMethod, same(original.first));
      final rebuilt = methods();
      await tester.pumpWidget(
          _host(_page(kind, [song], preference: pref, methods: rebuilt)));
      await tester.pumpAndSettle();
      expect(control().currSortMethod, same(rebuilt.first));
      control().setSortMethod(rebuilt.last);
      await tester.pumpAndSettle();
      expect(pref.sortMethod, 1);
      expect(find.byType(SortOrderSwitch<Audio>), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
