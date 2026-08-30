import 'dart:async';

import 'package:dan_player/component/full_width_spectrum.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Lyric extends Lyric {
  _Lyric()
      : super([
          for (var i = 0; i < 20; i++)
            LrcLine(Duration(seconds: i * 5), 'Line $i',
                isBlank: false, length: const Duration(seconds: 5)),
        ]);
}

class _Fixture {
  final lyric = _Lyric();
  final position = StreamController<double>.broadcast(sync: true);
  final hidden = ValueNotifier(false);
  final settings = LyricViewController();
  double current = 0;
  int reads = 0;

  void emit(double seconds) {
    current = seconds;
    position.add(seconds);
  }

  Widget view() => ChangeNotifierProvider.value(
        value: settings,
        child: VerticalLyricScrollView(
          lyric: lyric,
          positionStream: position.stream,
          readPosition: () {
            reads++;
            return current;
          },
          onSeek: emit,
          hidden: hidden,
        ),
      );

  Future<void> dispose() async {
    await position.close();
    hidden.dispose();
    settings.dispose();
  }
}

Widget _app(Widget child,
        {bool ticker = true, GlobalKey<NavigatorState>? navigator}) =>
    MaterialApp(
      navigatorKey: navigator,
      home: Scaffold(
        body: TickerMode(
          enabled: ticker,
          child: Center(child: SizedBox(width: 440, height: 320, child: child)),
        ),
      ),
    );

LyricViewTile _current(WidgetTester tester) => tester
    .widgetList<LyricViewTile>(find.byType(LyricViewTile))
    .singleWhere((row) => row.distance == 0);

String _currentText(WidgetTester tester) =>
    (_current(tester).line as LrcLine).content;

void main() {
  testWidgets('initial hidden lyric surface has no position demand or reads',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(_app(fixture.view(), ticker: false));
    await tester.pumpAndSettle();
    expect(fixture.position.hasListener, isFalse);
    expect(fixture.reads, 0);
    for (var i = 0; i < 500; i++) {
      fixture.emit(i / 10);
    }
    await tester.pump(const Duration(seconds: 5));
    expect(fixture.reads, 0);
    await tester.pumpWidget(_app(fixture.view()));
    await tester.pumpAndSettle();
    expect(fixture.position.hasListener, isTrue);
    expect(fixture.reads, 1);
    expect(_currentText(tester), 'Line 9');
    expect(tester.takeException(), isNull);
  });

  testWidgets('native hide cancels immediately and resume keeps mounted rows',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(_app(fixture.view()));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(VerticalLyricScrollView));
    final position = _current(tester).position;
    var paints = 0;
    position.addListener(() => paints++);
    fixture.hidden.value = true;
    // No pump: a hidden native window may stop producing frames altogether.
    expect(fixture.position.hasListener, isFalse);
    final before = position.value;
    for (var i = 0; i < 500; i++) {
      fixture.emit(i / 10);
    }
    expect(position.value, before);
    expect(paints, 0);
    fixture.hidden.value = false;
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(VerticalLyricScrollView)), same(state));
    expect(_currentText(tester), 'Line 9');
    expect(paints, 1);
    expect(fixture.reads, 2);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('covered route stops demand and resumes the current snapshot',
      (tester) async {
    final fixture = _Fixture();
    final navigator = GlobalKey<NavigatorState>();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(_app(fixture.view(), navigator: navigator));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(VerticalLyricScrollView));
    unawaited(navigator.currentState!.push(PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, animation, secondary) => const Text('Overlay'),
    )));
    await tester.pumpAndSettle();
    expect(fixture.position.hasListener, isFalse);
    fixture.emit(30);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(_currentText(tester), 'Line 6');
    expect(tester.state(find.byType(VerticalLyricScrollView)), same(state));
    expect(tester.takeException(), isNull);
  });

  testWidgets('paused app stops lyric demand without waiting for build',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await tester.pumpWidget(_app(fixture.view()));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(fixture.position.hasListener, isFalse);
    fixture.emit(45);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fixture.position.hasListener, isTrue);
    expect(_currentText(tester), 'Line 9');
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden source replacement subscribes only when shown',
      (tester) async {
    final first = _Fixture();
    final second = _Fixture()..current = 60;
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(_app(first.view()));
    await tester.pumpAndSettle();
    first.hidden.value = true;
    second.hidden.value = true;
    await tester.pumpWidget(_app(second.view()));
    await tester.pumpAndSettle();
    expect(first.position.hasListener, isFalse);
    expect(second.position.hasListener, isFalse);
    expect(second.reads, 0);
    first.hidden.value = false;
    expect(first.position.hasListener, isFalse);
    second.hidden.value = false;
    await tester.pumpAndSettle();
    expect(second.reads, 1);
    expect(_currentText(tester), 'Line 12');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(second.position.hasListener, isFalse);
    second.hidden.value = true;
    second.hidden.value = false;
    expect(tester.takeException(), isNull);
  });

  testWidgets('native hidden spectrum releases demand without lifecycle frame',
      (tester) async {
    final hidden = ValueNotifier(false);
    final frames = StreamController<List<double>>.broadcast(sync: true);
    addTearDown(hidden.dispose);
    addTearDown(frames.close);
    var reads = 0;
    await tester.pumpWidget(_app(FullWidthSpectrumView(
      samples: frames.stream,
      readLevels: () {
        reads++;
        return [.2, .8];
      },
      hidden: hidden,
    )));
    await tester.pumpAndSettle();
    expect(frames.hasListener, isTrue);
    hidden.value = true;
    expect(frames.hasListener, isFalse);
    for (var i = 0; i < 500; i++) {
      frames.add([.3, .7]);
    }
    expect(reads, 1);
    hidden.value = false;
    await tester.pump();
    expect(frames.hasListener, isTrue);
    expect(reads, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(frames.hasListener, isFalse);
    hidden.value = true;
    expect(tester.takeException(), isNull);
  });
}
