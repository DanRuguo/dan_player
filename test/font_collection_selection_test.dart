import 'dart:io';

import 'package:desktop_lyric/font_collection.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Assemble unmodified open-font faces into a TTC. Table offsets in a
// collection refer to the whole file, rather than the individual face.
Uint8List _collection(List<Uint8List> faces) {
  final header = (12 + faces.length * 4 + 3) & ~3;
  final result = Uint8List(
      header + faces.fold(0, (sum, face) => sum + ((face.length + 3) & ~3)));
  final out = ByteData.sublistView(result);
  out.setUint32(0, 0x74746366);
  out.setUint32(4, 0x00010000);
  out.setUint32(8, faces.length);
  var offset = header;
  for (final (index, face) in faces.indexed) {
    result.setRange(offset, offset + face.length, face);
    out.setUint32(12 + index * 4, offset);
    final input = ByteData.sublistView(face);
    for (var table = 0; table < input.getUint16(4); table++) {
      final record = 12 + table * 16;
      out.setUint32(offset + record + 8, offset + input.getUint32(record + 8));
    }
    offset += (face.length + 3) & ~3;
  }
  return result;
}

List<double> _metrics(String family) {
  final result = <double>[];
  for (final text in ['WWWWiiii', 'Dan Player 012345', 'AVATAR fj']) {
    final painter = TextPainter(
        text: TextSpan(
            text: text, style: TextStyle(fontFamily: family, fontSize: 32)),
        textDirection: TextDirection.ltr)
      ..layout();
    result.addAll([painter.width, painter.height]);
    painter.dispose();
  }
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List first, second, collection;
  setUpAll(() async {
    first =
        await File('third_party/desktop_lyric/assets/fonts/GoogleSans-VF.ttf')
            .readAsBytes();
    second = await File(
            'third_party/desktop_lyric/assets/fonts/Pretendard-Regular.otf')
        .readAsBytes();
    collection = _collection([first, second]);
    await (FontLoader('QA collection first')
          ..addFont(Future.value(ByteData.sublistView(first))))
        .load();
    await (FontLoader('QA collection second')
          ..addFont(Future.value(ByteData.sublistView(second))))
        .load();
  });
  test('a collection loads the requested second face instead of its first face',
      () async {
    final directory = await Directory.systemTemp.createTemp('dan-collection-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/open-fonts.ttc');
    await file.writeAsBytes(collection);
    final expected = _metrics('QA collection second');
    expect(_metrics('QA collection first'), isNot(expected),
        reason: 'The fixture must distinguish the two real fonts');
    await ensureAppFontLoaded(
        AppFontFace(id: 'custom', family: 'Pretendard', path: file.path));
    expect(_metrics('Pretendard'), expected,
        reason:
            'The selected face name must control which TTC face is registered');
  });
  test('full face name selects the second face under a separate logical alias',
      () async {
    final directory = await Directory.systemTemp.createTemp('dan-collection-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/open-fonts.ttc');
    await file.writeAsBytes(collection);
    await ensureAppFontLoaded(AppFontFace(
        id: 'custom',
        family: 'QA selected full name',
        nativeFamily: 'Pretendard Regular',
        path: file.path));
    expect(_metrics('QA selected full name'), _metrics('QA collection second'));
  });
  test('unknown legacy alias retains face zero without altering its glyphs',
      () async {
    final data =
        fontBytesForFace(ByteData.sublistView(collection), 'old alias');
    await (FontLoader('QA legacy collection')..addFont(Future.value(data)))
        .load();
    expect(_metrics('QA legacy collection'), _metrics('QA collection first'));
  });
  test('standalone fonts retain the original byte view', () {
    final data = ByteData.sublistView(second);
    expect(identical(fontBytesForFace(data, 'any alias'), data), isTrue);
  });
  test('extracted face preserves every shaping table and SFNT integrity', () {
    final original = Uint8List.fromList(collection);
    // A nonzero ByteData offset must not accidentally copy unrelated bytes.
    final wrapped = Uint8List(collection.length + 16)
      ..setRange(8, 8 + collection.length, collection);
    final data = fontBytesForFace(
        ByteData.sublistView(wrapped, 8, 8 + collection.length),
        'Pretendard Regular');
    final input = ByteData.sublistView(second);
    final tables = <int, Uint8List>{};
    for (var i = 0; i < input.getUint16(4); i++) {
      final record = 12 + i * 16;
      final tag = input.getUint32(record);
      if (tag == 0x44534947) continue;
      final bytes = Uint8List.fromList(second.sublist(
          input.getUint32(record + 8),
          input.getUint32(record + 8) + input.getUint32(record + 12)));
      if (tag == 0x68656164) ByteData.sublistView(bytes).setUint32(8, 0);
      tables[tag] = bytes;
    }
    expect(data.getUint16(4), tables.length);
    for (var i = 0; i < data.getUint16(4); i++) {
      final record = 12 + i * 16;
      final tag = data.getUint32(record),
          offset = data.getUint32(record + 8),
          length = data.getUint32(record + 12);
      expect(offset % 4, 0);
      final bytes = Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes + offset, length));
      if (tag == 0x68656164) ByteData.sublistView(bytes).setUint32(8, 0);
      expect(bytes, tables.remove(tag),
          reason: 'Selected table $tag must stay byte-for-byte intact');
    }
    expect(tables, isEmpty);
    var checksum = 0;
    for (var offset = 0; offset < data.lengthInBytes; offset += 4) {
      checksum = (checksum + data.getUint32(offset)) & 0xffffffff;
    }
    expect(checksum, 0xb1b0afba);
    expect(collection, original,
        reason: 'Selecting a face must not modify the source font');
  });
  test('invalid sibling face fails preflight and a restored collection retries',
      () async {
    final directory = await Directory.systemTemp.createTemp('dan-collection-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/restored.ttc');
    final broken = Uint8List.fromList(collection);
    final view = ByteData.sublistView(broken);
    view.setUint32(view.getUint32(16), 0);
    await file.writeAsBytes(broken);
    final face = AppFontFace(
        id: 'custom',
        family: 'QA restored collection',
        nativeFamily: 'Google Sans Regular',
        path: file.path);
    await expectLater(ensureAppFontLoaded(face), throwsFormatException);
    await file.writeAsBytes(collection);
    await ensureAppFontLoaded(face);
    expect(_metrics(face.family), _metrics('QA collection first'));
  });
}
