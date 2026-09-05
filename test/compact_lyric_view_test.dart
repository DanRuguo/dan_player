import 'dart:async';

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/compact_lyric_view.dart';
import 'package:dan_player/component/window_chrome_theme.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Lyric extends Lyric {
  _Lyric(super.lines);
}

class _Line extends UnsyncLyricLine {
  _Line(int seconds, String text) : super(Duration(seconds: seconds), text);
}

Widget _app({
  Object? track = 'track-a',
  Future<Lyric?>? future,
  double position = 0,
  bool reduced = true,
  bool tickerEnabled = true,
  double scale = 1,
  bool highContrast = false,
  Brightness brightness = Brightness.light,
  Color? chromeForeground,
}) =>
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue, brightness: brightness),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduced,
          textScaler: TextScaler.linear(scale),
          highContrast: highContrast,
        ),
        child: TickerMode(
          enabled: tickerEnabled,
          child: WindowChromeTheme(foreground: chromeForeground, child: child!),
        ),
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: CompactLyricView(
                trackIdentity: track, lyricFuture: future, position: position),
          ),
        ),
      ),
    );

Finder _primary() => find.byKey(const ValueKey('compact-lyric-primary'));
Finder _secondary() => find.byKey(const ValueKey('compact-lyric-secondary'));
Finder _switcher() => find.byKey(const ValueKey('compact-lyric-switcher'));

String _text(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder).data!;

