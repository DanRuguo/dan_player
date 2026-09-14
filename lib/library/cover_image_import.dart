import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/src/rust/api/cover_image.dart' as native;
import 'package:desktop_lyric/ui_language.dart' as language;
import 'package:path/path.dart' as path;

const maxCoverInputBytes = 20 * 1024 * 1024;
const maxCoverInputPixels = 40000000;
const maxCoverOutputBytes = 2 * 1024 * 1024;
const maxCoverOutputEdge = 1600;

bool isImportedCoverId(Object? value) =>
    value is String &&
    RegExp(r'^[a-f0-9]{64}\.(png|jpg|webp)$').hasMatch(value);

class CoverImageException extends FormatException {
  const CoverImageException(super.message);
  @override
  String toString() => language.ui(message);
}

class PreparedCoverImage {
  const PreparedCoverImage(this.bytes, this.extension, this.width, this.height);
  final Uint8List bytes;
  final String extension;
  final int width;
  final int height;
}

/// One import at a time bounds decode/encode memory. Small, static images are
/// decoded once for validation and retained byte-for-byte. Native workers do
/// resizing/compression only when necessary; no per-frame processing exists.
class CoverImageImporter {
  CoverImageImporter({
    Future<PreparedCoverImage> Function(Uint8List)? normalizeLarge,
  }) : _normalizeLarge = normalizeLarge ?? _nativeNormalize;
  static final shared = CoverImageImporter();
  final Future<PreparedCoverImage> Function(Uint8List) _normalizeLarge;
  Future<void> _tail = Future.value();
  int _queuedBytes = 0;

  static Future<PreparedCoverImage> _nativeNormalize(Uint8List bytes) async {
    try {
      final result = await native.normalizeCoverImage(data: bytes);
      return PreparedCoverImage(
          result.bytes, result.extension_, result.width, result.height);
    } catch (error) {
      var message = error.toString();
      if (message.startsWith('AnyhowException(') && message.endsWith(')')) {
        message = message.substring(16, message.length - 1);
      }
      throw CoverImageException(message);
    }
  }

