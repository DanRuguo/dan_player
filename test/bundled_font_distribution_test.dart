import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../scripts/support/sfnt_font.dart';

const _fontSha256 =
    '2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b';
const _fontGitBlob = 'dc15562470b4f842321894787a0d066879ccff8b';
const _upstreamCommit = '523d033d6cb47f4a80c58a35753646f5c3608a78';
const _licenseSha256 =
    '6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2';
const _fontPaths = [
  'assets/fonts/PingFangSC-Regular.ttf',
  'third_party/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf',
];

void main() {
  late List<Uint8List> fontBytes;
  late List<SfntFont> fonts;
  late List<Map<int, Set<String>>> names;
  setUpAll(() {
    fontBytes = [for (final path in _fontPaths) File(path).readAsBytesSync()];
    fonts = [for (final bytes in fontBytes) SfntFont.parse(bytes)];
    names = [for (final bytes in fontBytes) _unicodeNames(bytes)];
  });

  test('both compatibility asset paths contain the unchanged upstream OTF', () {
    for (var index = 0; index < fontBytes.length; index++) {
      final bytes = fontBytes[index];
      expect(bytes.length, 16437364, reason: _fontPaths[index]);
      expect(sha256.convert(bytes).toString(), _fontSha256,
          reason: _fontPaths[index]);
      expect(ascii.decode(bytes.sublist(0, 4)), 'OTTO');
    }
  });

  test('the actual font blob matches its pinned upstream source provenance',
      () {
    for (final bytes in fontBytes) {
      final gitBytes = (BytesBuilder(copy: false)
            ..add(utf8.encode('blob ${bytes.length}\u0000'))
            ..add(bytes))
          .takeBytes();
      expect(sha1.convert(gitBytes).toString(), _fontGitBlob);
    }
    final provenance =
        File('licenses/NOTO-SANS-CJK/PROVENANCE.md').readAsStringSync();
    for (final source in [
      'https://github.com/notofonts/noto-cjk',
      'Sans2.004',
      _upstreamCommit,
      'Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf',
      _fontGitBlob,
      _fontSha256,
      _licenseSha256,
    ]) {
      expect(provenance, contains(source));
    }
  });

  test('the real name tables identify Noto with its original Adobe copyright',
      () {
    for (final name in names) {
      expect(name[0], {'© 2014-2021 Adobe (http://www.adobe.com/).'});
      expect(name[1], {'Noto Sans CJK SC'});
      expect(name[2], {'Regular'});
      expect(name[4], {'Noto Sans CJK SC'});
      expect(name[5], isNotEmpty);
      for (final version in name[5]!) {
        expect(version, startsWith('Version 2.004;'));
      }
      expect(name[6], {'NotoSansCJKsc-Regular'});
    }
  });

  test('the bundled license is the original OFL and agrees with font metadata',
      () {
    final licenseBytes =
        File('licenses/NOTO-SANS-CJK/OFL.txt').readAsBytesSync();
    expect(sha256.convert(licenseBytes).toString(), _licenseSha256);
    final license = utf8.decode(licenseBytes);
    expect(license, contains('SIL OPEN FONT LICENSE Version 1.1'));
    expect(license, contains('may be bundled,'));
    expect(license, contains('redistributed and/or sold with any software'));
    for (final name in names) {
      expect(name[13], isNotEmpty);
      for (final description in name[13]!) {
        expect(description, contains('SIL Open Font License, Version 1.1'));
      }
      expect(name[14], {'http://scripts.sil.org/OFL'});
    }
  });

  test('the readable notice preserves every embedded Unicode copyright entry',
      () {
    final notice = File('licenses/NOTO-SANS-CJK/NOTICE.txt').readAsStringSync();
    for (final name in names) {
      for (final copyright in name[0]!) {
        expect(notice, contains(copyright));
      }
    }
    expect(notice, contains('OFL.txt'));
    expect(notice, contains('PROVENANCE.md'));
  });

  test('saved Flutter aliases remain compatible while the display name is Noto',
      () {
    expect(danEmbeddedFontFamily, 'DanPingFangSC');
    expect(danCjkFontFamily, danEmbeddedFontFamily);
    expect(danFontDisplayName(danEmbeddedFontFamily), 'Noto Sans CJK SC');
    expect(danFontDisplayName(null), 'Noto Sans CJK SC');
    for (final prefix in ['', 'third_party/desktop_lyric/']) {
      final pubspec = File('${prefix}pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('family: $danEmbeddedFontFamily'));
      expect(pubspec, contains('asset: assets/fonts/PingFangSC-Regular.ttf'));
    }
  });

  const samples = {
    'English': 'DanPlayer0123',
    'Chinese': '歌词播放汉语音量',
    'Japanese': '日本語あいうアイウ再生',
    'Korean': '한국어한글음악재생',
  };
  for (final sample in samples.entries) {
    test('both actual fonts map representative ${sample.key} glyphs', () {
      for (var index = 0; index < fonts.length; index++) {
        for (final rune in sample.value.runes) {
          expect(fonts[index].glyphIndex(rune), greaterThan(0),
              reason: '${_fontPaths[index]} lacks '
                  'U+${rune.toRadixString(16)} (${String.fromCharCode(rune)})');
        }
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
