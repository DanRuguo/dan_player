import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dan_player/library/audio_library.dart';
import 'package:path/path.dart' as p;

const m3uMaxBytes = 2 * 1024 * 1024;
const m3uMaxEntries = 20000;
final _windows = p.Context(style: p.Style.windows);

class M3uEntry {
  const M3uEntry(this.path, {this.title = '', this.duration = 0});
  final String path;
  final String title;
  final int duration;
}

class M3uDocument {
  const M3uDocument(this.entries, {this.skipped = 0});
  final List<M3uEntry> entries;
  final int skipped;
}

/// M3U is a list of references. Reading it never opens or fetches the songs.
/// Retain order, repeated recordings and unavailable local-file references.
M3uDocument parseM3u(String text, {required String playlistPath}) {
  if (utf8.encode(text).length > m3uMaxBytes) {
    throw const FormatException('歌单文件超过 2 MiB，无法导入。');
  }
  final entries = <M3uEntry>[];
  var skipped = 0;
  var title = '';
  var duration = 0;
  for (final raw
      in const LineSplitter().convert(text.replaceFirst('\uFEFF', ''))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.toUpperCase().startsWith('#EXT-X-')) {
      throw const FormatException('此文件是 HLS 流媒体清单，不能作为本地歌单导入。');
    }
    if (line.toUpperCase().startsWith('#EXTINF:')) {
      final comma = line.indexOf(',');
      if (comma >= 0) {
        duration = int.tryParse(line.substring(8, comma).split(' ').first) ?? 0;
        title = line.substring(comma + 1).trim();
      }
      continue;
    }
    if (line.startsWith('#')) continue;
    final resolved = _localPath(line, playlistPath: playlistPath);
    if (resolved == null) {
      skipped++;
    } else {
      if (entries.length == m3uMaxEntries) {
        throw const FormatException('歌单超过 20000 条，请拆分后导入。');
      }
      entries.add(M3uEntry(resolved,
          title: title, duration: duration > 0 ? duration : 0));
    }
    title = '';
    duration = 0;
  }
  return M3uDocument(List.unmodifiable(entries), skipped: skipped);
}

/// Matches the encoder's supported local references, without probing a file.
/// A standalone export has no base for drive-relative or relative audio paths.
bool isM3uLocalAudioPath(String path) => _localPath(path) != null;

String? _localPath(String value, {String? playlistPath}) {
  final controls = RegExp(r'[\x00-\x1f\x7f]');
  if (value.contains(controls)) return null;
  var candidate = value;
  if (candidate.toLowerCase().startsWith('file:')) {
    try {
      candidate = Uri.parse(candidate).toFilePath(windows: true);
    } on FormatException {
      return null;
    } on UnsupportedError {
      return null;
    }
  } else if (RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false)
          .hasMatch(candidate) &&
      !RegExp(r'^[a-z]:[/\\]', caseSensitive: false).hasMatch(candidate)) {
    return null;
  }
  // URI escapes must not introduce a newline, NUL or other control character.
  if (candidate.contains(controls)) return null;
  // path's Windows style treats // as drive-root-relative, not as a UNC root.
  // Normalize separators first, including file://server/share conversions.
  candidate = candidate.replaceAll('/', '\\');
  if (playlistPath != null) {
    final base = _windows.dirname(playlistPath.replaceAll('/', '\\'));
    // join binds \Music\song.mp3 to the playlist's drive/share, while a fully
    // absolute path or a different drive still replaces the base correctly.
    candidate = _windows.join(base, candidate);
  }
  candidate = _windows.normalize(candidate);
  if (candidate.startsWith(r'\\.\') ||
      candidate.toUpperCase().startsWith(r'\\?\GLOBALROOT')) {
    return null;
  }
  if (!_windows.isAbsolute(candidate) ||
      _windows.isRootRelative(candidate) ||
      !_audioExtensions.contains(_windows.extension(candidate).toLowerCase())) {
    return null;
  }
  return candidate;
}

