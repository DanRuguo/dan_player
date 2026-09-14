import 'dart:async';

import 'package:dan_player/component/live_seven_tone_spectrum.dart';
import 'package:dan_player/component/seven_tone_spectrum.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture {
  final samples = StreamController<List<double>>.broadcast(sync: true);
  final hidden = ValueNotifier(false);
  final preferences = ValueNotifier(const RenderingPreferences());
  final navigator = GlobalKey<NavigatorState>();
  var current = <double>[.1, .2, .3, .4, .5, .6, .7];
  int reads = 0;

  Widget app({bool offstage = false, bool playing = true}) =>
      RenderingPreferencesScope(
        preferences: preferences,
        child: MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: Offstage(
              offstage: offstage,
              child: TickerMode(
                enabled: !offstage,
                child: Center(
                  child: LiveSevenToneSpectrum(
                    samples: samples.stream,
                    readLevels: () {
                      reads++;
                      return current;
                    },
                    isPlaying: playing,
                    color: Colors.teal,
                    hidden: hidden,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> dispose() async {
    await samples.close();
    hidden.dispose();
    preferences.dispose();
  }
}

List<double> _levels(WidgetTester tester) => tester
    .widget<SevenToneSpectrum>(
        find.byType(SevenToneSpectrum, skipOffstage: false))
    .levels;

void main() {
  testWidgets('dialogs keep FFT live; opaque routes stop and resume its demand',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    final state = tester.state(find.byType(LiveSevenToneSpectrum));
    final context = tester.element(find.byType(LiveSevenToneSpectrum));
    expect(fixture.samples.hasListener, isTrue);
    final dialog = showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(title: Text('Queue')),
    );
    await tester.pumpAndSettle();
    expect(ModalRoute.of(context)!.isCurrent, isFalse);
    expect(fixture.samples.hasListener, isTrue);
    fixture.samples.add([.8, .7]);
    await tester.pump();
    expect(_levels(tester), [.8, .7, 0, 0, 0, 0, 0]);
    expect(fixture.reads, 1);
    fixture.navigator.currentState!.pop();
    await dialog;
    await tester.pumpAndSettle();
    unawaited(fixture.navigator.currentState!.push(PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => const Scaffold(body: Text('Lyrics')),
    )));
    await tester.pumpAndSettle();
    expect(fixture.samples.hasListener, isFalse);
    fixture.current = [.9];
    fixture.samples.add(fixture.current);
    await tester.pump(const Duration(seconds: 5));
    expect(_levels(tester), everyElement(0));
    expect(tester.binding.hasScheduledFrame, isFalse);
    fixture.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(fixture.samples.hasListener, isTrue);
    expect(fixture.reads, 2);
    expect(_levels(tester), [.9, 0, 0, 0, 0, 0, 0]);
    expect(tester.state(find.byType(LiveSevenToneSpectrum)), same(state));
  });

  testWidgets(
      'mini offstage and native hide release FFT, opt-out stays honored',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    final state = tester.state(find.byType(LiveSevenToneSpectrum));
    await tester.pumpWidget(fixture.app(offstage: true));
    expect(fixture.samples.hasListener, isFalse);
    fixture.hidden.value = true;
    fixture.current = [.7];
    fixture.preferences.value =
        const RenderingPreferences(pauseWhenHidden: false);
    // Native hide/preferences can change when no more frames are produced.
    expect(fixture.samples.hasListener, isTrue);
    await tester.pump();
    expect(_levels(tester), [.7, 0, 0, 0, 0, 0, 0]);
    fixture.preferences.value = const RenderingPreferences();
    expect(fixture.samples.hasListener, isFalse);
    fixture.hidden.value = false;
    expect(fixture.samples.hasListener, isFalse,
        reason: 'the normal player is still offstage under mini mode');
    fixture.current = [.6];
    await tester.pumpWidget(fixture.app());
    expect(fixture.samples.hasListener, isTrue);
    expect(_levels(tester), [.6, 0, 0, 0, 0, 0, 0]);
    expect(tester.state(find.byType(LiveSevenToneSpectrum)), same(state));
    fixture.hidden.value = true;
    expect(fixture.samples.hasListener, isFalse);
    fixture.hidden.value = false;
    expect(fixture.samples.hasListener, isTrue);
  });

  testWidgets('paused playback and compact spectrum preference do not need FFT',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app(playing: false));
    expect(fixture.samples.hasListener, isFalse);
    expect(fixture.reads, 0);
    await tester.pumpWidget(fixture.app());
    expect(fixture.samples.hasListener, isTrue);
    fixture.preferences.value = const RenderingPreferences(
        pauseWhenHidden: false, compactSpectrum: false);
    expect(fixture.samples.hasListener, isFalse);
    await tester.pump();
    expect(_levels(tester), everyElement(0));
    fixture.preferences.value = const RenderingPreferences();
    expect(fixture.samples.hasListener, isTrue);
    await tester.pumpWidget(fixture.app(playing: false));
    expect(fixture.samples.hasListener, isFalse);
    expect(_levels(tester), everyElement(0));
  });

  for (final lifecycle in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets('application $lifecycle follows visual policy', (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      await tester.pumpWidget(fixture.app());
      tester.binding.handleAppLifecycleStateChanged(lifecycle);
      expect(
          fixture.samples.hasListener, lifecycle == AppLifecycleState.inactive);
      fixture.preferences.value =
          const RenderingPreferences(pauseWhenHidden: false);
      expect(
          fixture.samples.hasListener,
          lifecycle == AppLifecycleState.inactive ||
              lifecycle == AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(fixture.samples.hasListener, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fixture.samples.hasListener, isFalse);
    });
  }

  testWidgets('reduced motion stops demand even with hidden opt-out',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    fixture.preferences.value =
        const RenderingPreferences(pauseWhenHidden: false);
    await tester.pumpWidget(fixture.app());
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    expect(fixture.samples.hasListener, isFalse);
    await tester.pump();
    expect(_levels(tester), everyElement(0));
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    expect(fixture.samples.hasListener, isTrue);
  });

  testWidgets(
      'identical frames cause no rebuild or idle clock; input is copied',
      (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    final original =
        tester.widget<SevenToneSpectrum>(find.byType(SevenToneSpectrum));
    for (var i = 0; i < 100; i++) {
      fixture.samples.add(List.of(fixture.current));
    }
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.widget<SevenToneSpectrum>(find.byType(SevenToneSpectrum)),
        same(original));
    final buffer = [double.nan, -1.0, 2.0, .4];
    fixture.samples.add(buffer);
    buffer[3] = .8;
    await tester.pump();
    expect(_levels(tester), [0, 0, 1, .4, 0, 0, 0]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(fixture.samples.hasListener, isFalse);
    fixture.hidden.value = true;
    fixture.preferences.value =
        const RenderingPreferences(compactSpectrum: false);
    expect(tester.takeException(), isNull);
  });
}
