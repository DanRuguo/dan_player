import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import '../scripts/support/release_font_audit.dart';
import '../scripts/support/sfnt_font.dart';

void main() {
  group('SFNT release glyph reader', () {
    test('format 4 covers BMP icons and applies signed delta modulo 65536', () {
      final font = SfntFont.parse(_font(_cmap4({0xe312: 2, 0xef8c: 3})));
      expect(font.glyphIndex(0xe312), 2);
      expect(font.glyphIndex(0xef8c), 3);
      expect(font.hasGlyph(0xe911), isFalse);
      expect(font.hasGlyph(0xf00e9), isFalse);
      expect(font.hasGlyph(-1), isFalse);
      expect(font.hasGlyph(0x110000), isFalse);
    });

    test('format 4 glyphIdArray applies delta only for nonzero glyphs', () {
      final mapped = _cmap4({0xe312: 2});
      final bytes = Uint8List(mapped.length + 2)..setAll(0, mapped);
      final data = ByteData.sublistView(bytes);
      data.setUint16(2, bytes.length);
      data.setUint16(24, 5);
      data.setUint16(28, 4);
      data.setUint16(32, 2);
      expect(SfntFont.parse(_font(bytes)).glyphIndex(0xe312), 7);
      data.setUint16(32, 0);
      expect(SfntFont.parse(_font(bytes)).hasGlyph(0xe312), isFalse);
    });

    test('format 12 validates supplementary icons, not only 16-bit cmaps', () {
      final font = SfntFont.parse(_font(_cmap12({0xef8c: 2, 0xf00e9: 3})));
      expect(font.hasGlyph(0xef8c), isTrue);
      expect(font.hasGlyph(0xf00e9), isTrue);
      expect(font.hasGlyph(0xf01de), isFalse);
    });

    test(
        'uses the preferred 32-bit cmap, not a union that hides missing glyphs',
        () {
      final font = SfntFont.parse(_font(
        _cmap4({0xe312: 2}),
        additionalSubtables: [
          _cmap12({0xf00e9: 3})
        ],
      ));
      expect(font.hasGlyph(0xf00e9), isTrue);
      expect(font.hasGlyph(0xe312), isFalse,
          reason: 'A renderer selects one cmap; the preferred table is broken '
              'when it omits a BMP glyph present only in the older table.');
    });

    test('format 13 reads a constant-glyph range without expanding Unicode',
        () {
      final cmap = _cmap12({0x10000: 2});
      final data = ByteData.sublistView(cmap);
      data.setUint16(0, 13);
      data.setUint32(20, 0x10ffff);
      final font = SfntFont.parse(_font(cmap));
      expect(font.glyphIndex(0x10000), 2);
      expect(font.glyphIndex(0x10ffff), 2);
    });

    test('variable fonts use their real Unicode cmap too', () {
      final font = SfntFont.parse(_font(_cmap4({0xe312: 2}), variable: true));
      expect(font.isVariable, isTrue);
      expect(font.hasGlyph(0xe312), isTrue);
    });

    test('rejects invalid SFNT signature and truncated table directory', () {
      expect(() => SfntFont.parse(Uint8List(8)), throwsFormatException);
      final wrong = _font(_cmap4({0xe312: 2}));
      ByteData.sublistView(wrong).setUint32(0, 0x74746366);
      expect(() => SfntFont.parse(wrong), throwsFormatException);
      final truncated = _font(_cmap4({0xe312: 2}));
      ByteData.sublistView(truncated).setUint16(4, 400);
      expect(() => SfntFont.parse(truncated), throwsFormatException);
    });

    test('rejects out-of-bounds tables, cmap groups and glyphIdArrays', () {
      final outside = _font(_cmap4({0xe312: 2}));
      ByteData.sublistView(outside).setUint32(20, outside.length + 100);
      expect(() => SfntFont.parse(outside), throwsFormatException);
      final hugeGroups = _cmap12({0xe312: 2});
      ByteData.sublistView(hugeGroups).setUint32(12, 0xffffffff);
      expect(() => SfntFont.parse(_font(hugeGroups)), throwsFormatException);
      final outsideArray = _cmap4({0xe312: 2});
      ByteData.sublistView(outsideArray).setUint16(28, 0xfffe);
      expect(() => SfntFont.parse(_font(outsideArray)), throwsFormatException);
    });

    test('rejects overlapping Unicode groups and glyphs beyond maxp', () {
      final overlapping = _cmap12({0xe312: 2, 0xe911: 3});
      ByteData.sublistView(overlapping).setUint32(28, 0xe312);
      expect(() => SfntFont.parse(_font(overlapping)), throwsFormatException);
      final font = SfntFont.parse(_font(_cmap12({0xe312: 500}), glyphCount: 5));
      expect(() => font.hasGlyph(0xe312), throwsFormatException);
    });

    test('does not treat glyph zero/notdef as a present icon', () {
      final font = SfntFont.parse(_font(_cmap12({0xe312: 0})));
      expect(font.hasGlyph(0xe312), isFalse);
    });
  });

  group('constant requirements and final-bundle audit', () {
    test(
        'normalizes packages, deduplicates and excludes framework system icons',
        () {
      final requirements = IconRequirements.fromConstFinder({
        'constantInstances': [
          _icon(0xe312, 'MaterialSymbolsOutlined', 'material_symbols_icons'),
          _icon(0xe312, 'MaterialSymbolsOutlined', 'material_symbols_icons'),
          _icon(0xf00e9, 'MaterialIcons'),
          {'codePoint': 0, 'fontFamily': null, 'fontPackage': null},
          {'codePoint': 0x1f74a, 'fontFamily': null, 'fontPackage': null},
        ],
        'nonConstantLocations': [],
      });
      expect(requirements.systemFontConstants, 2);
      expect(requirements.families['MaterialIcons'], {0xf00e9});
      expect(
          requirements.families[
              'packages/material_symbols_icons/MaterialSymbolsOutlined'],
          {0xe312});
    });

    test('dynamic or malformed IconData cannot silently skip validation', () {
      expect(
          () => IconRequirements.fromConstFinder({
                'constantInstances': [],
                'nonConstantLocations': [
                  {'file': 'lib/dynamic.dart', 'line': 5}
                ],
              }),
          throwsFormatException);
      expect(
          () => IconRequirements.fromConstFinder({
                'constantInstances': [
                  {'codePoint': 0xe312, 'fontFamily': null, 'fontPackage': null}
                ],
                'nonConstantLocations': [],
              }),
          throwsFormatException);
      expect(
          () => IconRequirements.fromConstFinder({
                'constantInstances': [_icon(0x110000, 'MaterialIcons')],
                'nonConstantLocations': [],
              }),
          throwsFormatException);
      expect(
          () => IconRequirements.fromConstFinder({
                'constantInstances': [
                  {'codePoint': 'U+E312'}
                ],
                'nonConstantLocations': [],
              }),
          throwsFormatException);
    });

    test(
        'manifest resolves exact family/assets and rejects duplicates/traversal',
        () {
      expect(readFontManifest(_manifest), {'MaterialIcons': 'fonts/icons.otf'});
      for (final unsafe in [
        '../secret.ttf',
        '/font.ttf',
        r'C:\font.ttf',
        'fonts//x.ttf'
      ]) {
        expect(
            () => readFontManifest([
                  {
                    'family': 'MaterialIcons',
                    'fonts': [
                      {'asset': unsafe}
                    ],
                  }
                ]),
            throwsFormatException);
      }
      expect(() => readFontManifest([..._manifest, ..._manifest]),
          throwsFormatException);
      expect(() => readFontManifest({'not': 'a list'}), throwsFormatException);
    });

    test('old subset fails for new BMP and supplementary-plane icons', () {
      final audit = auditFontBytes(
        manifest: readFontManifest(_manifest),
        assets: {
          'fonts/icons.otf': _font(_cmap4({0xe5cd: 2}))
        },
        requirements: const IconRequirements({
          'MaterialIcons': {0xe5cd, 0xef8c, 0xf00e9}
        }, 0),
        projectIconFamilies: {'MaterialIcons'},
      );
      expect(audit.passed, isFalse);
      expect(audit.fonts.single.missingCodePoints, [0xef8c, 0xf00e9]);
    });

    test(
        'new subset passes without requiring every SDK glyph or title character',
        () {
      final audit = auditFontBytes(
        manifest: readFontManifest(_manifest),
        assets: {
          'fonts/icons.otf': _font(_cmap12({0xef8c: 2, 0xf00e9: 3}))
        },
        requirements: const IconRequirements({
          'MaterialIcons': {0xef8c, 0xf00e9}
        }, 0),
        projectIconFamilies: {'MaterialIcons'},
      );
      expect(audit.passed, isTrue);
      expect(audit.fonts.single.requiredCodePoints, [0xef8c, 0xf00e9]);
      expect(jsonEncode(audit.fonts.single.toJson()),
          contains('requiredCodePoints'));
    });

    test('missing font bytes and unregistered project families are errors', () {
      expect(
          () => auditFontBytes(
                manifest: readFontManifest(_manifest),
                assets: {},
                requirements: const IconRequirements({}, 0),
                projectIconFamilies: {'MaterialIcons'},
              ),
          throwsFormatException);
      expect(
          () => auditFontBytes(
                manifest: {},
                assets: {},
                requirements: const IconRequirements({}, 0),
                projectIconFamilies: {'MaterialIcons'},
              ),
          throwsFormatException);
    });

    test('an unknown unbundled compiled family is not a framework exemption',
        () {
      expect(
          () => auditFontBytes(
                manifest: {},
                assets: {},
                requirements: const IconRequirements({
                  'packages/custom_icons/RequiredIcons': {0xe312}
                }, 0),
                projectIconFamilies: {},
              ),
          throwsFormatException);
    });

    test(
        'unbundled framework fallback is reported but not confused with project icons',
        () {
      const requirements = IconRequirements({
        'MaterialIcons': {0xe312},
        'packages/cupertino_icons/CupertinoIcons': {0xf388},
      }, 0);
      final audit = auditFontBytes(
        manifest: readFontManifest(_manifest),
        assets: {
          'fonts/icons.otf': _font(_cmap4({0xe312: 2}))
        },
        requirements: requirements,
        projectIconFamilies: {'MaterialIcons'},
      );
      expect(audit.passed, isTrue);
      expect(audit.unbundledFrameworkFamilies,
          ['packages/cupertino_icons/CupertinoIcons']);
      expect(
          () => auditFontBytes(
                manifest: readFontManifest(_manifest),
                assets: {
                  'fonts/icons.otf': _font(_cmap4({0xe312: 2}))
                },
                requirements: requirements,
                projectIconFamilies: {
                  'MaterialIcons',
                  'packages/cupertino_icons/CupertinoIcons'
                },
              ),
          throwsFormatException);
    });
  });

  test('release invalidation deletes only three exact stamps and honors WhatIf',
      () async {
    if (!Platform.isWindows) return;
    final workspaceTool = Directory(
        path.join(Directory.current.parent.path, 'tool', 'qa-release'));
    await workspaceTool.create(recursive: true);
    final fixture = await workspaceTool.createTemp('font-stamp-test-');
    addTearDown(() async {
      if (!path.isWithin(workspaceTool.absolute.path, fixture.absolute.path)) {
        throw StateError('Refusing cleanup outside the allocated QA fixture.');
      }
      await fixture.delete(recursive: true);
    });
    final build = Directory(path.join(fixture.path, '.dart_tool',
        'flutter_build', '0123456789abcdef0123456789abcdef'));
    await build.create(recursive: true);
    final release =
        File(path.join(build.path, 'release_bundle_windows-x64_assets.stamp'));
    final aotStamp = File(path.join(build.path, 'aot_elf_release.stamp'));
    final bundleStamp = File(path.join(build.path, 'windows_aot_bundle.stamp'));
    final profile =
        File(path.join(build.path, 'profile_bundle_windows-x64_assets.stamp'));
    final kernel = File(path.join(build.path, 'app.dill'));
    final aot = File(path.join(build.path, 'app.so'));
    await release.writeAsString('{}');
    await aotStamp.writeAsString('{}');
    await bundleStamp.writeAsString('{}');
    await profile.writeAsString('keep profile');
    await kernel.writeAsString('keep kernel');
    await aot.writeAsString('keep AOT');
    final script = path.join(Directory.current.path, 'scripts',
        'invalidate_windows_icon_assets.ps1');
    final arguments = [
      '-NoProfile',
      '-NonInteractive',
      // Scope script execution to this disposable test subprocess; never
      // change the machine/user execution policy for a fixture check.
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script,
      '-ProjectRoot',
      fixture.path
    ];
    final dryRun =
        await Process.run('powershell.exe', [...arguments, '-WhatIf']);
    expect(dryRun.exitCode, 0, reason: dryRun.stderr.toString());
    expect(await release.exists(), isTrue);
    expect(await aotStamp.exists(), isTrue);
    expect(await bundleStamp.exists(), isTrue);
    final run = await Process.run('powershell.exe', arguments);
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect(await release.exists(), isFalse);
    expect(await aotStamp.exists(), isFalse);
    expect(await bundleStamp.exists(), isFalse);
    expect(await profile.readAsString(), 'keep profile');
    expect(await kernel.readAsString(), 'keep kernel');
    expect(await aot.readAsString(), 'keep AOT');
    final repeated = await Process.run('powershell.exe', arguments);
    expect(repeated.exitCode, 0, reason: repeated.stderr.toString());
    expect(await aot.readAsString(), 'keep AOT');
  });
}

