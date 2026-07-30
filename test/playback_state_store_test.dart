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
}
