import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

enum ReplayGainMode { off, track, album }

class ReplayGainPreferences {
  const ReplayGainPreferences({
    this.mode = ReplayGainMode.off,
    this.preventClipping = true,
  });

  final ReplayGainMode mode;
  final bool preventClipping;

  factory ReplayGainPreferences.fromJson(Object? value) {
    if (value is! Map) return const ReplayGainPreferences();
    return ReplayGainPreferences(
      mode: ReplayGainMode.values.firstWhere(
        (mode) => mode.name == value['mode'],
        orElse: () => ReplayGainMode.off,
      ),
      preventClipping: value['preventClipping'] != false,
    );
  }

  Map<String, Object> toJson() => {
        'mode': mode.name,
        'preventClipping': preventClipping,
      };

  ReplayGainPreferences copyWith({
    ReplayGainMode? mode,
    bool? preventClipping,
  }) =>
      ReplayGainPreferences(
        mode: mode ?? this.mode,
        preventClipping: preventClipping ?? this.preventClipping,
      );

  @override
  bool operator ==(Object other) =>
      other is ReplayGainPreferences &&
      mode == other.mode &&
      preventClipping == other.preventClipping;

  @override
  int get hashCode => Object.hash(mode, preventClipping);
}

/// Existing file tags only: no loudness analysis, index migration or tag writes.
class ReplayGainTags {
  const ReplayGainTags({
    this.trackGainDb,
    this.trackPeak,
    this.albumGainDb,
    this.albumPeak,
  });

  final double? trackGainDb;
  final double? trackPeak;
  final double? albumGainDb;
  final double? albumPeak;

  bool get hasGain => trackGainDb != null || albumGainDb != null;

  /// Album selection falls back to a valid track tag. Off/missing/invalid
  /// tags are unapplied, not a fictitious applied 0 dB measurement.
  ReplayGainMode? appliedMode(ReplayGainPreferences preferences) {
    if (preferences.mode == ReplayGainMode.off) return null;
    if (preferences.mode == ReplayGainMode.album &&
        albumGainDb?.isFinite == true) {
      return ReplayGainMode.album;
    }
    if (trackGainDb?.isFinite == true) return ReplayGainMode.track;
    return null;
  }

  double? effectiveGainDb(
      double userVolume, ReplayGainPreferences preferences) {
    if (appliedMode(preferences) == null || userVolume <= 0) return null;
    final appliedVolume = volume(userVolume, preferences);
    if (appliedVolume <= 0 || !appliedVolume.isFinite) return null;
    return 20 * math.log(appliedVolume / userVolume) / math.ln10;
  }

  /// Compose once with user volume. The peak limit precedes later EQ/DSP and
  /// is not a final-output limiter. Unknown peaks never receive a positive
  /// ReplayGain boost while protection is enabled.
  double volume(double userVolume, ReplayGainPreferences preferences) {
    if (preferences.mode == ReplayGainMode.off) return userVolume;
    final useAlbum = appliedMode(preferences) == ReplayGainMode.album;
    final gain = useAlbum ? albumGainDb : trackGainDb;
    final peak = useAlbum ? albumPeak : trackPeak;
    if (gain == null || !gain.isFinite) return userVolume;
    final factor = math.pow(10, gain.clamp(-60.0, 30.0) / 20).toDouble();
    final requested = userVolume * factor;
    if (!preferences.preventClipping) return requested;
    if (peak == null || !peak.isFinite || peak <= 0) {
      return math.min(userVolume, requested);
    }
    return math.min(requested, 1 / peak);
  }

  ReplayGainTags fillMissing(ReplayGainTags fallback) => ReplayGainTags(
        trackGainDb: trackGainDb ?? fallback.trackGainDb,
        trackPeak: trackPeak ?? fallback.trackPeak,
        albumGainDb: albumGainDb ?? fallback.albumGainDb,
        albumPeak: albumPeak ?? fallback.albumPeak,
      );

