import 'dart:async';

import 'package:dan_player/component/app_shape.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DesktopTestRig rig;
  setUp(() => rig = DesktopTestRig());
  tearDown(() => rig.dispose());

  // Legacy preferences remain readable. The current native build ignores the
  // clipping fields; these tests cover protocol compatibility, not live corners.
  test('legacy corner configuration retains the shared 16dp surface radius',
      () async {
    await rig.initialize();
    await flushDesktopEvents();
    final configuration =
        rig.native.calls.singleWhere((call) => call.$1 == 'configure').$2!;
    expect(configuration['roundedWindowCorners'], isTrue);
    expect(
        configuration['windowCornerRadius'], AppShape.surfaceRadius.topLeft.x);
    expect(configuration['windowCornerRadius'], 16.0);
    expect(configuration['trayIconCodepoints'], hasLength(9));
    expect(configuration['trayIconFontPath'],
        endsWith('MaterialSymbolsOutlined.ttf'));
  });

  test('legacy corner fields synchronize once without disturbing playback',
      () async {
    await rig.initialize();
    await flushDesktopEvents();
    rig.native.calls.clear();
    rig.preferences.value =
        rig.preferences.value.copyWith(roundedWindowCorners: false);
    await flushDesktopEvents();
    expect(rig.native.calls.map((call) => call.$1), ['configure']);
    expect(rig.native.calls.single.$2!['roundedWindowCorners'], isFalse);
    expect(rig.native.calls.single.$2!['windowCornerRadius'], 16.0);
    rig.native.calls.clear();
    rig.preferences.value =
        rig.preferences.value.copyWith(roundedWindowCorners: false);
    rig.preferences.value = rig.preferences.value.copyWith(springLyrics: false);
    await flushDesktopEvents();
    expect(rig.native.calls, isEmpty);
    rig.preferences.value =
        rig.preferences.value.copyWith(roundedWindowCorners: true);
    await flushDesktopEvents();
    expect(rig.native.calls.single.$2!['roundedWindowCorners'], isTrue);
    expect(rig.playback.actions, isEmpty);
    expect(rig.window.hideCalls, 0);
    expect(rig.window.showModes, isEmpty);
  });

  test('a pending initial acknowledgement cannot swallow a corner toggle',
      () async {
    final gate = Completer<Object?>();
    rig.native.intercept = (method, _) async =>
        method == 'configure' && !gate.isCompleted
            ? gate.future
            : rig.native.state();
    final initialization = rig.initialize();
    rig.preferences.value =
        rig.preferences.value.copyWith(roundedWindowCorners: false);
    gate.complete(rig.native.state());
    await initialization;
    await flushDesktopEvents();
    final configurations =
        rig.native.calls.where((call) => call.$1 == 'configure').toList();
    expect(configurations, hasLength(2));
    expect(configurations.first.$2!['roundedWindowCorners'], isTrue);
    expect(configurations.last.$2!['roundedWindowCorners'], isFalse);
  });
}
