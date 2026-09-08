import 'dart:io';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/data/protected_json_store.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:path/path.dart' as p;

class NamedQueueStore {
  NamedQueueStore(File file)
      : store = ProtectedJsonStore(file, validate: validate);
  final ProtectedJsonStore store;
  static Future<NamedQueueStore>? _instance;
  static Future<NamedQueueStore> get instance =>
      _instance ??= (() async => NamedQueueStore(
          File(p.join((await getAppDataDir()).path, 'named_queues.json'))))();
  static void validate(Map<String, dynamic> root) {
    if (root['version'] != 1 ||
        (root['sessions'] != null && root['sessions'] is! List))
      throw const FormatException('Invalid queue store');
    final sessions = root['sessions'] as List? ?? [];
    if (sessions.length > 20) throw const FormatException('最多保存 20 个收听会话');
    var total = 0;
    final ids = <String>{};
    for (final raw in sessions) {
      if (raw is! Map ||
          raw['id'] is! String ||
          !ids.add(raw['id']) ||
          raw['name'] is! String ||
          (raw['name'] as String).trim().isEmpty ||
          (raw['name'] as String).length > 80)
        throw const FormatException('Invalid named queue');
      validateSnapshot(raw);
      total += (raw['queue'] as List).length;
    }
    if (total > 50000) throw const FormatException('保存的收听会话最多包含 50000 个出现项');
  }

  static void validateSnapshot(Map raw) {
    final queue = raw['queue'],
        backup = raw['backup'],
        slots = raw['slots'],
        position = raw['position'];
    if (queue is! List ||
        queue.isEmpty ||
        queue.length > 50000 ||
        backup is! List ||
        slots is! Map ||
        slots.length != queue.length ||
        queue.toSet().length != queue.length ||
        backup.toSet().length != backup.length ||
        !queue.toSet().containsAll(backup) ||
        queue.length != backup.length ||
        raw['shuffle'] is! bool ||
        position is! num ||
        !position.isFinite ||
        position < 0 ||
        !queue.contains(raw['current']))
      throw const FormatException('Invalid queue snapshot');
    for (final id in queue) {
      final slot = slots[id];
      if (id is! String ||
          slot is! Map ||
          slot['track'] is! String ||
          (!TrackIdentityRegistry.isTrackId(slot['track']) &&
              !slot['track'].startsWith('online://')))
        throw const FormatException('Invalid queue identity');
      if (slot['cue'] != null &&
          (slot['cue'] is! Map ||
              !Audio.fromMap(slot['cue'] as Map).isCueTrack))
        throw const FormatException('Invalid CUE snapshot');
    }
  }

  Future<List<Map<String, dynamic>>> list() async =>
      ((await store.snapshot())['sessions'] as List? ?? [])
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
  Future<void> save(String name, Map<String, dynamic> snapshot) async {
    await TrackIdentityRegistry.instance.flush();
    await store.update((root) {
      final sessions = root.putIfAbsent('sessions', () => []) as List;
      sessions.add({
        ...snapshot,
        'id': 'session-${DateTime.now().microsecondsSinceEpoch}',
        'name': name.trim()
      });
    });
  }

  Future<void> rename(String id, String name) => store.update((root) {
        for (final s in root['sessions'] as List? ?? []) {
          if (s['id'] == id) s['name'] = name.trim();
        }
      });
  Future<void> remove(String id) => store.update((root) {
        (root['sessions'] as List? ?? []).removeWhere((s) => s['id'] == id);
      });
}
