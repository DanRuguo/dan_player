import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/page/settings_page/desktop_integration_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';

void main() {
  Future<void> mount(WidgetTester tester, DesktopTestRig rig,
      {double width = 720,
      double scale = 1,
      Future<void> Function()? persist}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
          body: SingleChildScrollView(
              child: DesktopIntegrationSettings(
        preferences: rig.preferences,
        integration: rig.integration,
        persist: persist ?? () async {},
      ))),
    ));
  }

  testWidgets(
      'desktop settings and default visibility host do not initialize playback',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, rig);
    expect(PlayService.isInitialized, isFalse);
    expect(rig.native.calls, isEmpty);
    expect(rig.playback.starts, 0);
    expect(find.text('关闭窗口后在后台继续播放'), findsOneWidget);
    expect(find.textContaining('不在任务栏显示歌词'), findsOneWidget);
    await tester.pumpWidget(
        const MaterialApp(home: DesktopVisibilityHost(child: Text('cold'))));
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets('background preference change preserves unrelated player choices',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    rig.preferences.value = rig.preferences.value.copyWith(
        springLyrics: false, playbackRate: 1.5, desktopLyricVertical: true);
    var saves = 0;
    await mount(tester, rig, persist: () async {
      saves++;
    });
    await tester.tap(find.byKey(const ValueKey('close-to-tray-setting')));
    await tester.pumpAndSettle();
    final current = rig.preferences.value;
    expect(current.closeToTray, isTrue);
    expect(current.taskbarControls, isTrue);
    expect(current.springLyrics, isFalse);
    expect(current.desktopLyricVertical, isTrue);
    expect(current.playbackRate, 1.5);
    expect(saves, 1);
    expect(rig.native.calls, isEmpty);
  });

  testWidgets('two desktop switches in one frame retain both choices',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, rig);

    tester
        .widget<SwitchListTile>(
            find.byKey(const ValueKey('taskbar-controls-setting')))
        .onChanged!(false);
    tester
        .widget<SwitchListTile>(
            find.byKey(const ValueKey('taskbar-song-preview-setting')))
        .onChanged!(false);
    await tester.pump();

    expect(rig.preferences.value.taskbarControls, isFalse);
    expect(rig.preferences.value.taskbarSongPreview, isFalse);
  });

  testWidgets('song preview toggle preserves native buttons and persists once',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saves = 0;
    await mount(tester, rig, persist: () async {
      saves++;
    });
    await tester
        .tap(find.byKey(const ValueKey('taskbar-song-preview-setting')));
    await tester.pumpAndSettle();
    expect(rig.preferences.value.taskbarSongPreview, false);
    expect(rig.preferences.value.taskbarControls, true);
    expect(saves, 1);
    expect(rig.playback.starts, 0);
  });

  testWidgets('taskbar setting is separate and shows real persistence failure',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, rig, persist: () async => throw StateError('fake I/O'));
    await tester.tap(find.byKey(const ValueKey('taskbar-controls-setting')));
    await tester.pumpAndSettle();
    expect(rig.preferences.value.taskbarControls, isFalse);
    expect(rig.preferences.value.closeToTray, isFalse);
    expect(find.textContaining('保存桌面设置失败'), findsOneWidget);
  });

  testWidgets(
      'playback progress is independent of taskbar preview and controls',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    rig.preferences.value = rig.preferences.value
        .copyWith(taskbarControls: false, taskbarSongPreview: false);
    var saves = 0;
    await mount(tester, rig, persist: () async => saves++);
    final progress =
        find.byKey(const ValueKey('taskbar-playback-progress-setting'));
    await tester.ensureVisible(progress);
    await tester.tap(progress);
    await tester.pumpAndSettle();
    expect(rig.preferences.value.taskbarPlaybackProgress, isFalse);
    expect(rig.preferences.value.taskbarControls, isFalse);
    expect(rig.preferences.value.taskbarSongPreview, isFalse);
    expect(saves, 1);
    await tester.tap(progress);
    await tester.pumpAndSettle();
    expect(rig.preferences.value.taskbarPlaybackProgress, isTrue);
    expect(rig.preferences.value.taskbarControls, isFalse);
    expect(rig.preferences.value.taskbarSongPreview, isFalse);
    expect(saves, 2);
    expect(rig.native.calls, isEmpty);
    expect(rig.playback.starts, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  for (final width in [320.0, 440.0, 720.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('desktop settings remain reachable at $width / text $scale',
          (tester) async {
        final rig = DesktopTestRig();
        addTearDown(rig.dispose);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mount(tester, rig, width: width, scale: scale);
        expect(tester.takeException(), isNull);
        for (final key in [
          'close-to-tray-setting',
          'taskbar-controls-setting',
          'taskbar-song-preview-setting',
          'taskbar-playback-progress-setting',
        ]) {
          final tile = find.byKey(ValueKey(key));
          await tester.ensureVisible(tile);
          await tester.pumpAndSettle();
          expect(tester.getSize(tile).height, greaterThanOrEqualTo(44));
          expect(tester.widget<SwitchListTile>(tile).visualDensity,
              VisualDensity.standard);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
