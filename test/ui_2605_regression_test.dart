import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/category_display_controls.dart';
import 'package:dan_player/component/detail_header_backdrop.dart';
import 'package:dan_player/component/detail_volume_panel.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_management_dialog.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';

Widget _app(Widget child, {double scale = 1, bool dark = false}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: applyAppControlTheme(ThemeData(
          platform: TargetPlatform.windows,
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: const ['Malgun Gothic'],
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: dark ? Brightness.dark : Brightness.light))),
      builder: (context, child) => UiLanguageScope(
          child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!)),
      home: Scaffold(body: child),
    );

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<List<int>> _render(
        WidgetTester tester, GlobalKey key, String name) async =>
    (await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      try {
        const output = String.fromEnvironment('DAN_UI_2605_RENDER');
        if (output.isNotEmpty) {
          await Directory(output).create(recursive: true);
          await File('$output/$name.png').writeAsBytes(
              (await image.toByteData(format: drawing.ImageByteFormat.png))!
                  .buffer
                  .asUint8List());
        }
        return (await image.toByteData())!.buffer.asUint8List().toList();
      } finally {
        image.dispose();
      }
    }))!;

void main() {
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
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  test('category display defaults and all combinations roundtrip', () {
    for (final invalid in [
      null,
      false,
      4,
      {'shape': 'unknown', 'showTitle': 1}
    ]) {
      final value = CategoryPresentation.fromMap(invalid);
      expect(value.shape, CategoryCoverShape.circle);
      expect(value.showTitle, isTrue);
      expect(value.showDetails, isFalse);
    }
    for (final shape in CategoryCoverShape.values) {
      for (final title in [false, true]) {
        for (final details in [false, true]) {
          final value = CategoryPresentation(
              shape: shape, showTitle: title, showDetails: details);
          expect(CategoryPresentation.fromMap(value.toMap()).toMap(),
              value.toMap());
        }
      }
    }
  });

  testWidgets(
      'category toggles change covers and captions without losing search',
      (tester) async {
    _size(tester, const Size(1100, 780));
    final prior = AppPreference.instance.categoryPresentation;
    AppPreference.instance.categoryPresentation = const CategoryPresentation();
    addTearDown(() => AppPreference.instance.categoryPresentation = prior);
    await tester.pumpWidget(_app(CategoriesPage(audios: [
      CategoryTestAudio('Song', artist: 'Unique Artist', album: 'Album'),
    ], onOpenGroup: (_) {})));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('category-search'));
    await tester.enterText(search, 'Unique');
    await tester.pumpAndSettle();
    expect(find.text('Unique Artist'), findsOneWidget);
    expect(find.text('1 首 · 本地 1'), findsNothing);
    final controls = tester
        .widget<CategoryDisplayControls>(find.byType(CategoryDisplayControls));
    controls.onChanged(const CategoryPresentation(
        shape: CategoryCoverShape.rounded,
        showTitle: false,
        showDetails: true));
    await tester.pumpAndSettle();
    expect(find.text('Unique Artist'), findsNothing);
    expect(find.text('1 首 · 本地 1'), findsOneWidget);
    expect(tester.widget<TextField>(search).controller!.text, 'Unique');
    expect(AppPreference.instance.categoryPresentation.shape,
        CategoryCoverShape.rounded);
    expect(tester.takeException(), isNull);
  });

  for (final view in PlaylistViewMode.values) {
    for (final isSong in [false, true]) {
      testWidgets('ellipsis uses visible action for ${view.name} song=$isSong',
          (tester) async {
        _size(tester, const Size(1100, 900));
        final tree = PlaylistTree([]);
        final parent = tree.createPlaylist('Parent');
        // Use the last column so an incorrect row/card start cannot pass.
        for (var i = 0; i < 3; i++) {
          tree.createPlaylist('Folder $i', parent: parent);
        }
        final folder = tree.createPlaylist('Target', parent: parent);
        final song = CategoryTestAudio('Target song');
        final id = isSong ? tree.addAudio(parent, song).id : folder.id;
        await tester.pumpWidget(_app(PlaylistBrowser(
            tree: tree,
            initialPlaylist: parent,
            initialView: view,
            persist: () async {},
            trackBuilder: (_, audio, play, action) => ListTile(
                title: Text(audio.displayTitle),
                onTap: play,
                trailing: action))));
        await tester.pumpAndSettle();
        final action = find.byKey(ValueKey('playlist-menu-$id'));
        await tester.ensureVisible(action);
        final actionRect = tester.getRect(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        final item =
            find.widgetWithText(MenuItemButton, isSong ? '从当前歌单移除' : '打开歌单');
        expect(item, findsOneWidget);
        final menuRect = tester.getRect(item);
        // Windows can flip to the left near the right edge, but the menu must
        // touch the action's x coordinate, never jump to the page's left edge.
        expect(menuRect.left, lessThanOrEqualTo(actionRect.right + 12));
        expect(menuRect.right, greaterThanOrEqualTo(actionRect.left - 12));
        if (view == PlaylistViewMode.list) {
          expect(menuRect.left, greaterThan(650));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final language in UiLanguage.values) {
    for (final short in [false, true]) {
      testWidgets('render actual category page ${language.code}/$short',
          (tester) async {
        _size(tester, short ? const Size(360, 507) : const Size(1100, 760));
        uiLanguage.value = language;
        final previous = AppPreference.instance.categoryPresentation;
        AppPreference.instance.categoryPresentation = CategoryPresentation(
            shape:
                short ? CategoryCoverShape.circle : CategoryCoverShape.rounded);
        addTearDown(
            () => AppPreference.instance.categoryPresentation = previous);
        final key = GlobalKey();
        await tester.pumpWidget(_app(
            RepaintBoundary(
                key: key,
                child: CategoriesPage(
                  initialCategory: MusicCategoryKind.album,
                  audios: [
                    for (var i = 0; i < 20; i++)
                      CategoryTestAudio('Song $i',
                          album: '${[
                            'Lapis · 魔法少女',
                            'Auld Lang Syne',
                            '夏の約束',
                            '오래된 노래'
                          ][i % 4]} $i',
                          artist: 'Artist $i')
                  ],
                )),
            scale: short ? 1.5 : 1,
            dark: !short));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(CustomScrollView)).height,
            greaterThan(96));
        await _render(tester, key, '${language.code}-$short-category-page');
      });
    }
    for (final narrow in [false, true]) {
      testWidgets('render panels ${language.code} narrow=$narrow',
          (tester) async {
        _size(tester, Size(narrow ? 360 : 1100, 1000));
        uiLanguage.value = language;
        final key = GlobalKey();
        var presentation = const CategoryPresentation();
        double volume = .65;
        await tester.pumpWidget(_app(
            RepaintBoundary(
                key: key,
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      StatefulBuilder(
                          builder: (_, change) => CategoryDisplayControls(
                              value: presentation,
                              onChanged: (next) =>
                                  change(() => presentation = next),
                              search: TextField(
                                  decoration: InputDecoration(
                                      hintText: ui('搜索{0}', [ui('艺术家')]),
                                      prefixIcon: const Icon(Icons.search),
                                      border: const OutlineInputBorder())))),
                      const SizedBox(height: 24),
                      Material(
                          borderRadius: BorderRadius.circular(16),
                          elevation: 3,
                          child: StatefulBuilder(
                              builder: (_, change) => DetailVolumePanel(
                                  value: volume,
                                  onChanged: (value) =>
                                      change(() => volume = value)))),
                    ]))),
            scale: narrow ? 1.5 : 1,
            dark: !narrow));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _render(tester, key, '${language.code}-$narrow-controls');
        final dialogKey = GlobalKey();
        final playlist =
            PlaylistTree([]).createPlaylist('GAL · My favourite songs');
        await tester.pumpWidget(_app(
            RepaintBoundary(
                key: dialogKey,
                child: PlaylistPresentationDialog(playlist: playlist)),
            scale: narrow ? 1.5 : 1,
            dark: !narrow));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(ui('歌单视图')), findsOneWidget);
        await _render(
            tester, dialogKey, '${language.code}-$narrow-playlist-view');
      });
    }
  }

  for (final language in [UiLanguage.zh, UiLanguage.en]) {
    testWidgets('render actual volume popup ${language.code}', (tester) async {
      final previousDisableShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        final narrow = language == UiLanguage.en;
        _size(tester, Size(narrow ? 360 : 800, narrow ? 507 : 450));
        uiLanguage.value = language;
        final key = GlobalKey();
        final volume = ValueNotifier(.65);
        addTearDown(volume.dispose);
        await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: _app(
                Padding(
                    padding: const EdgeInsets.all(24),
                    child: Align(
                        alignment: Alignment.bottomCenter,
                        child: DetailVolumeButton(
                            readVolume: () => volume.value,
                            changes: volume,
                            onChanged: (value) => volume.value = value))),
                scale: narrow ? 1.5 : 1,
                dark: !narrow)));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(ui('音量')));
        await tester.pumpAndSettle();
        expect(find.text('65%'), findsOneWidget);
        expect(find.text(ui('音量')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _render(tester, key, '${language.code}-volume-popup');
      } finally {
        debugDisableShadows = previousDisableShadows;
      }
    });
  }

  for (final dpr in [1.0, 2.0]) {
    for (final alignment in [Alignment.topLeft, Alignment.bottomRight]) {
      testWidgets(
          'volume popup clamps to viewport and stays live $dpr/$alignment',
          (tester) async {
        _size(tester, Size(360 * dpr, 507 * dpr));
        tester.view.devicePixelRatio = dpr;
        final volume = ValueNotifier(.65);
        addTearDown(volume.dispose);
        final control = DetailVolumeButton(
            readVolume: () => volume.value,
            changes: volume,
            onChanged: (value) => volume.value = value);
        await tester.pumpWidget(
            _app(Align(alignment: alignment, child: control), scale: 2));
        await tester.pumpAndSettle();
        expect(find.byType(Slider), findsNothing);
        await tester.tap(find.byTooltip('音量'));
        await tester.pumpAndSettle();
        final panel = tester.getRect(find.byType(DetailVolumePanel));
        expect(panel.left, greaterThanOrEqualTo(0));
        expect(panel.top, greaterThanOrEqualTo(0));
        expect(panel.right, lessThanOrEqualTo(360));
        expect(panel.bottom, lessThanOrEqualTo(507));
        expect(find.text('65%'), findsOneWidget);
        volume.value = .2;
        await tester.pumpAndSettle();
        expect(find.text('20%'), findsOneWidget);
        final slider = tester.getRect(find.byType(Slider));
        for (final endpoint in [slider.left - 30, slider.right + 30]) {
          final pointer = await tester.startGesture(slider.center);
          await pointer.moveTo(Offset(endpoint, slider.center.dy));
          await pointer.up();
          await tester.pumpAndSettle();
          expect(volume.value, endpoint < slider.left ? 0 : 1);
        }
        expect(find.text('100%'), findsOneWidget);
        await tester.tapAt(const Offset(180, 253));
        await tester.pumpAndSettle();
        expect(find.byType(Slider), findsNothing);
        volume.value = 0;
        await tester.pump();
        await tester.tap(find.byTooltip('音量'));
        await tester.pumpAndSettle();
        expect(find.text('0%'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('header artwork is stable when route opacity layer is removed',
      (tester) async {
    _size(tester, const Size(600, 280));
    final data = await tester.runAsync(() async {
      final recorder = drawing.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
          const Rect.fromLTWH(0, 0, 64, 64), Paint()..color = Colors.teal);
      canvas.drawRect(
          const Rect.fromLTWH(32, 0, 32, 64), Paint()..color = Colors.pink);
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 64);
      final bytes =
          (await image.toByteData(format: drawing.ImageByteFormat.png))!
              .buffer
              .asUint8List();
      image.dispose();
      picture.dispose();
      return bytes;
    });
    final artwork = Future<ImageProvider?>.value(MemoryImage(data!));
    final key = GlobalKey();
    Widget frame(double opacity) => _app(RepaintBoundary(
        key: key,
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: Colors.orange),
          Opacity(
              opacity: opacity,
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: DetailHeaderBackdrop(artwork: artwork))),
        ])));
    await tester.pumpWidget(frame(.999));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsOneWidget);
    final before = await _render(tester, key, 'header-0999');
    await tester.pumpWidget(frame(1));
    await tester.pump();
    final after = await _render(tester, key, 'header-1000');
    var largestDelta = 0;
    for (var i = 0; i < before.length; i++) {
      final delta = (before[i] - after[i]).abs();
      if (delta > largestDelta) largestDelta = delta;
    }
    expect(largestDelta, lessThanOrEqualTo(2));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
