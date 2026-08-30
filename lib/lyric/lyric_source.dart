import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/utils.dart';

enum LyricSourceType {
  qq("qq"),
  kugou("kugou"),
  netease("netease"),
  lrclib("lrclib"),
  local("local");

  final String name;
  const LyricSourceType(this.name);
}

bool isLyricSourceCompatible({
  required bool isOnline,
  required LyricSourceType source,
}) {
  return !(isOnline && source == LyricSourceType.local);
}

/// 默认歌词来源
class LyricSource {
  LyricSourceType source;
  int? qqSongId;
  String? qqSongMid;
  String? kugouSongHash;
  String? neteaseSongId;
  int? lrclibId;

  LyricSource(
    this.source, {
    this.qqSongId,
    this.qqSongMid,
    this.kugouSongHash,
    this.neteaseSongId,
    this.lrclibId,
  });

  static LyricSource fromMap(Map map) {
    final source = map["source"]?.toString();
    return switch (source) {
      "qq" => _qqFromMap(map),
      "kugou" => LyricSource(
          LyricSourceType.kugou,
          kugouSongHash: _requiredText(map["id"], "kugou lyric hash"),
        ),
      "netease" => LyricSource(
          LyricSourceType.netease,
          neteaseSongId: _requiredText(map["id"], "netease lyric id"),
        ),
      "lrclib" => LyricSource(
          LyricSourceType.lrclib,
          lrclibId: _requiredPositiveInt(map["id"], "LRCLIB lyric id"),
        ),
      "local" => LyricSource(LyricSourceType.local),
      _ => throw const FormatException("Unknown lyric source"),
    };
  }

  static LyricSource _qqFromMap(Map map) {
    final rawId = map["id"];
    int? parsedId;
    if (rawId is int) {
      parsedId = rawId;
    } else if (rawId is num && rawId.isFinite) {
      final converted = rawId.toInt();
      if (rawId == converted) parsedId = converted;
    } else {
      parsedId = int.tryParse(rawId?.toString() ?? "");
    }
    final explicitMid = _optionalText(map["mid"]);
    final legacyMid =
        parsedId == null && rawId is String ? _optionalText(rawId) : null;
    if ((parsedId == null || parsedId <= 0) &&
        explicitMid == null &&
        legacyMid == null) {
      throw const FormatException("Missing QQ lyric identity");
    }
    return LyricSource(
      LyricSourceType.qq,
      qqSongId: parsedId != null && parsedId > 0 ? parsedId : null,
      qqSongMid: explicitMid ?? legacyMid,
    );
  }

  Map toMap() {
    switch (source) {
      case LyricSourceType.qq:
        return {
          "source": source.name,
          "id": qqSongId,
          if (qqSongMid != null) "mid": qqSongMid,
        };
      case LyricSourceType.kugou:
        return {"source": source.name, "id": kugouSongHash};
      case LyricSourceType.netease:
        return {"source": source.name, "id": neteaseSongId};
      case LyricSourceType.lrclib:
        return {"source": source.name, "id": lrclibId};
      case LyricSourceType.local:
        return {"source": source.name, "id": null};
    }
  }

  bool matches({
    required LyricSourceType candidateSource,
    int? candidateQqSongId,
    String? candidateQqSongMid,
    String? candidateKugouSongHash,
    String? candidateNeteaseSongId,
    int? candidateLrclibId,
  }) {
    if (source != candidateSource) return false;
    return switch (source) {
      LyricSourceType.qq =>
        (qqSongId != null && qqSongId == candidateQqSongId) ||
            (qqSongMid != null && qqSongMid == candidateQqSongMid),
      LyricSourceType.kugou =>
        kugouSongHash != null && kugouSongHash == candidateKugouSongHash,
      LyricSourceType.netease =>
        neteaseSongId != null && neteaseSongId == candidateNeteaseSongId,
      LyricSourceType.lrclib =>
        lrclibId != null && lrclibId == candidateLrclibId,
      LyricSourceType.local => true,
    };
  }
}

Map<String, LyricSource> LYRIC_SOURCES = {};
Future<void> _lyricSourceSaveTail = Future<void>.value();

