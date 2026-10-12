import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/playback_transition_preferences.dart';
import 'package:dan_player/play_service/replay_gain.dart';
import 'package:dan_player/src/bass/bass.dart';
import 'package:dan_player/src/bass/bass_mix.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/src/bass/bass_tempo.dart';
import 'package:dan_player/src/rust/api/smtc_flutter.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/music_category_fixtures.dart';

/// The real player, tempo processing and automatic service adoption, with a
/// decoding mixer on NoSound device 0. Shared-endpoint cases require a separate
/// opt-in and silence only this process's own output before it can start.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final runtime = Platform.environment['DAN_PLAYER_TRANSITION_BASS_DIR'];
  final skip = !Platform.isWindows || runtime == null
      ? 'Set DAN_PLAYER_TRANSITION_BASS_DIR to the complete device-0 runtime.'
      : false;
  final sharedSkip = skip != false
      ? skip
      : Platform.environment['DAN_PLAYER_TRANSITION_SHARED_DEVICE_TEST'] != '1'
          ? 'Opt in with DAN_PLAYER_TRANSITION_SHARED_DEVICE_TEST=1 for a silent shared endpoint.'
          : false;
  const provider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late _NativePlayer fixture;

  setUpAll(() async {
    if (skip != false) return;
    final temporary = p.normalize(Directory.systemTemp.absolute.path);
    if (!temporary
        .replaceAll('\\', '/')
        .toLowerCase()
        .contains('/tool/qa-local/')) {
      throw StateError('TEMP must be a workspace QA directory.');
    }
    directory =
        await Directory(temporary).createTemp('real-transition-player-');
    messenger.setMockMethodCallHandler(provider, (_) async => directory.path);
    expect(p.isWithin(directory.path, (await getAppDataDir()).path), isTrue);
    AppSettings.instance.dynamicTheme = false;
    AppPreference.instance.playbackPref
      ..playMode = PlayMode.forward
      ..shuffle = false
      ..volumeDsp = 1;
    for (final entry in [('a', .25), ('b', .5), ('c', .75)]) {
      await File(p.join(directory.path, '${entry.$1}.wav'))
          .writeAsBytes(_wave(entry.$2, 96000));
    }
  });
  tearDownAll(() {
    if (skip == false) messenger.setMockMethodCallHandler(provider, null);
  });
  setUp(() {
    if (skip == false) fixture = _NativePlayer(runtime!, directory);
  });
  tearDown(() async {
    if (skip != false) return;
    await fixture.close();
    AppSettings.instance.playbackTransitions.value =
        const PlaybackTransitionPreferences();
  });

  test(
      'real BassPlayer FIFO adopts its decoded successor without silent frames',
      () async {
    await fixture.open();
    fixture.expectSource(fixture.read(4800).skip(480), 'a', startFrame: 240);
    final mixer = fixture.player.nativeMixerHandle;
    expect(await fixture.prepare('b', 'next'), isTrue);
    expect(fixture.player.preparedSourceIdentity, 'next');
    fixture.expectSource(fixture.read(91200), 'a', startFrame: 4800);
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(fixture.events.where((event) => event.completed), isEmpty,
        reason: 'Decode EOF alone must not adopt an inaudible queued source.');
    fixture.expectSource(fixture.read(480), 'b');
    await _until(() => fixture.events.any((event) => event.completed));
    expect(fixture.player.takePreparedSource('other'), isFalse);
    expect(fixture.player.takePreparedSource('next'), isTrue);
    expect(fixture.player.nativeMixerHandle, mixer);
    expect(fixture.player.position, closeTo(.01, .0001));
    expect(fixture.player.length, closeTo(2, .0001));
    expect(fixture.player.preparedSourceIdentity, isNull);
    fixture.expectSource(fixture.read(4800), 'b', startFrame: 480);
  }, skip: skip);

  test('real BassPlayer handoff keeps the audible crossfade tail until EOF',
      () async {
    await fixture.open(crossfade: true);
    fixture.read(4800);
    expect(await fixture.prepare('b', 'next'), isTrue);
    fixture.expectSource(fixture.read(67200), 'a', startFrame: 4800);
    fixture.expectFade(fixture.read(6000), startFrame: 0);
    await _until(() => fixture.events.any((event) => event.completed));
    final mixer = fixture.player.nativeMixerHandle;
    expect(fixture.player.takePreparedSource('next'), isTrue);
    expect(fixture.player.position, closeTo(.125, .0001));
    expect(await fixture.prepare('c', 'third'), isFalse,
        reason:
            'An audible previous tail must bound preparation to one source.');
    fixture.expectFade(fixture.read(18000), startFrame: 6000);
    fixture.expectSource(fixture.read(2400), 'b', startFrame: 24000);
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(await fixture.prepare('c', 'third'), isTrue);
    expect(fixture.player.nativeMixerHandle, mixer);
  }, skip: skip);

  for (final edit in [
    'disabled band edit',
    'disabled curve edit',
    'unchanged enabled band',
    'unchanged enabled curve',
  ]) {
    final enabled = edit.startsWith('unchanged');
    void applyGainEdit() {
      if (edit.endsWith('band') || edit == 'disabled band edit') {
        fixture.player.setEqBandGain(0, enabled ? 0 : 3);
      } else {
        fixture.player.setEqGains(List.filled(10, enabled ? 0 : 3));
      }
      expect(fixture.player.eqEnabled, enabled);
      expect(fixture.player.eqGains.first, enabled ? 0 : 3);
    }

    test('native $edit retains the prepared FIFO source', () async {
      if (enabled) expect(fixture.player.setEqEnabled(true), isTrue);
      await fixture.open();
      fixture.read(4800);
      expect(await fixture.prepare('b', 'next'), isTrue);
      final sources = fixture.mixerSources();
      expect(sources, hasLength(2));
      applyGainEdit();
      expect(fixture.player.preparedSourceIdentity, 'next',
          reason: 'An inaudible EQ edit must not reopen the next decoder.');
      expect(fixture.mixerSources(), unorderedEquals(sources));
      fixture.expectSource(fixture.read(91200), 'a', startFrame: 4800);
      fixture.expectSource(fixture.read(480), 'b');
      await _until(() => fixture.events.any((event) => event.completed));
      expect(fixture.player.takePreparedSource('next'), isTrue);
      fixture.expectSource(fixture.read(4800), 'b', startFrame: 480);
    }, skip: skip);

    test('native $edit preserves the already adopted crossfade PCM', () async {
      if (enabled) expect(fixture.player.setEqEnabled(true), isTrue);
      await fixture.open(crossfade: true);
      fixture.read(4800);
      expect(await fixture.prepare('b', 'next'), isTrue);
      fixture.read(67200);
      fixture.expectFade(fixture.read(6000), startFrame: 0);
      await _until(() => fixture.events.any((event) => event.completed));
      expect(fixture.player.takePreparedSource('next'), isTrue);
      expect(fixture.player.position, closeTo(.125, .0001));
      final sources = fixture.mixerSources();
      expect(sources, hasLength(2));
      applyGainEdit();
      stdout.writeln('native inaudible EQ edit=$edit '
          'tailSourcesBefore=${sources.length} '
          'tailSourcesAfter=${fixture.mixerSources().length}');
      fixture.expectFade(fixture.read(18000), startFrame: 6000);
      expect(fixture.mixerSources(), unorderedEquals(sources),
          reason: 'Saving disabled/unchanged EQ cannot cut the audible tail.');
      fixture.expectSource(fixture.read(2400), 'b', startFrame: 24000);
      await Future<void>.delayed(const Duration(milliseconds: 45));
      expect(await fixture.prepare('c', 'third'), isTrue,
          reason: 'The original tail still retires normally at EOF.');
    }, skip: skip);
  }

  test('a superseded real preparation cannot replace a requested source',
      () async {
    await fixture.open();
    var current = true;
    final old = fixture.player.prepareNextSource(fixture.file('b'),
        identity: 'retired', rate: 1, pitch: 0, stillCurrent: () => current);
    current = false;
    expect(await fixture.player.setSource(fixture.file('c')), isTrue);
    expect(await old, isFalse);
    expect(fixture.player.preparedSourceIdentity, isNull);
    expect(fixture.player.takePreparedSource('retired'), isFalse);
    fixture.player.start();
    fixture.expectSource(fixture.read(4800).skip(480), 'c', startFrame: 240);
    await fixture.player.waitForPendingFileOpen(fixture.file('b'));
    expect(fixture.player.outputDiagnostics()['nextSourcePrepared'], isFalse);
  }, skip: skip);

  for (final command in ['pause', 'seek']) {
    test('real $command retires a partially audible next source and its fade',
        () async {
      void applyCommand() {
        if (command == 'pause') {
          fixture.player.pause();
          final before = fixture.player.position;
          fixture.expectSamples(fixture.read(2400), 0);
          expect(fixture.player.position, before);
          expect(fixture.player.playerState, PlayerState.paused);
          fixture.player.start();
        } else {
          fixture.player.seek(.5);
          expect(fixture.player.position, closeTo(.5, .0001));
        }
      }

      await fixture.open(crossfade: true);
      fixture.read(78000);
      applyCommand();
      final withoutTransition = fixture.read(2400);
      await fixture.open(crossfade: true);
      fixture.read(4800);
      expect(await fixture.prepare('b', 'next'), isTrue);
      fixture.read(73200);
      applyCommand();
      expect(fixture.player.preparedSourceIdentity, isNull);
      expect(fixture.player.takePreparedSource('next'), isFalse);
      fixture.expectAgainst(fixture.read(2400), withoutTransition);
      await Future<void>.delayed(const Duration(milliseconds: 45));
      expect(fixture.events.where((event) => event.completed), isEmpty);
    }, skip: skip);
  }

  test('real BASS_FX tempo changes the FIFO output duration independently',
      () async {
    expect(fixture.player.supportsPlaybackRate, isTrue);
    expect(fixture.player.setPlaybackRate(2), isTrue);
    await fixture.open();
    fixture.expectSource(fixture.read(4800).skip(480), 'a',
        startFrame: 240, rate: 2);
    expect(fixture.player.position, closeTo(.2, .002));
    expect(await fixture.prepare('b', 'next', rate: 1), isTrue);
    fixture.expectSource(fixture.read(43200), 'a', startFrame: 4800, rate: 2);
    fixture.expectSource(fixture.read(480), 'b');
    await _until(() => fixture.events.any((event) => event.completed));
    expect(fixture.player.takePreparedSource('next'), isTrue);
    expect(fixture.player.playbackRate, 1);
    expect(fixture.player.position, closeTo(.01, .0001));
    fixture.expectSource(fixture.read(4800), 'b', startFrame: 480);
  }, skip: skip);

  test(
      'native pitch ReplayGain and EQ commands withdraw only the held successor',
      () async {
    for (final command in ['pitch', 'replayGain', 'equalizer']) {
      void applyCommand() {
        switch (command) {
          case 'pitch':
            expect(fixture.player.setPlaybackPitch(2), isTrue);
            expect(fixture.player.setPlaybackPitch(0), isTrue);
          case 'replayGain':
            expect(
                fixture.player.configureReplayGain(const ReplayGainPreferences(
                    mode: ReplayGainMode.track, fallbackGainDb: -6)),
                isTrue);
            expect(
                fixture.player
                    .configureReplayGain(const ReplayGainPreferences()),
                isTrue);
          case 'equalizer':
            expect(fixture.player.setEqEnabled(true), isTrue);
            expect(fixture.player.setEqEnabled(false), isTrue);
        }
      }

      await fixture.open();
      fixture.read(4800);
      applyCommand();
      fixture.read(4800);
      final withoutTransition = fixture.read(4800);
      await fixture.open();
      fixture.read(4800);
      expect(await fixture.prepare('b', command), isTrue);
      applyCommand();
      expect(fixture.player.preparedSourceIdentity, isNull);
      expect(fixture.player.takePreparedSource(command), isFalse);
      expect(fixture.player.playerState, PlayerState.playing);
      fixture.read(4800); // Allow the existing native attribute ramp to settle.
      fixture.expectAgainst(fixture.read(4800), withoutTransition);
    }
    expect(await fixture.prepare('b', 'held'), isTrue);
    expect(fixture.player.freeSourceIfPath(fixture.file('b')), isTrue);
    expect(fixture.player.hasSource, isTrue);
    expect(fixture.player.preparedSourceIdentity, isNull);
    expect(fixture.player.freeSourceIfPath(fixture.file('a')), isTrue);
    expect(fixture.player.hasSource, isFalse);
  }, skip: skip);

  for (final crossfade in [false, true]) {
    test(
        'real PlaybackService automatically takes its native prepared source crossfade=$crossfade',
        () async {
      final preferences = PlaybackTransitionPreferences(
          mode: crossfade
              ? PlaybackTransitionMode.crossfade
              : PlaybackTransitionMode.gapless,
          crossfadeSeconds: .5);
      fixture.player.configureTransitions(preferences);
      AppSettings.instance.playbackTransitions.value = preferences;
      final readiness = PlaybackReadiness();
      final facade = PlayService.forTesting(
          readiness: readiness,
          createPlayback: (owner) => PlaybackService.forTesting(owner,
              player: fixture.player, smtc: _Media(), applyAudioTheme: (_) {}),
          createDesktopLyric: (_) => _Helper(),
          createLyric: (_) => _Lyrics());
      final service = facade.playbackService;
      final a =
          CategoryTestAudio('native-a', path: fixture.file('a'), duration: 2);
      final b =
          CategoryTestAudio('native-b', path: fixture.file('b'), duration: 2);
      try {
        expect(await service.playQueue(0, [a, b]), isTrue);
        await _until(() => fixture.player.preparedSourceIdentity != null);
        // Let the service commit its completed preparation plan's microtask.
        await Future<void>.delayed(Duration.zero);
        final mixer = fixture.player.nativeMixerHandle;
        if (crossfade) {
          fixture.expectSource(fixture.read(72000).skip(480), 'a',
              startFrame: 240);
          fixture.expectFade(fixture.read(6000), startFrame: 0);
        } else {
          fixture.expectSource(fixture.read(96000).skip(480), 'a',
              startFrame: 240);
          fixture.expectSource(fixture.read(480), 'b');
        }
        await _until(() => service.nowPlaying == b && service.canEditQueue);
        expect(service.playlistIndex, 1);
        expect(fixture.player.nativeMixerHandle, mixer);
        expect(fixture.player.preparedSourceIdentity, isNull);
        expect(service.position, closeTo(crossfade ? .125 : .01, .0001),
            reason:
                'Adoption must preserve decoded next samples rather than reopen at zero.');
        if (crossfade) {
          fixture.expectFade(fixture.read(18000), startFrame: 6000);
        }
        fixture.expectSource(fixture.read(2400), 'b',
            startFrame: crossfade ? 24000 : 480);
        expect(service.playerState, PlayerState.playing);
      } finally {
        await facade.close();
        service.dispose();
        readiness.dispose();
      }
    }, skip: skip);
  }

  for (final failedPreparation in [false, true]) {
    test(
        'silent shared output drains the final source failedPreparation=$failedPreparation',
        () async {
      await fixture.close();
      fixture = _NativePlayer(runtime!, directory, offlineOutput: false);
      // Only this player's output is silent. No system volume, endpoint choice
      // or persisted setting is changed by the explicit opt-in fixture.
      fixture.player.setVolumeDsp(0);
      await fixture.open();
      final mixer = fixture.player.nativeMixerHandle;
      expect(fixture.player.effectiveVolumeDsp, 0);
      if (failedPreparation) {
        expect(await fixture.prepare('missing', 'invalid'), isFalse);
      } else {
        expect(await fixture.prepare('b', 'next'), isTrue);
        await _until(() => fixture.events.any((event) => event.completed),
            maxTurns: 2500);
        expect(fixture.player.takePreparedSource('next'), isTrue);
        expect(fixture.player.nativeMixerHandle, mixer);
      }
      final completedBefore = failedPreparation ? 0 : 1;
      final endByte = (failedPreparation ? 2 : 4) * 48000 * 8;
      await _until(() => fixture.mixerPosition(decoding: true) >= endByte,
          maxTurns: 2500);
      final decoded = fixture.mixerPosition(decoding: true);
      final played = fixture.mixerPosition();
      expect(decoded, greaterThan(played),
          reason: 'The fixture must expose actual playable output backlog.');
      expect(played, lessThan(endByte));
      expect(fixture.events.where((event) => event.completed),
          hasLength(completedBefore),
          reason: 'The final source must not complete at decoder EOF.');
      await _until(
          () =>
              fixture.events.where((event) => event.completed).length >
              completedBefore,
          maxTurns: 2500);
      final playedAtCompletion = fixture.mixerPosition();
      expect(playedAtCompletion, greaterThanOrEqualTo(endByte));
      expect(fixture.player.nativeMixerHandle, mixer);
      expect(fixture.player.position, closeTo(2, .0001));
      expect(fixture.player.volumeDsp, 0);
      stdout
          .writeln('silent shared native failedPreparation=$failedPreparation '
              'decodeAtEOF=$decoded playedAtEOF=$played sourceEnd=$endByte '
              'playedAtCompletion=$playedAtCompletion');
    }, skip: sharedSkip);
  }

  test('silent shared output pause takes priority over an audible next source',
      () async {
    await fixture.close();
    final polling = <_ControlledPollingTimer>[];
    await runZoned(() async {
      fixture = _NativePlayer(runtime!, directory, offlineOutput: false);
      fixture.player.setVolumeDsp(0);
      await fixture.open();
      final previous = fixture.mixerSources().single;
      expect(await fixture.prepare('b', 'next'), isTrue);
      final mixer = fixture.player.nativeMixerHandle!;
      final next =
          fixture.mixerSources().singleWhere((source) => source != previous);
      // Native playback remains real. Control only the existing player poll so
      // the pause falls deterministically after next audio and before its event.
      await _until(() => fixture.sourcePosition(next) > 480 * 8,
          maxTurns: 2500);
      expect(fixture.api.BASS_ChannelPause(mixer), isNot(0));
      expect(fixture.player.playerState, PlayerState.paused);
      final paused = fixture.mixerPosition();
      stdout.writeln(
          'shared pause native nextPosition=${fixture.sourcePosition(next)}');
      polling.last.fire();
      await Future<void>.delayed(Duration.zero);
      expect(fixture.events.where((event) => event.completed), isEmpty);
      expect(fixture.player.preparedSourceIdentity, 'next');
      expect(fixture.api.BASS_ChannelStart(mixer), isNot(0));
      await _until(() => fixture.sourcePosition(next) > 480 * 8);
      polling.last.fire();
      await Future<void>.delayed(Duration.zero);
      stdout.writeln('resumed shared event diagnostics '
          '${fixture.events.map((event) => (
                event.state.name,
                event.reason?.name,
                event.problem?.nativeCode
              )).toList()} '
          '${fixture.player.outputDiagnostics()}');
      expect(fixture.events.where((event) => event.completed), hasLength(1));
      expect(fixture.player.takePreparedSource('next'), isTrue);
      expect(fixture.player.nativeMixerHandle, mixer);
      expect(fixture.player.position, greaterThan(0));
      expect(fixture.player.volumeDsp, 0);
      stdout.writeln('silent shared native pause priority played=$paused '
          'resumed=${fixture.mixerPosition()}');
    }, zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, duration, callback) {
      expect(duration, const Duration(milliseconds: 33));
      final timer = _ControlledPollingTimer(callback);
      polling.add(timer);
      return timer;
    }));
  }, skip: sharedSkip);

  test('silent shared cancellation discards already buffered successor PCM',
      () async {
    await fixture.close();
    fixture = _NativePlayer(runtime!, directory, offlineOutput: false);
    fixture.player.configureTransitions(const PlaybackTransitionPreferences(
        mode: PlaybackTransitionMode.crossfade, crossfadeSeconds: .5));
    expect(await fixture.player.setSource(fixture.file('a')), isTrue);
    final mixer = fixture.player.nativeMixerHandle!;
    // Keep sources measurable, but silence this mixer before its first start.
    // ChannelGetData reads its real playback buffer before output attenuation.
    expect(fixture.api.BASS_ChannelSetAttribute(mixer, 2, 0), isNot(0));
    fixture.expectMixerSilent();
    fixture.player.start();
    expect(await fixture.prepare('b', 'next'), isTrue);
    await _until(() => fixture.mixerPosition() >= 60000 * 8, maxTurns: 2500);
    expect(fixture.api.BASS_ChannelPause(mixer), isNot(0));
    await fixture.waitForPausedCursor();
    fixture.expectMixerSilent();
    final played = fixture.mixerPosition();
    final decoded = fixture.mixerPosition(decoding: true);
    final heard = fixture.player.position;
    final before = fixture.peekBuffer();
    final beforeMaximum = before.reduce((a, b) => a > b ? a : b);
    expect(beforeMaximum, greaterThan(.28),
        reason: 'The future output buffer must really contain next audio.');
    expect(fixture.sourcePosition(fixture.mixerSources().first),
        lessThan(72000 * 8),
        reason: 'The listener is still before the intended fade.');
    fixture.player.cancelPreparedSource();
    expect(fixture.player.preparedSourceIdentity, isNull);
    expect(fixture.mixerSources(), hasLength(1));
    expect(fixture.player.playerState, PlayerState.paused);
    expect(fixture.player.position, closeTo(heard, .003));
    fixture.expectMixerSilent();
    // A flushed paused mixer may have no data until it resumes. Any retained
    // bytes, however, must already contain only the current source.
    final after = fixture.peekBuffer(allowEmpty: true);
    final afterMaximum =
        after.isEmpty ? 0.0 : after.reduce((a, b) => a > b ? a : b);
    stdout.writeln('silent buffered cancel played=$played decoded=$decoded '
        'samplesBefore=${before.length} samplesAfter=${after.length} '
        'maximumBefore=$beforeMaximum maximumAfter=$afterMaximum');
    fixture.expectSource(after, 'a', startFrame: played ~/ 8);
    expect(fixture.api.BASS_ChannelStart(mixer), isNot(0));
    await _until(() => fixture.bufferAvailable() >= 4800 * 8);
    fixture.expectMixerSilent();
    final resumed = fixture.peekBuffer();
    fixture.expectSource(resumed, 'a',
        startFrame: (fixture.player.position * 48000).floor());
  }, skip: sharedSkip);

  test(
      'silent FIFO cancellation restores an EOF decoder before its buffered tail ends',
      () async {
    await fixture.close();
    fixture = _NativePlayer(runtime!, directory, offlineOutput: false);
    fixture.player.configureTransitions(const PlaybackTransitionPreferences(
        mode: PlaybackTransitionMode.gapless));
    expect(await fixture.player.setSource(fixture.file('a')), isTrue);
    final mixer = fixture.player.nativeMixerHandle!;
    final previous = fixture.mixerSources().single;
    expect(fixture.api.BASS_ChannelSetAttribute(mixer, 2, 0), isNot(0));
    fixture.expectMixerSilent();
    fixture.player.start();
    expect(await fixture.prepare('b', 'next'), isTrue);
    await _until(() => fixture.mixerPosition(decoding: true) >= 100800 * 8,
        maxTurns: 2500);
    stdout.writeln('FIFO decoded EOF played=${fixture.mixerPosition()} '
        'decoded=${fixture.mixerPosition(decoding: true)} '
        'previousMixer=${fixture.sourceMixer(previous)} '
        'previousState=${fixture.api.BASS_ChannelIsActive(previous)} '
        'sources=${fixture.mixerSources().length}');
    expect(fixture.api.BASS_ChannelPause(mixer), isNot(0));
    await fixture.waitForPausedCursor();
    fixture.expectMixerSilent();
    final played = fixture.mixerPosition();
    expect(played, lessThan(96000 * 8),
        reason: 'The old decoder stopped while its tail is still unheard.');
    expect(fixture.api.BASS_ChannelIsActive(previous), BASS_ACTIVE_STOPPED);
    expect(fixture.events.where((event) => event.completed), isEmpty);
    final before = fixture.peekBuffer();
    final beforeMaximum = before.reduce((a, b) => a > b ? a : b);
    expect(beforeMaximum, greaterThan(.45));
    fixture.player.cancelPreparedSource();
    expect(fixture.player.preparedSourceIdentity, isNull);
    expect(fixture.mixerSources(), [previous]);
    expect(fixture.player.playerState, PlayerState.paused);
    expect(fixture.player.position, closeTo(played / (48000 * 8), .003));
    fixture.expectMixerSilent();
    final after = fixture.peekBuffer(allowEmpty: true);
    fixture.expectSource(after, 'a', startFrame: played ~/ 8);
    expect(fixture.api.BASS_ChannelStart(mixer), isNot(0));
    await _until(() => fixture.bufferAvailable() >= 4800 * 8);
    fixture.expectMixerSilent();
    // The remaining old tail is shorter than the buffer; only its real frames
    // are checked, leaving NONSTOP's normal post-EOF silence outside the scope.
    final remaining = ((2 - fixture.player.position) * 48000).floor();
    final resumed = fixture.peekBuffer().take(remaining.clamp(0, 4800) * 2);
    expect(resumed, isNotEmpty);
    fixture.expectSource(resumed, 'a',
        startFrame: (fixture.player.position * 48000).floor());
    stdout.writeln('silent EOF FIFO cancel played=$played '
        'maximumBefore=$beforeMaximum restored=${fixture.player.position}');
  }, skip: sharedSkip);

  test('silent FIFO tail seek preserves shared playing and paused intent',
      () async {
    await fixture.close();
    fixture = _NativePlayer(runtime!, directory, offlineOutput: false);
    fixture.player.setVolumeDsp(0);
    await fixture.open();
    final previous = fixture.mixerSources().single;
    expect(await fixture.prepare('b', 'next'), isTrue);
    final current =
        fixture.mixerSources().singleWhere((source) => source != previous);
    await _until(() => fixture.events.any((event) => event.completed),
        maxTurns: 2500);
    expect(fixture.player.takePreparedSource('next'), isTrue);
    final mixer = fixture.player.nativeMixerHandle!;
    await _until(
        () =>
            fixture.api.BASS_ChannelIsActive(current) == BASS_ACTIVE_STOPPED &&
            fixture.player.playerState == PlayerState.playing,
        maxTurns: 2500);
    expect(fixture.player.position, lessThan(2));
    final before = fixture.player.position;
    fixture.player.seek(.5);
    expect(fixture.sourceMixer(current), mixer);
    expect(fixture.player.playerState, PlayerState.playing);
    expect(fixture.player.position, closeTo(.5, .003));
    await _until(() => fixture.player.position > .55);
    fixture.player.pause();
    await fixture.waitForPausedCursor();
    fixture.player.seek(.25);
    expect(fixture.player.playerState, PlayerState.paused);
    expect(fixture.player.position, closeTo(.25, .003));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fixture.player.position, closeTo(.25, .003));
    expect(fixture.player.nativeMixerHandle, mixer);
    expect(fixture.player.volumeDsp, 0);
    stdout.writeln('silent shared EOF seek before=$before '
        'playingThenPaused=${fixture.player.position}');
  }, skip: sharedSkip);
}

