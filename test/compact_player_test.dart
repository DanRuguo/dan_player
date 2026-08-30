import 'package:dan_player/component/compact_player.dart';
import 'package:dan_player/component/window_chrome_theme.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/window_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _show(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(520, 300),
  double textScale = 1,
  double devicePixelRatio = 1,
  bool reduced = true,
  bool highContrast = false,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.physicalSize =
      Size(size.width * devicePixelRatio, size.height * devicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      colorSchemeSeed: Colors.blue,
      brightness: brightness,
      platform: TargetPlatform.windows,
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduced,
        highContrast: highContrast,
      ),
      child: child!,
    ),
    home: Scaffold(body: child),
  ));
  await tester.pump();
}

Finder _key(String value) => find.byKey(ValueKey(value));

void _expectHeaderOrder(WidgetTester tester) {
  expect(_key('compact-shortcuts'), findsNothing);
  expect(find.byIcon(Icons.keyboard_outlined), findsNothing);
  final buttons = [
    tester.getRect(_key('compact-restore')),
    tester.getRect(_key('compact-pin')),
    tester.getRect(_key('compact-minimize')),
    tester.getRect(_key('compact-close')),
  ];
  for (final button in buttons) {
    expect(button.size, const Size.square(44));
  }
  for (var index = 1; index < buttons.length; index++) {
    expect(buttons[index - 1].right, buttons[index].left);
    expect(buttons[index - 1].center.dy, buttons[index].center.dy);
  }
}

class _Lyric extends Lyric {
  _Lyric(super.lines);
}

class _Line extends UnsyncLyricLine {
  _Line(int seconds, String text) : super(Duration(seconds: seconds), text);
}

