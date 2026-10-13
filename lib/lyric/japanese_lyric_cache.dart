import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:path/path.dart' as path;

/// Disposable derived readings, never a saved lyric/document revision.
class JapaneseLyricReadingCache {
  JapaneseLyricReadingCache({
    Future<Directory> Function()? directory,
    String? engine,
    this.maximumEntries = 1024,
    this.maximumTotalBytes = 16 * 1024 * 1024,
    this.maximumEntryBytes = 512 * 1024,
  })  : _directory = directory ??
            (() async => Directory(path.join(
                (await getAppDataDir()).path, 'cache', 'japanese_readings'))),
        _engine = engine ??
            'display-v4-han-spans/lindera-6.2.0/'
                'a8acd8b6352774fe3f6ac3fdbec59313ce04b548dad84340c17f0ee4bfab6e43/'
                '${Platform.operatingSystem}/${Platform.operatingSystemVersion}';

  static final instance = JapaneseLyricReadingCache();
  final Future<Directory> Function() _directory;
  final String _engine;
  final int maximumEntries, maximumTotalBytes, maximumEntryBytes;
  _ReadingWrite? _pending;
  Future<void>? _draining;
  String? _inventoryDirectory;
  DateTime? _inventoryReadAt;
  final _inventory = <String, (int, DateTime)>{};
  var _inventoryTotalBytes = 0;

  String fingerprint(Lyric source, {String namespace = 'offline'}) => sha256
      .convert(utf8.encode(jsonEncode([
        _engine,
        namespace,
        LyricSnapshot.capture(source).toJson(),
      ])))
      .toString();

