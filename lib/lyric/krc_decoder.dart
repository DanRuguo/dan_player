import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// KRC's public container: four-byte signature, XOR stream, zlib UTF-8.
/// Cap expanded output as well as the transport's compressed response limit.
String decodeKrcContainer(String value) {
  final data = base64Decode(value.replaceAll(RegExp(r'\s+'), ''));
  if (data.length < 5 ||
      data[0] != 107 ||
      data[1] != 114 ||
      data[2] != 99 ||
      data[3] != 49) {
    throw const FormatException('Invalid KRC container');
  }
  const mask = [
    64,
    71,
    97,
    119,
    94,
    50,
    116,
    71,
    81,
    54,
    49,
    45,
    206,
    210,
    110,
    105
  ];
  final compressed = Uint8List(data.length - 4);
  for (var i = 0; i < compressed.length; i++) {
    compressed[i] = data[i + 4] ^ mask[i % mask.length];
  }
  return decodeLyricZlib(compressed);
}

String decodeLyricZlib(List<int> compressed) {
  final sink = _BoundedLyricsSink();
  final decoder = zlib.decoder.startChunkedConversion(sink);
  decoder.add(compressed);
  decoder.close();
  return utf8.decode(sink.bytes.takeBytes());
}

class _BoundedLyricsSink implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> data) {
    if (bytes.length + data.length > 1024 * 1024) {
      throw const FormatException('Expanded lyrics too large');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}