void main() {
  for (final width in [440.0, 520.0]) {
    // The smaller values are transient/legacy viewport sizes. Even there the
    // fixed controls stay accessible while the new content can be scrolled.
    for (final height in [192.0, 200.0, 280.0, 300.0]) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        testWidgets(
            'compact $width x $height $brightness fits 200% text and 44px controls',
            (tester) async {
          await _show(
            tester,
            CompactPlayerView(
              title: '很长的歌曲标题 · 日本語 · 한국어 · العربية · A long title',
              artist: '多语言歌手 / Künstler / Мир / 아티스트',
              position: 65,
              duration: 360,
              onRestore: () {},
              onTogglePinned: () {},
              onMinimize: () {},
              onClose: () {},
              onPrevious: () {},
              onPlayPause: () {},
              onNext: () {},
              onSeek: (_) {},
            ),
            size: Size(width, height),
            textScale: 2,
            brightness: brightness,
          );
          expect(tester.takeException(), isNull);
          _expectHeaderOrder(tester);
          for (final name in [
            'compact-restore',
            'compact-pin',
            'compact-minimize',
            'compact-close',
            'compact-previous',
            'compact-play-pause',
            'compact-next',
          ]) {
            final size = tester.getSize(_key(name));
            expect(size.width, greaterThanOrEqualTo(44), reason: name);
            expect(size.height, greaterThanOrEqualTo(44), reason: name);
          }
          expect(tester.getSize(_key('compact-progress-slider')).height,
              greaterThanOrEqualTo(44));
          expect(find.text('01:05'), findsOneWidget);
          expect(find.text('06:00'), findsOneWidget);
          final text = tester.widget<Text>(find.textContaining('很长的歌曲标题'));
          expect(text.maxLines, 1);
          expect(text.overflow, TextOverflow.ellipsis);
          expect(find.byTooltip(text.data!), findsOneWidget);
        });
      }
    }
  }

  testWidgets('all playback and window controls dispatch only their callbacks',
      (tester) async {
    final calls = <String>[];
    await _show(
        tester,
        CompactPlayerView(
          onPrevious: () => calls.add('previous'),
          onPlayPause: () => calls.add('play'),
          onNext: () => calls.add('next'),
          onRestore: () => calls.add('restore'),
          onTogglePinned: () => calls.add('pin'),
          onMinimize: () => calls.add('minimize'),
          onClose: () => calls.add('close'),
          onDragStart: () => calls.add('drag'),
        ));
    for (final name in [
      'previous',
      'play-pause',
      'next',
      'restore',
      'pin',
      'minimize',
      'close',
    ]) {
      await tester.tap(_key('compact-$name'));
      await tester.pump();
    }
    expect(calls, [
      'previous',
      'play',
      'next',
      'restore',
      'pin',
      'minimize',
      'close',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag region moves, double tap restores instead of maximizing',
      (tester) async {
    var moves = 0;
    var restores = 0;
    await _show(
        tester,
        CompactPlayerView(
          onDragStart: () => moves++,
          onRestore: () => restores++,
        ));
    await tester.drag(_key('compact-drag-region'), const Offset(40, 0));
    expect(moves, 1);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(_key('compact-drag-region'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(_key('compact-drag-region'));
    await tester.pump(const Duration(milliseconds: 80));
    expect(restores, 1);
    expect(moves, 1);
  });

  testWidgets('seek drag commits once and never starts moving the window',
      (tester) async {
    final seeks = <double>[];
    var moves = 0;
    await _show(
        tester,
        CompactPlayerView(
          trackIdentity: 'track-a',
          position: 30,
          duration: 240,
          onSeek: seeks.add,
          onDragStart: () => moves++,
        ));
    await tester.drag(_key('compact-progress-slider'), const Offset(60, 0));
    await tester.pump();
    expect(seeks, hasLength(1));
    expect(seeks.single, inInclusiveRange(0, 240));
    expect(moves, 0);
  });

  testWidgets('position updates do not jump the thumb during a seek',
      (tester) async {
    final seeks = <double>[];
    CompactPlayerView view(double position) => CompactPlayerView(
          trackIdentity: 'track-a',
          duration: 240,
          position: position,
          onSeek: seeks.add,
        );
    await _show(tester, view(30));
    var slider = tester.widget<Slider>(_key('compact-progress-slider'));
    slider.onChangeStart!(30);
    slider.onChanged!(150);
    await tester.pump();
    await _show(tester, view(35));
    slider = tester.widget<Slider>(_key('compact-progress-slider'));
    expect(slider.value, 150);
    slider.onChangeEnd!(150);
    await tester.pump();
    expect(seeks, [150]);
    expect(tester.widget<Slider>(_key('compact-progress-slider')).value, 35);
  });

  testWidgets('changing tracks cancels an old pending seek', (tester) async {
    final seeks = <double>[];
    CompactPlayerView view(String id) => CompactPlayerView(
          trackIdentity: id,
          duration: 240,
          position: 30,
          onSeek: seeks.add,
        );
    await _show(tester, view('track-a'));
    var slider = tester.widget<Slider>(_key('compact-progress-slider'));
    slider.onChangeStart!(30);
    slider.onChanged!(150);
    await tester.pump();
    await _show(tester, view('track-b'));
    slider = tester.widget<Slider>(_key('compact-progress-slider'));
    slider.onChangeEnd!(150);
    await tester.pump();
    expect(seeks, isEmpty);
    expect(tester.widget<Slider>(_key('compact-progress-slider')).value, 30);
  });

  testWidgets('another occurrence of the same path cancels the old seek drag',
      (tester) async {
    final seeks = <double>[];
    final firstFuture = Future<Lyric?>.value(_Lyric([_Line(0, 'Same song')]));
    final secondFuture = Future<Lyric?>.value(_Lyric([_Line(0, 'Same song')]));
    CompactPlayerView view(Future<Lyric?> future, double position) =>
        CompactPlayerView(
          // Matches the live adapter: path alone cannot identify a repeated
          // queue occurrence or an explicit source replacement during a drag.
          trackIdentity: ('same-path.mp3', future),
          lyricFuture: future,
          duration: 240,
          position: position,
          onSeek: seeks.add,
        );
    await _show(tester, view(firstFuture, 30));
    var slider = tester.widget<Slider>(_key('compact-progress-slider'));
    slider.onChangeStart!(30);
    slider.onChanged!(150);
    final oldFinish = slider.onChangeEnd!;
    await tester.pump();
    await _show(tester, view(secondFuture, 0));
    slider = tester.widget<Slider>(_key('compact-progress-slider'));
    expect(slider.value, 0);
    oldFinish(150);
    await tester.pump();
    expect(seeks, isEmpty);
    expect(tester.widget<Slider>(_key('compact-progress-slider')).value, 0);
  });

  testWidgets('slider also supports keyboard seeking', (tester) async {
    final seeks = <double>[];
    await _show(
        tester,
        CompactPlayerView(
          trackIdentity: 'track-a',
          duration: 240,
          position: 30,
          onSeek: seeks.add,
        ));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    seeks.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(seeks, hasLength(1));
    expect(seeks.single, greaterThan(30));
  });

  testWidgets('invalid duration/position is safe and cannot seek',
      (tester) async {
    await _show(
        tester,
        CompactPlayerView(
          duration: double.nan,
          position: double.infinity,
          onSeek: (_) => fail('Invalid duration must not seek'),
        ));
    final slider = tester.widget<Slider>(_key('compact-progress-slider'));
    expect(slider.value, 0);
    expect(slider.max, 1);
    expect(slider.onChanged, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buffering disables playback/seek but allows changing tracks',
      (tester) async {
    await _show(
        tester,
        CompactPlayerView(
          isBuffering: true,
          duration: 240,
          onPrevious: () {},
          onNext: () {},
          onPlayPause: () {},
          onSeek: (_) {},
        ));
    expect(find.byTooltip('正在缓冲'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<IconButton>(_key('compact-play-pause')).onPressed,
        isNull);
    expect(tester.widget<Slider>(_key('compact-progress-slider')).onChanged,
        isNull);
    expect(
        tester.widget<IconButton>(_key('compact-next')).onPressed, isNotNull);
    expect(tester.widget<IconButton>(_key('compact-previous')).onPressed,
        isNotNull);
  });

  testWidgets('busy transition disables competing window actions, not playback',
      (tester) async {
    await _show(
        tester,
        CompactPlayerView(
          isBusy: true,
          isPlaying: true,
          isPinned: true,
          onPlayPause: () {},
          onRestore: () {},
          onTogglePinned: () {},
          onMinimize: () {},
          onClose: () {},
          onDragStart: () {},
        ));
    for (final name in ['restore', 'pin', 'minimize', 'close']) {
      expect(
          tester.widget<IconButton>(_key('compact-$name')).onPressed, isNull);
    }
    expect(
        tester.widget<GestureDetector>(_key('compact-drag-region')).onPanStart,
        isNull);
    expect(tester.widget<IconButton>(_key('compact-play-pause')).onPressed,
        isNotNull);
    expect(find.byTooltip('暂停'), findsOneWidget);
    expect(find.byTooltip('取消置顶'), findsOneWidget);
  });

  testWidgets('idle live wrapper does not initialize PlayService or BASS',
      (tester) async {
    expect(PlayService.isInitialized, isFalse);
    final controller = WindowModeController();
    addTearDown(controller.dispose);
    await _show(tester, CompactPlayer(controller: controller));
    expect(find.text('尚未选择歌曲'), findsOneWidget);
    expect(tester.widget<IconButton>(_key('compact-play-pause')).onPressed,
        isNull);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final ratio in [1.0, 1.25, 1.5, 2.0]) {
    for (final size in [const Size(440, 280), const Size(520, 300)]) {
      testWidgets(
          'transport is symmetric about the entire $size window at $ratio DPR',
          (tester) async {
        await _show(
          tester,
          CompactPlayerView(
            title: 'A very long title does not push the central controls',
            onPrevious: () {},
            onPlayPause: () {},
            onNext: () {},
          ),
          size: size,
          devicePixelRatio: ratio,
        );
        final previous = tester.getCenter(_key('compact-previous'));
        final play = tester.getCenter(_key('compact-play-pause'));
        final next = tester.getCenter(_key('compact-next'));
        expect(play.dx, closeTo(size.width / 2, .01));
        expect(play.dx - previous.dx, closeTo(next.dx - play.dx, .01));
        expect(previous.dy, closeTo(play.dy, .01));
        expect(next.dy, closeTo(play.dy, .01));
        expect(tester.getSize(_key('compact-play-pause')), const Size(52, 52));
        _expectHeaderOrder(tester);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'minimum window shows cover, two lyric lines and progress at 100 percent',
      (tester) async {
    final future = Future<Lyric?>.value(_Lyric([
      _Line(0, 'Original lyric┃Translated lyric'),
    ]));
    await _show(
      tester,
      CompactPlayerView(
        trackIdentity: 'track',
        lyricFuture: future,
        duration: 240,
        position: 30,
        onSeek: (_) {},
      ),
      size: const Size(440, 280),
    );
    final lyric = tester.getRect(_key('compact-lyric-secondary'));
    final scroll = tester.getRect(_key('compact-content-scroll'));
    final transport = tester.getRect(_key('compact-transport-region'));
    final slider = tester.getRect(_key('compact-progress-slider'));
    expect(lyric.top, greaterThanOrEqualTo(scroll.top));
    expect(lyric.bottom, lessThanOrEqualTo(transport.top));
    expect(slider.top, greaterThanOrEqualTo(transport.bottom));
    expect(slider.bottom, lessThanOrEqualTo(280));
    expect(find.text('Original lyric'), findsOneWidget);
    expect(find.text('Translated lyric'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '200 percent scrolls only the middle region without moving transport',
      (tester) async {
    final future = Future<Lyric?>.value(_Lyric([
      _Line(
          0,
          '长原文日本語한국어 العربية This is the entire original lyric┃'
          '完整的长译文不会缩小字体，能通过提示和辅助功能读取'),
    ]));
    await _show(
      tester,
      CompactPlayerView(
        title: 'Song title',
        artist: 'Artist name',
        trackIdentity: 'track',
        lyricFuture: future,
        duration: 240,
        position: 30,
        onSeek: (_) {},
        onPlayPause: () {},
      ),
      size: const Size(440, 280),
      textScale: 2,
    );
    expect(
        MediaQuery.textScalerOf(tester.element(find.text('Song title')))
            .scale(16),
        32);
    final playBefore = tester.getRect(_key('compact-play-pause'));
    final progressBefore = tester.getRect(_key('compact-progress-slider'));
    final scrollable = find.descendant(
        of: _key('compact-content-scroll'), matching: find.byType(Scrollable));
    expect(tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
        greaterThan(0));
    await tester.ensureVisible(_key('compact-lyric-secondary'));
    await tester.pumpAndSettle();
    final lyric = tester.getRect(_key('compact-lyric-secondary'));
    final content = tester.getRect(_key('compact-content-scroll'));
    expect(lyric.top, greaterThanOrEqualTo(content.top - .01));
    expect(lyric.bottom, lessThanOrEqualTo(content.bottom + .01));
    expect(tester.getRect(_key('compact-play-pause')), playBefore);
    expect(tester.getRect(_key('compact-progress-slider')), progressBefore);
    expect(progressBefore.height, greaterThanOrEqualTo(44));
    expect(progressBefore.bottom, lessThanOrEqualTo(280));
    expect(playBefore.center.dx, 220);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'dragging progress previews lyrics then follows the committed position',
      (tester) async {
    final future = Future<Lyric?>.value(_Lyric([
      _Line(0, 'First line'),
      _Line(100, 'Second line'),
    ]));
    final seeks = <double>[];
    CompactPlayerView view(double position) => CompactPlayerView(
          trackIdentity: 'same-track',
          lyricFuture: future,
          duration: 240,
          position: position,
          onSeek: seeks.add,
        );
    await _show(tester, view(30));
    expect(
        tester.widget<Text>(_key('compact-lyric-primary')).data, 'First line');
    var slider = tester.widget<Slider>(_key('compact-progress-slider'));
    slider.onChangeStart!(30);
    slider.onChanged!(150);
    await tester.pump();
    expect(
        tester.widget<Text>(_key('compact-lyric-primary')).data, 'Second line');
    await _show(tester, view(35));
    expect(
        tester.widget<Text>(_key('compact-lyric-primary')).data, 'Second line');
    slider = tester.widget<Slider>(_key('compact-progress-slider'));
    slider.onChangeEnd!(150);
    await tester.pump();
    expect(seeks, [150]);
    await _show(tester, view(150));
    expect(
        tester.widget<Text>(_key('compact-lyric-primary')).data, 'Second line');
  });

  for (final brightness in Brightness.values) {
    testWidgets('mini content stays paired with its $brightness host during HC',
        (tester) async {
      final future = Future<Lyric?>.value(_Lyric([
        _Line(0, 'Original┃Translation'),
      ]));
      await _show(
        tester,
        WindowChromeTheme(
          foreground:
              brightness == Brightness.light ? Colors.white : Colors.black,
          child: CompactPlayerView(
            title: 'Visible title',
            artist: 'Visible artist',
            trackIdentity: 'same-track',
            lyricFuture: future,
          ),
        ),
        brightness: brightness,
        highContrast: true,
      );
      final scheme =
          Theme.of(tester.element(find.text('Visible title'))).colorScheme;
      expect(tester.widget<Text>(find.text('Visible title')).style!.color,
          scheme.primary);
      expect(tester.widget<Text>(find.text('Visible artist')).style!.color,
          scheme.onSurface);
      expect(tester.widget<Text>(find.text('Original')).style!.color,
          scheme.primary);
      expect(tester.widget<Text>(find.text('Translation')).style!.color,
          scheme.onSurfaceVariant);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'reduced-motion buffering is indicated without an endless spinner',
      (tester) async {
    await _show(tester, const CompactPlayerView(isBuffering: true));
    final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(spinner.value, isNotNull);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.byTooltip('正在缓冲'), findsOneWidget);
  });

  testWidgets(
      'a platform reduce-motion change also stops a paused buffering spinner',
      (tester) async {
    await _show(tester, const CompactPlayerView(isBuffering: true),
        reduced: false);
    expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .value,
        isNull);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .value,
        isNotNull);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });
}
