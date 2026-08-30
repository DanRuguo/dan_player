import 'package:dan_player/src/bass/wasapi_output_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void verify(List<int> errors, List<bool> expectedFormats,
      {required int expectedError, int resets = 0}) {
    final formats = <bool>[];
    var actualResets = 0;
    final result = initializeWasapiOutput(
      attempt: (compatible) {
        formats.add(compatible);
        return errors[formats.length - 1];
      },
      resetExisting: () => actualResets++,
    );
    expect(formats, expectedFormats);
    expect(actualResets, resets);
    expect(result.errorCode, expectedError);
    expect(result.succeeded, expectedError == 0);
    expect(result.compatibleFormat, expectedFormats.last);
    expect(formats.length, lessThanOrEqualTo(3));
  }

  test('supported native format succeeds without fallback or reset', () {
    verify([0], [false], expectedError: 0);
  });
  test('unsupported format retries once with WASAPI auto format', () {
    verify([6, 0], [false, true], expectedError: 0);
  });
  test('a stale init can be reset only once', () {
    verify([14, 0], [false, false], expectedError: 0, resets: 1);
    verify([14, 14], [false, false], expectedError: 14, resets: 1);
  });
  test('format and stale-state recovery are bounded in either order', () {
    verify([14, 6, 0], [false, false, true], expectedError: 0, resets: 1);
    verify([6, 14, 0], [false, true, true], expectedError: 0, resets: 1);
    verify([14, 6, 6], [false, false, true], expectedError: 6, resets: 1);
  });
  for (final error in [46, 3, 8, 23, 37, 5000, 5001, 5002, 5003, -1]) {
    test('error $error cannot steal the device or retry indefinitely', () {
      verify([error], [false], expectedError: error);
      verify([6, error], [false, true], expectedError: error);
    });
  }

  test('unvalidated output never becomes the next source preference', () {
    final mode = WasapiOutputMode();
    mode.commitStream(true); // Exclusive decoder opened, device init failed.
    expect(mode.active, isTrue);
    expect(mode.preferred, isFalse);
    // The old URL rollback is pending. User next/cancel opens shared, not the
    // failed exclusive mode. A cancelled old transaction never calls confirm.
    mode.commitStream(mode.preferred);
    expect(mode.active, isFalse);
    expect(mode.preferred, isFalse);
  });

  test('successful replacement and cold preferences are inherited by tracks',
      () {
    final mode = WasapiOutputMode();
    mode.commitStream(true);
    mode.confirmActive();
    expect(mode.preferred, isTrue);
    mode.commitStream(
        false); // Failed switch back; still prefer confirmed true.
    expect(mode.preferred, isTrue);
    mode.commitStream(mode.preferred);
    expect(mode.active, isTrue);
    mode.selectBeforePlayback(false);
    expect(mode.active, isFalse);
    expect(mode.preferred, isFalse);
    mode.selectBeforePlayback(true);
    expect(mode.active, isTrue);
    expect(mode.preferred, isTrue);
  });

  for (final playing in [false, true]) {
    test('exclusive seek flushes old samples and preserves playing=$playing',
        () {
      final calls = <String>[];
      seekWasapiOutput(
        wasPlaying: playing,
        flush: () => calls.add('flush'),
        move: () => calls.add('seek'),
        resume: () => calls.add('resume'),
      );
      expect(calls, ['flush', 'seek', if (playing) 'resume']);
    });
    test('failed exclusive seek restores playing=$playing without fake success',
        () {
      final calls = <String>[];
      expect(
          () => seekWasapiOutput(
                wasPlaying: playing,
                flush: () => calls.add('flush'),
                move: () {
                  calls.add('seek');
                  throw StateError('seek rejected');
                },
                resume: () => calls.add('resume'),
              ),
          throwsStateError);
      expect(calls, ['flush', 'seek', if (playing) 'resume']);
    });
  }

  test('failed flush does not move the source or start another output', () {
    expect(
        () => seekWasapiOutput(
              wasPlaying: true,
              flush: () => throw StateError('device unavailable'),
              move: () => fail('source must be unchanged'),
              resume: () => fail('must not start unavailable output'),
            ),
        throwsStateError);
  });
}
