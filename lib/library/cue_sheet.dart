import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'audio_library.dart';
import 'cue_track.dart';
import 'playlist_exchange.dart';

const cueMaxBytes = 1024 * 1024;

class CueEntry {
  const CueEntry(this.reference,
      {required this.title,
      required this.artist,
      required this.album,
      required this.albumArtist,
      this.composer});
  final CueTrackReference reference;
  final String title, artist, album, albumArtist;
  final String? composer;
}

class CueDocument {
  const CueDocument(this.entries, this.title);
  final List<CueEntry> entries;
  final String title;
}

class _PendingTrack {
  _PendingTrack(this.file, this.number);
  final String file;
  final int number;
  int? start;
  String title = '', artist = '';
  String? composer;
}

/// External, audio-only CUE sheets. INDEX 01 defines audible boundaries;
/// embedded INDEX 00 remains in the preceding track. PREGAP/POSTGAP does not
/// synthesize additional samples. Never guess another source by basename.
CueDocument parseCue(String text, {required String cuePath}) {
  if (utf8.encode(text).length > cueMaxBytes) {
    throw const FormatException('CUE 文件超过 1 MiB，无法导入。');
  }
  if (!p.windows.isAbsolute(cuePath)) {
    throw const FormatException('CUE 文件位置必须为绝对路径。');
  }
  String album = '', artist = '';
  String? composer, source;
  _PendingTrack? current;
  final tracks = <_PendingTrack>[];
  final numbers = <int>{};
  final usedFiles = <String>{};
  for (final raw
      in const LineSplitter().convert(text.replaceFirst('\uFEFF', ''))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final split = line.indexOf(RegExp(r'\s'));
    final command = (split < 0 ? line : line.substring(0, split)).toUpperCase();
    final value = split < 0 ? '' : line.substring(split).trim();
    String tag() =>
        value.startsWith('"') && value.endsWith('"') && value.length >= 2
            ? value.substring(1, value.length - 1)
            : value;
    switch (command) {
      case 'FILE':
        final match =
            RegExp(r'^(?:"([^"]+)"|(\S+))\s+(\S+)$').firstMatch(value);
        if (match == null ||
            match[3]!.toUpperCase() == 'BINARY' ||
            match[3]!.toUpperCase() == 'MOTOROLA') {
          throw const FormatException('CUE 只支持本地音频文件，不支持数据光盘映像。');
        }
        final name = match[1] ?? match[2]!;
        if (name.contains(RegExp(r'[\x00-\x1f]')) ||
            (!p.windows.isAbsolute(name) && name.contains(':'))) {
          throw const FormatException('CUE 音频文件路径无效。');
        }
        source = p.windows.normalize(p.windows.isAbsolute(name)
            ? name
            : p.windows.join(p.windows.dirname(cuePath), name));
        if (!isM3uLocalAudioPath(source) ||
            !usedFiles.add(source.toLowerCase())) {
          throw const FormatException('CUE 音频格式或重复 FILE 段不受支持。');
        }
        current = null;
      case 'TRACK':
        final match = RegExp(r'^(\d{1,2})\s+AUDIO$', caseSensitive: false)
            .firstMatch(value);
        final number = match == null ? null : int.tryParse(match[1]!);
        if (source == null ||
            number == null ||
            number < 1 ||
            !numbers.add(number)) {
          throw const FormatException('CUE 曲目编号无效、重复或包含非音频曲目。');
        }
        current = _PendingTrack(source, number);
        tracks.add(current);
      case 'INDEX':
        final match =
            RegExp(r'^(\d{2})\s+(\d{1,4}):(\d{2}):(\d{2})$').firstMatch(value);
        if (current == null || match == null) {
          throw const FormatException('CUE INDEX 时间格式无效。');
        }
        final second = int.parse(match[3]!);
        final frame = int.parse(match[4]!);
        if (second >= 60 || frame >= 75) {
          throw const FormatException('CUE INDEX 时间格式无效。');
        }
        if (match[1] == '01') {
          if (current.start != null) {
            throw const FormatException('CUE 曲目包含重复 INDEX 01。');
          }
          current.start = (int.parse(match[2]!) * 60 + second) * 75 + frame;
        }
      case 'TITLE':
        if (current == null) {
          album = tag();
        } else {
          current.title = tag();
        }
      case 'PERFORMER':
        if (current == null) {
          artist = tag();
        } else {
          current.artist = tag();
        }
      case 'SONGWRITER':
        if (current == null) {
          composer = tag();
        } else {
          current.composer = tag();
        }
    }
  }
  if (tracks.isEmpty) throw const FormatException('CUE 中没有音频分轨。');
  final entries = <CueEntry>[];
  for (var i = 0; i < tracks.length; i++) {
    final track = tracks[i];
    final start = track.start;
    final next = i + 1 < tracks.length && tracks[i + 1].file == track.file
        ? tracks[i + 1]
        : null;
    if (start == null ||
        (next != null && (next.start == null || next.start! <= start))) {
      throw const FormatException('CUE 缺少 INDEX 01，或同文件分轨时间未递增。');
    }
    entries.add(CueEntry(
        CueTrackReference(
            cuePath: cuePath,
            sourcePath: track.file,
            number: track.number,
            startFrame: start,
            endFrame: next?.start),
        title: track.title.isEmpty
            ? 'Track ${track.number.toString().padLeft(2, '0')}'
            : track.title,
        artist: track.artist.isEmpty ? artist : track.artist,
        album: album,
        albumArtist: artist,
        composer: track.composer ?? composer));
  }
  return CueDocument(List.unmodifiable(entries),
      album.isEmpty ? p.windows.basenameWithoutExtension(cuePath) : album);
}

