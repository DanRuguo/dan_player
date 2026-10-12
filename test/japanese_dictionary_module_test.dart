import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dan_player/library/japanese_dictionary_module_install.dart';
import 'package:dan_player/library/japanese_dictionary_runtime.dart';
import 'package:dan_player/taskbar_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// The same pinned release shape is recreated entirely from tracked inputs.
// Tests and CI require neither dist/ nor Python nor any network download.
Future<Map<String, List<int>>> _moduleFiles() async {
  final catalog = jsonDecode(
      await File('scripts/support/bundled_japanese_readings.json')
          .readAsString()) as Map<String, dynamic>;
  final resource = catalog['resource'] as Map<String, dynamic>;
  final data = await File(resource['path'] as String).readAsBytes();
  final files = <String, List<int>>{japaneseDictionaryFileName: data};
  for (final entry in catalog['notices'] as List<dynamic>) {
    final notice = entry as Map<String, dynamic>;
    final path = notice['path'] as String;
    files[path] = await File(path).readAsBytes();
  }
  files['licenses/IPADIC/PROVENANCE.md'] =
      await File('licenses/IPADIC/PROVENANCE.md').readAsBytes();
  files['MODULE.json'] =
      utf8.encode('${const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'engine': catalog['engine'],
        'resource': {
          'name': japaneseDictionaryFileName,
          'bytes': data.length,
          'sha256': resource['sha256'],
        },
      })}\n');
  files['README.txt'] = utf8.encode(
      'Dan Player optional offline Japanese reading dictionary\n\n'
      "Install using the player's Japanese reading component prompt, or extract\n"
      'this entire ZIP into tool/japanese_readings beside Dan Player.exe and click\n'
      'the installed-component check. No executable is included.\n\n'
      'The IPADIC dictionary and license notices are separate from the player.\n'
      'Generated readings are cached separately and do not edit source lyrics.\n');
  return files;
}

// ZIP_STORED, DOS 2000-01-01, no extras; matches the published assembler's
// headers exactly on all test platforms rather than inheriting host timestamps.
Uint8List _storedZip(Map<String, List<int>> files) {
  final body = OutputStream(), central = OutputStream();
  final names = files.keys.toList()..sort();
  for (final name in names) {
    final encoded = utf8.encode(name), data = files[name]!;
    final crc = getCrc32(data), offset = body.length;
    body
      ..writeUint32(0x04034b50)
      ..writeUint16(20)
      ..writeUint16(0)
      ..writeUint16(0)
      ..writeUint16(0)
      ..writeUint16(0x2821)
      ..writeUint32(crc)
      ..writeUint32(data.length)
      ..writeUint32(data.length)
      ..writeUint16(encoded.length)
      ..writeUint16(0)
      ..writeBytes(encoded)
      ..writeBytes(data);
    central
      ..writeUint32(0x02014b50)
      ..writeUint16(20)
      ..writeUint16(20)
      ..writeUint16(0)
      ..writeUint16(0)
      ..writeUint16(0)
      ..writeUint16(0x2821)
      ..writeUint32(crc)
      ..writeUint32(data.length)
      ..writeUint32(data.length)
      ..writeUint16(encoded.length)
      ..writeUint16(0)
      ..writeUint16(0)
      ..writeUint16(0)
      ..writeUint16(0)
      ..writeUint32(0x81a40000)
      ..writeUint32(offset)
      ..writeBytes(encoded);
  }
  final centralOffset = body.length;
  body
    ..writeBytes(central.getBytes())
    ..writeUint32(0x06054b50)
    ..writeUint16(0)
    ..writeUint16(0)
    ..writeUint16(names.length)
    ..writeUint16(names.length)
    ..writeUint32(central.length)
    ..writeUint32(centralOffset)
    ..writeUint16(0);
  return Uint8List.fromList(body.getBytes());
}

