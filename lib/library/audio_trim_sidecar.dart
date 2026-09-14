import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/lyric/lyric_text_codec.dart';
import 'package:dan_player/src/rust/api/audio_trim.dart' as native;
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef TrimLyricTransform = Future<String> Function(
    String text, double startSeconds, double endSeconds);
const _maxLyricBytes = 4 * 1024 * 1024;

Future<String> _transformLyrics(String text, double start, double end) =>
    native.trimAudioLyricText(text: text, startSeconds: start, endSeconds: end);

String _hash(List<int> bytes) => sha256.convert(bytes).toString();

/// An external lyric transaction is prepared before audio publication. Its
/// original bytes remain available until the audio and index have both saved.
class PreparedTrimLyrics {
  PreparedTrimLyrics._(
      {required this.source,
      required this.destination,
      required this.overwrite,
      required this.unsupported,
      required String originalHash,
      required String outputHash,
      required Directory work})
      : _originalHash = originalHash,
        _outputHash = outputHash,
        _work = work;

  final String source;
  final String destination;
  final bool overwrite;
  final bool unsupported;
  final String _originalHash;
  final String _outputHash;
  final Directory _work;
  String get _staged => p.join(_work.path, 'adjusted.lrc');
  String get _backup => p.join(_work.path, 'original.lrc');
  bool _committed = false;
  bool _disposed = false;
  bool _preserveRecovery = false;
  String? get recoveryPath =>
      overwrite && (_committed || _preserveRecovery) ? _backup : null;

  Future<void> commit() async {
    if (_disposed) throw StateError('Lyric transaction is disposed');
    if (_committed) return;
    try {
      await Isolate.run(() => _commitLyrics(source, destination, _staged,
          _backup, overwrite, _originalHash, _outputHash));
      _committed = true;
    } catch (error) {
      // ReplaceFileW can report a partial rename (1177). Recover its backup
      // before propagating failure, while the original audio is still intact.
      if (overwrite && await File(_backup).exists()) {
        _committed = true;
        final warning = await rollback();
        if (warning != null) {
          throw AudioTrimException('lyric_rollback', warning);
        }
      }
      rethrow;
    }
  }

  /// Never roll back over lyrics edited by the user after publication.
  /// A recovery warning always includes the actual retained file path.
  Future<String?> rollback() async {
    if (!_committed || _disposed) return null;
    try {
      await Isolate.run(() => _rollbackLyrics(
          destination, _backup, overwrite, _originalHash, _outputHash));
      _committed = false;
      return null;
    } catch (_) {
      _preserveRecovery = true;
      return '${'歌词回滚未完成，已保留现有文件。恢复文件位于：'}\n'
          '${overwrite ? _backup : destination}';
    }
  }

  /// Cleanup touches only files created by this transaction. A nonempty work
  /// folder is retained rather than recursively removing any unexpected file.
  Future<String?> dispose({bool keepBackup = false}) async {
    if (_disposed) return null;
    _disposed = true;
    final preserve = keepBackup || _preserveRecovery;
    String? warning;
    try {
      if (await File(_staged).exists()) await File(_staged).delete();
      final backup = File(_backup);
      if (await backup.exists()) {
        if (preserve) {
          warning = '${'原歌词恢复副本已保留：'}\n$_backup';
        } else {
          await Isolate.run(() => _deleteVerifiedFile(_backup, _originalHash));
        }
      }
    } catch (_) {
      warning = '${'歌词临时文件未能清理，请检查：'}\n${_work.path}';
    }
    try {
      await _work.delete();
    } catch (_) {}
    return warning;
  }
}

