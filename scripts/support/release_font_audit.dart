import 'dart:typed_data';

import 'sfnt_font.dart';

class IconRequirements {
  const IconRequirements(this.families, this.systemFontConstants);

  final Map<String, Set<int>> families;
  final int systemFontConstants;

  factory IconRequirements.fromConstFinder(Object? decoded) {
    if (decoded is! Map ||
        decoded['constantInstances'] is! List ||
        decoded['nonConstantLocations'] is! List) {
      throw const FormatException('Invalid const_finder output.');
    }
    if ((decoded['nonConstantLocations'] as List).isNotEmpty) {
      throw const FormatException(
          'Dynamic IconData cannot be verified; use constant IconData.');
    }
    final families = <String, Set<int>>{};
    var system = 0;
    for (final instance in decoded['constantInstances'] as List) {
      if (instance is! Map ||
          instance['codePoint'] is! int ||
          (instance['fontFamily'] != null &&
              instance['fontFamily'] is! String) ||
          (instance['fontPackage'] != null &&
              instance['fontPackage'] is! String)) {
        throw const FormatException('Invalid IconData constant.');
      }
      final codePoint = instance['codePoint'] as int;
      if (codePoint < 0 || codePoint > 0x10ffff) {
        throw const FormatException('IconData is outside Unicode range.');
      }
      final family = instance['fontFamily'] as String?;
      final package = instance['fontPackage'] as String?;
      // Flutter itself retains fontless system constants: a zero-codepoint
      // sentinel and its inspector's selection icon (material/app.dart and
      // cupertino/app.dart in Flutter 3.47.1). Neither uses a bundled font.
      if (family == null) {
        if (!const {0, 0x1f74a}.contains(codePoint) || package != null) {
          throw const FormatException(
              'Unrecognized fontless IconData cannot be verified in a bundle.');
        }
        system++;
        continue;
      }
      if (family.isEmpty || package == '') {
        throw const FormatException(
            'IconData has an empty font family/package.');
      }
      final key = package == null ? family : 'packages/$package/$family';
      (families[key] ??= <int>{}).add(codePoint);
    }
    return IconRequirements(families, system);
  }
}

Map<String, String> readFontManifest(Object? decoded) {
  if (decoded is! List) {
    throw const FormatException('FontManifest must be a list.');
  }
  final result = <String, String>{};
  for (final entry in decoded) {
    if (entry is! Map ||
        entry['family'] is! String ||
        entry['fonts'] is! List) {
      throw const FormatException('Invalid FontManifest family.');
    }
    final family = entry['family'] as String;
    final fonts = entry['fonts'] as List;
    if (family.isEmpty || result.containsKey(family) || fonts.length != 1) {
      throw const FormatException('Expected one unambiguous font per family.');
    }
    final font = fonts.single;
    if (font is! Map || font['asset'] is! String) {
      throw const FormatException('Font asset path must be a string.');
    }
    final asset = font['asset'] as String;
    validateAssetPath(asset);
    result[family] = asset;
  }
  return result;
}

void validateAssetPath(String asset) {
  if (asset.isEmpty ||
      asset.startsWith('/') ||
      asset.contains('\\') ||
      asset.contains(':') ||
      asset
          .split('/')
          .any((part) => part.isEmpty || part == '..' || part == '.')) {
    throw FormatException('Unsafe relative Flutter asset path: $asset');
  }
}

class CheckedFont {
  const CheckedFont({
    required this.family,
    required this.asset,
    required this.byteLength,
    required this.glyphCount,
    required this.variable,
    required this.requiredCodePoints,
    required this.missingCodePoints,
  });

  final String family;
  final String asset;
  final int byteLength;
  final int glyphCount;
  final bool variable;
  final List<int> requiredCodePoints;
  final List<int> missingCodePoints;

  Map<String, Object> toJson() => {
        'family': family,
        'asset': asset,
        'bytes': byteLength,
        'glyphCount': glyphCount,
        'variableFont': variable,
        'requiredCodePoints': requiredCodePoints,
        'missingCodePoints': missingCodePoints,
      };
}

class FontAudit {
  const FontAudit(this.fonts, this.unbundledFrameworkFamilies);
  final List<CheckedFont> fonts;
  final List<String> unbundledFrameworkFamilies;
  bool get passed => fonts.every((font) => font.missingCodePoints.isEmpty);
}

/// Validate only actual constant icon requirements, not unrelated Unicode
/// titles/lyrics. Project-referenced icon families must be registered. Unused
/// framework fallbacks (e.g. CupertinoIcons in a Windows-only bundle) are
/// reported separately, matching Flutter's own font-subsetting selection.
FontAudit auditFontBytes({
  required Map<String, String> manifest,
  required Map<String, Uint8List> assets,
  required IconRequirements requirements,
  required Set<String> projectIconFamilies,
}) {
  for (final family in projectIconFamilies) {
    if (!manifest.containsKey(family)) {
      throw FormatException('Project icon family is not bundled: $family');
    }
  }
  final fonts = <CheckedFont>[];
  for (final entry in manifest.entries) {
    final bytes = assets[entry.value];
    if (bytes == null || bytes.isEmpty) {
      throw FormatException('Missing/empty bundled font: ${entry.value}');
    }
    final font = SfntFont.parse(bytes);
    final required = (requirements.families[entry.key] ?? <int>{}).toList()
      ..sort();
    fonts.add(CheckedFont(
      family: entry.key,
      asset: entry.value,
      byteLength: bytes.length,
      glyphCount: font.glyphCount,
      variable: font.isVariable,
      requiredCodePoints: required,
      missingCodePoints:
          required.where((point) => !font.hasGlyph(point)).toList(),
    ));
  }
  final unbundled = requirements.families.keys
      .where((family) => !manifest.containsKey(family))
      .toList()
    ..sort();
  for (final family in unbundled) {
    // Cupertino's fallback constant is retained by Flutter's platform-adaptive
    // widgets even in this Windows-only Material application. Do not silently
    // exempt an arbitrary missing package font under the same rationale.
    if (family != 'packages/cupertino_icons/CupertinoIcons') {
      throw FormatException('Compiled icon family is not bundled: $family');
    }
  }
  return FontAudit(fonts, unbundled);
}
