import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/playing_logo.dart';
import 'package:dan_player/performance_preset.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('title decoration never initializes playback to inspect state',
      (tester) async {
    expect(PlayService.isInitialized, isFalse);
    await tester.pumpWidget(const MaterialApp(home: PlayingLogo()));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(RotationTransition), findsNothing);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'playing logo stops itself for pause, hidden, offstage and its setting',
      (tester) async {
    final hidden = ValueNotifier(false);
    final rendering = ValueNotifier(const RenderingPreferences());
    addTearDown(hidden.dispose);
    addTearDown(rendering.dispose);
    var playing = false;
    var visible = true;
    var childBuilds = 0;
    late StateSetter change;
    final child = Builder(builder: (_) {
      childBuilds++;
      return const SizedBox(
          width: 24, height: 24, child: ColoredBox(color: Colors.teal));
    });
    await tester.pumpWidget(MaterialApp(
        home: RenderingPreferencesScope(
      preferences: rendering,
      child: StatefulBuilder(builder: (_, setState) {
        change = setState;
        return TickerMode(
            enabled: visible,
            child: Offstage(
                offstage: !visible,
                child: PlayingLogoMotion(
                    playing: playing, hidden: hidden, child: child)));
      }),
    )));
    AnimationController controller() => tester
        .widget<RotationTransition>(
            find.byType(RotationTransition, skipOffstage: false))
        .turns as AnimationController;
    await tester.pump();
    expect(controller().isAnimating, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    change(() => playing = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller().value, greaterThan(0));
    expect(controller().isAnimating, isTrue);
    final initialBuilds = childBuilds;
    await tester.pump(const Duration(milliseconds: 300));
    expect(childBuilds, initialBuilds,
        reason: 'Only the cached icon transform should animate');

    Future<void> stopped() async {
      await tester.pump();
      final pausedAt = controller().value;
      expect(controller().isAnimating, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(controller().value, pausedAt);
      expect(tester.binding.hasScheduledFrame, isFalse);
    }

    change(() => playing = false);
    await stopped();
    final pausedAt = controller().value;
    change(() => playing = true);
    await tester.pump();
    expect(controller().value, pausedAt,
        reason: 'Resuming must not reset the icon angle');
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller().isAnimating, isTrue);
    hidden.value = true;
    expect(controller().isAnimating, isFalse,
        reason: 'Native hidden stops before the next frame');
    await stopped();
    hidden.value = false;
    await tester.pump();
    expect(controller().isAnimating, isTrue);
    change(() => visible = false);
    await stopped();
    change(() => visible = true);
    await tester.pump();
    expect(controller().isAnimating, isTrue);
    rendering.value = rendering.value.copyWith(
        animations:
            rendering.value.animations.withKind(MotionKind.playingLogo, false));
    expect(controller().isAnimating, isFalse,
        reason: 'Preference listener must stop synchronously');
    await stopped();
    rendering.value = rendering.value.copyWith(
        animations:
            rendering.value.animations.withKind(MotionKind.playingLogo, true));
    await tester.pump();
    expect(controller().isAnimating, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(controller().isAnimating, isTrue,
        reason: 'Visible but unfocused music keeps its animation');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await stopped();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller().isAnimating, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('legacy disable-all retains its intent for the tenth animation', () {
    final oldKinds =
        MotionKind.values.where((kind) => kind != MotionKind.playingLogo);
    final old = {for (final kind in oldKinds) kind.name: false};
    expect(MotionPreferences.fromMap(old).allDisabled, isTrue);
    expect(MotionPreferences.fromMap(const {}).allows(MotionKind.playingLogo),
        isTrue);
    expect(
        MotionPreferences.fromMap({...old, 'feedback': true})
            .allows(MotionKind.playingLogo),
        isTrue);
    expect(
        MotionPreferences.fromMap({...old, 'playingLogo': true})
            .allows(MotionKind.playingLogo),
        isTrue);
    final copied =
        MotionPreferences.fromMap(MotionPreferences.fromMap(old).toMap());
    expect(copied.allDisabled, isTrue);
  });

  test('power presets include the playing icon and restore its original choice',
      () async {
    final original = PerformanceSnapshot.capture(
        const RenderingPreferences(
            animations: MotionPreferences(disabled: {MotionKind.playingLogo})),
        const BackgroundPreferences(),
        const PlayerExperiencePreferences(),
        false);
    var live = original;
    final preset = PerformancePresetController(
        capture: () => live,
        apply: (next) => live = next,
        persist: () async {});
    addTearDown(preset.dispose);
    await preset.select(PerformanceMode.performance);
    expect(live.rendering.animations.allows(MotionKind.playingLogo), isTrue);
    await preset.select(PerformanceMode.economy);
    expect(live.rendering.animations.allows(MotionKind.playingLogo), isFalse);
    await preset.select(PerformanceMode.custom);
    expect(live.toMap(), original.toMap());
  });
}