Future<PreparedTrimLyrics?> prepareTrimmedAudioLyrics(
    String source, AudioTrimRequest request,
    {TrimLyricTransform transform = _transformLyrics}) async {
  if (!request.overwrite && !request.preserveMetadata) return null;
  if (request.overwrite &&
      !p.equals(p.normalize(source), p.normalize(request.destinationPath))) {
    throw const AudioTrimException('destination', '覆盖只能保存到原文件，副本必须使用其他文件名');
  }
  final original = p.setExtension(source, '.lrc');
  if (!await File(original).exists()) return null;
  final destination = p.setExtension(request.destinationPath, '.lrc');
  final snapshot = await Isolate.run(
      () => _readLyrics(original, destination, overwrite: request.overwrite));
  final response = jsonDecode(await transform(
          snapshot.text, request.startSeconds, request.endSeconds))
      as Map<String, dynamic>;
  final text = response['text'];
  if (text is! String) {
    throw const AudioTrimException('lyrics', '无法读取或调整独立歌词，请检查歌词文件。');
  }
  final unsupported = response['warning'] != null && response['warning'] != '';
  final changed =
      !unsupported && response['adjusted'] == true && text != snapshot.text;
  final output = changed
      ? await Isolate.run(() => _encodeLyrics(text, snapshot.encoding))
      : snapshot.bytes;
  if (output.length > _maxLyricBytes * 2) {
    throw const AudioTrimException('lyrics', '独立歌词文件过大，暂不能安全裁剪。');
  }
  final work =
      await Directory(p.dirname(destination)).createTemp('.dan-player-lyrics-');
  try {
    await File(p.join(work.path, 'adjusted.lrc'))
        .writeAsBytes(output, flush: true);
    return PreparedTrimLyrics._(
        source: original,
        destination: destination,
        overwrite: request.overwrite,
        unsupported: unsupported,
        originalHash: snapshot.hash,
        outputHash: await Isolate.run(() => _hash(output)),
        work: work);
  } catch (_) {
    try {
      await File(p.join(work.path, 'adjusted.lrc')).delete();
    } catch (_) {}
    try {
      await work.delete();
    } catch (_) {}
    rethrow;
  }
}

class _LyricSnapshot {
  _LyricSnapshot(this.bytes, this.text, this.encoding, this.hash);
  final Uint8List bytes;
  final String text;
  final int encoding; // 0=UTF8, 1=UTF8 BOM, 2=UTF16LE BOM, 3=UTF16BE BOM.
  final String hash;
}

_LyricSnapshot _readLyrics(String source, String destination,
    {required bool overwrite}) {
  final files = _WindowsLyricFiles();
  try {
    files.plainPath(source);
    files.plainPath(destination, allowMissing: !overwrite);
    if (!overwrite && File(destination).existsSync()) {
      throw const AudioTrimException('lyrics', '目标歌词文件已存在，请换一个文件名保存副本。');
    }
    return files.guard(source, () {
      final file = File(source);
      if (file.lengthSync() > _maxLyricBytes) {
        throw const AudioTrimException('lyrics', '独立歌词文件过大，暂不能安全裁剪。');
      }
      final bytes = file.readAsBytesSync();
      if (bytes.length > _maxLyricBytes) {
        throw const AudioTrimException('lyrics', '独立歌词文件过大，暂不能安全裁剪。');
      }
      try {
        final text = decodeLyricText(bytes);
        // String.fromCharCodes accepts lone UTF-16 surrogates; passing those
        // through Rust's UTF-8 bridge would silently change original lyrics.
        for (var i = 0; i < text.length; i++) {
          final code = text.codeUnitAt(i);
          if (code >= 0xd800 && code <= 0xdbff) {
            if (++i >= text.length ||
                text.codeUnitAt(i) < 0xdc00 ||
                text.codeUnitAt(i) > 0xdfff) {
              throw const FormatException('Invalid surrogate');
            }
          } else if (code >= 0xdc00 && code <= 0xdfff) {
            throw const FormatException('Invalid surrogate');
          }
        }
        final encoding =
            bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe
                ? 2
                : bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff
                    ? 3
                    : bytes.length >= 3 &&
                            bytes[0] == 0xef &&
                            bytes[1] == 0xbb &&
                            bytes[2] == 0xbf
                        ? 1
                        : 0;
        return _LyricSnapshot(bytes, text, encoding, _hash(bytes));
      } on FormatException {
        throw const AudioTrimException('lyrics', '无法读取或调整独立歌词，请检查歌词文件。');
      }
    });
  } finally {
    files.close();
  }
}

Uint8List _encodeLyrics(String text, int encoding) {
  if (encoding < 2) {
    return Uint8List.fromList([
      if (encoding == 1) ...[0xef, 0xbb, 0xbf],
      ...utf8.encode(text),
    ]);
  }
  final units = text.codeUnits;
  final bytes = Uint8List(units.length * 2 + 2);
  bytes[0] = encoding == 2 ? 0xff : 0xfe;
  bytes[1] = encoding == 2 ? 0xfe : 0xff;
  for (var i = 0; i < units.length; i++) {
    bytes[i * 2 + 2] = encoding == 2 ? units[i] & 0xff : units[i] >> 8;
    bytes[i * 2 + 3] = encoding == 2 ? units[i] >> 8 : units[i] & 0xff;
  }
  return bytes;
}

