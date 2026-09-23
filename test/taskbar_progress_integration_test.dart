import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/taskbar_progress.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';

class _Playback extends FakeDesktopPlayback
    implements DesktopPlaybackProgressAdapter {
  @override
  final ValueNotifier<TaskbarProgressValue> taskbarProgress =
      ValueNotifier(TaskbarProgressValue.none);
  bool enabled = false;

  @override
  void setTaskbarProgressEnabled(bool value) => enabled = value;

  @override
  void dispose() {
    taskbarProgress.dispose();
    super.dispose();
  }
}

void main() {
  testWidgets('progress is separate from metadata and remains active minimized',
      (tester) async {
    final native = FakeDesktopNative();
    final playback = _Playback();
    final prefs = ValueNotifier(const PlayerExperiencePreferences());
    final tasks = TaskbarProgress();
    final integration = DesktopIntegration.forTesting(
      native: native,
      playback: playback,
      preferences: prefs,
      window: FakeDesktopWindow(native),
      progressOperations: tasks,
    );
    await integration.initialize(onExit: () async {});
    await tester.pump();
    expect(playback.enabled, isTrue);
    final metadata = native.calls.where((c) => c.$1 == 'updatePlayback').length;
    playback.taskbarProgress.value = TaskbarProgressValue.fraction(.1);
    await tester.pump();
    native.minimized = true;
    await native.emit('stateChanged', native.state());
    expect(integration.isHidden.value, isTrue);
    for (var i = 11; i <= 50; i++) {
      playback.taskbarProgress.value = TaskbarProgressValue.fraction(i / 100);
      await tester.pump(const Duration(milliseconds: 33));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(native.calls.where((c) => c.$1 == 'updatePlayback').length, metadata,
        reason: 'position events do not rebuild tray metadata or thumbnails');
    final progress = native.calls.where((c) => c.$1 == 'setProgress').toList();
    expect(progress.length, lessThanOrEqualTo(8));
    expect(progress.last.$2!['completed'], 500);
    playback.taskbarProgress.value =
        TaskbarProgressValue.fraction(.5, paused: true);
    await tester.pump();
    final pausedCount = native.calls.length;
    await tester.pump(const Duration(seconds: 5));
    expect(native.calls.length, pausedCount);
    expect(tester.binding.transientCallbackCount, 0);
    await integration.dispose();
    expect(
        native.calls
            .any((c) => c.$1 == 'setProgress' && c.$2!['state'] == 'none'),
        isTrue);
    playback.dispose();
    prefs.dispose();
    tasks.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'playback switch does not suppress jobs or buffering and shutdown clears',
      (tester) async {
    final native = FakeDesktopNative();
    final playback = _Playback();
    final prefs = ValueNotifier(const PlayerExperiencePreferences());
    final tasks = TaskbarProgress();
    final integration = DesktopIntegration.forTesting(
      native: native,
      playback: playback,
      preferences: prefs,
      window: FakeDesktopWindow(native),
      progressOperations: tasks,
    );
    await integration.initialize(onExit: () async {});
    await tester.pump();
    playback.taskbarProgress.value = TaskbarProgressValue.fraction(.4);
    await tester.pump();
    Map<String, Object> latest() =>
        native.calls.lastWhere((c) => c.$1 == 'setProgress').$2!;
    prefs.value = prefs.value.copyWith(taskbarPlaybackProgress: false);
    await tester.pump();
    expect(playback.enabled, isFalse);
    expect(latest()['state'], 'none');
    final task = tasks.begin();
    await tester.pump();
    expect(latest()['state'], 'indeterminate');
    task.update(.75);
    await tester.pump();
    expect(latest()['completed'], 750);
    task.dispose();
    await tester.pump();
    expect(latest()['state'], 'none');
    playback.taskbarProgress.value = TaskbarProgressValue.indeterminate;
    await tester.pump();
    expect(latest()['state'], 'indeterminate');
    await integration.dispose();
    expect(latest()['state'], 'none');
    final count = native.calls.length;
    playback.taskbarProgress.value = TaskbarProgressValue.fraction(.9);
    await tester.pump(const Duration(seconds: 1));
    expect(native.calls.length, count);
    playback.dispose();
    prefs.dispose();
    tasks.dispose();
  });

  testWidgets(
      'native recovery resends the current state without changing playback',
      (tester) async {
    final native = FakeDesktopNative();
    final playback = _Playback();
    final prefs = ValueNotifier(const PlayerExperiencePreferences());
    final tasks = TaskbarProgress();
    final integration = DesktopIntegration.forTesting(
      native: native,
      playback: playback,
      preferences: prefs,
      window: FakeDesktopWindow(native),
      progressOperations: tasks,
    );
    await integration.initialize(onExit: () async {});
    await tester.pump();
    playback.taskbarProgress.value = TaskbarProgressValue.fraction(.3);
    await tester.pump();
    native.taskbarAvailable = false;
    await native.emit('stateChanged', native.state());
    native.taskbarAvailable = true;
    await native.emit('stateChanged', native.state());
    await tester.pump();
    final progress = native.calls.where((c) => c.$1 == 'setProgress').toList();
    expect(progress.length, 2);
    expect(progress.first.$2, progress.last.$2);
    expect(playback.actions, isEmpty);
    await integration.dispose();
    playback.dispose();
    prefs.dispose();
    tasks.dispose();
  });
}
