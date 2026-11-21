import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

enum ReplayGainMode { off, track, album }

class ReplayGainPreferences {
  const ReplayGainPreferences({
    this.mode = ReplayGainMode.off,
    this.preventClipping = true,
    this.preampDb = 0,
    this.fallbackGainDb = 0,
  });

  final ReplayGainMode mode;
  final bool preventClipping;
  final double preampDb;
  final double fallbackGainDb;

  static const minimumGainDb = -24.0;
  static const maximumGainDb = 24.0;
  static const gainPresets = [-12.0, -6.0, -3.0, 0.0, 3.0, 6.0, 12.0];

  static double sanitizeGain(Object? value) => value is num && value.isFinite
      ? value.toDouble().clamp(minimumGainDb, maximumGainDb)
      : 0;

  static String gainLabel(double value) {
    final gain = sanitizeGain(value);
    final number = gain == gain.roundToDouble()
        ? gain.toStringAsFixed(0)
        : gain.toString();
    return '${gain > 0 ? '+' : ''}$number dB';
  }

  factory ReplayGainPreferences.fromJson(Object? value) {
    if (value is! Map) return const ReplayGainPreferences();
    return ReplayGainPreferences(
      mode: ReplayGainMode.values.firstWhere(
        (mode) => mode.name == value['mode'],
        orElse: () => ReplayGainMode.off,
      ),
      preventClipping: value['preventClipping'] != false,
      preampDb: sanitizeGain(value['preampDb']),
      fallbackGainDb: sanitizeGain(value['fallbackGainDb']),
    );
  }

  Map<String, Object> toJson() => {
        'mode': mode.name,
        'preventClipping': preventClipping,
        'preampDb': sanitizeGain(preampDb),
        'fallbackGainDb': sanitizeGain(fallbackGainDb),
      };

  ReplayGainPreferences copyWith({
    ReplayGainMode? mode,
    bool? preventClipping,
    double? preampDb,
    double? fallbackGainDb,
  }) =>
      ReplayGainPreferences(
        mode: mode ?? this.mode,
        preventClipping: preventClipping ?? this.preventClipping,
        preampDb: sanitizeGain(preampDb ?? this.preampDb),
        fallbackGainDb: sanitizeGain(fallbackGainDb ?? this.fallbackGainDb),
      );

  @override
  bool operator ==(Object other) =>
      other is ReplayGainPreferences &&
      mode == other.mode &&
      preventClipping == other.preventClipping &&
      preampDb == other.preampDb &&
      fallbackGainDb == other.fallbackGainDb;

  @override
  int get hashCode =>
      Object.hash(mode, preventClipping, preampDb, fallbackGainDb);
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

  /// The preamp is global within ReplayGain, including missing-tag fallback.
  /// Missing tags with the original zero defaults remain honestly unapplied.
  double? requestedGainDb(ReplayGainPreferences preferences) {
    if (preferences.mode == ReplayGainMode.off) return null;
    final preamp = ReplayGainPreferences.sanitizeGain(preferences.preampDb);
    final fallback =
        ReplayGainPreferences.sanitizeGain(preferences.fallbackGainDb);
    final mode = appliedMode(preferences);
    if (mode == null) {
      return preamp == 0 && fallback == 0 ? null : preamp + fallback;
    }
    final gain = mode == ReplayGainMode.album ? albumGainDb! : trackGainDb!;
    return gain.clamp(-60.0, 30.0) + preamp;
  }

  String? appliedSource(ReplayGainPreferences preferences) =>
      appliedMode(preferences)?.name ??
      (requestedGainDb(preferences) == null ? null : 'fallback');

  double? effectiveGainDb(
      double userVolume, ReplayGainPreferences preferences) {
    if (requestedGainDb(preferences) == null || userVolume <= 0) return null;
    final appliedVolume = volume(userVolume, preferences);
    if (appliedVolume <= 0 || !appliedVolume.isFinite) return null;
    return 20 * math.log(appliedVolume / userVolume) / math.ln10;
  }

