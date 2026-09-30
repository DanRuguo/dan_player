import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_trim_preview.dart';
import 'package:dan_player/lyric/lyric_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport extends ChangeNotifier {
  final track = Object();
  bool playing = true;
  double position = 12;
  int commands = 0, seeks = 0, resumed = 0;
  Object get intent => (commands, seeks);

  void pauseInternally() {
    playing = false;
    notifyListeners();
  }

  void command(String action) {
    if (action == 'seek same' || action == 'seek nearby') {
      seeks++;
      if (action == 'seek nearby') position += .1;
    } else {
      commands++;
      playing = false;
    }
    notifyListeners();
  }

  void sample() {
    position += .01;
    notifyListeners();
  }
}

class _Main extends TrimMainPlayback {
  _Main(this.model) {
    model.addListener(notifyListeners);
  }
  final _Transport model;
  @override
  Object? get track => model.track;
  @override
  bool get playing => model.playing;
  @override
  double get position => model.position;
  @override
  Object get intent => model.intent;
  @override
  void pause() => model.pauseInternally();
  @override
  void resume() {
    model.resumed++;
    model.playing = true;
    model.notifyListeners();
  }

  @override
  void dispose() {
    model.removeListener(notifyListeners);
    super.dispose();
  }
}

class _Process implements TrimPreviewProcess {
  final done = Completer<int>();
  int kills = 0;
  @override
  Future<int> get exitCode => done.future;
  @override
  void kill() {
    kills++;
    if (!done.isCompleted) done.complete(0);
  }
}

Audio _audio() => Audio('Song', 'Artist', 'Album', 0, 20, null, null,
    'synthetic-preview.wav', 0, 0, null);

Future<void> _flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final lyric in [false, true]) {
    final kind = lyric ? 'lyric' : 'trim';
    for (final action in ['pause', 'stop', 'seek same', 'seek nearby']) {
      test('$kind preview preserves an explicit same-state $action', () async {
        final model = _Transport(), process = _Process();
        final preview = lyric
            ? LyricAudioPreview(_audio(),
                mainPlayback: () => _Main(model),
                launch: (_, __, ___, ____) async => process)
            : ProcessAudioTrimPreview(_audio(),
                mainPlayback: () => _Main(model),
                launch: (_, __, ___) async => process);
        try {
          if (preview is LyricAudioPreview) {
            await preview.play(0, 10);
          } else {
            await (preview as ProcessAudioTrimPreview).play(0, 10);
          }
          expect(model.playing, isFalse);
          model.command(action);
          await _flush();
          expect(process.kills, greaterThan(0),
              reason: 'The user command must stop temporary audio immediately');
          if (preview is LyricAudioPreview) {
            await preview.close();
          } else {
            await (preview as ProcessAudioTrimPreview).stop();
          }
          expect(model.resumed, 0);
          expect(model.playing, isFalse);
          expect(model.position, action == 'seek nearby' ? 12.1 : 12);
        } finally {
          preview.dispose();
          await _flush();
          model.dispose();
        }
      });
    }

    test('$kind normal position notifications preserve preview ownership',
        () async {
      final model = _Transport(), process = _Process();
      final preview = lyric
          ? LyricAudioPreview(_audio(),
              mainPlayback: () => _Main(model),
              launch: (_, __, ___, ____) async => process)
          : ProcessAudioTrimPreview(_audio(),
              mainPlayback: () => _Main(model),
              launch: (_, __, ___) async => process);
      try {
        if (preview is LyricAudioPreview) {
          await preview.play(0, 10);
        } else {
          await (preview as ProcessAudioTrimPreview).play(0, 10);
        }
        model.sample();
        await _flush();
        expect(process.kills, 0);
        if (preview is LyricAudioPreview) {
          await preview.close();
        } else {
          await (preview as ProcessAudioTrimPreview).stop();
        }
        expect(model.resumed, 1);
        expect(model.playing, isTrue);
      } finally {
        preview.dispose();
        await _flush();
        model.dispose();
      }
    });

    test('$kind pause during late decoder close cancels deferred restoration',
        () async {
      final model = _Transport(), process = _Process();
      final pending = Completer<TrimPreviewProcess>();
      final preview = lyric
          ? LyricAudioPreview(_audio(),
              mainPlayback: () => _Main(model),
              launch: (_, __, ___, ____) => pending.future)
          : ProcessAudioTrimPreview(_audio(),
              mainPlayback: () => _Main(model),
              launch: (_, __, ___) => pending.future);
      try {
        final play = preview is LyricAudioPreview
            ? preview.play(0, 10)
            : (preview as ProcessAudioTrimPreview).play(0, 10);
        await _flush();
        final closing = preview is LyricAudioPreview
            ? preview.close()
            : (preview as ProcessAudioTrimPreview).stop();
        model.command('pause');
        pending.complete(process);
        await play;
        await closing;
        expect(process.kills, greaterThan(0));
        expect(model.resumed, 0);
        expect(model.playing, isFalse);
      } finally {
        if (!pending.isCompleted) pending.complete(process);
        preview.dispose();
        await _flush();
        model.dispose();
      }
    });
  }
}
