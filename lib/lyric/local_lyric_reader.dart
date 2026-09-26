import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/krc_decoder.dart';
import 'package:dan_player/lyric/local_lyric_parser.dart';
import 'package:dan_player/lyric/local_lyric_origin.dart';
import 'package:dan_player/lyric/lyric_document.dart';
export 'package:dan_player/lyric/local_lyric_origin.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:dan_player/lyric/lyric_text_codec.dart';
import 'package:dan_player/src/rust/api/tag_reader.dart';
import 'package:dan_player/utils.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';

const _sidecarExtensions = ['.qrc', '.yrc', '.krc', '.elrc', '.lrc'];
const _memoryBudget = 8 * 1024 * 1024;
final _memory = <String, _LocalLyricMemoryEntry>{};
int _memoryBytes = 0;

class _LocalLyricMemoryEntry {
  const _LocalLyricMemoryEntry(
      this.fingerprint, this.snapshot, this.origin, this.bytes);
  final String fingerprint, origin;
  final LyricSnapshot snapshot;
  final int bytes;
}

@visibleForTesting
int get localLyricMemoryCacheSize => _memory.length;

@visibleForTesting
int get localLyricMemoryCacheBytes => _memoryBytes;

@visibleForTesting
void clearLocalLyricMemoryCache() {
  _memory.clear();
  _memoryBytes = 0;
}

void _removeMemory(String key) {
  final old = _memory.remove(key);
  if (old != null) _memoryBytes -= old.bytes;
}

/// Stat every source on every read: the memory cache never validates itself
/// against stale library metadata or the persistent lyric fallback cache.
Future<String?> _sourceFingerprint(
    String audioPath, LocalLyricLineOrder order, bool Function() active) async {
  if (!active()) return null;
  try {
    final names = [
      audioPath,
      for (final extension in _sidecarExtensions) ...[
        path.setExtension(audioPath, extension),
        '${path.setExtension(audioPath, extension)}.translation.lrc',
        '${path.setExtension(audioPath, extension)}.romanization.lrc',
      ],
    ];
    final stats = await Future.wait(names.map(FileStat.stat));
    if (!active() || stats.first.type != FileSystemEntityType.file) return null;
    return jsonEncode([
      order.name,
      for (var i = 0; i < names.length; i++)
        [
          names[i],
          stats[i].type.toString(),
          stats[i].size,
          stats[i].modified.microsecondsSinceEpoch,
          stats[i].changed.microsecondsSinceEpoch,
        ],
    ]);
  } catch (_) {
    return null;
  }
}

/// All automatic local consumers share the same bounded, offline priority.
/// Whole-file lyrics must never be attached to a virtual CUE segment.
Future<Lyric?> readLocalLyric(Audio audio,
    {LocalLyricLineOrder? lineOrder,
    bool Function()? stillCurrent,
    Future<String?> Function(String)? readEmbedded,
    void Function(String)? onWarning}) async {
  if (audio.isOnline || audio.isCueTrack) return null;
  bool active() => stillCurrent?.call() ?? true;
  void warning(String message) {
    LOGGER.w('[lyric] $message');
    onWarning?.call(message);
  }

  final order = lineOrder ?? AppSettings.instance.localLyricLineOrder;
  final key = jsonEncode([audio.localFilePath, order.name]);
  final fingerprint =
      await _sourceFingerprint(audio.localFilePath, order, active);
  if (!active()) return null;
  if (fingerprint == null) {
    _removeMemory(key);
    return null;
  }
  // An injected embedded reader is an independent source without a file
  // revision contract, so it must not participate in production memory cache.
  final useMemory = readEmbedded == null;
  if (useMemory) {
    final cached = _memory[key];
    if (cached != null && cached.fingerprint == fingerprint) {
      _memory.remove(key);
      _memory[key] = cached;
      final copy = cached.snapshot.toLyric();
      markDiscoveredLocalLyric(copy, cached.origin);
      return active() ? copy : null;
    }
    _removeMemory(key);
  }
  Future<Lyric?> complete(Lyric lyric, String origin) async {
    if (!active()) return null;
    final latest = await _sourceFingerprint(audio.localFilePath, order, active);
    if (!active() || latest != fingerprint) return null;
    markDiscoveredLocalLyric(lyric, origin);
    if (useMemory) {
      final snapshot = LyricSnapshot.capture(lyric);
      final bytes = utf8.encode(jsonEncode(snapshot.toJson())).length;
      if (bytes <= _memoryBudget && active()) {
        _removeMemory(key);
        while (_memory.isNotEmpty &&
            (_memory.length >= 32 || _memoryBytes + bytes > _memoryBudget)) {
          _removeMemory(_memory.keys.first);
        }
        _memory[key] =
            _LocalLyricMemoryEntry(fingerprint, snapshot, origin, bytes);
        _memoryBytes += bytes;
      }
    }
    return active() ? lyric : null;
  }

  for (final extension in _sidecarExtensions) {
    if (!active()) return null;
    final file = File(path.setExtension(audio.localFilePath, extension));
    try {
      if (!await file.exists()) continue;
      if (!active()) return null;
      final bytes = await _readBounded(file);
      if (!active()) return null;
      final text = extension == '.krc' &&
              bytes.length >= 4 &&
              ascii.decode(bytes.take(4).toList(), allowInvalid: true) == 'krc1'
          ? decodeKrcContainer(base64Encode(bytes))
          : decodeLyricText(bytes);
      final lyric =
          parseLocalLyricText(text, extension: extension, lineOrder: order);
      if (lyric == null) {
        warning('本地歌词没有有效内容，继续尝试其他来源：${file.path}');
        continue;
      }
      await _readCompanions(file, lyric, order, active, warning);
      if (!active()) return null;
      return await complete(lyric, file.path);
    } catch (error) {
      if (!active()) return null;
      warning(extension == '.qrc'
          ? '本轮支持文本 QRC；加密或损坏的 QRC 未加载，继续尝试其他来源：$error'
          : '本地歌词读取失败，继续尝试其他来源：$error');
    }
  }
  if (!active()) return null;
  try {
    final text = await (readEmbedded ??
        (audioPath) => getLyricFromPath(path: audioPath))(audio.localFilePath);
    if (!active() || text == null) return null;
    final lyric = parseLocalLyricText(text, lineOrder: order);
    return lyric == null
        ? null
        : await complete(lyric, 'embedded:${audio.localFilePath}');
  } catch (error) {
    if (active()) warning('内嵌歌词读取失败：$error');
    return null;
  }
}

