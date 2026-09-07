import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/audios_page.dart';
import 'package:dan_player/page/category_detail_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

Widget _host(Widget page, GlobalKey capture,
    {required double scale,
    Brightness brightness = Brightness.light,
    Color seed = Colors.teal}) {
  final base = ThemeData(
      platform: TargetPlatform.windows,
      fontFamily: danEmbeddedFontFamily,
      fontFamilyFallback: danFontFamilyFallback,
      colorScheme:
          ColorScheme.fromSeed(seedColor: seed, brightness: brightness));
  return MaterialApp(
    locale: uiLanguage.value.locale,
    supportedLocales: [for (final value in UiLanguage.values) value.locale],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    themeAnimationDuration: Duration.zero,
    theme: applyAppControlTheme(base.copyWith(
        textTheme: base.textTheme.copyWith(
      // Fractional line metrics catch ceil differences between segment labels
      // and toolbar buttons, not only the standard 20px text line.
      labelLarge:
          base.textTheme.labelLarge!.copyWith(fontSize: 17, height: 1.13),
    ))),
    builder: (context, child) => UiLanguageScope(
        child: MediaQuery(
      data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale), disableAnimations: true),
      child: child!,
    )),
    home: RepaintBoundary(key: capture, child: Scaffold(body: page)),
  );
}

void _size(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 700);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

List<Audio> _songs({bool empty = false}) {
  final library = AudioLibrary.instance;
  final previous = library.audioCollection;
  final preference = AppPreference.instance.audiosPagePref;
  final songs = <Audio>[
    if (!empty)
      for (var i = 0; i < 3; i++)
        CategoryTestAudio('Memory song $i', artist: 'Artist', album: 'Album'),
  ];
  library.audioCollection = songs;
  AppPreference.instance.audiosPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.list);
  addTearDown(() {
    library.audioCollection = previous;
    AppPreference.instance.audiosPagePref = preference;
  });
  return songs;
}

Finder _buttons(Finder scope) => find.descendant(
    of: scope,
    matching: find.byWidgetPredicate(
        (widget) => widget is ButtonStyleButton || widget is IconButton));

List<Finder> _musicButtons() {
  final selection = find.byType(AppSegmentedControl<ContentView>);
  final choices = _buttons(selection);
  return [
    find.byKey(const ValueKey('music-search-action')),
    find.byKey(const ValueKey('playback-mode-shuffle')),
    find.byKey(const ValueKey('playback-mode-repeat')),
    _buttons(find.byType(AppSortButton<int>)).first,
    for (var i = 0; i < choices.evaluate().length; i++) choices.at(i),
  ];
}

Finder _material(Finder button) =>
    find.descendant(of: button, matching: find.byType(Material)).first;

void _checkGeometry(WidgetTester tester, List<Finder> controls,
    {bool oneRow = true}) {
  final reference = tester.getRect(_material(controls.first));
  final expected = appToolbarControlHeight(tester.element(controls.first));
  for (final control in controls) {
    final painted = tester.getRect(_material(control));
    expect(painted.height, closeTo(expected, .01));
    expect(painted.height, greaterThanOrEqualTo(44));
    if (oneRow) {
      expect(painted.top, closeTo(reference.top, .01));
      expect(painted.bottom, closeTo(reference.bottom, .01));
    }
    final group =
        find.descendant(of: control, matching: find.byType(AppToolbarLabel));
    if (group.evaluate().isNotEmpty) {
      final glyphs = find.descendant(
          of: group,
          matching: find
              .byWidgetPredicate((widget) => widget is Icon || widget is Text));
      Rect? contents;
      for (var i = 0; i < glyphs.evaluate().length; i++) {
        final rect = tester.getRect(glyphs.at(i));
        contents = contents == null ? rect : contents.expandToInclude(rect);
        expect(rect.center.dy, closeTo(painted.center.dy, .01));
      }
      expect(contents!.center.dx, closeTo(painted.center.dx, .01));
      final row = tester
          .widget<Row>(find.descendant(of: group, matching: find.byType(Row)));
      expect((row.children[1] as SizedBox).width, appToolbarLabelGap);
      final text = find.descendant(of: group, matching: find.byType(Text));
      expect(DefaultTextStyle.of(tester.element(text)).style.fontFamily,
          danEmbeddedFontFamily);
    } else {
      final icon =
          find.descendant(of: control, matching: find.byType(Icon)).first;
      expect(tester.getRect(icon).center, painted.center);
    }
  }
}

