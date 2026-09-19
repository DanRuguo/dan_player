import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/readable_ellipsis_text.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/artist_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'support/music_category_fixtures.dart';

void main() {
  for (final online in [false, true]) {
    testWidgets('artist selection opens normalized detail online=$online',
        (tester) async {
      final audio = CategoryTestAudio('artist-navigation-$online',
          artist: 'Artist A / Artist B', online: online);
      final library = AudioLibrary.instance;
      final folders = library.folders;
      final onlineAudios = library.onlineAudioCollection;
      addTearDown(() {
        library.folders = folders;
        library.onlineAudioCollection = onlineAudios;
        library.rebuildDerivedCollections();
      });
      // An online search result has not been added to the library yet.
      library.folders = online
          ? []
          : [
              AudioFolder([audio], 'J:/artist-test-fixtures', 0, 0)
            ];
      library.onlineAudioCollection = [];
      library.rebuildDerivedCollections();
      MusicCategoryGroup? opened;
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            builder: (_, __) =>
                Scaffold(body: AudioTile(audioIndex: 0, playlist: [audio]))),
        GoRoute(
            path: app_paths.CATEGORY_DETAIL_PAGE,
            builder: (_, state) {
              opened = state.extra! as MusicCategoryGroup;
              return Scaffold(
                  body: ArtistDetailPage.group(
                      groupId: opened!.id, initialGroup: opened));
            }),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(AudioTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SubmenuButton));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Artist B'));
      await tester.pumpAndSettle();
      expect(find.byType(ArtistDetailPage), findsOneWidget);
      expect(
          find.byWidgetPredicate((widget) =>
              widget is AudioTile &&
              identical(widget.playlist[widget.audioIndex], audio)),
          findsOneWidget);
      expect(opened!.audios.single, same(audio));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('playlist-only copies use current separators when opening menus',
      (tester) async {
    final settings = AppSettings.instance;
    final original = settings.artistSplitPattern;
    settings.artistSplitPattern = r'/';
    addTearDown(() => settings.artistSplitPattern = original);
    final audio = CategoryTestAudio('Playlist-only copy', artist: 'A|B');
    expect(audio.splitedArtists, ['A|B']);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AudioTile(audioIndex: 0, playlist: [audio]))));
    await tester.pumpAndSettle();
    settings.artistSplitPattern = r'\|';
    await tester.longPress(find.byType(AudioTile));
    await tester.pumpAndSettle();
    expect(find.byType(SubmenuButton), findsOneWidget);
    await tester.tap(find.byType(SubmenuButton));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, 'A'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'B'), findsOneWidget);
    expect(audio.splitedArtists, ['A|B'],
        reason: 'reading the menu must not mutate detached audio objects');
    expect(tester.takeException(), isNull);
  });

  test('readable ellipsis keeps multilingual and symbol token boundaries', () {
    String truncate(String value, int maxGraphemes) =>
        truncateReadableSingleLine(
          value,
          (candidate) => candidate.characters.length <= maxGraphemes,
        );

    expect(truncate('中文日本語한국어', 4), '中文日…');
    expect(truncate('中文 Mix2026 UnbreakableWord', 12), '中文 Mix2026…');
    expect(truncate('日☆🎼韓 SuperLongWord', 5), '日☆🎼韓…');
    expect(truncate("Mix Rock'n-Roll Extended", 10), "Mix Rock'…");
    expect(truncate('AA-BB_CC\'DD', 4), 'AA-…');
    expect(truncate('AA-BB_CC\'DD', 7), 'AA-BB_…');
    expect(truncate('AA-BB_CC\'DD', 10), "AA-BB_CC'…");
    expect(truncate('中文    UnbreakableWord', 4), '中文…');
  });

  testWidgets('multiple artists share a submenu while album stays direct',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    final audio = CategoryTestAudio(
      'menu metadata',
      artist: 'Artist A / Artist B',
      album: 'Album C',
    )..splitedArtists = ['Artist A', 'Artist B'];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: AudioTile(audioIndex: 0, playlist: [audio]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final anchor = tester.widget<MenuAnchor>(
      find.descendant(
        of: find.byType(AudioTile),
        matching: find.byType(MenuAnchor),
      ),
    );
    expect(anchor.crossAxisUnconstrained, isFalse);
    await tester.longPress(find.byType(AudioTile));
    await tester.pumpAndSettle();

    final artistSubmenu = find.widgetWithText(SubmenuButton, '艺术家');
    expect(artistSubmenu, findsOneWidget);
    expect(find.text('Artist A'), findsNothing);
    expect(
        (tester.widget<SubmenuButton>(artistSubmenu).leadingIcon! as Icon).icon,
        Symbols.artist);
    final albumItem = tester.widget<MenuItemButton>(
      find.widgetWithText(MenuItemButton, audio.album),
    );
    expect((albumItem.leadingIcon! as Icon).icon, Symbols.album);
    await tester.tap(artistSubmenu);
    await tester.pumpAndSettle();
    for (final artistName in audio.splitedArtists) {
      final item = tester.widget<MenuItemButton>(
        find.widgetWithText(MenuItemButton, artistName),
      );
      expect((item.leadingIcon! as Icon).icon, Symbols.artist);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'long metadata stays single-line ellipsized inside a narrow rounded menu',
      (tester) async {
    tester.view.physicalSize = const Size(320, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final artist = List.filled(12, 'Long Artist').join(' · ');
    final album = List.filled(
      8,
      '中文 日本語 한국어 AlbumWord2026 ☆ 🎼 Special-Edition',
    ).join(' · ');
    final audio = CategoryTestAudio(
      'narrow menu metadata',
      artist: artist,
      album: album,
    )..splitedArtists = [artist];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: AudioTile(
              audioIndex: 0,
              playlist: [audio],
              additionalMenuItems: [
                for (var index = 0; index < 10; index++)
                  MenuItemButton(
                    onPressed: () {},
                    leadingIcon: const Icon(Icons.playlist_play),
                    child: Text('附加歌单操作 $index'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(AudioTile));
    await tester.pumpAndSettle();

    final albumLabel = find.text(album);
    final artistLabel = find.text(artist);
    expect(albumLabel, findsOneWidget);
    expect(artistLabel, findsOneWidget);
    for (final label in [albumLabel, artistLabel]) {
      final text = tester.widget<Text>(label);
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
      expect(text.overflow, TextOverflow.ellipsis);
    }

    final displayedAlbum = ReadableEllipsisText.debugDisplayedText(
      tester.renderObject(albumLabel),
    );
    expect(displayedAlbum, endsWith('…'));
    final visiblePrefix =
        displayedAlbum.substring(0, displayedAlbum.length - 1);
    expect(RegExp(r'\s$').hasMatch(visiblePrefix), isFalse);
    expect(album.startsWith(visiblePrefix), isTrue);
    if (visiblePrefix.isNotEmpty && visiblePrefix.length < album.length) {
      expect(
        RegExp(r'[A-Za-z0-9]').hasMatch(visiblePrefix.characters.last) &&
            RegExp(r'[A-Za-z0-9]').hasMatch(
              album.substring(visiblePrefix.length).characters.first,
            ),
        isFalse,
        reason: 'an English/number token must not be cut in half',
      );
    }

    final albumContext = tester.element(albumLabel);
    final naturalWidth = TextPainter(
      text: TextSpan(
        text: album,
        style: DefaultTextStyle.of(albumContext).style,
      ),
      textDirection: Directionality.of(albumContext),
      textScaler: MediaQuery.textScalerOf(albumContext),
      maxLines: 1,
    )..layout();
    expect(tester.getSize(albumLabel).width, lessThan(naturalWidth.width));
    naturalWidth.dispose();

    // The constrained panel must size and clip at its rounded Material without
    // crossing MenuAnchor's 8px reserved viewport edge.
    final menuMaterials = find
        .ancestor(of: albumLabel, matching: find.byType(Material))
        .evaluate()
        .where((element) {
      final material = element.widget as Material;
      return material.shape is RoundedRectangleBorder &&
          material.clipBehavior != Clip.none;
    }).toList();
    expect(menuMaterials, hasLength(1));
    final menuSurface = find.byElementPredicate(
      (element) => identical(element, menuMaterials.single),
    );
    final menuSize = tester.getSize(menuSurface);
    expect(menuSize.width, lessThanOrEqualTo(420));
    final menuRect = tester.getRect(menuSurface);
    expect(menuRect.left, greaterThanOrEqualTo(8));
    expect(menuRect.right, lessThanOrEqualTo(312));
    final material = menuMaterials.single.widget as Material;
    final shape = material.shape! as RoundedRectangleBorder;
    final borderRadius = shape.borderRadius.resolve(TextDirection.ltr);
    expect(borderRadius.topRight.x, greaterThan(0));
    expect(borderRadius.bottomRight.x, greaterThan(0));
    expect(borderRadius.bottomLeft.x, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
