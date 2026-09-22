import 'package:dan_player/component/artwork_pulse.dart';
import 'package:dan_player/component/background_image_motion.dart';
import 'package:dan_player/component/fluid_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attack and release are frame-rate independent and bounded', () {
    for (final hz in [30, 60, 144]) {
      final pulse = ArtworkPulse();
      for (var i = 0; i < hz; i++) {
        pulse.advance(1 / hz, 1);
      }
      expect(pulse.scale, closeTo(1.075, .000001));
      for (var i = 0; i < hz; i++) {
        pulse.advance(1 / hz, 0);
      }
      expect(pulse.scale, closeTo(1.00210867, .000001));
      pulse.advance(1, double.nan);
      expect(pulse.scale, inInclusiveRange(1, 1.075));
      pulse.advance(1, -2);
      pulse.advance(1, 8);
      expect(pulse.scale, inInclusiveRange(1, 1.075));
      pulse.reset();
      expect(pulse.scale, 1);
    }
  });

  testWidgets('only the existing visible playback clock samples the cache',
      (tester) async {
    var reads = 0;
    var builds = 0;
    final hidden = ValueNotifier(false);
    final child = Builder(builder: (_) {
      builds++;
      return const ColoredBox(color: Colors.orange);
    });
    Widget app({bool enabled = true, bool playing = true}) => MaterialApp(
          home: BackgroundImageMotion(
            enabled: true,
            isPlaying: playing,
            hidden: hidden,
            refreshInterval: const Duration(milliseconds: 16),
            phaseBuilder: (phase, active, child) => FluidArtwork(
              phase: phase,
              active: active,
              readLowFrequency: enabled
                  ? () {
                      reads++;
                      return 1;
                    }
                  : null,
              child: child,
            ),
            child: child,
          ),
        );
    ArtworkFlowDelegate delegate() =>
        tester.widget<Flow>(find.byType(Flow)).delegate as ArtworkFlowDelegate;
    await tester.pumpWidget(app());
    await tester.pump();
    final initialBuilds = builds;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(delegate().pulse!.scale, greaterThan(1.06));
    expect(builds, initialBuilds,
        reason: 'texture is not rebuilt by the pulse');
    hidden.value = true;
    final before = reads;
    final scale = delegate().pulse!.scale;
    await tester.pump(const Duration(seconds: 1));
    expect(reads, before);
    expect(delegate().pulse!.scale, scale);
    expect(tester.binding.transientCallbackCount, 0);
    hidden.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 8));
    expect(reads, greaterThan(before));
    await tester.pumpWidget(app(playing: false));
    final paused = reads;
    await tester.pump(const Duration(seconds: 1));
    expect(reads, paused);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(app(enabled: false));
    await tester.pump(const Duration(milliseconds: 16));
    expect(delegate().pulse, isNull);
    expect(reads, paused);
    await tester.pumpWidget(const SizedBox());
    hidden.dispose();
  });

  testWidgets('cycle boundary uses a short elapsed interval, not a full cycle',
      (tester) async {
    final phase = ValueNotifier(.9999);
    await tester.pumpWidget(MaterialApp(
        home: FluidArtwork(
      phase: phase,
      readLowFrequency: () => 1,
      child: const ColoredBox(color: Colors.blue),
    )));
    phase.value = .0001;
    final delegate =
        tester.widget<Flow>(find.byType(Flow)).delegate as ArtworkFlowDelegate;
    expect(delegate.pulse!.scale, closeTo(1.006865, .000001));
    await tester.pumpWidget(const SizedBox());
    phase.dispose();
    expect(tester.binding.transientCallbackCount, 0);
  });
}