class _CommitRuntime extends JapaneseDictionaryRuntime {
  _CommitRuntime(
      {required super.installRoot, required super.applicationDirectory});
  final committed = Completer<void>(), resume = Completer<void>();
  @override
  Future<bool> ensure({bool force = false}) async {
    if (force) {
      committed.complete();
      await resume.future;
    }
    return super.ensure(force: force);
  }
}

class _UnavailableDataRuntime extends JapaneseDictionaryRuntime {
  _UnavailableDataRuntime({required super.applicationDirectory});
  var dataLookups = 0;
  @override
  Future<Directory> get installDirectory async {
    dataLookups++;
    throw const FileSystemException('Isolated unavailable user-data fixture');
  }
}

class _StaleDiscoveryRuntime extends JapaneseDictionaryRuntime {
  _StaleDiscoveryRuntime(
      {required super.installRoot, required super.applicationDirectory});
  final waiting = Completer<void>(), resume = Completer<void>();
  var oldScan = true, activeChecks = 0, maximumActiveChecks = 0;
  @override
  Future<bool> validateDirectory(String directory) async {
    activeChecks++;
    if (activeChecks > maximumActiveChecks) maximumActiveChecks = activeChecks;
    try {
      if (oldScan) {
        if (directory == installRoot!.path) {
          waiting.complete();
          await resume.future;
          oldScan = false;
        }
        // The previous scan captured a missing file before installation.
        return false;
      }
      return await super.validateDirectory(directory);
    } finally {
      activeChecks--;
    }
  }
}

