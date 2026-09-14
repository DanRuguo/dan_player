import 'dart:async';
import 'dart:io';
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/audio_trim_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';

class _Transport extends ChangeNotifier {
  Object? track = Object();
  bool playing = true;
  double position = 12.5;
  int pauses = 0;
  int resumes = 0;
  void change({Object? newTrack, bool? newPlaying, double? newPosition}) {
    if (newTrack != null) track = newTrack;
    if (newPlaying != null) playing = newPlaying;
    if (newPosition != null) position = newPosition;
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
  void pause() {
    model.pauses++;
    model.change(newPlaying: false);
  }

  @override
  void resume() {
    model.resumes++;
    model.change(newPlaying: true);
  }

  @override
  void dispose() {
    model.removeListener(notifyListeners);
    super.dispose();
  }
}

class _Process implements TrimPreviewProcess {
  _Process({this.finishOnKill = true});
  final bool finishOnKill;
  final done = Completer<int>();
  int kills = 0;
  @override
  Future<int> get exitCode => done.future;
  @override
  void kill() {
    kills++;
    if (finishOnKill && !done.isCompleted) done.complete(0);
  }
}

Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.value();
  }
}

void main() {
  test(
      'bundled ffplay previews a generated local file muted and exits at selection end',
      () async {
    final folder =
        await Directory('.dart_tool/test-data').create(recursive: true);
    final scratch = await folder.createTemp('trim-preview-');
    final source = '${scratch.absolute.path}/静音 & preview.wav';
    final savedVolume = AppPreference.instance.playbackPref.volumeDsp;
    AppPreference.instance.playbackPref.volumeDsp = 0;
    final preview = ProcessAudioTrimPreview(
        CategoryTestAudio('Synthetic', path: source),
        mainPlayback: () => null);
    try {
      await runAudioTool('ffmpeg', [
        '-v',
        'error',
        '-nostdin',
        '-f',
        'lavfi',
        '-i',
        'anullsrc=r=44100:cl=stereo',
        '-t',
        '2',
        '-y',
        source
      ]);
      await preview.play(.4, .7);
      // Wait for the native decoder to stop, not merely for process launch.
      while (preview.playing || preview.loading) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      expect(preview.error, isNull);
    } finally {
      await preview.stop();
      preview.dispose();
      AppPreference.instance.playbackPref.volumeDsp = savedVolume;
      await scratch.delete(recursive: true);
    }
  },
      skip: Platform.environment['DAN_PLAYER_FFMPEG_DIR'] == null,
      timeout: const Timeout(Duration(seconds: 20)));

  test('preview argv respects mute and saved volume without shell/network', () {
    for (final pair in [(0.0, '0'), (.3, '30'), (1.7, '100')]) {
      final args = trimPreviewArguments(r'J:/music/中 文 & $ song.mp3', 1.25, 3.5,
          volume: pair.$1);
      expect(args[args.indexOf('-volume') + 1], pair.$2);
      expect(args[args.indexOf('-protocol_whitelist') + 1], 'file,pipe');
      expect(args[args.indexOf('-ss') + 1], '1.250000');
      expect(args[args.indexOf('-t') + 1], '3.500000');
      expect(args.last, r'J:/music/中 文 & $ song.mp3');
    }
  });

  test('preview pauses and resumes only the unchanged main playback', () async {
    final main = _Transport();
    final process = _Process();
    final preview = ProcessAudioTrimPreview(CategoryTestAudio('sample'),
        mainPlayback: () => _Main(main),
        launch: (file, start, duration) async {
          expect(start, 2.25);
          expect(duration, 4.5);
          return process;
        });
    await preview.play(2.25, 6.75);
    expect(main.playing, isFalse);
    expect(main.pauses, 1);
    expect(preview.playing, isTrue);
    process.done.complete(0);
    await _flush();
    expect(main.playing, isTrue);
    expect(main.resumes, 1);
    expect(main.position, 12.5);
    expect(preview.playing, isFalse);
    preview.dispose();
    main.dispose();
  });

  for (final action in ['track', 'seek', 'play']) {
    test('main $action action stops preview and never restores stale state',
        () async {
      final main = _Transport();
      final process = _Process();
      final preview = ProcessAudioTrimPreview(CategoryTestAudio('sample'),
          mainPlayback: () => _Main(main),
          launch: (_, __, ___) async => process);
      await preview.play(0, 5);
      if (action == 'track') main.change(newTrack: Object());
      if (action == 'seek') main.change(newPosition: 35);
      if (action == 'play') main.change(newPlaying: true);
      await _flush();
      expect(process.kills, greaterThan(0));
      expect(preview.playing, isFalse);
      expect(main.resumes, 0);
      preview.dispose();
      main.dispose();
    });
  }

  test(
      'paused main stays paused; decoder failure is visible without audio changes',
      () async {
    final main = _Transport()..playing = false;
    final preview = ProcessAudioTrimPreview(CategoryTestAudio('sample'),
        mainPlayback: () => _Main(main),
        launch: (_, __, ___) async => throw StateError('device'));
    await preview.play(0, 5);
    expect(preview.error, isNotNull);
    expect(main.pauses, 0);
    expect(main.resumes, 0);
    expect(main.playing, isFalse);
    preview.dispose();
    main.dispose();
  });

  test(
      'stop during launch waits for the late process exit before saving can proceed',
      () async {
    final main = _Transport();
    final launched = Completer<TrimPreviewProcess>();
    final process = _Process(finishOnKill: false);
    final preview = ProcessAudioTrimPreview(CategoryTestAudio('sample'),
        mainPlayback: () => _Main(main),
        launch: (_, __, ___) => launched.future);
    final play = preview.play(0, 5);
    await _flush();
    var stopped = false;
    final stop = preview.stop().then((_) => stopped = true);
    await _flush();
    expect(stopped, isFalse);
    launched.complete(process);
    await _flush();
    expect(process.kills, greaterThan(0));
    expect(stopped, isFalse);
    expect(main.resumes, 0);
    process.done.complete(0);
    await Future.wait([stop, play]);
    expect(stopped, isTrue);
    expect(main.resumes, 1);
    preview.dispose();
    main.dispose();
  });

  test(
      'rapid preview requests start only the latest selection and disposal reaps it',
      () async {
    final launched = <_Process>[];
    final ranges = <double>[];
    final preview = ProcessAudioTrimPreview(CategoryTestAudio('sample'),
        mainPlayback: () => null,
        launch: (_, start, __) async {
          ranges.add(start);
          final process = _Process();
          launched.add(process);
          return process;
        });
    await Future.wait(
        [preview.play(1, 3), preview.play(4, 6), preview.play(7, 9)]);
    expect(ranges, [7]);
    expect(preview.playing, isTrue);
    preview.dispose();
    await _flush();
    expect(launched.single.kills, greaterThan(0));
  });
}
