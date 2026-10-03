import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:dan_player/play_service/taskbar_queue_preview.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/taskbar_lyric_service.dart';
import 'package:dan_player/taskbar_lyrics_publisher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _Audio extends Fake implements Audio {
  _Audio(this.displayTitle);
  @override
  String displayTitle;
}

class _Playback extends ChangeNotifier implements PlaybackService {
  final positions = StreamController<double>.broadcast();
  final states = StreamController<PlayerState>.broadcast();
  @override
  final ValueNotifier<Object> playbackIntent = ValueNotifier<Object>(0);
  @override
  final playbackRate = ValueNotifier(1.0);
  @override
  final resolvingAudioPath = ValueNotifier<String?>(null);
  @override
  final isBuffering = ValueNotifier(false);
  @override
  final isChangingOutput = ValueNotifier(false);
  @override
  final playlist = ValueNotifier<List<Audio>>([]);
  @override
  final playMode = ValueNotifier(PlayMode.forward);
  @override
  final shuffle = ValueNotifier(false);
  @override
  final stopAfterCurrent = ValueNotifier(false);
  @override
  final segmentLoop = SegmentLoopController();
  @override
  int playbackSessionToken = 1;
  @override
  Audio? nowPlaying = _Audio('a');
  @override
  double position = 0;
  @override
  double get length => 12;
  @override
  PlayerState playerState = PlayerState.playing;
  @override
  Audio? get nextAutomaticQueueAudio {
    final next = _nextAutomaticQueueAudio;
    if (next == null) return null;
    final queue = [nowPlaying!, next];
    final index = knownNextQueueIndex(
        length: queue.length,
        currentIndex: 0,
        playMode: playMode.value,
        shuffle: shuffle.value,
        stopAtCurrent: stopAfterCurrent.value,
        repeatingSegment: segmentLoop.enabled);
    return index == null ? null : queue[index];
  }

  Audio? _nextAutomaticQueueAudio;
  set nextAutomaticQueueAudio(Audio? value) => _nextAutomaticQueueAudio = value;
  @override
  Stream<double> get positionStream => positions.stream;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  Future<void> cleanUp() async {
    await positions.close();
    await states.close();
    playbackIntent.dispose();
    playbackRate.dispose();
    resolvingAudioPath.dispose();
    isBuffering.dispose();
    isChangingOutput.dispose();
    playlist.dispose();
    playMode.dispose();
    shuffle.dispose();
    stopAfterCurrent.dispose();
    segmentLoop.dispose();
    dispose();
  }
}

class _Lyrics extends ChangeNotifier implements LyricService {
  final lines = StreamController<int>.broadcast();
  @override
  Future<Lyric?> currLyricFuture = Future.value(PlainLyric('a lyric'));
  @override
  int resolutionGeneration = 1;
  @override
  Stream<int> get lyricLineStream => lines.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void use(Future<Lyric?> future) {
    currLyricFuture = future;
    resolutionGeneration++;
    notifyListeners();
  }

  Future<void> cleanUp() async {
    await lines.close();
    dispose();
  }
}

class _Rig {
  _Rig() {
    final service = PlayService.forTesting(
      readiness: readiness,
      createPlayback: (_) => playback,
      createLyric: (_) => lyrics,
      createDesktopLyric: (_) => throw StateError('Unexpected desktop helper'),
    );
    source = playerTaskbarLyricSourceForTesting(service);
    publisher = TaskbarLyricsPublisher(
      source: source,
      elapsed: () => elapsed,
      appearance: () => const TaskbarLyricAppearance(
          accent: 0xff123456, fontFamily: 'fixture', fontPath: ''),
      send: (frame) async => writes.add(frame),
      onError: (error, trace) => fail('$error\n$trace'),
    );
  }
  final readiness = PlaybackReadiness();
  final libraryRevision = AudioLibrary.changes.value;
  final playback = _Playback();
  final lyrics = _Lyrics();
  final writes = <Map<String, Object>>[];
  Duration elapsed = Duration.zero;
  late final TaskbarLyricSource source;
  late final TaskbarLyricsPublisher publisher;
  bool sourceDisposed = false;

