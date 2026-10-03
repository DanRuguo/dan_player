import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric_display_coordinator.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/taskbar_lyric_service.dart';
import 'package:dan_player/taskbar_lyrics_preferences.dart';
import 'package:dan_player/taskbar_lyrics_publisher.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';

class _Source extends TaskbarLyricSource {
  @override
  final Future<Lyric?> lyric = Future.value(PlainLyric('current lyric'));
  @override
  int get generation => 1;
  @override
  int get session => 1;
  @override
  bool get hasTrack => true;
  @override
  double get position => 0;
  @override
  bool get playing => false;
  @override
  String get nextTrackTitle => 'Next 😀';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('actual desktop bridge keeps ARGB and independent taskbar outline',
      () async {
    final native = FakeDesktopNative();
    final playback = FakeDesktopPlayback();
    final preferences =
        ValueNotifier(const PlayerExperiencePreferences(taskbarLyrics: true));
    final readiness = ValueNotifier(true);
    final rendering = ValueNotifier<Object?>(null);
    final theme = ThemeProvider.forTesting(
        seedColor: const Color(0xff123456),
        dynamicThemeEnabled: () => false,
        loadArtwork: (_) async => null,
        extractScheme: (_, brightness) async => ColorScheme.fromSeed(
            seedColor: Colors.blue, brightness: brightness));
    theme.lightScheme =
        theme.lightScheme.copyWith(primary: const Color(0xff123456));
    final sharedAppearance = AppSettings.instance.desktopLyricAppearance;
    final original = sharedAppearance.value;
    sharedAppearance.value = DesktopLyricAppearance.defaults;
    var factoryCalls = 0;
    final taskbar = TaskbarLyricService(
      preferences: preferences,
      playbackReady: readiness,
      createSource: () {
        factoryCalls++;
        return _Source();
      },
      coordinator: LyricDisplayCoordinator(),
      savePreferences: () async {},
      rendering: rendering,
    );
    final integration = DesktopIntegration.forTesting(
      native: native,
      window: FakeDesktopWindow(native),
      playback: playback,
      preferences: preferences,
      themeProvider: theme,
      syncAppearance: true,
      taskbarLyrics: taskbar,
    );
    addTearDown(() async {
      await integration.dispose();
      sharedAppearance.value = original;
      theme.dispose();
      preferences.dispose();
      readiness.dispose();
      rendering.dispose();
      playback.dispose();
    });
    final wasInitialized = PlayService.isInitialized;
    await integration.initialize(onExit: () async {});
    await flushDesktopEvents();
    Map<String, Object> latestFrame() =>
        native.calls.lastWhere((call) => call.$1 == 'setTaskbarLyrics').$2!;
    expect(factoryCalls, 1);
    expect(latestFrame()['accent'], 0xff123456);
    expect(latestFrame()['nextTrackText'], '下一首：Next 😀');
    expect(latestFrame()['playing'], false);
    expect(latestFrame()['showPauseIndicator'], true);
    final identity = latestFrame()['sourceIdentity'];
    final revision = latestFrame()['timelineRevision'];
    expect(
        native.calls.firstWhere((call) => call.$1 == 'configure').$2!['accent'],
        0x563412,
        reason: 'The independent tray still uses COLORREF');

    preferences.value = preferences.value.copyWith(
      taskbarAppearance: const TaskbarLyricsPreferences(
          position: TaskbarLyricPosition.end,
          areaSelection: 2,
          showNextTrack: false,
          showPauseIndicator: false),
    );
    await flushDesktopEvents();
    expect(factoryCalls, 1);
    expect(latestFrame()['placement'], 'end');
    expect(latestFrame()['areaSelection'], 2);
    expect(latestFrame()['nextTrackText'], '');
    expect(latestFrame()['showPauseIndicator'], false);
    expect(latestFrame()['sourceIdentity'], identity);
    expect(latestFrame()['timelineRevision'], revision);

    sharedAppearance.value =
        sharedAppearance.value.copyWith(strokeEnabled: true);
    await flushDesktopEvents();
    expect(latestFrame()['strokeEnabled'], false);
    preferences.value = preferences.value.copyWith(
        taskbarAppearance:
            preferences.value.taskbarAppearance.copyWith(strokeEnabled: true));
    await flushDesktopEvents();
    expect(latestFrame()['strokeEnabled'], true);
    expect(latestFrame()['sourceIdentity'], identity);
    expect(latestFrame()['timelineRevision'], revision);
    expect(factoryCalls, 1);

    preferences.value = preferences.value.copyWith(taskbarLyrics: false);
    await flushDesktopEvents();
    expect(latestFrame()['enabled'], false);
    final offCount = native.calls.length;
    sharedAppearance.value =
        sharedAppearance.value.copyWith(strokeEnabled: false);
    preferences.value = preferences.value.copyWith(
        taskbarAppearance: preferences.value.taskbarAppearance
            .copyWith(position: TaskbarLyricPosition.center));
    await flushDesktopEvents();
    expect(factoryCalls, 1);
    expect(native.calls.where((call) => call.$1 == 'setTaskbarLyrics').last.$2!,
        {'enabled': false, 'text': ''});
    expect(
        native.calls
            .skip(offCount)
            .where((call) => call.$1 == 'setTaskbarLyrics'),
        isEmpty);
    expect(PlayService.isInitialized, wasInitialized);
  });

