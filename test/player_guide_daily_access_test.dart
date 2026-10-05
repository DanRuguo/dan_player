import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/player_feature_guide.dart';
import 'package:dan_player/component/player_guide_demo.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/playlist_feature_fixture.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    final output = Platform.environment['DAN_DAILY_GUIDE_RENDER_DIR'];
    if (output == null) return;
    final qa = path.normalize(
        path.join(Directory.current.parent.path, 'tool', 'qa-local'));
    expect(path.isWithin(qa, path.normalize(path.absolute(output))), isTrue);
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets(
      'common controls open the real topic and retain it after language changes',
      (tester) async {
    sizePlaylistFeature(tester, width: 900, height: 900);
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(
        playlistFeatureHost(PlayerFeatureGuideDialog(demoIsHidden: hidden)));
    for (final section in ['queue', 'lyrics', 'sound', 'playlists']) {
      final scroll = tester
          .widget<SingleChildScrollView>(_key('player-feature-guide-scroll'))
          .controller!;
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      final quick = _key('guide-common-$section');
      await tester.ensureVisible(quick);
      await tester.tap(quick);
      await tester.pumpAndSettle();
      final topic =
          tester.widget<ExpansionTile>(_key('guide-section-$section'));
      expect(topic.controller!.isExpanded, isTrue);
      final offset = scroll.offset;
      uiLanguage.value = UiLanguage.en;
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<ExpansionTile>(_key('guide-section-$section'))
              .controller!
              .isExpanded,
          isTrue);
      expect(scroll.offset, offset);
      uiLanguage.value = UiLanguage.zh;
      await tester.pumpAndSettle();
    }
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'progress demonstration keeps first-touch ownership when second touch cancels',
      (tester) async {
    sizePlaylistFeature(tester, width: 800, height: 500);
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(playlistFeatureHost(
        PlayerGuideDemo(kind: PlayerGuideDemoKind.progress, isHidden: hidden)));
    await tester.pumpAndSettle();
    final slider = _key('guide-demo-progress-slider');
    final bounds = tester.getRect(slider);
    final first = await tester.startGesture(
        Offset(bounds.left + bounds.width * .25, bounds.center.dy),
        pointer: 1,
        kind: raster.PointerDeviceKind.touch);
    await first.moveBy(const Offset(50, 0));
    await tester.pump();
    final value = tester.widget<Slider>(slider).value;
    final second = await tester.startGesture(
        Offset(bounds.left + bounds.width * .85, bounds.center.dy),
        pointer: 2,
        kind: raster.PointerDeviceKind.touch);
    await second.moveBy(const Offset(-40, 0));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, value);
    await second.cancel();
    await first.moveBy(const Offset(35, 0));
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, greaterThan(value));
    await first.up();
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets('common reference renders real glyphs in wide and narrow layouts',
      (tester) async {
    final boundary = GlobalKey();
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      for (final wide in [true, false]) {
        sizePlaylistFeature(tester, width: wide ? 1100 : 420, height: 950);
        await tester.pumpWidget(playlistFeatureHost(
            const PlayerFeatureGuideDialog(),
            textScale: wide ? 1 : 1.5,
            boundary: boundary));
        await tester.pumpAndSettle();
        expect(_key('guide-common-queue'), findsOneWidget);
        expect(tester.getRect(_key('guide-common-queue')).left,
            greaterThanOrEqualTo(0));
        expect(tester.getRect(_key('guide-common-queue')).right,
            lessThanOrEqualTo(wide ? 1100 : 420));
        expect(tester.takeException(), isNull);
        final output = Platform.environment['DAN_DAILY_GUIDE_RENDER_DIR'];
        if (output != null) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
            try {
              final bytes =
                  await image.toByteData(format: raster.ImageByteFormat.png);
              await Directory(output).create(recursive: true);
              await File(
                      '$output/${language.name}-${wide ? 'wide' : 'narrow'}-guide.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
}