class _ControlledPollingTimer implements Timer {
  _ControlledPollingTimer(this.callback);
  final void Function(Timer) callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    expect(isActive, isTrue);
    tick++;
    callback(this);
  }
}

class _NativePlayer {
  _NativePlayer(this.runtime, this.directory, {bool offlineOutput = true})
      : player =
            BassPlayer(runtimeDirectory: runtime, offlineOutput: offlineOutput),
        library = DynamicLibrary.open(p.join(runtime, 'bass.dll')) {
    api = Bass(library);
    setDevice =
        library.lookupFunction<Int32 Function(Uint32), int Function(int)>(
            'BASS_SetDevice');
    getData = library.lookupFunction<
        Uint32 Function(Uint32, Pointer<Void>, Uint32),
        int Function(int, Pointer<Void>, int)>('BASS_ChannelGetData');
    subscription = player.playbackEvents.listen(events.add);
    if (offlineOutput) {
      expect(setDevice(0), isNot(0));
    } else {
      final getDevice = library
          .lookupFunction<Uint32 Function(), int Function()>('BASS_GetDevice');
      expect(getDevice(), allOf(greaterThan(0), lessThan(0xffffffff)));
    }
    expect(player.supportsPlaybackRate, isTrue,
        reason:
            'The complete fixture must include BASS_FX, not silently bypass it.');
  }
  final String runtime;
  final Directory directory;
  final BassPlayer player;
  final DynamicLibrary library;
  late final Bass api;
  late final int Function(int) setDevice;
  late final int Function(int, Pointer<Void>, int) getData;
  final events = <BassPlaybackEvent>[];
  late final StreamSubscription<BassPlaybackEvent> subscription;
  final buffer = calloc<Float>(19200);
  final _references = <String, List<double>>{};
  String file(String name) => p.join(directory.path, '$name.wav');

