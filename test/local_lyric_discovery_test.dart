import 'dart:async';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/lyric/krc.dart';
import 'package:dan_player/lyric/krc_decoder.dart';
import 'package:dan_player/lyric/local_lyric_parser.dart';
import 'package:dan_player/lyric/local_lyric_reader.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:dan_player/lyric/lyric_cache_batch.dart';
import 'package:dan_player/lyric/online_lyric_cache.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

class _LocalPlayback extends Fake implements PlaybackService {
  _LocalPlayback(this.audio);
  Audio? audio;
  final positions = StreamController<double>.broadcast(sync: true);
  @override
  Audio? get nowPlaying => audio;
  @override
  Stream<double> get positionStream => positions.stream;
  @override
  double get position => 0;
  @override
  Future<void> close() async {}
}

class _LocalDesktop extends Fake implements DesktopLyricService {
  @override
  Future<bool> get canSendMessage async => true;
  @override
  void sendNoLyricMessage() {}
  @override
  void sendPlaybackTimelineMessage() {}
  @override
  void sendLyricLineMessage(LyricLine line, {required int lineIndex}) {}
  @override
  Future<void> flushAppearance() async {}
  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late Audio audio;
  setUp(() async {
    final root = Platform.environment['DAN_PLAYER_DATA_DIR'];
    if (root == null ||
        !path.isWithin(
            path.join(Directory.current.parent.path, 'tool', 'qa-local'),
            root)) {
      throw StateError('Use independent workspace QA data');
    }
    fixture = await Directory(root).createTemp('local-lyrics-');
    audio = Audio('Example', 'Artist', 'Album', 0, 60, null, null,
        path.join(fixture.path, 'Example.flac'), 0, 0, null);
    await File(audio.localFilePath).writeAsBytes([0]);
    clearLocalLyricMemoryCache();
  });
  Future<void> write(String suffix, String value) =>
      File(path.setExtension(audio.path, suffix)).writeAsString(value);

  test(
      'memory cache clones word and auxiliary axes and validates file revisions',
      () async {
    await write('.yrc', '[1000,1000](1000,500,0)Hello(1500,500,0) world');
    await write('.lrc', '[00:01.000]Translation');
    final roman =
        File('${path.setExtension(audio.path, '.yrc')}.romanization.lrc');
    await roman.writeAsString('[00:01.000]Roman');
    final first = await readLocalLyric(audio);
    expect(localLyricMemoryCacheSize, 1);
    final line = first!.lines.single as SyncLyricLine;
    line.translation = 'Edited';
    line.romanization = 'Edited';
    line.words.first.content = 'Edited';
    final copy = await readLocalLyric(audio);
    final copyLine = copy!.lines.single as SyncLyricLine;
    expect(copyLine.content, 'Hello world');
    expect(copyLine.translation, 'Translation');
    expect(copyLine.romanization, 'Roman');
    expect(
        copyLine.words.map((word) => word.start.inMilliseconds), [1000, 1500]);
    expect(localLyricOrigin(copy), endsWith('.yrc'));
    await roman.writeAsString('[00:01.000]Fresh romanization');
    expect((await readLocalLyric(audio))!.lines.single.romanization,
        'Fresh romanization');
    await write('.lrc', '[00:01.000]Fresh translation');
    expect(
        ((await readLocalLyric(audio))!.lines.single as SyncLyricLine)
            .translation,
        'Fresh translation');
    await write('.yrc', '[1000,1000](1000,1000,0)Fresh original');
    expect(
        ((await readLocalLyric(audio))!.lines.single as SyncLyricLine).content,
        'Fresh original');
    await File(path.setExtension(audio.path, '.yrc')).delete();
    expect((await readLocalLyric(audio))!.lines.single, isA<LrcLine>());
    await File(audio.localFilePath).delete();
    expect(await readLocalLyric(audio), isNull);
    expect(localLyricMemoryCacheSize, 0);
  });

