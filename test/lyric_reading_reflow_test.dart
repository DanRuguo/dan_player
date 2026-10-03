import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/lyric/lyric_text_search.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;

import 'support/playlist_feature_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final output = Platform.environment['DAN_PLAYLIST_FEATURE_RENDER_DIR'];
    if (output != null &&
        !path.isWithin(
            path.join(Directory.current.parent.path, 'tool', 'qa-local'),
            output)) {
      throw StateError('Render output must stay in workspace QA');
    }
    await loadPlaylistFeatureFonts();
  });

  for (final change in ['width', 'font']) {
    for (final animations in [false, true]) {
      testWidgets(
          'found plain-text glyph remains readable after $change reflow animations=$animations',
          (tester) async {
        sizePlaylistFeature(tester, width: 800, height: 700);
        final document = PlainLyric('${'雨に歌う reading 밤의 노래 ' * 160}Needle 终点');
        final targetOffset = document.text.indexOf('Needle');
        final settings = LyricViewController(
            preferences: NowPlayingPagePreference.fromMap({}));
        final width = ValueNotifier(700.0);
        addTearDown(width.dispose);
        addTearDown(settings.dispose);
        var seeks = 0;
        await tester.pumpWidget(playlistFeatureHost(
            ChangeNotifierProvider.value(
                value: settings,
                child: Center(
                    child: ValueListenableBuilder(
                        valueListenable: width,
                        builder: (_, value, __) => SizedBox(
                            width: value,
                            height: 600,
                            child: Builder(
                                builder: (context) => MediaQuery(
                                    data: MediaQuery.of(context).copyWith(
                                        disableAnimations: !animations),
                                    child: VerticalLyricScrollView(
                                        lyric: document,
                                        positionStream:
                                            const Stream<double>.empty(),
                                        readPosition: () => 0,
                                        onSeek: (_) => seeks++,
                                        playing: false,
                                        springLyrics: false)))))))));
        await tester.pumpAndSettle();
        settings.revealForReading(LyricReadingTarget(
            document, 0, document.lines.single,
            textOffset: targetOffset));
        await tester.pumpAndSettle();
        double glyphY() {
          final element = tester.element(find.byWidgetPredicate((widget) =>
              widget is BalancedLyricText && widget.text == document.text));
          return ((element as StatefulElement).state
                  as LyricTextReadingGeometry)
              .readingGlobalY(targetOffset)!;
        }

        final viewport =
            tester.getRect(find.byKey(const ValueKey('vertical-lyric-scroll')));
        final beforeY = glyphY();
        expect(beforeY, inInclusiveRange(viewport.top, viewport.bottom));
        if (change == 'width') {
          width.value = 360;
        } else {
          settings.setPresetFontSize(42);
        }
        await tester.pump();
        expect(glyphY(), closeTo(beforeY, 1),
            reason: 'The first changed frame must already preserve the glyph');
        for (var i = 0; i < 32; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(glyphY(), closeTo(beforeY, 1),
              reason: 'Motion frame $i keeps the reading glyph');
        }
        await tester.pumpAndSettle();
        expect(glyphY(), closeTo(beforeY, 1),
            reason: 'Reflow must preserve the found text rather than the old '
                'numerical scroll offset');
        expect(settings.readingMode, isTrue);
        expect(settings.readingTarget!.textOffset, targetOffset);
        expect(seeks, 0);
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }

  testWidgets('wheel reading supersedes a found target across hidden return',
      (tester) async {
    sizePlaylistFeature(tester, width: 800, height: 700);
    final document = PlainLyric('${'雨に歌う reading 밤의 노래 ' * 160}Needle 终点');
    final settings =
        LyricViewController(preferences: NowPlayingPagePreference.fromMap({}));
    final hidden = ValueNotifier(false);
    final boundary = GlobalKey();
    addTearDown(settings.dispose);
    addTearDown(hidden.dispose);
    var seeks = 0;
    await tester.pumpWidget(playlistFeatureHost(
        ChangeNotifierProvider.value(
            value: settings,
            child: Center(
                child: SizedBox(
                    width: 700,
                    height: 600,
                    child: Builder(
                        builder: (context) => MediaQuery(
                            data: MediaQuery.of(context)
                                .copyWith(disableAnimations: false),
                            child: Column(children: [
                              const Align(
                                  alignment: Alignment.centerRight,
                                  child: LyricFontSizeMenu()),
                              Expanded(
                                  child: VerticalLyricScrollView(
                                      lyric: document,
                                      positionStream:
                                          const Stream<double>.empty(),
                                      readPosition: () => 0,
                                      onSeek: (_) => seeks++,
                                      hidden: hidden,
                                      playing: false,
                                      springLyrics: false)),
                            ])))))),
        boundary: boundary));
    await tester.pumpAndSettle();
    settings.revealForReading(LyricReadingTarget(
        document, 0, document.lines.single,
        textOffset: document.text.indexOf('Needle')));
    await tester.pumpAndSettle();
    double glyphY([int? offset]) {
      final element = tester.element(find.byWidgetPredicate(
          (widget) =>
              widget is BalancedLyricText && widget.text == document.text,
          skipOffstage: false));
      return ((element as StatefulElement).state as LyricTextReadingGeometry)
          .readingGlobalY(offset ?? document.text.indexOf('Needle'))!;
    }

    final beforeY = glyphY();
    await capturePlaylistFeature(tester, boundary, 'find-before');
    settings.setPresetFontSize(32);
    await tester.pumpAndSettle();
    expect(glyphY(), closeTo(beforeY, 1));
    await capturePlaylistFeature(tester, boundary, 'find-reflow');
    final viewport = find.byKey(const ValueKey('vertical-lyric-scroll'));
    final scroll = tester.widget<CustomScrollView>(viewport).controller!;
    final foundOffset = scroll.offset;
    await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(viewport),
        scrollDelta: const Offset(0, -600)));
    await tester.pumpAndSettle();
    final heldOffset = scroll.offset;
    expect(heldOffset, lessThan(foundOffset - 500),
        reason: 'The real wheel event must move the reading viewport');
    hidden.value = true;
    await tester.pump();
    hidden.value = false;
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(heldOffset, 1),
        reason: 'Returning from hidden must not resurrect an old find target');
    expect(settings.readingMode, isTrue);
    final viewportRect = tester.getRect(viewport);
    final visibleOffset = [
      for (var offset = 0; offset < document.text.length; offset += 40) offset
    ].firstWhere((offset) =>
        glyphY(offset) >= viewportRect.top + 100 &&
        glyphY(offset) <= viewportRect.bottom - 100);
    final startY = glyphY(visibleOffset);
    await tester.tap(find.byKey(const ValueKey('lyric-font-size-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lyric-font-size-preset-48')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(settings.lyricFontSize, 48);
    final movingY = glyphY(visibleOffset);
    expect((movingY - startY).abs(), greaterThan(1),
        reason: 'The real shaped glyph must move during the normal A± effect');
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await capturePlaylistFeature(tester, boundary, 'manual-font-during');
    await tester.tap(find.byKey(const ValueKey('lyric-font-size-open')));
    await tester.pumpAndSettle();
    final endY = glyphY(visibleOffset);
    expect((endY - movingY).abs(), greaterThan(1),
        reason: 'The intermediate glyph pose must differ from its final pose');
    expect(
        movingY,
        inInclusiveRange(
            startY < endY ? startY : endY, startY < endY ? endY : startY));
    await capturePlaylistFeature(tester, boundary, 'manual-font-after');
    expect(seeks, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
