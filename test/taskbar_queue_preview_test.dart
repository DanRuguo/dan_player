import 'package:dan_player/play_service/playback_modes.dart';
import 'package:dan_player/play_service/taskbar_queue_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview follows the committed suffix and natural repeat policy', () {
    expect(
        knownNextQueueIndex(
            length: 4,
            currentIndex: 1,
            playMode: PlayMode.forward,
            shuffle: false),
        2);
    expect(
        knownNextQueueIndex(
            length: 4,
            currentIndex: 1,
            playMode: PlayMode.forward,
            shuffle: true),
        2);
    expect(
        knownNextQueueIndex(
            length: 4,
            currentIndex: 3,
            playMode: PlayMode.forward,
            shuffle: false),
        isNull);
    expect(
        knownNextQueueIndex(
            length: 4,
            currentIndex: 3,
            playMode: PlayMode.loop,
            shuffle: false),
        0);
    expect(
        knownNextQueueIndex(
            length: 4,
            currentIndex: 2,
            playMode: PlayMode.singleLoop,
            shuffle: true),
        2);
  });

  test('random wraparound is unknown except for a single possible song', () {
    expect(
        knownNextQueueIndex(
            length: 4, currentIndex: 3, playMode: PlayMode.loop, shuffle: true),
        isNull);
    expect(
        knownNextQueueIndex(
            length: 1, currentIndex: 0, playMode: PlayMode.loop, shuffle: true),
        0);
  });

  test('stop targets suspension and practice take precedence over repeat', () {
    for (final mode in PlayMode.values) {
      expect(
          knownNextQueueIndex(
              length: 3,
              currentIndex: 1,
              playMode: mode,
              shuffle: false,
              stopAtCurrent: true),
          isNull);
      expect(
          knownNextQueueIndex(
              length: 3,
              currentIndex: 1,
              playMode: mode,
              shuffle: false,
              canAdvance: false),
          isNull);
      expect(
          knownNextQueueIndex(
              length: 3,
              currentIndex: 1,
              playMode: mode,
              shuffle: false,
              repeatingSegment: true),
          isNull);
    }
  });

  test('empty or uncommitted occurrences cannot advertise a next song', () {
    for (final size in [0, 3]) {
      for (final index in [-1, size]) {
        expect(
            knownNextQueueIndex(
                length: size,
                currentIndex: index,
                playMode: PlayMode.loop,
                shuffle: true),
            isNull);
      }
    }
  });
}