  Future<void> dispose() async {
    await publisher.close();
    if (!sourceDisposed) {
      source.dispose();
      sourceDisposed = true;
    }
    await lyrics.cleanUp();
    await playback.cleanUp();
    readiness.dispose();
    AudioLibrary.changes.value = libraryRevision;
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real adapter hides retained source through a slow session handoff',
      () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    await _flush();
    expect(rig.writes.last['text'], 'a lyric');
    final oldRefresh = Completer<Lyric?>();
    rig.lyrics.use(oldRefresh.future);
    await _flush();
    expect(rig.writes.last['text'], 'a lyric');

    rig.playback.playbackSessionToken++;
    rig.playback.playbackIntent.value = 1;
    rig.playback.resolvingAudioPath.value = 'new-session-b.wav';
    await _flush();
    expect(rig.source.hasTrack, false);
    expect(rig.writes.last['text'], '');
    final clearCount = rig.writes.length;
    oldRefresh.complete(PlainLyric('late old a'));
    await _flush();
    expect(rig.writes.length, clearCount);
    expect(rig.writes.any((frame) => frame['text'] == 'late old a'), false);

    rig.lyrics.use(Future.value(PlainLyric('b lyric')));
    rig.playback.nowPlaying = _Audio('b');
    rig.playback.resolvingAudioPath.value = null;
    await _flush();
    expect(rig.source.hasTrack, true);
    expect(rig.writes.last['text'], 'b lyric');
    expect(
        rig.writes
            .skip(clearCount)
            .any((frame) => frame['text'] == 'late old a'),
        false);
    final stableCount = rig.writes.length;
    final stable = rig.writes.last;
    rig.playback.position = .4;
    rig.elapsed = const Duration(milliseconds: 400);
    rig.playback.positions.add(.4);
    await _flush();
    expect(rig.writes.last['text'], 'b lyric');
    expect(rig.writes.last['sourceIdentity'], stable['sourceIdentity']);
    expect(rig.writes.last['timelineRevision'], stable['timelineRevision']);
    expect(rig.writes.skip(stableCount).every((frame) => frame['text'] != ''),
        true);
  });

  test('real adapter publishes queue metadata and detaches all new observers',
      () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    await _flush();
    expect(rig.writes.last['nextTrackText'], '');
    rig.playback.nextAutomaticQueueAudio = _Audio('next 😀');
    rig.playback.playlist.value = [rig.playback.nowPlaying!, _Audio('next 😀')];
    await _flush();
    expect(rig.writes.last['nextTrackText'], '下一首：next 😀');
    expect(rig.writes.last['showPauseIndicator'], true);
    rig.playback.playerState = PlayerState.paused;
    rig.playback.states.add(PlayerState.paused);
    await _flush();
    expect(rig.writes.last['playing'], false);
    expect(rig.writes.last['paused'], true);
    rig.playback.playerState = PlayerState.stalled;
    rig.playback.states.add(PlayerState.stalled);
    await _flush();
    expect(rig.writes.last['playing'], false);
    expect(rig.writes.last['paused'], false);
    expect(rig.writes.last['showPauseIndicator'], true);
    rig.playback.playerState = PlayerState.pausedDevice;
    rig.playback.states.add(PlayerState.pausedDevice);
    await _flush();
    expect(rig.writes.last['paused'], true);
    rig.playback.playerState = PlayerState.unknown;
    rig.playback.states.add(PlayerState.unknown);
    await _flush();
    expect(rig.writes.last['paused'], false);
    rig.playback.nextAutomaticQueueAudio = null;
    rig.playback.stopAfterCurrent.value = true;
    await _flush();
    expect(rig.writes.last['nextTrackText'], '');

    await rig.publisher.close();
    rig.source.dispose();
    rig.sourceDisposed = true;
    final afterClose = rig.writes.length;
    // Any forgotten observer calls notifyListeners on the disposed adapter
    // and fails this test, even though the closed publisher ignores callbacks.
    rig.playback.resolvingAudioPath.value = 'late-source';
    rig.playback.isBuffering.value = true;
    rig.playback.isChangingOutput.value = true;
    rig.playback.playlist.value = [];
    rig.playback.playMode.value = PlayMode.loop;
    rig.playback.shuffle.value = true;
    rig.playback.stopAfterCurrent.value = false;
    rig.playback.segmentLoop.setStart(0, 12);
    AudioLibrary.changes.value++;
    await _flush();
    expect(rig.writes.length, afterClose);
  });

  test('paused real adapter reacts to practice and next-only metadata changes',
      () async {
    final rig = _Rig();
    final beforeLibraryChange = AudioLibrary.changes.value;
    addTearDown(() async {
      await rig.dispose();
      AudioLibrary.changes.value = beforeLibraryChange;
    });
    final next = _Audio('Original next');
    rig.playback.playerState = PlayerState.paused;
    rig.playback.nextAutomaticQueueAudio = next;
    await _flush();
    expect(rig.writes.last['nextTrackText'], '下一首：Original next');
    final sourceIdentity = rig.writes.last['sourceIdentity'];
    final timelineRevision = rig.writes.last['timelineRevision'];
    rig.playback.segmentLoop.setStart(0, 12);
    rig.playback.segmentLoop.setEnd(2, 12);
    rig.playback.segmentLoop.setEnabled(true);
    await _flush();
    expect(rig.writes.last['nextTrackText'], '');
    rig.playback.segmentLoop.setEnabled(false);
    await _flush();
    expect(rig.writes.last['nextTrackText'], '下一首：Original next');

    // The real metadata synchronizer rebuilds derived collections and publishes
    // AudioLibrary.changes. No current-track or queue notification is emitted.
    next.displayTitle = 'Edited next 😀';
    AudioLibrary.changes.value++;
    await _flush();
    expect(rig.writes.last['nextTrackText'], '下一首：Edited next 😀');
    expect(rig.writes.last['playing'], false);
    expect(rig.writes.last['paused'], true);
    expect(rig.writes.last['sourceIdentity'], sourceIdentity);
    expect(rig.writes.last['timelineRevision'], timelineRevision);
  });
}
