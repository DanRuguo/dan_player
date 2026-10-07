import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:dan_player/play_service/queue_order.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

Widget _host(PlaylistFeaturePlayback playback,
        {double scale = 1,
        TextDirection direction = TextDirection.ltr,
        GlobalKey? boundary}) =>
    MaterialApp(
        locale: uiLanguage.value.locale,
        supportedLocales: [for (final item in UiLanguage.values) item.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: applyAppControlTheme(ThemeData(
            useMaterial3: true,
            platform: TargetPlatform.windows,
            fontFamily: danEmbeddedFontFamily,
            fontFamilyFallback: danFontFamilyFallback,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal))),
        builder: (context, child) => RepaintBoundary(
            key: boundary,
            child: Directionality(
                textDirection: direction,
                child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        disableAnimations: true),
                    child: child!))),
        home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: CurrentPlaylistView(playbackService: playback))));

Future<void> _open(WidgetTester tester, String menu) async {
  await tester.ensureVisible(_key(menu));
  await tester.tap(_key(menu));
  await tester.pumpAndSettle();
}

void _expectNaturalWidth(WidgetTester tester, List<String> rows) {
  var widestText = 0.0, widestRow = 0.0;
  for (final id in rows) {
    widestRow = widestRow < tester.getSize(_key(id)).width
        ? tester.getSize(_key(id)).width
        : widestRow;
    for (final rich in find
        .descendant(of: _key(id), matching: find.byType(RichText))
        .evaluate()) {
      final paragraph = rich.renderObject! as RenderParagraph;
      final intrinsic = paragraph.getMaxIntrinsicWidth(double.infinity);
      if (intrinsic > widestText) widestText = intrinsic;
    }
  }
  // Leave a generous budget for native menu padding, leading icons, check
  // columns and submenu arrows. Short labels must not force a 360 px body.
  expect(widestRow, lessThanOrEqualTo(widestText + 120),
      reason: 'menu width should follow text and native icon columns');
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final kind in ['organizer', 'sort', 'arrange', 'export']) {
    testWidgets('queue $kind menu hugs natural labels in a wide window',
        (tester) async {
      sizePlaylistFeature(tester, width: 1100, height: 900);
      final playback = PlaylistFeaturePlayback([
        CategoryTestAudio('Active'),
        CategoryTestAudio('Zulu'),
        CategoryTestAudio('Alpha'),
        CategoryTestAudio('Other')
      ]);
      addTearDown(playback.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(_host(playback, boundary: boundary));
      await tester.pumpAndSettle();
      await _open(
          tester, kind == 'export' ? 'queue-export-m3u' : 'queue-organize');
      if (kind == 'sort' || kind == 'arrange') {
        await _open(tester, 'queue-extra-$kind');
      }
      final rows = switch (kind) {
        'organizer' => [
            'queue-trim-before',
            'queue-trim-after',
            'queue-extra-sort',
            'queue-extra-arrange'
          ],
        'sort' => [
            'queue-sort-name',
            'queue-sort-artist',
            'queue-sort-album',
            'queue-sort-duration',
            for (final order in UpcomingQueueOrder.values
                .where((order) => !order.arrangement))
              'queue-order-${order.name}',
            'queue-reverse-upcoming'
          ],
        'arrange' => [
            for (final order in UpcomingQueueOrder.values
                .where((order) => order.arrangement))
              'queue-order-${order.name}'
          ],
        _ => ['queue-export-m3u-all', 'queue-export-folder-all'],
      };
      _expectNaturalWidth(tester, rows);
      await capturePlaylistFeature(tester, boundary, 'queue-zh-wide-$kind');
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'queue menus remain reachable in four languages large text and RTL',
      (tester) async {
    sizePlaylistFeature(tester, width: 360, height: 900);
    final playback = PlaylistFeaturePlayback([
      CategoryTestAudio('Active'),
      CategoryTestAudio('Zulu'),
      CategoryTestAudio('Alpha')
    ]);
    addTearDown(playback.dispose);
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final direction in TextDirection.values) {
        final boundary = GlobalKey();
        await tester.pumpWidget(_host(playback,
            scale: 2, direction: direction, boundary: boundary));
        await tester.pumpAndSettle();
        await _open(tester, 'queue-organize');
        await capturePlaylistFeature(tester, boundary,
            'queue-${language.name}-${direction.name}-organizer');
        await _open(tester, 'queue-extra-sort');
        for (final row in ['queue-sort-name', 'queue-reverse-upcoming']) {
          await tester.ensureVisible(_key(row));
          await tester.pumpAndSettle();
          expect(_key(row).hitTestable(), findsOneWidget,
              reason: '${language.name}/${direction.name}/$row');
          final rect = tester.getRect(_key(row));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(360));
          final label =
              find.descendant(of: _key(row), matching: find.byType(Text)).first;
          Focus.of(tester.element(label)).requestFocus();
          await tester.pump();
          expect(Focus.of(tester.element(label)).hasFocus, isTrue);
        }
        await capturePlaylistFeature(tester, boundary,
            'queue-${language.name}-${direction.name}-sort-tail');
        expect(tester.takeException(), isNull);
        expect(playback.nowPlaying, same(playback.playlist.value.first));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
}
