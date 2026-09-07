import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import 'support/release_font_audit.dart';

/// This gate reads the final bundle, not build/unit_test_assets or SDK fonts.
/// The kernel is selected by matching its compiled app.so to the bundle's
/// app.so; source searches are only used to reject missing project families.
Future<void> main(List<String> arguments) async {
  try {
    final options = <String, String>{};
    for (var index = 0; index < arguments.length; index += 2) {
      if (index + 1 == arguments.length ||
          !const {
            '--project-root',
            '--release-dir',
            '--flutter-root',
            '--report'
          }.contains(arguments[index])) {
        throw const FormatException(
            'Usage: dart scripts/verify_release_fonts.dart --project-root PATH '
            '--release-dir PATH --flutter-root PATH [--report NEW_FILE]');
      }
      options[arguments[index]] = arguments[index + 1];
    }
    final project =
        Directory(options['--project-root'] ?? Directory.current.path);
    final releasePath = options['--release-dir'];
    final flutterPath =
        options['--flutter-root'] ?? Platform.environment['FLUTTER_ROOT'];
    if (releasePath == null || flutterPath == null) {
      throw const FormatException(
          '--release-dir and --flutter-root are required.');
    }
    final release = Directory(releasePath);
    final flutter = Directory(flutterPath);
    final assetsDirectory =
        Directory(path.join(release.path, 'data', 'flutter_assets'));
    final appSo = File(path.join(release.path, 'data', 'app.so'));
    final aotHash = await _hash(appSo);
    final kernel = await _findMatchingKernel(project, appSo, aotHash);
    final kernelHash = await _hash(kernel);
    final dart = File(path.join(flutter.path, 'bin', 'cache', 'dart-sdk', 'bin',
        Platform.isWindows ? 'dart.exe' : 'dart'));
    final finder = File(path.join(flutter.path, 'bin', 'cache', 'artifacts',
        'engine', 'windows-x64', 'const_finder.dart.snapshot'));
    if (!await dart.exists() || !await finder.exists()) {
      throw StateError('Flutter Windows SDK/const_finder is missing.');
    }
    final constants = await Process.run(dart.path, [
      finder.path,
      '--kernel-file',
      kernel.path,
      '--class-library-uri',
      'package:flutter/src/widgets/icon_data.dart',
      '--class-name',
      'IconData',
      '--annotation-class-name',
      '_StaticIconProvider',
      '--annotation-class-library-uri',
      'package:flutter/src/widgets/icon_data.dart',
    ]);
    if (constants.exitCode != 0) {
      throw StateError('Flutter const_finder failed: ${constants.stderr}');
    }
    final requirements = IconRequirements.fromConstFinder(
        jsonDecode(constants.stdout as String));
    final fontManifestFile =
        File(path.join(assetsDirectory.path, 'FontManifest.json'));
    final fontManifestBytes = await fontManifestFile.readAsBytes();
    final manifest =
        readFontManifest(jsonDecode(utf8.decode(fontManifestBytes)));
    final fontBytes = <String, Uint8List>{};
    for (final asset in manifest.values) {
      final fontFile = await _safeAsset(assetsDirectory, asset);
      fontBytes[asset] = await fontFile.readAsBytes();
    }
    final audit = auditFontBytes(
      manifest: manifest,
      assets: fontBytes,
      requirements: requirements,
      projectIconFamilies: await _projectIconFamilies(project),
    );
    final sourceAssets = <Map<String, Object>>[];
    final pubspec =
        await File(path.join(project.path, 'pubspec.yaml')).readAsString();
    if (RegExp(r'^name:\s*dan_player\s*$', multiLine: true).hasMatch(pubspec)) {
      // Logo assets are separate from icon fonts. Catch an omitted or stale
      // logo explicitly instead of attributing every blank image to subsetting.
      for (final relative in const [
        'app_icon.ico',
        'assets/images/RCE_logo_transparent.png',
        'assets/images/RCE_logo_white.png',
        'assets/branding/danruguo_light.png',
        'assets/branding/danruguo_dark.png',
      ]) {
        final bundled = await _safeAsset(assetsDirectory, relative);
        final sourceHash = await _hash(File(path.join(project.path, relative)));
        final bundledHash = await _hash(bundled);
        if (sourceHash != bundledHash || await bundled.length() == 0) {
          throw StateError('Missing/stale logo asset: $relative');
        }
        sourceAssets.add({'asset': relative, 'sha256': bundledHash});
      }
    }
    if (await _hash(kernel) != kernelHash || await _hash(appSo) != aotHash) {
      throw StateError(
          'Kernel or AOT changed while verifying; build serially.');
    }
    final report = <String, Object>{
      'schemaVersion': 1,
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'passed': audit.passed,
      'requirementSource':
          'Flutter const_finder on kernel matched to bundled app.so',
      'aotSha256': aotHash,
      'kernelSha256': kernelHash,
      'fontManifestSha256': sha256.convert(fontManifestBytes).toString(),
      'systemFontSentinelCount': requirements.systemFontConstants,
      'unbundledFrameworkFamilies': audit.unbundledFrameworkFamilies,
      'fonts': [
        for (final font in audit.fonts)
          {
            ...font.toJson(),
            'sha256': sha256.convert(fontBytes[font.asset]!).toString()
          },
      ],
      'sourceAssets': sourceAssets,
    };
    final reportPath = options['--report'];
    if (reportPath != null) {
      final reportFile = File(reportPath);
      if (await reportFile.exists()) {
        throw StateError(
            'Refusing to overwrite an existing font audit: $reportPath');
      }
      await reportFile.parent.create(recursive: true);
      await reportFile.writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(report)}\n',
          flush: true);
    }
    for (final font in audit.fonts) {
      stdout.writeln(
          '${font.family}: ${font.requiredCodePoints.length} required '
          'icons, ${font.missingCodePoints.length} missing, ${font.byteLength} bytes');
      if (font.missingCodePoints.isNotEmpty) {
        stdout.writeln(
            '  Missing: ${font.missingCodePoints.map((point) => 'U+${point.toRadixString(16).toUpperCase()}').join(', ')}');
      }
    }
    if (audit.unbundledFrameworkFamilies.isNotEmpty) {
      stdout.writeln('Unbundled framework-only fallback constants (not project '
          'icon families): ${audit.unbundledFrameworkFamilies.join(', ')}');
    }
    if (!audit.passed) {
      throw StateError(
          'Release icon fonts do not cover the current compiled app. '
          'Rebuild using scripts/build_windows_release.ps1; stale asset stamps '
          'must be invalidated before Flutter bundles its icon subsets.');
    }
    stdout.writeln(
        'Release icon/font/logo integrity verified against bundled AOT.');
  } catch (error) {
    // stdout keeps this readable in Windows PowerShell 5.1 wrappers, whose
    // native stderr handling otherwise masks the actual validation message.
    stdout.writeln('FONT INTEGRITY FAILED: $error');
    exitCode = 1;
  }
}

