import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/player_feature_guide.dart';
import 'package:dan_player/page/search_page/search_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/player_shortcut_preferences.dart';
import 'package:dan_player/search/audio_search_query.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:desktop_lyric/l10n/catalog_player_feature_guide.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

Widget _app(Widget child, {GlobalKey? boundary, double scale = 1}) =>
    MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: applyAppControlTheme(ThemeData(
            platform: TargetPlatform.windows,
            useMaterial3: true,
            fontFamily: danEmbeddedFontFamily,
            fontFamilyFallback: danFontFamilyFallback,
            colorScheme: ColorScheme.fromSeed(
                seedColor: scale == 1 ? Colors.teal : Colors.amber,
                brightness: scale == 1 ? Brightness.light : Brightness.dark))),
        builder: (context, child) => RepaintBoundary(
            key: boundary,
            child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale)),
                child: child!)),
        home: Scaffold(body: SingleChildScrollView(child: child)));

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-player-feature-guide')));
  await tester.pumpAndSettle();
}

Future<void> _expand(WidgetTester tester, String id) async {
  final section = find.byKey(ValueKey('guide-section-$id'));
  await tester.ensureVisible(section);
  await tester
      .tap(find.descendant(of: section, matching: find.byType(ListTile)).first);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);

  testWidgets('settings guide opens and closes without starting playback',
      (tester) async {
    sizePlaylistFeature(tester);
    expect(PlayService.isInitialized, isFalse);
    await tester.pumpWidget(_app(const PlayerFeatureGuideSettings()));
    await _open(tester);
    expect(find.byType(PlayerFeatureGuideDialog), findsOneWidget);
    expect(
        find.byKey(const ValueKey('guide-section-playlists')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('guide-section-shortcuts')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-section-search')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close-player-feature-guide')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerFeatureGuideDialog), findsNothing);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guide reuses local search help and valid current syntax',
      (tester) async {
    sizePlaylistFeature(tester);
    await tester.pumpWidget(_app(const PlayerFeatureGuideSettings()));
    await _open(tester);
    await _expand(tester, 'playlists');
    await _expand(tester, 'search');
    final example = tester
        .widget<SelectableText>(
            find.byKey(const ValueKey('guide-search-example')))
        .data!;
    expect(AudioSearchQuery.parse(example).hasStructuredSyntax, isTrue);
    final link = find.byKey(const ValueKey('guide-local-search-help'));
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(LocalSearchHelpDialog), findsOneWidget);
    expect(find.byType(PlayerFeatureGuideDialog), findsOneWidget);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('guide reads saved shortcuts and links exact setting locations',
      (tester) async {
    sizePlaylistFeature(tester);
    final old = AppSettings.instance.shortcuts.value;
    addTearDown(() => AppSettings.instance.shortcuts.value = old);
    AppSettings.instance.shortcuts.value = old.withBinding(PlayerCommand.next,
        ShortcutChord(LogicalKeyboardKey.keyN.keyId, control: true));
    final locations = <String>[];
    await tester
        .pumpWidget(_app(PlayerFeatureGuideDialog(onNavigate: locations.add)));
    await _expand(tester, 'playlists');
    await _expand(tester, 'shortcuts');
    final keysLink = find.byKey(const ValueKey('guide-current-shortcuts'));
    await tester.ensureVisible(keysLink);
    await tester.tap(keysLink);
    await tester.pumpAndSettle();
    expect(find.text('Ctrl + N'), findsOneWidget);
    await tester.tap(find.byTooltip(ui('关闭快捷键说明')));
    await tester.pumpAndSettle();
    final settingLink = find.byKey(const ValueKey('guide-shortcut-settings'));
    await tester.ensureVisible(settingLink);
    await tester.tap(settingLink);
    expect(locations, ['/settings?section=desktop&setting=shortcuts']);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('guide catalog and setting search cover all four languages', () {
    for (final key in catalogPlayerFeatureGuide.keys) {
      expect(catalogPlayerFeatureGuide[key], hasLength(3));
      for (final language in UiLanguage.values) {
        expect(translateUi(key, language), isNotEmpty);
        if (language != UiLanguage.zh) {
          expect(translateUi(key, language), isNot(key));
        }
      }
    }
    for (final language in UiLanguage.values) {
      final results = searchSettings(translateUi('特色操作指南', language));
      expect(results.map((e) => e.id), contains('feature-guide'));
      expect(results.firstWhere((e) => e.id == 'feature-guide').location,
          '/settings?section=backup&setting=feature-guide');
    }
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets('guide ${language.name} narrow=$narrow real fonts',
          (tester) async {
        final oldLanguage = uiLanguage.value;
        addTearDown(() => uiLanguage.value = oldLanguage);
        uiLanguage.value = language;
        sizePlaylistFeature(tester, width: narrow ? 360 : 1080, height: 1000);
        final boundary = GlobalKey();
        await tester.pumpWidget(_app(const PlayerFeatureGuideSettings(),
            boundary: boundary, scale: narrow ? 2 : 1));
        await _open(tester);
        expect(tester.takeException(), isNull);
        await capturePlaylistFeature(tester, boundary,
            'guide-${language.name}-${narrow ? 'narrow-large' : 'wide'}-playlists');
        await _expand(tester, 'playlists');
        await _expand(tester, 'search');
        await _expand(tester, 'shortcuts');
        final link = find.byKey(const ValueKey('guide-shortcut-settings'));
        await tester.ensureVisible(link);
        await tester.pumpAndSettle();
        expect(
            tester.getRect(link).right, lessThanOrEqualTo(narrow ? 360 : 1080));
        expect(tester.takeException(), isNull);
        await capturePlaylistFeature(tester, boundary,
            'guide-${language.name}-${narrow ? 'narrow-large' : 'wide'}-search-shortcuts');
        await tester
            .tap(find.byKey(const ValueKey('close-player-feature-guide')));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerFeatureGuideDialog), findsNothing);
        expect(PlayService.isInitialized, isFalse);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