  Future<void> open({bool crossfade = false}) async {
    player.configureTransitions(PlaybackTransitionPreferences(
        mode: crossfade
            ? PlaybackTransitionMode.crossfade
            : PlaybackTransitionMode.gapless,
        crossfadeSeconds: .5));
    expect(await player.setSource(file('a')), isTrue);
    player.start();
    expect(player.playerState, PlayerState.playing);
    expect(player.nativeMixerHandle, isNotNull);
  }

  Future<bool> prepare(String name, Object identity, {double rate = 1}) =>
      player.prepareNextSource(file(name),
          identity: identity, rate: rate, pitch: 0, stillCurrent: () => true);

  List<double> read(int frames) {
    expect(setDevice(0), isNot(0));
    final output = <double>[];
    for (var remaining = frames; remaining > 0;) {
      final count = remaining.clamp(0, 9600);
      final bytes =
          getData(player.nativeMixerHandle!, buffer.cast<Void>(), count * 8);
      expect(bytes, count * 8,
          reason:
              'NoSound mixer decode failed: BASS ${api.BASS_ErrorGetCode()}');
      output.addAll(buffer.asTypedList(count * 2));
      remaining -= count;
    }
    return output;
  }

  int mixerPosition({bool decoding = false}) {
    final value = api.BASS_ChannelGetPosition(
        player.nativeMixerHandle!, BASS_POS_BYTE | (decoding ? 0x10000000 : 0));
    expect(value, allOf(greaterThanOrEqualTo(0), isNot(0xffffffffffffffff)));
    return value;
  }

