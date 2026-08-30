import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/uni_detail_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

class _Detail extends StatelessWidget {
  _Detail({this.selection});
  final selectionType = PicShape.oval;
  final MultiSelectController<Audio>? selection;
  final pref = PagePreference(0, SortOrder.ascending, ContentView.list);
  final noImage = Future<ImageProvider?>.value();
  final audios = <Audio>[
    for (var i = 0; i < 30; i++)
      CategoryTestAudio('Song · 音楽 · 음악 {0} $i',
          artist: 'Artist', album: 'Album')
  ];

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return UniDetailPage<String, Audio, String>(
      pref: pref,
      primaryContent: 'stable-album-id',
      primaryPic: noImage,
      backgroundPic: noImage,
      picShape: selectionType,
      title: '音乐原文 / Album · アルバム · 앨범 {0} 👩🏽‍🎤',
      subtitle: ui('{0} 首乐曲', [audios.length]),
      secondaryContent: audios,
      secondaryContentBuilder: (_, audio, i, controller) => AudioTile(
          audioIndex: i, playlist: audios, multiSelectController: controller),
      tertiaryContentTitle: ui('专辑'),
      tertiaryContent: const ['Related Album'],
      tertiaryContentBuilder: (_, title, __, ___) => Text(title),
      enableShufflePlay: false,
      enableSortMethod: true,
      enableSortOrder: true,
      enableSecondaryContentViewSwitch: true,
      sortMethods: [
        SortMethodDesc<Audio>(
            icon: Icons.title, name: ui('歌名'), method: (_, __) {})
      ],
      multiSelectController: selection,
      multiSelectViewActions: [
        IconButton(
            tooltip: ui('退出多选'),
            onPressed: () => selection?.useMultiSelectView(false),
            icon: const Icon(Icons.close))
      ],
    );
  }
}

Widget _app(Widget detail) => ValueListenableBuilder<UiLanguage>(
      valueListenable: uiLanguage,
      child: Scaffold(body: detail),
      builder: (_, language, child) => MaterialApp(
        locale: language.locale,
        supportedLocales: [for (final value in UiLanguage.values) value.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          platform: TargetPlatform.windows,
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: language == UiLanguage.ko
                  ? Brightness.dark
                  : Brightness.light),
        ),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: UiLanguageScope(child: child!),
        ),
        home: child,
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Finder _entrance() => find.byWidgetPredicate(
    (widget) => widget is AppEntrance && widget.identity == 'detail-header');
double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(
        find.descendant(of: _entrance(), matching: find.byType(Opacity)).first)
    .opacity;

Future<void> _grid(WidgetTester tester) async {
  final selector = find.byType(AppSegmentedControl<ContentView>);
  var option = find.text(ui('网格'));
  if (option.evaluate().isEmpty) {
    final button = find.descendant(
        of: selector,
        matching: find.byWidgetPredicate(
            (widget) => widget is IconButton || widget is OutlinedButton));
    await tester.ensureVisible(button.first);
    await _settle(tester);
    await tester.tap(button.first);
    await _settle(tester);
    option = find.text(ui('网格'));
  }
  await tester.ensureVisible(option.last);
  await _settle(tester);
  await tester.tap(option.hitTestable().last);
  await _settle(tester);
}

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

  for (final language in UiLanguage.values) {
    for (final width in [320.0, 507.0, 1280.0]) {
      for (final height in [320.0, 800.0]) {
        testWidgets('real detail ${language.code} $width x $height 200%',
            (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, height);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          uiLanguage.value = language;
          final detail = _Detail();
          await tester.pumpWidget(_app(detail));
          expect(_opacity(tester), 0);
          await _settle(tester);
          expect(_opacity(tester), 1);
          final header = tester
              .getRect(find.byKey(const ValueKey('uni-detail-header-scroll')));
          final content = tester
              .getRect(find.byKey(const ValueKey('uni-detail-content-scroll')));
          expect(content.height, greaterThanOrEqualTo((height - 48) * .4 - 1));
          expect(content.top, greaterThan(header.bottom));
          final cover =
              tester.getSize(find.byKey(const ValueKey('uni-detail-cover')));
          expect(cover.width, width < 400 ? 72 : 96);
          expect(cover.width, cover.height);
          expect(find.text(ui('{0} 首乐曲', [30])), findsOneWidget);
          final entrance = tester.state(_entrance());
          await _grid(tester);
          expect(detail.pref.contentView, ContentView.table);
          expect(tester.state(_entrance()), same(entrance));
          expect(_opacity(tester), 1);
          expect(find.byType(SliverGrid), findsOneWidget);
          await tester.drag(
              find.byKey(const ValueKey('uni-detail-content-scroll')),
              const Offset(0, -250));
          await _settle(tester);
          expect(_opacity(tester), 1);
        });
      }
    }
  }

  testWidgets(
      'detail resize/language/multiselect keeps entrance and body position',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selection = MultiSelectController<Audio>()..useMultiSelectView(true);
    addTearDown(selection.dispose);
    final detail = _Detail(selection: selection);
    await tester.pumpWidget(_app(detail));
    await _settle(tester);
    await tester.tap(find.text(detail.audios.first.displayTitle));
    await tester.pump();
    final scroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    scroll.jumpTo(500);
    await tester.pump();
    final entrance = tester.state(_entrance());
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      tester.view.physicalSize =
          Size(language == UiLanguage.ja ? 320 : 507, 800);
      await tester.pump();
      expect(_opacity(tester), 1);
      await _settle(tester);
      expect(tester.state(_entrance()), same(entrance));
      expect(
          tester
              .widget<CustomScrollView>(find.byType(CustomScrollView))
              .controller,
          same(scroll));
      expect(scroll.offset, 500);
      expect(selection.selected, {detail.audios.first});
    }
  });
}