  test('memory cache stays bounded and each line order has its own model',
      () async {
    await write('.lrc',
        '[00:01.000]Roman\n[00:01.000]Original\n[00:01.000]Translation');
    final ordinary = await readLocalLyric(audio);
    final reordered = await readLocalLyric(audio,
        lineOrder: LocalLyricLineOrder.romanizationOriginalTranslation);
    expect(ordinary!.lines.single.romanization, isNull);
    expect(reordered!.lines.single.romanization, 'Roman');
    for (var i = 0; i < 34; i++) {
      final name = path.join(fixture.path, 'Item$i.flac');
      await File(name).writeAsBytes([0]);
      await File(path.setExtension(name, '.lrc'))
          .writeAsString('[00:01.000]$i');
      final item = Audio(
          'Item$i', 'Artist', 'Album', 0, 60, null, null, name, 0, 0, null);
      expect(await readLocalLyric(item), isNotNull);
    }
    expect(localLyricMemoryCacheSize, 32);
    expect(localLyricMemoryCacheBytes, lessThanOrEqualTo(8 * 1024 * 1024));
    expect(await readLocalLyric(audio, stillCurrent: () => false), isNull);
    expect(localLyricMemoryCacheSize, 32);
  });

  test('memory budget evicts large lyrics before reaching the item limit',
      () async {
    final large = '[00:01.000]${'A' * 1800000}';
    for (var i = 0; i < 5; i++) {
      final name = path.join(fixture.path, 'Large$i.flac');
      await File(name).writeAsBytes([0]);
      await File(path.setExtension(name, '.lrc')).writeAsString(large);
      final item = Audio(
          'Large$i', 'Artist', 'Album', 0, 60, null, null, name, 0, 0, null);
      expect(await readLocalLyric(item), isNotNull);
    }
    expect(localLyricMemoryCacheSize, 4);
    expect(localLyricMemoryCacheBytes, lessThanOrEqualTo(8 * 1024 * 1024));
  });

  test('LDDC bracket words and tags preserve original word times', () {
    final lyric = parseLocalLyricText('[ar:Author]\n[au:Composer]\n'
        '[tool:LDDC example]\n[offset:0]\n'
        '[00:01.000]Hello[00:01.500] world[00:02.000]\n'
        '[00:01.000]你好，世界\n[00:03.000]Next[00:04.000]')!;
    final first = lyric.lines.first as SyncLyricLine;
    expect(first.content, 'Hello world');
    expect(first.translation, '你好，世界');
    expect(first.words.map((word) => word.start.inMilliseconds), [1000, 1500]);
    expect(first.words.map((word) => word.length.inMilliseconds), [500, 500]);
    expect(first.romanization, isNull);
  });

  test('enhanced LRC handles timed original with untimed translation rows', () {
    final lyric = parseLocalLyricText(
        '[00:01.000]<00:01.000>Hello<00:01.500> world<00:02.000>\n'
        '[00:01.000]译文\n[00:03.000]Plain next')!;
    expect((lyric.lines.first as SyncLyricLine).translation, '译文');
    expect((lyric.lines.last as SyncLyricLine).content, 'Plain next');
  });

  test('three duplicate rows stay conservative unless roles are explicit', () {
    const text = '[00:01.000]roman\n[00:01.000]原文\n[00:01.000]译文';
    final automatic = parseLocalLyricText(text)!;
    expect((automatic.lines.single as LrcLine).content, 'roman┃原文┃译文');
    expect(automatic.lines.single.romanization, isNull);
    final explicit = parseLocalLyricText(text,
        lineOrder: LocalLyricLineOrder.romanizationOriginalTranslation)!;
    expect((explicit.lines.single as LrcLine).content, '原文┃译文');
    expect(explicit.lines.single.romanization, 'roman');
    final restored = LyricSnapshot.capture(explicit).toLyric();
    expect(restored.lines.single.romanization, 'roman');
    expect((restored.lines.single as LrcLine).content, '原文┃译文');
  });

  test('original translation romanization order keeps each role', () {
    final lyric = parseLocalLyricText(
        '[00:01.000]Original\n[00:01.000]Translation\n[00:01.000]Roman',
        lineOrder: LocalLyricLineOrder.originalTranslationRomanization)!;
    expect((lyric.lines.single as LrcLine).content, 'Original┃Translation');
    expect(lyric.lines.single.romanization, 'Roman');
  });

