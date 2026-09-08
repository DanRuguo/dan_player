import 'dart:io';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/data/protected_json_store.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class PersonalTrack {
  const PersonalTrack(
      {this.rating,
      this.tags = const [],
      this.firstAddedAtUtc,
      this.modifiedAtUtc,
      this.addedFromCreation = false});
  final int? rating;
  final List<String> tags;
  final DateTime? firstAddedAtUtc;
  final DateTime? modifiedAtUtc;
  final bool addedFromCreation;
  factory PersonalTrack.decode(Map value) => PersonalTrack(
      rating: value['rating'] as int?,
      modifiedAtUtc: value['modified'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(value['modified'] as int,
              isUtc: true),
      addedFromCreation: value['addedFromCreation'] == true,
      tags: List<String>.unmodifiable((value['tags'] as List?) ?? const []),
      firstAddedAtUtc: value['added'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(value['added'] as int,
              isUtc: true));
}

class PersonalLibrary {
  PersonalLibrary(File file)
      : store = ProtectedJsonStore(file, validate: validate);
  final ProtectedJsonStore store;
  static final changes = ValueNotifier<int>(0);
  static Map<String, PersonalTrack> latest = const {};
  static Future<PersonalLibrary>? _instance;
  static Future<PersonalLibrary> get instance =>
      _instance ??= (() async => PersonalLibrary(File(
          p.join((await getAppDataDir()).path, 'personal_library.json'))))();
  static void validate(Map<String, dynamic> root) {
    if (root['version'] != 1 ||
        (root['seeded'] != null && root['seeded'] is! bool) ||
        (root['tracks'] != null && root['tracks'] is! Map))
      throw const FormatException('Invalid personal library');
    final tracks = (root['tracks'] as Map?) ?? {};
    for (final entry in tracks.entries) {
      if (entry.key is! String ||
          (!TrackIdentityRegistry.isTrackId(entry.key) &&
              !entry.key.startsWith('online://')) ||
          entry.value is! Map)
        throw const FormatException('Invalid personal track');
      final item = entry.value as Map;
      final rating = item['rating'], tags = item['tags'], added = item['added'];
      final modified = item['modified'];
      if (modified != null &&
          (modified is! int || modified < 0 || modified > 8640000000000000))
        throw const FormatException('Invalid personal modification date');
      if ((item['addedFromCreation'] != null &&
              item['addedFromCreation'] is! bool) ||
          (rating != null && (rating is! int || rating < 1 || rating > 5)) ||
          (tags != null &&
              (tags is! List ||
                  tags.length > 32 ||
                  tags.any((t) =>
                      t is! String || t.trim().isEmpty || t.length > 80))) ||
          (added != null &&
              (added is! int || added < 0 || added > 8640000000000000)))
        throw const FormatException('Invalid personal values');
    }
  }

  Future<Map<String, PersonalTrack>> snapshot() async {
    final value = await store.snapshot();
    return latest = Map.unmodifiable({
      for (final e in ((value['tracks'] as Map?) ?? {}).entries)
        e.key as String: PersonalTrack.decode(e.value as Map)
    });
  }

  /// Existing songs use file creation time, explicitly marked as a fallback.
  /// New committed identities
  /// use the index commit timestamp, which survives a failed synchronization.
  Future<void> observeCommitted(
      Map<String, int> creationSeconds, DateTime committedAt) async {
    final ids = creationSeconds.keys.toSet();
    final current = await store.snapshot();
    final known = (current['tracks'] as Map?) ?? {};
    if (current['seeded'] == true &&
        ids.every((id) =>
            known.containsKey(id) &&
            ((known[id] as Map)['added'] != null ||
                (creationSeconds[id] ?? 0) <= 0))) return;
    await store.update((root) {
      final seeded = root['seeded'] == true;
      final tracks =
          root.putIfAbsent('tracks', () => <String, dynamic>{}) as Map;
      for (final id in ids) {
        final existed = tracks.containsKey(id);
        final item = tracks.putIfAbsent(
            id, () => <String, dynamic>{'tags': <String>[]}) as Map;
        if (item['added'] == null) {
          if (seeded && !existed) {
            item['added'] = committedAt.toUtc().millisecondsSinceEpoch;
          } else if ((creationSeconds[id] ?? 0) > 0) {
            item['added'] = creationSeconds[id]! * 1000;
            item['addedFromCreation'] = true;
          }
        }
      }
      root['seeded'] = true;
    });
    await snapshot();
    changes.value++;
  }

  Future<void> apply(Iterable<Audio> targets,
      {bool changeRating = false,
      int? rating,
      bool changeTags = false,
      List<String> addTags = const [],
      List<String> removeTags = const []}) async {
    final ids = targets.map((a) => a.stableTrackId).toSet();
    await TrackIdentityRegistry.instance.flush();
    await store.update((root) {
      final tracks =
          root.putIfAbsent('tracks', () => <String, dynamic>{}) as Map;
      for (final id in ids) {
        final item = Map<String, dynamic>.from(tracks[id] as Map? ?? {});
        final oldRating = item['rating'];
        final oldTags = Set<String>.from((item['tags'] as List?) ?? []);
        if (changeRating) item['rating'] = rating;
        if (changeTags)
          item['tags'] = {...((item['tags'] as List?) ?? []), ...addTags}
              .where((t) => !removeTags.contains(t))
              .toList();
        if (oldRating != item['rating'] ||
            !setEquals(
                oldTags, Set<String>.from((item['tags'] as List?) ?? [])))
          item['modified'] = DateTime.now().toUtc().millisecondsSinceEpoch;
        tracks[id] = item;
      }
    });
    await snapshot();
    changes.value++;
  }
}
