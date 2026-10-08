import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'release_font_audit.dart';
import 'sfnt_font.dart';

/// Original UI font files owned by one local package. This catalog also drives
/// source distribution checks and the final release gate; it never edits fonts.
class BundledFontAsset {
  const BundledFontAsset({
    required this.id,
    required this.family,
    required this.asset,
    required this.source,
    required this.bytes,
    required this.sha256,
    required this.gitBlob,
    required this.variable,
    required this.requiredSamples,
  });

  final String id;
  final String family;
  final String asset;
  final String source;
  final int bytes;
  final String sha256;
  final String gitBlob;
  final bool variable;
  final List<String> requiredSamples;

  String bundledFamily(bool mainProject) =>
      mainProject ? 'packages/desktop_lyric/$family' : family;
  String bundledAsset(bool mainProject) =>
      mainProject ? 'packages/desktop_lyric/$asset' : asset;
}

class BundledFontCatalog {
  const BundledFontCatalog(this.fonts);
  final List<BundledFontAsset> fonts;

  factory BundledFontCatalog.parse(Object? value) {
    if (value is! Map ||
        value['schemaVersion'] != 1 ||
        value['ownerPackage'] != 'desktop_lyric' ||
        value['ownerDirectory'] != 'third_party/desktop_lyric' ||
        value['fonts'] is! List) {
      throw const FormatException('Invalid single-owner bundled font catalog.');
    }
    final fonts = <BundledFontAsset>[];
    final ids = <String>{};
    final families = <String>{};
    final paths = <String>{};
    final hashes = <String>{};
    for (final item in value['fonts'] as List) {
      if (item is! Map ||
          item['id'] is! String ||
          item['family'] is! String ||
          item['asset'] is! String ||
          item['source'] is! String ||
          item['bytes'] is! int ||
          (item['bytes'] as int) <= 0 ||
          item['sha256'] is! String ||
          item['gitBlob'] is! String ||
          item['variable'] is! bool ||
          item['requiredSamples'] is! List) {
        throw const FormatException('Invalid pinned bundled font entry.');
      }
      final id = item['id'] as String;
      final family = item['family'] as String;
      final asset = item['asset'] as String;
      final source = item['source'] as String;
      final hash = item['sha256'] as String;
      final blob = item['gitBlob'] as String;
      validateAssetPath(asset);
      validateAssetPath(source);
      if (id.isEmpty ||
          !RegExp(r'^Dan[A-Za-z]+$').hasMatch(family) ||
          !asset.startsWith('assets/fonts/') ||
          source != 'third_party/desktop_lyric/$asset' ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ||
          !RegExp(r'^[0-9a-f]{40}$').hasMatch(blob) ||
          !ids.add(id) ||
          !families.add(family) ||
          !paths.add(asset) ||
          !hashes.add(hash)) {
        throw const FormatException('Ambiguous or unsafe bundled font owner.');
      }
      final samples = item['requiredSamples'] as List;
      if (samples.isEmpty ||
          samples.any((sample) => sample is! String || sample.isEmpty)) {
        throw const FormatException('Bundled font glyph samples are missing.');
      }
      fonts.add(BundledFontAsset(
        id: id,
        family: family,
        asset: asset,
        source: source,
        bytes: item['bytes'] as int,
        sha256: hash,
        gitBlob: blob,
        variable: item['variable'] as bool,
        requiredSamples: List<String>.unmodifiable(samples.cast<String>()),
      ));
    }
    if (fonts.length != 4 ||
        !families.containsAll(const {
          'DanPingFangSC',
          'DanGoogleSans',
          'DanSourceHanJP',
          'DanPretendard',
        })) {
      throw const FormatException('All four shared UI fonts must be pinned.');
    }
    return BundledFontCatalog(List.unmodifiable(fonts));
  }
}

/// Fail on wrong package registration, stale bytes or duplicate UI font copies.
/// Icons continue through the independent compiled-IconData release audit.
List<Map<String, Object>> auditBundledFontAssets({
  required BundledFontCatalog catalog,
  required bool mainProject,
  required Map<String, String> manifest,
  required Map<String, Uint8List> assets,
}) {
  final expectedAssets = {
    for (final font in catalog.fonts) font.bundledAsset(mainProject)
  };
  final pinnedHashes = {for (final font in catalog.fonts) font.sha256};
  for (final entry in assets.entries) {
    if (!expectedAssets.contains(entry.key) &&
        pinnedHashes.contains(sha256.convert(entry.value).toString())) {
      throw FormatException('Duplicate UI font copy: ${entry.key}');
    }
  }
  final result = <Map<String, Object>>[];
  for (final font in catalog.fonts) {
    final family = font.bundledFamily(mainProject);
    final asset = font.bundledAsset(mainProject);
    if (manifest[family] != asset ||
        manifest.values.where((value) => value == asset).length != 1) {
      throw FormatException('UI font must have one package owner: $family');
    }
    final bytes = assets[asset];
    if (bytes == null ||
        bytes.length != font.bytes ||
        sha256.convert(bytes).toString() != font.sha256) {
      throw FormatException('Missing/stale original UI font: $asset');
    }
    final parsed = SfntFont.parse(bytes);
    if (parsed.isVariable != font.variable) {
      throw FormatException('UI font variation metadata changed: $asset');
    }
    for (final sample in font.requiredSamples) {
      for (final rune in sample.runes) {
        if (!parsed.hasGlyph(rune)) {
          throw FormatException('UI font $asset lacks '
              'U+${rune.toRadixString(16).toUpperCase()}');
        }
      }
    }
    result.add({
      'id': font.id,
      'family': family,
      'asset': asset,
      'sha256': font.sha256,
      'bytes': font.bytes,
      'variableFont': font.variable,
    });
  }
  return result;
}
