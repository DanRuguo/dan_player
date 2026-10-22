import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist_text_encoding.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

const m3uMaxBytes = 2 * 1024 * 1024;
const m3uMaxEntries = 20000;
final _windows = p.Context(style: p.Style.windows);

class M3uEntry {
  const M3uEntry(this.path,
      {this.title = '',
      this.duration = 0,
      this.artist = '',
      this.album = '',
      this.track = 0});
  final String path;
  final String title;
  final int duration;
  final String artist, album;
  final int track;
}

class M3uDocument {
  const M3uDocument(this.entries, {this.skipped = 0, this.sourceFingerprint});
  final List<M3uEntry> entries;
  final int skipped;
  final String? sourceFingerprint;
}

void _checkPlaylistSize(String text) {
  if (utf8.encode(text).length > m3uMaxBytes) {
    throw const FormatException('歌单文件超过 2 MiB，无法导入。');
  }
}

/// PLS numbers define order, even when metadata precedes FileN or physical
/// lines are shuffled. Repeated recordings at different numbers are retained.
M3uDocument parsePls(String text, {required String playlistPath}) {
  _checkPlaylistSize(text);
  final records = <int, Map<String, String>>{};
  var inPlaylist = false, foundPlaylist = false;
  for (final raw
      in const LineSplitter().convert(text.replaceFirst('\uFEFF', ''))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) continue;
    if (line.startsWith('[')) {
      inPlaylist = line.toLowerCase() == '[playlist]';
      foundPlaylist |= inPlaylist;
      continue;
    }
    if (!inPlaylist) continue;
    final equals = line.indexOf('=');
    if (equals < 0) continue;
    final key = line.substring(0, equals).trim().toLowerCase();
    final value = line.substring(equals + 1).trim();
    final match = RegExp(r'^(file|title|length)(\d+)$').firstMatch(key);
    if (match == null) {
      if (key == 'numberofentries') {
        final count = int.tryParse(value);
        if (count == null || count < 0)
          throw const FormatException('PLS 歌单格式无效。');
        if (count > m3uMaxEntries)
          throw const FormatException('歌单超过 20000 条，请拆分后导入。');
      }
      continue;
    }
    final index = int.tryParse(match.group(2)!);
    if (index == null || index > m3uMaxEntries)
      throw const FormatException('歌单超过 20000 条，请拆分后导入。');
    if (index < 1) throw const FormatException('PLS 歌单格式无效。');
    (records[index] ??= {})[match.group(1)!] = value;
  }
  if (!foundPlaylist) throw const FormatException('PLS 歌单格式无效。');
  final entries = <M3uEntry>[];
  var skipped = 0;
  for (final index in records.keys.toList()..sort()) {
    final record = records[index]!;
    final path =
        _interchangePath(record['file'] ?? '', playlistPath: playlistPath);
    if (path == null) {
      skipped++;
      continue;
    }
    final duration = int.tryParse(record['length'] ?? '') ?? 0;
    entries.add(M3uEntry(path,
        title: record['title'] ?? '', duration: duration > 0 ? duration : 0));
  }
  return M3uDocument(List.unmodifiable(entries), skipped: skipped);
}

const _xspfNamespace = 'http://xspf.org/ns/0/';
const _xmlBaseNamespace = 'http://www.w3.org/XML/1998/namespace';
const _xspfError = FormatException('XSPF 歌单格式无效或包含不支持的 XML 结构。');

bool _xmlScalar(int value) =>
    value == 9 ||
    value == 10 ||
    value == 13 ||
    (value >= 0x20 && value <= 0xd7ff) ||
    (value >= 0xe000 && value <= 0xfffd) ||
    (value >= 0x10000 && value <= 0x10ffff);

