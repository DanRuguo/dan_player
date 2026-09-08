import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path;

class BackgroundImageException implements Exception {
  const BackgroundImageException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ManagedBackgroundImage {
  const ManagedBackgroundImage({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
  });
  final String id;
  final String name;
  final int width;
  final int height;
}

/// Owns only background rendering copies. It never edits or removes a selected
/// source, and never interprets a persisted ID as a path or URL.
///
/// Import is deliberately single-flight: encoded input is limited to 20 MiB,
/// its header to 40 MP, and the managed PNG to a 2048-edge / 4-MP contain sample.
/// The latter is a decoded OUTPUT budget, not a promise about codec peak memory.
/// Original pictures and foreground album art are not routed through this store.
class BackgroundImageStore {
  BackgroundImageStore({
    required Future<Directory> Function() directory,
    Future<Set<String>> Function()? persistedIds,
    this.maxStoredBytes = 96 * 1024 * 1024,
    this.maxStoredImages = 24,
  })  : _directoryProvider = directory,
        _persistedIds = persistedIds;

  static final instance = BackgroundImageStore(
    directory: () async =>
        Directory(path.join((await getAppDataDir()).path, 'background-images')),
    persistedIds: _readPersistedIds,
  );

  static const maxInputBytes = 20 * 1024 * 1024;
  static const maxInputPixels = 40 * 1000 * 1000;
  static const maxOutputEdge = 2048;
  static const maxOutputPixels = 4 * 1024 * 1024;

  final Future<Directory> Function() _directoryProvider;
  final Future<Set<String>> Function()? _persistedIds;
  final int maxStoredBytes;
  final int maxStoredImages;
  final _images = <String, Future<ImageProvider?>>{};
  Future<void> _operation = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _operation.then((_) => action());
    // An unsuccessful import must not poison subsequent user requests.
    _operation = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<Directory> _directory({bool create = false}) async {
    final directory = (await _directoryProvider()).absolute;
    final kind =
        await FileSystemEntity.type(directory.path, followLinks: false);
    if (kind == FileSystemEntityType.link ||
        (kind != FileSystemEntityType.notFound &&
            kind != FileSystemEntityType.directory)) {
      throw const BackgroundImageException('背景副本目录不可用，请检查目录权限。');
    }
    if (create) await directory.create(recursive: true);
    if (await directory.exists()) {
      final parent = await directory.parent.resolveSymbolicLinks();
      final resolved = await directory.resolveSymbolicLinks();
      if (!path.isWithin(parent, resolved)) {
        throw const BackgroundImageException('背景副本目录不能指向其它位置。');
      }
      return Directory(resolved);
    }
    return directory;
  }

  Future<ManagedBackgroundImage> importFile(String sourcePath) =>
      _serial(() => _importFile(sourcePath));

