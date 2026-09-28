import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _CostLyric extends Lyric {
  _CostLyric(super.lines);
}

Map<String, double> _percentiles(List<double> samples) {
  samples.sort();
  return {
    'p50Us': samples[(samples.length * .50).ceil() - 1],
    'p95Us': samples[(samples.length * .95).ceil() - 1],
    'p99Us': samples[(samples.length * .99).ceil() - 1],
    'maxUs': samples.last,
  };
}

Map<String, double> _measure(void Function() operation,
    {int batch = 8, int count = 800}) {
  for (var i = 0; i < 400; i++) {
    operation();
  }
  final samples = <double>[];
  final clock = Stopwatch();
  for (var i = 0; i < count; i++) {
    clock.reset();
    clock.start();
    for (var j = 0; j < batch; j++) {
      operation();
    }
    clock.stop();
    samples.add(clock.elapsedMicroseconds / batch);
  }
  return _percentiles(samples);
}

void main() {
  final output = Platform.environment['DAN_RECENT_COST_OUTPUT'];
  testWidgets('recent features CPU cost with bounded observed histories',
      (tester) async {
    final results = <String, Object>{};
    final audio = Audio.online(
        provider: 'netease',
        id: 'cost-fixture',
        title: 'Synthetic cost fixture',
        artist: 'Artist',
        album: 'Album',
        duration: 7200);
    for (final size in [0, 1000, 19990]) {
      var now = DateTime.utc(2026, 9, 27, 12);
      final end = now.millisecondsSinceEpoch;
      final begin = end - const Duration(hours: 24).inMilliseconds;
      final stats = PlaybackStatistics.inMemory(clock: () => now, initialData: {
        'version': 4,
        'recentTrackingStartedAt': begin,
        'recentPlayStarts': [for (var i = 0; i < size; i++) begin + i * 2000],
        'recentListeningIntervals': [
          for (var i = 0; i < size; i++)
            [begin + i * 2000, begin + i * 2000 + 1000],
        ],
      });
      stats.start(audio);
      results['statisticsTick-$size'] = _measure(() {
        now = now.add(const Duration(milliseconds: 100));
        stats.tick(audio, PlayerState.playing);
      });
      expect(stats.totalListenMilliseconds, 680000);
      expect(stats.recentListeningIntervals.length, size + 1);
      stats.dispose();
    }
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    Future<void> measureLyricRows(int rowCount, int cycles,
        {bool reducedMotion = false}) async {
      final settings = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap(const {
          'lyricFontSize': 22,
          'translationFontSize': 18,
          'showLyricTimestamps': false,
          'showLyricTranslation': true,
        }),
      );
      final position = ValueNotifier(Duration.zero);
      addTearDown(() {
        settings.dispose();
        position.dispose();
      });
      // A non-virtualizing column deliberately keeps every lyric row mounted,
      // matching the expensive boundary of a long full-column lyric view.
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: danEmbeddedFontFamily),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: ChangeNotifierProvider.value(
                value: settings,
                child: Column(children: [
                  for (var index = 0; index < rowCount; index++)
                    LyricViewTile(
                      line: LrcLine(
                        Duration(seconds: index * 5),
                        '音もない世界、何を見てるの? $index┃In a silent world, what do you see?',
                        isBlank: false,
                      ),
                      position: position,
                      opacity: 1,
                      distance: index,
                      reducedMotion: reducedMotion,
                    ),
                ]),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      final frameTimes = <double>[];
      final firstFrames = <double>[];
      final clock = Stopwatch();
      for (var cycle = 0; cycle < cycles; cycle++) {
        if (cycle.isEven) {
          settings.increaseFontSize();
        } else {
          settings.decreaseFontSize();
        }
        clock
          ..reset()
          ..start();
        await tester.pump();
        clock.stop();
        firstFrames.add(clock.elapsedMicroseconds.toDouble());
        if (reducedMotion) {
          await tester.pumpAndSettle();
          expect(tester.binding.transientCallbackCount, 0);
          continue;
        }
        for (var frame = 0; frame < 28; frame++) {
          clock
            ..reset()
            ..start();
          await tester.pump(const Duration(milliseconds: 16));
          clock.stop();
          frameTimes.add(clock.elapsedMicroseconds.toDouble());
        }
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      }
      if (reducedMotion) {
        results['lyricImmediateRelayoutRows-$rowCount'] = firstFrames.single;
      } else {
        results['lyricFontMorphRows-$rowCount'] = _percentiles(frameTimes);
        results['lyricFontMorphMiddleRows-$rowCount'] =
            _percentiles(frameTimes.skip(1).take(19).toList());
        results['lyricFontMorphFirstRows-$rowCount'] = firstFrames;
        results['lyricFontMorphSamples-$rowCount'] = frameTimes.length;
      }
      results['lyricIdleCallbacks-${reducedMotion ? 'immediate-' : ''}$rowCount'] =
          tester.binding.transientCallbackCount;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    }

    Future<void> measureProductionRows(int rowCount,
        {bool reducedMotion = false}) async {
      final settings = LyricViewController(
        preferences: NowPlayingPagePreference.fromMap(const {
          'lyricFontSize': 22,
          'translationFontSize': 18,
          'showLyricTimestamps': false,
          'showLyricTranslation': true,
        }),
      );
      final positions = StreamController<double>.broadcast();
      addTearDown(() async {
        settings.dispose();
        await positions.close();
      });
      final lyric = _CostLyric([
        for (var index = 0; index < rowCount; index++)
          LrcLine(
            Duration(seconds: index * 5),
            '音もない世界、何を見てるの? $index┃In a silent world, what do you see?',
            isBlank: false,
            length: const Duration(seconds: 5),
          ),
      ]);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: danEmbeddedFontFamily),
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 480,
              height: 500,
              child: ChangeNotifierProvider.value(
                value: settings,
                child: VerticalLyricScrollView(
                  lyric: lyric,
                  positionStream: positions.stream,
                  readPosition: () => 100,
                  onSeek: (_) {},
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      settings.increaseFontSize();
      final clock = Stopwatch()..start();
      await tester.pump();
      clock.stop();
      final firstUs = clock.elapsedMicroseconds.toDouble();
      if (reducedMotion) {
        results['lyricProductionImmediateRows-$rowCount'] = firstUs;
      } else {
        final samples = <double>[];
        for (var frame = 0; frame < 28; frame++) {
          clock
            ..reset()
            ..start();
          await tester.pump(const Duration(milliseconds: 16));
          clock.stop();
          samples.add(clock.elapsedMicroseconds.toDouble());
        }
        results['lyricProductionMorphRows-$rowCount'] = _percentiles(samples);
        results['lyricProductionMorphMiddleRows-$rowCount'] =
            _percentiles(samples.skip(1).take(19).toList());
        results['lyricProductionMorphFirstRows-$rowCount'] = firstUs;
      }
      await tester.pumpAndSettle();
      results['lyricProductionIdleCallbacks-${reducedMotion ? 'immediate-' : ''}$rowCount'] =
          tester.binding.transientCallbackCount;
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    // Sample the actual viewport before the deliberately unbounded direct
    // column: its 300 dual-endpoint layers stress the software raster cache
    // and would otherwise contaminate the production CPU measurements.
    await measureProductionRows(100);
    await measureProductionRows(300);
    await measureProductionRows(100, reducedMotion: true);
    await measureProductionRows(300, reducedMotion: true);
    await measureLyricRows(4, 4);
    await measureLyricRows(100, 1);
    await measureLyricRows(300, 1);
    await measureLyricRows(100, 1, reducedMotion: true);
    await measureLyricRows(300, 1, reducedMotion: true);
    results['measurement'] =
        'Flutter test CPU timings per statistics tick and forced lyric transition pump; not Windows GPU frame times';
    debugPrint(jsonEncode(results));
    await tester
        .runAsync(() => File(output!).writeAsString(jsonEncode(results)));
  }, skip: output == null);
}