  Future<PreparedCoverImage> fromFile(String sourcePath) async {
    final source = File(sourcePath);
    final stat = await source.stat();
    if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
      throw const CoverImageException('封面图片为空或无法读取。');
    }
    if (stat.size > maxCoverInputBytes) {
      throw const CoverImageException('封面图片不能超过 20 MiB，请先缩小原图后重试。');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in source.openRead()) {
      if (bytes.length + chunk.length > maxCoverInputBytes) {
        throw const CoverImageException('封面图片不能超过 20 MiB，请先缩小原图后重试。');
      }
      bytes.add(chunk);
    }
    return fromBytes(bytes.takeBytes());
  }

  Future<PreparedCoverImage> fromBytes(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxCoverInputBytes) {
      return Future.error(CoverImageException(
          bytes.isEmpty ? '封面图片为空或无法读取。' : '封面图片不能超过 20 MiB，请先缩小原图后重试。'));
    }
    if (_queuedBytes + bytes.length > 64 * 1024 * 1024) {
      return Future.error(const CoverImageException('正在处理其他封面，请稍后重试。'));
    }
    _queuedBytes += bytes.length;
    final result = _tail.then((_) => _prepare(bytes)).whenComplete(() {
      _queuedBytes -= bytes.length;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<PreparedCoverImage> _prepare(Uint8List bytes) async {
    final extension = _extension(bytes);
    if (extension == null) {
      throw const CoverImageException('封面仅支持静态 PNG、JPEG、WebP 和 BMP 图片。');
    }
    if (_animated(bytes, extension)) {
      throw const CoverImageException('封面暂不支持动图，请选择静态图片。');
    }
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? decoded;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= 0 ||
          height <= 0 ||
          width > 32768 ||
          height > 32768 ||
          width * height > maxCoverInputPixels) {
        throw const CoverImageException('封面图片最多支持 4000 万像素，请先缩小原图后重试。');
      }
      if (width <= maxCoverOutputEdge &&
          height <= maxCoverOutputEdge &&
          bytes.length <= maxCoverOutputBytes &&
          extension != 'bmp') {
        codec = await descriptor.instantiateCodec();
        if (codec.frameCount != 1) {
          throw const CoverImageException('封面暂不支持动图，请选择静态图片。');
        }
        decoded = (await codec.getNextFrame()).image;
        return PreparedCoverImage(bytes, extension, width, height);
      }
      final result = await _normalizeLarge(bytes);
      if (result.bytes.isEmpty ||
          result.bytes.length > maxCoverOutputBytes ||
          result.width <= 0 ||
          result.width > maxCoverOutputEdge ||
          result.height <= 0 ||
          result.height > maxCoverOutputEdge ||
          !const ['png', 'jpg', 'webp'].contains(result.extension)) {
        throw const CoverImageException('无法将封面压缩到 2 MiB，请选择其他图片。');
      }
      return result;
    } on CoverImageException {
      rethrow;
    } catch (_) {
      throw const CoverImageException('封面图片已损坏或无法解码。');
    } finally {
      decoded?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static String? _extension(Uint8List data) {
    if (data.length < 12) return null;
    if (data[0] == 0xff && data[1] == 0xd8 && data[2] == 0xff) return 'jpg';
    if (data[0] == 137 && String.fromCharCodes(data.sublist(1, 4)) == 'PNG') {
      return 'png';
    }
    if (String.fromCharCodes(data.sublist(0, 2)) == 'BM') return 'bmp';
    if (String.fromCharCodes(data.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(data.sublist(8, 12)) == 'WEBP') {
      return 'webp';
    }
    return null;
  }

  static bool _animated(Uint8List bytes, String extension) {
    if (extension != 'png' && extension != 'webp') return false;
    final png = extension == 'png';
    final data = ByteData.sublistView(bytes);
    var offset = png ? 8 : 12;
    var chunks = 0;
    while (offset + 8 <= bytes.length) {
      if (++chunks > 4096) {
        throw const CoverImageException('封面图片已损坏或无法解码。');
      }
      final length = data.getUint32(
          png ? offset : offset + 4, png ? Endian.big : Endian.little);
      final at = png ? offset + 4 : offset;
      final type = String.fromCharCodes(bytes.sublist(at, at + 4));
      if (type == 'acTL' || type == 'ANIM' || type == 'ANMF') return true;
      if (!png &&
          type == 'VP8X' &&
          length > 0 &&
          offset + 8 < bytes.length &&
          bytes[offset + 8] & 2 != 0) {
        return true;
      }
      offset += length + (png ? 12 : 8 + (length & 1));
      if (offset > bytes.length) {
        throw const CoverImageException('封面图片已损坏或无法解码。');
      }
      if (png && type == 'IEND') break;
    }
    return false;
  }
}

Future<String> importPlaylistCoverFile(String sourcePath,
        {Future<Directory> Function()? dataDirectory}) async =>
    savePreparedPlaylistCover(
      await CoverImageImporter.shared.fromFile(sourcePath),
      dataDirectory: dataDirectory,
    );

Future<String> savePreparedPlaylistCover(PreparedCoverImage cover,
    {Future<Directory> Function()? dataDirectory}) async {
  if (cover.bytes.isEmpty ||
      cover.bytes.length > maxCoverOutputBytes ||
      cover.width <= 0 ||
      cover.width > maxCoverOutputEdge ||
      cover.height <= 0 ||
      cover.height > maxCoverOutputEdge ||
      !const ['png', 'jpg', 'webp'].contains(cover.extension)) {
    throw const CoverImageException('无法将封面压缩到 2 MiB，请选择其他图片。');
  }
  final directory = Directory(path.join(
      (await (dataDirectory ?? getAppDataDir)()).path, 'playlist-covers'));
  final type = await FileSystemEntity.type(directory.path, followLinks: false);
  if (type != FileSystemEntityType.notFound &&
      type != FileSystemEntityType.directory) {
    throw const CoverImageException('无法保存封面副本，请检查目录权限。');
  }
  await directory.create(recursive: true);
  final id = '${sha256.convert(cover.bytes)}.${cover.extension}';
  final file = File(path.join(directory.path, id));
  final existing = await FileSystemEntity.type(file.path, followLinks: false);
  if (existing != FileSystemEntityType.notFound) {
    if (existing != FileSystemEntityType.file ||
        await file.length() != cover.bytes.length ||
        sha256.convert(await file.readAsBytes()).toString() !=
            id.substring(0, 64)) {
      throw const CoverImageException('已保存的封面副本损坏，请选择其他图片。');
    }
    return file.absolute.path;
  }
  final staging = await directory.createTemp('.cover-');
  final partial = File(path.join(staging.path, id));
  try {
    await partial.writeAsBytes(cover.bytes, flush: true);
    if (!await file.exists()) await partial.rename(file.path);
  } finally {
    if (await partial.exists()) await partial.delete();
    await staging.delete();
  }
  return file.absolute.path;
}
