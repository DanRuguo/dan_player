import 'dart:io';
import 'package:flutter/services.dart';
import 'font_policy.dart';
import 'font_collection.dart';

final _loaded = <(String, String, String), Future<void>>{};

/// Each Flutter engine owns its font registry. Concurrent requests share IO;
/// failures are removed so a restored custom file can be retried.
Future<void> ensureAppFontsLoaded(AppFontPolicy policy) async {
  final faces = <AppFontFace>{...policy.faces, policy.baseFallback};
  await Future.wait(faces.map(ensureAppFontLoaded));
}

Future<void> ensureAppFontLoaded(AppFontFace face) {
  final source = face.asset ?? face.path;
  if (source == null) return Future<void>.value();
  final selectedName = face.nativeFamily ?? face.family;
  final key = (face.family, source, selectedName);
  return _loaded.putIfAbsent(key, () async {
    try {
      final bytes = face.asset != null
          ? await _bundledBytes(face.asset!)
          : ByteData.sublistView(await File(face.path!).readAsBytes());
      _validateFont(bytes);
      final selected = fontBytesForFace(bytes, selectedName);
      final loader = FontLoader(face.family)..addFont(Future.value(selected));
      await loader.load();
    } catch (_) {
      _loaded.remove(key);
      rethrow;
    }
  });
}

Future<ByteData> _bundledBytes(String asset) async {
  try {
    return await rootBundle.load(asset);
  } catch (_) {
    const prefix = 'packages/desktop_lyric/';
    if (!asset.startsWith(prefix)) rethrow;
    // The optional standalone package has local asset keys; the shared host
    // uses canonical package keys. Both register the same logical family.
    return rootBundle.load(asset.substring(prefix.length));
  }
}

// FontLoader may complete after the engine rejects invalid bytes. Validate the
// SFNT directory first so a broken file cannot be saved as an applied font.
void _validateFont(ByteData data) {
  Never invalid() => throw const FormatException('Invalid font data');
  if (data.lengthInBytes < 12) invalid();
  final offsets = <int>[0];
  if (data.getUint32(0) == 0x74746366) {
    final count = data.getUint32(8);
    if (count == 0 || count > (data.lengthInBytes - 12) ~/ 4) invalid();
    offsets.clear();
    for (var i = 0; i < count; i++) {
      offsets.add(data.getUint32(12 + i * 4));
    }
  }
  for (final offset in offsets) {
    if (offset > data.lengthInBytes - 12) invalid();
    final signature = data.getUint32(offset);
    if (signature != 0x00010000 &&
        signature != 0x4f54544f &&
        signature != 0x74727565) {
      invalid();
    }
    final tables = data.getUint16(offset + 4);
    if (tables == 0 || tables > (data.lengthInBytes - offset - 12) ~/ 16) {
      invalid();
    }
    final directory = <int, (int, int)>{};
    for (var i = 0; i < tables; i++) {
      final tag = data.getUint32(offset + 12 + i * 16);
      final start = data.getUint32(offset + 12 + i * 16 + 8);
      final length = data.getUint32(offset + 12 + i * 16 + 12);
      if (start > data.lengthInBytes || length > data.lengthInBytes - start) {
        invalid();
      }
      if (directory.containsKey(tag)) invalid();
      directory[tag] = (start, length);
    }
    (int, int) requiredTable(int tag, int minimum) {
      final table = directory[tag];
      if (table == null || table.$2 < minimum) invalid();
      return table;
    }

    final head = requiredTable(0x68656164, 54);
    if (data.getUint32(head.$1 + 12) != 0x5f0f3cf5) invalid();
    final units = data.getUint16(head.$1 + 18);
    if (units < 16 || units > 16384) invalid();
    final maxp = requiredTable(0x6d617870, 6);
    final glyphs = data.getUint16(maxp.$1 + 4);
    final hhea = requiredTable(0x68686561, 36);
    final metrics = data.getUint16(hhea.$1 + 34);
    if (glyphs == 0 || metrics == 0 || metrics > glyphs) invalid();
    requiredTable(0x686d7478, metrics * 4 + (glyphs - metrics) * 2);
    final cmap = requiredTable(0x636d6170, 4);
    final encodings = data.getUint16(cmap.$1 + 2);
    if (data.getUint16(cmap.$1) != 0 ||
        encodings == 0 ||
        encodings > (cmap.$2 - 4) ~/ 8) {
      invalid();
    }
    for (var i = 0; i < encodings; i++) {
      final relative = data.getUint32(cmap.$1 + 4 + i * 8 + 4);
      if (relative > cmap.$2 - 2) invalid();
      final start = cmap.$1 + relative;
      final format = data.getUint16(start);
      final minimum = switch (format) {
        0 => 262,
        2 => 518,
        4 => 16,
        6 => 10,
        8 => 8208,
        10 => 20,
        12 || 13 => 16,
        14 => 10,
        _ => 0
      };
      if (minimum == 0 || minimum > cmap.$2 - relative) invalid();
      final length = format == 14
          ? data.getUint32(start + 2)
          : format >= 8
              ? data.getUint32(start + 4)
              : data.getUint16(start + 2);
      if (length < minimum || length > cmap.$2 - relative) invalid();
    }
    final cff = directory[0x43464620] ?? directory[0x43464632];
    if (cff != null) {
      if (cff.$2 < 4 ||
          data.getUint8(cff.$1) < 1 ||
          data.getUint8(cff.$1) > 2 ||
          data.getUint8(cff.$1 + 2) < 4 ||
          data.getUint8(cff.$1 + 2) > cff.$2) {
        invalid();
      }
    } else if (directory.containsKey(0x676c7966)) {
      final format = data.getInt16(head.$1 + 50);
      if (format != 0 && format != 1) invalid();
      requiredTable(0x6c6f6361, (glyphs + 1) * (format == 0 ? 2 : 4));
    } else if (!((directory[0x43424454]?.$2 ?? 0) > 0 &&
            (directory[0x43424c43]?.$2 ?? 0) > 0) &&
        !((directory[0x45424454]?.$2 ?? 0) > 0 &&
            (directory[0x45424c43]?.$2 ?? 0) > 0) &&
        (directory[0x73626978]?.$2 ?? 0) == 0) {
      invalid();
    }
  }
}
