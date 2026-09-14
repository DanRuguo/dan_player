import 'package:flutter/gestures.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'dart:convert';
import 'package:dan_player/data/cache_backup_service.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_cover_picker.dart';
import 'package:dan_player/component/playlist_rectangle_tile.dart';
import 'package:dan_player/component/playlist_tile_grid.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/component/category_tile_motion.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/playlist_cover_snapshot.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

class _ArtAudio extends CategoryTestAudio {
  _ArtAudio(super.title, this.image);
  final ImageProvider? image;
  int requests = 0;
  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) async {
    requests++;
    return image;
  }
}

Future<Uint8List> _cover(int index) async {
  final recorder = drawing.PictureRecorder();
  final canvas = Canvas(recorder);
  final color = Colors.primaries[index % Colors.primaries.length];
  canvas.drawRect(
      const Rect.fromLTWH(0, 0, 200, 200),
      Paint()
        ..shader = LinearGradient(
                colors: [color.shade100, color.shade900],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)
            .createShader(const Rect.fromLTWH(0, 0, 200, 200)));
  canvas.drawCircle(Offset(60 + index * 4, 75), 55,
      Paint()..color = Colors.white.withValues(alpha: .6));
  canvas.drawRect(const Rect.fromLTWH(0, 150, 200, 50),
      Paint()..color = index.isEven ? Colors.white : Colors.black);
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 200);
  final bytes = (await image.toByteData(format: drawing.ImageByteFormat.png))!;
  image.dispose();
  picture.dispose();
  return bytes.buffer.asUint8List();
}

Widget _app(Widget child,
        {Brightness brightness = Brightness.light, double scale = 1}) =>
    MaterialApp(
        theme: applyAppControlTheme(ThemeData(
            fontFamily: danEmbeddedFontFamily,
            fontFamilyFallback: const ['Malgun Gothic'],
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal, brightness: brightness))),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(body: child));

