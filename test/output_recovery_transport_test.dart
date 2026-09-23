import 'dart:async';

import 'package:dan_player/src/bass/wasapi_output_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('internal seek resume keeps output restoration tied to observed state',
      () {
    final intent = OutputPlaybackIntent();
    var resumes = 0;
    seekWasapiOutput(
      wasPlaying: true,
      flush: () {},
      move: () {},
      // The native integration uses _resumeCurrentOutput here, which resumes
      // buffered output without recording a user play command.
      resume: () => resumes++,
    );
    expect(resumes, 1);
    // The old track can reach EOF before the replacement finishes opening.
    expect(intent.resolve(false), isFalse);
    intent.request(false);
    expect(intent.resolve(true), isFalse);
  });

  for (final wasPlaying in [false, true]) {
    test('an untouched output transaction preserves playing=$wasPlaying', () {
      final intent = OutputPlaybackIntent();
      expect(intent.resolve(wasPlaying), wasPlaying);
    });
  }

  for (final commands in [
    [false],
    [true],
    [false, true],
    [true, false],
  ]) {
    test(
        'pending output rollback honors the latest transport command $commands',
        () async {
      final intent = OutputPlaybackIntent();
      final reopened = Completer<void>();
      var starts = 0;
      // The old snapshot is deliberately opposite to the last user command.
      final previouslyPlaying = !commands.last;
      final rollback = () async {
        await reopened.future;
        if (intent.resolve(previouslyPlaying)) starts++;
      }();
      for (final playing in commands) {
        intent.request(playing);
      }
      reopened.complete();
      await rollback;
      expect(starts, commands.last ? 1 : 0);
    });
  }
}
