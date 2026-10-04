import 'dart:io';

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/player_feature_guide.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:desktop_lyric/l10n/catalog_player_feature_guide.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;

import 'support/playlist_feature_fixture.dart';

const _topics = [
  ('queue', '播放队列与停止目标', 'guide-session-settings'),
  ('bookmarks', '书签与播放记忆', 'guide-resume-settings'),
  ('lyric-display', '桌面与任务栏歌词', 'guide-taskbar-lyric-settings'),
  ('storage', '文件夹与缓存管理', 'guide-backup-settings'),
  ('statistics', '统计与资源监控', 'guide-resource-settings'),
  ('sound', '速度、音高与音量', 'guide-replaygain-settings'),
];
const _settingsLinks = [
  ('queue', 'guide-session-settings', 'library', 'session'),
  ('bookmarks', 'guide-resume-settings', 'library', 'resume'),
  (
    'lyric-display',
    'guide-desktop-lyric-settings',
    'desktop',
    'desktop-lyrics'
  ),
  ('lyric-display', 'guide-taskbar-lyric-settings', 'desktop', 'integration'),
  ('storage', 'guide-backup-settings', 'backup', 'backup'),
  ('statistics', 'guide-resource-settings', 'backup', 'process-resources'),
  ('sound', 'guide-speed-pitch-settings', 'library', 'playback'),
  ('sound', 'guide-replaygain-settings', 'library', 'gain'),
];

Widget _frame(BuildContext context, Widget child,
        {GlobalKey? boundary, double scale = 1}) =>
    RepaintBoundary(
        key: boundary,
        child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
                disableAnimations: true, textScaler: TextScaler.linear(scale)),
            child: child));

ThemeData _theme(bool dark) => applyAppControlTheme(ThemeData(
    platform: TargetPlatform.windows,
    useMaterial3: true,
    fontFamily: danEmbeddedFontFamily,
    fontFamilyFallback: danFontFamilyFallback,
    colorScheme: ColorScheme.fromSeed(
        seedColor: dark ? Colors.deepOrange : Colors.teal,
        brightness: dark ? Brightness.dark : Brightness.light)));

Widget _app({GlobalKey? boundary, double scale = 1}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme(scale > 1),
    builder: (context, child) =>
        _frame(context, child!, boundary: boundary, scale: scale),
    home: const Scaffold(
        body: SingleChildScrollView(child: PlayerFeatureGuideSettings())));

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-player-feature-guide')));
  await tester.pumpAndSettle();
  await _toggle(tester, 'playlists');
}

Finder _header(String id) => find
    .descendant(
        of: find.byKey(ValueKey('guide-section-$id')),
        matching: find.byType(ListTile))
    .first;

Future<void> _showHeader(WidgetTester tester, String id) async {
  await Scrollable.ensureVisible(tester.element(_header(id)), alignment: 0);
  await tester.pumpAndSettle();
}

