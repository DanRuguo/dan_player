import 'dart:convert';
import 'dart:typed_data';

import 'package:dan_player/play_service/replay_gain.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _synchsafe(int value) => [
      (value >> 21) & 127,
      (value >> 14) & 127,
      (value >> 7) & 127,
      value & 127,
    ];

List<int> _frame(String id, List<int> payload, int version, {int flags = 0}) =>
    [
      ...ascii.encode(id),
      if (version == 4)
        ..._synchsafe(payload.length)
      else
        ...((ByteData(4)..setUint32(0, payload.length)).buffer.asUint8List()),
      0,
      flags,
      ...payload,
    ];

Uint8List _id3(List<int> body, int version, {int flags = 0}) =>
    Uint8List.fromList([
      ...ascii.encode('ID3'),
      version,
      0,
      flags,
      ..._synchsafe(body.length),
      ...body,
    ]);

List<int> _text(String key, String value, int encoding) {
  final text = '$key\u0000$value\u0000';
  if (encoding == 0) return [0, ...latin1.encode(text)];
  if (encoding == 3) return [3, ...utf8.encode(text)];
  final bytes = ByteData(text.length * 2);
  for (var i = 0; i < text.length; i++) {
    bytes.setUint16(
        i * 2, text.codeUnitAt(i), encoding == 1 ? Endian.little : Endian.big);
  }
  return [
    encoding,
    if (encoding == 1) ...[255, 254],
    ...bytes.buffer.asUint8List()
  ];
}