  void expectMixerSilent() {
    final volume = calloc<Float>();
    try {
      expect(api.BASS_ChannelGetAttribute(player.nativeMixerHandle!, 2, volume),
          isNot(0));
      expect(volume.value, 0);
    } finally {
      calloc.free(volume);
    }
  }

  int bufferAvailable() {
    final bytes = getData(player.nativeMixerHandle!, nullptr, 0);
    expect(bytes, allOf(greaterThanOrEqualTo(0), isNot(0xffffffff)));
    return bytes;
  }

  Future<void> waitForPausedCursor() async {
    var previous = mixerPosition();
    var stable = 0;
    for (var turn = 0; turn < 200; turn++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final current = mixerPosition();
      stable = current == previous ? stable + 1 : 0;
      if (stable >= 6) return;
      previous = current;
    }
    fail('This own mixer did not settle its paused physical playback cursor.');
  }

  List<double> peekBuffer({bool allowEmpty = false}) {
    final mixer = player.nativeMixerHandle!;
    final available = bufferAvailable();
    if (allowEmpty && available == 0) return const [];
    expect(available, greaterThan(0));
    final output = calloc<Float>((available + 3) ~/ 4);
    try {
      final bytes = getData(mixer, output.cast<Void>(), available);
      expect(bytes, allOf(greaterThan(0), lessThanOrEqualTo(available)));
      expect(bytes % 8, 0);
      return output.asTypedList(bytes ~/ 4).toList();
    } finally {
      calloc.free(output);
    }
  }