Future<void> readLyricSources({Directory? storageDirectory}) async {
  final directory = storageDirectory ?? await getAppDataDir();
  final primary = File("${directory.path}\\lyric_source.json");
  final backup = File("${primary.path}.bak");
  for (final candidate in [primary, backup]) {
    if (!await candidate.exists()) continue;
    try {
      final decoded = json.decode(await candidate.readAsString());
      if (decoded is! Map) {
        throw const FormatException("Lyric source index is not an object");
      }
      final restored = <String, LyricSource>{};
      for (final item in decoded.entries) {
        try {
          final audioPath = item.key.toString();
          if (audioPath.trim().isEmpty || item.value is! Map) continue;
          final source = LyricSource.fromMap(item.value as Map);
          final isOnlinePath = audioPath.startsWith("online://");
          if (!isLyricSourceCompatible(
            isOnline: isOnlinePath,
            source: source.source,
          )) {
            continue;
          }
          // Keep associations for temporarily unavailable drives and renamed
          // files. A later library reconciliation can migrate the path without
          // an ordinary startup silently deleting the user's chosen source.
          restored[audioPath] = source;
        } catch (error, trace) {
          LOGGER.w("忽略一条损坏的歌词来源记录", stackTrace: trace);
        }
      }
      LYRIC_SOURCES
        ..clear()
        ..addAll(restored);
      return;
    } catch (error, trace) {
      LOGGER.w("读取歌词来源索引失败：${candidate.path}", stackTrace: trace);
    }
  }
}

Future<void> saveLyricSources({Directory? storageDirectory}) {
  return _enqueueLyricSourceOperation(() {
    final snapshot = <String, Map>{
      for (final item in LYRIC_SOURCES.entries) item.key: item.value.toMap(),
    };
    return _writeLyricSources(
      snapshot,
      storageDirectory: storageDirectory,
    );
  });
}

Future<void> persistLyricSource(
  String audioPath,
  LyricSource source, {
  Directory? storageDirectory,
}) async {
  await _enqueueLyricSourceOperation(() async {
    final hadPrevious = LYRIC_SOURCES.containsKey(audioPath);
    final previous = LYRIC_SOURCES[audioPath];
    LYRIC_SOURCES[audioPath] = source;
    final snapshot = <String, Map>{
      for (final item in LYRIC_SOURCES.entries) item.key: item.value.toMap(),
    };
    try {
      await _writeLyricSources(
        snapshot,
        storageDirectory: storageDirectory,
      );
    } catch (_) {
      if (hadPrevious) {
        LYRIC_SOURCES[audioPath] = previous!;
      } else {
        LYRIC_SOURCES.remove(audioPath);
      }
      rethrow;
    }
  });
}

Future<void> _enqueueLyricSourceOperation(Future<void> Function() operation) {
  final queued = _lyricSourceSaveTail.then((_) => operation());
  _lyricSourceSaveTail = queued.then<void>((_) {}, onError: (_, __) {});
  return queued;
}

Future<void> _writeLyricSources(
  Map<String, Map> snapshot, {
  Directory? storageDirectory,
}) async {
  final directory = storageDirectory ?? await getAppDataDir();
  await directory.create(recursive: true);
  final target = File("${directory.path}\\lyric_source.json");
  final backup = File("${target.path}.bak");
  final temporary = File(
    "${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp",
  );
  var movedPrimary = false;
  try {
    await temporary.writeAsString(
      const JsonEncoder.withIndent("  ").convert(snapshot),
      flush: true,
    );
    if (await target.exists()) {
      if (await backup.exists()) await backup.delete();
      await target.rename(backup.path);
      movedPrimary = true;
    }
    await temporary.rename(target.path);
  } catch (_) {
    if (movedPrimary && !await target.exists() && await backup.exists()) {
      try {
        await backup.rename(target.path);
      } catch (restoreError, trace) {
        LOGGER.e("恢复旧歌词来源索引失败：$restoreError", stackTrace: trace);
      }
    }
    rethrow;
  } finally {
    if (await temporary.exists()) {
      try {
        await temporary.delete();
      } catch (_) {}
    }
  }
}

String? _optionalText(Object? value) {
  if (value is! String && value is! num) return null;
  final text = value.toString().trim();
  return text.isEmpty || text.toLowerCase() == "null" ? null : text;
}

int _requiredPositiveInt(Object? value, String field) {
  final parsed = value is int ? value : int.tryParse(value?.toString() ?? "");
  if (parsed == null || parsed <= 0) throw FormatException("Missing $field");
  return parsed;
}

String _requiredText(Object? value, String field) {
  final text = _optionalText(value);
  if (text == null) throw FormatException("Missing $field");
  return text;
}
