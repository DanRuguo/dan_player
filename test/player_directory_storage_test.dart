import 'dart:io';

import 'package:dan_player/statistics/app_data_storage.dart';
import 'package:dan_player/statistics/player_directory_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _MetadataFile implements File {
  _MetadataFile(this.delegate);
  final File delegate;
  var statCalls = 0, resolveCalls = 0;
  @override
  String get path => delegate.path;
  @override
  File get absolute => this;
  @override
  Future<FileStat> stat() {
    statCalls++;
    return delegate.stat();
  }

  @override
  Future<String> resolveSymbolicLinks() {
    resolveCalls++;
    return delegate.resolveSymbolicLinks();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MetadataDirectory implements Directory {
  _MetadataDirectory(this.delegate, this.file);
  final Directory delegate;
  final _MetadataFile file;
  @override
  String get path => delegate.path;
  @override
  Directory get absolute => this;
  @override
  Future<String> resolveSymbolicLinks() => delegate.resolveSymbolicLinks();
  @override
  Stream<FileSystemEntity> list(
      {bool recursive = false, bool followLinks = true}) async* {
    yield file;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _junction(Directory link, Directory target) async {
  if (Platform.isWindows) {
    final result = await Process.run(
        p.join(Platform.environment['SystemRoot'] ?? r'C:\Windows', 'System32',
            'WindowsPowerShell', 'v1.0', 'powershell.exe'),
        [
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-Command',
          'New-Item -ItemType Junction -Path \$env:DAN_STORAGE_LINK -Target \$env:DAN_STORAGE_TARGET -ErrorAction Stop | Out-Null'
        ],
        environment: {
          'DAN_STORAGE_LINK': link.path,
          'DAN_STORAGE_TARGET': target.path
        });
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  } else {
    await Link(link.path).create(target.path);
  }
}

void main() {
  late Directory fixture, root;
  const scanner = PlayerDirectoryStorageScanner();
  setUp(() async {
    fixture =
        await Directory.systemTemp.createTemp('player-directory-storage-');
    root = await Directory(p.join(fixture.path, 'player')).create();
  });
  tearDown(() async => fixture.delete(recursive: true));
  Future<File> write(String relative, int bytes) async {
    final file = File(p.join(root.path, relative));
    await file.parent.create(recursive: true);
    return file.writeAsBytes(List.filled(bytes, 37));
  }

  test('portable and legacy component paths have one stable category', () {
    for (final entry in {
      'Dan Player.exe': '主程序',
      'desktop_lyric/desktop_lyric.exe': '主程序',
      'flutter_windows.dll': 'Flutter引擎与运行库',
      'rust_lib_dan_player.dll': 'Flutter引擎与运行库',
      'vcruntime140.dll': 'Flutter引擎与运行库',
      'data/app.so': 'Flutter引擎与运行库',
      'desktop_lyric/data/app.so': 'Flutter引擎与运行库',
      'data/icudtl.dat': 'Flutter引擎与运行库',
      'data/flutter_assets/packages/desktop_lyric/assets/fonts/GoogleSans-VF.ttf':
          '字体',
      'data/flutter_assets/packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf':
          '字体',
      'data/flutter_assets/packages/desktop_lyric/assets/fonts/SourceHanSansJP-Regular.otf':
          '字体',
      'data/flutter_assets/packages/desktop_lyric/assets/fonts/Pretendard-Regular.otf':
          '字体',
      'desktop_lyric/data/flutter_assets/assets/fonts/PingFangSC-Regular.ttf':
          '字体',
      'data/flutter_assets/fonts/MaterialIcons-Regular.otf': '字体',
      'data/flutter_assets/FontManifest.json': '界面资源',
      'data/flutter_assets/assets/images/RCE_logo_transparent.png': '界面资源',
      'data/flutter_assets/shaders/edge.frag': '界面资源',
      'data/flutter_assets/NOTICES.Z': '说明与许可证',
      'data/flutter_assets/packages/desktop_lyric/shaders/FLUTTER-LICENSE.txt':
          '说明与许可证',
      'data/flutter_assets/third_party/desktop_lyric/shaders/FLUTTER-LICENSE.txt':
          '说明与许可证',
      'BASS/bass_fx.dll': 'BASS音频组件',
      'BASS/bass.dll': 'BASS音频组件',
      'tool/ffmpeg/bin/ffmpeg.exe': 'FFmpeg工具',
      'tools/ffmpeg/ffprobe.exe': 'FFmpeg工具',
      'tool/ffplay.exe': 'FFmpeg工具',
      'tools/ffmpeg-7.1.1/ffmpeg.exe': 'FFmpeg工具',
      '.dan-player-install/unins000.exe': '更新与安装辅助',
      '.dan-player-install/payload.manifest': '更新与安装辅助',
      'dan_player_shell_action.exe': '更新与安装辅助',
      'updates/DanPlayer-26.1.1-Setup.exe': '更新与安装辅助',
      'licenses/SOURCE-HAN-SANS/OFL.txt': '说明与许可证',
      'LICENSE': '说明与许可证',
      'BUILD-PROVENANCE.json': '说明与许可证',
      'FONT-INTEGRITY.json': '说明与许可证',
      'PORTABLE-README.txt': '说明与许可证',
      'SHA256SUMS': '说明与许可证',
      'custom.bin': '其他文件',
    }.entries) {
      expect(PlayerDirectoryStorageScanner.categoryFor(entry.key), entry.value,
          reason: entry.key);
      expect(
          PlayerDirectoryStorageScanner.categoryFor(
              entry.key.toUpperCase().replaceAll('/', r'\')),
          entry.value,
          reason: 'Windows separators and case: ${entry.key}');
    }
  });

  test('FFmpeg detection excludes similar directory and filename aliases', () {
    for (final relative in [
      'tool/ffmpeg-backup/bin/ffmpeg.exe',
      'tools/ffmpegness/ffmpeg.exe',
      'tools/ffmpeg-7.1.1-old/ffmpeg.exe',
      'tool/ffmpeghelper.exe',
      'unrelated/ffmpeg.exe',
    ]) {
      expect(PlayerDirectoryStorageScanner.categoryFor(relative), '其他文件');
    }
    expect(PlayerDirectoryStorageScanner.categoryFor('tool/ffmpeg/LICENSE.txt'),
        '说明与许可证');
    expect(
        PlayerDirectoryStorageScanner.categoryFor(
            'licenses/BASS_FX/bass_fx.txt'),
        '说明与许可证');
  });

  test('actual fixture bytes and files are partitioned once in category order',
      () async {
    final files = {
      'Dan Player.exe': 11,
      'flutter_windows.dll': 13,
      'data/app.so': 17,
      'data/icudtl.dat': 19,
      'data/flutter_assets/packages/desktop_lyric/assets/fonts/Pretendard-Regular.otf':
          23,
      'data/flutter_assets/assets/images/logo.png': 29,
      'BASS/bass.dll': 31,
      'tool/ffmpeg/bin/ffmpeg.exe': 37,
      '.dan-player-install/unins000.exe': 41,
      'licenses/SOURCE-HAN-SANS/OFL.txt': 43,
      'other.bin': 0,
    };
    for (final entry in files.entries) {
      await write(entry.key, entry.value);
    }
    final snapshot = await scanner.scan(root);
    expect(snapshot.path, root.path);
    expect(snapshot.files, files.length);
    expect(snapshot.bytes, files.values.fold<int>(0, (a, b) => a + b));
    expect(snapshot.parts.map((part) => part.label),
        PlayerDirectoryStorageScanner.categories);
    expect(snapshot.unreadable, 0);
    expect(snapshot.skippedLinks, 0);
    expect(snapshot.truncated, false);
    final expected = <String, (int, int)>{};
    for (final entry in files.entries) {
      final label = PlayerDirectoryStorageScanner.categoryFor(entry.key);
      final old = expected[label] ?? (0, 0);
      expected[label] = (old.$1 + 1, old.$2 + entry.value);
    }
    for (final part in snapshot.parts) {
      expect((part.files, part.bytes), expected[part.label]);
      expect(part.paths.every((path) => p.isWithin(root.path, path)), true);
    }
    expect(snapshot.parts.first.paths, [p.join(root.path, 'Dan Player.exe')]);
    final fonts = snapshot.parts.singleWhere((part) => part.label == '字体');
    expect(fonts.paths, [
      p.normalize(p.join(
          root.path, 'data/flutter_assets/packages/desktop_lyric/assets/fonts'))
    ]);
  });

  test('reported paths are bounded and returned collections are read only',
      () async {
    for (var i = 0; i < 20; i++) {
      await write('data/flutter_assets/group-$i/file.bin', i + 1);
    }
    final snapshot = await scanner.scan(root);
    expect(snapshot.files, 20);
    expect(snapshot.bytes, 210);
    expect(snapshot.parts.single.paths, hasLength(12));
    expect(() => snapshot.parts.clear(), throwsUnsupportedError);
    expect(() => snapshot.parts.single.paths.add(root.path),
        throwsUnsupportedError);
  });

  test('entry budget returns an explicit partial snapshot', () async {
    for (var i = 0; i < 8; i++) {
      await write('file-$i.bin', 10);
    }
    final snapshot =
        await const PlayerDirectoryStorageScanner(maximumEntries: 2).scan(root);
    expect(snapshot.truncated, true);
    expect(snapshot.files, 2);
    expect(snapshot.bytes, 20);
    expect(snapshot.unreadable, 0);
  });

  test('cache scanning retains one stat while player rechecks file links',
      () async {
    final file = _MetadataFile(await write('Dan Player.exe', 7));
    final directory = _MetadataDirectory(root, file);
    final cache = await const AppDataStorageScanner().scan(directory);
    expect(cache.files, 1);
    expect(cache.bytes, 7);
    expect(file.statCalls, 1);
    expect(file.resolveCalls, 0,
        reason: 'Large cache reports retain their existing metadata I/O cost.');
    final player = await scanner.scan(directory);
    expect(player.files, 1);
    expect(player.bytes, 7);
    expect(file.statCalls, 2);
    expect(file.resolveCalls, 1,
        reason: 'Player files use one additional canonical-path check.');
  });

  test('zero time budget returns before any directory metadata is required',
      () async {
    final missing = Directory(p.join(fixture.path, 'does-not-exist'));
    final snapshot = await const PlayerDirectoryStorageScanner(
            maximumDuration: Duration.zero)
        .scan(missing);
    expect(snapshot.truncated, true);
    expect(snapshot.files, 0);
    expect(snapshot.bytes, 0);
    expect(snapshot.unreadable, 0);
  });

  test('missing directory is reported as unreadable without invented bytes',
      () async {
    final snapshot =
        await scanner.scan(Directory(p.join(fixture.path, 'does-not-exist')));
    expect(snapshot.files, 0);
    expect(snapshot.bytes, 0);
    expect(snapshot.unreadable, 1);
    expect(snapshot.truncated, false);
  });

  test('outside directory links and a linked root are skipped', () async {
    await write('Dan Player.exe', 3);
    final outside = await Directory(p.join(fixture.path, 'outside')).create();
    final sentinel = await File(p.join(outside.path, 'private-song.flac'))
        .writeAsBytes(List.filled(97, 5));
    final link = Directory(p.join(root.path, 'external'));
    await _junction(link, outside);
    final snapshot = await scanner.scan(root);
    expect(snapshot.files, 1);
    expect(snapshot.bytes, 3);
    expect(snapshot.skippedLinks, 1);
    expect(snapshot.truncated, false);
    expect(await sentinel.length(), 97);
    final linkedRoot = await scanner.scan(link);
    expect(linkedRoot.files, 0);
    expect(linkedRoot.bytes, 0);
    expect(linkedRoot.skippedLinks, 1);
  });

  test('internal junction cycle cannot duplicate files or consume the budget',
      () async {
    await write('BASS/bass.dll', 7);
    await _junction(Directory(p.join(root.path, 'BASS', 'back')), root);
    final snapshot = await scanner.scan(root);
    expect(snapshot.files, 1);
    expect(snapshot.bytes, 7);
    expect(snapshot.skippedLinks, 1);
    expect(snapshot.truncated, false);
  });

  test('cancellation is distinct from filesystem errors before enumeration',
      () async {
    await expectLater(
        scanner.scan(Directory(p.join(fixture.path, 'missing')),
            isCancelled: () => true),
        throwsA(isA<DirectoryStorageScanCancelled>()));
  });

  test(
      'cancellation during metadata traversal never publishes a partial report',
      () async {
    await write('Dan Player.exe', 3);
    var checks = 0;
    await expectLater(scanner.scan(root, isCancelled: () => ++checks >= 4),
        throwsA(isA<DirectoryStorageScanCancelled>()));
    expect(checks, 4);
  });
}
