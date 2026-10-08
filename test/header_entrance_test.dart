import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/audio_columns.dart';
import 'package:dan_player/component/category_display_controls.dart';
import 'package:dan_player/page/page_scaffold.dart';
import 'package:dan_player/page/settings_page/grouped_settings.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _entrance(String identity) => find.byWidgetPredicate(
    (widget) => widget is AppEntrance && widget.identity == identity);

double _opacity(WidgetTester tester, Finder entrance) => tester
    .widget<Opacity>(
        find.descendant(of: entrance, matching: find.byType(Opacity)).first)
    .opacity;

Offset _offset(WidgetTester tester, Finder entrance) {
  final transform = tester.widget<Transform>(
      find.descendant(of: entrance, matching: find.byType(Transform)).first);
  return Offset(
      transform.transform.storage[12], transform.transform.storage[13]);
}

Widget _body(String identity, TextEditingController? searchController) =>
    switch (identity) {
      'audio-columns-header' => const Column(children: [
          AudioColumnsHeader(),
          Expanded(child: Center(child: Text('爱像首寂寞的歌 / Morning'))),
        ]),
      'category-display-controls' => StatefulBuilder(
          builder: (context, setState) => Column(children: [
                CategoryDisplayControls(
                  value: const CategoryPresentation(),
                  onChanged: (_) => setState(() {}),
                  search: TextField(
                    key: const ValueKey('header-search'),
                    controller: searchController,
                    decoration: InputDecoration(
                        hintText: ui('搜索专辑或专辑艺术家'),
                        prefixIcon: const Icon(Icons.search)),
                  ),
                ),
                const Expanded(child: SizedBox()),
              ])),
      _ => GroupedSettings(sections: [
          for (final section in [
            ('library', '曲库与播放', Icons.library_music_outlined),
            ('lyrics', '联网与歌词', Icons.lyrics_outlined),
            ('appearance', '界面与主题', Icons.palette_outlined),
            ('effects', '背景与动效', Icons.blur_on),
            ('desktop', '桌面与快捷键', Icons.desktop_windows_outlined),
            ('backup', '备份与恢复', Icons.settings_backup_restore_outlined),
            ('about', '更新与关于', Icons.info_outline),
          ])
            SettingsSection(
                id: section.$1,
                title: ui(section.$2),
                icon: section.$3,
                children: [SizedBox(height: 100, child: Text(ui(section.$2)))]),
        ]),
    };

Widget _host(String identity, GlobalKey boundary,
        {double scale = 1,
        bool disabled = false,
        bool hidden = false,
        TextEditingController? searchController,
        bool systemReduced = false}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: applyAppControlTheme(ThemeData(
          platform: TargetPlatform.windows,
          fontFamily: danEmbeddedFontFamily,
          fontFamilyFallback: danFontFamilyFallback,
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xffb14b72),
              brightness: Brightness.dark))),
      builder: (context, child) => UiLanguageScope(
          child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: systemReduced),
              child: MotionPreferencesScope(
                  preferences: MotionPreferences(
                      disabled: disabled ? {MotionKind.entrance} : {}),
                  child: TickerMode(enabled: !hidden, child: child!)))),
      home: RepaintBoundary(
          key: boundary,
          child: Scaffold(
              body: PageScaffold(
                  title: ui('设置'),
                  actions: const [],
                  body: _body(identity, searchController)))),
    );

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  const output = String.fromEnvironment('DAN_HEADER_RENDER');
  if (output.isEmpty) return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    try {
      final file = File('$output/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
          (await image.toByteData(format: drawing.ImageByteFormat.png))!
              .buffer
              .asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });

  for (final identity in [
    'audio-columns-header',
    'category-display-controls',
    'settings-category-navigation',
  ]) {
    testWidgets(
        '$identity enters with the page title and keeps state on resize',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final boundary = GlobalKey();
      final search = TextEditingController();
      addTearDown(search.dispose);
      await tester
          .pumpWidget(_host(identity, boundary, searchController: search));
      final entrance = _entrance(identity);
      final header = find.byWidgetPredicate((widget) =>
          widget is AppEntrance &&
          widget.identity == ('page-header', ui('设置')));
      expect(entrance, findsOneWidget);
      final state = tester.state(entrance);
      expect(_opacity(tester, entrance), 0);
      expect(_offset(tester, entrance), const Offset(0, AppEntrance.distance));
      await _capture(tester, boundary, '$identity-start');
      await tester.pump(const Duration(milliseconds: 60));
      expect(_opacity(tester, entrance), allOf(greaterThan(0), lessThan(1)));
      expect(_opacity(tester, entrance), _opacity(tester, header));
      expect(_offset(tester, entrance), _offset(tester, header));
      await _capture(tester, boundary, '$identity-entering');
      await tester.pumpAndSettle();
      expect(_opacity(tester, entrance), 1);
      expect(_offset(tester, entrance), Offset.zero);
      await _capture(tester, boundary, '$identity-wide');
      if (identity == 'category-display-controls') {
        // Inject an existing draft through the page-owned controller. Native
        // IME messages are independent of the entrance/resize contract.
        search.text = 'draft';
        await tester.pump();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      }
      if (identity == 'settings-category-navigation') {
        await tester
            .tap(find.byKey(const ValueKey('settings-category-lyrics')));
        await tester.pumpAndSettle();
      }
      tester.view.physicalSize = const Size(440, 800);
      uiLanguage.value = UiLanguage.en;
      addTearDown(() => uiLanguage.value = UiLanguage.zh);
      await tester.pumpWidget(
          _host(identity, boundary, scale: 2, searchController: search));
      expect(tester.state(entrance), same(state));
      expect(_opacity(tester, entrance), 1);
      expect(_offset(tester, entrance), Offset.zero);
      await tester.pumpAndSettle();
      if (identity == 'category-display-controls') {
        expect(find.text('draft'), findsOneWidget);
      }
      if (identity == 'settings-category-navigation') {
        expect(
            tester
                .widget<DropdownButton<String>>(
                    find.byKey(const ValueKey('settings-category-picker')))
                .value,
            'lyrics');
      }
      await _capture(tester, boundary, '$identity-narrow-large-en');
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });

    for (final policy in ['disabled', 'system-reduced', 'hidden']) {
      testWidgets('$identity is immediately visible when $policy',
          (tester) async {
        await tester.pumpWidget(_host(identity, GlobalKey(),
            disabled: policy == 'disabled',
            hidden: policy == 'hidden',
            systemReduced: policy == 'system-reduced'));
        expect(_opacity(tester, _entrance(identity)), 1);
        expect(_offset(tester, _entrance(identity)), Offset.zero);
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
