import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/audio_trim_commit.dart';
import 'package:dan_player/library/cover_image_import.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/src/rust/api/audio_trim.dart' as native;
import 'package:dan_player/src/rust/api/tag_reader.dart' as tags;
import 'package:dan_player/src/rust/frb_generated.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Explicit opt-in: uses only synthetic audio and a private application profile.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dll = Platform.environment['DAN_PLAYER_TRIM_NATIVE_DLL'];
  test(
      'release bridge trims tags, LRC and cached lyrics together; publication failure rolls back',
      () async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final root = await Directory(p.absolute('..', 'tool', 'validation',
            'sep14-audio-trim', 'native-integration'))
        .create(recursive: true);
    final directory = await root.createTemp('roundtrip-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
    await RustLib.init(externalLibrary: ExternalLibrary.open(dll!));
    addTearDown(() async {
      RustLib.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      LYRIC_SOURCES.clear();
      expect(p.isWithin(root.path, directory.path), isTrue);
      await directory.delete(recursive: true);
    });
    final music = await Directory(p.join(directory.path, 'music')).create();
    final source = File(p.join(music.path, '原曲 & 日本語.flac'));
    const lyricText =
        '[ar:原歌手]\n[offset:100]\n[00:00.100]opening\n[00:01.100]middle\n[00:02.600]outside\n';
    await runAudioTool('ffmpeg', [
      '-v',
      'error',
      '-nostdin',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=523:sample_rate=48000:duration=3',
      '-ac',
      '2',
      '-c:a',
      'flac',
      '-metadata',
      'title=Original',
      '-metadata',
      'artist=原歌手',
      '-metadata',
      'composer=作曲者',
      '-metadata',
      'lyrics=$lyricText',
      source.path
    ]);
    final sidecar = File(p.setExtension(source.path, '.lrc'));
    await sidecar.writeAsString(lyricText);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0x803399ee), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(2400, 1800);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    final preparedCover = await CoverImageImporter.shared.fromBytes(
        png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
    expect([preparedCover.width, preparedCover.height], [1600, 1200]);
    expect(preparedCover.bytes.length, lessThanOrEqualTo(maxCoverOutputBytes));
    expect(preparedCover.extension, 'png');
    final cover = File(p.join(directory.path, 'cover.png'));
    await cover.writeAsBytes(preparedCover.bytes);
    await tags.updateAudioMetadata(
        path: source.path,
        fileName: p.basename(source.path),
        title: 'Original',
        artist: '原歌手',
        album: '',
        picturePath: cover.path);
    final originalHash = sha256.convert(await source.readAsBytes()).toString();
    final data = await getAppDataDir();
    final sourceMap =
        jsonDecode(await native.readAudioTrimFile(path: source.path))
            as Map<String, dynamic>;
    await File(p.join(data.path, 'index.json')).writeAsString(jsonEncode({
      'version': 113,
      'roots': [music.path],
      'folders': [
        {
          'path': music.path,
          'audios': [sourceMap]
        }
      ]
    }));
    await AudioLibrary.initFromIndex();
    final audio = AudioLibrary.instance.audioCollection.single;
    final documents = LyricDocumentStore.instance;
    await documents.select(
        audio,
        Lrc([
          LrcLine(Duration.zero, 'opening', isBlank: false),
          LrcLine(const Duration(seconds: 1), 'middle', isBlank: false),
          LrcLine(const Duration(milliseconds: 2500), 'outside',
              isBlank: false),
        ], LrcSource.local),
        source: LyricSource(LyricSourceType.local));

    final copy = p.join(music.path, '片段 & 副本.flac');
    final result = await trimAudio(
        audio,
        AudioTrimRequest(
            destinationPath: copy,
            startSeconds: .5,
            endSeconds: 2,
            title: '片段'));
    expect(result.libraryUpdated, isTrue);
    expect(result.warning, isNull);
    expect(result.duration, closeTo(1.5, 1 / 48000));
    expect(sha256.convert(await source.readAsBytes()).toString(), originalHash);
    expect(await sidecar.readAsString(), lyricText);
    final adjusted = await File(p.setExtension(copy, '.lrc')).readAsString();
    expect(adjusted, contains('[00:00.000]opening'));
    expect(adjusted, contains('[00:00.500]middle'));
    expect(adjusted, isNot(contains('outside')));
    final saved = AudioLibrary.instance.audioByPath[copy]!;
    expect(saved.title, '片段');
    expect(saved.composer, '作曲者');
    expect(
        await tags.getPictureFromPath(path: copy, width: 1600, height: 1600),
        await tags.getPictureFromPath(
            path: source.path, width: 1600, height: 1600));
    expect(documents.forAudio(saved)!.render()!.lines.last.start,
        const Duration(milliseconds: 500));
    expect(documents.forAudio(audio)!.render()!.lines.last.start,
        const Duration(milliseconds: 2500));
    final tagged = jsonDecode(await runAudioTool('ffprobe', [
      '-v',
      'error',
      '-show_entries',
      'format_tags=lyrics',
      '-of',
      'json',
      copy
    ])) as Map;
    expect((tagged['format']['tags'] as Map).values.single, adjusted);

    // Inject failure at the real music publication boundary, after the LRC
    // has already been staged/replaced, and verify byte-for-byte rollback.
    final failingOperations = AudioTrimOperations(
        prepare: (path) => native.prepareAudioTrim(sourcePath: path),
        metadata: (path, temp, request) => native.finishAudioTrimMetadata(
            sourcePath: path,
            temporaryPath: temp,
            preserveMetadata: true,
            startSeconds: request.startSeconds,
            endSeconds: request.endSeconds),
        commit: (source, temporary, request, fingerprint) async =>
            throw StateError('Injected disk commit failure'),
        synchronize: (source, request, result) async =>
            fail('Failed commit must not sync'),
        releaseTemporary: (path) =>
            native.releaseAudioTrim(temporaryPath: path));
    await expectLater(
        performAudioTrim(
            audio,
            AudioTrimRequest(
                destinationPath: source.path,
                startSeconds: .5,
                endSeconds: 2,
                overwrite: true),
            operations: failingOperations),
        throwsStateError);
    expect(await sidecar.readAsString(), lyricText);
    expect(sha256.convert(await source.readAsBytes()).toString(), originalHash);

    final overwrite = await trimAudio(
        audio,
        AudioTrimRequest(
            destinationPath: source.path,
            startSeconds: .5,
            endSeconds: 2,
            overwrite: true));
    expect(overwrite.warning, isNull);
    expect(overwrite.libraryUpdated, isTrue);
    expect(await sidecar.readAsString(), adjusted);
    expect(AudioLibrary.instance.audioByPath[source.path]!.stableTrackId,
        audio.stableTrackId);
    expect(
        await music
            .list()
            .where((entry) => p.basename(entry.path).startsWith('.dan-player-'))
            .isEmpty,
        isTrue);
  }, skip: dll == null, timeout: const Timeout(Duration(minutes: 3)));
}
