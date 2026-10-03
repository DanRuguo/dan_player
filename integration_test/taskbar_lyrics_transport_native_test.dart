import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

const _channel = MethodChannel('dan_player/desktop_integration');
const _nativeCase = String.fromEnvironment('DAN_TASKBAR_NATIVE_CASE');

Map<String, Object> _frame({
  String text = '',
  String next = '',
  List<Map<String, Object>> words = const [],
  String source = 'native-fixture',
  String line = '0',
  int position = 0,
  int revision = 0,
  bool playing = false,
  bool animate = true,
}) =>
    {
      'enabled': true,
      'text': text,
      'nextText': next,
      'words': words,
      'accent': 0xffdcba6b,
      'fontFamily': 'DanPingFangSC',
      'fontPath': const String.fromEnvironment('DAN_TASKBAR_NATIVE_FONT'),
      'animate': animate,
      'playing': playing,
      'sourceIdentity': source,
      'lineIdentity': '$source:$line',
      'positionMilliseconds': position,
      'playbackRate': 1.0,
      'lineStartMilliseconds': 0,
      'lineEndMilliseconds': 10000,
      'timelineRevision': revision,
    };

Future<void> _send(Map<String, Object> frame) =>
    _channel.invokeMethod<void>('setTaskbarLyrics', frame);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await windowManager.ensureInitialized();
    await windowManager.hide();
  });
  tearDownAll(() async {
    await _send({'enabled': false});
  });

  // This exercises the real Flutter codec/native channel, rather than the
  // publisher's fake transport. It owns only this test process's lyric surface;
  // no music, playback service, system setting or Explorer parent is changed.
  if (_nativeCase.isEmpty || _nativeCase == 'transport') {
    testWidgets(
        'taskbar native codec accepts lifecycle and bounded lyric frames', (
      tester,
    ) async {
      expect(Platform.isWindows, isTrue);
      expect(
        File(const String.fromEnvironment('DAN_TASKBAR_NATIVE_FONT'))
            .existsSync(),
        isTrue,
      );
      await _send(_frame()); // Complete empty capability handshake.
      await _send(
          {'enabled': false, 'text': ''}); // Minimal publisher shutdown.

      const samples = [
        ['歌词', '首尾完整'],
        ['Current ', 'and next line'],
        ['日本語の', '歌詞'],
        ['한국어 ', '가사'],
        ['A😀', 'e\u0301B'],
      ];
      for (var sample = 0; sample < samples.length; sample++) {
        final parts = samples[sample];
        final text = parts.join();
        final words = <Map<String, Object>>[
          {
            'startMilliseconds': -100,
            'lengthMilliseconds': 0,
            'content': parts[0]
          },
          {
            'startMilliseconds': 100,
            'lengthMilliseconds': 900,
            'content': parts[1],
          },
        ];
        await _send(
          _frame(
            text: text,
            next: 'Next · 下一句 · 次の行 · 다음 줄',
            words: words,
            source: 'sample-$sample',
            playing: true,
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));
        await _send(
          _frame(
            text: text,
            next: 'Next · 下一句 · 次の行 · 다음 줄',
            words: words,
            source: 'sample-$sample',
            position: 400,
            playing: true,
          ),
        );
        // A paused seek and reduced animation frame remain valid native inputs.
        await _send(
          _frame(
            text: text,
            words: words,
            source: 'sample-$sample',
            position: 100,
            revision: 1,
            animate: false,
          ),
        );
        await _send({'enabled': false});
      }

      // Legal documents may exceed a small transport text cap. Preserve the full
      // primary text up to the existing 2 MiB input bound, without guessed words.
      for (final text in ['歌' * 6000, 'W' * (2 * 1024 * 1024)]) {
        await _send(_frame(text: text, animate: false));
        await tester.pump(const Duration(milliseconds: 120));
        await _send(_frame(text: text, position: 9999, animate: false));
        await tester.pump(const Duration(milliseconds: 80));
        await _send({'enabled': false});
      }

      await expectLater(
        _send(_frame(text: 'W' * (2 * 1024 * 1024 + 1))),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'INVALID_ARGUMENT',
          ),
        ),
      );
      await _send({'enabled': false});
    });
  }

  if (_nativeCase.isEmpty || _nativeCase == 'adaptation') {
    testWidgets('taskbar native layout and appearance accept adaptive frames',
        (tester) async {
      expect(Platform.isWindows, isTrue);
      final events = <Map<Object?, Object?>>[];
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'taskbarLyricsLayoutChanged' &&
            call.arguments is Map) {
          events.add(Map<Object?, Object?>.from(call.arguments as Map));
        }
      });
      addTearDown(() => _channel.setMethodCallHandler(null));
      await _send({'enabled': false});
      final cold = await _channel
          .invokeMapMethod<String, Object?>('getTaskbarLyricsLayout');
      expect(cold, isNotNull);
      expect(cold!['vertical'], isA<bool>());
      expect(cold['areaCount'], 0);

      Map<String, Object> styled(String placement, int areaSelection) => {
            ..._frame(
              text: '歌词 · 字形描边 · A😀e\u0301 · 日本語 · 한국어',
              next: '下一句预览 · Next lyric line',
              source: 'adaptive-codec',
              position: 500,
              animate: false,
            ),
            'placement': placement,
            'areaSelection': areaSelection,
            'nextTrackText': '下一首：下一曲 · Next song · 次の曲 · 다음 곡',
            'showPauseIndicator': true,
            'paused': true,
            'strokeEnabled': true,
          };

      for (final placement in ['auto', 'start', 'center', 'end']) {
        for (var area = 0; area < 3; area++) {
          await _send(styled(placement, area));
          await tester.pump(const Duration(milliseconds: 100));
          final layout = await _channel
              .invokeMapMethod<String, Object?>('getTaskbarLyricsLayout');
          expect(layout!['vertical'], isA<bool>());
          final count = layout['areaCount'] as int;
          expect(count, greaterThanOrEqualTo(0));
          if (count > 0) {
            expect(layout['areaIndex'], inInclusiveRange(0, count - 1));
          }
        }
      }
      await _send({
        ...styled('auto', 0),
        'playing': true,
        'paused': false,
        'showPauseIndicator': false,
        'strokeEnabled': false,
        'nextTrackText': '',
      });
      for (final invalid in <Map<String, Object>>[
        {'placement': 'unknown'},
        {'areaSelection': -1},
        {'areaSelection': 65536},
        {'showPauseIndicator': 'true'},
        {'paused': 'true'},
        {'strokeEnabled': 'true'},
        {'nextTrackText': 'W' * (2 * 1024 * 1024 + 1)},
      ]) {
        await expectLater(
          _send({...styled('auto', 0), ...invalid}),
          throwsA(isA<PlatformException>()
              .having((error) => error.code, 'code', 'INVALID_ARGUMENT')),
        );
      }
      for (final event in events) {
        expect(event['vertical'], isA<bool>());
        expect(event['areaCount'], isA<int>());
        expect(event['areaIndex'], isA<int>());
      }
      await _send({'enabled': false});
      final closed = await _channel
          .invokeMapMethod<String, Object?>('getTaskbarLyricsLayout');
      expect(closed!['areaCount'], 0);
    });
  }

  if (_nativeCase.isEmpty || _nativeCase == 'interaction') {
    testWidgets(
        'taskbar native color and optional controls accept bounded frames',
        (tester) async {
      expect(Platform.isWindows, isTrue);
      Map<String, Object> controls({
        String colorScheme = 'player',
        bool showButton = false,
        bool buttonEnabled = false,
        bool stroke = false,
        bool animateLayout = true,
        bool showNextLyric = true,
      }) =>
          {
            ..._frame(
              text: '独立描边 · 正规图标 · Optional controls',
              next: '下一句 · Next line · 次の行 · 다음 줄',
              source: 'interactive-codec',
              position: 500,
              animate: false,
            ),
            'colorScheme': colorScheme,
            'showNextButton': showButton,
            'nextButtonEnabled': buttonEnabled,
            'animateLayout': animateLayout,
            'showNextLyric': showNextLyric,
            'strokeEnabled': stroke,
            'showPauseIndicator': true,
            'paused': true,
            'nextTrackText': '下一首：歌曲名 · Track · 曲名 · 곡명',
          };

      // Keep the existing minimal close/default protocol compatible. The new
      // interactive fields are optional and default to a passive surface.
      await _send({'enabled': false});
      await _send(_frame(text: 'Legacy passive frame', animate: false));
      for (final color in ['player', 'system']) {
        for (final stroke in [false, true]) {
          await _send(controls(colorScheme: color, stroke: stroke));
          await tester.pump(const Duration(milliseconds: 80));
          await _send(
              controls(colorScheme: color, showButton: true, stroke: stroke));
          await tester.pump(const Duration(milliseconds: 80));
          await _send(controls(
              colorScheme: color,
              showButton: true,
              buttonEnabled: true,
              stroke: stroke));
          await tester.pump(const Duration(milliseconds: 80));
        }
      }
      for (final invalid in <Map<String, Object>>[
        {'colorScheme': 'unknown'},
        {'colorScheme': true},
        {'showNextButton': 'true'},
        {'nextButtonEnabled': 1},
        {'animateLayout': 'true'},
        {'showNextLyric': 1},
      ]) {
        await expectLater(
          _send({...controls(), ...invalid}),
          throwsA(isA<PlatformException>()
              .having((error) => error.code, 'code', 'INVALID_ARGUMENT')),
        );
      }
      // Layout motion has its own gate: it can run on paused lyrics with lyric
      // motion off, and disabling it immediately accepts the final placement.
      await _send({...controls(), 'placement': 'start'});
      await tester.pump(const Duration(milliseconds: 80));
      await _send({...controls(), 'placement': 'end'});
      await tester.pump(const Duration(milliseconds: 80));
      await _send(controls(showNextLyric: false));
      await tester.pump(const Duration(milliseconds: 80));
      await _send(controls());
      await tester.pump(const Duration(milliseconds: 80));
      await _send({
        ...controls(animateLayout: false, showNextLyric: false),
        'placement': 'center',
      });
      await _send(controls()); // Disabling controls retains lyric ownership.
      await _send({'enabled': false});
      final closed = await _channel
          .invokeMapMethod<String, Object?>('getTaskbarLyricsLayout');
      expect(closed!['areaCount'], 0);
    });
  }

  if (_nativeCase.isEmpty || _nativeCase == 'shell') {
    testWidgets(
        'taskbar native playback control preserves passive compatibility',
        (tester) async {
      expect(Platform.isWindows, isTrue);
      Map<String, Object> playback(bool playing, bool paused) => {
            ..._frame(
              text: '播放 / 暂停 · Play / Pause · 再生 · 재생',
              next: '下一句 · Next line',
              source: 'shell-codec',
              playing: playing,
              position: 2500,
            ),
            'paused': paused,
            'showPauseIndicator': true,
            'playbackButtonEnabled': true,
            'showNextButton': true,
            'nextButtonEnabled': true,
            'showNextLyric': false,
            'animateLayout': true,
          };

      await _send({'enabled': false});
      // Older frames omit the new field and must remain passive, including
      // the empty capability handshake used before a playback source exists.
      await _send(_frame());
      await _send(_frame(text: 'Legacy paused surface', animate: false));
      for (final states in [(true, false), (false, true), (false, false)]) {
        await _send(playback(states.$1, states.$2));
        await tester.pump(const Duration(milliseconds: 100));
        await _send({
          ...playback(states.$1, states.$2),
          'playbackButtonEnabled': false,
        });
      }
      for (final invalid in <Object>['true', 1]) {
        await expectLater(
          _send({...playback(false, true), 'playbackButtonEnabled': invalid}),
          throwsA(isA<PlatformException>()
              .having((error) => error.code, 'code', 'INVALID_ARGUMENT')),
        );
      }

      // A long next-song label must not turn the current authored-word viewport
      // into an unrelated marquee. Native pixel tests cover its actual offset;
      // this case checks those combined fields through the main Flutter codec.
      final parts = ['逐字歌词保留演唱位置' * 8, '最后一个字😀'];
      for (final position in [200, 9000]) {
        await _send({
          ...playback(false, true),
          'text': parts.join(),
          'nextTrackText': '下一首歌曲信息 · Next song ' * 12,
          'words': <Map<String, Object>>[
            {
              'startMilliseconds': 0,
              'lengthMilliseconds': 8000,
              'content': parts[0],
            },
            {
              'startMilliseconds': 8000,
              'lengthMilliseconds': 2000,
              'content': parts[1],
            },
          ],
          'positionMilliseconds': position,
        });
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _send({'enabled': false});
      final closed = await _channel
          .invokeMapMethod<String, Object?>('getTaskbarLyricsLayout');
      expect(closed!['areaCount'], 0);
    });
  }
}