Future<List<int>> _readBounded(File file) async {
  final handle = await file.open();
  try {
    final bytes = await handle.read(LyricEditDraft.maxBytes + 1);
    if (bytes.length > LyricEditDraft.maxBytes) {
      throw const FormatException('歌词文件过大');
    }
    return bytes;
  } finally {
    await handle.close();
  }
}

Future<void> _readCompanions(File main, Lyric lyric, LocalLyricLineOrder order,
    bool Function() active, void Function(String) warning) async {
  // Explicit companion suffixes are also used by Dan's editor. A same-name
  // LRC is a translation for word formats, as documented by ZeroBit.
  final translation = [
    '${main.path}.translation.lrc',
    if (!main.path.toLowerCase().endsWith('.lrc'))
      path.setExtension(main.path, '.lrc'),
  ];
  for (final kind in [false, true]) {
    for (final name in kind ? ['${main.path}.romanization.lrc'] : translation) {
      if (!active()) return;
      try {
        final file = File(name);
        if (!await file.exists()) continue;
        final text = decodeLyricText(await _readBounded(file));
        if (!active()) return;
        final parsed = parseLocalLyricText(text, lineOrder: order);
        if (parsed == null) continue;
        final values = {for (final line in parsed.lines) line.start: line};
        var matched = false;
        for (final line in lyric.lines) {
          final auxiliaryLine = values[line.start];
          if (auxiliaryLine == null) continue;
          final value = lyricLineText(auxiliaryLine);
          if (value.trim().isEmpty) continue;
          final original = line is SyncLyricLine
              ? line.content
              : (line as UnsyncLyricLine).content.split('┃').first;
          // A parallel original-only LRC is not a translation of itself.
          if (!kind && auxiliaryLine.romanization != null) {
            line.romanization ??= auxiliaryLine.romanization;
          }
          final translated =
              auxiliaryLine is SyncLyricLine ? auxiliaryLine.translation : null;
          final auxiliary = [value, if (translated != null) translated]
              .join('┃')
              .split('┃')
              .where((item) =>
                  item.trim().isNotEmpty && item.trim() != original.trim())
              .join('┃');
          if (auxiliary.isEmpty) continue;
          matched = true;
          if (kind) {
            line.romanization ??= auxiliary;
          } else if (line is SyncLyricLine) {
            line.translation ??= auxiliary;
          } else if (line is UnsyncLyricLine && !line.content.contains('┃')) {
            line.content = '${line.content}┃$auxiliary';
          }
        }
        if (matched) break;
      } catch (error) {
        if (active()) warning('辅助歌词读取失败，保留原文：$error');
      }
    }
  }
}
