import 'dart:ffi';

import 'package:dan_player/src/bass/audio_segment.dart';
import 'package:dan_player/src/bass/bass.dart';
import 'package:flutter_test/flutter_test.dart';

class _CoordinateBass extends Bass {
  _CoordinateBass({
    this.bytes = 400,
    this.sourceLength = 400,
    this.sourceDuration = 1,
  }) : super.fromLookup(<T extends NativeType>(_) =>
            throw StateError('Unexpected native lookup'));

  final int bytes;
  final int sourceLength;
  final double sourceDuration;

  @override
  // The generated BASS API retains the native export name.
  // ignore: non_constant_identifier_names
  int BASS_ChannelSeconds2Bytes(int handle, double seconds) => bytes;

  @override
  // ignore: non_constant_identifier_names
  int BASS_ChannelGetLength(int handle, int mode) => sourceLength;

  @override
  // ignore: non_constant_identifier_names
  double BASS_ChannelBytes2Seconds(int handle, int bytes) => sourceDuration;
}

void main() {
  test('physical EOF targets the final sample without fabricating completion',
      () {
    expect(bassSeekPositionBytes(_CoordinateBass(), 1, 1), 399);
  });

  test('a one-frame source retains an available zero position', () {
    expect(
        bassSeekPositionBytes(_CoordinateBass(bytes: 4, sourceLength: 4), 1, 1),
        3);
  });

  test('CUE end inside the file retains its exact absolute coordinate', () {
    expect(bassSeekPositionBytes(_CoordinateBass(bytes: 300), 1, .75), 300);
  });

  test('ordinary zero and middle positions are unchanged', () {
    expect(bassSeekPositionBytes(_CoordinateBass(bytes: 0), 1, 0), 0);
    expect(bassSeekPositionBytes(_CoordinateBass(bytes: 200), 1, .5), 200);
  });

  test('an out-of-range target is not hidden by sample rounding', () {
    expect(bassSeekPositionBytes(_CoordinateBass(), 1, 1.00001), 400);
    expect(
        bassSeekPositionBytes(_CoordinateBass(sourceDuration: .5), 1, 1), 400);
    expect(bassSeekPositionBytes(_CoordinateBass(bytes: 440), 1, 1.1), 440);
    expect(bassSeekPositionBytes(_CoordinateBass(bytes: -4), 1, -.01), -4);
  });

  test('unavailable, empty and invalid coordinates retain native failure', () {
    expect(bassSeekPositionBytes(_CoordinateBass(sourceLength: -1), 1, 1), 400);
    expect(
        bassSeekPositionBytes(_CoordinateBass(bytes: 0, sourceLength: 0), 1, 0),
        0);
    for (final invalid in [
      double.nan,
      double.infinity,
      double.negativeInfinity
    ]) {
      expect(bassSeekPositionBytes(_CoordinateBass(), 1, invalid), 400);
    }
  });
}
