import 'dart:convert';

/// Decodes the Unicode encodings supported by the local lyric reader without
/// silently replacing invalid bytes that could later overwrite the original.
String decodeLyricText(List<int> bytes) {
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff))) {
    if (bytes.length.isOdd) {
      throw const FormatException('UTF-16 歌词文件长度无效');
    }
    final littleEndian = bytes[0] == 0xff;
    final codeUnits = <int>[];
    for (var i = 2; i < bytes.length; i += 2) {
      codeUnits.add(littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(codeUnits);
  }
  return utf8.decode(bytes).replaceFirst('\uFEFF', '');
}