  Future<ManagedBackgroundImage> _importFile(String sourcePath) async {
    if (sourcePath.trim().isEmpty) {
      throw const BackgroundImageException('请选择一张本地图片。');
    }
    final source = File(sourcePath);
    final stat = await source.stat();
    if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
      throw const BackgroundImageException('图片不存在、为空或无法读取。');
    }
    if (stat.size > maxInputBytes) {
      throw const BackgroundImageException('图片不能超过 20 MiB，请选择较小的图片。');
    }
    final bytes = BytesBuilder(copy: false);
    // Bound the stream too, in case the source grows after the stat call.
    await for (final chunk in source.openRead()) {
      if (bytes.length + chunk.length > maxInputBytes) {
        throw const BackgroundImageException('图片不能超过 20 MiB。');
      }
      bytes.add(chunk);
    }
    final encoded = bytes.takeBytes();
    if (!_supportedHeader(encoded)) {
      throw const BackgroundImageException('仅支持静态 PNG、JPEG、WebP 和 BMP 图片。');
    }
    if (_animatedHeader(encoded)) {
      throw const BackgroundImageException('暂不支持动图；可为静态图片开启轻缓动态效果。');
    }

    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    late Uint8List png;
    late int width;
    late int height;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 ||
          descriptor.height <= 0 ||
          descriptor.width * descriptor.height > maxInputPixels) {
        throw const BackgroundImageException('图片像素数过大（最多 4000 万像素）。');
      }
      final scale = math.min(
          1.0,
          math.min(
              maxOutputEdge / math.max(descriptor.width, descriptor.height),
              math.sqrt(
                  maxOutputPixels / (descriptor.width * descriptor.height))));
      width = math.max(1, (descriptor.width * scale).floor());
      height = math.max(1, (descriptor.height * scale).floor());
      codec = await descriptor.instantiateCodec(
          targetWidth: width, targetHeight: height);
      if (codec.frameCount != 1) {
        throw const BackgroundImageException('暂不支持动图；可为静态图片开启轻缓动态效果。');
      }
      image = (await codec.getNextFrame()).image;
      final output = await image.toByteData(format: ui.ImageByteFormat.png);
      if (output == null || output.lengthInBytes > maxInputBytes) {
        throw const BackgroundImageException('无法生成受控的背景副本，请换一张图片。');
      }
      png =
          output.buffer.asUint8List(output.offsetInBytes, output.lengthInBytes);
    } on BackgroundImageException {
      rethrow;
    } catch (_) {
      throw const BackgroundImageException('图片已损坏或无法解码，原背景未改变。');
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }

    final id = '${sha256.convert(png)}.png';
    final directory = await _directory(create: true);
    final destination = File(path.join(directory.path, id));
    final existing =
        await FileSystemEntity.type(destination.path, followLinks: false);
    if (existing != FileSystemEntityType.notFound) {
      if (existing != FileSystemEntityType.file ||
          (await destination.length()) != png.length ||
          sha256.convert(await destination.readAsBytes()).toString() !=
              id.substring(0, 64)) {
        throw const BackgroundImageException('同名背景副本损坏，请先清理未使用副本。');
      }
    } else {
      var total = 0;
      var count = 0;
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is File && isBackgroundImageId(path.basename(entry.path))) {
          total += (await entry.stat()).size;
          count++;
        }
      }
      if (count >= maxStoredImages || total + png.length > maxStoredBytes) {
        throw const BackgroundImageException('背景副本空间已满，请先点击“清理未使用副本”再导入。');
      }
      final temporary = await directory.createTemp('.import-');
      final partial = File(path.join(temporary.path, 'background.png'));
      try {
        await partial.writeAsBytes(png, flush: true);
        // The serial queue and content ID avoid overwriting another import.
        if (await FileSystemEntity.type(destination.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw const BackgroundImageException('背景副本发生冲突，请重新选择图片。');
        }
        await partial.rename(destination.path);
      } finally {
        // Only this request's temporary file and now-empty directory are ours.
        if (await partial.exists()) await partial.delete();
        if (await temporary.exists()) await temporary.delete();
      }
    }
    _images.remove(id);
    var name = path.posix.basename(sourcePath.replaceAll('\\', '/'));
    name = name.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '');
    if (name.length > 180) name = name.substring(0, 180);
    return ManagedBackgroundImage(
        id: id, name: name, width: width, height: height);
  }

  Future<ImageProvider?> imageFor(String? id) {
    if (!isBackgroundImageId(id)) return Future.value();
    final previous = _images.remove(id);
    final request = previous ?? _readImage(id!);
    _images[id!] = request;
    while (_images.length > 6) {
      _images.remove(_images.keys.first);
    }
    return request;
  }

  /// Evict only reconstructable provider/decoded state, retaining the managed
  /// original and all references even if it is temporarily unreadable.
  Future<ImageProvider?> reloadImage(String id) async {
    final old = _images.remove(id);
    if (old != null) await (await old)?.evict();
    final image = await _readImage(id);
    if (image != null) await image.evict();
    _images[id] = Future.value(image);
    while (_images.length > 6) {
      _images.remove(_images.keys.first);
    }
    return image;
  }

  Future<ImageProvider?> _readImage(String id) async {
    try {
      final directory = await _directory();
      final file = File(path.join(directory.path, id));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      return FileImage(file);
    } catch (_) {
      return null;
    }
  }

  /// Explicit user action only. Inactive scene selections must be retained too.
  /// Unknown files, links, partials and original pictures are never removed.
  Future<int> removeUnused(Set<String> Function() retainedIds) =>
      _serial(() async {
        // A settings save can fail while the session uses a newer picture.
        // Preserve references in both the live model and saved/backup settings.
        // Read all of these before the first delete; malformed settings fail
        // closed rather than making recovery lose its background images.
        final persisted = await _persistedIds?.call() ?? <String>{};
        final directory = await _directory();
        if (!await directory.exists()) return 0;
        var removed = 0;
        await for (final entry in directory.list(followLinks: false)) {
          final id = path.basename(entry.path);
          if (entry is! File ||
              !isBackgroundImageId(id) ||
              persisted.contains(id) ||
              retainedIds().contains(id)) {
            continue;
          }
          if (await FileSystemEntity.type(entry.path, followLinks: false) !=
              FileSystemEntityType.file) {
            continue;
          }
          await entry.delete();
          _images.remove(id);
          removed++;
        }
        return removed;
      });

  static Future<Set<String>> _readPersistedIds() async {
    final directory = await getAppDataDir();
    final result = <String>{};
    for (final name in ['settings.json', 'settings.json.bak']) {
      final file = File(path.join(directory.path, name));
      final kind = await FileSystemEntity.type(file.path, followLinks: false);
      if (kind == FileSystemEntityType.notFound) continue;
      if (kind != FileSystemEntityType.file ||
          await file.length() > 4 * 1024 * 1024) {
        throw const BackgroundImageException('已保存配置不可读，暂不清理背景副本。');
      }
      final settings = jsonDecode(await file.readAsString());
      if (settings is! Map ||
          (settings['Backgrounds'] != null &&
              settings['Backgrounds'] is! Map)) {
        throw const BackgroundImageException('已保存配置无效，暂不清理背景副本。');
      }
      final backgrounds = settings['Backgrounds'];
      if (backgrounds is Map) {
        for (final scene in BackgroundScene.values) {
          final appearance = backgrounds[scene.name];
          if (appearance == null) continue;
          // Reading preferences may recover malformed values using defaults;
          // destructive cleanup may not infer that unreadable references are
          // unused. Reject the entire cleanup before deleting its first file.
          if (appearance is! Map ||
              (appearance['customImageId'] != null &&
                  !isBackgroundImageId(appearance['customImageId']))) {
            throw const BackgroundImageException('已保存图片引用不可读，暂不清理背景副本。');
          }
        }
      }
      result.addAll(BackgroundPreferences.fromMap(settings['Backgrounds'])
          .retainedImageIds);
    }
    return result;
  }

  static bool _supportedHeader(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final png = bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 13 &&
        bytes[5] == 10 &&
        bytes[6] == 26 &&
        bytes[7] == 10;
    final jpeg = bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    final bmp = bytes[0] == 0x42 && bytes[1] == 0x4d;
    final webp = bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return png || jpeg || bmp || webp;
  }

  static bool _animatedHeader(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final png = bytes[0] == 0x89;
    final webp = bytes[0] == 0x52;
    if (!png && !webp) return false;
    var offset = png ? 8 : 12;
    while (offset + 8 <= bytes.length) {
      final length = data.getUint32(
          png ? offset : offset + 4, png ? Endian.big : Endian.little);
      final typeAt = png ? offset + 4 : offset;
      final type = String.fromCharCodes(bytes.sublist(typeAt, typeAt + 4));
      if ((png && type == 'acTL') || (webp && type == 'ANIM')) return true;
      if (webp &&
          type == 'VP8X' &&
          length >= 1 &&
          offset + 8 < bytes.length &&
          (bytes[offset + 8] & 2) != 0) {
        return true;
      }
      final next = offset +
          8 +
          length +
          (png
              ? 4
              : length.isOdd
                  ? 1
                  : 0);
      if (next <= offset || next > bytes.length) break;
      offset = next;
    }
    return false;
  }
}
