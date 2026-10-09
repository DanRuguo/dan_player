import 'dart:typed_data';

/// Register only the requested face of a validated TTC. Flutter's FontLoader
/// otherwise registers face zero under the supplied family alias. Standalone
/// fonts are returned unchanged; legacy aliases retain the first-face fallback.
ByteData fontBytesForFace(ByteData data, String name) {
  if (data.getUint32(0) != 0x74746366) return data;
  var selected = data.getUint32(12);
  // Exact full names distinguish sibling faces. A family-name fallback also
  // supports older settings that stored the family rather than the full name.
  var matched = false;
  for (final nameId in [4, 1]) {
    for (var face = 0; face < data.getUint32(8); face++) {
      final offset = data.getUint32(12 + face * 4);
      if (_hasName(data, offset, name, nameId)) {
        selected = offset;
        matched = true;
        break;
      }
    }
    if (matched) break;
  }
  final tables = <(int, int, int)>[];
  for (var index = 0; index < data.getUint16(selected + 4); index++) {
    final record = selected + 12 + index * 16;
    final tag = data.getUint32(record);
    // An original file's digital signature cannot describe a reconstructed
    // standalone face. The font outlines, names and shaping tables are retained.
    if (tag != 0x44534947) {
      tables
          .add((tag, data.getUint32(record + 8), data.getUint32(record + 12)));
    }
  }
  tables.sort((a, b) => a.$1.compareTo(b.$1));
  final directorySize = 12 + tables.length * 16;
  final bytes = Uint8List(directorySize +
      tables.fold(0, (sum, table) => sum + ((table.$3 + 3) & ~3)));
  final out = ByteData.sublistView(bytes);
  out.setUint32(0, data.getUint32(selected));
  out.setUint16(4, tables.length);
  var power = 1, selector = 0;
  while (power * 2 <= tables.length) {
    power *= 2;
    selector++;
  }
  out.setUint16(6, power * 16);
  out.setUint16(8, selector);
  out.setUint16(10, tables.length * 16 - power * 16);
  var offset = directorySize, head = 0;
  for (final (index, table) in tables.indexed) {
    final (tag, start, length) = table;
    bytes.setRange(offset, offset + length,
        data.buffer.asUint8List(data.offsetInBytes + start, length));
    if (tag == 0x68656164) {
      head = offset;
      out.setUint32(head + 8, 0);
    }
    final record = 12 + index * 16;
    out.setUint32(record, tag);
    out.setUint32(record + 4, _checksum(out, offset, (length + 3) & ~3));
    out.setUint32(record + 8, offset);
    out.setUint32(record + 12, length);
    offset += (length + 3) & ~3;
  }
  out.setUint32(
      head + 8, (0xb1b0afba - _checksum(out, 0, bytes.length)) & 0xffffffff);
  return out;
}

int _checksum(ByteData data, int offset, int length) {
  var sum = 0;
  for (var index = offset; index < offset + length; index += 4) {
    sum = (sum + data.getUint32(index)) & 0xffffffff;
  }
  return sum;
}

bool _hasName(ByteData data, int face, String requested, int nameId) {
  for (var table = 0; table < data.getUint16(face + 4); table++) {
    final record = face + 12 + table * 16;
    if (data.getUint32(record) != 0x6e616d65) continue;
    final start = data.getUint32(record + 8),
        length = data.getUint32(record + 12);
    if (length < 6) return false;
    final count = data.getUint16(start + 2),
        strings = data.getUint16(start + 4);
    if (count > (length - 6) ~/ 12 || strings > length) return false;
    for (var index = 0; index < count; index++) {
      final name = start + 6 + index * 12;
      final platform = data.getUint16(name),
          encoding = data.getUint16(name + 2);
      if (data.getUint16(name + 6) != nameId ||
          !(platform == 0 ||
              platform == 3 &&
                  (encoding == 0 || encoding == 1 || encoding == 10))) {
        continue;
      }
      final size = data.getUint16(name + 8), offset = data.getUint16(name + 10);
      if (size.isOdd ||
          offset > length - strings ||
          size > length - strings - offset) {
        continue;
      }
      final value = String.fromCharCodes([
        for (var at = start + strings + offset;
            at < start + strings + offset + size;
            at += 2)
          data.getUint16(at)
      ]);
      if (value == requested) return true;
    }
    return false;
  }
  return false;
}