void _commitLyrics(String source, String destination, String staged,
    String backup, bool overwrite, String originalHash, String outputHash) {
  final files = _WindowsLyricFiles();
  try {
    for (final file in [source, staged]) {
      files.plainPath(file);
    }
    files.plainPath(destination, allowMissing: !overwrite);
    files.guard(source, () {
      if (_hash(File(source).readAsBytesSync()) != originalHash) {
        throw const AudioTrimException('lyrics', '独立歌词已发生变化，请重新打开裁剪窗口。');
      }
      files.guard(staged, () {
        if (_hash(File(staged).readAsBytesSync()) != outputHash) {
          throw const AudioTrimException('lyrics', '独立歌词校验失败，歌曲尚未被修改。');
        }
      });
      if (overwrite) {
        if (File(backup).existsSync()) {
          throw const FileSystemException('Lyric backup already exists');
        }
        // ReplaceFileW opens its private replacement with sharing disabled.
        // Release that handle; keep the user's destination write-guarded.
        files.replace(destination, staged, backup);
      } else {
        files.moveNew(staged, destination);
      }
    });
  } finally {
    files.close();
  }
}

void _rollbackLyrics(String destination, String backup, bool overwrite,
    String originalHash, String outputHash) {
  final files = _WindowsLyricFiles();
  try {
    files.plainPath(destination, allowMissing: true);
    if (!File(destination).existsSync()) {
      if (overwrite) {
        files.guard(backup, () {
          if (_hash(File(backup).readAsBytesSync()) != originalHash) {
            throw const FileSystemException('Lyric backup changed');
          }
          files.moveNew(backup, destination);
        });
      }
      return;
    }
    files.guard(destination, () {
      final currentHash = _hash(File(destination).readAsBytesSync());
      if (overwrite && currentHash == originalHash) return;
      if (currentHash != outputHash) {
        throw const FileSystemException('Published lyrics changed');
      }
      if (overwrite) {
        files.plainPath(backup);
        files.guard(backup, () {
          if (_hash(File(backup).readAsBytesSync()) != originalHash) {
            throw const FileSystemException('Lyric backup changed');
          }
        });
        files.replace(destination, backup, null);
      } else {
        files.delete(destination);
      }
    });
  } finally {
    files.close();
  }
}

void _deleteVerifiedFile(String file, String hash) {
  final files = _WindowsLyricFiles();
  try {
    files.plainPath(file);
    files.guard(file, () {
      if (_hash(File(file).readAsBytesSync()) != hash) {
        throw const FileSystemException('Recovery file changed');
      }
      files.delete(file);
    });
  } finally {
    files.close();
  }
}

