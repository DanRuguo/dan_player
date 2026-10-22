import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

const _encodingError = FormatException('请将歌单另存为 UTF-8 编码的 M3U8 文件。');

/// M3U8 is always UTF-8. Legacy M3U additionally accepts BOM-marked UTF-16
/// and, after strict UTF-8 fails, the current Windows ANSI code page. This
/// follows the local machine's legacy text convention; it is not detection of
/// arbitrary GBK/Shift-JIS/Windows-1252 files from another computer.
String decodeM3uText(List<int> bytes, {required String playlistPath}) {
  final legacy = playlistPath.toLowerCase().endsWith('.m3u');
  if (!legacy) return _utf8(bytes);
  return _decodeLegacy(bytes, allowAnsi: true);
}

/// PLS shares M3U's local legacy convention. XML accepts only Unicode, and
/// its declaration must agree with the bytes rather than silently garbling a
/// path from an unsupported legacy XML encoding.
String decodeLocalPlaylistText(List<int> bytes,
    {required String playlistPath}) {
  final lower = playlistPath.toLowerCase();
  if (!lower.endsWith('.pls') && !lower.endsWith('.xspf')) {
    return decodeM3uText(bytes, playlistPath: playlistPath);
  }
  final xml = lower.endsWith('.xspf');
  try {
    final text = _decodeLegacy(bytes, allowAnsi: !xml);
    if (xml) {
      final declaration =
          RegExp(r'''^\s*<\?xml\s[^?]*encoding\s*=\s*["']([^"']+)["']''')
              .firstMatch(text);
      final encoding = declaration?.group(1)?.toLowerCase();
      final little = bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe;
      final big = bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff;
      if (encoding != null &&
          !(little
              ? encoding == 'utf-16' || encoding == 'utf-16le'
              : big
                  ? encoding == 'utf-16' || encoding == 'utf-16be'
                  : encoding == 'utf-8')) {
        throw _encodingError;
      }
    }
    return text;
  } on FormatException {
    throw FormatException(xml
        ? 'XSPF 编码无效，请使用 UTF-8 或带 BOM 的 UTF-16。'
        : 'PLS 编码无效，请使用 UTF-8 或带 BOM 的 UTF-16。');
  }
}

String _decodeLegacy(List<int> bytes, {required bool allowAnsi}) {
  if (bytes.isEmpty) return '';

  bool startsWith(List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  const unicodeMarks = [
    [0xef, 0xbb, 0xbf],
    [0xff, 0xfe],
    [0xfe, 0xff],
    [0xff, 0xfe, 0, 0],
    [0, 0, 0xfe, 0xff],
  ];
  // UTF-32 is intentionally unsupported, including the little-endian mark
  // whose first two bytes are also the UTF-16 mark.
  if (startsWith(unicodeMarks[3]) || startsWith(unicodeMarks[4])) {
    throw _encodingError;
  }
  if (startsWith(unicodeMarks[1]) || startsWith(unicodeMarks[2])) {
    if (bytes.length.isOdd) throw _encodingError;
    final littleEndian = bytes[0] == 0xff;
    final units = [
      for (var i = 2; i < bytes.length; i += 2)
        littleEndian
            ? bytes[i] | bytes[i + 1] << 8
            : bytes[i] << 8 | bytes[i + 1],
    ];
    return _utf16(units);
  }
  // An incomplete BOM is not an ANSI path.
  for (final mark in unicodeMarks) {
    if (bytes.length < mark.length &&
        List.generate(bytes.length, (i) => bytes[i] == mark[i])
            .every((same) => same)) {
      throw _encodingError;
    }
  }
  // A declared UTF-8 encoding must not fall back and turn corruption into a
  // different local filename. BOM-less UTF-8 retains priority over ANSI.
  if (startsWith(unicodeMarks[0])) return _utf8(bytes);
  try {
    return utf8.decode(bytes);
  } on FormatException {
    if (!allowAnsi || !Platform.isWindows) throw _encodingError;
    return _windowsAnsi(bytes);
  }
}

String _utf8(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw _encodingError;
  }
}

String _utf16(List<int> units) {
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
        throw _encodingError;
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw _encodingError;
    }
  }
  return String.fromCharCodes(units);
}

String _windowsAnsi(List<int> bytes) {
  final kernel = DynamicLibrary.open('kernel32.dll');
  final convert = kernel.lookupFunction<
      Int32 Function(
          Uint32, Uint32, Pointer<Uint8>, Int32, Pointer<Uint16>, Int32),
      int Function(int, int, Pointer<Uint8>, int, Pointer<Uint16>, int)>(
    'MultiByteToWideChar',
  );
  final input = calloc<Uint8>(bytes.length);
  Pointer<Uint16>? output;
  try {
    input.asTypedList(bytes.length).setAll(0, bytes);
    // CP_ACP + MB_ERR_INVALID_CHARS rejects invalid byte sequences instead
    // of substituting U+FFFD. Never retry with a lossy conversion flag.
    final count = convert(0, 8, input, bytes.length, nullptr, 0);
    if (count == 0) throw _encodingError;
    output = calloc<Uint16>(count);
    if (convert(0, 8, input, bytes.length, output, count) != count) {
      throw _encodingError;
    }
    return _utf16(output.asTypedList(count));
  } finally {
    calloc.free(input);
    if (output != null) calloc.free(output);
    kernel.close();
  }
}