Future<void> _checkPixels(WidgetTester tester, GlobalKey key,
    List<({Finder button, Color fill})> probes) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final data = (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      return (
        bytes: Uint8List.fromList(
            (await image.toByteData())!.buffer.asUint8List()),
        width: image.width
      );
    } finally {
      image.dispose();
    }
  }))!;
  final origin = tester.getTopLeft(find.byKey(key));
  for (final probe in probes) {
    final rect = tester.getRect(_material(probe.button)).shift(-origin);
    final argb = probe.fill.toARGB32();
    for (final y in [(rect.top + 3).ceil(), (rect.bottom - 4).floor()]) {
      final x = rect.center.dx.floor();
      final offset = (y * data.width + x) * 4;
      for (var channel = 0; channel < 3; channel++) {
        expect(
            (data.bytes[offset + channel] -
                    ((argb >> (16 - channel * 8)) & 255))
                .abs(),
            lessThanOrEqualTo(1),
            reason: 'Actual button fill at ($x,$y)');
      }
    }
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
          ..addFont(rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
        .load();
  });
  tearDown(() {
    uiLanguage.value = UiLanguage.zh;
    expect(PlayService.isInitialized, isFalse);
  });

  for (final language in UiLanguage.values) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('real music toolbar $language $brightness $scale',
            (tester) async {
          _size(tester, 2400);
          _songs();
          uiLanguage.value = language;
          final capture = GlobalKey();
          await tester.pumpWidget(_host(const AudiosPage(), capture,
              scale: scale, brightness: brightness));
          await _settle(tester);
          final controls = _musicButtons();
          expect(controls, hasLength(6));
          _checkGeometry(tester, controls);
          final scheme = Theme.of(tester.element(controls.first)).colorScheme;
          await _checkPixels(tester, capture, [
            (button: controls[0], fill: scheme.secondaryContainer),
            (button: controls[1], fill: scheme.surface),
            (button: controls[2], fill: scheme.surface),
            (button: controls[3], fill: scheme.surface),
            (button: controls[4], fill: scheme.primaryContainer),
            (button: controls[5], fill: scheme.surface),
          ]);
          expect(tester.getSize(controls[0]).width,
              lessThan(tester.getSize(controls[3]).width));
          for (final button in [controls[0], controls[3]]) {
            expect(
                tester
                    .widget<ButtonStyleButton>(button)
                    .style!
                    .shape!
                    .resolve({}),
                AppShape.control);
          }
          expect(
              tester
                  .widget<SegmentedButton<ContentView>>(
                      find.byType(SegmentedButton<ContentView>))
                  .style!
                  .shape!
                  .resolve({}),
              AppShape.control);
        });
      }
    }
  }

  for (final language in UiLanguage.values) {
    for (final width in [320.0, 507.0]) {
      testWidgets('real music toolbar reachable $language $width at 200%',
          (tester) async {
        _size(tester, width);
        _songs();
        uiLanguage.value = language;
        await tester
            .pumpWidget(_host(const AudiosPage(), GlobalKey(), scale: 2));
        await _settle(tester);
        final controls = _musicButtons();
        _checkGeometry(tester, controls, oneRow: false);
        for (final control in controls) {
          await tester.ensureVisible(control);
          await _settle(tester);
          expect(control.hitTestable(), findsOneWidget);
          expect(tester.getSize(control).width, lessThanOrEqualTo(width - 64));
        }
      });
    }
  }

  testWidgets(
      'empty library disabled controls keep their actual height and theme',
      (tester) async {
    _size(tester, 2400);
    _songs(empty: true);
    final capture = GlobalKey();
    for (final seed in [Colors.teal, Colors.deepOrange]) {
      await tester
          .pumpWidget(_host(const AudiosPage(), capture, scale: 2, seed: seed));
      await _settle(tester);
      final controls = _musicButtons();
      _checkGeometry(tester, controls);
      expect(
          tester.widget<ButtonStyleButton>(controls[0]).onPressed, isNotNull);
      // Playback has not initialized in this layout-only fixture.
      expect(tester.widget<IconButton>(controls[1]).onPressed, isNull);
      expect(tester.widget<IconButton>(controls[2]).onPressed, isNull);
      expect(tester.widget<ButtonStyleButton>(controls[3]).onPressed, isNull);
      final scheme = Theme.of(tester.element(controls.first)).colorScheme;
      await _checkPixels(tester, capture, [
        (button: controls[1], fill: scheme.surface),
        (button: controls[2], fill: scheme.surface),
        (button: controls[3], fill: scheme.surface),
      ]);
    }
  });

  testWidgets(
      'playlist and category toolbar use the same measured label contract',
      (tester) async {
    _size(tester, 2400);
    final songs = _songs();
    final playlist = PlaylistToolbar(
        isRoot: false,
        hasItems: true,
        canPlay: true,
        view: PlaylistViewMode.circular,
        onViewChanged: (_) {},
        onCreate: () {},
        onStartSelection: () {},
        onEndSelection: () {},
        onSelectAll: () {},
        onRemoveSelected: () {},
        onSortChanged: (_) {});
    final group =
        MusicCategories(songs).groups(MusicCategoryKind.artist).single;
    for (final page in <Widget>[
      Align(alignment: Alignment.topLeft, child: playlist),
      CategoryDetailPage(
          kind: group.kind,
          groupId: group.id,
          initialGroup: group,
          audios: songs,
          onPlay: (_, __) {},
          onAddToPlaylist: (_) {}),
    ]) {
      await tester.pumpWidget(_host(page, GlobalKey(), scale: 2));
      await _settle(tester);
      final toolbar = find
          .byWidgetPredicate((widget) => widget is Wrap && widget.spacing == 8)
          .first;
      final buttons = _buttons(toolbar);
      final controls = [
        for (var i = 0; i < buttons.evaluate().length; i++) buttons.at(i)
      ];
      _checkGeometry(tester, controls);
    }
  });
}
