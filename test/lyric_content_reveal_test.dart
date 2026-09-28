import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Word extends SyncLyricWord {
  _Word() : super(Duration.zero, const Duration(seconds: 4), 'Moonlight');
}

class _Line extends SyncLyricLine {
  _Line()
      : super(Duration.zero, const Duration(seconds: 4), [_Word()],
            'Translation below the current lyric') {
    romanization = 'yuè guāng';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
  });

  for (final reduced in [false, true]) {
    testWidgets('optional lyric tracks reveal with next text, reduced=$reduced',
        (tester) async {
      final preferences = NowPlayingPagePreference.fromMap({
        'showLyricTimestamps': false,
        'showLyricTranslation': false,
        'showLyricRomanization': false,
      });
      final settings = LyricViewController(preferences: preferences)
        ..setShowTimestamps(false)
        ..setShowTranslation(false)
        ..setShowRomanization(false);
      final position = ValueNotifier(Duration.zero);
      final line = _Line();
      addTearDown(() {
        settings.dispose();
        position.dispose();
      });
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: danEmbeddedFontFamily),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 420,
              child: ChangeNotifierProvider.value(
                value: settings,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      key: const ValueKey('current-row'),
                      width: double.infinity,
                      child: LyricViewTile(
                        line: line,
                        position: position,
                        opacity: 1,
                        distance: 0,
                        reducedMotion: reduced,
                        onTap: () {},
                      ),
                    ),
                    SizedBox(
                      key: const ValueKey('next-row'),
                      width: double.infinity,
                      child: LyricViewTile(
                        line: LrcLine(const Duration(seconds: 4),
                            'The next line remains visible',
                            isBlank: false),
                        position: position,
                        opacity: 1,
                        distance: 1,
                        reducedMotion: reduced,
                        onTap: () {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final current = find.byKey(const ValueKey('current-row'));
      final next = find.byKey(const ValueKey('next-row'));
      LyricWordHighlightPainter painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<LyricWordHighlightPainter>()
          .single;
      final glyphLayout = painter().layoutIdentity;
      double height() => tester.getSize(current).height;
      double nextTop() => tester.getTopLeft(next).dy;

      Future<void> exercise(VoidCallback show, VoidCallback hide) async {
        final beforeHeight = height();
        final beforeNext = nextTop();
        show();
        await tester.pump();
        if (reduced) {
          expect(height(), greaterThan(beforeHeight + 4));
          expect(tester.binding.transientCallbackCount, 0);
        } else {
          expect(height(), closeTo(beforeHeight, .01));
          await tester.pump(const Duration(milliseconds: 160));
          final midwayHeight = height();
          expect(midwayHeight, greaterThan(beforeHeight));
          expect(nextTop(), greaterThan(beforeNext));
          expect(painter().layoutIdentity, same(glyphLayout));
          hide();
          await tester.pump();
          expect(height(), closeTo(midwayHeight, .01),
              reason: 'Retargeting mid-reveal must start at the painted size');
          await tester.pumpAndSettle();
          expect(height(), closeTo(beforeHeight, .01));
          expect(nextTop(), closeTo(beforeNext, .01));
          return;
        }
        expect(painter().layoutIdentity, same(glyphLayout));
        hide();
        await tester.pump();
        expect(height(), closeTo(beforeHeight, .01));
      }

      await exercise(() => settings.setShowTimestamps(true),
          () => settings.setShowTimestamps(false));
      await exercise(() => settings.setShowRomanization(true),
          () => settings.setShowRomanization(false));
      await exercise(() => settings.setShowTranslation(true),
          () => settings.setShowTranslation(false));
      expect(tester.takeException(), isNull);
    });
  }
}
