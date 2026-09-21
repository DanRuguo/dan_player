import 'dart:async';

import 'package:dan_player/component/compact_lyric_view.dart';
import 'package:dan_player/component/compact_player.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Lyric extends Lyric {
  _Lyric()
      : super([
          LrcLine(Duration.zero, 'First line',
              isBlank: false, length: const Duration(seconds: 40)),
          LrcLine(const Duration(seconds: 40), 'Second line',
              isBlank: false, length: const Duration(seconds: 60)),
        ]);
}

class _Fixture {
  final positions = StreamController<double>.broadcast(sync: true);
  final hidden = ValueNotifier(false);
  final preferences = ValueNotifier(const RenderingPreferences());
  final future = Future<Lyric?>.value(_Lyric());
  final seeks = <double>[];
  var position = 10.0;
  var reads = 0;
  String title = 'Stable title';
  Object identity = 'song';
  bool treeVisible = true;

  Widget app({Stream<double>? source}) => RenderingPreferencesScope(
        preferences: preferences,
        child: MaterialApp(
          home: Scaffold(
            body: TickerMode(
              enabled: treeVisible,
              child: CompactPlayerView(
                title: title,
                trackIdentity: identity,
                lyricFuture: future,
                positions: source ?? positions.stream,
                readPosition: () {
                  reads++;
                  return position;
                },
                hidden: hidden,
                duration: 100,
                isPlaying: true,
                onSeek: seeks.add,
              ),
            ),
          ),
        ),
      );

  void emit(double value) {
    position = value;
    positions.add(value);
  }

  Future<void> dispose() async {
    await positions.close();
    hidden.dispose();
    preferences.dispose();
  }
}

Slider _slider(WidgetTester tester) => tester
    .widget<Slider>(find.byKey(const ValueKey('compact-progress-slider')));

void main() {
  testWidgets('live progress rebuilds only lyric and progress regions',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text(fixture.title));
    final close = tester.widget(find.byKey(const ValueKey('compact-close')));
    final play =
        tester.widget(find.byKey(const ValueKey('compact-play-pause')));
    final lyricState = tester.state(find.byType(CompactLyricView));
    for (var i = 0; i < 30; i++) {
      fixture.emit(10 + i / 30);
      await tester.pump(const Duration(milliseconds: 33));
      expect(tester.widget<Text>(find.text(fixture.title)), same(title));
      expect(tester.widget(find.byKey(const ValueKey('compact-close'))),
          same(close));
      expect(tester.widget(find.byKey(const ValueKey('compact-play-pause'))),
          same(play));
    }
    expect(_slider(tester).value, closeTo(10 + 29 / 30, .001));
    fixture.emit(45);
    await tester.pumpAndSettle();
    expect(find.text('Second line'), findsOneWidget);
    expect(tester.state(find.byType(CompactLyricView)), same(lyricState));
    fixture.title = 'Updated title';
    await tester.pumpWidget(fixture.app());
    expect(find.text('Updated title'), findsOneWidget);
    expect(_slider(tester).value, 45);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('native hide stops demand immediately and resumes current lyrics',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(CompactPlayerView));
    expect(fixture.positions.hasListener, isTrue);
    expect(fixture.reads, 1);
    fixture.hidden.value = true;
    expect(fixture.positions.hasListener, isFalse);
    for (var i = 0; i < 500; i++) {
      fixture.emit(i / 10);
    }
    await tester.pump(const Duration(seconds: 1));
    expect(_slider(tester).value, 10);
    expect(fixture.reads, 1);
    fixture.hidden.value = false;
    await tester.pumpAndSettle();
    expect(_slider(tester).value, 49.9);
    expect(find.text('Second line'), findsOneWidget);
    expect(tester.state(find.byType(CompactPlayerView)), same(state));
    expect(fixture.reads, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(fixture.positions.hasListener, isFalse);
    fixture.hidden.value = true;
    fixture.hidden.value = false;
    expect(fixture.reads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live preference and inactive lifecycle obey visual policy',
      (tester) async {
    final fixture = _Fixture()..hidden.value = true;
    addTearDown(fixture.dispose);
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await tester.pumpWidget(fixture.app());
    expect(fixture.positions.hasListener, isFalse);
    expect(fixture.reads, 0);
    fixture.preferences.value =
        const RenderingPreferences(pauseWhenHidden: false);
    expect(fixture.positions.hasListener, isTrue);
    fixture.emit(20);
    await tester.pumpAndSettle();
    expect(_slider(tester).value, 20);
    fixture.preferences.value = const RenderingPreferences();
    expect(fixture.positions.hasListener, isFalse);
    fixture.hidden.value = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(fixture.positions.hasListener, isTrue);
    fixture.emit(30);
    await tester.pumpAndSettle();
    expect(_slider(tester).value, 30);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(fixture.positions.hasListener, isFalse);
    fixture.emit(70);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(_slider(tester).value, 70);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('offstage replacement does not consume old or new hidden streams',
      (tester) async {
    final fixture = _Fixture();
    final second = StreamController<double>.broadcast(sync: true);
    addTearDown(fixture.dispose);
    addTearDown(second.close);
    await tester.pumpWidget(fixture.app());
    fixture.treeVisible = false;
    await tester.pumpWidget(fixture.app(source: second.stream));
    expect(fixture.positions.hasListener, isFalse);
    expect(second.hasListener, isFalse);
    fixture.position = 60;
    fixture.treeVisible = true;
    await tester.pumpWidget(fixture.app(source: second.stream));
    await tester.pumpAndSettle();
    expect(_slider(tester).value, 60);
    second.addError(StateError('transient sample failure'));
    await tester.pump();
    expect(_slider(tester).value, 60);
    second.add(62);
    await tester.pump();
    expect(_slider(tester).value, 62);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(second.hasListener, isFalse);
  });

  testWidgets('live samples preserve drag preview and hiding cancels late seek',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final slider = _slider(tester);
    slider.onChangeStart!(10);
    slider.onChanged!(65);
    fixture.emit(11);
    await tester.pumpAndSettle();
    expect(_slider(tester).value, 65);
    expect(find.text('Second line'), findsOneWidget);
    fixture.hidden.value = true;
    fixture.position = 18;
    fixture.hidden.value = false;
    slider.onChangeEnd!(65);
    await tester.pumpAndSettle();
    expect(fixture.seeks, isEmpty);
    expect(_slider(tester).value, 18);
    expect(find.text('First line'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