/// Deny write access while validating hashes and publishing/rolling back. The
/// delete-sharing flag allows atomic rename while these read handles are held.
class _WindowsLyricFiles {
  _WindowsLyricFiles() {
    if (!Platform.isWindows) {
      throw const AudioTrimException('lyrics', '当前平台暂不支持安全保存独立歌词。');
    }
  }
  late final _kernel = ffi.DynamicLibrary.open('kernel32.dll');
  late final _information = _kernel.lookupFunction<
      ffi.Int32 Function(
          ffi.IntPtr, ffi.Int32, ffi.Pointer<ffi.Void>, ffi.Uint32),
      int Function(int, int, ffi.Pointer<ffi.Void>,
          int)>('GetFileInformationByHandleEx');
  late final _attributes = _kernel.lookupFunction<
      ffi.Uint32 Function(ffi.Pointer<Utf16>),
      int Function(ffi.Pointer<Utf16>)>('GetFileAttributesW');
  late final _open = _kernel.lookupFunction<
      ffi.IntPtr Function(ffi.Pointer<Utf16>, ffi.Uint32, ffi.Uint32,
          ffi.Pointer<ffi.Void>, ffi.Uint32, ffi.Uint32, ffi.IntPtr),
      int Function(ffi.Pointer<Utf16>, int, int, ffi.Pointer<ffi.Void>, int,
          int, int)>('CreateFileW');
  late final _close =
      _kernel.lookupFunction<ffi.Int32 Function(ffi.IntPtr), int Function(int)>(
          'CloseHandle');
  late final _move = _kernel.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>, ffi.Uint32),
      int Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>, int)>('MoveFileExW');
  late final _replace = _kernel.lookupFunction<
      ffi.Int32 Function(
          ffi.Pointer<Utf16>,
          ffi.Pointer<Utf16>,
          ffi.Pointer<Utf16>,
          ffi.Uint32,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Void>),
      int Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>, ffi.Pointer<Utf16>,
          int, ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>)>('ReplaceFileW');
  late final _delete = _kernel.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<Utf16>),
      int Function(ffi.Pointer<Utf16>)>('DeleteFileW');

  void plainPath(String file, {bool allowMissing = false}) {
    if (!p.isAbsolute(file)) {
      throw const AudioTrimException('lyrics', '请选择有效的保存位置和文件名');
    }
    var current = p.normalize(file);
    var first = true;
    while (true) {
      final pointer = current.toNativeUtf16();
      try {
        final attributes = _attributes(pointer);
        if (attributes == 0xffffffff) {
          if (!first || !allowMissing) {
            throw const AudioTrimException('lyrics', '无法读取或调整独立歌词，请检查歌词文件。');
          }
        } else if ((attributes & 0x400) != 0 && _nameSurrogate(current)) {
          throw const AudioTrimException('lyrics', '不支持通过符号链接或目录联接修改独立歌词。');
        }
      } finally {
        calloc.free(pointer);
      }
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
      first = false;
    }
  }

  bool _nameSurrogate(String path) {
    final pointer = path.toNativeUtf16();
    // FILE_FLAG_BACKUP_SEMANTICS also permits checking ancestor directories.
    final handle = _open(pointer, 0x80, 0x7, ffi.nullptr, 3, 0x02200000, 0);
    calloc.free(pointer);
    if (handle == -1) {
      throw const AudioTrimException('lyrics', '无法读取或调整独立歌词，请检查歌词文件。');
    }
    final info = calloc<ffi.Uint32>(2);
    try {
      if (_information(handle, 9, info.cast(), 8) == 0) {
        throw const AudioTrimException('lyrics', '无法读取或调整独立歌词，请检查歌词文件。');
      }
      // Name-surrogate tags redirect path lookup. Cloud placeholders are
      // reparse points too, but have no such bit and remain valid inputs.
      return (info[1] & 0x20000000) != 0;
    } finally {
      calloc.free(info);
      _close(handle);
    }
  }

  T guard<T>(String path, T Function() operation) {
    final pointer = path.toNativeUtf16();
    final handle =
        _open(pointer, 0x80000000, 0x5, ffi.nullptr, 3, 0x00200000, 0);
    calloc.free(pointer);
    if (handle == -1) {
      throw const AudioTrimException('lyrics', '独立歌词被占用或无法读取，请稍后重试。');
    }
    try {
      return operation();
    } finally {
      _close(handle);
    }
  }

  void moveNew(String source, String destination) {
    final before = source.toNativeUtf16();
    final after = destination.toNativeUtf16();
    try {
      if (_move(before, after, 8) == 0) {
        throw const AudioTrimException('lyrics', '无法安全保存独立歌词，请检查目标是否已存在或被占用。');
      }
    } finally {
      calloc.free(before);
      calloc.free(after);
    }
  }

  void replace(String destination, String source, String? backup) {
    final target = destination.toNativeUtf16();
    final input = source.toNativeUtf16();
    final recovery = backup?.toNativeUtf16() ?? ffi.nullptr;
    try {
      if (_replace(target, input, recovery, 0, ffi.nullptr, ffi.nullptr) == 0) {
        throw const AudioTrimException('lyrics', '无法安全保存独立歌词，请检查目标是否已存在或被占用。');
      }
    } finally {
      calloc.free(target);
      calloc.free(input);
      if (backup != null) calloc.free(recovery);
    }
  }

  void delete(String file) {
    final pointer = file.toNativeUtf16();
    try {
      if (_delete(pointer) == 0) {
        throw const FileSystemException('Cannot remove owned lyric file');
      }
    } finally {
      calloc.free(pointer);
    }
  }

  void close() => _kernel.close();
}