void main() {
  late Map<String, List<int>> files;
  late Uint8List module;
  late Directory fixture;
  late File archive;
  late Directory app, installed;
  late JapaneseDictionaryRuntime runtime;
  setUpAll(() async {
    files = await _moduleFiles();
    module = _storedZip(files);
  });
  setUp(() async {
    final qa = Directory(p.join(
        Directory.current.parent.path,
        'tool',
        'qa-local',
        'lyric-settings-feedback-oct11',
        'japanese',
        'module-fixtures'));
    await qa.create(recursive: true);
    fixture = await qa.createTemp('case-');
    archive = File(p.join(fixture.path, japaneseDictionaryModuleName));
    await archive.writeAsBytes(module, flush: true);
    app = Directory(p.join(fixture.path, 'player'));
    installed =
        Directory(p.join(fixture.path, 'data', 'tools', 'japanese_readings'));
    runtime = JapaneseDictionaryRuntime(
        installRoot: installed, applicationDirectory: app);
  });
  tearDown(() async => fixture.delete(recursive: true));

  Future<void> putDictionary(Directory folder) async {
    await folder.create(recursive: true);
    await File(p.join(folder.path, japaneseDictionaryFileName))
        .writeAsBytes(files[japaneseDictionaryFileName]!, flush: true);
  }

  test(
      'tracked source recreates pinned module and extracts only six data files',
      () async {
    expect(module.length, japaneseDictionaryModuleBytes);
    expect(sha256.convert(module).toString(), japaneseDictionaryModuleSha256);
    final target = Directory(p.join(fixture.path, 'extracted'));
    await extractJapaneseDictionaryModule(archive.path, target.path);
    final actual = <String>[];
    await for (final entry
        in target.list(recursive: true, followLinks: false)) {
      if (entry is File) {
        final name =
            p.posix.joinAll(p.split(p.relative(entry.path, from: target.path)));
        actual.add(name);
        expect(await entry.readAsBytes(), files[name]);
      }
    }
    expect(actual.toSet(), files.keys.toSet());
    expect(actual.length, 6);
    expect(
        actual.where((name) => name.endsWith('.exe') || name.endsWith('.dll')),
        isEmpty);
    expect(await runtime.validateDirectory(target.path), isTrue);
  });

  test('same-size module byte tamper is rejected before any output', () async {
    final tampered = Uint8List.fromList(module);
    tampered[module.length ~/ 2] ^= 1;
    await archive.writeAsBytes(tampered);
    final target = Directory(p.join(fixture.path, 'rejected'));
    await expectLater(
        extractJapaneseDictionaryModule(archive.path, target.path),
        throwsFormatException);
    expect(await target.exists(), isFalse);
  });

  test('untrusted traversal archive cannot extract outside the whitelist',
      () async {
    await archive.writeAsBytes(_storedZip({
      ...files,
      '../outside.txt': [1, 2, 3]
    }));
    final target = Directory(p.join(fixture.path, 'rejected'));
    await expectLater(
        extractJapaneseDictionaryModule(archive.path, target.path),
        throwsFormatException);
    expect(await target.exists(), isFalse);
    expect(await File(p.join(fixture.path, 'outside.txt')).exists(), isFalse);
  });

  test('missing discovery is lazy coalesced and retries after installation',
      () async {
    final first = runtime.dictionaryPath(), second = runtime.dictionaryPath();
    expect(second, same(first));
    expect(await first, isNull);
    expect(await installed.exists(), isFalse);
    expect(await app.exists(), isFalse);
    await putDictionary(installed);
    expect(await runtime.dictionaryPath(),
        p.join(installed.path, japaneseDictionaryFileName));
  });

  test('portable tool dictionary precedes data copy and supports tools path',
      () async {
    final tool = Directory(p.join(app.path, 'tool', 'japanese_readings'));
    final tools = Directory(p.join(app.path, 'tools', 'japanese_readings'));
    await putDictionary(installed);
    await putDictionary(tool);
    await putDictionary(tools);
    expect(await runtime.dictionaryPath(),
        p.join(tool.path, japaneseDictionaryFileName));
    await tool.delete(recursive: true);
    expect(await runtime.dictionaryPath(),
        p.join(tools.path, japaneseDictionaryFileName));
    await tools.delete(recursive: true);
    expect(await runtime.dictionaryPath(),
        p.join(installed.path, japaneseDictionaryFileName));
  });

  test('dictionary tamper is rejected and restored same path becomes available',
      () async {
    await putDictionary(installed);
    expect(await runtime.ensure(), isTrue);
    final file = File(p.join(installed.path, japaneseDictionaryFileName));
    final bad = Uint8List.fromList(files[japaneseDictionaryFileName]!);
    bad[bad.length ~/ 2] ^= 1;
    await file.writeAsBytes(bad, flush: true);
    expect(await runtime.ensure(force: true), isFalse);
    await file.writeAsBytes(files[japaneseDictionaryFileName]!, flush: true);
    expect(await runtime.ensure(force: true), isTrue);
  });

  test('valid portable dictionary does not access unavailable data directory',
      () async {
    final tool = Directory(p.join(app.path, 'tool', 'japanese_readings'));
    await putDictionary(tool);
    final portable = _UnavailableDataRuntime(applicationDirectory: app);
    expect(await portable.dictionaryPath(),
        p.join(tool.path, japaneseDictionaryFileName));
    expect(portable.dataLookups, 0);
  });

  test('forced discovery waits old miss then validates newly installed file',
      () async {
    final controlled = _StaleDiscoveryRuntime(
        installRoot: installed, applicationDirectory: app);
    final old = controlled.dictionaryPath();
    await controlled.waiting.future;
    await putDictionary(installed);
    final forced = controlled.ensure(force: true);
    controlled.resume.complete();
    expect(await old, isNull);
    expect(await forced, isTrue);
    expect(await controlled.dictionaryPath(),
        p.join(installed.path, japaneseDictionaryFileName));
    expect(controlled.maximumActiveChecks, 1);
  });

  test(
      'explicit install uses authenticated ZIP and preserves newer taskbar owner',
      () async {
    await putDictionary(installed);
    final old = File(p.join(installed.path, 'old-marker.txt'));
    await old.writeAsString('old component');
    final taskbar = TaskbarProgress();
    addTearDown(taskbar.dispose);
    final seen = <TaskbarProgressValue?>[];
    taskbar.addListener(() => seen.add(taskbar.value));
    final progress = <double?>[];
    TaskbarProgressTask? newer;
    final installer = JapaneseDictionaryModuleInstaller(
        runtime: runtime,
        taskbarProgress: taskbar,
        download: (destination, report, active) async {
          expect(active(), isTrue);
          report(.25);
          newer = taskbar.begin()..update(.75);
          await archive.copy(destination.path);
        });
    await installer.install(progress: progress.add);
    expect(progress, [.25, null, 1]);
    expect(seen.any((value) => value?.completed == 250), isTrue);
    expect(taskbar.value, TaskbarProgressValue.fraction(.75));
    expect(await old.exists(), isFalse);
    expect(await runtime.ensure(), isTrue);
    expect(
        await File(p.join(installed.path, 'licenses', 'IPADIC', 'NOTICE.txt'))
            .readAsBytes(),
        files['licenses/IPADIC/NOTICE.txt']);
    newer!.dispose();
    expect(taskbar.value, isNull);
    expect(
        await installed.parent
            .list()
            .where((e) =>
                p.basename(e.path).startsWith('.japanese-reading-install-'))
            .toList(),
        isEmpty);
  });

  test(
      'download cancellation preserves installed dictionary and unrelated files',
      () async {
    await putDictionary(installed);
    final old = File(p.join(installed.path, 'old-marker.txt'));
    await old.writeAsString('preserve old component');
    final taskbar = TaskbarProgress();
    addTearDown(taskbar.dispose);
    late JapaneseDictionaryModuleInstaller installer;
    installer = JapaneseDictionaryModuleInstaller(
        runtime: runtime,
        taskbarProgress: taskbar,
        download: (destination, report, active) async {
          await archive.copy(destination.path);
          installer.cancel();
          expect(active(), isFalse);
        });
    await expectLater(installer.install(progress: (_) {}),
        throwsA(isA<JapaneseDictionaryUnavailable>()));
    expect(await old.readAsString(), 'preserve old component');
    expect(await runtime.ensure(), isTrue);
    expect(taskbar.value, isNull);
    expect(await installed.parent.list().toList(), hasLength(1));
  });

  test('failed ZIP verification preserves installed dictionary', () async {
    await putDictionary(installed);
    final old = File(p.join(installed.path, 'old-marker.txt'));
    await old.writeAsString('preserve old component');
    final taskbar = TaskbarProgress();
    addTearDown(taskbar.dispose);
    final installer = JapaneseDictionaryModuleInstaller(
        runtime: runtime,
        taskbarProgress: taskbar,
        download: (destination, report, active) async {
          await destination.writeAsBytes([1, 2, 3]);
        });
    await expectLater(
        installer.install(progress: (_) {}), throwsFormatException);
    expect(await old.readAsString(), 'preserve old component');
    expect(await runtime.ensure(), isTrue);
    expect(taskbar.value, isNull);
    expect(await installed.parent.list().toList(), hasLength(1));
  });

  test('cancellation after directory replacement restores previous component',
      () async {
    final controlled =
        _CommitRuntime(installRoot: installed, applicationDirectory: app);
    await putDictionary(installed);
    final old = File(p.join(installed.path, 'old-marker.txt'));
    await old.writeAsString('preserve replaced component');
    final taskbar = TaskbarProgress();
    addTearDown(taskbar.dispose);
    final installer = JapaneseDictionaryModuleInstaller(
        runtime: controlled,
        taskbarProgress: taskbar,
        download: (destination, report, active) =>
            archive.copy(destination.path));
    final pending = installer.install(progress: (_) {});
    final rejected =
        expectLater(pending, throwsA(isA<JapaneseDictionaryUnavailable>()));
    await controlled.committed.future;
    expect(await old.exists(), isFalse);
    installer.cancel();
    controlled.resume.complete();
    await rejected;
    expect(await old.readAsString(), 'preserve replaced component');
    expect(await controlled.dictionaryPath(),
        p.join(installed.path, japaneseDictionaryFileName));
    expect(taskbar.value, isNull);
    // A recovery copy is retained if needed; no new component replaces the old.
    expect(await installed.parent.list().toList(), hasLength(1));
  });
}