Map<String, Object?> _icon(int codePoint, String family, [String? package]) =>
    {'codePoint': codePoint, 'fontFamily': family, 'fontPackage': package};

const _manifest = [
  {
    'family': 'MaterialIcons',
    'fonts': [
      {'asset': 'fonts/icons.otf'}
    ]
  },
];

Uint8List _cmap4(Map<int, int> mapping) {
  final points = mapping.keys.toList()..sort();
  final count = points.length + 1;
  final bytes = Uint8List(16 + count * 8);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 4);
  data.setUint16(2, bytes.length);
  data.setUint16(6, count * 2);
  final starts = 16 + count * 2;
  final deltas = starts + count * 2;
  for (var index = 0; index < count; index++) {
    final point = index == points.length ? 0xffff : points[index];
    data.setUint16(14 + index * 2, point);
    data.setUint16(starts + index * 2, point);
    data.setUint16(deltas + index * 2,
        index == points.length ? 1 : (mapping[point]! - point) & 0xffff);
  }
  return bytes;
}

Uint8List _cmap12(Map<int, int> mapping) {
  final points = mapping.keys.toList()..sort();
  final bytes = Uint8List(16 + points.length * 12);
  final data = ByteData.sublistView(bytes);
  data.setUint16(0, 12);
  data.setUint32(4, bytes.length);
  data.setUint32(12, points.length);
  for (var index = 0; index < points.length; index++) {
    data.setUint32(16 + index * 12, points[index]);
    data.setUint32(20 + index * 12, points[index]);
    data.setUint32(24 + index * 12, mapping[points[index]]!);
  }
  return bytes;
}

