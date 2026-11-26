import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/data/protected_json_store.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Recent explicit searches, newest first. Window resizing never edits storage.
class SearchHistoryStore extends ValueNotifier<List<String>> {
  SearchHistoryStore(Future<File> Function() resolveFile)
      : _resolveFile = resolveFile,
        super(const []);

  static final instance = SearchHistoryStore(() async =>
      File(path.join((await getAppDataDir()).path, 'search_history.json')));
  static const maxEntries = 12;
  final Future<File> Function() _resolveFile;
  ProtectedJsonStore? _store;
  bool _loaded = false;
  int _pendingClears = 0;
  List<String> _persisted = const [];

  void _publish(List<String> queries) {
    _persisted = List.unmodifiable(queries);
    if (_pendingClears == 0) value = _persisted;
  }
  Future<void> _pending = Future.value();

  Future<void> _serial(Future<void> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> flush() => _pending;

  static void _validate(Map<String, dynamic> data) {
    final queries = data['queries'];
    if (data['version'] != 1 ||
        (queries != null &&
            (queries is! List ||
                queries.length > maxEntries ||
                queries.any((q) => q is! String || q.trim().isEmpty)))) {
      throw const FormatException('Invalid search history');
    }
  }

  Future<void> _load() async {
    if (_loaded) return;
    final store = _store ??= ProtectedJsonStore(await _resolveFile(),
        validate: _validate, maxBytes: 512 * 1024);
    final data = await store.snapshot();
    final queries = (data['queries'] as List? ?? const [])
        .cast<String>()
        .map((q) => q.trim())
        .toSet();
    _publish(queries.toList());
    _loaded = true;
  }

  Future<void> load() => _serial(_load);

  Future<void> _save(List<String> queries) async {
    await _store!.update((data) => data['queries'] = queries);
    _publish(queries);
  }

  Future<void> record(String query,
          {required int Function(List<String>) capacity}) =>
      _serial(() async {
        final text = query.trim();
        if (text.isEmpty) return;
        await _load();
        if (_persisted.isNotEmpty && _persisted.first == text) return;
        final next = [text, ..._persisted.where((entry) => entry != text)]
            .take(maxEntries)
            .toList();
        // The canonical presentation budget also bounds long, full-row terms.
        // The current (possibly tiny) window is deliberately not this budget.
        await _save(next.take(capacity(next).clamp(1, maxEntries)).toList());
      });

  Future<void> remove(String query) => _serial(() async {
        await _load();
        if (!_persisted.contains(query)) return;
        await _save(_persisted.where((q) => q != query).toList());
      });

  /// Clears all saved queries with optimistic UI feedback and rollback on
  /// persistence failure when no newer search mutation has superseded it.
  Future<void> clear() {
    _pendingClears++;
    value = const [];
    return _serial(() async {
      try {
        await _load();
        await _save(const []);
      } finally {
        if (--_pendingClears == 0) value = _persisted;
      }
    });
  }
}