void main() {
  const track = ReplayGainPreferences(mode: ReplayGainMode.track);
  const album = ReplayGainPreferences(mode: ReplayGainMode.album);
  const tagged = ReplayGainTags(
      trackGainDb: -6.020599913,
      trackPeak: .8,
      albumGainDb: 6.020599913,
      albumPeak: .8);

  test('preferences default off and retain valid persisted choices only', () {
    for (final json in [
      null,
      42,
      {},
      {'mode': 'unexpected'}
    ]) {
      expect(
          ReplayGainPreferences.fromJson(json), const ReplayGainPreferences());
    }
    final expected = album.copyWith(preventClipping: false);
    expect(ReplayGainPreferences.fromJson(expected.toJson()), expected);
    expect(
        ReplayGainPreferences.fromJson({'preventClipping': 'false'})
            .preventClipping,
        isTrue);
  });

  test('off, missing tags and mute preserve user volume', () {
    expect(tagged.volume(.7, const ReplayGainPreferences()), .7);
    expect(const ReplayGainTags().volume(.7, track), .7);
    for (final preferences in [
      track,
      album,
      album.copyWith(preventClipping: false)
    ]) {
      expect(tagged.volume(0, preferences), 0);
    }
  });

  test('track gain composes with user volume and album uses its own peak', () {
    expect(tagged.volume(.75, track), closeTo(.375, 1e-8));
    expect(tagged.volume(.75, album), 1.25);
    expect(tagged.volume(.75, album.copyWith(preventClipping: false)),
        closeTo(1.5, 1e-8));
  });

  test('missing album gain falls back to track without mixing album peak', () {
    const tags =
        ReplayGainTags(trackGainDb: 6.020599913, trackPeak: .5, albumPeak: 20);
    expect(tags.volume(.75, album), closeTo(1.5, 1e-8));
    expect(const ReplayGainTags(albumGainDb: -6).volume(.75, track), .75);
  });

  test('unknown peak blocks positive boosts only when protection is enabled',
      () {
    const tags = ReplayGainTags(trackGainDb: 6.020599913);
    expect(tags.volume(.75, track), .75);
    expect(tags.volume(.75, track.copyWith(preventClipping: false)),
        closeTo(1.5, 1e-8));
    expect(const ReplayGainTags(trackGainDb: -6.020599913).volume(.75, track),
        closeTo(.375, 1e-8));
  });

  test('standard comments accept case, signed dB and finite peaks', () {
    final tags = ReplayGainTags.fromComments([
      'replaygain_track_gain = -6.02 dB',
      'REPLAYGAIN_TRACK_PEAK=0.9234',
      'REPLAYGAIN_ALBUM_GAIN=+1.25 DB',
      'REPLAYGAIN_ALBUM_PEAK=1.01',
      'REPLAYGAIN_REFERENCE_LOUDNESS=89 dB',
    ]);
    expect(tags.trackGainDb, -6.02);
    expect(tags.trackPeak, .9234);
    expect(tags.albumGainDb, 1.25);
    expect(tags.albumPeak, 1.01);
  });

  test('malformed, extreme and duplicate numeric tags cannot over-amplify', () {
    for (final value in [
      'NaN',
      'Infinity',
      '-Infinity',
      '999',
      '-999',
      'hello',
      '12 dB x'
    ]) {
      final tags =
          ReplayGainTags.fromComments(['REPLAYGAIN_TRACK_GAIN=$value']);
      expect(tags.hasGain, isFalse, reason: value);
    }
    for (final value in ['NaN', 'Infinity', '0', '-1', '1000']) {
      expect(
          ReplayGainTags.fromComments(['REPLAYGAIN_TRACK_PEAK=$value'])
              .trackPeak,
          isNull);
    }
    expect(
        ReplayGainTags.fromComments(
                ['REPLAYGAIN_TRACK_GAIN=-6 dB', 'REPLAYGAIN_TRACK_GAIN=+20 dB'])
            .trackGainDb,
        -6);
  });

  for (final version in [3, 4]) {
    for (final encoding in [0, 1, 2, 3]) {
      test('ID3v2.$version TXXX encoding $encoding reads gain and peak', () {
        final tags = ReplayGainTags.fromId3(_id3([
          ..._frame('TXXX',
              _text('replaygain_track_gain', '-6.02 dB', encoding), version),
          ..._frame(
              'TXXX', _text('replaygain_track_peak', '.8', encoding), version),
          ..._frame('TXXX', _text('replaygain_album_gain', '+1.2 dB', encoding),
              version),
        ], version));
        expect(tags.trackGainDb, -6.02);
        expect(tags.trackPeak, .8);
        expect(tags.albumGainDb, 1.2);
      });
    }
    test('ID3v2.$version skips empty dates and large artwork without decoding',
        () {
      final tags = ReplayGainTags.fromId3(_id3([
        ..._frame('TYER', [], version),
        ..._frame('APIC', List.filled(1024 * 1024 + 1, 17), version),
        ..._frame('TXXX', _text('REPLAYGAIN_TRACK_GAIN', '-8 dB', 3), version),
      ], version));
      expect(tags.trackGainDb, -8);
    });
    test('ID3v2.$version bounded extended header locates TXXX', () {
      final extension = version == 4 ? _synchsafe(6) : [0, 0, 0, 6];
      final tags = ReplayGainTags.fromId3(_id3([
        ...extension,
        ...List.filled(version == 4 ? 2 : 6, 0),
        ..._frame('TXXX', _text('REPLAYGAIN_TRACK_GAIN', '-8 dB', 3), version),
      ], version, flags: 0x40));
      expect(tags.trackGainDb, -8);
    });
  }

  test(
      'truncated or unsupported ID3 blocks and encrypted frames stay unapplied',
      () {
    final frame =
        _frame('TXXX', _text('REPLAYGAIN_TRACK_GAIN', '+20 dB', 3), 4);
    final valid = _id3(frame, 4);
    final forgedFrame = Uint8List.fromList(valid)
      ..setRange(14, 18, [127, 127, 127, 127]);
    for (final bytes in [
      Uint8List(0),
      Uint8List.sublistView(valid, 0, 9),
      Uint8List.sublistView(valid, 0, valid.length - 1),
      forgedFrame,
      _id3(frame, 4, flags: 0x80),
      _id3(
          _frame('TXXX', _text('REPLAYGAIN_TRACK_GAIN', '+20 dB', 3), 4,
              flags: 4),
          4)
    ]) {
      expect(ReplayGainTags.fromId3(bytes).hasGain, isFalse);
    }
  });
}