  /// Compose once with user volume. The peak limit precedes later EQ/DSP and
  /// is not a final-output limiter. Unknown peaks never receive a positive
  /// ReplayGain boost while protection is enabled.
  double volume(double userVolume, ReplayGainPreferences preferences) {
    if (preferences.mode == ReplayGainMode.off) return userVolume;
    final mode = appliedMode(preferences);
    final gain = requestedGainDb(preferences);
    if (gain == null) return userVolume;
    final peak = mode == ReplayGainMode.album
        ? albumPeak
        : mode == ReplayGainMode.track
            ? trackPeak
            : preferences.mode == ReplayGainMode.album
                ? albumPeak ?? trackPeak
                : trackPeak;
    final factor = math.pow(10, gain / 20).toDouble();
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

  static const _freeformPrefixes = <String>[
    '----:COM.APPLE.ITUNES:',
    'COM.APPLE.ITUNES:',
    '----:ORG.HYDROGENAUDIO.REPLAYGAIN:',
    'ORG.HYDROGENAUDIO.REPLAYGAIN:',
    '----:',
  ];

  static String _normalizeCommentKey(String rawKey) {
    var key = rawKey.trim().toUpperCase();
    for (final prefix in _freeformPrefixes) {
      if (key.startsWith(prefix)) {
        key = key.substring(prefix.length).trim();
        break;
      }
    }
    return key;
  }

  static double? _parseReplayGainNumber(String raw, {required bool isGain}) {
    final trimmed = isGain
        ? raw.replaceFirst(RegExp(r'\s*dB$', caseSensitive: false), '').trim()
        : raw.trim();
    var value = double.tryParse(trimmed);
    if (value == null &&
        !trimmed.contains('.') &&
        trimmed.indexOf(',') > 0 &&
        trimmed.indexOf(',') == trimmed.lastIndexOf(',')) {
      value = double.tryParse(trimmed.replaceFirst(',', '.'));
    }
    if (value == null || !value.isFinite) return null;
    if (isGain ? value < -60 || value > 30 : value <= 0 || value > 64) {
      return null;
    }
    return value;
  }

  factory ReplayGainTags.fromComments(Iterable<String> comments) {
    final fields = <String, double>{};
    final r128Fields = <String, double>{};
    for (final comment in comments.take(512)) {
      if (comment.length > 8192) continue;
      final separator = comment.indexOf('=');
      if (separator <= 0) continue;
      final key = _normalizeCommentKey(comment.substring(0, separator));
      final raw = comment.substring(separator + 1).trim();
      // RFC 7845 Opus R128_*_GAIN uses Q7.8 signed integers relative to -23 LUFS.
      // Shift by +5 dB to align with ReplayGain's -18 LUFS reference when
      // explicit REPLAYGAIN_* comments are absent.
      if (key == 'R128_TRACK_GAIN' || key == 'R128_ALBUM_GAIN') {
        final q78 = int.tryParse(raw);
        if (q78 == null || q78 < -32768 || q78 > 32767) continue;
        final db = q78 / 256.0 + 5.0;
        if (!db.isFinite || db < -60 || db > 30) continue;
        r128Fields.putIfAbsent(key, () => db);
        continue;
      }
      final isGain =
          key == 'REPLAYGAIN_TRACK_GAIN' || key == 'REPLAYGAIN_ALBUM_GAIN';
      if (!isGain &&
          key != 'REPLAYGAIN_TRACK_PEAK' &&
          key != 'REPLAYGAIN_ALBUM_PEAK') {
        continue;
      }
      final value = _parseReplayGainNumber(raw, isGain: isGain);
      if (value == null) continue;
      fields.putIfAbsent(key, () => value);
    }
    return ReplayGainTags(
      trackGainDb:
          fields['REPLAYGAIN_TRACK_GAIN'] ?? r128Fields['R128_TRACK_GAIN'],
      trackPeak: fields['REPLAYGAIN_TRACK_PEAK'],
      albumGainDb:
          fields['REPLAYGAIN_ALBUM_GAIN'] ?? r128Fields['R128_ALBUM_GAIN'],
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
    double? rvaTrackGain;
    double? rvaTrackPeak;
    double? rvaAlbumGain;
    double? rvaAlbumPeak;
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
      final isRva2 = bytes[offset] == 0x52 &&
          bytes[offset + 1] == 0x56 &&
          bytes[offset + 2] == 0x41 &&
          bytes[offset + 3] == 0x32;
      if (isText && bytes[offset + 9] == 0 && length <= 8192) {
        final text = _decodeText(
            Uint8List.sublistView(bytes, offset + 10, offset + 10 + length));
        final separator = text?.indexOf('\u0000') ?? -1;
        if (separator > 0) {
          final value = text!.substring(separator + 1).split('\u0000').first;
          comments.add('${text.substring(0, separator)}=$value');
        }
      } else if (isRva2 && bytes[offset + 9] == 0 && length <= 4096) {
        final parsed = _parseRva2(
          Uint8List.sublistView(bytes, offset + 10, offset + 10 + length),
        );
        if (parsed != null) {
          if (parsed.isAlbum) {
            rvaAlbumGain ??= parsed.gainDb;
            rvaAlbumPeak ??= parsed.peak;
          } else {
            rvaTrackGain ??= parsed.gainDb;
            rvaTrackPeak ??= parsed.peak;
          }
        }
      }
      offset += 10 + length;
    }
    return ReplayGainTags.fromComments(comments).fillMissing(
      ReplayGainTags(
        trackGainDb: rvaTrackGain,
        trackPeak: rvaTrackPeak,
        albumGainDb: rvaAlbumGain,
        albumPeak: rvaAlbumPeak,
      ),
    );
  }

  /// Bounded ID3v2.4 RVA2 frame reader for Master Volume (`0x01`) entries
  /// identified as `track` or `album` (used by Quod Libet, Mutagen, etc.).
  static ({bool isAlbum, double gainDb, double? peak})? _parseRva2(
      Uint8List payload) {
    final nul = payload.indexOf(0);
    if (nul <= 0 || nul + 4 > payload.length) return null;
    final id = latin1.decode(payload.sublist(0, nul)).trim().toLowerCase();
    final bool isAlbum;
    if (id == 'album') {
      isAlbum = true;
    } else if (id == 'track') {
      isAlbum = false;
    } else {
      return null;
    }
    final data = ByteData.sublistView(payload);
    var cursor = nul + 1;
    for (var ch = 0; ch < 32 && cursor + 4 <= payload.length; ch++) {
      final channel = payload[cursor];
      final rawGain = data.getInt16(cursor + 1, Endian.big);
      final peakBits = payload[cursor + 3];
      cursor += 4;
      final peakBytes = (peakBits + 7) >> 3;
      if (peakBits > 64 || cursor + peakBytes > payload.length) return null;
      if (channel == 0x01) {
        final gainDb = rawGain / 512.0;
        if (!gainDb.isFinite || gainDb < -60 || gainDb > 30) return null;
        double? peak;
        if (peakBits == 16 && peakBytes == 2) {
          final peakRaw = data.getUint16(cursor, Endian.big);
          if (peakRaw > 0) {
            final normalized = peakRaw / 32768.0;
            if (normalized.isFinite && normalized > 0 && normalized <= 64) {
              peak = normalized;
            }
          }
        }
        return (isAlbum: isAlbum, gainDb: gainDb, peak: peak);
      }
      cursor += peakBytes;
    }
    return null;
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