Future<void> _rightClick(WidgetTester tester, Finder target) async {
  final mouse = await tester.startGesture(tester.getCenter(target),
      kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
  await mouse.up();
  await tester.pumpAndSettle();
}

Future<void> _decode(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 40));
  }
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _render(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await render.toImage(pixelRatio: 1);
  final data = await image.toByteData(format: drawing.ImageByteFormat.png);
  image.dispose();
  const output = String.fromEnvironment('DAN_PLAYLIST_RENDER');
  if (output.isNotEmpty) {
    await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Uint8List> covers;
  setUpAll(() async {
    final font = FontLoader(danEmbeddedFontFamily)
      ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf'));
    await font.load();
    for (final entry in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(entry.$1)..addFont(rootBundle.load(entry.$2))).load();
    }
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
    covers = [for (var i = 0; i < 8; i++) await _cover(i)];
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets('song cover snapshot is independent, deduplicated and readable',
      (tester) async {
    final directory = (await tester.runAsync(() => Directory(
            'build/playlist-cover-test-${DateTime.now().microsecondsSinceEpoch}')
        .create(recursive: true)))!;
    addTearDown(() => directory.delete(recursive: true));
    final source = _ArtAudio('Snapshot', MemoryImage(covers[0]));
    final saved = await tester.runAsync(() async {
      final first = await savePlaylistSongCover(source,
          dataDirectory: () async => directory);
      final second = await savePlaylistSongCover(source,
          dataDirectory: () async => directory);
      expect(first, second);
      expect(await File(first).readAsBytes(), covers[0]);
      return first;
    });
    await tester.pumpWidget(_app(Image.file(File(saved!))));
    await _decode(tester);
    expect(find.byType(Image), findsOneWidget);
    await tester.runAsync(() async {
      await expectLater(
          savePlaylistSongCover(_ArtAudio('Empty', null),
              dataDirectory: () async => directory),
          throwsFormatException);
      expect(await Directory('${directory.path}/playlist-covers').list().length,
          1);
    });
  });

  testWidgets(
      'playlist-only backup restores copied song cover and tile choices',
      (tester) async {
    final sandbox = (await tester.runAsync(() async {
      final parent = await Directory('build/test-data').create(recursive: true);
      return parent.createTemp('playlist-snapshot-backup-');
    }))!;
    addTearDown(() => sandbox.delete(recursive: true));
    await tester.runAsync(() async {
      final source =
          await Directory(path.join(sandbox.path, 'source')).create();
      final current =
          await Directory(path.join(sandbox.path, 'current')).create();
      final song = _ArtAudio('Backup art', MemoryImage(covers[2]));
      final snapshot =
          await savePlaylistSongCover(song, dataDirectory: () async => source);
      final tree = PlaylistTree([]);
      final playlist = tree.createPlaylist('Keep cover', imagePath: snapshot);
      playlist.presentation = {
        'tiles': const CategoryPresentation(
            autoFill: false, sizes: {'child': CategoryTileSize.tall}).toMap()
      };
      await File(path.join(source.path, 'playlists.json'))
          .writeAsString(jsonEncode([playlist.toMap()]));
      const service = CacheBackupService();
      final backup = File(path.join(sandbox.path, 'playlist.bak'));
      await service.exportBackup(
          source: source,
          destination: backup,
          selection:
              const BackupSelection(components: {BackupComponent.playlists}));
      final info = await service.inspectBackup(backup: backup);
      expect(info.components, {BackupComponent.playlists});
      expect(info.musicCount, 0);
      final destination = Directory(path.join(sandbox.path, 'target'));
      Directory? staged;
      await service.restoreBackup(
          backup: backup,
          destination: destination,
          currentData: current,
          selection:
              const BackupSelection(components: {BackupComponent.playlists}),
          activateLocation: (_, value) async => staged = value);
      final restored = decodePlaylists(jsonDecode(
              await File(path.join(staged!.path, 'playlists.json'))
                  .readAsString()))
          .single;
      expect(restored.presentation, playlist.presentation);
      expect(path.isWithin(destination.path, restored.imagePath!), isTrue);
      final actual = File(path.join(staged!.path,
          path.relative(restored.imagePath!, from: destination.path)));
      expect(await actual.readAsBytes(), await File(snapshot).readAsBytes());
    });
  });

  testWidgets('cover picker keeps selection, file fallback, failure and retry',
      (tester) async {
    final audio = _ArtAudio('Song', MemoryImage(covers[0]));
    var calls = 0;
    String? selected;
    Future<void> open() async {
      await tester.tap(find.text('Open'));
      await _decode(tester);
    }

    await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
            onPressed: () async => selected = await showDialog<String>(
                context: context,
                builder: (_) => PlaylistCoverPicker(
                    songs: [audio, audio],
                    pickImage: () => '/fixture.png',
                    saveFileCover: (selected) async => selected,
                    saveSongCover: (_) async {
                      if (++calls == 1) throw StateError('unreadable');
                      return '/snapshot.png';
                    })),
            child: const Text('Open')))));
    await open();
    expect(find.byType(ListTile), findsOneWidget);
    final apply = find.byKey(const ValueKey('playlist-cover-apply'));
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    await tester.tap(find.byKey(ValueKey(('playlist-cover-song', audio.path))));
    await tester.pump();
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(find.text(ui('无法读取封面，请重试或选择其他图片。')), findsOneWidget);
    expect(selected, isNull);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(selected, '/snapshot.png');
    await open();
    await tester.tap(find.byKey(const ValueKey('playlist-cover-file')));
    await tester.pumpAndSettle();
    expect(selected, '/fixture.png');
  });

  for (final language in UiLanguage.values) {
    for (final dark in [false, true]) {
      testWidgets(
          'feedback menus and song surfaces ${language.name} dark=$dark',
          (tester) async {
        uiLanguage.value = language;
        tester.view.physicalSize = const Size(1060, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final tree = PlaylistTree([]);
        final parent = tree.createPlaylist('Music · 音楽');
        tree.createPlaylist('Playlist · 歌单', parent: parent);
        for (var i = 0; i < 3; i++) {
          tree.addAudio(
              parent, _ArtAudio('Song ${i + 1}', MemoryImage(covers[i])));
        }
        final boundary = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: _app(
                PlaylistBrowser(
                    tree: tree,
                    initialPlaylist: parent,
                    initialView: PlaylistViewMode.circular,
                    persist: () async {}),
                brightness: dark ? Brightness.dark : Brightness.light)));
        await _decode(tester);
        PlaylistToolbar toolbar() =>
            tester.widget<PlaylistToolbar>(find.byType(PlaylistToolbar));
        for (final mode in ['theme', 'artwork']) {
          if (mode == 'artwork') {
            toolbar().onToggleSongBackground!();
            await _decode(tester);
          }
          await tester.tap(find.byTooltip(ui('更多')));
          await tester.pumpAndSettle();
          expect(find.text(ui(mode == 'artwork' ? '歌曲底色：封面配色' : '歌曲底色：主题配色')),
              findsOneWidget);
          await tester.runAsync(() =>
              _render(tester, boundary, 'circle-$mode-${language.name}-$dark'));
          await tester.tapAt(const Offset(10, 740));
          await tester.pumpAndSettle();
        }
        toolbar().onViewChanged!(PlaylistViewMode.grid);
        await _decode(tester);
        await tester.tap(find.byTooltip(ui('更多')));
        await tester.pumpAndSettle();
        expect(find.text(ui('歌单视图')), findsNothing);
        await tester.runAsync(() =>
            _render(tester, boundary, 'rectangle-menu-${language.name}-$dark'));
        await tester.tap(find.text(ui('关闭歌曲标题')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 70));
        final fading = find.ancestor(
            of: find.text('Song 1'), matching: find.byType(FadeTransition));
        expect(fading, findsWidgets);
        expect(tester.widget<FadeTransition>(fading.first).opacity.value,
            inExclusiveRange(0, 1));
        await tester.pumpAndSettle();
        expect(find.text('Song 1'), findsNothing);
        await tester.tap(find.byTooltip(ui('更多')));
        await tester.pumpAndSettle();
        expect(find.text(ui('显示歌曲标题')), findsOneWidget);
        await tester.tapAt(const Offset(10, 740));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('playlist-breadcrumb-root')));
        await _decode(tester);
        toolbar().onViewChanged!(PlaylistViewMode.circular);
        await _decode(tester);
        await tester.tap(find.byTooltip(ui('更多')));
        await tester.pumpAndSettle();
        expect(find.text(ui('歌曲底色：主题配色')), findsNothing);
        expect(find.text(ui('歌曲底色：封面配色')), findsNothing);
        expect(find.text(ui('歌单视图')), findsNothing);
        await tester.runAsync(() =>
            _render(tester, boundary, 'root-circle-menu-${language.name}-$dark'));
        expect(tester.takeException(), isNull);
      });
      testWidgets(
          'playlist tiles and cover picker render ${language.name} dark=$dark',
          (tester) async {
        uiLanguage.value = language;
        tester.view.physicalSize = Size(dark ? 420 : 1080, dark ? 800 : 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        final tree = PlaylistTree([]);
        final parent = tree.createPlaylist('Music · 音楽');
        final children = [
          for (var i = 0; i < 8; i++)
            tree.createPlaylist('Album ${i + 1}', parent: parent)
        ];
        for (var i = 0; i < children.length; i++) {
          tree.addAudio(
              children[i], _ArtAudio('Song ${i + 1}', MemoryImage(covers[i])));
        }
        parent.presentation['tiles'] = CategoryPresentation(sizes: {
          children[1].id: CategoryTileSize.wide,
          children[2].id: CategoryTileSize.tall,
          children[3].id: CategoryTileSize.large,
        }).toMap();
        await tester.pumpWidget(_app(
            RepaintBoundary(
                key: boundary,
                child: PlaylistBrowser(
                    initialPlaylist: parent,
                    tree: tree,
                    initialView: PlaylistViewMode.grid,
                    persist: () async {})),
            brightness: dark ? Brightness.dark : Brightness.light,
            scale: dark ? 1.5 : 1));
        await _decode(tester);
        expect(find.byType(PlaylistRectangleTile), findsWidgets);
        // Text sampling can finish after the first decoded frame. Export the
        // settled caption state, including warm-cache runs from earlier tests.
        final caption = find
            .ancestor(
                of: find.text('Album 1'),
                matching: find.byType(AnimatedDefaultTextStyle))
            .first;
        for (var i = 0;
            i < 50 &&
                tester.widget<AnimatedDefaultTextStyle>(caption).style.color !=
                    Colors.black;
            i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 40));
        }
        await tester.pumpAndSettle();
        expect(tester.widget<AnimatedDefaultTextStyle>(caption).style.color,
            Colors.black);
        final motions = tester
            .widgetList<CategoryTileMotion>(find.byType(CategoryTileMotion))
            .toList();
        for (var i = 0; i < motions.length; i++) {
          for (var j = i + 1; j < motions.length; j++) {
            expect(motions[i].rect.overlaps(motions[j].rect), isFalse);
          }
        }
        for (final title in tester.widgetList<Text>(find.byType(Text))) {
          expect(
              title.data?.contains('直接项目') == true &&
                  title.data!.contains('Album'),
              isFalse);
        }
        await tester.runAsync(() => _render(tester, boundary,
            'tiles-${language.name}-${dark ? 'dark-narrow' : 'light-wide'}'));
        final requests = children
            .map((p) => (p.firstAudioOrNull! as _ArtAudio).requests)
            .toList();
        await tester.pump(const Duration(seconds: 5));
        expect(children.map((p) => (p.firstAudioOrNull! as _ArtAudio).requests),
            requests);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.pumpWidget(_app(
            RepaintBoundary(
                key: boundary,
                child: PlaylistCoverPicker(songs: parent.flattenAudios())),
            brightness: dark ? Brightness.dark : Brightness.light,
            scale: dark ? 1.5 : 1));
        await _decode(tester);
        await tester.runAsync(() => _render(tester, boundary,
            'cover-picker-${language.name}-${dark ? 'dark-narrow' : 'light-wide'}'));
      });
    }
  }

  testWidgets('level views, sort and tile settings stay independent on return',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tree = PlaylistTree([]);
    final parent = tree.createPlaylist('Parent');
    final other = tree.createPlaylist('Other');
    final child = tree.createPlaylist('Child', parent: parent);
    tree.createPlaylist('Grandchild', parent: child);
    final rootViews = <PlaylistViewMode>[];
    await tester.pumpWidget(_app(PlaylistBrowser(
        tree: tree,
        initialView: PlaylistViewMode.grid,
        persist: () async {},
        onViewChanged: rootViews.add,
        trackBuilder: (_, __, ___, ____) => const SizedBox.shrink())));
    await _decode(tester);
    PlaylistToolbar toolbar() =>
        tester.widget<PlaylistToolbar>(find.byType(PlaylistToolbar));
    Future<void> view(PlaylistViewMode value) async {
      toolbar().onViewChanged!(value);
      await _decode(tester);
    }

    await view(PlaylistViewMode.circular);
    toolbar().onToggleSongBackground!();
    await tester.pumpAndSettle();
    expect(toolbar().artworkBackground, isTrue);
    await tester.tap(find.byKey(ValueKey('playlist-circle-open-${parent.id}')));
    await tester.pumpAndSettle();
    expect(toolbar().view, PlaylistViewMode.list);
    expect(toolbar().artworkBackground, isFalse);
    await view(PlaylistViewMode.grid);
    toolbar().onToggleSongTitles!();
    await tester.pumpAndSettle();
    expect(toolbar().showSongTitles, isFalse);
    toolbar().onSortChanged(PlaylistSortMode.nameDescending);
    toolbar().onAutoFillChanged!(false);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('playlist-rectangle-${child.id}')));
    await tester.pumpAndSettle();
    expect(toolbar().view, PlaylistViewMode.list);
    expect(toolbar().showSongTitles, isTrue);
    expect(toolbar().sortMode, PlaylistSortMode.custom);
    await view(PlaylistViewMode.circular);
    await tester.tap(find.byKey(ValueKey('playlist-breadcrumb-${parent.id}')));
    await tester.pumpAndSettle();
    expect(toolbar().view, PlaylistViewMode.grid);
    expect(toolbar().showSongTitles, isFalse);
    expect(toolbar().autoFill, isFalse);
    expect(toolbar().sortMode, PlaylistSortMode.nameDescending);
    await tester.tap(find.byKey(const ValueKey('playlist-breadcrumb-root')));
    await tester.pumpAndSettle();
    expect(toolbar().view, PlaylistViewMode.circular);
    expect(toolbar().artworkBackground, isTrue);
    await tester.tap(find.byKey(ValueKey('playlist-circle-open-${other.id}')));
    await tester.pumpAndSettle();
    expect(toolbar().view, PlaylistViewMode.list);
    expect(toolbar().autoFill, isTrue);
    expect(parent.presentation['view'], 'grid');
    expect(child.presentation['view'], 'circular');
    expect(other.presentation['view'], isNull);
    expect(rootViews, [PlaylistViewMode.circular]);
  });

  testWidgets(
      'all playlist views suppress cover details while song menu survives',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tree = PlaylistTree([]);
    final root = tree.createPlaylist('Hover parent');
    final child = tree.createPlaylist('Hover child', parent: root);
    final song =
        tree.addAudio(root, _ArtAudio('Menu song', MemoryImage(covers[0])));
    final pointer =
        await tester.createGesture(kind: drawing.PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    for (final view in PlaylistViewMode.values) {
      await tester.pumpWidget(_app(PlaylistBrowser(
          key: ValueKey(view),
          tree: tree,
          initialPlaylist: root,
          initialView: view,
          persist: () async {})));
      await _decode(tester);
      for (final id in [child.id, song.id]) {
        final item = find.byKey(ValueKey('playlist-select-$id'));
        expect(TooltipVisibility.of(tester.element(item)), isFalse);
        await pointer.moveTo(tester.getCenter(item));
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        for (final tooltip in tester.stateList<TooltipState>(
            find.descendant(of: item, matching: find.byType(Tooltip)))) {
          expect(tooltip.ensureTooltipVisible(), isFalse);
        }
      }
      if (view == PlaylistViewMode.grid) {
        await pointer.moveTo(Offset.zero);
        expect(find.byKey(ValueKey('playlist-menu-${song.id}')), findsNothing);
        await _rightClick(
            tester, find.byKey(ValueKey('playlist-rectangle-${song.id}')));
        await tester.pumpAndSettle();
        expect(find.text(ui('下一首播放')), findsOneWidget);
        expect(find.text(ui('详细信息')), findsOneWidget);
        expect(find.text(ui('从当前歌单移除')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('large tile collection only builds visible cards and idles',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var built = 0;
    final ids = [for (var i = 0; i < 5000; i++) 'entry-$i'];
    await tester.pumpWidget(_app(PlaylistTileGrid(
      ids: ids,
      controller: controller,
      padding: EdgeInsets.zero,
      presentation: CategoryPresentation(sizes: {
        for (var i = 0; i < ids.length; i++)
          ids[i]: CategoryTileSize.values[i % 4],
      }),
      onLayoutChanged: (_) {},
      itemBuilder: (_, index) {
        built++;
        return Text(ids[index]);
      },
    )));
    await tester.pumpAndSettle();
    expect(built, lessThan(150));
    controller.jumpTo(10000);
    await tester.pumpAndSettle();
    expect(built, lessThan(300));
    final afterScroll = built;
    await tester.pump(const Duration(seconds: 10));
    expect(built, afterScroll);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
      'mixed sizes preserve holes when disabled and compact when enabled',
      (tester) async {
    tester.view.physicalSize = const Size(700, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tree = PlaylistTree([]);
    final parent = tree.createPlaylist('Parent');
    final children = [
      for (var i = 0; i < 6; i++)
        tree.createPlaylist('Child $i', parent: parent)
    ];
    await tester.pumpWidget(_app(PlaylistBrowser(
        tree: tree,
        initialPlaylist: parent,
        initialView: PlaylistViewMode.grid,
        persist: () async {},
        trackBuilder: (_, __, ___, ____) => const SizedBox.shrink())));
    await _decode(tester);
    Future<void> resize(CategoryTileSize size) async {
      await _rightClick(tester,
          find.byKey(ValueKey('playlist-rectangle-${children.first.id}')));
      await tester.pumpAndSettle();
      final submenu = find.widgetWithText(SubmenuButton, ui('封面尺寸'));
      await tester.tap(submenu);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
          ValueKey(('playlist-tile-size', children.first.id, size.name))));
      await tester.pumpAndSettle();
    }

    await resize(CategoryTileSize.large);
    final large = tester.getSize(
        find.byKey(ValueKey('playlist-rectangle-${children.first.id}')));
    final small = tester.getSize(
        find.byKey(ValueKey('playlist-rectangle-${children.last.id}')));
    expect(large.width, closeTo(small.width * 2 + 4, .1));
    await tester.tap(find.byKey(const ValueKey('playlist-auto-fill')));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(
        find.byKey(ValueKey('playlist-rectangle-${children.last.id}')));
    await resize(CategoryTileSize.small);
    expect(
        tester.getTopLeft(
            find.byKey(ValueKey('playlist-rectangle-${children.last.id}'))),
        before);
    await tester.tap(find.byKey(const ValueKey('playlist-auto-fill')));
    await tester.pumpAndSettle();
    expect(CategoryPresentation.fromMap(parent.presentation['tiles']).autoFill,
        isTrue);
    final tiles = tester
        .widgetList<CategoryTileMotion>(find.byType(CategoryTileMotion))
        .toList();
    for (var i = 0; i < tiles.length; i++) {
      for (var j = i + 1; j < tiles.length; j++) {
        expect(tiles[i].rect.overlaps(tiles[j].rect), isFalse);
      }
    }
    expect(tester.takeException(), isNull);
  });
}