  List<int> mixerSources() {
    final library = DynamicLibrary.open(p.join(runtime, 'bassmix.dll'));
    final getChannels = library.lookupFunction<
        Uint32 Function(Uint32, Pointer<Uint32>, Uint32),
        int Function(
            int, Pointer<Uint32>, int)>('BASS_Mixer_StreamGetChannels');
    final channels = calloc<Uint32>(4);
    try {
      final count = getChannels(player.nativeMixerHandle!, channels, 4);
      expect(count, allOf(greaterThanOrEqualTo(0), lessThanOrEqualTo(4)));
      return channels.asTypedList(count).toList();
    } finally {
      calloc.free(channels);
      library.close();
    }
  }

  int sourcePosition(int source) {
    final library = BassMixLibrary.open(p.join(runtime, 'bassmix.dll'));
    try {
      final position = library.getChannelPosition(source, BASS_POS_BYTE);
      expect(
          position, allOf(greaterThanOrEqualTo(0), isNot(0xffffffffffffffff)));
      return position;
    } finally {
      library.close();
    }
  }

  int sourceMixer(int source) {
    final library = BassMixLibrary.open(p.join(runtime, 'bassmix.dll'));
    try {
      return library.getChannelMixer(source);
    } finally {
      library.close();
    }
  }

