import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/play_service/queue_edits.dart';
import 'package:dan_player/play_service/queue_track_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

void main() {
  test('normalized local aliases preserve the exact active object and order',
      () {
    final first = CategoryTestAudio('first', path: r'C:\Music\Same.mp3');
    final current = CategoryTestAudio('active', path: 'c:/music/a/../same.MP3');
    final other = CategoryTestAudio('other');
    final last = CategoryTestAudio('last');
    final queue = [first, other, current, first, last, other];
    final edit = QueueEdit.deduplicate(queue, 2, keyOf: queueTrackIdentity)!;
    expect(edit.items, [other, current, last]);
    expect(edit.currentIndex, 1);
    expect(edit.items[1], same(current));
    expect(queue.length, 6);
    final backup = QueueEdit.deduplicatedBackup(
        [last, first, current, other, first, other], edit.items,
        keyOf: queueTrackIdentity);
    expect(backup, [last, current, other]);
    final history = QueueEditHistory<Audio>();
    final originalBackup = [last, first, current, other, first, other];
    history.record(QueueSnapshot(queue, originalBackup, 2),
        QueueSnapshot(edit.items, backup, edit.currentIndex));
    final restored = history.undo(edit.items, backup, 1)!;
    expect(restored.items, queue);
    expect(restored.backup, originalBackup);
    expect(restored.currentIndex, 2);
  });

  test('UNC casing and dot segments deduplicate without opening files', () {
    final first =
        CategoryTestAudio('one', path: r'\\NAS\Music\a\..\Canon.flac');
    final alias = CategoryTestAudio('two', path: '//nas/music/canon.FLAC');
    final otherShare =
        CategoryTestAudio('three', path: '//nas/other/canon.FLAC');
    final edit = QueueEdit.deduplicate([first, alias, otherShare], -1,
        keyOf: queueTrackIdentity)!;
    expect(edit.items, [first, otherShare]);
    expect(edit.currentIndex, -1);
  });

  test('online provider and id are exact and independent of titles', () {
    Audio online(String provider, String id, String title) => Audio.online(
        provider: provider,
        id: id,
        title: title,
        artist: 'Artist',
        album: 'Album',
        duration: 100);
    final first = online('qq', 'a', 'Same');
    final alias = online('qq', 'a', 'New title');
    final caseSensitive = online('qq', 'A', 'Same');
    final provider = online('netease', 'a', 'Same');
    final edit = QueueEdit.deduplicate(
        [first, alias, caseSensitive, provider], 1,
        keyOf: queueTrackIdentity)!;
    expect(edit.items, [alias, caseSensitive, provider]);
    expect(edit.currentIndex, 0);
  });

  test(
      'CUE tracks sharing an audio file remain distinct from each other and raw',
      () {
    Audio cue(int number) {
      final ref = CueTrackReference(
          cuePath: r'C:\Music\Album.cue',
          sourcePath: r'C:\Music\Album.flac',
          number: number,
          startFrame: number * 7500);
      return Audio('Track $number', 'Artist', 'Album', number, 100, null, null,
          ref.identity, 0, 0, 'CUE',
          cueTrack: ref);
    }

    final one = cue(1), two = cue(2), duplicate = cue(1);
    final raw = CategoryTestAudio('raw', path: r'C:\Music\Album.flac');
    final edit = QueueEdit.deduplicate([one, two, raw, duplicate], 3,
        keyOf: queueTrackIdentity)!;
    expect(edit.items, [two, raw, duplicate]);
    expect(edit.currentIndex, 2);
  });

  test('empty, unique and invalid selections are no-ops', () {
    for (final (items, index) in [
      (<String>[], -1),
      (['a', 'b'], 1),
      (['a', 'a'], -2),
      (['a', 'a'], 2),
    ]) {
      expect(
          QueueEdit.deduplicate(items, index, keyOf: (item) => item), isNull);
    }
    final history = QueueEditHistory<String>();
    history.record(QueueSnapshot(['a', 'b'], ['a', 'b'], 0),
        QueueSnapshot(['a'], ['a'], 0));
    expect(QueueEdit.deduplicate(['a'], 0, keyOf: (item) => item), isNull);
    expect(history.length, 1);
  });
}
