import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/category_tile_motion.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_tile_grid.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playback_mode_fixture.dart';

const _fillKey = ValueKey('playlist-auto-fill');

class _Fixture {
  final playback = PlaybackModeFixture();
  bool isRoot = true;
  bool hasItems = true;
  bool editingEnabled = true;
  bool autoFill = true;
  bool titles = true;
  PlaylistViewMode view = PlaylistViewMode.grid;
  final calls = <bool>[];
  late StateSetter refresh;

  Widget build(BuildContext context) => StatefulBuilder(
        builder: (context, setState) {
          refresh = setState;
          return Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: PlaylistToolbar(
                isRoot: isRoot,
                playbackService: playback,
                hasItems: hasItems,
                canPlay: hasItems,
                editingEnabled: editingEnabled,
                autoFill: autoFill,
                view: view,
                showSongTitles: titles,
                onAutoFillChanged: (value) => setState(() {
                  calls.add(value);
                  autoFill = value;
                }),
                onToggleSongTitles: () => setState(() => titles = !titles),
                onToggleSongBackground: () {},
                onViewChanged: (value) => setState(() => view = value),
                onCreate: () {},
                onAddSongs: () {},
                onStartSelection: () {},
                onEndSelection: () {},
                onSelectAll: () {},
                onRemoveSelected: () {},
                onSortChanged: (_) {},
                onTrash: () {},
                onImportM3u: () {},
                onImportCue: () {},
                onOpenSmartPlaylists: () {},
                onHelp: () {},
              ),
            ),
          );
        },
      );
}

Widget _app(Widget child,
        {Brightness brightness = Brightness.light,
        double scale = 1,
        bool reduced = true}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: applyAppControlTheme(ThemeData(
        fontFamily: danEmbeddedFontFamily,
        fontFamilyFallback: const ['Malgun Gothic'],
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: brightness),
      )),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            disableAnimations: reduced, textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('playlist-current-settings')));
  await tester.pumpAndSettle();
}

Future<void> _toggle(WidgetTester tester) async {
  await _open(tester);
  await tester.tap(find.byKey(_fillKey));
  await tester.pumpAndSettle();
}