  void expectSamples(Iterable<double> samples, double expected) {
    var index = 0;
    for (final sample in samples) {
      expect(sample, closeTo(expected, .0002), reason: 'Native sample $index');
      index++;
    }
  }

  /// Decode an independent, unmixed BASS_FX source. SoundTouch's native float
  /// conversion and processing are preserved instead of assuming authored PCM
  /// constants survive tempo processing exactly.
  List<double> reference(String name, {double rate = 1}) =>
      _references.putIfAbsent('$name:$rate', () {
        final pointer = file(name).toNativeUtf16();
        var stream = 0;
        final tempo = BassTempoLibrary.open(p.join(runtime, 'bass_fx.dll'));
        try {
          stream = api.BASS_StreamCreateFile(0, pointer.cast<Void>(), 0, 0,
              BASS_UNICODE | BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE | 0x20000);
          expect(stream, isNot(0));
          final wrapped = tempo.createStream(stream, decodingOutput: true);
          expect(wrapped, isNot(0));
          stream = wrapped;
          expect(
              api.BASS_ChannelSetAttribute(
                  stream, BassTempoLibrary.tempoAttribute, (rate - 1) * 100),
              isNot(0));
          expect(
              api.BASS_ChannelSetAttribute(
                  stream, BassTempoLibrary.pitchAttribute, 0),
              isNot(0));
          expect(
              api.BASS_ChannelSetAttribute(
                  stream, BassTempoLibrary.preventClickAttribute, 1),
              isNot(0));
          final output = <double>[];
          while (true) {
            final bytes = getData(stream, buffer.cast<Void>(), 9600 * 8);
            if (bytes == 0 || bytes == 0xffffffff) break;
            expect(bytes % 8, 0);
            output.addAll(buffer.asTypedList(bytes ~/ 4));
            expect(output.length, lessThanOrEqualTo(96000 * 2));
          }
          expect(output, isNotEmpty);
          expect(output.length, (96000 / rate).round() * 2);
          return output;
        } finally {
          if (stream != 0) api.BASS_StreamFree(stream);
          malloc.free(pointer);
          tempo.close();
        }
      });

