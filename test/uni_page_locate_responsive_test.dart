import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/audio_columns.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/audios_page.dart';
import 'package:dan_player/page/page_scaffold.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/ui_layout_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

Widget _app(Widget page, {bool columns = false}) =>
    ValueListenableBuilder<UiLanguage>(
      valueListenable: uiLanguage,
      child: Scaffold(body: page),
      builder: (_, language, child) => MaterialApp(
        locale: language.locale,
        supportedLocales: [for (final value in UiLanguage.values) value.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: applyAppControlTheme(ThemeData(
          platform: TargetPlatform.windows,
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        )),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: UiLanguageScope(
            child: UiLayoutScope(
              preferences: UiLayoutPreferences(
                  libraryRowLayout: columns
                      ? LibraryRowLayout.columns
                      : LibraryRowLayout.classic),
              child: child!,
            ),
          ),
        ),
        home: child,
      ),
    );

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

List<Audio> _libraryFixture() {
  final library = AudioLibrary.instance;
  final previousAudios = library.audioCollection;
  final preferences = AppPreference.instance;
  final previousPref = preferences.audiosPagePref;
  final songs = <Audio>[
    for (var i = 0; i < 200; i++)
      CategoryTestAudio('Song ${i.toString().padLeft(3, '0')} 音楽 음악',
          artist: 'Artist', album: 'Album')
        ..duration = i.isEven ? 120 : 123456,
  ];
  library.audioCollection = songs;
  preferences.audiosPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.list);
  addTearDown(() {
    library.audioCollection = previousAudios;
    preferences.audiosPagePref = previousPref;
  });
  return songs;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Finder _header() => find.byKey(const ValueKey('page-custom-header-scroll'));
Finder _body() => find.byType(AppContentScrollbar);
Finder _entrance() => find
    .descendant(
        of: find.byType(PageScaffold), matching: find.byType(AppEntrance))
    .first;
double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(
        find.descendant(of: _entrance(), matching: find.byType(Opacity)).first)
    .opacity;

