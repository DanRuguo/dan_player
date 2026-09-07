import 'dart:convert';
import 'dart:ffi';

import 'package:dan_player/play_service/replay_gain.dart';

final class _BassBinaryTag extends Struct {
  external Pointer<Uint8> data;

  @Uint32()
  external int length;
}

/// Read only while this worker exclusively owns the uncommitted decoder.
/// BASS owns the pointers; no pointer is returned across isolates or retained
/// after wrapping/freeing a stream. Missing/unsupported tags are normal.
ReplayGainTags readBassReplayGain(DynamicLibrary library, int handle) {
  if (handle == 0) return const ReplayGainTags();
  final getTags = library.lookupFunction<
      Pointer<Uint8> Function(Uint32, Uint32),
      Pointer<Uint8> Function(int, int)>('BASS_ChannelGetTags');
  var result = const ReplayGainTags();
  // FLAC uses the same Vorbis comment interface as Ogg. APE and MP4 tags also
  // use UTF-8 key=value lists; they need no format-specific string heuristics.
  for (final type in [2, 6, 7]) {
    final pointer = getTags(handle, type);
    if (pointer == nullptr) continue;
    final comments = <String>[];
    var start = 0;
    for (var offset = 0; offset < 1024 * 1024; offset++) {
      if (pointer[offset] != 0) continue;
      if (offset == start) break;
      if (offset - start <= 8192) {
        comments.add(utf8.decode(
          (pointer + start).asTypedList(offset - start),
          allowMalformed: true,
        ));
      }
      start = offset + 1;
      if (comments.length >= 512) break;
    }
    result = result.fillMissing(ReplayGainTags.fromComments(comments));
  }
  // Unlike the older raw pointer tag, TAG_BINARY supplies an authoritative
  // buffer length. Never trust an ID3 file's claimed size as native memory size.
  for (final type in [20, 21]) {
    final pointer = getTags(handle, type);
    if (pointer == nullptr) continue;
    final tag = pointer.cast<_BassBinaryTag>().ref;
    if (tag.data == nullptr ||
        tag.length < 10 ||
        tag.length > 64 * 1024 * 1024) {
      continue;
    }
    result = result.fillMissing(
      ReplayGainTags.fromId3(tag.data.asTypedList(tag.length)),
    );
  }
  return result;
}