  void expectAgainst(Iterable<double> samples, List<double> expected) {
    var index = 0;
    for (final sample in samples) {
      expect(index, lessThan(expected.length));
      expect(sample, closeTo(expected[index], .0002),
          reason: 'Native reference sample $index');
      index++;
    }
    expect(index, expected.length);
  }

  void expectSource(Iterable<double> samples, String name,
      {int startFrame = 0, double rate = 1}) {
    final expected = reference(name, rate: rate);
    var index = startFrame * 2;
    for (final sample in samples) {
      expect(index, lessThan(expected.length));
      expect(sample, closeTo(expected[index], .0002),
          reason: 'Native $name reference sample $index');
      expect(sample, greaterThan(.2),
          reason: 'No silent frame in source $name.');
      index++;
    }
  }

  void expectFade(List<double> samples, {required int startFrame}) {
    final old = reference('a');
    final next = reference('b');
    for (var index = 0; index < samples.length; index++) {
      final frame = startFrame + index ~/ 2;
      final channel = index % 2;
      final progress = frame / 24000;
      final expected = old[(72000 + frame) * 2 + channel] * (1 - progress) +
          next[frame * 2 + channel] * progress;
      expect(samples[index], closeTo(expected, .0002),
          reason: 'Native crossfade frame $frame channel ${index % 2}');
    }
  }