Uint8List _font(Uint8List subtable,
    {int glyphCount = 64,
    bool variable = false,
    List<Uint8List> additionalSubtables = const []}) {
  final subtables = [subtable, ...additionalSubtables];
  final cmapHeaderLength = 4 + subtables.length * 8;
  final cmap = Uint8List(cmapHeaderLength +
      subtables.fold<int>(0, (sum, table) => sum + table.length));
  final cmapData = ByteData.sublistView(cmap);
  cmapData.setUint16(2, subtables.length);
  var cmapOffset = cmapHeaderLength;
  for (var index = 0; index < subtables.length; index++) {
    final table = subtables[index];
    final record = 4 + index * 8;
    cmapData.setUint16(record, 3);
    cmapData.setUint16(
        record + 2, ByteData.sublistView(table).getUint16(0) == 4 ? 1 : 10);
    cmapData.setUint32(record + 4, cmapOffset);
    cmap.setAll(cmapOffset, table);
    cmapOffset += table.length;
  }
  final maxp = Uint8List(6);
  ByteData.sublistView(maxp)
    ..setUint32(0, 0x00010000)
    ..setUint16(4, glyphCount);
  final tables = <String, Uint8List>{
    'cmap': cmap,
    'maxp': maxp,
    if (variable) 'fvar': Uint8List(16),
  };
  final directorySize = 12 + tables.length * 16;
  final bytes = Uint8List(directorySize +
      tables.values.fold<int>(0, (sum, value) => sum + value.length));
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 0x00010000);
  data.setUint16(4, tables.length);
  var offset = directorySize;
  var index = 0;
  for (final entry in tables.entries) {
    final record = 12 + index++ * 16;
    bytes.setAll(record, entry.key.codeUnits);
    data.setUint32(record + 8, offset);
    data.setUint32(record + 12, entry.value.length);
    bytes.setAll(offset, entry.value);
    offset += entry.value.length;
  }
  return bytes;
}
