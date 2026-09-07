import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Durable identities live beside the scanner index: rebuilding that index
/// must never regenerate IDs or infer identity from editable tags/fingerprints.
class TrackIdentityRegistry {
  TrackIdentityRegistry._();

  static final instance = TrackIdentityRegistry._();
  static const fileName = 'track_identities.json';
  static final _idPattern = RegExp(
      r'^local:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
  static bool isTrackId(String value) => _idPattern.hasMatch(value);
  static final _random = Random.secure();

  @visibleForTesting
  factory TrackIdentityRegistry.inMemory() => TrackIdentityRegistry._();

  final Map<String, _TrackIdentity> _records = {};
  final Map<String, String> _byLocation = {};
  String? _directory;
  bool _dirty = false;
  bool _preserveBackup = false;
  Future<void> _writes = Future.value();

  static String normalizePath(String value) => value.startsWith('cue://')
      ? value
      : p.windows.normalize(value).toLowerCase();

  Future<void> initialize({Directory? directory}) async {
    final root = directory ?? await getAppDataDir();
    final rootPath = root.absolute.path;
    if (_directory == rootPath) return;
    await _writes;
    final target = File(p.join(rootPath, fileName));
    Object? firstError;
    List<_TrackIdentity>? restored;
    var recovered = false;
    for (final candidate in [target, File('${target.path}.bak')]) {
      if (!await candidate.exists()) continue;
      try {
        restored = _decode(jsonDecode(await candidate.readAsString()));
        recovered = candidate.path != target.path;
        break;
      } catch (error) {
        firstError ??= error;
      }
    }
    if (restored == null && firstError != null) {
      throw FormatException('Stable track identities cannot be recovered: '
          '$firstError');
    }
    // Do not discard IDs created before the first persistence call. A profile
    // switch is explicit and uses only that profile's authoritative registry.
    final pending =
        _directory == null ? _records.values.toList() : <_TrackIdentity>[];
    _records.clear();
    _byLocation.clear();
    for (final entry in restored ?? <_TrackIdentity>[]) {
      _records[entry.trackId] = entry;
      _byLocation[entry.locationKey] = entry.trackId;
    }
    for (final entry in pending) {
      if (!_byLocation.containsKey(entry.locationKey) &&
          !_records.containsKey(entry.trackId)) {
        _records[entry.trackId] = entry;
        _byLocation[entry.locationKey] = entry.trackId;
      }
    }
    _directory = rootPath;
    _dirty = recovered || pending.isNotEmpty;
    _preserveBackup = recovered;
  }

  String idFor(String path, {CueTrackReference? cue, String? preferredId}) {
    if (path.startsWith('online://')) return path;
    final prototype = _TrackIdentity(
        '', path, [], cue?.sourcePath, cue?.startFrame, cue?.endFrame);
    final known = _byLocation[prototype.locationKey];
    if (known != null) return known;
    // A copied index ID must not collapse two independent file instances. CUE
    // boundary changes likewise never inherit the previous segment's ID.
    final canUsePreferred = preferredId != null &&
        isTrackId(preferredId) &&
        !_records.containsKey(preferredId);
    final id = canUsePreferred ? preferredId : _newId();
    final entry = _TrackIdentity(
        id, path, [], cue?.sourcePath, cue?.startFrame, cue?.endFrame);
    _records[id] = entry;
    _byLocation[entry.locationKey] = id;
    _dirty = true;
    return id;
  }

  /// Old paths resolve only if unambiguous. New imports use [idFor] and never
  /// reuse an old alias when a different file appears at a vacated location.
  String? resolvePath(String path) {
    final normalized = normalizePath(path);
    final candidates = _records.values.where((record) =>
        normalizePath(record.path) == normalized ||
        record.aliases.any((alias) => normalizePath(alias) == normalized));
    final ids = candidates.map((record) => record.trackId).toSet();
    return ids.length == 1 ? ids.single : null;
  }

  /// Called after an explicit, validated mapping; it moves references only.
  /// All conflicts are checked before mutating the current registry.
  void remapPaths(String Function(String) mapPath) {
    final mapped = <String, _TrackIdentity>{};
    final locations = <String, String>{};
    for (final old in _records.values) {
      final nextPath = mapPath(old.path);
      final next = _TrackIdentity(
          old.trackId,
          nextPath,
          {...old.aliases, if (nextPath != old.path) old.path}.toList(),
          old.cueSourcePath == null ? null : mapPath(old.cueSourcePath!),
          old.cueStartFrame,
          old.cueEndFrame);
      final previous = locations[next.locationKey];
      if (previous != null && previous != next.trackId) {
        throw StateError('Two track identities map to the same file/segment');
      }
      mapped[next.trackId] = next;
      locations[next.locationKey] = next.trackId;
    }
    _records
      ..clear()
      ..addAll(mapped);
    _byLocation
      ..clear()
      ..addAll(locations);
    _dirty = true;
  }

  Future<void> relocatePaths(Map<String, String> mapping) async {
    await initialize();
    final normalized = {
      for (final entry in mapping.entries)
        normalizePath(entry.key): entry.value,
    };
    remapPaths((path) => normalized[normalizePath(path)] ?? path);
    await flush();
  }

  /// Reload after the cross-file migration journal has committed its batch.
  Future<void> reload() async {
    await _writes;
    _records.clear();
    _byLocation.clear();
    _directory = null;
    _dirty = false;
    await initialize();
  }

  Map<String, Object?> toMap() => {
        'version': 1,
        'records': [for (final record in _records.values) record.toMap()],
      };

  Future<void> flush() {
    final result = _writes.then((_) async {
      if (_directory == null) {
        // initialize() normally awaits this queue; use a temporary independent
        // load here to avoid a self-await when persisting a standalone track.
        final root = await getAppDataDir();
        final loaded = TrackIdentityRegistry._();
        await loaded.initialize(directory: root);
        for (final entry in _records.values) {
          final existing = loaded._byLocation[entry.locationKey];
          if (existing != null && existing != entry.trackId) {
            throw StateError('Track identity was used before registry load');
          }
          loaded._records[entry.trackId] = entry;
          loaded._byLocation[entry.locationKey] = entry.trackId;
        }
        _directory = root.absolute.path;
        _records
          ..clear()
          ..addAll(loaded._records);
        _byLocation
          ..clear()
          ..addAll(loaded._byLocation);
        _preserveBackup = loaded._preserveBackup;
      }
      if (!_dirty) return;
      final contents = jsonEncode(toMap());
      final target = File(p.join(_directory!, fileName));
      final temporary = File('${target.path}.tmp');
      final backup = File('${target.path}.bak');
      await target.parent.create(recursive: true);
      await temporary.writeAsString(contents, flush: true);
      if (!_preserveBackup && await target.exists()) {
        if (await backup.exists()) await backup.delete();
        await target.rename(backup.path);
      } else if (_preserveBackup && await target.exists()) {
        // Preserve the corrupt target for diagnosis without replacing the only
        // successfully parsed backup.
        await target.rename(
            '${target.path}.damaged-${DateTime.now().microsecondsSinceEpoch}');
      }
      try {
        await temporary.rename(target.path);
      } catch (_) {
        if (!await target.exists() && await backup.exists()) {
          await backup.copy(target.path);
        }
        rethrow;
      }
      _preserveBackup = false;
      // Mutations during disk I/O remain dirty for the next flush.
      _dirty = contents != jsonEncode(toMap());
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static List<_TrackIdentity> _decode(Object? raw) {
    if (raw is! Map || raw['version'] != 1 || raw['records'] is! List) {
      throw const FormatException('Invalid stable track registry');
    }
    final result = <_TrackIdentity>[];
    final ids = <String>{};
    final locations = <String>{};
    for (final value in raw['records'] as List) {
      if (value is! Map ||
          value['trackId'] is! String ||
          !isTrackId(value['trackId']) ||
          value['path'] is! String ||
          (value['path'] as String).isEmpty ||
          value['aliases'] is! List ||
          (value['aliases'] as List).any((alias) => alias is! String)) {
        throw const FormatException('Invalid stable track record');
      }
      final source = value['cueSourcePath'];
      final start = value['cueStartFrame'];
      final end = value['cueEndFrame'];
      if ((source != null && source is! String) ||
          (start != null && (start is! int || start < 0)) ||
          (end != null && (end is! int || start is! int || end <= start)) ||
          ((source == null) != (start == null))) {
        throw const FormatException('Invalid stable CUE boundary');
      }
      final entry = _TrackIdentity(value['trackId'], value['path'],
          List<String>.from(value['aliases']), source, start, end);
      if (!ids.add(entry.trackId) || !locations.add(entry.locationKey)) {
        throw const FormatException('Duplicate stable track identity/location');
      }
      result.add(entry);
    }
    return result;
  }

  static String _newId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return 'local:${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class _TrackIdentity {
  _TrackIdentity(this.trackId, this.path, this.aliases, this.cueSourcePath,
      this.cueStartFrame, this.cueEndFrame);
  final String trackId;
  final String path;
  final List<String> aliases;
  final String? cueSourcePath;
  final int? cueStartFrame;
  final int? cueEndFrame;

  String get locationKey => jsonEncode([
        TrackIdentityRegistry.normalizePath(path),
        if (cueSourcePath != null) ...[
          TrackIdentityRegistry.normalizePath(cueSourcePath!),
          cueStartFrame,
          cueEndFrame,
        ],
      ]);
  Map<String, Object?> toMap() => {
        'trackId': trackId,
        'path': path,
        'aliases': aliases,
        if (cueSourcePath != null) ...{
          'cueSourcePath': cueSourcePath,
          'cueStartFrame': cueStartFrame,
          'cueEndFrame': cueEndFrame,
        },
      };
}
