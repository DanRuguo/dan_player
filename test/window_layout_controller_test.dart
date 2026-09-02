import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/window_layout_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWindowLayoutAdapter implements WindowLayoutAdapter {
  Size size = const Size(1600, 900);
  final calls = <String>[];
  Object? failure;

  @override
  Future<Size> getSize() async {
    calls.add('getSize');
    return size;
  }

  @override
  Future<void> setAspectRatio(double value) async {
    calls.add('ratio:${value.toStringAsFixed(4)}');
    if (failure != null) throw failure!;
  }

  @override
  Future<void> setResizable(bool value) async {
    calls.add('resizable:$value');
    if (failure != null) throw failure!;
  }
}

void main() {
  test('default policy leaves resize free and clears any native ratio',
      () async {
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    final adapter = _FakeWindowLayoutAdapter();
    final controller = WindowLayoutController(
      adapter: adapter,
      preferences: preferences,
      persistCapturedRatio: () async {},
    );
    addTearDown(controller.dispose);
    addTearDown(preferences.dispose);

    await controller.initialize();

    expect(adapter.calls, ['ratio:0.0000', 'resizable:true']);
    expect(controller.lastError, isNull);
  });

  test('ratio lock captures the live ratio once and persists it', () async {
    final preferences = ValueNotifier(const PlayerExperiencePreferences(
      windowAspectRatioLocked: true,
    ));
    final adapter = _FakeWindowLayoutAdapter();
    var saves = 0;
    final controller = WindowLayoutController(
      adapter: adapter,
      preferences: preferences,
      persistCapturedRatio: () async => saves++,
    );
    addTearDown(controller.dispose);
    addTearDown(preferences.dispose);

    await controller.initialize();
    await controller.apply();

    expect(preferences.value.windowAspectRatio, closeTo(16 / 9, .0001));
    expect(saves, 1);
    expect(adapter.calls, contains('getSize'));
    expect(adapter.calls, contains('ratio:1.7778'));
    expect(adapter.calls.last, 'resizable:true');
  });

  test('size lock changes only user resizing and can be released', () async {
    final preferences = ValueNotifier(const PlayerExperiencePreferences(
      windowSizeLocked: true,
    ));
    final adapter = _FakeWindowLayoutAdapter();
    final controller = WindowLayoutController(
      adapter: adapter,
      preferences: preferences,
      persistCapturedRatio: () async {},
    );
    addTearDown(controller.dispose);
    addTearDown(preferences.dispose);

    await controller.initialize();
    expect(adapter.calls.last, 'resizable:false');

    preferences.value = preferences.value.copyWith(windowSizeLocked: false);
    await controller.apply();
    expect(adapter.calls.last, 'resizable:true');
  });

  test('fixed size wins when an old caller supplies both window constraints',
      () async {
    final preferences = ValueNotifier(const PlayerExperiencePreferences(
      windowSizeLocked: true,
      windowAspectRatioLocked: true,
      windowAspectRatio: 16 / 9,
    ));
    final adapter = _FakeWindowLayoutAdapter();
    final controller = WindowLayoutController(
      adapter: adapter,
      preferences: preferences,
      persistCapturedRatio: () async {},
    );
    addTearDown(controller.dispose);
    addTearDown(preferences.dispose);

    await controller.initialize();

    expect(adapter.calls, ['ratio:0.0000', 'resizable:false']);
    expect(adapter.calls, isNot(contains('getSize')),
        reason: 'the ignored ratio lock must not capture a new native ratio');
  });

  test('native failure is exposed and a later retry clears it', () async {
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    final adapter = _FakeWindowLayoutAdapter()..failure = StateError('fixture');
    final controller = WindowLayoutController(
      adapter: adapter,
      preferences: preferences,
      persistCapturedRatio: () async {},
    );
    addTearDown(controller.dispose);
    addTearDown(preferences.dispose);

    await expectLater(controller.initialize(), throwsStateError);
    expect(controller.lastError, isA<StateError>());

    adapter.failure = null;
    await controller.apply();
    expect(controller.lastError, isNull);
  });
}