/// Standard XML escapes remain usable in filenames. Custom/unknown entities,
/// malformed references and illegal numeric characters are never substituted.
class _PlaylistEntities extends XmlDefaultEntityMapping {
  const _PlaylistEntities() : super.xml();
  @override
  String decode(String input) {
    final output = StringBuffer();
    var start = 0;
    while (true) {
      final amp = input.indexOf('&', start);
      if (amp < 0) {
        output.write(input.substring(start));
        break;
      }
      output.write(input.substring(start, amp));
      final end = input.indexOf(';', amp + 1);
      if (end < 0 || end - amp > 16) throw _xspfError;
      final name = input.substring(amp + 1, end);
      if (!RegExp(r'^(amp|lt|gt|apos|quot|#[0-9]+|#x[0-9a-fA-F]+)$')
          .hasMatch(name)) throw _xspfError;
      final decoded = super.decodeEntity(name);
      if (decoded == null || !decoded.runes.every(_xmlScalar)) throw _xspfError;
      output.write(decoded);
      start = end + 1;
    }
    return output.toString();
  }
}

/// XSPF is parsed as bounded XML, never as a collection of matching descendant
/// names: vendor extensions cannot inject tracks or alternate metadata.
M3uDocument parseXspf(String text, {required String playlistPath}) {
  _checkPlaylistSize(text);
  text = text.replaceFirst('\uFEFF', '');
  if (!text.runes.every(_xmlScalar)) throw _xspfError;
  try {
    const entities = _PlaylistEntities();
    var depth = 0, nodes = 0;
    for (final event in parseEvents(text,
        entityMapping: entities,
        validateDocument: true,
        validateNesting: true)) {
      if (++nodes > 300000 || event is XmlDoctypeEvent) throw _xspfError;
      if (event is XmlStartElementEvent) {
        nodes += event.attributes.length;
        if (event.attributes.length > 64 ||
            depth >= 32 ||
            event.attributes.map((a) => a.name).toSet().length !=
                event.attributes.length) throw _xspfError;
        if (!event.isSelfClosing) depth++;
      } else if (event is XmlEndElementEvent) {
        depth--;
      }
    }
    final root = XmlDocument.parse(text, entityMapping: entities).rootElement;
    if (root.name.local != 'playlist' ||
        root.name.namespaceUri != _xspfNamespace ||
        !{'0', '1'}.contains(root.getAttribute('version'))) throw _xspfError;
    final lists = _xspfChildren(root, 'trackList').toList();
    if (lists.length != 1) throw _xspfError;
    final rootBase = _xspfBase(root, Uri.file(playlistPath, windows: true));
    final listBase = _xspfBase(lists.single, rootBase);
    final entries = <M3uEntry>[];
    var skipped = 0, count = 0;
    for (final track in _xspfChildren(lists.single, 'track')) {
      if (++count > m3uMaxEntries)
        throw const FormatException('歌单超过 20000 条，请拆分后导入。');
      final trackBase = _xspfBase(track, listBase);
      String? path;
      for (final location in _xspfChildren(track, 'location')) {
        final uri =
            _xspfUri(_xspfText(location), _xspfBase(location, trackBase));
        if (uri == null ||
            uri.scheme != 'file' ||
            uri.hasQuery ||
            uri.hasFragment) continue;
        path = _interchangePath(uri.toString());
        if (path != null) break;
      }
      if (path == null) {
        skipped++;
        continue;
      }
      String field(String name) {
        final values = _xspfChildren(track, name).toList();
        if (values.length > 1) throw _xspfError;
        return values.isEmpty ? '' : _xspfText(values.single);
      }

      final duration = int.tryParse(field('duration')) ?? 0;
      final number = int.tryParse(field('trackNum')) ?? 0;
      entries.add(M3uEntry(path,
          title: field('title'),
          artist: field('creator'),
          album: field('album'),
          duration: duration > 0 ? duration ~/ 1000 : 0,
          track: number > 0 ? number : 0));
    }
    return M3uDocument(List.unmodifiable(entries), skipped: skipped);
  } on XmlException {
    throw _xspfError;
  }
}

Iterable<XmlElement> _xspfChildren(XmlElement parent, String name) =>
    parent.childElements.where((node) =>
        node.name.local == name && node.name.namespaceUri == _xspfNamespace);