ScrollController _listController(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!;

Future<void> _selectGrid(WidgetTester tester) async {
  var grid = find.text(ui('网格'));
  if (grid.evaluate().isEmpty) {
    final trigger = find.descendant(
        of: find.byType(AppSegmentedControl<ContentView>),
        matching: find.byWidgetPredicate(
            (widget) => widget is IconButton || widget is OutlinedButton));
    await tester.ensureVisible(trigger.first);
    await _settle(tester);
    await tester.tap(trigger.first);
    await _settle(tester);
    grid = find.text(ui('网格'));
  }
  await tester.ensureVisible(grid.last);
  await _settle(tester);
  await tester.tap(grid.hitTestable().last);
  await _settle(tester);
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
    expect(PlayService.isInitialized, isFalse);
  });

  for (final language in UiLanguage.values) {
    for (final width in [320.0, 507.0]) {
      testWidgets('real music page ${language.code} $width x 320 at 200%',
          (tester) async {
        _size(tester, Size(width, 320));
        _libraryFixture();
        uiLanguage.value = language;
        await tester.pumpWidget(_app(const AudiosPage()));
        expect(_opacity(tester), 0);
        await _settle(tester);
        final entrance = tester.state(_entrance());
        expect(_opacity(tester), 1);
        expect(tester.getSize(_header()).height, lessThanOrEqualTo(304 * .6));
        expect(tester.getSize(_body()).height,
            greaterThanOrEqualTo(304 * .4 - .1));
        expect(tester.getRect(_body()).top,
            greaterThanOrEqualTo(tester.getRect(_header()).bottom));

        final content = _listController(tester)..jumpTo(700);
        await _settle(tester);
        final search = find.widgetWithText(FilledButton, ui('搜索'));
        await tester.ensureVisible(search);
        await _settle(tester);
        expect(search.hitTestable(), findsOneWidget);
        expect(tester.widget<FilledButton>(search).onPressed, isNotNull);
        expect(content.offset, 700);
        await _selectGrid(tester);
        expect(AppPreference.instance.audiosPagePref.contentView,
            ContentView.table);
        expect(tester.widget<GridView>(find.byType(GridView)).controller,
            same(content));
        expect(tester.state(_entrance()), same(entrance));
        expect(_opacity(tester), 1);
      });
    }
  }

  for (final spec in [
    (width: 1800.0, columns: true),
    (width: 1800.0, columns: false),
    (width: 320.0, columns: false),
  ]) {
    for (final targetIndex in [100, 199]) {
      testWidgets(
          'real music locate $targetIndex at ${spec.width}, columns=${spec.columns}',
          (tester) async {
        _size(tester, Size(spec.width, 800));
        final songs = _libraryFixture();
        final target = songs[targetIndex];
        await tester.pumpWidget(
            _app(AudiosPage(locateTo: target), columns: spec.columns));
        await _settle(tester);
        final tile = find.byWidgetPredicate((widget) =>
            widget is AudioTile &&
            identical(widget.playlist[widget.audioIndex], target));
        expect(tile, findsOneWidget);
        final bounds = tester.getRect(tile);
        final viewport = tester.getRect(find.byType(ListView));
        expect(bounds.top, greaterThanOrEqualTo(viewport.top - .1));
        expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom + .1));
        expect(find.text(target.title).hitTestable(), findsOneWidget);
        expect(find.byType(AudioColumnsHeader),
            spec.columns ? findsOneWidget : findsNothing);
        if (spec.columns && targetIndex == 100) {
          expect(_listController(tester).offset, closeTo(100 * 64, .1));
        }
      });
    }
  }

  testWidgets(
      'locate refines mixed actual row extents without a full-size copy',
      (tester) async {
    _size(tester, const Size(900, 800));
    final heights =
        List.generate(200, (i) => i < 60 ? 40.0 : [200.0, 80.0, 150.0][i % 3]);
    await tester.pumpWidget(_app(UniPage<int>(
      pref: PagePreference(0, SortOrder.ascending, ContentView.list),
      title: 'Variable rows',
      contentList: List.generate(200, (index) => index),
      locateTo: 100,
      contentBuilder: (_, item, __, ___) => SizedBox(
          key: ValueKey('row-$item'),
          height: heights[item],
          child: Text('Row $item')),
      enableShufflePlay: false,
      enableSortMethod: false,
      enableSortOrder: false,
      enableContentViewSwitch: false,
    )));
    await _settle(tester);
    expect(find.text('Row 100').hitTestable(), findsOneWidget);
    expect(_listController(tester).offset,
        closeTo(heights.take(100).reduce((a, b) => a + b), .1));
    expect(find.textContaining('Row ').evaluate().length, lessThan(30));
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('resize and language keep independent header/content state',
      (tester) async {
    _size(tester, const Size(320, 320));
    _libraryFixture();
    await tester.pumpWidget(_app(const AudiosPage()));
    await _settle(tester);
    final entrance = tester.state(_entrance());
    final route = ModalRoute.of(tester.element(find.byType(AudiosPage)));
    final content = _listController(tester)..jumpTo(700);
    final headerState = tester.state<ScrollableState>(
        find.descendant(of: _header(), matching: find.byType(Scrollable)));
    headerState.position.jumpTo(headerState.position.maxScrollExtent);
    await _settle(tester);
    for (final language in UiLanguage.values) {
      final previousHeaderOffset = headerState.position.pixels;
      uiLanguage.value = language;
      tester.view.physicalSize =
          Size(language == UiLanguage.ja ? 507 : 320, 320);
      await _settle(tester);
      expect(_listController(tester), same(content));
      expect(content.offset, 700);
      expect(tester.state(_entrance()), same(entrance));
      expect(_opacity(tester), 1);
      expect(
          ModalRoute.of(tester.element(find.byType(AudiosPage))), same(route));
      expect(
          tester.state<ScrollableState>(find.descendant(
              of: _header(), matching: find.byType(Scrollable))),
          same(headerState));
      // Flutter may replace ScrollPosition when the inherited scroll behavior
      // changes. Its state and retained/clamped offset are the stable contract.
      expect(
          headerState.position.pixels,
          closeTo(
              previousHeaderOffset.clamp(
                  0.0, headerState.position.maxScrollExtent),
              .1));
    }
  });

  testWidgets('manual scroll cancels a pending measured locate',
      (tester) async {
    _size(tester, const Size(1800, 800));
    final songs = _libraryFixture();
    await tester
        .pumpWidget(_app(AudiosPage(locateTo: songs[100]), columns: true));
    final controller = _listController(tester);
    final context = tester.element(find.byType(ListView));
    UserScrollNotification(
      metrics: controller.position,
      context: context,
      direction: ScrollDirection.reverse,
    ).dispatch(context);
    controller.jumpTo(0);
    await _settle(tester);
    expect(controller.offset, 0);
  });
}
