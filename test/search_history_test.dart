import 'dart:io';

import 'package:dan_player/search/search_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;
  late SearchHistoryStore history;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('search-history-');
    file = File('${directory.path}/history.json');
    history = SearchHistoryStore(() async => file);
  });
  tearDown(() async {
    await history.flush();
    history.dispose();
    await directory.delete(recursive: true);
  });

  test('queued additions preserve recency, Unicode and deduplicate on reload',
      () async {
    int capacity(List<String> _) => 12;
    final writes = [
      history.record('  春の歌 🎶  ', capacity: capacity),
      history.record('한국어 café', capacity: capacity),
      history.record('春の歌 🎶', capacity: capacity),
    ];
    await Future.wait(writes);
    final reopened = SearchHistoryStore(() async => file);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.value, ['한국어 café', '春の歌 🎶']);
  });

  test(
      'canonical area evicts oldest independently of count and deletion persists',
      () async {
    for (var i = 0; i < 15; i++) {
      await history.record('query $i', capacity: (_) => 12);
    }
    expect(history.value.length, 12);
    expect(history.value.last, 'query 3');
    await history.record('full row', capacity: (_) => 3);
    expect(history.value, ['full row', 'query 14', 'query 13']);
    await history.remove('query 14');
    final reopened = SearchHistoryStore(() async => file);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.value, ['full row', 'query 13']);
  });

  test('repeat searches neither rewrite storage nor move an existing capsule',
      () async {
    await history.record('older', capacity: (_) => 12);
    await history.record('newest', capacity: (_) => 12);
    final saved = await file.readAsString();
    // Any attempted commit would fail here, proving duplicates skip disk writes.
    await Directory('${file.path}.tmp').create();
    await history.record('  older  ', capacity: (_) => 1);
    expect(history.value, ['newest', 'older']);
    expect(await file.readAsString(), saved);
  });

  test('failed removal preserves the visible term and a later retry succeeds',
      () async {
    await history.record('keep me', capacity: (_) => 12);
    final blocker = await Directory('${file.path}.tmp').create();
    await expectLater(
        history.remove('keep me'), throwsA(isA<FileSystemException>()));
    expect(history.value, ['keep me']);
    await blocker.delete();
    await history.remove('keep me');
    expect(history.value, isEmpty);
  });
}