  test('chorus leading stamps repeat rather than becoming word markers', () {
    final lyric = parseLocalLyricText('[00:01.000][00:05.000]Repeat')!;
    expect(lyric, isA<Lrc>());
    expect(lyric.lines.map((line) => line.start.inSeconds), [1, 5]);
    expect(lyric.lines.cast<LrcLine>().map((line) => line.content),
        ['Repeat', 'Repeat']);
  });

  test('bad word intervals and incomplete tails never enter local cache', () {
    expect(() => parseLocalLyricText('[00:02.000]Hello[00:01.000]'),
        throwsFormatException);
    expect(
        () => parseLocalLyricText('[00:01.000]<00:01.000>Hello<00:02.000>tail'),
        throwsFormatException);
    expect(parseLocalLyricText('[00:01.000]'), isNull);
  });

  test('word sidecar precedes LRC and same-name LRC supplies translation',
      () async {
    await write('.qrc', '[1000,1000]Hello(1000,500) world(1500,500)');
    await write('.lrc', '[00:01.000]你好，世界');
    var embeddedReads = 0;
    final lyric = await readLocalLyric(audio, readEmbedded: (_) async {
      embeddedReads++;
      return '[00:01.000]embedded';
    });
    expect((lyric!.lines.single as SyncLyricLine).translation, '你好，世界');
    expect(embeddedReads, 0);
    expect(isDiscoveredLocalLyric(lyric), isTrue);
    expect(localLyricOrigin(lyric), endsWith('.qrc'));
    final cache = OnlineLyricCache(
        directory: () async =>
            Directory(path.join(fixture.path, 'lyrics-cache')));
    await cacheLocalLyric(audio, lyric, cache: cache);
    final restored = await readAvailableCachedLyric(audio, cache: cache);
    expect(isDiscoveredLocalLyric(restored!), isTrue);
    final first = restored.lines.single as SyncLyricLine;
    expect(first.words.length, 2);
    expect(first.translation, '你好，世界');
  });

  test('same original LRC does not duplicate itself as a translation',
      () async {
    await write('.yrc', '[1000,1000](1000,500,0)Hello(1500,500,0) world');
    await write('.lrc', '[00:01.000]Hello world');
    final lyric = await readLocalLyric(audio);
    expect((lyric!.lines.single as SyncLyricLine).translation, isNull);
  });

  test('parallel LDDC word LRC provides auxiliary text without timing markers',
      () async {
    await write('.qrc', '[1000,1000]Hello(1000,500) world(1500,500)');
    await write(
        '.lrc',
        '[00:01.000]roman\n'
            '[00:01.000]Hello[00:01.500] world[00:02.000]\n'
            '[00:01.000]译文');
    final lyric = await readLocalLyric(audio,
        lineOrder: LocalLyricLineOrder.romanizationOriginalTranslation);
    final line = lyric!.lines.single as SyncLyricLine;
    expect(line.translation, '译文');
    expect(line.romanization, 'roman');
    expect(line.words.map((word) => word.length.inMilliseconds), [500, 500]);
  });

  test(
      'batch local completion after a user edit cannot populate old local cache',
      () async {
    final store = LyricDocumentStore(storageDirectory: fixture);
    await store.load();
    final cache = OnlineLyricCache(
        directory: () async =>
            Directory(path.join(fixture.path, 'batch-cache')));
    final local = Completer<Lyric?>();
    final entered = Completer<void>();
    var onlineRequests = 0;
    final task = LyricCacheBatch(
        documents: store,
        cache: cache,
        scan: (_, __) async => [audio],
        readLocal: (_) {
          entered.complete();
          return local.future;
        },
        fetchAndCache: (_, __) async {
          onlineRequests++;
          return false;
        });
    addTearDown(task.dispose);
    addTearDown(store.dispose);
    final job = task.start(fixture.path);
    await entered.future;
    await store.edit(audio, '[00:01.000]Human selected text');
    local.complete(parseLocalLyricText('[00:01.000]Old sidecar'));
    await job;
    expect(onlineRequests, 0);
    expect(await readAvailableCachedLyric(audio, cache: cache), isNull);
    expect((store.forAudio(audio)!.render()!.lines.single as LrcLine).content,
        'Human selected text');
  });