String _xspfText(XmlElement node) {
  if (node.childElements.isNotEmpty) throw _xspfError;
  return node.innerText.trim();
}

Uri? _xspfBase(XmlElement node, Uri? parent) {
  // xml is predefined by XML Namespaces; xml 6.x only resolves explicitly
  // declared prefixes, so the ordinary xml:base spelling needs this lookup.
  final base = node.getAttribute('xml:base') ??
      node.getAttribute('base', namespace: _xmlBaseNamespace);
  return base == null ? parent : _xspfUri(base, parent, allowEmpty: true);
}

Uri? _xspfUri(String value, Uri? base, {bool allowEmpty = false}) {
  if ((!allowEmpty && value.isEmpty) ||
      value.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
      RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(value)) return null;
  try {
    // Strawberry also writes percent-escaped native drive paths. Decode only
    // this path case, then re-encode as a file URI before resolving descendants.
    // decodeComponent expects ASCII URI text. Decode escaped byte runs only,
    // so exporters that leave IRI Unicode literal can mix it with %20/%25.
    final decoded = value.replaceAllMapped(RegExp(r'(?:%[0-9a-fA-F]{2})+'),
        (match) => Uri.decodeComponent(match[0]!));
    if (RegExp(r'^[a-z]:[/\\]', caseSensitive: false).hasMatch(decoded) ||
        decoded.startsWith(r'\\')) return Uri.file(decoded, windows: true);
    final reference = Uri.parse(value);
    final result =
        reference.hasScheme ? reference : base?.resolveUri(reference);
    return result == null || result.hasQuery || result.hasFragment
        ? null
        : result;
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

String? _interchangePath(String value, {String? playlistPath}) {
  if (value.isEmpty) return null;
  final resolved = _localPath(value, playlistPath: playlistPath);
  if (resolved == null ||
      resolved.startsWith(r'\\?\') ||
      resolved.contains(RegExp(r'[<>"|?*]')) ||
      resolved
          .substring(RegExp(r'^[a-z]:', caseSensitive: false).hasMatch(resolved)
              ? 2
              : 0)
          .contains(':')) return null;
  return resolved;
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

Future<List<int>> _readPlaylistBytes(File file) async {
  final bytes = await file
      .openRead(0, m3uMaxBytes + 1)
      .fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk));
  if (bytes.length > m3uMaxBytes) {
    throw const FormatException('歌单文件超过 2 MiB，无法导入。');
  }
  return bytes;
}

Future<String> readPlaylistSourceFingerprint(File file) async =>
    sha256.convert(await _readPlaylistBytes(file)).toString();

Future<M3uDocument> readM3uFile(File file) =>
    _readPlaylist(file, m3uOnly: true);

Future<M3uDocument> readLocalPlaylistFile(File file) => _readPlaylist(file);

Future<M3uDocument> _readPlaylist(File file, {bool m3uOnly = false}) async {
  final bytes = await _readPlaylistBytes(file);
  final location = file.absolute.path;
  return Isolate.run(() {
    final text = m3uOnly
        ? decodeM3uText(bytes, playlistPath: location)
        : decodeLocalPlaylistText(bytes, playlistPath: location);
    final M3uDocument document;
    switch (m3uOnly ? '.m3u' : _windows.extension(location).toLowerCase()) {
      case '.m3u':
      case '.m3u8':
        document = parseM3u(text, playlistPath: location);
      case '.pls':
        document = parsePls(text, playlistPath: location);
      case '.xspf':
        document = parseXspf(text, playlistPath: location);
      default:
        throw const FormatException('请选择 M3U、M3U8、PLS 或 XSPF 歌单。');
    }
    return M3uDocument(document.entries,
        skipped: document.skipped,
        sourceFingerprint: sha256.convert(bytes).toString());
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
          if (entry.artist.isNotEmpty) 'artist': entry.artist,
          if (entry.album.isNotEmpty) 'album': entry.album,
          if (entry.track > 0) 'track': entry.track,
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
