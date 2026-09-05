import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/play_service/queue_edits.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';

void main() {
  test('move/remove operates on occurrences and preserves current position',
      () {
    final items = ['same', 'middle', 'same', 'last'];
    final moved = QueueEdit.moveNext(items, 2, 0)!;
    expect(moved.items, ['middle', 'same', 'same', 'last']);
    expect(moved.currentIndex, 1);
    expect(items, ['same', 'middle', 'same', 'last']);
    final removed = QueueEdit.remove(items, 2, 0)!;
    expect(removed.items, ['middle', 'same', 'last']);
    expect(removed.currentIndex, 1);
    expect(QueueEdit.remove(items, 2, 2), isNull);
    expect(QueueEdit.moveNext(items, 2, 2), isNull);
    expect(QueueEdit.moveNext(items, 2, 3), isNull);
    expect(QueueEdit.remove(items, 2, 100), isNull);
  });

  test('queue playlist keeps ordered repeated occurrences with separate IDs',
      () {
    final tree = PlaylistTree([]);
    final a = CategoryTestAudio('first');
    final b = CategoryTestAudio('second', online: true);
    final saved = tree.createPlaylistFromAudios('Mixed queue', [a, b, a]);
    expect(saved.flattenAudios(), [a, b, a]);
    expect(saved.entries.map((entry) => entry.id).toSet().length, 3);
    tree.validate();
    expect(() => tree.createPlaylistFromAudios(' ', [b]), throwsArgumentError);
    expect(tree.roots.length, 1);
    // Existing library additions retain their deliberate de-duplication policy.
    expect(tree.addAudios(saved, [a, b]), isEmpty);
  });

  test('A-B loop validates range and waits for seek acknowledgement', () {
    final loop = SegmentLoopController();
    addTearDown(loop.dispose);
    expect(loop.setStart(10, 100), isTrue);
    expect(loop.setEnd(10.5, 100), isFalse);
    expect(loop.setEnd(20, 100), isTrue);
    loop.setEnabled(true);
    expect(loop.targetForPosition(19.9), isNull);
    expect(loop.targetForPosition(20), 10);
    expect(loop.targetForPosition(20.1), isNull);
    expect(loop.targetForPosition(10), isNull);
    expect(loop.targetForPosition(21), 10);
    loop.manualSeek(5);
    expect(loop.enabled, isFalse);
    expect(loop.hasRange, isTrue);
    loop.setEnabled(true);
    loop.clear(); // Source changes cancel the range before asynchronous loading.
    expect(loop.targetForPosition(30), isNull);
    expect(loop.start, isNull);
    expect(loop.end, isNull);
    expect(loop.setStart(double.nan, 100), isFalse);
    expect(loop.setEnd(double.infinity, 100), isFalse);
  });
}
