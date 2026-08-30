import 'dart:typed_data';

/// Read-only SFNT cmap reader used by the release gate. It never needs Flutter,
/// a display, native font installation, fontTools or a playback process.
///
/// Supports the Unicode cmap formats used by Material Icons (including its
/// supplementary-plane codepoints) and Material Symbols variable fonts.
class SfntFont {
  SfntFont._(this.glyphCount, this.isVariable, this._cmap);

  final int glyphCount;
  final bool isVariable;
  final _UnicodeCmap _cmap;

  factory SfntFont.parse(Uint8List bytes) {
    final reader = _Reader(bytes);
    reader.require(0, 12);
    final signature = reader.u32(0);
    if (signature != 0x00010000 &&
        signature != 0x4f54544f &&
        signature != 0x74727565) {
      throw const FormatException('Expected a single-face TTF/OTF font.');
    }
    final tableCount = reader.u16(4);
    if (tableCount == 0 || tableCount > 4096) {
      throw const FormatException('Invalid SFNT table count.');
    }
    reader.require(12, tableCount * 16);
    final tables = <String, _Table>{};
    for (var index = 0; index < tableCount; index++) {
      final record = 12 + index * 16;
      final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
      final offset = reader.u32(record + 8);
      final length = reader.u32(record + 12);
      reader.require(offset, length);
      if (tables.containsKey(tag)) {
        throw FormatException('Duplicate SFNT table: $tag');
      }
      tables[tag] = _Table(offset, length);
    }
    final maxp = tables['maxp'];
    final cmap = tables['cmap'];
    if (maxp == null || maxp.length < 6 || cmap == null || cmap.length < 4) {
      throw const FormatException('Missing/truncated maxp or cmap table.');
    }
    final glyphCount = reader.u16(maxp.offset + 4);
    if (glyphCount == 0) throw const FormatException('Font has no glyphs.');
    if (reader.u16(cmap.offset) != 0) {
      throw const FormatException('Unsupported cmap version.');
    }
    final encodingCount = reader.u16(cmap.offset + 2);
    if (encodingCount > 4096 || 4 + encodingCount * 8 > cmap.length) {
      throw const FormatException('Invalid cmap encoding records.');
    }
    _UnicodeCmap? selectedCmap;
    var selectedPriority = -1;
    final visited = <int>{};
    for (var index = 0; index < encodingCount; index++) {
      final record = cmap.offset + 4 + index * 8;
      final platform = reader.u16(record);
      final encoding = reader.u16(record + 2);
      if (platform != 0 &&
          !(platform == 3 && (encoding == 1 || encoding == 10))) {
        continue;
      }
      final relative = reader.u32(record + 4);
      if (relative + 2 > cmap.length) {
        throw const FormatException('cmap subtable offset is out of bounds.');
      }
      if (!visited.add(relative)) continue;
      final offset = cmap.offset + relative;
      final format = reader.u16(offset);
      if (format != 4 && format != 12 && format != 13) continue;
      const minimumLength = 16;
      if (relative + minimumLength > cmap.length) {
        throw const FormatException('Truncated Unicode cmap header.');
      }
      final length =
          format == 4 ? reader.u16(offset + 2) : reader.u32(offset + 4);
      if (length < minimumLength || relative + length > cmap.length) {
        throw const FormatException('Unicode cmap length is out of bounds.');
      }
      final parsed = format == 4
          ? _Cmap4(reader, offset, length)
          : _CmapGroups(reader, offset, length, format == 13);
      // OpenType specifies selecting one Unicode cmap, preferring the 32-bit
      // repertoire when present. Do not "repair" a broken preferred cmap by
      // unioning glyphs from an older table the Windows renderer won't use.
      final priority = (format == 12
              ? 30
              : format == 4
                  ? 20
                  : 10) +
          (platform == 3 ? 1 : 0);
      if (priority > selectedPriority) {
        selectedCmap = parsed;
        selectedPriority = priority;
      }
    }
    if (selectedCmap == null) {
      throw const FormatException('No supported Unicode cmap (4/12/13).');
    }
    return SfntFont._(glyphCount, tables.containsKey('fvar'), selectedCmap);
  }

