import 'bass.dart' as bass;

/// Source coordinates stay absolute inside BASS (also through BASS_FX and
/// BASSmix); the public player exposes this segment's relative timeline.
class AudioSegment {
  const AudioSegment(this.start, [this.end]);
  final double start;
  final double? end;

  double duration(double sourceLength) {
    if (!start.isFinite ||
        start < 0 ||
        !sourceLength.isFinite ||
        sourceLength <= start ||
        (end != null &&
            (!end!.isFinite ||
                end! <= start ||
                end! > sourceLength + 1 / 75))) {
      throw const FormatException('CUE 分轨时间超出音频文件范围，请检查 CUE 与音频是否匹配。');
    }
    return (end == null || end! > sourceLength ? sourceLength : end!) - start;
  }

  double sourcePosition(double relative, double duration) {
    if (!relative.isFinite) throw const FormatException('播放位置无效。');
    return start + relative.clamp(0, duration);
  }

  double relativePosition(double absolute, double duration) =>
      (absolute - start).clamp(0, duration);
}

/// BASS 2.4.16+ enforces this boundary in the decoder, before any output
/// buffer or tempo processing. A UI timer must never determine track cuts.
double prepareBassSegment(bass.Bass api, int handle, AudioSegment segment) {
  final fullLength = api.BASS_ChannelBytes2Seconds(
      handle, api.BASS_ChannelGetLength(handle, bass.BASS_POS_BYTE));
  final length = segment.duration(fullLength);
  const positionEnd = 0x10; // BASS_POS_END, official bass.h
  if ((segment.end != null &&
          api.BASS_ChannelSetPosition(
                  handle,
                  api.BASS_ChannelSeconds2Bytes(handle, segment.start + length),
                  positionEnd) ==
              0) ||
      api.BASS_ChannelSetPosition(
              handle,
              api.BASS_ChannelSeconds2Bytes(handle, segment.start),
              bass.BASS_POS_BYTE) ==
          0) {
    throw FormatException('无法设置 CUE 分轨边界（BASS ${api.BASS_ErrorGetCode()}）。');
  }
  return length;
}