Future<String> _hash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<File> _findMatchingKernel(
    Directory project, File appSo, String aotHash) async {
  final build =
      Directory(path.join(project.path, '.dart_tool', 'flutter_build'));
  if (!await build.exists()) {
    throw StateError(
        'No Flutter kernel cache; build the project before packaging.');
  }
  final candidates = <File>[];
  await for (final entry in build.list(followLinks: false)) {
    if (entry is! Directory ||
        !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(path.basename(entry.path))) {
      continue;
    }
    final aot = File(path.join(entry.path, 'app.so'));
    final kernel = File(path.join(entry.path, 'app.dill'));
    if (!await aot.exists() || !await kernel.exists()) continue;
    if (await aot.length() != await appSo.length() ||
        await _hash(aot) != aotHash) {
      continue;
    }
    if ((await kernel.stat()).modified.isAfter((await aot.stat()).modified)) {
      continue;
    }
    candidates.add(kernel);
  }
  if (candidates.isEmpty) {
    throw StateError('No kernel matches the final app.so. Refusing to verify '
        'fonts against unrelated source constants or another build.');
  }
  candidates
      .sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  return candidates.first;
}

Future<File> _safeAsset(Directory assets, String relative) async {
  validateAssetPath(relative);
  final file = File(path.join(assets.path, relative));
  final root = await assets.resolveSymbolicLinks();
  final resolved = await file.resolveSymbolicLinks();
  if (!path.isWithin(root, resolved)) {
    throw FormatException('Font/image asset escapes the bundle: $relative');
  }
  return file;
}

Future<Set<String>> _projectIconFamilies(Directory project) async {
  final result = <String>{};
  final sources = [Directory(path.join(project.path, 'lib'))];
  final pubspec =
      await File(path.join(project.path, 'pubspec.yaml')).readAsString();
  if (RegExp(r'^name:\s*dan_player\s*$', multiLine: true).hasMatch(pubspec) &&
      RegExp(r'^\s+desktop_lyric:\s*$', multiLine: true).hasMatch(pubspec)) {
    // The helper entry point now shares the main AOT. const_finder above reads
    // both entry points; include the local package's family declarations too.
    sources.add(Directory(
        path.join(project.path, 'third_party', 'desktop_lyric', 'lib')));
  }
  for (final source in sources) {
    await for (final entry
        in source.list(recursive: true, followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.dart')) continue;
      final text = await entry.readAsString();
      if (RegExp(r'\bIcons\.').hasMatch(text)) result.add('MaterialIcons');
      if (RegExp(r'\bCupertinoIcons\.').hasMatch(text)) {
        result.add('packages/cupertino_icons/CupertinoIcons');
      }
      for (final match in RegExp(r'\bSymbols\.(\w+)').allMatches(text)) {
        final name = match[1]!;
        final style = name.endsWith('_rounded')
            ? 'Rounded'
            : name.endsWith('_sharp')
                ? 'Sharp'
                : 'Outlined';
        result.add('packages/material_symbols_icons/MaterialSymbols$style');
      }
      // Literal custom families are also required, even when omitted from the
      // manifest. Dynamic IconData is rejected using const_finder above.
      for (final match in RegExp(r'IconData\([\s\S]*?\)').allMatches(text)) {
        final literal = match[0]!;
        final family = RegExp("fontFamily\\s*:\\s*['\"]([^'\"]+)['\"]")
            .firstMatch(literal)?[1];
        final package = RegExp("fontPackage\\s*:\\s*['\"]([^'\"]+)['\"]")
            .firstMatch(literal)?[1];
        if (family != null) {
          result.add(package == null ? family : 'packages/$package/$family');
        }
      }
    }
  }
  return result;
}
