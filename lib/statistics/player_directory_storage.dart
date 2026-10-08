import 'dart:io';

import 'package:path/path.dart' as p;

import 'directory_storage_scan.dart';
export 'directory_storage_scan.dart'
    show
        AppDataStoragePart,
        AppDataStorageSnapshot,
        DirectoryStorageScanCancelled;

/// Logical file bytes inside the supplied executable directory only. Optional
/// tools installed elsewhere, PATH candidates and user data are not discovered.
class PlayerDirectoryStorageScanner {
  const PlayerDirectoryStorageScanner({
    this.maximumEntries = 200000,
    this.maximumDuration = const Duration(seconds: 15),
    this.operationTimeout = const Duration(seconds: 3),
  });
  final int maximumEntries;
  final Duration maximumDuration, operationTimeout;

  Future<AppDataStorageSnapshot> scan(Directory directory,
          {bool Function()? isCancelled}) =>
      DirectoryStorageScan(
              maximumEntries: maximumEntries,
              maximumDuration: maximumDuration,
              operationTimeout: operationTimeout,
              verifyFileLinks: true)
          .scan(directory,
              categories: categories,
              categoryFor: categoryFor,
              isCancelled: isCancelled,
              locationFor: (file, _) =>
                  p.equals(p.dirname(file.path), directory.path)
                      ? file.path
                      : p.dirname(file.path));

  static const categories = [
    '主程序',
    'Flutter引擎与运行库',
    '字体',
    '界面资源',
    'BASS音频组件',
    'FFmpeg工具',
    '更新与安装辅助',
    '说明与许可证',
    '其他文件'
  ];
  static final _noticeName =
      RegExp(r'^(?:license|notice|readme|portable-readme)(?:[._-].*)?$');
  static final _ffmpegDirectory = RegExp(r'^tools?/ffmpeg(?:-\d+\.\d+\.\d+)?/');
  static final _ffmpegDirectTool =
      RegExp(r'^tool/(?:ffmpeg|ffprobe|ffplay)\.exe$');

  static String categoryFor(String relative) {
    final value = relative.replaceAll('\\', '/').toLowerCase();
    final local = value.startsWith('desktop_lyric/')
        ? value.substring('desktop_lyric/'.length)
        : value;
    final name = p.posix.basename(local);
    if (local == 'dan player.exe' || local == 'desktop_lyric.exe') {
      return categories[0];
    }
    if (value.startsWith('licenses/') ||
        local.startsWith('licenses/') ||
        name == 'license' ||
        name == 'notice' ||
        name == 'sha256sums' ||
        name == 'desktop-lyric-mode' ||
        name == 'build-provenance.json' ||
        name == 'font-integrity.json' ||
        name == 'notices.z' ||
        name == 'flutter-license.txt' ||
        _noticeName.hasMatch(name)) {
      return categories[7];
    }
    if (local.startsWith('bass/')) return categories[4];
    if (_ffmpegDirectory.hasMatch(local) || _ffmpegDirectTool.hasMatch(local)) {
      return categories[5];
    }
    if (local.startsWith('.dan-player-install/') ||
        local.startsWith('updates/') ||
        local.startsWith('installer/') ||
        local == 'dan_player_shell_action.exe' ||
        local == 'dan_player_update_launcher.exe') {
      return categories[6];
    }
    if (local.startsWith('data/flutter_assets/')) {
      return const ['.ttf', '.otf', '.ttc', '.woff', '.woff2']
              .contains(p.posix.extension(name))
          ? categories[2]
          : categories[3];
    }
    if (local == 'data/app.so' ||
        local == 'data/icudtl.dat' ||
        local.endsWith('.dll')) {
      return categories[1];
    }
    return categories[8];
  }
}
