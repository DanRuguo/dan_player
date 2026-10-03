import 'dart:async';
import 'dart:ui' show AccessibilityFeatures;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:dan_player/lyric_display_coordinator.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/taskbar_lyric_service.dart';
import 'package:dan_player/taskbar_lyrics_preferences.dart';
import 'package:dan_player/taskbar_lyrics_publisher.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';

class _Features extends Fake implements AccessibilityFeatures {
  _Features({this.reduced = false, this.disabled = false});
  final bool reduced;
  final bool disabled;
  @override
  bool get reduceMotion => reduced;
  @override
  bool get disableAnimations => disabled;
}

class _Audio extends Fake implements Audio {
  @override
  String get displayTitle => 'current';
}

class _Playback extends ChangeNotifier implements PlaybackService {
  final positions = StreamController<double>.broadcast();
  final states = StreamController<PlayerState>.broadcast();
  @override
  final ValueNotifier<Object> playbackIntent = ValueNotifier<Object>(0);
  @override
  final playbackRate = ValueNotifier(1.0);
  @override
  final resolvingAudioPath = ValueNotifier<String?>(null);
  @override
  final isBuffering = ValueNotifier(false);
  @override
  final isChangingOutput = ValueNotifier(false);
  @override
  final playlist = ValueNotifier<List<Audio>>([_Audio()]);
  @override
  final playMode = ValueNotifier(PlayMode.forward);
  @override
  final shuffle = ValueNotifier(false);
  @override
  final stopAfterCurrent = ValueNotifier(false);
  @override
  final segmentLoop = SegmentLoopController();
  @override
  Audio? nowPlaying = _Audio();
  @override
  PlayerState playerState = PlayerState.paused;
  @override
  int get playbackSessionToken => 1;
  @override
  double get position => 0;
  @override
  double get length => 12;
  @override
  Audio? get nextAutomaticQueueAudio => null;
  @override
  Stream<double> get positionStream => positions.stream;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  Future<void> cleanUp() async {
    await positions.close();
    await states.close();
    playbackIntent.dispose();
    playbackRate.dispose();
    resolvingAudioPath.dispose();
    isBuffering.dispose();
    isChangingOutput.dispose();
    playlist.dispose();
    playMode.dispose();
    shuffle.dispose();
    stopAfterCurrent.dispose();
    segmentLoop.dispose();
    dispose();
  }
}

class _Lyrics extends ChangeNotifier implements LyricService {
  final lines = StreamController<int>.broadcast();
  @override
  Future<Lyric?> currLyricFuture = Future.value(PlainLyric('kept lyric 😀'));
  @override
  int get resolutionGeneration => 1;
  @override
  Stream<int> get lyricLineStream => lines.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  Future<void> cleanUp() async {
    await lines.close();
    dispose();
  }
}

class _Rig {
  _Rig({
    bool enabled = true,
    bool ready = true,
    bool Function()? animationsAllowed,
    bool Function()? layoutAnimationsAllowed,
  }) {
    readiness.value = ready;
    preferences.value = PlayerExperiencePreferences(taskbarLyrics: enabled);
    final facade = PlayService.forTesting(
      readiness: facadeReady,
      createPlayback: (_) => playback,
      createLyric: (_) => lyrics,
      createDesktopLyric: (_) => throw StateError('Unexpected desktop helper'),
    );
    taskbar = TaskbarLyricService(
      preferences: preferences,
      playbackReady: readiness,
      createSource: () {
        factoryCalls++;
        return source = playerTaskbarLyricSourceForTesting(facade);
      },
      coordinator: LyricDisplayCoordinator(),
      savePreferences: () async {},
      rendering: rendering,
      animationsAllowed: animationsAllowed,
      layoutAnimationsAllowed: layoutAnimationsAllowed,
    );
    theme = ThemeProvider.forTesting(
        seedColor: const Color(0xff123456),
        dynamicThemeEnabled: () => false,
        loadArtwork: (_) async => null,
        extractScheme: (_, brightness) async => ColorScheme.fromSeed(
            seedColor: Colors.blue, brightness: brightness));
    theme.lightScheme =
        theme.lightScheme.copyWith(primary: const Color(0xff123456));
    desktop.value = readyDesktopPlayback;
    integration = DesktopIntegration.forTesting(
      native: native,
      window: FakeDesktopWindow(native),
      playback: desktop,
      preferences: preferences,
      taskbarLyrics: taskbar,
      themeProvider: theme,
      syncAppearance: true,
    );
  }

