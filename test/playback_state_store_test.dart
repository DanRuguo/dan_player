import 'package:dan_player/play_service/playback_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("parses a valid playback state", () {
    final state = SavedPlaybackState.fromMap({
      "queuePaths": ["a.mp3", "b.mp3"],
      "backupPaths": ["b.mp3", "a.mp3"],
      "index": 1,
      "position": 42,
      "shuffle": true,
    });

    expect(state, isNotNull);
    expect(state!.queuePaths, ["a.mp3", "b.mp3"]);
    expect(state.backupPaths, ["b.mp3", "a.mp3"]);
    expect(state.index, 1);
    expect(state.position, 42.0);
    expect(state.shuffle, isTrue);
  });

  test("rejects a playback state without usable paths", () {
    expect(SavedPlaybackState.fromMap({"queuePaths": []}), isNull);
    expect(
      SavedPlaybackState.fromMap({
        "queuePaths": [1, null],
      }),
      isNull,
    );
  });

  test('invalid prefix values cannot move saved progress to a later track', () {
    final state = SavedPlaybackState.fromMap({
      'queuePaths': [null, 'a.mp3', 'b.mp3'],
      'index': 1,
      'position': 42,
    })!;
    expect(state.queuePaths, ['a.mp3', 'b.mp3']);
    expect(state.index, 0);
    expect(state.queuePaths[state.index], 'a.mp3');
    expect(state.position, 42);
  });

  test('filtering invalid values preserves the selected duplicate occurrence',
      () {
    final state = SavedPlaybackState.fromMap({
      'queuePaths': ['a.mp3', 7, 'b.mp3', 'a.mp3', null],
      'index': 3,
      'position': 42,
    })!;
    expect(state.queuePaths, ['a.mp3', 'b.mp3', 'a.mp3']);
    expect(state.index, 2);
    expect(state.position, 42);
  });

  test('a discarded saved occurrence cannot lend progress to a surviving one',
      () {
    for (final index in [1, -1, 3, 100]) {
      final state = SavedPlaybackState.fromMap({
        'queuePaths': ['a.mp3', null, 'b.mp3'],
        'index': index,
        'position': 42,
      })!;
      expect(state.index, -1, reason: 'saved index $index');
      expect(state.position, 0, reason: 'saved index $index');
    }
  });
}