Future<void> _toggle(WidgetTester tester, String id) async {
  await _showHeader(tester, id);
  await tester.tap(_header(id));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    final output = Platform.environment['DAN_PLAYLIST_FEATURE_RENDER_DIR'];
    if (output == null) return;
    final allowed = path.normalize(path.join(Directory.current.parent.path,
        'tool', 'qa-local', 'features-2606-oct4', 'feature-guide'));
    expect(
        path.isWithin(allowed, path.normalize(path.absolute(output))), isTrue,
        reason: 'Guide screenshots must use the isolated QA directory');
  });

  test('new guide catalog has all four languages', () {
    final keys = catalogPlayerFeatureGuide.keys
        .skipWhile((key) => key != '队列、书签、歌词、文件夹与统计的常用操作；设置和已有说明可直接打开。');
    expect(keys.length, greaterThanOrEqualTo(29));
    for (final key in keys) {
      expect(catalogPlayerFeatureGuide[key], hasLength(3));
      for (final language in UiLanguage.values) {
        expect(translateUi(key, language).trim(), isNotEmpty);
        if (language != UiLanguage.zh) {
          expect(translateUi(key, language), isNot(key), reason: key);
        }
      }
    }
  });

  testWidgets('new topics link existing setting IDs without activating tools',
      (tester) async {
    sizePlaylistFeature(tester);
    final oldLanguage = uiLanguage.value;
    addTearDown(() => uiLanguage.value = oldLanguage);
    uiLanguage.value = UiLanguage.zh;
    final destinations = <String>[];
    await tester.pumpWidget(MaterialApp(
        theme: _theme(false),
        builder: (context, child) => _frame(context, child!),
        home: Scaffold(
            body: PlayerFeatureGuideDialog(onNavigate: destinations.add))));
    await _toggle(tester, 'playlists');
    String? expanded;
    for (final link in _settingsLinks) {
      if (expanded != link.$1) {
        if (expanded != null) await _toggle(tester, expanded);
        await _toggle(tester, link.$1);
        expanded = link.$1;
      }
      final button = find.byKey(ValueKey(link.$2));
      await tester.ensureVisible(button);
      await tester.tap(button);
      final entry = settingsSearchEntries.singleWhere(
          (entry) => entry.section == link.$3 && entry.id == link.$4);
      expect(destinations.last, entry.location);
    }
    expect(destinations, hasLength(8));
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'new guide links close the real dialog and route with query intact',
      (tester) async {
    sizePlaylistFeature(tester);
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
              body:
                  SingleChildScrollView(child: PlayerFeatureGuideSettings()))),
      for (final route in ['/settings', '/folders', '/statistics'])
        GoRoute(
            path: route,
            builder: (context, state) => Scaffold(
                body: Text(state.uri.toString(),
                    key: const ValueKey('guide-route-target')))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        theme: _theme(false),
        builder: (context, child) => _frame(context, child!)));
    for (final target in [
      ('storage', 'guide-folder-page', '/folders'),
      ('statistics', 'guide-cache-statistics', '/statistics?section=cache'),
      (
        'statistics',
        'guide-resource-settings',
        '/settings?section=backup&setting=process-resources'
      ),
    ]) {
      router.go('/');
      await tester.pumpAndSettle();
      await _open(tester);
      await _toggle(tester, target.$1);
      final button = find.byKey(ValueKey(target.$2));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerFeatureGuideDialog), findsNothing);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('guide-route-target')))
              .data,
          target.$3);
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets('new guide ${language.name} narrow=$narrow real fonts',
          (tester) async {
        final oldLanguage = uiLanguage.value;
        addTearDown(() => uiLanguage.value = oldLanguage);
        uiLanguage.value = language;
        sizePlaylistFeature(tester, width: narrow ? 360 : 1080, height: 1200);
        final boundary = GlobalKey();
        await tester
            .pumpWidget(_app(boundary: boundary, scale: narrow ? 2 : 1));
        await _open(tester);
        for (final topic in _topics) {
          await _toggle(tester, topic.$1);
          await _showHeader(tester, topic.$1);
          final section = find.byKey(ValueKey('guide-section-${topic.$1}'));
          expect(
              find.descendant(of: section, matching: find.text(ui(topic.$2))),
              findsOneWidget);
          final tile = tester.widget<ExpansionTile>(section);
          expect(tile.leading, isA<Icon>());
          expect(
              tester
                  .widget<Icon>(find
                      .descendant(
                          of: _header(topic.$1), matching: find.byType(Icon))
                      .first)
                  .color,
              Theme.of(tester.element(section)).colorScheme.primary);
          expect(tester.takeException(), isNull);
          final name =
              'topics-${language.name}-${narrow ? 'narrow-large' : 'wide'}-${topic.$1}';
          await capturePlaylistFeature(tester, boundary, name);
          final lastLink = find.byKey(ValueKey(topic.$3));
          final viewport = tester.getRect(
              find.byKey(const ValueKey('player-feature-guide-scroll')));
          if (tester.getRect(lastLink).bottom > viewport.bottom) {
            await tester.ensureVisible(lastLink);
            await tester.pumpAndSettle();
            await capturePlaylistFeature(tester, boundary, '$name-tail');
          }
          final linkRect = tester.getRect(lastLink);
          expect(linkRect.left, greaterThanOrEqualTo(0));
          expect(linkRect.right, lessThanOrEqualTo(narrow ? 360 : 1080));
          expect(lastLink.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _toggle(tester, topic.$1);
        }
        await tester
            .tap(find.byKey(const ValueKey('close-player-feature-guide')));
        await tester.pumpAndSettle();
        expect(PlayService.isInitialized, isFalse);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