  test('binary KRC and explicit companions preserve three lyric roles',
      () async {
    await File(path.setExtension(audio.path, '.krc')).writeAsBytes(
        encodeKrcContainer(
            '[id:metadata]\n[1000,1000]<0,500,0>Hello<500,500,0> world'));
    await write('.krc.translation.lrc', '[00:01.000]译文');
    await write('.krc.romanization.lrc', '[00:01.000]roman');
    final lyric = await readLocalLyric(audio);
    expect(lyric, isA<Krc>());
    final first = lyric!.lines.single as SyncLyricLine;
    expect(first.translation, '译文');
    expect(first.romanization, 'roman');
  });

  test('text XML QRC decodes escaped newlines without decrypting containers',
      () {
    final lyric = parseLocalLyricText(
        '<QrcInfos><Lyric_1 LyricContent="[1000,500]One(1000,500)&#10;'
        '[2000,500]Two(2000,500)"/></QrcInfos>',
        extension: '.qrc')!;
    expect(
        lyric.lines
            .whereType<SyncLyricLine>()
            .where((line) => line.content.isNotEmpty)
            .map((line) => line.content),
        ['One', 'Two']);
  });

  test('invalid and oversized sidecars fall back with explicit warning',
      () async {
    await write('.qrc', 'encrypted binary unsupported');
    await File(path.setExtension(audio.path, '.yrc'))
        .writeAsBytes(List.filled(LyricEditDraft.maxBytes + 1, 120));
    await write('.lrc', '[00:01.000]usable');
    final warnings = <String>[];
    final lyric = await readLocalLyric(audio, onWarning: warnings.add);
    expect((lyric!.lines.single as LrcLine).content, 'usable');
    expect(warnings.any((value) => value.contains('文本 QRC')), isTrue);
    expect(warnings.any((value) => value.contains('过大')), isTrue);
  });

  test('embedded LDDC enhanced lyrics are used after external sources miss',
      () async {
    final lyric = await readLocalLyric(audio,
        readEmbedded: (_) async =>
            '[tool:LDDC]\n[00:01.000]<00:01.000>Embedded<00:02.000>');
    expect((lyric!.lines.single as SyncLyricLine).content, 'Embedded');
    expect(localLyricOrigin(lyric), startsWith('embedded:'));
    expect(
        await readLocalLyric(audio,
            readEmbedded: (_) async =>
                throw const FormatException('invalid tags')),
        isNull);
  });

  test('stale embedded completion is discarded before source provenance/cache',
      () async {
    var current = true;
    final pending = Completer<String?>();
    final entered = Completer<void>();
    final result = readLocalLyric(audio,
        stillCurrent: () => current,
        readEmbedded: (_) {
          entered.complete();
          return pending.future;
        });
    await entered.future;
    current = false;
    pending.complete('[00:01.000]stale');
    expect(await result, isNull);
  });

  test('source fallback does not start another read after cancellation',
      () async {
    var current = true;
    var nextReads = 0;
    final result = await resolveAutomaticLyricSources(
        localFirst: true,
        stillCurrent: () => current,
        local: () async {
          current = false;
          return Lrc.fromLrcText('[00:01.000]stale', LrcSource.local);
        },
        cachedOnline: () async {
          nextReads++;
          return null;
        });
    expect(result, isNull);
    expect(nextReads, 0);
  });

  test('CUE and online identities never probe whole-file sidecars/tags',
      () async {
    var reads = 0;
    final reference = CueTrackReference(
        cuePath: path.join(fixture.path, 'album.cue'),
        sourcePath: audio.path,
        number: 1,
        startFrame: 75,
        endFrame: 450);
    final cue = Audio('Cue', 'Artist', 'Album', 1, 5, null, null,
        reference.identity, 0, 0, null,
        cueTrack: reference);
    final online = Audio.online(
        provider: 'test',
        id: 'example',
        title: 'Online',
        artist: '',
        album: '',
        duration: 1);
    for (final track in [cue, online]) {
      expect(
          await readLocalLyric(track, readEmbedded: (_) async {
            reads++;
            return '[00:01.000]wrong';
          }),
          isNull);
    }
    expect(reads, 0);
  });

