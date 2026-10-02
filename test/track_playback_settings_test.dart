import 'dart:async';

import 'package:dan_player/play_service/track_playback_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('optional profiles reject bad fields without coercing legal fractions',
      () {
    for (final value in [
      null,
      '1.25',
      {},
      {'rate': 1},
      {'rate': '1.25', 'pitch': 0},
      {'rate': double.infinity, 'pitch': 0},
      {'rate': 1, 'pitch': double.negativeInfinity},
      {'rate': double.nan, 'pitch': 0},
      {'rate': .49, 'pitch': 0},
      {'rate': 2.01, 'pitch': 0},
      {'rate': 1, 'pitch': -12.01},
      {'rate': 1, 'pitch': 12.01},
    ]) {
      expect(TrackPlaybackSettings.decode(value), isNull, reason: '$value');
    }
    final valid = TrackPlaybackSettings.decode({'rate': .875, 'pitch': -2.5})!;
    expect(valid.toMap(), {'rate': .875, 'pitch': -2.5});
    expect(() => valid.validate(), returnsNormally);
    expect(() => const TrackPlaybackSettings(rate: 0, pitch: 0).validate(),
        throwsArgumentError);
  });

  test('profile is applied independently of immutable global defaults', () {
    final ownership = TrackPlaybackOwnership();
    const defaults = TrackPlaybackSettings(rate: 1.1, pitch: -1);
    const saved = TrackPlaybackSettings(rate: .75, pitch: 3);
    expect(
        ownership
            .resolve(
                opening: ownership.revision, defaults: defaults, saved: saved)
            .toMap(),
        saved.toMap());
    expect(
        ownership
            .resolve(opening: ownership.revision, defaults: defaults)
            .toMap(),
        defaults.toMap());
    expect(defaults.toMap(), {'rate': 1.1, 'pitch': -1});
  });

  test('manual speed change during slow opening wins only speed', () async {
    final ownership = TrackPlaybackOwnership();
    final opening = ownership.revision;
    final load = Completer<TrackPlaybackSettings?>();
    final opened = load.future.then((saved) => ownership.resolve(
        opening: opening,
        defaults: const TrackPlaybackSettings(rate: 1.2, pitch: 0),
        saved: saved));
    ownership.changedRate();
    load.complete(const TrackPlaybackSettings(rate: .75, pitch: 3));
    expect((await opened).toMap(), {'rate': 1.2, 'pitch': 3});
  });

  test('same-value manual pitch intent defeats an older saved pitch', () {
    final ownership = TrackPlaybackOwnership();
    final opening = ownership.revision;
    ownership.changedPitch();
    expect(
        ownership
            .resolve(
                opening: opening,
                defaults: const TrackPlaybackSettings(rate: 1, pitch: 0),
                saved: const TrackPlaybackSettings(rate: .75, pitch: 5))
            .toMap(),
        {'rate': .75, 'pitch': 0});
  });

  test('late save is rejected after A to B to A, or external parameter edit',
      () {
    final ownership = TrackPlaybackOwnership();
    final captured = (track: 'A', session: 1, revision: ownership.revision);
    bool accepted(String track, int session) => ownership.accepts(captured,
        track: 'A', currentTrack: track, session: session);
    expect(accepted('A', 1), isTrue);
    expect(accepted('B', 2), isFalse);
    expect(accepted('A', 3), isFalse);
    ownership.changedRate();
    expect(accepted('A', 1), isFalse);
  });

  test('track setting apply supersedes both older parameter snapshots', () {
    final ownership = TrackPlaybackOwnership();
    final captured = (track: 'A', session: 1, revision: ownership.revision);
    ownership.changedTrackSettings();
    expect(
        ownership.accepts(captured, track: 'A', currentTrack: 'A', session: 1),
        isFalse);
    expect(
        ownership
            .resolve(
                opening: captured.revision,
                defaults: const TrackPlaybackSettings(rate: 1.25, pitch: -2),
                saved: const TrackPlaybackSettings(rate: .75, pitch: 5))
            .toMap(),
        {'rate': 1.25, 'pitch': -2});
  });
}