const _audioExtensions = {
  // Keep the scanner's SUPPORT_FORMAT extensions available for interchange.
  '.mp3',
  '.mp2',
  '.mp1',
  '.flac',
  '.wav',
  '.wave',
  '.m4a',
  '.m4b',
  '.aac',
  '.adts',
  '.ogg',
  '.opus',
  '.wma',
  '.asf',
  '.ac3',
  '.amr',
  '.3ga',
  '.mpc',
  '.mid',
  '.ape',
  '.aiff',
  '.aif',
  '.aifc',
  '.alac',
  '.mp4',
  '.dsf',
  '.dff',
  '.wv',
  '.wvc',
  '.tta',
  '.mka',
};

Future<M3uDocument> readM3uFile(File file) async {
  final bytes = await file
      .openRead(0, m3uMaxBytes + 1)
      .fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk));
  if (bytes.length > m3uMaxBytes) {
    throw const FormatException('歌单文件超过 2 MiB，无法导入。');
  }
  final location = file.absolute.path;
  return Isolate.run(() {
    late final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const FormatException('请将歌单另存为 UTF-8 编码的 M3U8 文件。');
    }
    return parseM3u(text, playlistPath: location);
  });
}

/// Reuse library metadata without a scan; unknown files stay valid references
/// and use EXTINF/file names until their metadata is available in the library.
Future<List<Audio>> resolveM3uEntries(
    M3uDocument document, Iterable<Audio> library) async {
  final known = {
    for (final audio in library)
      if (audio.isLocal) _windows.normalize(audio.path).toLowerCase(): audio
  };
  final result = <Audio>[];
  for (var index = 0; index < document.entries.length; index++) {
    if (index % 256 == 0) await Future<void>.delayed(Duration.zero);
    final entry = document.entries[index];
    result.add(known[entry.path.toLowerCase()] ??
        Audio.fromMap({
          'path': entry.path,
          'title': entry.title.isEmpty
              ? _windows.basenameWithoutExtension(entry.path)
              : entry.title,
          'duration': entry.duration,
          'metadata_pending': true,
        }));
  }
  return result;
}

String encodeM3u(Iterable<M3uEntry> entries,
    {required String playlistPath, bool relative = true}) {
  final output = StringBuffer('#EXTM3U\r\n');
  var count = 0;
  for (final entry in entries) {
    final absolute = _localPath(entry.path, playlistPath: playlistPath);
    if (absolute == null) {
      throw const FormatException('歌单包含无法导出的本地文件引用，请移除不支持的项目后重试。');
    }
    if (++count > m3uMaxEntries) {
      throw const FormatException('歌单超过 20000 条，请拆分后导入。');
    }
    var reference = absolute;
    if (relative) {
      try {
        reference =
            _windows.relative(absolute, from: _windows.dirname(playlistPath));
      } on p.PathException {
        reference = absolute;
      }
    }
    // Keep an absolute UNC reference unambiguous to Windows M3U consumers.
    if (!reference.startsWith(r'\\')) {
      reference = reference.replaceAll('\\', '/');
    }
    if (reference.startsWith('#')) reference = './$reference';
    final label = entry.title.replaceAll(RegExp(r'[\x00-\x1f]'), ' ').trim();
    output.writeln(
        '#EXTINF:${entry.duration > 0 ? entry.duration : -1},$label\r');
    output.writeln('$reference\r');
    if (output.length > m3uMaxBytes) {
      throw const FormatException('歌单文件超过 2 MiB，无法导入。');
    }
  }
  final text = output.toString();
  if (utf8.encode(text).length > m3uMaxBytes) {
    throw const FormatException('歌单文件超过 2 MiB，无法导入。');
  }
  return text;
}

Future<void> writeM3uFile(File destination, List<M3uEntry> entries,
    {bool relative = true}) async {
  final location = destination.absolute.path;
  final text = await Isolate.run(
      () => encodeM3u(entries, playlistPath: location, relative: relative));
  final temporary =
      File('$location.${DateTime.now().microsecondsSinceEpoch}.tmp');
  try {
    await temporary.writeAsString(text, encoding: utf8, flush: true);
    await temporary.rename(location);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