  test('layout query and events publish only valid orientation or area changes',
      () async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    await rig.initialize();
    var notices = 0;
    rig.integration.addListener(() => notices++);
    rig.native.intercept = (method, _) async =>
        method == 'getTaskbarLyricsLayout'
            ? {'vertical': true, 'areaCount': 3, 'areaIndex': 1}
            : rig.native.state();
    await rig.integration.refreshTaskbarLyricsLayout();
    expect(rig.integration.taskbarLyricsVertical, true);
    expect(rig.integration.taskbarLyricsAreaCount, 3);
    expect(rig.integration.taskbarLyricsAreaIndex, 1);
    final published = notices;
    await rig.native.emit('taskbarLyricsLayoutChanged',
        {'vertical': true, 'areaCount': 3, 'areaIndex': 1});
    expect(notices, published);
    await rig.native.emit('taskbarLyricsLayoutChanged',
        {'vertical': 'bad', 'areaCount': -1, 'areaIndex': 999});
    expect(notices, published);
    await rig.native.emit('taskbarLyricsLayoutChanged',
        {'vertical': false, 'areaCount': -1, 'areaIndex': 0});
    await rig.native.emit('taskbarLyricsLayoutChanged',
        {'vertical': false, 'areaCount': 1, 'areaIndex': 9});
    expect(notices, published);
    await rig.native.emit('taskbarLyricsLayoutChanged',
        {'vertical': false, 'areaCount': 1, 'areaIndex': 0});
    expect(rig.integration.taskbarLyricsVertical, false);
    expect(rig.integration.taskbarLyricsAreaCount, 1);
    expect(rig.integration.taskbarLyricsAreaIndex, 0);
    expect(notices, published + 1);
    await rig.integration.dispose();
    final afterClose = notices;
    await rig.integration.refreshTaskbarLyricsLayout();
    expect(notices, afterClose);
  });

  test('late layout readback cannot replace a newer native environment event',
      () async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    await rig.initialize();
    await flushDesktopEvents();
    final response = Completer<Object?>();
    rig.native.intercept = (method, _) => method == 'getTaskbarLyricsLayout'
        ? response.future
        : Future.value(rig.native.state());
    final reading = rig.integration.refreshTaskbarLyricsLayout();
    await Future<void>.delayed(Duration.zero);
    await rig.native.emit('taskbarLyricsLayoutChanged',
        {'vertical': false, 'areaCount': 2, 'areaIndex': 0});
    response.complete({'vertical': true, 'areaCount': 3, 'areaIndex': 2});
    await reading;
    expect(rig.integration.taskbarLyricsVertical, false);
    expect(rig.integration.taskbarLyricsAreaCount, 2);
    expect(rig.integration.taskbarLyricsAreaIndex, 0);
  });
}
