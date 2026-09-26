import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/play_service/queue_duration_summary.dart';
import 'package:dan_player/play_service/queue_edits.dart';
import 'package:dan_player/play_service/queue_stop_boundary.dart';
import 'package:dan_player/play_service/queue_track_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';

void main() {
  test(
      'trim preserves exact current duplicate and can undo with shuffle backup',
      () {
    final alias = QueueOccurrence('same');
    final active = QueueOccurrence('same');
    final after = QueueOccurrence('after');
    final items = [alias, active, after];
    final backup = [after, alias, active];
    final history = QueueEditHistory<QueueOccurrence<String>>();
    final trimmed = QueueEdit.trim(items, 1, before: true)!;
    expect(trimmed.items, [active, after]);
    expect(trimmed.currentIndex, 0);
    final retained = trimmed.items.map((e) => e.id).toSet();
    final nextBackup = backup.where((e) => retained.contains(e.id)).toList();
    history.record(QueueSnapshot(items, backup, 1),
        QueueSnapshot(trimmed.items, nextBackup, trimmed.currentIndex));
    final restored = history.undo(trimmed.items, nextBackup, 0)!;
    expect(restored.items, items);
    expect(restored.backup, backup);
    expect(restored.items[restored.currentIndex].id, active.id);
    final suffix = QueueEdit.trim(items, 1, before: false)!;
    expect(suffix.items, [alias, active]);
    expect(suffix.currentIndex, 1);
    expect(QueueEdit.trim(items, -1, before: true), isNull);
    expect(QueueEdit.trim(items, 0, before: true), isNull);
    expect(QueueEdit.trim(items, 2, before: false), isNull);
    expect(items, [alias, active, after]);
  });

  test('upcoming ordering preserves prefix, ties, unknowns and stop occurrence',
      () {
    final prefix = QueueOccurrence(CategoryTestAudio('prefix'));
    final active = QueueOccurrence(CategoryTestAudio('same', duration: 60));
    final long = QueueOccurrence(CategoryTestAudio('long', duration: 300));
    final short = QueueOccurrence(CategoryTestAudio('same', duration: 60));
    final equal = QueueOccurrence(CategoryTestAudio('same', duration: 60));
    final unknown = QueueOccurrence(CategoryTestAudio('unknown', duration: 0));
    final items = [prefix, active, unknown, long, short, equal];
    final stop = QueueStopBoundary()..arm(equal.id);
    addTearDown(stop.dispose);
    final edit = QueueEdit.orderUpcoming(items, 1,
        compare: (a, b) =>
            compareAudioSort(a.item, b.item, AudioSortField.duration))!;
    expect(edit.items, [prefix, active, short, equal, long, unknown]);
    expect(edit.currentIndex, 1);
    stop.retain(edit.items.map((e) => e.id));
    expect(stop.target, equal.id);
    expect(stop.active, isTrue);
    final reversed = QueueEdit.orderUpcoming(edit.items, 1, reverse: true)!;
    expect(reversed.items, [prefix, active, unknown, long, equal, short]);
    expect(
        QueueEdit.orderUpcoming(edit.items, 1,
            compare: (a, b) =>
                compareAudioSort(a.item, b.item, AudioSortField.duration)),
        isNull);
    stop.retain(
        QueueEdit.trim(items, 1, before: false)!.items.map((e) => e.id));
    expect(stop.active, isFalse);
    expect(stop.lastCancellation, QueueStopCancelReason.removed);
  });

  test(
      'queue clocks distinguish unknowns and count repeated and CUE descriptors',
      () {
    final first = CategoryTestAudio('first', duration: 3601);
    final unknown = CategoryTestAudio('unknown', duration: 0);
    final summary = QueueDurationSummary.of([first, first, unknown]);
    expect(summary.clock, '2:00:02');
    expect(summary.unknownCount, 1);
    expect(QueueDurationSummary.of([]).clock, '0:00');
    expect(
        QueueDurationSummary.of([CategoryTestAudio('short', duration: 59)])
            .clock,
        '0:59');
  });
}
