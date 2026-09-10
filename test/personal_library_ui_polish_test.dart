import 'dart:io';
import 'package:dan_player/component/app_content_transition.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/page/personal_library_page.dart';
import 'package:flutter/gestures.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'dart:ui' as drawing;
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/personal_library_dialog.dart';
import 'package:dan_player/component/app_date_range_dialog.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/component/listening_tools_dialog.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/page/settings_page/other_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';

class _Personal extends PersonalLibrary {
  _Personal() : super(File('unused-test-store'));
  @override
  Future<Map<String, PersonalTrack>> snapshot() async => {
        for (final name in ['Canon', 'Canon · 卡农 · カノン · 캐논', 'Good Time'])
          CategoryTestAudio(name).stableTrackId: PersonalTrack(
              rating: name == 'Good Time' ? null : 4,
              tags: ['Night', 'Chorus', 'Favorite', 'Piano', 'Music'],
              modifiedAtUtc: DateTime.utc(2026, 9, 9))
      };
}

class _ManyPersonal extends PersonalLibrary {
  _ManyPersonal() : super(File('unused-many-personal'));
  @override
  Future<Map<String, PersonalTrack>> snapshot() async => {
        for (var i = 0; i < 24; i++)
          CategoryTestAudio('Row $i').stableTrackId:
              PersonalTrack(rating: 4, modifiedAtUtc: DateTime.utc(2026, 9, 9))
      };
}

class _Covers extends CategoryCoverStore {
  _Covers() : super(dataDirectory: () async => Directory('unused-covers'));
  @override
  Future<void> load() async {}
  @override
  Future<void> reconcileKind(
      MusicCategoryKind kind, Iterable<MusicCategoryGroup> groups) async {}
}

