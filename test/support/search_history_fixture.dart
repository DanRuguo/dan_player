import 'package:dan_player/search/search_history.dart';

/// Widget tests exercise interaction without real disk work in fake time.
/// The real serialized persistence has separate I/O tests.
class MemorySearchHistory extends SearchHistoryStore {
  MemorySearchHistory([List<String> queries = const []])
      : super(() async => throw StateError('No disk in component fixture')) {
    value = List.unmodifiable(queries);
  }

  @override
  Future<void> load() async {}

  @override
  Future<void> record(String query,
      {required int Function(List<String>) capacity}) async {
    if (value.contains(query.trim())) return;
    final next = [query.trim(), ...value.where((q) => q != query.trim())]
        .take(SearchHistoryStore.maxEntries)
        .toList();
    value = List.unmodifiable(next.take(capacity(next)));
  }

  @override
  Future<void> remove(String query) async {
    value = List.unmodifiable(value.where((q) => q != query));
  }
}