  int glyphIndex(int codePoint) {
    if (codePoint < 0 || codePoint > 0x10ffff) return 0;
    final glyph = _cmap.glyphIndex(codePoint);
    if (glyph >= glyphCount) {
      throw FormatException(
          'cmap maps U+${codePoint.toRadixString(16)} outside maxp glyphs.');
    }
    return glyph;
  }

  bool hasGlyph(int codePoint) => glyphIndex(codePoint) != 0;
}

class _Reader {
  _Reader(Uint8List bytes) : data = ByteData.sublistView(bytes);
  final ByteData data;

  void require(int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > data.lengthInBytes) {
      throw const FormatException('Truncated/out-of-bounds font data.');
    }
  }

  int u16(int offset) {
    require(offset, 2);
    return data.getUint16(offset, Endian.big);
  }

  int u32(int offset) {
    require(offset, 4);
    return data.getUint32(offset, Endian.big);
  }
}

class _Table {
  const _Table(this.offset, this.length);
  final int offset;
  final int length;
}

abstract class _UnicodeCmap {
  int glyphIndex(int codePoint);
}

class _Cmap4 implements _UnicodeCmap {
  _Cmap4(this.reader, this.offset, this.length) {
    final twiceCount = reader.u16(offset + 6);
    if (twiceCount == 0 || twiceCount.isOdd) {
      throw const FormatException('Invalid format-4 segment count.');
    }
    count = twiceCount ~/ 2;
    if (16 + count * 8 > length) {
      throw const FormatException('Truncated format-4 segments.');
    }
    ends = offset + 14;
    starts = ends + count * 2 + 2;
    deltas = starts + count * 2;
    ranges = deltas + count * 2;
    var previous = -1;
    for (var index = 0; index < count; index++) {
      final start = reader.u16(starts + index * 2);
      final end = reader.u16(ends + index * 2);
      if (start > end || start <= previous) {
        throw const FormatException('Unsorted/overlapping format-4 segments.');
      }
      previous = end;
      final range = reader.u16(ranges + index * 2);
      if (range != 0 &&
          (range.isOdd ||
              ranges + index * 2 + range + (end - start) * 2 + 2 >
                  offset + length)) {
        throw const FormatException('Format-4 glyph array is out of bounds.');
      }
    }
  }

  final _Reader reader;
  final int offset;
  final int length;
  late final int count;
  late final int ends;
  late final int starts;
  late final int deltas;
  late final int ranges;

  @override
  int glyphIndex(int codePoint) {
    if (codePoint >= 0xffff) return 0;
    for (var index = 0; index < count; index++) {
      if (codePoint > reader.u16(ends + index * 2)) continue;
      final start = reader.u16(starts + index * 2);
      if (codePoint < start) return 0;
      final delta = reader.u16(deltas + index * 2);
      final range = reader.u16(ranges + index * 2);
      if (range == 0) return (codePoint + delta) & 0xffff;
      final glyph =
          reader.u16(ranges + index * 2 + range + (codePoint - start) * 2);
      return glyph == 0 ? 0 : (glyph + delta) & 0xffff;
    }
    return 0;
  }
}

class _CmapGroups implements _UnicodeCmap {
  _CmapGroups(this.reader, this.offset, int length, this.constantGlyph) {
    count = reader.u32(offset + 12);
    if (count > 0x110000 || 16 + count * 12 > length) {
      throw const FormatException('Truncated format-12/13 groups.');
    }
    var previous = -1;
    for (var index = 0; index < count; index++) {
      final record = offset + 16 + index * 12;
      final start = reader.u32(record);
      final end = reader.u32(record + 4);
      if (start > end || start <= previous || end > 0x10ffff) {
        throw const FormatException('Invalid format-12/13 Unicode range.');
      }
      previous = end;
    }
  }

  final _Reader reader;
  final int offset;
  final bool constantGlyph;
  late final int count;

  @override
  int glyphIndex(int codePoint) {
    var low = 0;
    var high = count - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      final record = offset + 16 + middle * 12;
      final start = reader.u32(record);
      final end = reader.u32(record + 4);
      if (codePoint < start) {
        high = middle - 1;
      } else if (codePoint > end) {
        low = middle + 1;
      } else {
        final firstGlyph = reader.u32(record + 8);
        return constantGlyph ? firstGlyph : firstGlyph + codePoint - start;
      }
    }
    return 0;
  }
}