  Future<void> close() async {
    await subscription.cancel();
    await player.free();
    library.close();
    calloc.free(buffer);
  }
}

Future<void> _until(bool Function() condition, {int maxTurns = 500}) async {
  for (var turn = 0; turn < maxTurns && !condition(); turn++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue, reason: 'Native transition did not settle.');
}

Uint8List _wave(double amplitude, int frames) {
  final bytes = ByteData(44 + frames * 8);
  void ascii(int offset, String text) {
    for (var index = 0; index < text.length; index++) {
      bytes.setUint8(offset + index, text.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 3, Endian.little); // IEEE float, exact nonzero samples.
  bytes.setUint16(22, 2, Endian.little);
  bytes.setUint32(24, 48000, Endian.little);
  bytes.setUint32(28, 384000, Endian.little);
  bytes.setUint16(32, 8, Endian.little);
  bytes.setUint16(34, 32, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, frames * 8, Endian.little);
  for (var index = 44; index < bytes.lengthInBytes; index += 4) {
    bytes.setFloat32(index, amplitude, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

class _Media extends Fake implements SmtcFlutter {
  @override
  Stream<SMTCControlEvent> subscribeToControlEvents() => const Stream.empty();
  @override
  Future<void> updateState({required SMTCState state}) async {}
  @override
  Future<void> updateDisplay(
      {required String title,
      required String artist,
      required String album,
      required int duration,
      required String path}) async {}
  @override
  Future<void> updateTimeProperties({required int progress}) async {}
  @override
  Future<void> close() async {}
}

class _Lyrics extends Fake implements LyricService {
  @override
  void updateLyric() {}
  @override
  void findCurrLyricLine() {}
  @override
  void dispose() {}
}

class _Helper extends Fake implements DesktopLyricService {
  @override
  Future<bool> get canSendMessage async => false;
  @override
  void sendPlaybackTimelineMessage() {}
  @override
  Future<void> flushAppearance() async {}
  @override
  void dispose() {}
}