class _Bookmarks extends PlaybackBookmarkStore {
  _Bookmarks() : super(File('unused-test-bookmarks'));
  @override
  Future<List<PlaybackBookmark>> all() async => const [
        PlaybackBookmark(
            id: 'point',
            track: 'missing',
            label: 'Canon · 晚间片段 · 夜の音楽 · 밤의 음악',
            positionMs: 90000),
        PlaybackBookmark(
            id: 'range',
            track: 'missing',
            label: 'Good Time · Chorus',
            positionMs: 60000,
            endMs: 75000),
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const output = String.fromEnvironment('DAN_UI_POLISH_RENDER');
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
    final bytes = await File('C:/Windows/Fonts/malgun.ttf').readAsBytes();
    await (FontLoader('Malgun Gothic')
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  });
  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    if (output.isEmpty) return;
    await tester.runAsync(() async {
      final pic = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final data = await pic.toByteData(format: drawing.ImageByteFormat.png);
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      pic.dispose();
    });
  }

  test('personal tools stay in categories without adding a sidebar destination',
      () {
    expect(destinations.map((d) => d.desPath), [
      '/audios',
      '/categories',
      '/playlists',
      '/folders',
      '/search',
      '/statistics',
      '/settings'
    ]);
  });
  testWidgets(
      'personal song viewport extends behind floating bar with scroll clearance',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PersonalLibraryPanel(personalStore: _ManyPersonal(), audios: [
      for (var i = 0; i < 24; i++) CategoryTestAudio('Row $i')
    ]))));
    await tester.pumpAndSettle();
    final list = find.byType(ListView);
    expect(tester.getBottomRight(list).dy, 800);
    final padding = tester.widget<ListView>(list).padding as EdgeInsets;
    expect(padding.bottom, greaterThanOrEqualTo(80));
    final scroll = tester
        .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first)
        .position;
    scroll.jumpTo(scroll.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(find.byType(AudioTile).last).dy,
        lessThanOrEqualTo(800 - padding.bottom));
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets(
        'personal tabs preserve their selector and honor motion reduced=$reduced',
        (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!),
          home: Scaffold(
              body: PersonalLibraryPanel(
                  personalStore: _Personal(),
                  bookmarkStore: _Bookmarks(),
                  audios: [CategoryTestAudio('Canon')]))));
      await tester.pumpAndSettle();
      final tabs = find.byKey(const ValueKey('personal-library-tabs'));
      final bounds = tester.getRect(tabs);
      final before = find.byType(AppSegmentedControl<bool>).evaluate().single;
      final transition = find.byKey(const ValueKey('personal-library-content'));
      expect(tester.widget<AppContentTransition>(transition).identity, false);
      await tester.tap(find.text(ui('全库书签')));
      await tester.pump();
      expect(tester.getRect(tabs), bounds);
      expect(find.byType(AppSegmentedControl<bool>).evaluate().single,
          same(before));
      final fade = find
          .descendant(of: transition, matching: find.byType(FadeTransition))
          .first;
      expect(
          tester.widget<FadeTransition>(fade).opacity.value, reduced ? 1 : 0);
      await tester.pump(AppMotion.standard ~/ 2);
      if (!reduced) {
        expect(tester.widget<FadeTransition>(fade).opacity.value,
            allOf(greaterThan(0), lessThan(1)));
      }
      await tester.pumpAndSettle();
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      await tester.tap(find.text(ui('评分和标签')));
      await tester.pumpAndSettle();
      expect(tester.getRect(tabs), bounds);
      expect(find.byType(PersonalLibraryDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final viewport in [const Size(380, 560), const Size(900, 420)]) {
    testWidgets('date range remains usable at $viewport', (tester) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      DateTimeRange? result;
      await tester.pumpWidget(MaterialApp(
        theme: Entry(welcome: false).fromSchemeAndFontFamily(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      child: const Text('Open'),
                      onPressed: () async {
                        result = await showAppDateRangePicker(context,
                            initialRange: DateTimeRange(
                                start: DateTime(2026, 9, 1),
                                end: DateTime(2026, 9, 8)),
                            lastDate: DateTime(2026, 9, 15));
                      },
                    ))),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('date-range-end')));
      await tester.tap(find.byKey(const ValueKey('date-range-end')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(ui('输入日期')));
      await tester.tap(find.text(ui('输入日期')));
      await tester.pumpAndSettle();
      final input = find.byType(TextFormField);
      final locale = MaterialLocalizations.of(tester.element(input));
      await tester.enterText(
          input, locale.formatCompactDate(DateTime(2026, 9, 3)));
      await tester.tap(find.text(ui('应用')));
      await tester.pumpAndSettle();
      expect(
          result,
          DateTimeRange(
              start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 3)));
      expect(tester.takeException(), isNull);
    });
  }
  for (final language in UiLanguage.values) {
    for (final large in [false, true]) {
      testWidgets('expanded controls ${language.name} large=$large',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(large ? 660 : 1100, large ? 820 : 840);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        uiLanguage.value = language;
        addTearDown(() => uiLanguage.value = UiLanguage.zh);
        final savedExperience = AppSettings.instance.experience.value;
        final savedPower = DesktopIntegration.instance.powerRequestStatus.value;
        addTearDown(() {
          AppSettings.instance.experience.value = savedExperience;
          DesktopIntegration.instance.powerRequestStatus.value = savedPower;
        });
        final captureKey = GlobalKey();
        final scheme = ColorScheme.fromSeed(
            seedColor: Colors.amber,
            brightness: large ? Brightness.dark : Brightness.light);
        final theme =
            Entry(welcome: false).fromSchemeAndFontFamily(colorScheme: scheme);
        Widget host(Widget child) => RepaintBoundary(
            key: captureKey,
            child: UiLanguageScope(
                child: MaterialApp(
              theme: theme,
              debugShowCheckedModeBanner: false,
              locale: language.locale,
              supportedLocales: UiLanguage.values.map((l) => l.locale),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(large ? 1.8 : 1)),
                  child: child!),
              home: Scaffold(
                  body:
                      Padding(padding: const EdgeInsets.all(24), child: child)),
            )));
        await tester.pumpWidget(host(CategoriesPage(
          audios: [CategoryTestAudio('Canon')],
          personalStore: _Personal(),
          coverStore: _Covers(),
          bookmarkStore: _Bookmarks(),
        )));
        await tester.pumpAndSettle();
        final personalCategory =
            find.byKey(const ValueKey('category-kind-personal'));
        await tester.ensureVisible(personalCategory);
        await tester.tap(personalCategory);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(personalCategory).selected, isTrue);
        expect(
            find.byKey(const ValueKey('personal-rating-menu')), findsOneWidget);
        await capture(
            tester, captureKey, 'category-personal-${language.name}-$large');
        final tabs = find.byKey(const ValueKey('personal-library-tabs'));
        final tabBounds = tester.getRect(tabs);
        final selectorElement =
            find.byType(AppSegmentedControl<bool>).evaluate().single;
        if (find.text(ui('全库书签')).evaluate().isEmpty) {
          await tester.tap(find.text(ui('评分和标签')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(ui('全库书签')));
        await tester.pumpAndSettle();
        expect(find.byType(BookmarkLibraryDialog), findsOneWidget);
        expect(tester.getRect(tabs), tabBounds,
            reason:
                'Both tabs retain the same bounds at every locale and scale');
        expect(find.byType(AppSegmentedControl<bool>).evaluate().single,
            same(selectorElement),
            reason: 'Selection animation must keep its element');
        await tester.scrollUntilVisible(find.text('Good Time · Chorus'), 140,
            scrollable: find
                .descendant(
                    of: find.byType(BookmarkLibraryDialog),
                    matching: find.byType(Scrollable))
                .last);
        expect(find.text('Good Time · Chorus'), findsOneWidget);
        expect(find.byType(Checkbox), findsNothing);
        await tester.ensureVisible(find.text('Good Time · Chorus'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Good Time · Chorus'));
        await tester.pumpAndSettle();
        final selectedCard = tester
            .widgetList<Material>(find.byType(Material))
            .where((m) =>
                m.shape is RoundedRectangleBorder &&
                (m.shape! as RoundedRectangleBorder).side.width == 2);
        expect(selectedCard, isNotEmpty);
        expect(tester.takeException(), isNull);
        await capture(
            tester, captureKey, 'category-bookmarks-${language.name}-$large');
        if (large) {
          final rename = find.byTooltip(ui('重命名')).last;
          await tester.ensureVisible(rename);
          await tester.pumpAndSettle();
          expect(rename.hitTestable(), findsOneWidget);
          await capture(
              tester, captureKey, 'bookmark-actions-${language.name}');
        }
        final albums = find.byKey(const ValueKey('category-kind-album'));
        await tester.ensureVisible(albums);
        await tester.tap(albums);
        await tester.pumpAndSettle();
        expect(tester.widget<ChoiceChip>(albums).selected, isTrue);
        expect(find.byType(BookmarkLibraryDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(host(
            PersonalLibraryDialog(embedded: true, store: _Personal(), audios: [
          CategoryTestAudio('Canon · 卡农 · カノン · 캐논'),
          CategoryTestAudio('Good Time'),
          CategoryTestAudio('Untouched song')
        ])));
        await tester.pumpAndSettle();
        expect(find.text('Untouched song'), findsNothing);
        final heights = [
          for (final key in [
            'personal-days-0',
            'personal-days-7',
            'personal-days-30',
            'personal-date-range'
          ])
            tester.getSize(find.byKey(ValueKey(key))).height
        ];
        expect(heights.every((h) => (h - heights.first).abs() < .1), isTrue);
        expect(tester.takeException(), isNull);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.byType(AudioTile).first));
        await tester.pumpAndSettle();
        await capture(tester, captureKey, 'personal-${language.name}-$large');
        await mouse.removePointer();
        await tester.tap(find.byKey(const ValueKey('personal-rating-menu')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('personal-rating-4')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(
            tester, captureKey, 'rating-menu-${language.name}-$large');
        await tester.tap(find.byKey(const ValueKey('personal-rating-4')));
        await tester.pumpAndSettle();
        expect(find.text('Canon · 卡农 · カノン · 캐논'), findsOneWidget);
        expect(find.text('Good Time'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('personal-date-range')));
        await tester.pumpAndSettle();
        final dialog = find.byKey(const ValueKey('app-date-range-dialog'));
        expect(dialog, findsOneWidget);
        final painted =
            find.descendant(of: dialog, matching: find.byType(Material)).first;
        expect(tester.getSize(painted).width, lessThanOrEqualTo(528));
        expect(tester.takeException(), isNull);
        await capture(tester, captureKey, 'calendar-${language.name}-$large');
        await tester.ensureVisible(find.text(ui('输入日期')));
        await tester.tap(find.text(ui('输入日期')));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byType(InputDatePickerFormField).evaluate().isNotEmpty
                ? find.descendant(
                    of: find.byType(InputDatePickerFormField),
                    matching: find.byType(TextFormField))
                : find.byType(TextFormField),
            'invalid');
        await tester.tap(find.text(ui('应用')));
        await tester.pumpAndSettle();
        expect(dialog, findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, captureKey, 'date-error-${language.name}-$large');
        await tester.tap(find.byTooltip(ui('关闭')));
        await tester.pumpAndSettle();
        await tester.pumpWidget(host(const Column(children: [
          PreventSleepSwitch(),
          SizedBox(height: 12),
          RestoreSessionSwitch()
        ])));
        await tester.pumpAndSettle();
        expect(
            tester
                .widgetList<SettingsSwitchTile>(find.byType(SettingsSwitchTile))
                .length,
            2);
        expect(tester.takeException(), isNull);
        AppSettings.instance.experience.value =
            savedExperience.copyWith(preventSleepDuringPlayback: false);
        await tester.pumpAndSettle();
        expect(find.text(ui('已关闭 · 使用系统休眠设置')), findsOneWidget);
        await capture(tester, captureKey, 'settings-${language.name}-$large');
        AppSettings.instance.experience.value =
            savedExperience.copyWith(preventSleepDuringPlayback: true);
        DesktopIntegration.instance.powerRequestStatus.value = '未请求';
        await tester.pumpAndSettle();
        expect(find.text(ui('已开启 · 等待播放')), findsOneWidget);
        DesktopIntegration.instance.powerRequestStatus.value = '已生效';
        await tester.pumpAndSettle();
        expect(find.text(ui('已开启 · 播放中，防休眠已生效')), findsOneWidget);
        await capture(
            tester, captureKey, 'settings-active-${language.name}-$large');
        DesktopIntegration.instance.powerRequestStatus.value = '电源请求失败：test';
        await tester.pumpAndSettle();
        expect(find.text(ui('未生效 · 请重新切换开关')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        expect(PlayService.isInitialized, isFalse);
      });
    }
  }
}