  final native = FakeDesktopNative();
  final desktop = FakeDesktopPlayback();
  final preferences = ValueNotifier(const PlayerExperiencePreferences());
  final readiness = ValueNotifier(false);
  final facadeReady = PlaybackReadiness();
  final rendering = ValueNotifier<Object?>(null);
  final playback = _Playback();
  final lyrics = _Lyrics();
  late final ThemeProvider theme;
  late final TaskbarLyricService taskbar;
  late final DesktopIntegration integration;
  TaskbarLyricSource? source;
  int factoryCalls = 0;

  List<Map<String, Object>> get frames => native.calls
      .where((call) => call.$1 == 'setTaskbarLyrics')
      .map((call) => call.$2!)
      .toList();

  void changeAppearance(TaskbarLyricsPreferences value) =>
      preferences.value = preferences.value.copyWith(taskbarAppearance: value);

  Future<void> initialize() async {
    await integration.initialize(onExit: () async {});
    await flushDesktopEvents();
  }

  Future<void> dispose() async {
    await integration.dispose();
    await lyrics.cleanUp();
    await playback.cleanUp();
    desktop.dispose();
    preferences.dispose();
    readiness.dispose();
    facadeReady.dispose();
    rendering.dispose();
    theme.dispose();
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'playback button follows real source states and existing toggle transport',
      () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    await rig.initialize();
    expect(rig.frames.first['playbackButtonEnabled'], false);
    expect(rig.frames.last['showPauseIndicator'], true);
    expect(rig.frames.last['playbackButtonEnabled'], true);
    final document = rig.lyrics.currLyricFuture;
    for (final state in const [
      PlayerState.playing,
      PlayerState.paused,
      PlayerState.pausedDevice,
      PlayerState.stopped,
      PlayerState.completed,
    ]) {
      rig.playback.playerState = state;
      rig.playback.states.add(state);
      await flushDesktopEvents();
      expect(rig.frames.last['playbackButtonEnabled'], true);
      expect(rig.frames.last['playing'], state == PlayerState.playing);
      expect(rig.frames.last['paused'],
          state == PlayerState.paused || state == PlayerState.pausedDevice);
      await rig.native.emit('action', 'taskbarPlayPause');
    }
    expect(rig.desktop.actions, List.filled(5, 'toggle'));
    for (final state in const [PlayerState.stalled, PlayerState.unknown]) {
      rig.playback.playerState = state;
      rig.playback.states.add(state);
      await rig.native.emit('action', 'taskbarPlayPause');
      expect(rig.desktop.actions.length, 5,
          reason: 'A stale enabled frame cannot toggle unavailable transport');
      await flushDesktopEvents();
      expect(rig.frames.last['playbackButtonEnabled'], false);
    }
    expect(identical(rig.lyrics.currLyricFuture, document), true);
    expect(rig.factoryCalls, 1);
  });

  test('playback button rejects late busy preference and shutdown clicks',
      () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    await rig.initialize();
    final identity = rig.frames.last['sourceIdentity'];
    final revision = rig.frames.last['timelineRevision'];
    for (final busy in [
      rig.playback.isBuffering,
      rig.playback.isChangingOutput
    ]) {
      busy.value = true;
      await rig.native.emit('action', 'taskbarPlayPause');
      expect(rig.desktop.actions, isEmpty);
      await flushDesktopEvents();
      expect(rig.frames.last['playbackButtonEnabled'], false);
      busy.value = false;
      await flushDesktopEvents();
      expect(rig.frames.last['playbackButtonEnabled'], true);
    }
    rig.playback.resolvingAudioPath.value = 'opening.wav';
    await rig.native.emit('action', 'taskbarPlayPause');
    expect(rig.desktop.actions, isEmpty);
    await flushDesktopEvents();
    expect(rig.frames.last['playbackButtonEnabled'], false);
    await rig.native.emit('action', 'toggle');
    expect(rig.desktop.actions, ['toggle'],
        reason: 'The existing tray toggle policy is preserved');
    rig.playback.resolvingAudioPath.value = null;
    await flushDesktopEvents();
    expect(rig.frames.last['playbackButtonEnabled'], true);
    expect(rig.frames.last['timelineRevision'], revision);
    expect(rig.frames.last['sourceIdentity'], isNot(identity),
        reason:
            'Source opening legitimately revalidates the retained document');
    rig.changeAppearance(
        const TaskbarLyricsPreferences(showPauseIndicator: false));
    await rig.native.emit('action', 'taskbarPlayPause');
    expect(rig.desktop.actions, ['toggle']);
    await flushDesktopEvents();
    expect(rig.frames.last['showPauseIndicator'], false);
    expect(rig.frames.last['playbackButtonEnabled'], false);
    rig.changeAppearance(const TaskbarLyricsPreferences());
    await flushDesktopEvents();
    rig.readiness.value = false;
    await rig.native.emit('action', 'taskbarPlayPause');
    expect(rig.desktop.actions, ['toggle']);
    rig.readiness.value = true;
    await flushDesktopEvents();
    rig.desktop.value = const DesktopPlaybackSnapshot(
        ready: true, hasTrack: true, buffering: true);
    await rig.native.emit('action', 'taskbarPlayPause');
    expect(rig.desktop.actions, ['toggle']);
    rig.desktop.value = readyDesktopPlayback;
    rig.playback.nowPlaying = null;
    rig.playback.playlist.value = [_Audio()];
    await rig.native.emit('action', 'taskbarPlayPause');
    expect(rig.desktop.actions, ['toggle']);
    await flushDesktopEvents();
    expect(rig.frames.last['playbackButtonEnabled'], false);
    rig.playback.nowPlaying = _Audio();
    rig.playback.playlist.value = [_Audio()];
    await flushDesktopEvents();
    await rig.native.emit('action', 'taskbarPlayPause');
    expect(rig.desktop.actions, ['toggle', 'toggle']);
    rig.preferences.value =
        rig.preferences.value.copyWith(taskbarLyrics: false);
    await rig.native.emit('action', 'taskbarPlayPause');
    expect(rig.desktop.actions, ['toggle', 'toggle']);
    await flushDesktopEvents();
    expect(rig.frames.last, {'enabled': false, 'text': ''});
    await rig.integration.dispose();
    await rig.integration.dispatchAction('taskbarPlayPause');
    expect(rig.taskbar.runtimeCanPlayPause, false);
    expect(rig.desktop.actions, ['toggle', 'toggle']);
  });

  test(
      'next lyric visibility preserves authored data during paused appearance changes',
      () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    addTearDown(binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    rig.lyrics.currLyricFuture = Future.value(Qrc.fromQrcText(
        '[0,5000]当前 😀(0,5000)\n[5000,5000]Next e\u0301(5000,5000)'));
    final document = rig.lyrics.currLyricFuture;
    await rig.initialize();
    expect(rig.frames.first['showNextLyric'], true,
        reason: 'The capability handshake also carries the default');
    final initial = rig.frames.last;
    expect(initial['showNextLyric'], true);
    expect(initial['text'], '当前 😀');
    expect(initial['nextText'], 'Next e\u0301');
    expect(initial['words'], isNotEmpty);
    expect(initial['paused'], true);

    for (final reduced in [false, true]) {
      binding.platformDispatcher.accessibilityFeaturesTestValue =
          _Features(reduced: reduced);
      rig.changeAppearance(
          const TaskbarLyricsPreferences(showNextLyric: false));
      await flushDesktopEvents();
      final single = rig.frames.last;
      expect(single['showNextLyric'], false);
      expect(single['nextText'], initial['nextText'],
          reason:
              'Only native visibility changes; next-line ownership remains');
      expect(single['text'], initial['text']);
      expect(identical(single['words'], initial['words']), true);
      expect(single['sourceIdentity'], initial['sourceIdentity']);
      expect(single['lineIdentity'], initial['lineIdentity']);
      expect(single['timelineRevision'], initial['timelineRevision']);
      expect(single['animate'], !reduced);
      expect(single['animateLayout'], !reduced);
      rig.changeAppearance(const TaskbarLyricsPreferences(showNextLyric: true));
      await flushDesktopEvents();
      final dual = rig.frames.last;
      expect(dual['showNextLyric'], true);
      expect(dual['nextText'], initial['nextText']);
      expect(identical(dual['words'], initial['words']), true);
      expect(dual['sourceIdentity'], initial['sourceIdentity']);
      expect(dual['timelineRevision'], initial['timelineRevision']);
      expect(identical(rig.lyrics.currLyricFuture, document), true);
    }
    expect(rig.factoryCalls, 1);
    expect(binding.transientCallbackCount, 0);
  });

  test('paused layout and lyric motion gates remain independent and accessible',
      () async {
    var lyrics = true, layout = false;
    final rig = _Rig(
        animationsAllowed: () => lyrics, layoutAnimationsAllowed: () => layout);
    addTearDown(rig.dispose);
    addTearDown(binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await rig.initialize();
    expect(rig.frames.first['animate'], true);
    expect(rig.frames.first['animateLayout'], false);
    final initial = rig.frames.last;
    expect(initial['paused'], true);
    expect(initial['animate'], true);
    expect(initial['animateLayout'], false);

    lyrics = false;
    layout = true;
    rig.rendering.value = 1;
    await flushDesktopEvents();
    expect(rig.frames.last['animate'], false);
    expect(rig.frames.last['animateLayout'], true,
        reason: 'Paused geometry motion uses layout rather than lyric motion');
    rig.changeAppearance(const TaskbarLyricsPreferences(
        position: TaskbarLyricPosition.end, strokeEnabled: true));
    await flushDesktopEvents();
    expect(rig.frames.last['placement'], 'end');
    expect(rig.frames.last['animateLayout'], true);
    expect(rig.frames.last['timelineRevision'], initial['timelineRevision']);
    expect(rig.frames.last['sourceIdentity'], initial['sourceIdentity']);
    expect(identical(rig.frames.last['words'], initial['words']), true);

    for (final features in [
      _Features(reduced: true),
      _Features(disabled: true),
    ]) {
      binding.platformDispatcher.accessibilityFeaturesTestValue = features;
      await flushDesktopEvents();
      expect(rig.frames.last['animate'], false);
      expect(rig.frames.last['animateLayout'], false);
    }
    binding.platformDispatcher.accessibilityFeaturesTestValue = _Features();
    await flushDesktopEvents();
    expect(rig.frames.last['animate'], false);
    expect(rig.frames.last['animateLayout'], true);
    lyrics = true;
    layout = false;
    rig.rendering.value = 2;
    await flushDesktopEvents();
    expect(rig.frames.last['animate'], true);
    expect(rig.frames.last['animateLayout'], false);
    expect(rig.frames.last['timelineRevision'], initial['timelineRevision']);
    expect(binding.transientCallbackCount, 0);
    expect(rig.factoryCalls, 1);
  });

  test('actual bridge projects independent taskbar options without clock reset',
      () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    final desktopAppearance = AppSettings.instance.desktopLyricAppearance;
    final original = desktopAppearance.value;
    addTearDown(() => desktopAppearance.value = original);
    await rig.initialize();
    final initial = rig.frames.last;
    expect(initial['colorScheme'], 'player');
    expect(initial['showNextButton'], false);
    expect(initial['nextButtonEnabled'], false);
    expect(initial['strokeEnabled'], false);
    final initialCount = rig.frames.length;
    desktopAppearance.value =
        original.copyWith(strokeEnabled: !original.strokeEnabled);
    await flushDesktopEvents();
    expect(rig.frames.length, initialCount,
        reason: 'Desktop outline no longer subscribes or changes this surface');

    rig.changeAppearance(const TaskbarLyricsPreferences(
        colorScheme: TaskbarLyricColorScheme.system,
        strokeEnabled: true,
        showNextButton: true,
        showNextTrack: false));
    await flushDesktopEvents();
    final changed = rig.frames.last;
    expect(changed['colorScheme'], 'system');
    expect(changed['strokeEnabled'], true);
    expect(changed['showNextButton'], true);
    expect(changed['nextButtonEnabled'], true);
    expect(changed['nextTrackText'], '');
    expect(changed['playing'], false);
    expect(changed['paused'], true);
    expect(changed['sourceIdentity'], initial['sourceIdentity']);
    expect(changed['lineIdentity'], initial['lineIdentity']);
    expect(changed['timelineRevision'], initial['timelineRevision']);
    expect(identical(changed['words'], initial['words']), true);
    expect(rig.factoryCalls, 1);

    rig.theme.lightScheme =
        rig.theme.lightScheme.copyWith(primary: const Color(0xff654321));
    rig.theme.notifyListeners();
    await flushDesktopEvents();
    expect(rig.frames.last['accent'], 0xff654321);
    expect(rig.frames.last['colorScheme'], 'system');
    expect(rig.frames.last['timelineRevision'], initial['timelineRevision']);
    rig.changeAppearance(const TaskbarLyricsPreferences(showNextButton: true));
    await flushDesktopEvents();
    expect(rig.frames.last['colorScheme'], 'player');
    expect(rig.frames.last['strokeEnabled'], false);
    expect(rig.frames.last['accent'], 0xff654321);
    expect(rig.frames.last['sourceIdentity'], initial['sourceIdentity']);
  });

  test('taskbar next uses live source guard and existing next transport',
      () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    rig.changeAppearance(const TaskbarLyricsPreferences(
        showNextButton: true, showNextTrack: false));
    await rig.initialize();
    expect(rig.frames.last['nextTrackText'], '');
    expect(rig.frames.last['nextButtonEnabled'], true);
    rig.playback.segmentLoop.setStart(0, 12);
    rig.playback.segmentLoop.setEnd(2, 12);
    rig.playback.segmentLoop.setEnabled(true);
    rig.playback.stopAfterCurrent.value = true;
    await rig.native.emit('action', 'taskbarNext');
    expect(rig.desktop.actions, ['next'],
        reason: 'Manual Next is independent of natural-next title or practice');

    rig.playback.resolvingAudioPath.value = 'opening.wav';
    // No microtask flush: the native button and desktop snapshot are stale.
    expect(rig.frames.last['nextButtonEnabled'], true);
    await rig.native.emit('action', 'taskbarNext');
    expect(rig.desktop.actions, ['next']);
    await rig.native.emit('action', 'next');
    expect(rig.desktop.actions, ['next', 'next'],
        reason: 'The existing tray Next can still interrupt local loading');
    await flushDesktopEvents();
    expect(rig.frames.last['nextButtonEnabled'], false);
    rig.playback.resolvingAudioPath.value = null;
    await flushDesktopEvents();
    expect(rig.frames.last['nextButtonEnabled'], true);

    for (final gate in [
      rig.playback.isBuffering,
      rig.playback.isChangingOutput
    ]) {
      gate.value = true;
      await rig.native.emit('action', 'taskbarNext');
      expect(rig.desktop.actions, ['next', 'next']);
      await flushDesktopEvents();
      expect(rig.frames.last['nextButtonEnabled'], false);
      gate.value = false;
      await flushDesktopEvents();
      expect(rig.frames.last['nextButtonEnabled'], true);
    }
    rig.playback.playerState = PlayerState.stalled;
    rig.playback.states.add(PlayerState.stalled);
    await rig.native.emit('action', 'taskbarNext');
    expect(rig.desktop.actions, ['next', 'next']);
    await flushDesktopEvents();
    expect(rig.frames.last['nextButtonEnabled'], false);
    rig.playback.playerState = PlayerState.pausedDevice;
    rig.playback.states.add(PlayerState.pausedDevice);
    await flushDesktopEvents();
    expect(rig.frames.last['nextButtonEnabled'], true);
    rig.playback.playlist.value = [];
    await rig.native.emit('action', 'taskbarNext');
    expect(rig.desktop.actions, ['next', 'next']);
    await flushDesktopEvents();
    expect(rig.frames.last['nextButtonEnabled'], false);
    rig.playback.nowPlaying = null;
    rig.playback.playlist.value = [_Audio()];
    await rig.native.emit('action', 'taskbarNext');
    expect(rig.desktop.actions, ['next', 'next']);
    await flushDesktopEvents();
    expect(rig.frames.last['nextButtonEnabled'], false,
        reason: 'Visual capability agrees with dispatch for a retained queue');
  });

  test('taskbar next also obeys desktop capabilities and ready lifecycle',
      () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    rig.changeAppearance(const TaskbarLyricsPreferences(showNextButton: true));
    await rig.initialize();
    expect(rig.taskbar.runtimeCanNext, true);
    for (final capability in const [
      DesktopPlaybackSnapshot(hasQueue: true),
      DesktopPlaybackSnapshot(ready: true),
      DesktopPlaybackSnapshot(ready: true, hasQueue: true, buffering: true),
    ]) {
      rig.desktop.value = capability;
      await rig.native.emit('action', 'taskbarNext');
    }
    expect(rig.desktop.actions, isEmpty);
    rig.desktop.value = readyDesktopPlayback;
    rig.readiness.value = false;
    await rig.native.emit('action', 'taskbarNext');
    expect(rig.desktop.actions, isEmpty);
    rig.readiness.value = true;
    await flushDesktopEvents();
    rig.changeAppearance(const TaskbarLyricsPreferences());
    await rig.native.emit('action', 'taskbarNext');
    expect(rig.desktop.actions, isEmpty);
    rig.changeAppearance(const TaskbarLyricsPreferences(showNextButton: true));
    await flushDesktopEvents();
    await rig.native.emit('action', 'taskbarNext');
    expect(rig.desktop.actions, ['next']);
    rig.preferences.value =
        rig.preferences.value.copyWith(taskbarLyrics: false);
    await rig.native.emit('action', 'taskbarNext');
    expect(rig.desktop.actions, ['next']);
    await flushDesktopEvents();
    expect(rig.frames.last, {'enabled': false, 'text': ''});
    await rig.integration.dispose();
    rig.playback.isBuffering.value = true;
    rig.playback.isChangingOutput.value = true;
    await rig.native.emit('action', 'taskbarNext');
    expect(rig.desktop.actions, ['next']);
  });

  test('off and not-ready option changes do not construct or publish source',
      () async {
    final wasInitialized = PlayService.isInitialized;
    final rig = _Rig(enabled: false, ready: false);
    addTearDown(rig.dispose);
    await rig.initialize();
    rig.changeAppearance(const TaskbarLyricsPreferences(
        colorScheme: TaskbarLyricColorScheme.system,
        strokeEnabled: true,
        showNextButton: true));
    await rig.native.emit('action', 'taskbarNext');
    await flushDesktopEvents();
    expect(rig.frames, isEmpty);
    expect(rig.factoryCalls, 0);
    expect(rig.desktop.actions, isEmpty);
    rig.preferences.value = rig.preferences.value.copyWith(taskbarLyrics: true);
    await flushDesktopEvents();
    expect(rig.frames, isEmpty);
    expect(rig.factoryCalls, 0);
    await rig.native.emit('action', 'taskbarNext');
    expect(rig.desktop.actions, isEmpty);
    rig.readiness.value = true;
    await flushDesktopEvents();
    expect(rig.factoryCalls, 1);
    expect(rig.frames.first['colorScheme'], 'system');
    expect(rig.frames.first['showNextButton'], true);
    expect(rig.frames.first['nextButtonEnabled'], false,
        reason: 'Capability handshake never enables an unattached button');
    expect(rig.frames.last['nextButtonEnabled'], true);
    expect(PlayService.isInitialized, wasInitialized);
  });
}
