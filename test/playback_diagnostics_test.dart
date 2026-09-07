import 'dart:async';
import 'dart:convert';

import 'package:dan_player/component/playback_diagnostics_panel.dart';
import 'package:dan_player/play_service/playback_diagnostics.dart';
import 'package:dan_player/play_service/replay_gain.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/src/bass/bass_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'local relink accepts only the committed source and a valid absolute target',
      () {
    String? relink(
            {String? current = r'J:\Music\old.flac',
            bool online = false,
            String before = r'j:/music/OLD.flac',
            String after = r'J:\Moved\new.flac'}) =>
        relinkedLocalPlaybackPath(
            currentPath: current,
            isUrl: online,
            oldPath: before,
            newPath: after);
    expect(relink(), r'J:\Moved\new.flac');
    expect(relink(current: r'J:\Music\another.flac'), isNull,
        reason:
            'A pending or background rename must not replace another current source.');
    expect(relink(current: null), isNull);
    expect(relink(online: true), isNull);
    for (final invalid in [
      '',
      'relative.flac',
      r'\root-relative.flac',
      'https://host/music.flac',
      'J:\\Moved\\\u0000.flac',
      'J:\\'
    ]) {
      expect(relink(after: invalid), isNull, reason: invalid);
    }
    expect(
        sourcePathAfterLocalRelink(
            requested: r'J:\Music\old.flac',
            previousCurrent: r'J:\Music\old.flac',
            current: r'J:\Moved\new.flac',
            isUrl: false),
        r'J:\Moved\new.flac',
        reason:
            'Same-source output rebuild retains a concurrent verified rename.');
    expect(
        sourcePathAfterLocalRelink(
            requested: r'J:\Music\next.flac',
            previousCurrent: r'J:\Music\old.flac',
            current: r'J:\Moved\new.flac',
            isUrl: false),
        r'J:\Music\next.flac',
        reason: 'An unrelated pending next source must not be redirected.');
  });
  test('device recovery retries INIT once and never drops other failures', () {
    for (final error in [8, 5, 23, -1, 0]) {
      var attempts = 0, initialized = 0;
      final result = startBassDeviceOnce(
          start: () {
            attempts++;
            return 0;
          },
          errorCode: () => error,
          initialize: () => initialized++);
      expect(result, error == 0 ? -1 : error);
      expect(attempts, error == 8 ? 2 : 1);
      expect(initialized, error == 8 ? 1 : 0);
    }
    var attempts = 0;
    expect(
        startBassDeviceOnce(
            start: () => ++attempts == 2 ? 1 : 0,
            errorCode: () => 8,
            initialize: () {}),
        0);
  });
  test('A-B-A instances reject old completion and position events', () {
    final boundary = PlaybackEventBoundary()..replace();
    final firstA = boundary.stamp;
    boundary.replace();
    final b = boundary.stamp;
    boundary.replace();
    final secondA = boundary.stamp;
    expect(boundary.accepts(firstA), isFalse);
    expect(boundary.settle(firstA), isFalse);
    expect(boundary.accepts(b), isFalse);
    expect(boundary.accepts(secondA), isTrue);
    expect(boundary.settle(secondA), isTrue);
    expect(boundary.settle(secondA), isFalse);
  });

  test('pause/seek invalidate already queued completion before delivery',
      () async {
    final boundary = PlaybackEventBoundary()..replace();
    final stream = StreamController<PlaybackStamp>.broadcast();
    final accepted = <PlaybackStamp>[];
    final subscription = boundary
        .currentEvents(stream.stream, (stamp) => stamp)
        .listen(accepted.add);
    stream.add(boundary.stamp);
    boundary.command(); // pause wins over a queued end message
    await Future<void>.delayed(Duration.zero);
    expect(accepted, isEmpty);
    stream.add(boundary.stamp);
    boundary.command(rearm: true); // seek starts another run of this instance
    await Future<void>.delayed(Duration.zero);
    expect(accepted, isEmpty);
    stream.add(boundary.stamp);
    await Future<void>.delayed(Duration.zero);
    expect(accepted, hasLength(1));
    await subscription.cancel();
    await stream.close();
  });

  test('terminal settlement rearms only for an explicit new run', () {
    final boundary = PlaybackEventBoundary()..replace();
    expect(boundary.settle(boundary.stamp), isTrue);
    boundary.command();
    expect(boundary.settle(boundary.stamp), isFalse);
    boundary.command(rearm: true);
    expect(boundary.settle(boundary.stamp), isTrue);
  });

  test('event delivery advances only a current natural/CUE completion once',
      () async {
    final boundary = PlaybackEventBoundary()..replace();
    final events = StreamController<BassPlaybackEvent>.broadcast();
    var advances = 0;
    final subscription = boundary
        .currentEvents(events.stream, (event) => event.stamp)
        .listen((event) {
      if (event.completed && boundary.settle(event.stamp)) advances++;
    });
    final a = boundary.stamp;
    events.add(BassPlaybackEvent(a, PlayerState.completed,
        reason: PlaybackEndReason.naturalEnd));
    boundary.replace(); // B
    boundary.replace(); // another A occurrence, same URI is immaterial
    await Future<void>.delayed(Duration.zero);
    expect(advances, 0);
    final current = boundary.stamp;
    for (final reason in [
      PlaybackEndReason.userStop,
      PlaybackEndReason.invalidHandle,
      PlaybackEndReason.deviceUnavailable,
      PlaybackEndReason.unexpectedStop
    ]) {
      events
          .add(BassPlaybackEvent(current, PlayerState.stopped, reason: reason));
    }
    await Future<void>.delayed(Duration.zero);
    expect(advances, 0);
    events.add(BassPlaybackEvent(current, PlayerState.completed,
        reason: PlaybackEndReason.segmentEnd));
    events.add(BassPlaybackEvent(current, PlayerState.completed,
        reason: PlaybackEndReason.segmentEnd));
    await Future<void>.delayed(Duration.zero);
    expect(advances, 1);
    await subscription.cancel();
    await events.close();
  });

  test('invalid/stopped/unknown length/device failure never imply completion',
      () {
    PlaybackEndReason classify(
            {bool valid = true,
            bool device = true,
            double position = 30,
            double length = 30,
            bool cue = false}) =>
        classifyPlaybackStop(
            validHandle: valid,
            deviceAvailable: device,
            position: position,
            duration: length,
            segment: cue);
    expect(classify(), PlaybackEndReason.naturalEnd);
    expect(classify(cue: true), PlaybackEndReason.segmentEnd);
    expect(classify(valid: false), PlaybackEndReason.invalidHandle);
    expect(classify(device: false), PlaybackEndReason.deviceUnavailable);
    expect(classify(position: 0), PlaybackEndReason.unexpectedStop);
    expect(classify(length: double.nan), PlaybackEndReason.unexpectedStop);
    expect(classify(position: double.nan), PlaybackEndReason.unexpectedStop);
    expect(classify(length: 0), PlaybackEndReason.unexpectedStop);
    expect(classify(position: 29.9), PlaybackEndReason.unexpectedStop);
  });

  test('diagnostic error serializes category/code and no upstream secrets', () {
    const problem = PlaybackProblem(PlaybackProblemKind.sourceUnavailable,
        r'C:\Users\Secret\private.mp3 https://host?token=secret',
        nativeCode: 2);
    final exported = jsonEncode(problem.toSafeJson());
    expect(exported, contains('sourceUnavailable'));
    expect(exported, contains('2'));
    expect(exported, isNot(contains('Secret')));
    expect(exported, isNot(contains('token')));
  });

  test('ReplayGain reports actual fallback and no invented zero dB', () {
    const album = ReplayGainPreferences(mode: ReplayGainMode.album);
    const tags = ReplayGainTags(trackGainDb: -6, trackPeak: 0.9);
    expect(tags.appliedMode(album), ReplayGainMode.track);
    expect(tags.effectiveGainDb(0.5, album), closeTo(-6, 0.001));
    expect(const ReplayGainTags().appliedMode(album), isNull);
    expect(tags.effectiveGainDb(0, album), isNull);
    expect(tags.appliedMode(const ReplayGainPreferences()), isNull);
    const invalidAlbum =
        ReplayGainTags(albumGainDb: double.nan, trackGainDb: -3);
    expect(invalidAlbum.appliedMode(album), ReplayGainMode.track);
    expect(invalidAlbum.effectiveGainDb(1, album), closeTo(-3, 0.001));
    const positive = ReplayGainTags(trackGainDb: 6, trackPeak: 2);
    expect(positive.effectiveGainDb(1, album), closeTo(-6.0206, 0.001));
  });

  testWidgets(
      'details show unknown device and unapplied loudness at narrow width',
      (tester) async {
    const snapshot = <String, Object?>{
      'phase': 'paused',
      'output': <String, Object?>{
        'session': 4,
        'requestedOutput': 'exclusive',
        'streamOutput': 'exclusive',
        'deviceFormat': null,
        'replayGainRequested': 'album',
        'replayGainApplied': null,
        'replayGainEffectiveDb': null,
      },
    };
    Map<String, Object?>? exported;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: Center(
          child: SizedBox(
        width: 280,
        child: PlaybackDiagnosticsContent(
            snapshot: snapshot,
            onExport: (value) async => exported = value,
            onRefresh: () {}),
      )),
    ))));
    expect(find.textContaining('未知 / 未接通检测'), findsWidgets);
    expect(find.textContaining('独占解码链路；设备尚未确认'), findsOneWidget);
    expect(find.textContaining('0.00 dB'), findsNothing);
    await tester.ensureVisible(find.text('导出脱敏诊断'));
    await tester.tap(find.text('导出脱敏诊断'));
    expect(exported, snapshot);
    expect(tester.takeException(), isNull);
  });
}
