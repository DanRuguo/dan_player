import 'package:dan_player/play_service/playback_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Only mode writes are permitted: accidental playback/queue calls fail loudly.
class PlaybackModeFixture extends Fake implements PlaybackService {
  @override
  final shuffle = ValueNotifier(false);
  @override
  final playMode = ValueNotifier(PlayMode.forward);
  final calls = <String>[];

  @override
  void useShuffle(bool flag) {
    calls.add('shuffle:$flag');
    shuffle.value = flag;
  }

  @override
  void setPlayMode(PlayMode mode) {
    calls.add('repeat:${mode.name}');
    playMode.value = mode;
  }

  @override
  void dispose() {
    shuffle.dispose();
    playMode.dispose();
  }
}
