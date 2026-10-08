import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../scripts/support/bundled_font_assets.dart';
import '../scripts/support/sfnt_font.dart';

void main() {
  late Map<String, dynamic> catalogJson;
  late BundledFontCatalog catalog;
  late List<Uint8List> fontBytes;
  late List<SfntFont> fonts;
  late List<Map<int, Set<String>>> names;
  setUpAll(() {
    catalogJson = jsonDecode(
        File('scripts/support/bundled_fonts.json').readAsStringSync());
    catalog = BundledFontCatalog.parse(catalogJson);
    fontBytes = [
      for (final font in catalog.fonts) File(font.source).readAsBytesSync()
    ];
    fonts = [for (final bytes in fontBytes) SfntFont.parse(bytes)];
    names = [for (final bytes in fontBytes) _unicodeNames(bytes)];
  });

  test('the four shared resources contain unchanged pinned upstream fonts', () {
    for (var index = 0; index < fontBytes.length; index++) {
      final bytes = fontBytes[index];
      final font = catalog.fonts[index];
      expect(bytes.length, font.bytes, reason: font.source);
      expect(sha256.convert(bytes).toString(), font.sha256,
          reason: font.source);
      expect(ByteData.sublistView(bytes).getUint32(0, Endian.big),
          font.variable ? 0x00010000 : 0x4f54544f);
    }
  });

  test('the actual font blob matches its pinned upstream source provenance',
      () {
    for (var index = 0; index < fontBytes.length; index++) {
      final bytes = fontBytes[index];
      final gitBytes = (BytesBuilder(copy: false)
            ..add(utf8.encode('blob ${bytes.length}\u0000'))
            ..add(bytes))
          .takeBytes();
      final font = catalog.fonts[index];
      final raw = catalogJson['fonts'][index] as Map<String, dynamic>;
      final upstream = raw['upstream'] as Map<String, dynamic>;
      expect(sha1.convert(gitBytes).toString(), font.gitBlob);
      final provenance =
          File('${raw['licenseDirectory']}/PROVENANCE.md').readAsStringSync();
      for (final source in [
        upstream['repository'],
        upstream['commit'],
        upstream['path'],
        if (upstream['tag'] != null) upstream['tag'],
        font.gitBlob,
        font.sha256,
      ]) {
        expect(provenance, contains(source));
      }
    }
  });

  test('the real name tables retain each original family and copyright', () {
    for (var index = 0; index < names.length; index++) {
      final expected = catalogJson['fonts'][index]['names'] as Map;
      for (final id in [0, 1, 2, 4, 5, 6]) {
        expect(names[index][id], (expected['$id'] as List).toSet());
      }
    }
  });

  test('the bundled license is the original OFL and agrees with font metadata',
      () {
    for (final entry in catalogJson['licenses'] as List) {
      for (final file in entry['files'] as List) {
        final bytes =
            File('${entry['directory']}/${file['name']}').readAsBytesSync();
        expect(sha256.convert(bytes).toString(), file['sha256']);
      }
      final license = File('${entry['directory']}/OFL.txt').readAsStringSync();
      expect(license, contains('SIL OPEN FONT LICENSE Version 1.1'));
      expect(license, contains('may be bundled,'));
      expect(license, contains('redistributed and/or sold with any software'));
    }
    for (final name in names) {
      expect(name[13], isNotEmpty);
      for (final description in name[13]!) {
        expect(description, contains('SIL Open Font License, Version 1.1'));
      }
      expect(name[14], isNotEmpty);
    }
  });

  test('the readable notice preserves every embedded Unicode copyright entry',
      () {
    for (var index = 0; index < names.length; index++) {
      final directory = catalogJson['fonts'][index]['licenseDirectory'];
      final notice = File('$directory/NOTICE.txt').readAsStringSync();
      for (final copyright in names[index][0]!) {
        expect(notice, contains(copyright));
      }
      expect(notice, contains('OFL.txt'));
      expect(notice, contains('PROVENANCE.md'));
    }
  });

  test('shared Flutter registration preserves the legacy family identity', () {
    expect(danEmbeddedFontFamily, 'packages/desktop_lyric/DanPingFangSC');
    expect(danCjkFontFamily, danEmbeddedFontFamily);
    expect(danFontDisplayName(danEmbeddedFontFamily), 'Source Han Sans SC');
    expect(danFontDisplayName(null), 'Source Han Sans SC');
    final owner =
        File('third_party/desktop_lyric/pubspec.yaml').readAsStringSync();
    for (final font in catalog.fonts) {
      expect(owner, contains('family: ${font.family}'));
      expect(owner, contains('asset: ${font.asset}'));
    }
    expect(
        File('pubspec.yaml').readAsStringSync(), isNot(contains('  fonts:')));
    expect(File('assets/fonts/PingFangSC-Regular.ttf').existsSync(), isFalse);
  });

  const samples = {
    'English': 'DanPlayer0123',
    'Chinese': '歌词播放汉语音量',
    'Japanese': '日本語あいうアイウ再生',
    'Korean': '한국어한글음악재생',
  };
  for (final sample in samples.entries) {
    test('the shared fallback maps representative ${sample.key} glyphs', () {
      // Both surfaces use this exact single authoritative full-CJK resource.
      final index =
          catalog.fonts.indexWhere((font) => font.id == 'sourceHanSC');
      for (final rune in sample.value.runes) {
        expect(fonts[index].glyphIndex(rune), greaterThan(0),
            reason: '${catalog.fonts[index].source} lacks '
                'U+${rune.toRadixString(16)} (${String.fromCharCode(rune)})');
      }
    });
  }
}

/// Read only the Unicode name records of the already SFNT-validated asset.
/// Cmap selection and glyph validation come from the existing release reader.
Map<int, Set<String>> _unicodeNames(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var nameOffset = -1;
  var nameLength = 0;
  for (var index = 0; index < data.getUint16(4, Endian.big); index++) {
    final record = 12 + index * 16;
    if (ascii.decode(bytes.sublist(record, record + 4)) != 'name') continue;
    nameOffset = data.getUint32(record + 8, Endian.big);
    nameLength = data.getUint32(record + 12, Endian.big);
    break;
  }
  if (nameOffset < 0 || nameLength < 6) {
    throw const FormatException('The actual font has no name table');
  }
  final count = data.getUint16(nameOffset + 2, Endian.big);
  final storage = nameOffset + data.getUint16(nameOffset + 4, Endian.big);
  if (6 + count * 12 > nameLength) {
    throw const FormatException('The actual font has truncated name records');
  }
  final result = <int, Set<String>>{};
  for (var index = 0; index < count; index++) {
    final record = nameOffset + 6 + index * 12;
    final platform = data.getUint16(record, Endian.big);
    if (platform != 0 && platform != 3) continue;
    final nameId = data.getUint16(record + 6, Endian.big);
    final length = data.getUint16(record + 8, Endian.big);
    final offset = storage + data.getUint16(record + 10, Endian.big);
    if (length.isOdd ||
        offset < storage ||
        offset + length > nameOffset + nameLength) {
      throw const FormatException('The actual font has invalid name text');
    }
    final value = String.fromCharCodes([
      for (var at = offset; at < offset + length; at += 2)
        data.getUint16(at, Endian.big),
    ]);
    result.putIfAbsent(nameId, () => {}).add(value);
  }
  return result;
}
