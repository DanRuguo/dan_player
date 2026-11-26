import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/lyric/english_phonetic_lexicon.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:path/path.dart' as path;

/// Disposable derived English IPA phonetics cache (`cache/english_phonetics/`).
/// Stores canonical plain IPA spans; framing style (`plain`/`slashes`/`brackets`)
/// is applied during display projection without invalidating cached files.
class EnglishLyricPhoneticCache {
  EnglishLyricPhoneticCache({
    Future<Directory> Function()? directory,
    String? engine,
    this.maximumEntries = 1024,
    this.maximumTotalBytes = 16 * 1024 * 1024,
    this.maximumEntryBytes = 512 * 1024,
  })  : _directory = directory ??
            (() async => Directory(path.join(
                (await getAppDataDir()).path, 'cache', 'english_phonetics'))),
        _engine = engine ?? EnglishPhoneticLexicon.engineVersion;

  static final instance = EnglishLyricPhoneticCache();
  final Future<Directory> Function() _directory;
  final String _engine;
  final int maximumEntries, maximumTotalBytes, maximumEntryBytes;
  final _pending = <String, _PhoneticWrite>{};
  final _latestWrites = <String, Object>{};
  final _acceptedWrites = <Future<void>>{};
  static const _maximumPendingWrites = 8;
  Future<void>? _draining;
  String? _inventoryDirectory;
  DateTime? _inventoryReadAt;
  final _inventory = <String, (int, DateTime)>{};
  var _inventoryTotalBytes = 0;

  String fingerprint(Lyric source) => sha256
      .convert(utf8.encode(jsonEncode([
        _engine,
        LyricSnapshot.capture(source).toJson(),
      ])))
      .toString();

  Future<Map<int, EnglishCachedPhonetic>?> read(
    String fingerprint, {
    required bool Function() stillCurrent,
  }) async {
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
          value['phonetics'] is! Map) {
        return null;
      }
      final result = <int, EnglishCachedPhonetic>{};
      for (final entry in (value['phonetics'] as Map).entries) {
        final index = entry.key is String ? int.tryParse(entry.key) : null;
        final item = entry.value;
        if (index == null ||
            index < 0 ||
            item is! Map ||
            item['text'] is! String ||
            (item['text'] as String).isEmpty ||
            item['spans'] is! List) {
          return null;
        }
        final spans = <EnglishLyricPhoneticSpan>[];
        for (final span in item['spans'] as List) {
          if (span is! Map ||
              span['start'] is! int ||
              span['end'] is! int ||
              span['text'] is! String ||
              (span['text'] as String).isEmpty ||
              (span['start'] as int) < 0 ||
              (span['end'] as int) <= (span['start'] as int)) {
            return null;
          }
          spans.add(EnglishLyricPhoneticSpan(
            start: span['start'] as int,
            end: span['end'] as int,
            text: span['text'] as String,
          ));
        }
        result[index] = EnglishCachedPhonetic(
          item['text'] as String,
          List.unmodifiable(spans),
        );
      }
      return stillCurrent() && result.isNotEmpty
          ? Map.unmodifiable(result)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(
    String fingerprint,
    Map<int, EnglishCachedPhonetic> phonetics, {
    required bool Function() stillCurrent,
  }) {
    if (!stillCurrent() ||
        phonetics.isEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      return Future.value();
    }
    final identity = Object();
    final next = _PhoneticWrite(
      fingerprint,
      Map.unmodifiable({
        for (final entry in phonetics.entries)
          entry.key: EnglishCachedPhonetic(
            entry.value.text,
            List.unmodifiable(entry.value.spans),
          ),
      }),
      () => identical(_latestWrites[fingerprint], identity) && stillCurrent(),
    );
    _latestWrites[fingerprint] = identity;
    late final Future<void> accepted;
    accepted = _enqueue(next).whenComplete(() {
      _acceptedWrites.remove(accepted);
      if (identical(_latestWrites[fingerprint], identity)) {
        _latestWrites.remove(fingerprint);
      }
    });
    _acceptedWrites.add(accepted);
    return accepted;
  }

  Future<void> _enqueue(_PhoneticWrite next) {
    if (!next.current()) return Future.value();
    _pending.removeWhere((_, previous) {
      if (previous.current()) return false;
      previous.done.complete();
      return true;
    });
    final previous = _pending[next.fingerprint];
    if (previous == null && _pending.length >= _maximumPendingWrites) {
      return _draining!.then((_) => _enqueue(next));
    }
    previous?.done.complete();
    _pending[next.fingerprint] = next;
    _draining ??= _drain();
    return next.done.future;
  }

  Future<void> flush() async {
    while (_acceptedWrites.isNotEmpty) {
      await Future.wait(_acceptedWrites.toList());
    }
  }

  Future<void> _drain() async {
    await Future<void>.value();
    try {
      while (_pending.isNotEmpty) {
        final next = _pending.remove(_pending.keys.first)!;
        try {
          await _write(next);
        } catch (_) {
          // Read-only or unavailable cache never blocks display projection.
        } finally {
          next.done.complete();
        }
      }
    } finally {
      _draining = null;
    }
  }

  Future<void> _write(_PhoneticWrite next) async {
    if (!next.current() || maximumEntries <= 0) return;
    final bytes = utf8.encode(jsonEncode({
      'fingerprint': next.fingerprint,
      'engine': _engine,
      'phonetics': {
        for (final entry in next.phonetics.entries)
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

class _PhoneticWrite {
  _PhoneticWrite(this.fingerprint, this.phonetics, this.current);
  final String fingerprint;
  final Map<int, EnglishCachedPhonetic> phonetics;
  final bool Function() current;
  final done = Completer<void>();
}

class EnglishCachedPhonetic {
  const EnglishCachedPhonetic(this.text, this.spans);
  final String text;
  final List<EnglishLyricPhoneticSpan> spans;
}
