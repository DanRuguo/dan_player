import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../scripts/support/bundled_font_assets.dart';
import '../scripts/support/release_font_audit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> raw;
  late BundledFontCatalog catalog;
  late Map<String, Uint8List> sourceBytes;

  setUpAll(() {
    raw = jsonDecode(
        File('scripts/support/bundled_fonts.json').readAsStringSync());
    catalog = BundledFontCatalog.parse(raw);
    sourceBytes = {
      for (final font in catalog.fonts)
        font.asset: File(font.source).readAsBytesSync(),
    };
  });

  Map<String, String> manifest(bool main) => {
        for (final font in catalog.fonts)
          font.bundledFamily(main): font.bundledAsset(main)
      };
  Map<String, Uint8List> assets(bool main) => {
        for (final font in catalog.fonts)
          font.bundledAsset(main): sourceBytes[font.asset]!
      };
  Object clone() => jsonDecode(jsonEncode(raw));

  test('actual Flutter asset bundle has all four package-owned original files',
      () async {
    final bytes = <String, Uint8List>{};
    for (final font in catalog.fonts) {
      final key = font.bundledAsset(true);
      bytes[key] = (await rootBundle.load(key)).buffer.asUint8List();
    }
    expect(
        auditBundledFontAssets(
            catalog: catalog,
            mainProject: true,
            manifest: readFontManifest(
                jsonDecode(await rootBundle.loadString('FontManifest.json'))),
            assets: bytes),
        hasLength(4));
    final declared = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(declared.listAssets(),
        isNot(contains('assets/fonts/PingFangSC-Regular.ttf')));
  });

  test('standalone package paths resolve to the same original byte resources',
      () {
    expect(
        auditBundledFontAssets(
            catalog: catalog,
            mainProject: false,
            manifest: manifest(false),
            assets: assets(false)),
        hasLength(4));
  });

  test('missing registered family is rejected even when bytes exist', () {
    final wrong = manifest(true)
      ..remove(catalog.fonts.last.bundledFamily(true));
    expect(
        () => auditBundledFontAssets(
            catalog: catalog,
            mainProject: true,
            manifest: wrong,
            assets: assets(true)),
        throwsFormatException);
  });

  test('unprefixed main alias cannot silently select a system font', () {
    expect(
        () => auditBundledFontAssets(
            catalog: catalog,
            mainProject: true,
            manifest: manifest(false),
            assets: assets(true)),
        throwsFormatException);
  });

  test('second main copy is rejected even under a different registered family',
      () {
    final copies = assets(true)
      ..['assets/fonts/PingFangSC-Regular.ttf'] =
          sourceBytes[catalog.fonts.first.asset]!;
    expect(
        () => auditBundledFontAssets(
            catalog: catalog,
            mainProject: true,
            manifest: manifest(true)
              ..['old-main-copy'] = 'assets/fonts/PingFangSC-Regular.ttf',
            assets: copies),
        throwsFormatException);
  });

  test('one file cannot be declared again under another Flutter family', () {
    final wrong = manifest(true)
      ..['duplicate'] = catalog.fonts.first.bundledAsset(true);
    expect(
        () => auditBundledFontAssets(
            catalog: catalog,
            mainProject: true,
            manifest: wrong,
            assets: assets(true)),
        throwsFormatException);
  });

  test('same-length changed original font bytes fail pinned provenance', () {
    final changed = assets(true);
    final key = catalog.fonts.last.bundledAsset(true);
    changed[key] = Uint8List.fromList(changed[key]!);
    changed[key]![changed[key]!.length - 1] ^= 1;
    expect(
        () => auditBundledFontAssets(
            catalog: catalog,
            mainProject: true,
            manifest: manifest(true),
            assets: changed),
        throwsFormatException);
  });

  test('missing original bytes fail before glyph validation', () {
    final changed = assets(true)..remove(catalog.fonts.last.bundledAsset(true));
    expect(
        () => auditBundledFontAssets(
            catalog: catalog,
            mainProject: true,
            manifest: manifest(true),
            assets: changed),
        throwsFormatException);
  });

  test('catalog rejects another resource owner and traversal paths', () {
    final owner = clone() as Map;
    owner['ownerDirectory'] = 'assets';
    expect(() => BundledFontCatalog.parse(owner), throwsFormatException);
    final traversal = clone() as Map;
    traversal['fonts'][0]['asset'] = 'assets/fonts/../outside.otf';
    expect(() => BundledFontCatalog.parse(traversal), throwsFormatException);
  });

  test('catalog rejects duplicate content and missing recommended families',
      () {
    final duplicate = clone() as Map;
    duplicate['fonts'][1]['sha256'] = duplicate['fonts'][0]['sha256'];
    expect(() => BundledFontCatalog.parse(duplicate), throwsFormatException);
    final missing = clone() as Map;
    (missing['fonts'] as List).removeLast();
    expect(() => BundledFontCatalog.parse(missing), throwsFormatException);
  });

  test('glyph and variable gates do not exempt a correctly hashed font', () {
    final missingGlyph = clone() as Map;
    missingGlyph['fonts'][1]['requiredSamples'] = ['歌词'];
    expect(
        () => auditBundledFontAssets(
            catalog: BundledFontCatalog.parse(missingGlyph),
            mainProject: true,
            manifest: manifest(true),
            assets: assets(true)),
        throwsFormatException);
    final variation = clone() as Map;
    variation['fonts'][1]['variable'] = false;
    expect(
        () => auditBundledFontAssets(
            catalog: BundledFontCatalog.parse(variation),
            mainProject: true,
            manifest: manifest(true),
            assets: assets(true)),
        throwsFormatException);
  });

  test('one authoritative directory contains exactly the four selected files',
      () {
    final actual = Directory('third_party/desktop_lyric/assets/fonts')
        .listSync()
        .whereType<File>()
        .map((file) => file.path.replaceAll('\\', '/'))
        .toSet();
    expect(actual, {for (final font in catalog.fonts) font.source});
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('  fonts:')));
    expect(pubspec, isNot(contains('assets/fonts/')));
    final owner =
        File('third_party/desktop_lyric/pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^    - family:', multiLine: true).allMatches(owner),
        hasLength(4));
  });

  test(
      'installer font source and control fixture follow the same package owner',
      () {
    final setup = File('installer/setup.iss').readAsStringSync();
    expect(setup, contains('Source: "{#EmbeddedFontSource}"'));
    expect(setup, contains('DestName: "PingFangSC-Regular.ttf"'));
    final controls = File('installer/CMakeLists.txt').readAsStringSync();
    expect(
        controls,
        contains(
            '../third_party/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf'));
    final build =
        File('scripts/build_windows_installer.ps1').readAsStringSync();
    expect(build, contains('EmbeddedFontSource=\$installerFont.SourcePath'));
    expect(build, contains('EmbeddedFontSha256=\$installerFont.Sha256'));
  });
}
