import 'package:dan_player/component/now_playing_bar_controls.dart';
import 'package:dan_player/component/now_playing_bar_metrics.dart';
import 'package:dan_player/component/now_playing_bar_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [280.0, 360.0, 520.0, 640.0]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('home bar stays bounded at $width px and ${scale}x text',
          (tester) async {
        var taps = 0;
        Future<void> render(Brightness brightness) =>
            tester.pumpWidget(MaterialApp(
              theme: ThemeData(
                  colorScheme: ColorScheme.fromSeed(
                      seedColor: Colors.teal, brightness: brightness)),
              home: Scaffold(
                  body: MediaQuery(
                data: const MediaQueryData(size: Size(1500, 900))
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: Builder(
                    builder: (context) => Center(
                            child: SizedBox(
                          key: const ValueKey('bar-bounds'),
                          width: width,
                          height: NowPlayingBarMetrics.height(context),
                          child: NowPlayingBarRow(
                            leading: const SizedBox.square(
                                dimension: 52,
                                child: ColoredBox(color: Colors.blue)),
                            title:
                                '長い曲名・EnglishSupercalifragilisticexpialidocious 👩🏽‍💻 한국어 {0}',
                            subtitle: '作曲家／Artist · 긴앨범명 · Album & “special”',
                            identity: 'track',
                            spectrum: const SizedBox(width: 50, height: 12),
                            controlsBuilder: (showQueue) =>
                                NowPlayingBarControls(
                              isPlaying: false,
                              showQueue: showQueue,
                              onPrevious: () => taps++,
                              onNext: () => taps++,
                              onPlayPause: () => taps++,
                              onQueue: () => taps++,
                            ),
                          ),
                        ))),
              )),
            ));
        for (final brightness in Brightness.values) {
          await render(brightness);
          await tester.pumpAndSettle();
          final bounds =
              tester.getRect(find.byKey(const ValueKey('bar-bounds')));
          for (final key in ['bar-previous', 'bar-play-pause', 'bar-next']) {
            final control = find.byKey(ValueKey(key));
            final rect = tester.getRect(control);
            expect(rect.width, 44);
            expect(rect.height, 44);
            expect(rect.center.dy, bounds.center.dy,
                reason: 'no reserved strip below the existing progress fill');
            expect(bounds.contains(rect.topLeft), isTrue);
            expect(bounds.contains(rect.bottomRight), isTrue);
            await tester.tap(control);
          }
          expect(find.byKey(const ValueKey('bar-queue')),
              width >= 540 ? findsOneWidget : findsNothing,
              reason: 'use the bar allocation, never the full desktop width');
          expect(tester.takeException(), isNull);
        }
        expect(taps, 6);
      });
    }
  }
}