Future<void> _dismiss(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

Future<void> _render(GlobalKey boundary, String name) async {
  const output = String.fromEnvironment('DAN_PLAYLIST_GAP_RENDER');
  if (output.isEmpty) return;
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await render.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: drawing.ImageByteFormat.png);
  image.dispose();
  await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets('gap mode lives beside titles in populated and empty levels',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.playback.dispose);
    for (final root in [true, false]) {
      for (final populated in [true, false]) {
        fixture
          ..isRoot = root
          ..hasItems = populated
          ..autoFill = true;
        await tester.pumpWidget(_app(Builder(builder: fixture.build)));
        await tester.pumpAndSettle();
        expect(find.byKey(_fillKey), findsNothing);
        await _open(tester);
        final automatic = find.text(ui('自动填充空隙'));
        final title = find.text(ui('关闭歌曲标题'));
        expect(tester.getTopLeft(automatic).dx,
            closeTo(tester.getTopLeft(title).dx, .01));
        expect(tester.getCenter(automatic).dy - tester.getCenter(title).dy,
            closeTo(48, .01));
        expect(find.byIcon(Icons.auto_awesome_mosaic_outlined), findsOneWidget);
        await tester.tap(find.byKey(_fillKey));
        await tester.pumpAndSettle();
        expect(fixture.autoFill, isFalse);
        await _open(tester);
        expect(find.text(ui('保留封面空隙')), findsOneWidget);
        expect(find.byIcon(Icons.space_dashboard_outlined), findsOneWidget);
        await tester.tap(find.byKey(_fillKey));
        await tester.pumpAndSettle();
        expect(fixture.autoFill, isTrue);
      }
    }
    expect(fixture.calls, [false, true, false, true, false, true, false, true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved holes survive view changes and stale menu cannot edit',
      (tester) async {
    final fixture = _Fixture()..autoFill = false;
    addTearDown(fixture.playback.dispose);
    await tester.pumpWidget(_app(Builder(builder: fixture.build)));
    await tester.pumpAndSettle();
    for (final mode in [PlaylistViewMode.list, PlaylistViewMode.circular]) {
      await _open(tester);
      expect(find.text(ui('保留封面空隙')), findsOneWidget);
      fixture.refresh(() => fixture.view = mode);
      await tester.pump();
      // The already-painted route must not dispatch an action that became
      // unavailable underneath it.
      await tester.tap(find.byKey(_fillKey));
      await tester.pumpAndSettle();
      expect(fixture.calls, isEmpty);
      await _open(tester);
      expect(find.byKey(_fillKey), findsNothing);
      await _dismiss(tester);
      fixture.refresh(() => fixture.view = PlaylistViewMode.grid);
      await tester.pumpAndSettle();
    }
    await _open(tester);
    fixture.refresh(() => fixture.editingEnabled = false);
    await tester.pump();
    await tester.tap(find.byKey(_fillKey));
    await tester.pumpAndSettle();
    expect(fixture.calls, isEmpty);
    expect(fixture.autoFill, isFalse);
    await _open(tester);
    expect(tester.widget<PopupMenuItem>(find.byKey(_fillKey)).enabled, isFalse);
    PopupMenuItem itemWithLabel(String label) =>
        tester.widget<PopupMenuItem>(find.ancestor(
            of: find.text(ui(label)),
            matching: find.byWidgetPredicate((w) => w is PopupMenuItem)));
    expect(itemWithLabel('关闭歌曲标题').enabled, isFalse);
    await _dismiss(tester);
    fixture.refresh(() {
      fixture.isRoot = false;
      fixture.view = PlaylistViewMode.circular;
    });
    await tester.pumpAndSettle();
    await _open(tester);
    expect(itemWithLabel('歌曲底色：主题配色').enabled, isFalse);
    await _dismiss(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow menu wraps and toggles its latest available state',
      (tester) async {
    tester.view.physicalSize = const Size(280, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    uiLanguage.value = UiLanguage.en;
    final fixture = _Fixture();
    addTearDown(fixture.playback.dispose);
    await tester.pumpWidget(_app(Builder(builder: fixture.build), scale: 1.25));
    await tester.pumpAndSettle();
    await _open(tester);
    await tester.ensureVisible(find.byKey(_fillKey));
    final rect = tester.getRect(find.byKey(_fillKey));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(280));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(500));
    fixture.refresh(() => fixture.autoFill = false);
    await tester.pump();
    await tester.tap(find.byKey(_fillKey));
    await tester.pumpAndSettle();
    expect(fixture.calls, [true]);
    expect(fixture.autoFill, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gap menu changes only its level and preserves custom ordering',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tree = PlaylistTree([]);
    final parent = tree.createPlaylist('Parent');
    tree.createPlaylist('Other');
    final z = tree.createPlaylist('Z', parent: parent);
    final a = tree.createPlaylist('A', parent: parent);
    parent.presentation = {
      'view': 'grid',
      'tiles': CategoryPresentation(autoFill: false, sizes: {
        z.id: CategoryTileSize.tall,
        a.id: CategoryTileSize.wide,
      }).toMap(),
    };
    final order = parent.entries.map((entry) => entry.id).toList();
    var saved = 0;
    await tester.pumpWidget(_app(PlaylistBrowser(
      tree: tree,
      initialView: PlaylistViewMode.grid,
      persist: () async => saved++,
      trackBuilder: (_, __, ___, ____) => const SizedBox.shrink(),
    )));
    await tester.pumpAndSettle();
    PlaylistToolbar toolbar() =>
        tester.widget<PlaylistToolbar>(find.byType(PlaylistToolbar));
    await _toggle(tester);
    expect(toolbar().autoFill, isFalse);
    await tester.tap(find.byKey(ValueKey('playlist-rectangle-${parent.id}')));
    await tester.pumpAndSettle();
    expect(toolbar().autoFill, isFalse); // Existing per-level choice wins.
    toolbar().onSortChanged(PlaylistSortMode.nameAscending);
    await tester.pumpAndSettle();
    await _toggle(tester);
    expect(toolbar().autoFill, isTrue);
    expect(toolbar().sortMode, PlaylistSortMode.nameAscending);
    expect(parent.entries.map((entry) => entry.id), order);
    expect(CategoryPresentation.fromMap(parent.presentation['tiles']).sizes,
        {z.id: CategoryTileSize.tall, a.id: CategoryTileSize.wide});
    toolbar().onSortChanged(PlaylistSortMode.custom);
    await tester.pumpAndSettle();
    expect(parent.entries.map((entry) => entry.id), order);
    await tester.tap(find.byKey(const ValueKey('playlist-breadcrumb-root')));
    await tester.pumpAndSettle();
    expect(toolbar().autoFill, isFalse);
    expect(saved, greaterThanOrEqualTo(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('gap menu retains linear tracking across rapid changes and idles',
      (tester) async {
    tester.view.physicalSize = const Size(740, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scroll = ScrollController();
    final playback = PlaybackModeFixture();
    addTearDown(scroll.dispose);
    addTearDown(playback.dispose);
    var presentation = const CategoryPresentation(autoFill: false, layouts: {
      'first': [6, 0, 0],
      'last': [6, 4, 3],
    });
    const lastKey = ValueKey('moving-cover');
    await tester.pumpWidget(_app(
        MotionPreferencesScope(
          preferences: const MotionPreferences(disabled: {MotionKind.feedback}),
          child: StatefulBuilder(builder: (context, setState) {
            return Center(
              child: SizedBox(
                width: 700,
                child: Column(children: [
                  PlaylistToolbar(
                    isRoot: true,
                    hasItems: true,
                    canPlay: false,
                    playbackService: playback,
                    view: PlaylistViewMode.grid,
                    onViewChanged: (_) {},
                    autoFill: presentation.autoFill,
                    onAutoFillChanged: (value) => setState(() =>
                        presentation = presentation.copyWith(autoFill: value)),
                    onCreate: () {},
                    onStartSelection: () {},
                    onEndSelection: () {},
                    onSelectAll: () {},
                    onRemoveSelected: () {},
                    onSortChanged: (_) {},
                  ),
                  Expanded(
                    child: PlaylistTileGrid(
                      ids: const ['first', 'last'],
                      presentation: presentation,
                      controller: scroll,
                      padding: EdgeInsets.zero,
                      onLayoutChanged: (value) =>
                          presentation = presentation.copyWith(layouts: value),
                      itemBuilder: (_, index) => ColoredBox(
                          key: index == 1 ? lastKey : null,
                          color: index == 0 ? Colors.red : Colors.blue),
                    ),
                  ),
                ]),
              ),
            );
          }),
        ),
        reduced: false));
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(find.byKey(lastKey));
    await _open(tester);
    await tester.tap(find.byKey(_fillKey));
    await tester.pump();
    await tester.pump();
    final start = tester.getTopLeft(find.byKey(lastKey));
    expect((start - origin).distance, closeTo(0, .01));
    await tester.pump(const Duration(milliseconds: 45));
    final quarter = tester.getTopLeft(find.byKey(lastKey));
    await tester.pump(const Duration(milliseconds: 45));
    final half = tester.getTopLeft(find.byKey(lastKey));
    expect((quarter - start).distance, greaterThan(1));
    expect((half - quarter).distance, closeTo((quarter - start).distance, .1));
    expect(
        tester
            .widgetList<CategoryTileMotion>(find.byType(CategoryTileMotion))
            .every((tile) => tile.linear),
        isTrue);
    // Reopen/click without settling: the existing 180 ms flight is running.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('playlist-current-settings')));
      await tester.pump();
      await tester.tap(find.byKey(_fillKey));
      await tester.pump();
      await tester.pump();
    }
    expect(presentation.autoFill, isTrue);
    await tester.pumpAndSettle();
    final finalRects = tester
        .widgetList<CategoryTileMotion>(find.byType(CategoryTileMotion))
        .map((tile) => tile.rect)
        .toList();
    expect(finalRects.length, 2);
    expect(finalRects.first.overlaps(finalRects.last), isFalse);
    expect(finalRects.first.top, finalRects.last.top);
    final settled = tester.getTopLeft(find.byKey(lastKey));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.getTopLeft(find.byKey(lastKey)), settled);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final brightness in Brightness.values) {
      testWidgets('gap menu ${language.name} ${brightness.name} render',
          (tester) async {
        uiLanguage.value = language;
        final narrow = brightness == Brightness.dark;
        tester.view.physicalSize = Size(narrow ? 360 : 1080, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = _Fixture()
          ..isRoot = !narrow
          ..autoFill = !narrow;
        addTearDown(fixture.playback.dispose);
        final boundary = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: _app(Builder(builder: fixture.build),
                brightness: brightness, scale: narrow ? 1.15 : 1)));
        await tester.pumpAndSettle();
        await _open(tester);
        final item = find.byKey(_fillKey);
        expect(item, findsOneWidget);
        final label = ui(narrow ? '保留封面空隙' : '自动填充空隙');
        expect(find.text(label), findsOneWidget);
        if (language != UiLanguage.zh) {
          expect(label, isNot(narrow ? '保留封面空隙' : '自动填充空隙'));
        }
        final rect = tester.getRect(item);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(tester.view.physicalSize.width));
        expect(tester.takeException(), isNull);
        await tester.runAsync(() => _render(boundary,
            '${language.name}-${brightness.name}-${narrow ? 'narrow' : 'wide'}'));
        await _dismiss(tester);
      });
    }
  }
}
