import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/lyric_line_view.dart';
import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Fixture {
  _Fixture(WidgetTester tester) {
    clock = PlaybackClock(
        nowMilliseconds: () =>
            tester.binding.clock.now().millisecondsSinceEpoch);
    source = DesktopLyricController.detached(clock: clock);
    clock.addListener(() => samples++);
    source.handleMessage(
        const PlaybackTimelineMessage(1, 0, true).buildMessageJson());
    addTearDown(source.dispose);
    addTearDown(settings.dispose);
  }

  late final PlaybackClock clock;
  late final DesktopLyricController source;
  final settings = TextDisplayController();
  int samples = 0;

  void line(String text,
          {List<DesktopLyricWord> words = const [], int length = 5000}) =>
      source.handleMessage(LyricLineTimelineMessage(
              sequence: 1,
              lineIndex: 0,
              startMilliseconds: 0,
              lengthMilliseconds: length,
              content: text,
              translation: null,
              words: words)
          .buildMessageJson());

  Widget app({double width = 600}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 120,
              child: Provider<ThemeChangedMessage>.value(
                value: source.theme.value,
                child: ChangeNotifierProvider.value(
                  value: settings,
                  child: LyricLineView(controller: source),
                ),
              ),
            ),
          ),
        ),
      );
}

void main() {
  testWidgets('desktop consumers release only their own shared sampling demand',
      (tester) async {
    final clock = PlaybackClock(
        nowMilliseconds: () =>
            tester.binding.clock.now().millisecondsSinceEpoch);
    addTearDown(clock.dispose);
    var samples = 0;
    clock.addListener(() => samples++);
    clock.sync(const PlaybackTimelineMessage(1, 0, true));
    final first = Object(), second = Object();
    clock.setVisualSamplingDemand(first, true);
    clock.setVisualSamplingDemand(second, true);
    clock.setVisualSamplingDemand(first, false);
    samples = 0;
    await tester.pump(const Duration(milliseconds: 100));
    expect(samples, greaterThan(0));
    clock.setVisualSamplingDemand(second, false);
    samples = 0;
    final position = clock.positionMilliseconds;
    await tester.pump(const Duration(seconds: 2));
    expect(samples, 0);
    expect(clock.positionMilliseconds, position + 2000);
    clock.setVisualSamplingDemand(first, true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(samples, greaterThan(0));
    clock.setPlaying(false);
    samples = 0;
    await tester.pump(const Duration(seconds: 2));
    expect(samples, 0);
  });

  testWidgets('short ordinary desktop lyrics do not wake a visual sampler',
      (tester) async {
    final fixture = _Fixture(tester)..line('安静短句');
    await tester.pumpWidget(fixture.app());
    await tester.pump(const Duration(milliseconds: 300));
    fixture.samples = 0;
    final position = fixture.clock.positionMilliseconds;
    await tester.pump(const Duration(seconds: 2));
    expect(fixture.samples, 0,
        reason: 'A fully static visible line has no frame work to sample');
    expect(fixture.clock.positionMilliseconds, position + 2000,
        reason: 'The shared media timeline keeps advancing without repainting');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('desktop highlighting samples only until its last authored word',
      (tester) async {
    final fixture = _Fixture(tester)
      ..line('词', words: const [DesktopLyricWord(0, 1000, '词')]);
    await tester.pumpWidget(fixture.app());
    await tester.pump(const Duration(milliseconds: 100));
    fixture.samples = 0;
    await tester.pump(const Duration(milliseconds: 300));
    expect(fixture.samples, greaterThan(0));
    await tester.pump(const Duration(seconds: 1));
    fixture.samples = 0;
    await tester.pump(const Duration(seconds: 2));
    expect(fixture.samples, 0);

    fixture.source.handleMessage(
        const PlaybackTimelineMessage(1, 200, false).buildMessageJson());
    await tester.pump();
    final painter = tester
        .widget<CustomPaint>(find.byWidgetPredicate((widget) =>
            widget is CustomPaint && widget.painter is DesktopLyricTextPainter))
        .painter! as DesktopLyricTextPainter;
    expect(painter.progressForWord(0), .2);
    fixture.source.handleMessage(
        const PlaybackTimelineMessage(1, 200, true).buildMessageJson());
    fixture.samples = 0;
    await tester.pump(const Duration(milliseconds: 100));
    expect(fixture.samples, greaterThan(0),
        reason: 'An explicit backward seek restores real word sampling');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('overflow desktop lyrics sample only while their reading moves',
      (tester) async {
    final fixture = _Fixture(tester)..line('完整长歌词与译文 ' * 30);
    await tester.pumpWidget(fixture.app(width: 260));
    await tester.pump(const Duration(milliseconds: 100));
    final scroll = tester
        .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('desktop-lyric-scroll')))
        .controller!;
    final start = scroll.offset;
    fixture.samples = 0;
    await tester.pump(const Duration(milliseconds: 500));
    expect(fixture.samples, greaterThan(0));
    expect(scroll.offset, greaterThan(start));
    await tester.pump(const Duration(seconds: 5));
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, .5));
    fixture.samples = 0;
    await tester.pump(const Duration(seconds: 2));
    expect(fixture.samples, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('new timed text restores sampling after a static desktop line',
      (tester) async {
    final fixture = _Fixture(tester)..line('旧的静态歌词');
    await tester.pumpWidget(fixture.app());
    await tester.pump(const Duration(milliseconds: 300));
    fixture.samples = 0;
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.samples, 0);
    fixture
        .line('新的演唱歌词', words: const [DesktopLyricWord(1300, 5000, '新的演唱歌词')]);
    await tester.pump();
    fixture.samples = 0;
    await tester.pump(const Duration(milliseconds: 100));
    expect(fixture.samples, greaterThan(0));
    fixture.line('新的静态歌词');
    await tester.pump();
    fixture.samples = 0;
    await tester.pump(const Duration(seconds: 2));
    expect(fixture.samples, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('untimed overflow does not invent a repeating desktop clock',
      (tester) async {
    final fixture = _Fixture(tester)..line('无时间轴歌词完整保留 ' * 30, length: 0);
    await tester.pumpWidget(fixture.app(width: 260));
    await tester.pump(const Duration(milliseconds: 300));
    fixture.samples = 0;
    await tester.pump(const Duration(seconds: 2));
    expect(fixture.samples, 0);
    final scroll = tester
        .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('desktop-lyric-scroll')))
        .controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(scroll.offset, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('future zero-length desktop words retain their actual onset',
      (tester) async {
    final fixture = _Fixture(tester)
      ..line('词', words: const [DesktopLyricWord(500, 0, '词')]);
    await tester.pumpWidget(fixture.app());
    await tester.pump(const Duration(milliseconds: 100));
    fixture.samples = 0;
    await tester.pump(const Duration(milliseconds: 100));
    expect(fixture.samples, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 500));
    fixture.samples = 0;
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.samples, 0);
    final painter = tester
        .widget<CustomPaint>(find.byWidgetPredicate((widget) =>
            widget is CustomPaint && widget.painter is DesktopLyricTextPainter))
        .painter! as DesktopLyricTextPainter;
    expect(painter.progressForWord(0), 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposing the owner clock before its views cannot restart it',
      (tester) async {
    final fixture = _Fixture(tester)
      ..line('词', words: const [DesktopLyricWord(0, 5000, '词')]);
    await tester.pumpWidget(fixture.app());
    await tester.pump(const Duration(milliseconds: 100));
    fixture.source.dispose();
    fixture.samples = 0;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(fixture.samples, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'bounded desktop text samples only its currently visible authored words',
      (tester) async {
    final clock = PlaybackClock(
        nowMilliseconds: () =>
            tester.binding.clock.now().millisecondsSinceEpoch);
    addTearDown(clock.dispose);
    var samples = 0;
    clock.addListener(() => samples++);
    clock.sync(const PlaybackTimelineMessage(1, 0, true));
    var width = 50.0;
    var fontSize = 22.0;
    var vertical = false;
    Widget app() => MaterialApp(
          home: Center(
            child: DesktopLyricText(
              text: 'Visible Hidden trailing words',
              clock: clock,
              style: TextStyle(fontSize: fontSize),
              playedColor: Colors.blue,
              unplayedColor: Colors.grey,
              maxHorizontalWidth: width,
              vertical: vertical,
              words: const [
                DesktopLyricWord(0, 100, 'Visible '),
                DesktopLyricWord(10000, 10000, 'Hidden trailing words'),
              ],
            ),
          ),
        );
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 300));
    samples = 0;
    await tester.pump(const Duration(seconds: 1));
    expect(samples, 0,
        reason: 'The only pending word is wholly beyond the ellipsis');
    clock.sync(const PlaybackTimelineMessage(1, 25000, false));
    final painter = tester
        .widget<CustomPaint>(find.byWidgetPredicate((widget) =>
            widget is CustomPaint && widget.painter is DesktopLyricTextPainter))
        .painter! as DesktopLyricTextPainter;
    expect(painter.highlightRectsForWord(1), isEmpty);

    clock.sync(const PlaybackTimelineMessage(1, 1300, true));
    width = 600;
    await tester.pumpWidget(app());
    samples = 0;
    await tester.pump(const Duration(milliseconds: 100));
    expect(samples, greaterThan(0),
        reason: 'Widening restores visible pending words without a new source');

    width = 400;
    fontSize = 64;
    await tester.pumpWidget(app());
    samples = 0;
    await tester.pump(const Duration(seconds: 1));
    expect(samples, 0,
        reason: 'The larger font again makes the trailing word invisible');
    fontSize = 22;
    await tester.pumpWidget(app());
    samples = 0;
    await tester.pump(const Duration(milliseconds: 100));
    expect(samples, greaterThan(0),
        reason: 'Reducing the font restores its actual visible word extent');

    width = 50;
    vertical = true;
    await tester.pumpWidget(app());
    samples = 0;
    await tester.pump(const Duration(milliseconds: 100));
    expect(samples, greaterThan(0),
        reason: 'Vertical mode retains the pending word in its own row');
    vertical = false;
    await tester.pumpWidget(app());
    samples = 0;
    await tester.pump(const Duration(seconds: 1));
    expect(samples, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