  factory ReplayGainTags.fromComments(Iterable<String> comments) {
    final fields = <String, double>{};
    for (final comment in comments.take(512)) {
      if (comment.length > 8192) continue;
      final separator = comment.indexOf('=');
      if (separator <= 0) continue;
      final key = comment.substring(0, separator).trim().toUpperCase();
      final isGain =
          key == 'REPLAYGAIN_TRACK_GAIN' || key == 'REPLAYGAIN_ALBUM_GAIN';
      if (!isGain &&
          key != 'REPLAYGAIN_TRACK_PEAK' &&
          key != 'REPLAYGAIN_ALBUM_PEAK') {
        continue;
      }
      final raw = comment.substring(separator + 1).trim();
      final number = isGain
          ? raw.replaceFirst(RegExp(r'\s*dB$', caseSensitive: false), '')
          : raw;
      final value = double.tryParse(number);
      if (value == null || !value.isFinite) continue;
      if (isGain ? value < -60 || value > 30 : value <= 0 || value > 64) {
        continue;
      }
      fields.putIfAbsent(key, () => value);
    }
    return ReplayGainTags(
      trackGainDb: fields['REPLAYGAIN_TRACK_GAIN'],
      trackPeak: fields['REPLAYGAIN_TRACK_PEAK'],
      albumGainDb: fields['REPLAYGAIN_ALBUM_GAIN'],
      albumPeak: fields['REPLAYGAIN_ALBUM_PEAK'],
    );
  }

  /// Bounded ID3v2.3/2.4 TXXX reader. Unrelated frames (including large APIC
  /// covers and malformed dates) are skipped without decoding or copying them.
  /// Unsupported unsynchronization/compression/encryption is left unapplied.
  factory ReplayGainTags.fromId3(Uint8List bytes) {
    const empty = ReplayGainTags();
    if (bytes.length < 10 ||
        bytes.length > 64 * 1024 * 1024 ||
        bytes[0] != 0x49 ||
        bytes[1] != 0x44 ||
        bytes[2] != 0x33) {
      return empty;
    }
    final version = bytes[3];
    if ((version != 3 && version != 4) || bytes[5] & 0x80 != 0) return empty;
    final size = _synchsafe(bytes, 6);
    if (size == null || size > bytes.length - 10) return empty;
    final end = 10 + size;
    var offset = 10;
    if (bytes[5] & 0x40 != 0) {
      if (end - offset < 4) return empty;
      final extension = version == 4
          ? _synchsafe(bytes, offset)
          : ByteData.sublistView(bytes).getUint32(offset);
      if (extension == null || extension < 6) return empty;
      offset += extension + (version == 3 ? 4 : 0);
      if (offset > end) return empty;
    }
    final comments = <String>[];
    for (var frame = 0; frame < 4096 && offset + 10 <= end; frame++) {
      if (bytes[offset] == 0) break;
      final length = version == 4
          ? _synchsafe(bytes, offset + 4)
          : ByteData.sublistView(bytes).getUint32(offset + 4);
      if (length == null || length > end - offset - 10) break;
      final isText = bytes[offset] == 0x54 &&
          bytes[offset + 1] == 0x58 &&
          bytes[offset + 2] == 0x58 &&
          bytes[offset + 3] == 0x58;
      if (isText && bytes[offset + 9] == 0 && length <= 8192) {
        final text = _decodeText(
            Uint8List.sublistView(bytes, offset + 10, offset + 10 + length));
        final separator = text?.indexOf('\u0000') ?? -1;
        if (separator > 0) {
          final value = text!.substring(separator + 1).split('\u0000').first;
          comments.add('${text.substring(0, separator)}=$value');
        }
      }
      offset += 10 + length;
    }
    return ReplayGainTags.fromComments(comments);
  }

  static int? _synchsafe(Uint8List bytes, int offset) {
    var value = 0;
    for (var i = offset; i < offset + 4; i++) {
      if (bytes[i] > 0x7f) return null;
      value = (value << 7) | bytes[i];
    }
    return value;
  }

  static String? _decodeText(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final body = Uint8List.sublistView(bytes, 1);
    if (bytes[0] == 0) return latin1.decode(body);
    if (bytes[0] == 3) return utf8.decode(body, allowMalformed: true);
    if (bytes[0] != 1 && bytes[0] != 2) return null;
    var offset = 0;
    var endian = Endian.big;
    if (bytes[0] == 1) {
      if (body.length < 2) return null;
      if (body[0] == 0xff && body[1] == 0xfe) {
        endian = Endian.little;
      } else if (body[0] != 0xfe || body[1] != 0xff) {
        return null;
      }
      offset = 2;
    }
    if ((body.length - offset).isOdd) return null;
    final data = ByteData.sublistView(body);
    return String.fromCharCodes([
      for (var i = offset; i + 1 < body.length; i += 2)
        if (data.getUint16(i, endian) != 0xfeff) data.getUint16(i, endian),
    ]);
  }
}