/// UTF-8, BOM-marked UTF-16 and Windows GB18030 (including GBK/GB2312).
String decodeCueText(List<int> bytes) {
  if (bytes.length >= 2 &&
      ((bytes[0] == 255 && bytes[1] == 254) ||
          (bytes[0] == 254 && bytes[1] == 255))) {
    if (bytes.length.isOdd) {
      throw const FormatException('CUE 文本编码无效，请转换为 UTF-8。');
    }
    final le = bytes[0] == 255;
    return String.fromCharCodes([
      for (var i = 2; i < bytes.length; i += 2)
        le ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1]
    ]);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    if (!Platform.isWindows) rethrow;
    final kernel = DynamicLibrary.open('kernel32.dll');
    final convert = kernel.lookupFunction<
        Int32 Function(
            Uint32, Uint32, Pointer<Uint8>, Int32, Pointer<Uint16>, Int32),
        int Function(int, int, Pointer<Uint8>, int, Pointer<Uint16>,
            int)>('MultiByteToWideChar');
    final input = calloc<Uint8>(bytes.length);
    Pointer<Uint16>? output;
    try {
      input.asTypedList(bytes.length).setAll(0, bytes);
      final count = convert(54936, 8, input, bytes.length, nullptr, 0);
      if (count == 0) throw const FormatException('CUE 文本编码无效，请转换为 UTF-8。');
      output = calloc<Uint16>(count);
      if (convert(54936, 8, input, bytes.length, output, count) != count) {
        throw const FormatException('CUE 文本编码无效，请转换为 UTF-8。');
      }
      return String.fromCharCodes(output.asTypedList(count));
    } finally {
      calloc.free(input);
      if (output != null) calloc.free(output);
      kernel.close();
    }
  }
}

Future<CueDocument> readCueFile(File file) async {
  final handle = await file.open();
  late final List<int> bytes;
  try {
    bytes = await handle.read(cueMaxBytes + 1);
  } finally {
    await handle.close();
  }
  if (bytes.length > cueMaxBytes) {
    throw const FormatException('CUE 文件超过 1 MiB，无法导入。');
  }
  final location = file.absolute.path;
  return Isolate.run(() => parseCue(decodeCueText(bytes), cuePath: location));
}

Future<List<Audio>> resolveCueEntries(
    CueDocument document, List<Audio> library) async {
  final indexed = {
    for (final audio in library.where((a) => a.isLocal && !a.isCueTrack))
      p.windows.normalize(audio.path).toLowerCase(): audio
  };
  final checked = <String, FileStat>{};
  final audios = <Audio>[];
  for (final entry in document.entries) {
    final ref = entry.reference;
    final key = p.windows.normalize(ref.sourcePath).toLowerCase();
    final stat = checked[key] ??= await File(ref.sourcePath).stat();
    if (stat.type != FileSystemEntityType.file) {
      throw const FormatException('CUE 引用的音频文件不存在或无法读取。');
    }
    final original = indexed[key];
    final end = ref.endSeconds ?? original?.duration.toDouble();
    final duration = end != null && end > ref.startSeconds
        ? (end - ref.startSeconds).floor()
        : 0;
    audios.add(Audio(
        entry.title,
        entry.artist.isEmpty ? original?.artist ?? 'UNKNOWN' : entry.artist,
        entry.album.isEmpty ? original?.album ?? document.title : entry.album,
        ref.number,
        duration,
        original?.bitrate,
        original?.sampleRate,
        ref.identity,
        stat.modified.millisecondsSinceEpoch ~/ 1000,
        stat.changed.millisecondsSinceEpoch ~/ 1000,
        'CUE',
        cueTrack: ref,
        albumArtist: entry.albumArtist.isEmpty
            ? original?.albumArtist
            : entry.albumArtist,
        composer: entry.composer ?? original?.composer,
        fileSizeBytes: stat.size,
        modifiedNanos: '${stat.modified.microsecondsSinceEpoch * 1000}'));
  }
  return List.unmodifiable(audios);
}
