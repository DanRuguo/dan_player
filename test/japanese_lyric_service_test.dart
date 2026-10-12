import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/japanese_lyric_readings.dart';
import 'package:dan_player/lyric/japanese_lyric_cache.dart';
import 'package:dan_player/lyric/japanese_phonetic_channel.dart';
import 'package:dan_player/lyric/japanese_online_readings.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:dan_player/lyric/japanese_reading_analyzer.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/online_lyric_cache.dart';
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/taskbar_lyric_service.dart';
import 'package:dan_player/taskbar_lyrics_publisher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';

class _Audio extends Fake implements Audio {
  _Audio(this.id);
  final String id;
  @override
  String? language;
  @override
  String get path => 'synthetic-japanese-$id-not-opened.wav';
  @override
  String get stableTrackId => 'synthetic-japanese-$id';
  @override
  bool get isOnline => false;
}

class _Playback extends ChangeNotifier implements PlaybackService {
  final positions = StreamController<double>.broadcast(sync: true);
  final states = StreamController<PlayerState>.broadcast(sync: true);
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
  final audio = _Audio('one');
  late Audio? active = audio;
  double at = 0;
  @override
  Stream<double> get positionStream => positions.stream;
  @override
  Audio? get nowPlaying => active;
  @override
  double get position => at;
  @override
  int get playbackSessionToken => 1;
  PlayerState currentState = PlayerState.playing;
  @override
  PlayerState get playerState => currentState;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  double get length => 10;
  @override
  Audio? get nextAutomaticQueueAudio => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<void> close() async {
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

class _Desktop extends Fake implements DesktopLyricService {
  final sent = <LyricLine>[];
  var missing = 0;
  Completer<bool>? ready;
  @override
  Future<bool> get canSendMessage => ready?.future ?? Future.value(true);
  @override
  void sendPlaybackTimelineMessage() {}
  @override
  void sendNoLyricMessage() => missing++;
  @override
  void sendLyricLineMessage(LyricLine line, {required int lineIndex}) =>
      sent.add(line);
  @override
  void dispose() {}
  @override
  Future<void> flushAppearance() async {}
}

JapanesePhoneticBatch _read(List<String> text) => JapanesePhoneticBatch([
      for (final chunk in text)
        [JapanesePhoneticWord(chunk, chunk.replaceAll('漢', 'かん'))],
    ]);
Lyric _line(String text) =>
    Lrc([LrcLine(Duration.zero, text, isBlank: false)], LrcSource.web);

class _Rig {
  _Rig(
      {required JapaneseChunkAnalyzer analyze,
      LyricDocumentStore? documents,
      OnlineLyricCache? onlineCache,
      JapaneseReadingProjector? projector,
      Future<Lyric?> Function(Audio, bool Function())? online}) {
    facade = PlayService.forTesting(
      readiness: readiness,
      createPlayback: (_) => playback,
      createDesktopLyric: (_) => desktop,
      createLyric: (owner) => LyricService.forTesting(
        owner,
        resolveDefaultLyric: (_) {
          lookups++;
          return resolve();
        },
        documents: documents,
        onlineCache: onlineCache,
        onlineLookup: online,
        japanesePreferences: preferences,
        japaneseProjector: projector ??
            JapaneseReadingProjector(
                analyze: (chunks) {
                  analyses++;
                  return analyze(chunks);
                },
                cancel: () => cancellations++),
      ),
    );
    service = facade.lyricService;
  }
  final readiness = PlaybackReadiness();
  final playback = _Playback();
  final desktop = _Desktop();
  final preferences = ValueNotifier(const JapaneseReadingPreferences());
  Future<Lyric?> Function() resolve = () async => null;
  late final PlayService facade;
  late final LyricService service;
  var lookups = 0, analyses = 0, cancellations = 0;
  Future<void> close() async {
    await facade.close();
    await playback.positions.close();
    readiness.dispose();
    preferences.dispose();
  }
}

Future<void> _flush() async {
  for (var index = 0; index < 10; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _ModeProjector extends JapaneseReadingProjector {
  _ModeProjector() : super(analyze: (chunks) async => _read(chunks));
  final modes = <JapaneseReadingRequestMode>[];
  @override
  Future<JapaneseReadingProjection> project(Lyric source,
      {String? language,
      required bool enabled,
      bool force = false,
      JapaneseReadingRequestMode requestMode =
          JapaneseReadingRequestMode.automatic,
      required bool Function() stillCurrent}) {
    modes.add(requestMode);
    return super.project(source,
        language: language,
        enabled: enabled,
        force: force,
        requestMode: requestMode,
        stillCurrent: stillCurrent);
  }
}

class _FailingProjector extends JapaneseReadingProjector {
  _FailingProjector() : super(analyze: (_) => throw StateError('Not used'));
  final result = Completer<JapaneseReadingProjection>();
  @override
  Future<JapaneseReadingProjection> project(Lyric source,
          {String? language,
          required bool enabled,
          bool force = false,
          JapaneseReadingRequestMode requestMode =
              JapaneseReadingRequestMode.automatic,
          required bool Function() stillCurrent}) =>
      result.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool previousAutomatic;
  setUp(() {
    previousAutomatic = AppSettings.instance.automaticOnlineLyrics.value;
    AppSettings.instance.automaticOnlineLyrics.value = false;
  });
  tearDown(() =>
      AppSettings.instance.automaticOnlineLyrics.value = previousAutomatic);

  test('default off preserves canonical object without offline work', () async {
    final rig = _Rig(analyze: (_) => throw StateError('off'));
    addTearDown(rig.close);
    final source = _line('漢かな');
    rig.resolve = () async => source;
    rig.service.updateLyric();
    expect(await rig.service.currLyricFuture, same(source));
    expect(rig.service.rawCurrentLyric, same(source));
    expect(rig.analyses, 0);
    expect(rig.service.japaneseReadingsBusy.value, isFalse);
  });

  test('network gate change does not reuse prior manual online authorization',
      () async {
    AppSettings.instance.automaticOnlineLyrics.value = true;
    final projector = _ModeProjector();
    final rig = _Rig(
        analyze: (_) => throw StateError('not used'), projector: projector);
    addTearDown(rig.close);
    rig.service.useSpecificLyric(_line('漢かな'));
    await rig.service.currLyricFuture;
    expect(
        await rig.service.generateJapaneseReadingsForCurrentTrack(
            expectedGeneration: rig.service.resolutionGeneration,
            mode: JapaneseReadingRequestMode.online),
        JapaneseReadingResult.applied);
    expect(projector.modes, [JapaneseReadingRequestMode.online]);
    final generation = rig.service.resolutionGeneration;
    AppSettings.instance.automaticOnlineLyrics.value = false;
    await rig.service.currLyricFuture;
    expect(projector.modes, [
      JapaneseReadingRequestMode.online,
      JapaneseReadingRequestMode.automatic
    ]);
    expect(rig.service.resolutionGeneration, generation);
  });

  test(
      'Japanese preference change cannot renew completed manual online permission',
      () async {
    late _Rig rig;
    final requestedKeys = <String>[];
    final online =
        JapaneseOnlineReadingAnalyzer(request: (body, clientId, active) async {
      expect(active(), isTrue);
      requestedKeys.add(clientId);
      return {
        'jsonrpc': '2.0',
        'id': body['id'],
        'result': {
          'word': [
            {'surface': '漢', 'furigana': 'かん'},
            {'surface': 'かな'},
          ]
        },
      };
    });
    final policy = JapaneseReadingAnalyzerPolicy(
        onlineAllowed: () => AppSettings.instance.automaticOnlineLyrics.value,
        clientId: () => rig.preferences.value.yahooClientId,
        online: online,
        offline: (_) => throw StateError('No offline generation authorized'),
        cancelOffline: () {},
        hasDictionary: () =>
            throw StateError('No dictionary lookup authorized'));
    addTearDown(policy.dispose);
    final projector = JapaneseReadingProjector(
        policy: policy,
        // Keep this service fixture independent of durable cache/storage.
        analyze: (_) => throw StateError('Policy owns analysis'));
    rig = _Rig(
        analyze: (_) => throw StateError('not used'), projector: projector);
    addTearDown(rig.close);
    rig.preferences.value = const JapaneseReadingPreferences(
        enabled: true, yahooClientId: 'explicit-first-key');
    final raw = _line('漢かな');
    rig.service.useSpecificLyric(raw);
    expect(await rig.service.currLyricFuture, same(raw));
    expect(
        await rig.service.generateJapaneseReadingsForCurrentTrack(
            expectedGeneration: rig.service.resolutionGeneration,
            mode: JapaneseReadingRequestMode.online),
        JapaneseReadingResult.applied);
    expect(requestedKeys, ['explicit-first-key']);
    final generation = rig.service.resolutionGeneration;
    rig.preferences.value = const JapaneseReadingPreferences(
        enabled: true, yahooClientId: 'changed-without-new-permission');
    final refreshed = await rig.service.currLyricFuture;
    expect(requestedKeys, ['explicit-first-key']);
    expect(refreshed, same(raw));
    expect(rig.service.resolutionGeneration, generation);
    expect(rig.service.rawCurrentLyric, same(raw));
  });

  test('preference changes reuse raw lookup and share projected desktop line',
      () async {
    final rig = _Rig(analyze: (chunks) async => _read(chunks));
    addTearDown(rig.close);
    final source = _line('漢かな');
    rig.resolve = () async => source;
    rig.service.updateLyric();
    await rig.service.currLyricFuture;
    final generation = rig.service.resolutionGeneration;
    rig.preferences.value = const JapaneseReadingPreferences(enabled: true);
    final projected = await rig.service.currLyricFuture;
    await _flush();
    expect(projected!.lines.single.japaneseReading, 'かんかな');
    expect(rig.desktop.sent.last, same(projected.lines.single));
    expect(rig.service.rawCurrentLyric, same(source));
    expect(source.lines.single.japaneseReading, isNull);
    expect(rig.lookups, 1);
    expect(rig.service.resolutionGeneration, generation);
    rig.preferences.value = const JapaneseReadingPreferences();
    expect(await rig.service.currLyricFuture, same(source));
    expect(rig.lookups, 1);
  });

  test('toggle during explicit lookup preserves request owner and commits once',
      () async {
    final root = await Directory(
            'J:/temp/codex/software/danplayer/tool/qa-local/selection-folders-oct11/japanese/data')
        .create(recursive: true);
    final isolated = await root.createTemp('online-cache-');
    final cache = OnlineLyricCache(directory: () async => isolated);
    final pending = Completer<Lyric?>();
    var lookups = 0;
    late bool Function() current;
    final rig = _Rig(
        analyze: (chunks) async => _read(chunks),
        onlineCache: cache,
        online: (_, owner) {
          lookups++;
          current = owner;
          return pending.future;
        });
    addTearDown(() async {
      await rig.close();
      cache.changes.dispose();
      await isolated.delete(recursive: true);
    });
    rig.service.useOnlineLyric();
    await _flush();
    final generation = rig.service.resolutionGeneration;
    rig.preferences.value = const JapaneseReadingPreferences(enabled: true);
    expect(current(), isTrue);
    expect(rig.service.resolutionGeneration, generation);
    pending.complete(_line('漢かな'));
    final display = await rig.service.currLyricFuture;
    expect(display!.lines.single.japaneseReading, 'かんかな');
    expect(lookups, 1);
    expect(rig.service.rawCurrentLyric!.lines.single.japaneseReading, isNull);
    final saved =
        await cache.read(onlineLyricCacheIdentity(rig.playback.audio));
    expect(saved!.lines.single.japaneseReading, isNull);
  });

  test('track Japanese language metadata reaches the offline projector',
      () async {
    final rig = _Rig(analyze: (chunks) async => _read(chunks));
    addTearDown(rig.close);
    rig.playback.audio.language = 'jpn';
    rig.preferences.value = const JapaneseReadingPreferences(enabled: true);
    rig.service.useSpecificLyric(_line('漢字'));
    expect((await rig.service.currLyricFuture)!.lines.single.japaneseReading,
        'かん字');
    expect(rig.analyses, 1);
  });

  test('manual Han request deduplicates even while raw source is pending',
      () async {
    final raw = Completer<Lyric?>();
    final rig = _Rig(analyze: (chunks) async => _read(chunks));
    addTearDown(rig.close);
    rig.resolve = () => raw.future;
    rig.service.updateLyric();
    final generation = rig.service.resolutionGeneration;
    final first = rig.service.generateJapaneseReadingsForCurrentTrack(
        expectedGeneration: generation);
    final second = rig.service.generateJapaneseReadingsForCurrentTrack(
        expectedGeneration: generation);
    expect(second, same(first));
    raw.complete(_line('漢'));
    expect(await first, JapaneseReadingResult.applied);
    expect((await rig.service.currLyricFuture)!.lines.single.japaneseReading,
        'かん');
    expect(rig.preferences.value.enabled, isFalse);
    expect(rig.lookups, 1);
    expect(rig.analyses, 1);
  });

  test('showing completed readings preserves the current future and lines',
      () async {
    final rig = _Rig(analyze: (chunks) async => _read(chunks));
    addTearDown(rig.close);
    final raw = _line('漢かな');
    rig.service.useSpecificLyric(raw);
    await rig.service.currLyricFuture;
    final generation = rig.service.resolutionGeneration;
    expect(
        await rig.service.ensureJapaneseReadingsForCurrentTrack(
            expectedGeneration: generation),
        JapaneseReadingResult.applied);
    final future = rig.service.currLyricFuture;
    final display = await future;
    expect(display!.lines.single.japaneseReadingSpans, isNotEmpty);
    expect(
        await rig.service.ensureJapaneseReadingsForCurrentTrack(
            expectedGeneration: generation),
        JapaneseReadingResult.unchanged);
    expect(rig.service.currLyricFuture, same(future));
    expect(await rig.service.currLyricFuture, same(display));
    expect(rig.analyses, 1);
    expect(rig.service.japaneseReadingsBusy.value, isFalse);
    expect(rig.service.rawCurrentLyric, same(raw));
    expect(raw.lines.single.japaneseReadingSpans, isEmpty);
  });

  test('initial automatic readings publish offset text before projection ends',
      () async {
    AppSettings.instance.automaticOnlineLyrics.value = true;
    final directory = await Directory(
            'J:/temp/codex/software/danplayer/tool/qa-local/kana-reveal-blur-oct12/interaction/initial-service')
        .create(recursive: true);
    final isolated = await directory.createTemp('offset-');
    final store = LyricDocumentStore(storageDirectory: isolated);
    await store.load();
    final pending = Completer<JapanesePhoneticBatch>();
    final rig = _Rig(analyze: (_) => pending.future, documents: store);
    TaskbarLyricSource? taskbar;
    TaskbarLyricsPublisher? publisher;
    addTearDown(() async {
      await publisher?.close();
      taskbar?.dispose();
      await rig.close();
      store.dispose();
      await isolated.delete(recursive: true);
    });
    await store.edit(rig.playback.audio, '[00:02.00]漢かな\n[00:04.00]漢な');
    await store.setOffset(rig.playback.audio, 250);
    rig.playback.at = 4.5;
    rig.preferences.value = const JapaneseReadingPreferences(enabled: true);
    rig.service.updateLyric();
    final finalFuture = rig.service.currLyricFuture;
    var completed = false;
    unawaited(finalFuture.then((_) => completed = true));
    await _flush();
    final original = rig.service.currentPresentation!;
    expect(completed, isFalse,
        reason: 'The public future still represents the final projection');
    expect(rig.service.currLyricFuture, same(finalFuture));
    expect(original.lines[1].start, const Duration(milliseconds: 4250));
    expect(original.lines[1].japaneseReadingSpans, isEmpty);
    expect(rig.service.rawCurrentLyric!.lines[1].start,
        const Duration(seconds: 4));
    expect(rig.desktop.sent.last, same(original.lines[1]));
    final packets = <Map<String, Object>>[];
    taskbar = playerTaskbarLyricSourceForTesting(rig.facade);
    final availableFuture = taskbar.lyric;
    expect(taskbar.lyric, same(availableFuture),
        reason: 'The actual adapter retains its future ownership per document');
    expect(await availableFuture, same(original));
    publisher = TaskbarLyricsPublisher(
        source: taskbar,
        elapsed: () => const Duration(milliseconds: 400),
        appearance: () => const TaskbarLyricAppearance(
            accent: 0xff123456, fontFamily: 'fixture', fontPath: ''),
        send: (frame) async => packets.add(frame),
        onError: (error, stack) => fail('$error\n$stack'));
    await _flush();
    expect(packets.last['text'], '漢な',
        reason: 'Taskbar text must not wait for automatic reading generation');
    final identity = packets.last['sourceIdentity'];
    rig.playback.at = 4.6;
    rig.playback.positions.add(4.6);
    await _flush();
    expect(taskbar.lyric, same(availableFuture));
    expect(packets.last['sourceIdentity'], identity);
    final sends = rig.desktop.sent.length;
    await rig.service.syncDesktopLyric();
    expect(rig.desktop.sent.length, sends + 1,
        reason: 'A newly opened helper can synchronize the available text');
    expect(rig.desktop.sent.last, same(original.lines[1]));
    expect(rig.analyses, 1);
    pending.complete(_read(['漢かな', '漢な']));
    final projected = (await finalFuture)!;
    await _flush();
    expect(projected, same(rig.service.currentPresentation));
    expect(projected, isNot(same(original)));
    expect(projected.lines[1].start, original.lines[1].start);
    expect(projected.lines[1].japaneseReadingSpans, isNotEmpty);
    expect(rig.desktop.sent.last, same(projected.lines[1]));
    expect(await taskbar.lyric, same(projected));
    expect(taskbar.lyric, isNot(same(availableFuture)));
    expect(packets.last['text'], '漢な');
    expect(original.lines[1].japaneseReadingSpans, isEmpty);
    expect(rig.service.rawCurrentLyric!.lines[1].japaneseReading, isNull);
  });

  test('initial presentation cannot revive a replaced or disposed source',
      () async {
    AppSettings.instance.automaticOnlineLyrics.value = true;
    final lateRaw = Completer<Lyric?>();
    final lateReading = Completer<JapanesePhoneticBatch>();
    final rig = _Rig(analyze: (_) => lateReading.future);
    var closed = false;
    addTearDown(() async {
      if (!closed) await rig.close();
    });
    rig.preferences.value = const JapaneseReadingPreferences(enabled: true);
    rig.resolve = () => lateRaw.future;
    rig.service.updateLyric();
    final superseded = rig.service.currLyricFuture;
    expect(rig.service.currentPresentation, isNull);
    final replacement = _line('かな');
    rig.playback.active = _Audio('replacement');
    rig.service.useSpecificLyric(replacement);
    expect(await rig.service.currLyricFuture, same(replacement));
    await _flush();
    final sent = rig.desktop.sent.length;
    lateRaw.complete(_line('漢かな'));
    expect(await superseded, isNull);
    await _flush();
    expect(rig.service.currentPresentation, same(replacement));
    expect(rig.desktop.sent.length, sent);
    expect(rig.analyses, 0);
    final last = _line('漢かな');
    rig.service.useSpecificLyric(last);
    final disposed = rig.service.currLyricFuture;
    await _flush();
    expect(rig.service.currentPresentation, same(last));
    expect(rig.desktop.sent.last, same(last.lines.single));
    expect(rig.analyses, 1);
    final beforeClose = rig.desktop.sent.length;
    await rig.close();
    closed = true;
    lateReading.complete(_read(['漢かな']));
    expect(await disposed, isNull);
    await _flush();
    expect(rig.service.currentPresentation, isNull);
    expect(rig.desktop.sent.length, beforeClose);
  });

  test('current projection failure clears paused early taskbar presentation',
      () async {
    AppSettings.instance.automaticOnlineLyrics.value = true;
    final projector = _FailingProjector();
    final rig = _Rig(
        analyze: (_) => throw StateError('Projector owns work'),
        projector: projector);
    rig.playback.currentState = PlayerState.paused;
    final taskbar = playerTaskbarLyricSourceForTesting(rig.facade);
    final packets = <Map<String, Object>>[];
    final publisher = TaskbarLyricsPublisher(
        source: taskbar,
        elapsed: () => Duration.zero,
        appearance: () => const TaskbarLyricAppearance(
            accent: 0xff123456, fontFamily: 'fixture', fontPath: ''),
        send: (frame) async => packets.add(frame),
        onError: (error, stack) => fail('$error\n$stack'));
    addTearDown(() async {
      await publisher.close();
      taskbar.dispose();
      await rig.close();
    });
    rig.preferences.value = const JapaneseReadingPreferences(enabled: true);
    final raw = _line('漢かな');
    rig.service.useSpecificLyric(raw);
    final failedFuture = rig.service.currLyricFuture;
    final failure = StateError('Current derived projection failed');
    final observesFailure = expectLater(failedFuture, throwsA(same(failure)));
    await _flush();
    expect(rig.service.currentPresentation, same(raw));
    expect(packets.last['text'], '漢かな');
    expect(packets.last['paused'], isTrue);
    expect(rig.desktop.missing, 0);
    projector.result.completeError(failure);
    await observesFailure;
    await _flush();
    expect(rig.service.currentPresentation, isNull);
    expect(rig.service.currLyricFuture, same(failedFuture),
        reason:
            'Presentation notifications cannot replace the future contract');
    expect(packets.last['text'], '',
        reason: 'A paused source has no position tick to repair stale text');
    expect(packets.last['paused'], isTrue);
    expect(rig.desktop.missing, 1);
    final finished = packets.length;
    await _flush();
    expect(packets.length, finished);
    expect(raw.lines.single.japaneseReadingSpans, isEmpty);
  });

  test('same-source reading work keeps publishing the active playback line',
      () async {
    final pending = Completer<JapanesePhoneticBatch>();
    final rig = _Rig(analyze: (_) => pending.future);
    addTearDown(rig.close);
    final raw = Lrc([
      LrcLine(Duration.zero, '漢かな', isBlank: false),
      LrcLine(const Duration(seconds: 2), '漢な', isBlank: false),
    ], LrcSource.web);
    rig.service.useSpecificLyric(raw);
    await rig.service.currLyricFuture;
    await _flush();
    final request = rig.service.ensureJapaneseReadingsForCurrentTrack(
        expectedGeneration: rig.service.resolutionGeneration);
    await _flush();
    expect(rig.service.japaneseReadingsBusy.value, isTrue);
    rig.playback.at = 2.5;
    rig.playback.positions.add(2.5);
    await _flush();
    expect(rig.desktop.sent.last, same(raw.lines[1]),
        reason: 'Pending ruby must not suspend the existing lyric clock');
    pending.complete(_read(['漢かな', '漢な']));
    expect(await request, JapaneseReadingResult.applied);
    await _flush();
    final display = await rig.service.currLyricFuture;
    expect(rig.desktop.sent.last, same(display!.lines[1]));
    expect(display.lines[1].japaneseReadingSpans, isNotEmpty);
    expect(raw.lines[1].japaneseReading, isNull);
  });

  test('explicit generation retains its mode after a completed display',
      () async {
    final projector = _ModeProjector();
    final rig = _Rig(
        analyze: (_) => throw StateError('Projector owns analysis'),
        projector: projector);
    addTearDown(rig.close);
    rig.service.useSpecificLyric(_line('漢かな'));
    await rig.service.currLyricFuture;
    final generation = rig.service.resolutionGeneration;
    await rig.service
        .ensureJapaneseReadingsForCurrentTrack(expectedGeneration: generation);
    final completed = rig.service.currLyricFuture;
    expect(
        await rig.service.generateJapaneseReadingsForCurrentTrack(
            expectedGeneration: generation,
            mode: JapaneseReadingRequestMode.online),
        JapaneseReadingResult.applied);
    expect(projector.modes, [
      JapaneseReadingRequestMode.offline,
      JapaneseReadingRequestMode.online
    ]);
    expect(rig.service.currLyricFuture, isNot(same(completed)));
  });

  test('source change invalidates busy manual output and resets force intent',
      () async {
    final pending = Completer<JapanesePhoneticBatch>();
    final rig = _Rig(analyze: (_) => pending.future);
    addTearDown(rig.close);
    rig.service.useSpecificLyric(_line('漢'));
    await rig.service.currLyricFuture;
    final generation = rig.service.resolutionGeneration;
    final old = rig.service.generateJapaneseReadingsForCurrentTrack(
        expectedGeneration: generation);
    await _flush();
    expect(rig.service.japaneseReadingsBusy.value, isTrue);
    rig.playback.active = _Audio('two');
    final newer = _line('漢新');
    rig.service.useSpecificLyric(newer);
    expect(await rig.service.currLyricFuture, same(newer));
    pending.complete(_read(['漢']));
    expect(await old, JapaneseReadingResult.stale);
    expect(rig.cancellations, 1);
    expect(rig.analyses, 1);
    expect(rig.service.japaneseReadingsBusy.value, isFalse);
    await _flush();
    expect(rig.desktop.sent.last, same(newer.lines.single));
  });

  test(
      'presentation retarget cannot deduplicate a new manual request into old work',
      () async {
    final pending = Completer<JapanesePhoneticBatch>();
    var analyses = 0;
    final rig = _Rig(analyze: (chunks) {
      analyses++;
      return analyses == 1 ? pending.future : Future.value(_read(chunks));
    });
    addTearDown(rig.close);
    rig.service.useSpecificLyric(_line('漢'));
    await rig.service.currLyricFuture;
    final source = rig.service.resolutionGeneration;
    final old = rig.service
        .generateJapaneseReadingsForCurrentTrack(expectedGeneration: source);
    await _flush();
    rig.preferences.value = const JapaneseReadingPreferences(enabled: true);
    final current = rig.service
        .generateJapaneseReadingsForCurrentTrack(expectedGeneration: source);
    expect(current, isNot(same(old)));
    expect(await current, JapaneseReadingResult.applied);
    pending.complete(_read(['漢']));
    expect(await old, JapaneseReadingResult.stale);
    expect((await rig.service.currLyricFuture)!.lines.single.japaneseReading,
        'かん');
  });

  test('old presentation sync cannot republish after preference cancellation',
      () async {
    final pending = Completer<JapanesePhoneticBatch>();
    final rig = _Rig(analyze: (_) => pending.future);
    addTearDown(rig.close);
    rig.preferences.value = const JapaneseReadingPreferences(enabled: true);
    final source = _line('漢かな');
    rig.service.useSpecificLyric(source);
    rig.service.findCurrLyricLine();
    final oldSync = rig.service.syncDesktopLyric();
    await _flush();
    rig.preferences.value = const JapaneseReadingPreferences();
    expect(await rig.service.currLyricFuture, same(source));
    await _flush();
    final before = rig.desktop.sent.length;
    pending.complete(_read(['漢かな']));
    await oldSync;
    await _flush();
    expect(rig.desktop.sent.length, before);
    expect(rig.desktop.sent.last, same(source.lines.single));
  });

  test(
      'superseded pending source error cannot clear newer desktop presentation',
      () async {
    final raw = Completer<Lyric?>();
    final rig = _Rig(analyze: (chunks) async => _read(chunks));
    addTearDown(rig.close);
    rig.resolve = () => raw.future;
    rig.service.updateLyric();
    final oldSync = rig.service.syncDesktopLyric();
    rig.service.useSpecificLyric(_line('漢かな'));
    await rig.service.currLyricFuture;
    await _flush();
    final missing = rig.desktop.missing;
    raw.completeError(StateError('old source failed'));
    await oldSync;
    await _flush();
    expect(rig.desktop.missing, missing);
  });

  test(
      'projected readings never mutate saved document and retain applied offset',
      () async {
    final directory = await Directory(
            'J:/temp/codex/software/danplayer/tool/qa-local/selection-folders-oct11/japanese/data')
        .create(recursive: true);
    final isolated = await directory.createTemp('document-');
    final store = LyricDocumentStore(storageDirectory: isolated);
    await store.load();
    final rig =
        _Rig(analyze: (chunks) async => _read(chunks), documents: store);
    addTearDown(() async {
      await rig.close();
      store.dispose();
      await isolated.delete(recursive: true);
    });
    await store.edit(rig.playback.audio, '[00:02.00]漢かな');
    await store.setOffset(rig.playback.audio, 250);
    rig.service.updateLyric();
    final stored =
        await File('${isolated.path}/lyric_documents.json').readAsBytes();
    rig.preferences.value = const JapaneseReadingPreferences(enabled: true);
    final display = await rig.service.currLyricFuture;
    expect(display!.lines.single.japaneseReading, 'かんかな');
    expect(display.lines.single.start, const Duration(milliseconds: 2250));
    expect(rig.service.rawCurrentLyric!.lines.single.start,
        const Duration(seconds: 2));
    expect(rig.service.rawCurrentLyric!.lines.single.japaneseReading, isNull);
    expect(
        store
            .forAudio(rig.playback.audio)!
            .effective!
            .toLyric()
            .lines
            .single
            .japaneseReading,
        isNull);
    expect(await File('${isolated.path}/lyric_documents.json').readAsBytes(),
        stored);
  });

  test('close cancels native work and busy completion cannot revive service',
      () async {
    final pending = Completer<JapanesePhoneticBatch>();
    final rig = _Rig(analyze: (_) => pending.future);
    rig.preferences.value = const JapaneseReadingPreferences(enabled: true);
    rig.service.useSpecificLyric(_line('漢かな'));
    final old = rig.service.currLyricFuture;
    await _flush();
    final count = rig.desktop.sent.length;
    await rig.close();
    pending.complete(_read(['漢かな']));
    await old;
    await _flush();
    expect(rig.cancellations, 1);
    expect(rig.desktop.sent.length, count);
  });

  test('checked initial cache publishes readings once with generation off',
      () async {
    final previous = AppSettings.instance.desktopLyricAppearance.value;
    AppSettings.instance.desktopLyricAppearance.value =
        DesktopLyricAppearance.fromJson({
      ...DesktopLyricAppearance.defaults.toJson(),
      'showJapaneseReading': true,
    });
    addTearDown(
        () => AppSettings.instance.desktopLyricAppearance.value = previous);
    final root = await Directory(
            'J:/temp/codex/software/danplayer/tool/qa-local/blur-position-feedback-oct12/cache/service')
        .create(recursive: true);
    final isolated = await root.createTemp('initial-');
    final cache = JapaneseLyricReadingCache(
        directory: () async => isolated, engine: 'service-cache-v1');
    final raw = _line('日本語かな');
    await cache.write(
        cache.fingerprint(raw),
        {
          0: const JapaneseCachedReading('にほんごかな',
              [JapaneseLyricReadingSpan(start: 0, end: 3, text: 'にほんご')]),
        },
        stillCurrent: () => true);
    await cache.flush();
    var calls = 0;
    final rig = _Rig(
        analyze: (_) => throw StateError('Unused injected analyzer'),
        projector: JapaneseReadingProjector(
            cache: cache,
            analyze: (_) async {
              calls++;
              throw StateError('Restoring a display is not generation');
            }));
    TaskbarLyricSource? taskbar;
    TaskbarLyricsPublisher? publisher;
    addTearDown(() async {
      await publisher?.close();
      taskbar?.dispose();
      await rig.close();
      await cache.flush();
      await isolated.delete(recursive: true);
    });
    final published = <Lyric>[];
    rig.service.addListener(() {
      final display = rig.service.currentPresentation;
      if (display != null) published.add(display);
    });
    rig.resolve = () async => raw;
    rig.service.updateLyric();
    final finalFuture = rig.service.currLyricFuture;
    final display = (await finalFuture)!;
    await _flush();
    expect(rig.preferences.value.enabled, isFalse);
    expect(AppSettings.instance.automaticOnlineLyrics.value, isFalse);
    expect(calls, 0);
    expect(published, isNotEmpty);
    expect(
        published.every(
            (value) => value.lines.single.japaneseReadingSpans.isNotEmpty),
        isTrue,
        reason: 'A cached initial song must not publish a plain intermediate');
    expect(display.lines.single.japaneseReading, 'にほんごかな');
    expect(rig.service.rawCurrentLyric, same(raw));
    expect(raw.lines.single.japaneseReadingSpans, isEmpty);
    expect(rig.desktop.sent.last, same(display.lines.single));
    final packets = <Map<String, Object>>[];
    taskbar = playerTaskbarLyricSourceForTesting(rig.facade);
    expect(await taskbar.lyric, same(display));
    publisher = TaskbarLyricsPublisher(
        source: taskbar,
        elapsed: () => Duration.zero,
        appearance: () => const TaskbarLyricAppearance(
            accent: 0xff123456, fontFamily: 'fixture', fontPath: ''),
        send: (packet) async => packets.add(packet),
        onError: (error, stack) => fail('$error\n$stack'));
    await _flush();
    expect(packets.last['text'], '日本語かな');
    expect(packets.last['enabled'], isTrue);
    expect(rig.service.currLyricFuture, same(finalFuture));
  });

  test(
      'imported Japanese spans stay the first display without cache or analysis',
      () async {
    final raw = _line('漢かな');
    raw.lines.single.japaneseReading = 'かんかな';
    raw.lines.single.japaneseReadingSpans = const [
      JapaneseLyricReadingSpan(start: 0, end: 1, text: 'かん'),
    ];
    var reads = 0;
    final rig = _Rig(
        analyze: (_) => throw StateError('Unused analyzer'),
        projector: JapaneseReadingProjector(
            cache: JapaneseLyricReadingCache(directory: () async {
              reads++;
              throw StateError('Authored spans already provide the display');
            }),
            analyze: (_) =>
                throw StateError('Imported spans must not regenerate')));
    addTearDown(rig.close);
    rig.preferences.value = const JapaneseReadingPreferences(enabled: true);
    rig.service.useSpecificLyric(raw);
    expect(await rig.service.currLyricFuture, same(raw));
    await _flush();
    expect(rig.service.currentPresentation, same(raw));
    expect(rig.desktop.sent.last, same(raw.lines.single));
    expect(reads, 0);
    expect(raw.lines.single.japaneseReadingSpans.single.text, 'かん');
    expect(rig.service.japaneseReadingsBusy.value, isFalse);
  });

  test('closing during initial cache read prevents late presentation',
      () async {
    final previous = AppSettings.instance.desktopLyricAppearance.value;
    AppSettings.instance.desktopLyricAppearance.value =
        DesktopLyricAppearance.defaults.copyWith(showJapaneseReading: true);
    addTearDown(
        () => AppSettings.instance.desktopLyricAppearance.value = previous);
    final root = await Directory(
            'J:/temp/codex/software/danplayer/tool/qa-local/blur-position-feedback-oct12/cache/service')
        .create(recursive: true);
    final isolated = await root.createTemp('retired-');
    final waiting = Completer<Directory>();
    final rig = _Rig(
        analyze: (_) => throw StateError('Unused injected analyzer'),
        projector: JapaneseReadingProjector(
            cache: JapaneseLyricReadingCache(
                directory: () => waiting.future, engine: 'service-cache-v1'),
            analyze: (_) =>
                throw StateError('Read-only cache must not analyze')));
    var closed = false;
    addTearDown(() async {
      if (!closed) await rig.close();
      if (!waiting.isCompleted) waiting.complete(isolated);
      await isolated.delete(recursive: true);
    });
    rig.resolve = () async => _line('日本語かな');
    rig.service.updateLyric();
    final old = rig.service.currLyricFuture;
    await _flush();
    expect(rig.service.currentPresentation, isNull);
    expect(rig.service.japaneseReadingsBusy.value, isFalse);
    final sends = rig.desktop.sent.length;
    await rig.close();
    closed = true;
    waiting.complete(isolated);
    expect(await old, isNull);
    await _flush();
    expect(rig.desktop.sent.length, sends);
  });
}