  Future<Map<int, JapaneseCachedReading>?> read(String fingerprint,
      {required bool Function() stillCurrent}) async {
    if (!stillCurrent() || !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      return null;
    }
    try {
      final file =
          File(path.join((await _directory()).path, '$fingerprint.json'));
      if (!stillCurrent() ||
          await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() > maximumEntryBytes) {
        return null;
      }
      final bytes = await file.readAsBytes();
      if (!stillCurrent() || bytes.length > maximumEntryBytes) return null;
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map ||
          value['fingerprint'] != fingerprint ||
          value['engine'] != _engine ||
          value['readings'] is! Map) {
        return null;
      }
      final result = <int, JapaneseCachedReading>{};
      for (final entry in (value['readings'] as Map).entries) {
        final index = entry.key is String ? int.tryParse(entry.key) : null;
        final value = entry.value;
        if (index == null ||
            index < 0 ||
            value is! Map ||
            value['text'] is! String ||
            (value['text'] as String).isEmpty ||
            value['spans'] is! List) {
          return null;
        }
        final spans = <JapaneseLyricReadingSpan>[];
        for (final span in value['spans'] as List) {
          if (span is! Map ||
              span['start'] is! int ||
              span['end'] is! int ||
              span['text'] is! String ||
              (span['text'] as String).isEmpty ||
              (span['start'] as int) < 0 ||
              (span['end'] as int) <= (span['start'] as int)) {
            return null;
          }
          spans.add(JapaneseLyricReadingSpan(
              start: span['start'] as int,
              end: span['end'] as int,
              text: span['text'] as String));
        }
        result[index] = JapaneseCachedReading(
            value['text'] as String, List.unmodifiable(spans));
      }
      return stillCurrent() && result.isNotEmpty
          ? Map.unmodifiable(result)
          : null;
    } catch (_) {
      return null;
    }
  }

  /// At most one writer and one latest pending result. A stale owner never
  /// replaces a newer entry, including after an asynchronous temporary write.
  Future<void> write(
      String fingerprint, Map<int, JapaneseCachedReading> readings,
      {required bool Function() stillCurrent}) {
    if (!stillCurrent() ||
        readings.isEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      return Future.value();
    }
    final next = _ReadingWrite(
        fingerprint,
        Map.unmodifiable({
          for (final entry in readings.entries)
            entry.key: JapaneseCachedReading(
                entry.value.text, List.unmodifiable(entry.value.spans)),
        }),
        stillCurrent);
    _pending?.done.complete();
    _pending = next;
    _draining ??= _drain();
    return next.done.future;
  }

  Future<void> flush() async {
    while (_draining != null) {
      await _draining;
    }
  }

  Future<void> _drain() async {
    // Start after write() has published _draining, including synchronous misses.
    await Future<void>.value();
    try {
      while (_pending != null) {
        final next = _pending!;
        _pending = null;
        try {
          await _write(next);
        } catch (_) {
          // Corrupt, unavailable or read-only cache cannot prevent analysis.
        } finally {
          next.done.complete();
        }
      }
    } finally {
      _draining = null;
    }
  }

  Future<void> _write(_ReadingWrite next) async {
    if (!next.current() || maximumEntries <= 0) return;
    final bytes = utf8.encode(jsonEncode({
      'fingerprint': next.fingerprint,
      'engine': _engine,
      'readings': {
        for (final entry in next.readings.entries)
          '${entry.key}': {
            'text': entry.value.text,
            'spans': [
              for (final span in entry.value.spans)
                {
                  'start': span.start,
                  'end': span.end,
                  'text': span.text,
                }
            ],
          }
      },
    }));
    if (bytes.length > maximumEntryBytes || bytes.length > maximumTotalBytes) {
      return;
    }
    final directory = await _directory();
    if (!next.current()) return;
    final existed = await directory.exists();
    await directory.create(recursive: true);
    final now = DateTime.now();
    if (!existed ||
        _inventoryDirectory != directory.path ||
        _inventoryReadAt == null ||
        now.difference(_inventoryReadAt!) > const Duration(minutes: 10)) {
      final inventory = <String, (int, DateTime)>{};
      // A batch shares this inventory; it never rescans the cache per song.
      var examined = 0;
      await for (final entity in directory.list(followLinks: false)) {
        if (++examined > 10000) return;
        if (entity is! File ||
            !RegExp(r'^[a-f0-9]{64}\.json$')
                .hasMatch(path.basename(entity.path))) {
          continue;
        }
        final stat = await entity.stat();
        inventory[entity.path] = (stat.size, stat.modified);
      }
      _inventory
        ..clear()
        ..addAll(inventory);
      _inventoryTotalBytes =
          inventory.values.fold<int>(0, (sum, entry) => sum + entry.$1);
      _inventoryDirectory = directory.path;
      _inventoryReadAt = now;
    }
    final target = File(path.join(directory.path, '${next.fingerprint}.json'));
    final temporary = File(
        '${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp');
    try {
      if (!next.current()) return;
      await temporary.writeAsBytes(bytes, flush: true);
      if (!next.current()) return;
      // Never replace a cache entry with a linked destination.
      if (await FileSystemEntity.type(target.path, followLinks: false) ==
          FileSystemEntityType.link) {
        return;
      }
      if (!next.current()) return;
      await temporary.rename(target.path);
      _inventoryTotalBytes -= _inventory[target.path]?.$1 ?? 0;
      _inventory[target.path] = (bytes.length, now);
      _inventoryTotalBytes += bytes.length;
      var count = _inventory.length;
      if (count <= maximumEntries &&
          _inventoryTotalBytes <= maximumTotalBytes) {
        return;
      }
      final files = _inventory.entries
          .where((entry) => entry.key != target.path)
          .toList()
        ..sort((a, b) => a.value.$2.compareTo(b.value.$2));
      for (final entry in files) {
        if (count <= maximumEntries &&
            _inventoryTotalBytes <= maximumTotalBytes) {
          break;
        }
        final file = File(entry.key);
        if (await file.exists()) await file.delete();
        _inventory.remove(entry.key);
        _inventoryTotalBytes -= entry.value.$1;
        count--;
      }
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {}
    }
  }
}

class _ReadingWrite {
  _ReadingWrite(this.fingerprint, this.readings, this.current);
  final String fingerprint;
  final Map<int, JapaneseCachedReading> readings;
  final bool Function() current;
  final done = Completer<void>();
}

class JapaneseCachedReading {
  const JapaneseCachedReading(this.text, this.spans);
  final String text;
  final List<JapaneseLyricReadingSpan> spans;
}
