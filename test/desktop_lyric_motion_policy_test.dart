import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/component/lyric_line_view.dart';
import 'package:desktop_lyric/component/taskbar_lyric_row.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/desktop_lyric_test_support.dart';

class _Clock extends PlaybackClock {
  _Clock(int Function() now)
      : super(nowMilliseconds: now, automaticTicks: false);
  void visualTick() => notifyListeners();
}

Widget _host(DesktopLyricController source, Widget child,
        {bool lyrics = false, bool ticker = true}) =>
    MaterialApp(
      home: MotionPreferencesScope(
        preferences:
            const MotionPreferences().withKind(MotionKind.lyrics, lyrics),
        child: TickerMode(
          enabled: ticker,
          child: Provider<ThemeChangedMessage>.value(
            value: source.theme.value,
            child: ChangeNotifierProvider<TextDisplayController>.value(
              value: source.appearance,
              child:
                  Center(child: SizedBox(width: 520, height: 90, child: child)),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('disabled lyric motion stops long-line drift but keeps seek sync',
      (tester) async {
    var now = 0;
    final clock = _Clock(() => now);
    final source = DesktopLyricController.detached(clock: clock);
    addTearDown(source.dispose);
    source.handleMessage(LyricLineTimelineMessage(
      sequence: 1,
      lineIndex: 0,
      startMilliseconds: 0,
      lengthMilliseconds: 10000,
      content: 'A very long lyric for scrolling ' * 15,
      translation: null,
      words: const [],
    ).buildMessageJson());
    clock.sync(const PlaybackTimelineMessage(1, 0, true));
    await tester.pumpWidget(_host(source, LyricLineView(controller: source)));
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('desktop-lyric-scroll')))
        .controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(500));
    final before = scroll.offset;
    now = 1000;
    clock.visualTick();
    await tester.pump();
    expect(scroll.offset, before,
        reason: 'The player lyric toggle also owns continuous long-line drift');

    clock.sync(const PlaybackTimelineMessage(1, 5000, false));
    await tester.pump();
    expect(scroll.offset, greaterThan(before),
        reason: 'Disabling visual interpolation must not freeze a paused seek');
    expect(tester.takeException(), isNull);
  });

  for (final configuration in [(false, true), (true, false)]) {
    testWidgets(
        'taskbar word painting follows lyric/ticker policy $configuration',
        (tester) async {
      final source = DesktopLyricController.detached(
          clock: PlaybackClock(automaticTicks: false));
      addTearDown(source.dispose);
      source.handleMessage(const LyricLineTimelineMessage(
        sequence: 1,
        lineIndex: 0,
        startMilliseconds: 0,
        lengthMilliseconds: 10000,
        content: 'Word',
        translation: null,
        words: [DesktopLyricWord(0, 10000, 'Word')],
      ).buildMessageJson());
      final layout =
          DesktopLyricWindowLayout(adapter: FakeDesktopLyricWindow());
      addTearDown(layout.dispose);
      await tester.pumpWidget(_host(
        source,
        TaskbarLyricRow(
            controller: source, windowLayout: layout, sendMessage: (_) {}),
        lyrics: configuration.$1,
        ticker: configuration.$2,
      ));
      final text =
          tester.widget<DesktopLyricText>(find.byType(DesktopLyricText));
      expect(text.words, isNotEmpty);
      expect(text.reducedMotion, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