void main() {
  testWidgets('idle, loading, missing and failed lyrics have explicit states',
      (tester) async {
    await tester.pumpWidget(_app(track: null));
    expect(_text(tester, _primary()), '选择歌曲，开始聆听');
    await tester.pumpWidget(_app());
    expect(_text(tester, _primary()), '暂无歌词');
    final pending = Completer<Lyric?>();
    await tester.pumpWidget(_app(future: pending.future));
    expect(_text(tester, _primary()), '正在加载歌词…');
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(_text(tester, _primary()), '暂无歌词');
    final failing = Completer<Lyric?>();
    await tester.pumpWidget(_app(future: failing.future));
    failing.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(_text(tester, _primary()), '歌词加载失败');
    expect(_text(tester, _secondary()), '请在完整播放器重试或切换来源');
    expect(tester.takeException(), isNull);
  });

  testWidgets('late success from an old track cannot overwrite the new one',
      (tester) async {
    final first = Completer<Lyric?>();
    final second = Completer<Lyric?>();
    await tester.pumpWidget(_app(future: first.future));
    await tester.pumpWidget(_app(track: 'track-b', future: second.future));
    second.complete(_Lyric([_Line(0, 'New track line')]));
    await tester.pumpAndSettle();
    expect(_text(tester, _primary()), 'New track line');
    first.complete(_Lyric([_Line(0, 'Old track late line')]));
    await tester.pumpAndSettle();
    expect(_text(tester, _primary()), 'New track line');
    expect(find.text('Old track late line'), findsNothing);
  });

  testWidgets(
      'late old-track failure does not replace a pending new-track state',
      (tester) async {
    final first = Completer<Lyric?>();
    final second = Completer<Lyric?>();
    await tester.pumpWidget(_app(future: first.future));
    await tester.pumpWidget(_app(track: 'track-b', future: second.future));
    first.completeError(StateError('old request failed'));
    await tester.pumpAndSettle();
    expect(_text(tester, _primary()), '正在加载歌词…');
    second.complete(_Lyric([_Line(0, 'New track')]));
    await tester.pumpAndSettle();
    expect(_text(tester, _primary()), 'New track');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'changing the source on one track immediately clears the old lyric',
      (tester) async {
    final first = Future<Lyric?>.value(_Lyric([_Line(0, 'Original source')]));
    final second = Completer<Lyric?>();
    await tester.pumpWidget(_app(future: first, reduced: false));
    await tester.pumpAndSettle();
    expect(find.text('Original source'), findsOneWidget);
    await tester.pumpWidget(_app(future: second.future, reduced: false));
    expect(find.text('Original source'), findsNothing);
    expect(_text(tester, _primary()), '正在加载歌词…');
    second.complete(_Lyric([_Line(0, 'Chosen replacement')]));
    await tester.pumpAndSettle();
    expect(_text(tester, _primary()), 'Chosen replacement');
  });

  testWidgets(
      'clearing the track never displays a pending result as idle lyrics',
      (tester) async {
    final future = Completer<Lyric?>();
    await tester.pumpWidget(_app(future: future.future));
    await tester.pumpWidget(_app(track: null, future: future.future));
    future.complete(_Lyric([_Line(0, 'No longer selected')]));
    await tester.pumpAndSettle();
    expect(_text(tester, _primary()), '选择歌曲，开始聆听');
    expect(find.text('No longer selected'), findsNothing);
  });

  testWidgets('forward and backward seeking use the supplied playback position',
      (tester) async {
    final future = Future<Lyric?>.value(_Lyric([
      _Line(10, 'First┃首句译文'),
      _Line(20, 'Second'),
      _Line(30, 'Third'),
    ]));
    await tester.pumpWidget(_app(future: future, position: 9.99));
    await tester.pump();
    expect(_text(tester, _primary()), '歌词即将开始');
    expect(_text(tester, _secondary()), 'First');
    await tester.pumpWidget(_app(future: future, position: 10));
    expect(_text(tester, _primary()), 'First');
    expect(_text(tester, _secondary()), '首句译文');
    await tester.pumpWidget(_app(future: future, position: 25));
    expect(_text(tester, _primary()), 'Second');
    expect(_text(tester, _secondary()), '下一句 · Third');
    await tester.pumpWidget(_app(future: future, position: 12));
    expect(_text(tester, _primary()), 'First');
    await tester.pumpWidget(_app(future: future, position: 31));
    expect(_text(tester, _primary()), 'Third');
    expect(_text(tester, _secondary()), isEmpty);
  });

  testWidgets('instrumental and silent-break states remain distinct',
      (tester) async {
    final music = Future<Lyric?>.value(_Lyric([
      _Line(0, '纯音乐，请欣赏'),
    ]));
    await tester.pumpWidget(_app(future: music));
    await tester.pump();
    expect(_text(tester, _primary()), '纯音乐，请欣赏');
    final lyrics = Future<Lyric?>.value(_Lyric([
      _Line(0, 'Verse'),
      _Line(10, ''),
      _Line(20, 'Chorus'),
    ]));
    await tester.pumpWidget(_app(future: lyrics, position: 15));
    await tester.pump();
    expect(_text(tester, _primary()), '间奏 · 聆听音乐');
    expect(_text(tester, _secondary()), '下一句 · Chorus');
  });

  testWidgets('paused playback and ticks within one line do not replay entry',
      (tester) async {
    final future = Future<Lyric?>.value(_Lyric([
      _Line(0, 'Stable line'),
      _Line(20, 'Next'),
    ]));
    await tester.pumpWidget(_app(future: future, reduced: false));
    await tester.pumpAndSettle();
    for (final position in [2.0, 3.0, 3.0, 3.0, 2.0]) {
      await tester
          .pumpWidget(_app(future: future, reduced: false, position: position));
      final fade = find.descendant(
          of: _switcher(), matching: find.byType(FadeTransition));
      expect(fade, findsOneWidget);
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      expect(_text(tester, _primary()), 'Stable line');
      expect(tester.binding.transientCallbackCount, 0);
    }
  });

  testWidgets('line changes fade only text and exclude outgoing semantics',
      (tester) async {
    final future = Future<Lyric?>.value(_Lyric([
      _Line(0, 'Old line'),
      _Line(10, 'New line'),
    ]));
    await tester.pumpWidget(_app(future: future, reduced: false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(future: future, reduced: false, position: 12));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('Old line'), findsOneWidget);
    expect(find.text('New line'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Old line'),
        matching: find.byWidgetPredicate(
            (widget) => widget is ExcludeSemantics && widget.excluding),
      ),
      findsWidgets,
    );
    expect(
        tester.widget<AnimatedSwitcher>(_switcher()).duration, AppMotion.quick);
    for (var frame = 0; frame < 5; frame++) {
      final visible = tester
          .widgetList<FadeTransition>(find.descendant(
              of: _switcher(), matching: find.byType(FadeTransition)))
          .where((fade) => fade.opacity.value > 0)
          .length;
      expect(visible, lessThanOrEqualTo(1),
          reason: 'Lyric text must not overlap');
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(find.text('Old line'), findsNothing);
    expect(_text(tester, _primary()), 'New line');
  });

  testWidgets(
      'a live reduced-motion change finishes the lyric fade immediately',
      (tester) async {
    final future = Future<Lyric?>.value(_Lyric([
      _Line(0, 'First'),
      _Line(10, 'Second'),
    ]));
    await tester.pumpWidget(_app(future: future, reduced: false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_app(future: future, reduced: false, position: 12));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(_app(future: future, position: 12));
    expect(_switcher(), findsNothing);
    expect(find.text('First'), findsNothing);
    expect(_text(tester, _primary()), 'Second');
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final feature in ['disableAnimations', 'reduceMotion']) {
    testWidgets('platform $feature disables lyric transitions', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(
        disableAnimations: feature == 'disableAnimations',
        reduceMotion: feature == 'reduceMotion',
      );
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final future = Future<Lyric?>.value(_Lyric([_Line(0, 'Current')]));
      await tester.pumpWidget(_app(future: future, reduced: false));
      await tester.pump();
      expect(_switcher(), findsNothing);
      expect(_text(tester, _primary()), 'Current');
    });
  }

  testWidgets(
      'a live platform motion preference is observed without a new tick',
      (tester) async {
    final future = Future<Lyric?>.value(_Lyric([_Line(0, 'Current')]));
    await tester.pumpWidget(_app(future: future, reduced: false));
    await tester.pumpAndSettle();
    expect(_switcher(), findsOneWidget);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(_switcher(), findsNothing);
    expect(_text(tester, _primary()), 'Current');
  });

  testWidgets('disabled ticker scopes render the final line without a ticker',
      (tester) async {
    final future = Future<Lyric?>.value(_Lyric([_Line(0, 'Current')]));
    await tester
        .pumpWidget(_app(future: future, reduced: false, tickerEnabled: false));
    await tester.pump();
    expect(_switcher(), findsNothing);
    expect(_text(tester, _primary()), 'Current');
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final brightness in Brightness.values) {
    testWidgets('$brightness uses its opaque host palette even under HC chrome',
        (tester) async {
      final future = Future<Lyric?>.value(_Lyric([
        _Line(0, 'Original┃Translation'),
      ]));
      await tester.pumpWidget(_app(
        future: future,
        brightness: brightness,
        // Deliberately incompatible with this content background, as can
        // happen when a native high-contrast palette precedes MediaQuery.
        chromeForeground:
            brightness == Brightness.light ? Colors.white : Colors.black,
      ));
      await tester.pump();
      final scheme = Theme.of(tester.element(_primary())).colorScheme;
      expect(tester.widget<Text>(_primary()).style!.color!.toARGB32(),
          scheme.primary.toARGB32());
      expect(tester.widget<Text>(_secondary()).style!.color!.toARGB32(),
          scheme.onSurfaceVariant.toARGB32());
    });
  }

  testWidgets('long original and translated lines retain accessible full text',
      (tester) async {
    const original = '很长的原文 日本語 한국어 العربية This is a long lyric line';
    const translation = '这是不会被丢弃的完整译文，还有更多的内容供辅助技术阅读';
    final future = Future<Lyric?>.value(_Lyric([
      _Line(0, '$original┃$translation'),
    ]));
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_app(future: future, scale: 2));
      await tester.pump();
      expect(_text(tester, _primary()), original);
      expect(_text(tester, _secondary()), translation);
      expect(tester.widget<Text>(_primary()).overflow, TextOverflow.ellipsis);
      expect(tester.widget<Text>(_secondary()).overflow, TextOverflow.ellipsis);
      expect(find.byTooltip('$original\n译文：$translation'), findsOneWidget);
      expect(find.bySemanticsLabel('当前歌词：$original\n译文：$translation'),
          findsOneWidget);
      expect(MediaQuery.textScalerOf(tester.element(_primary())).scale(16), 32);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('invalid playback positions never crash the text-only adapter',
      (tester) async {
    final future = Future<Lyric?>.value(_Lyric([_Line(0, 'First')]));
    for (final position in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      double.maxFinite,
      -10.0,
    ]) {
      await tester.pumpWidget(_app(future: future, position: position));
      await tester.pump();
      expect(_text(tester, _primary()), 'First');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'disposal drops a late error without leaving subscriptions or timers',
      (tester) async {
    final future = Completer<Lyric?>();
    await tester.pumpWidget(_app(future: future.future, reduced: false));
    await tester.pumpWidget(const SizedBox.shrink());
    future.completeError(StateError('late completion'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
