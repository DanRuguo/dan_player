import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/audio_trim_commit.dart';
import 'package:dan_player/src/rust/api/audio_trim.dart' as native;
import 'package:dan_player/src/rust/api/tag_reader.dart' as tags;
import 'package:dan_player/src/rust/frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final samples = Platform.environment['DAN_PLAYER_TRIM_SAMPLES'];
  test('explicit copied samples retain native metadata when trimmed', () async {
    await RustLib.init(
        externalLibrary: ExternalLibrary.open(
            Platform.environment['DAN_PLAYER_TRIM_NATIVE_DLL']!));
    addTearDown(RustLib.dispose);
    final folder = Directory(samples!);
    final failures = <String>[];
    for (final file in folder.listSync().whereType<File>().where(
        (f) => const ['.mp3', '.flac', '.m4a'].contains(p.extension(f.path)))) {
      try {
        if (p.basename(file.path) ==
            Platform.environment['DAN_PLAYER_TRIM_EXPECT_UNSUPPORTED']) {
          final original = await sha256.bind(file.openRead()).first;
          await expectLater(
              native.prepareAudioTrim(sourcePath: file.path),
              throwsA(predicate((Object e) =>
                  e.toString().contains('TAG_LAYOUT_UNSUPPORTED'))));
          expect(await sha256.bind(file.openRead()).first, original);
          print('EXPECTED unsupported layout: ${p.basename(file.path)}');
          continue;
        }
        final destination = await folder.createTemp('result-');
        final originalHash = await sha256.bind(file.openRead()).first;
        final cover = await tags.getPictureFromPath(
            path: file.path, width: 128, height: 128);
        final audio = Audio.fromMap(
            jsonDecode(await native.readAudioTrimFile(path: file.path)));
        final ops = AudioTrimOperations(
            prepare: (path) => native.prepareAudioTrim(sourcePath: path),
            metadata: (path, temp, request) async {
              final value = await native.finishAudioTrimMetadata(
                  sourcePath: path,
                  temporaryPath: temp,
                  preserveMetadata: true,
                  startSeconds: request.startSeconds,
                  endSeconds: request.endSeconds);
              if (Platform.environment['DAN_PLAYER_TRIM_CAPTURE'] == 'true') {
                await File(temp).copy(
                    p.join(destination.path, 'stage${p.extension(path)}'));
              }
              return value;
            },
            commit: (path, temp, request, fingerprint) =>
                native.commitAudioTrim(
                    sourcePath: path,
                    temporaryPath: temp,
                    destinationPath: request.destinationPath,
                    overwrite: false,
                    expectedFingerprint: fingerprint),
            releaseTemporary: (path) =>
                native.releaseAudioTrim(temporaryPath: path),
            synchronize: (source, request, result) async {});
        final result = await performAudioTrim(
            audio,
            AudioTrimRequest(
                destinationPath:
                    p.join(destination.path, p.basename(file.path)),
                startSeconds: 10,
                endSeconds: 17),
            operations: ops);
        expect(result.duration, closeTo(7, .15));
        expect(File(result.path).existsSync(), isTrue);
        expect(await sha256.bind(file.openRead()).first, originalHash,
            reason: 'Original copy must remain unchanged: ${file.path}');
        final saved = Audio.fromMap(
            jsonDecode(await native.readAudioTrimFile(path: result.path)));
        expect(saved.title, audio.title, reason: file.path);
        expect(saved.artist, audio.artist, reason: file.path);
        expect(saved.album, audio.album, reason: file.path);
        final savedCover = await tags.getPictureFromPath(
            path: result.path, width: 128, height: 128);
        if (cover != null &&
            savedCover != null &&
            sha256.convert(cover) != sha256.convert(savedCover)) {
          await File(p.join(destination.path, 'before.png'))
              .writeAsBytes(cover);
          await File(p.join(destination.path, 'after.png'))
              .writeAsBytes(savedCover);
        }
        expect(savedCover, cover == null ? isNull : orderedEquals(cover),
            reason: 'Inherited cover: ${file.path}');
        print(
            'Verified ${p.basename(file.path)}: duration, tags, original SHA256');
      } catch (error) {
        failures.add('${p.basename(file.path)}: $error');
        print('FAILED ${failures.last}');
      }
    }
    expect(failures, isEmpty);
  }, skip: samples == null, timeout: const Timeout(Duration(minutes: 30)));
}