  test(
      'actual playback loads word sidecar and preserves selected edited document',
      () async {
    final settings = AppSettings.instance;
    final previousAutomatic = settings.automaticOnlineLyrics.value;
    final previousLocalFirst = settings.localLyricFirst;
    settings.automaticOnlineLyrics.value = false;
    settings.localLyricFirst = true;
    addTearDown(() {
      settings.automaticOnlineLyrics.value = previousAutomatic;
      settings.localLyricFirst = previousLocalFirst;
    });
    await write('.yrc', '[1000,1000](1000,500,0)Hello(1500,500,0) world');
    final playback = _LocalPlayback(audio);
    final readiness = PlaybackReadiness();
    final facade = PlayService.forTesting(
        readiness: readiness,
        createPlayback: (_) => playback,
        createDesktopLyric: (_) => _LocalDesktop(),
        createLyric: (owner) => LyricService(owner));
    addTearDown(() async {
      await facade.close();
      await playback.positions.close();
      readiness.dispose();
    });
    final service = facade.lyricService;
    service.updateLyric();
    final lyric = await service.currLyricFuture;
    expect((lyric!.lines.single as SyncLyricLine).content, 'Hello world');
    expect(isDiscoveredLocalLyric(service.rawCurrentLyric!), isTrue);
    final store = LyricDocumentStore.instance;
    await store.load();
    await store.edit(audio, '[00:01.000]Edited authoritative version');
    await store.setLocked(audio, true);
    await write('.qrc', '[1000,1000]New sidecar(1000,1000)');
    service.updateLyric();
    expect(
        (await service.currLyricFuture)!.lines.single,
        isA<LrcLine>().having((line) => line.content, 'preserved text',
            'Edited authoritative version'));
  });

  test('online-first refreshes local cache from a newly added LDDC sidecar',
      () async {
    final settings = AppSettings.instance;
    final previousAutomatic = settings.automaticOnlineLyrics.value;
    final previousLocalFirst = settings.localLyricFirst;
    settings.automaticOnlineLyrics.value = false;
    settings.localLyricFirst = false;
    addTearDown(() {
      settings.automaticOnlineLyrics.value = previousAutomatic;
      settings.localLyricFirst = previousLocalFirst;
    });
    await cacheLocalLyric(
        audio, parseLocalLyricText('[00:01.000]Old saved local')!);
    await write(
        '.lrc',
        '[tool:LDDC]\n'
            '[00:01.000]New[00:01.500] words[00:02.000]');
    final playback = _LocalPlayback(audio);
    final readiness = PlaybackReadiness();
    final facade = PlayService.forTesting(
        readiness: readiness,
        createPlayback: (_) => playback,
        createDesktopLyric: (_) => _LocalDesktop(),
        createLyric: (owner) => LyricService(owner));
    addTearDown(() async {
      await facade.close();
      await playback.positions.close();
      readiness.dispose();
    });
    final service = facade.lyricService;
    service.updateLyric();
    final lyric = await service.currLyricFuture;
    expect(lyric!.lines.single, isA<SyncLyricLine>());
    expect((lyric.lines.single as SyncLyricLine).content, 'New words');
    expect((lyric.lines.single as SyncLyricLine).words.length, 2);
    await OnlineLyricCache.instance.resolve(onlineLyricCacheIdentity(audio),
        () async => parseLocalLyricText('[00:01.000]Saved online choice'));
    service.updateLyric();
    expect(((await service.currLyricFuture)!.lines.single as LrcLine).content,
        'Saved online choice');
    settings.localLyricFirst = true;
    service.updateLyric();
    expect(
        ((await service.currLyricFuture)!.lines.single as SyncLyricLine)
            .content,
        'New words');
  });
}
