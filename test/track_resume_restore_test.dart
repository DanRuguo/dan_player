import 'dart:async';

import 'package:dan_player/play_service/track_resume_restore.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved CUE session position needs identical source and CD frame range',
      () {
    CueTrackReference cue(int start, int end,
            {String source = r'J:\Music\album.flac'}) =>
        CueTrackReference(
            cuePath: r'J:\Music\album.cue',
            sourcePath: source,
            number: 2,
            startFrame: start,
            endFrame: end);
    final before = cue(75, 7500);
    expect(sameCueResumeSegment(before, cue(75, 7500)), isTrue);
    expect(sameCueResumeSegment(before, cue(150, 7575)), isFalse,
        reason: 'Same duration but different slice must start at zero.');
    expect(
        sameCueResumeSegment(
            before, cue(75, 7500, source: r'J:\Music\other.flac')),
        isFalse);
    expect(sameCueResumeSegment(null, before), isFalse);
  });
  test(
      'slow storage yields to playback after 500ms and late result cannot seek',
      () {
    fakeAsync((clock) {
      final lookup = Completer<double?>();
      final seeks = <double>[];
      var completed = false;
      restoreRememberedTrackPosition(
              read: () => lookup.future, canApply: () => true, seek: seeks.add)
          .then((position) {
        expect(position, isNull);
        completed = true;
      });
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 499));
      expect(completed, isFalse);
      clock.elapse(const Duration(milliseconds: 1));
      clock.flushMicrotasks();
      expect(completed, isTrue);
      lookup.complete(120);
      clock.flushMicrotasks();
      expect(seeks, isEmpty);
    });
  });
  test(
      'delayed disk lookup cannot seek after track change, manual seek or shutdown',
      () async {
    for (final reason in [
      'new source',
      'manual seek',
      'shutdown',
      'A-B loop'
    ]) {
      var allowed = true;
      final lookup = Completer<double?>();
      final seeks = <double>[];
      final pending = restoreRememberedTrackPosition(
          read: () => lookup.future, canApply: () => allowed, seek: seeks.add);
      allowed = false;
      lookup.complete(120);
      expect(await pending, isNull, reason: reason);
      expect(seeks, isEmpty, reason: reason);
    }
  });
  test('valid remembered position applies once; no record leaves decoder alone',
      () async {
    final seeks = <double>[];
    expect(
        await restoreRememberedTrackPosition(
            read: () async => 120, canApply: () => true, seek: seeks.add),
        120);
    expect(
        await restoreRememberedTrackPosition(
            read: () async => null, canApply: () => true, seek: seeks.add),
        isNull);
    expect(seeks, [120]);
  });
  test('already superseded request does not read storage', () async {
    var reads = 0;
    expect(
        await restoreRememberedTrackPosition(
            read: () async {
              reads++;
              return 120;
            },
            canApply: () => false,
            seek: (_) => fail('stale seek')),
        isNull);
    expect(reads, 0);
  });
}
