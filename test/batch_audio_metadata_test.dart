import 'dart:async';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_metadata_update.dart';
import 'package:dan_player/library/batch_audio_metadata.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/music_category_fixtures.dart';

MetadataFileSnapshot snapshot(Audio audio,
        {String fingerprint = '100_1',
        bool readOnly = false,
        bool supported = true}) =>
    MetadataFileSnapshot(
        fingerprint: fingerprint,
        title: audio.title,
        artist: audio.artist,
        album: audio.album,
        readOnly: readOnly,
        supported: supported,
        reason: 'unsupported');

void main() {
  test('native file identity deduplicates aliases and hard links', () async {
    final a = CategoryTestAudio('a'), alias = CategoryTestAudio('alias');
    var writes = 0;
    final batch = BatchAudioMetadata([a, alias],
        inspect: (path) async => const MetadataFileSnapshot(
            fingerprint: '1_1',
            title: 'Track',
            artist: 'Artist',
            album: 'Album',
            sourceKey: 'volume:file-id'),
        apply: (audio, edit) async {
          writes++;
          return audio;
        });
    addTearDown(batch.dispose);
    await batch.preview(BatchMetadataDraft(album: 'New'));
    expect(batch.targets.last.status, BatchMetadataStatus.skipped);
    await batch.apply();
    expect(writes, 1);
  });
  test(
      'unmodified whitespace and leading filename spaces survive coordinator normalization',
      () async {
    final audio = CategoryTestAudio('track',
        path: 'J:/fixture/ leading.mp3', artist: ' Artist ', album: ' Album ');
    AudioMetadataEdit? written;
    final coordinator = AudioMetadataEditCoordinator(
        write: (path, edit) async {
          written = edit;
          return path;
        },
        synchronize: (audio, commit) async {});
    final batch = BatchAudioMetadata([audio],
        inspect: (path) async => snapshot(audio), apply: coordinator.apply);
    addTearDown(batch.dispose);
    await batch.preview(
        BatchMetadataDraft(titles: {audio.stableTrackId: 'New title'}));
    await batch.apply();
    expect(written!.artist, ' Artist ');
    expect(written!.album, ' Album ');
    expect(written!.fileName, ' leading.mp3');
  });
  test('mixed values explicit no-op blanks and duplicate occurrences',
      () async {
    final a = CategoryTestAudio('a', artist: 'First');
    final b = CategoryTestAudio('b', artist: 'Second');
    final sources = {a.path: snapshot(a), b.path: snapshot(b)};
    var writes = 0;
    final batch = BatchAudioMetadata([a, a, b],
        inspect: (path) async => sources[path]!,
        apply: (audio, edit) async {
          writes++;
          return audio;
        });
    addTearDown(batch.dispose);
    expect(batch.targets.length, 2);
    expect(batch.commonValue((audio) => audio.artist), isNull);
    await batch.preview(BatchMetadataDraft());
    expect(batch.count(BatchMetadataStatus.unchanged), 2);
    await batch.apply();
    expect(writes, 0);
    await expectLater(
        batch.preview(BatchMetadataDraft(artist: ' ')), throwsFormatException);
    await batch.preview(BatchMetadataDraft(titles: {a.stableTrackId: 'New A'}));
    await batch.apply();
    expect(writes, 1);
    expect(batch.targets.first.edit!.fileName, 'a.mp3');
    expect(batch.targets.first.edit!.expectedFingerprint, '100_1');
    expect(batch.targets.last.status, BatchMetadataStatus.unchanged);
  });

  test('online cue read-only unsupported have explicit reasons and no write',
      () async {
    final ordinary = CategoryTestAudio('read-only');
    final unsupported = CategoryTestAudio('unsupported');
    final online = CategoryTestAudio('online', online: true);
    final cue = Audio(
        'cue', 'A', 'B', 1, 10, null, null, 'cue://fixture', 1, 1, 'test',
        cueTrack: const CueTrackReference(
            sourcePath: 'J:/fixture/whole.flac',
            cuePath: 'J:/fixture/whole.cue',
            number: 1,
            startFrame: 0,
            endFrame: 750));
    var writes = 0;
    final batch = BatchAudioMetadata([ordinary, unsupported, online, cue],
        inspect: (path) async => snapshot(
            path == ordinary.path ? ordinary : unsupported,
            readOnly: path == ordinary.path,
            supported: path != unsupported.path),
        apply: (audio, edit) async {
          writes++;
          return audio;
        });
    addTearDown(batch.dispose);
    await batch.preview(BatchMetadataDraft(artist: 'Changed'));
    expect(batch.count(BatchMetadataStatus.skipped), 4);
    expect(batch.targets.every((target) => target.reason.isNotEmpty), isTrue);
    await batch.apply();
    expect(writes, 0);
  });

  test('cancel while first file writes finishes it and skips unstarted files',
      () async {
    final audios = [CategoryTestAudio('a'), CategoryTestAudio('b')];
    final started = Completer<void>(), release = Completer<void>();
    final batch = BatchAudioMetadata(audios,
        inspect: (path) async =>
            snapshot(audios.firstWhere((audio) => audio.path == path)),
        apply: (audio, edit) async {
          started.complete();
          await release.future;
          return audio;
        });
    addTearDown(batch.dispose);
    await batch.preview(BatchMetadataDraft(album: 'New'));
    final applying = batch.apply();
    await started.future;
    batch.cancel();
    release.complete();
    await applying;
    expect(batch.targets.first.status, BatchMetadataStatus.success);
    expect(batch.targets.last.status, BatchMetadataStatus.cancelled);
  });

  test('retry sync finishes first journal without duplicate native writes',
      () async {
    final audios = [CategoryTestAudio('a'), CategoryTestAudio('b')];
    final original = {for (final audio in audios) audio.path: snapshot(audio)};
    var writes = 0, syncs = 0;
    final coordinator = AudioMetadataEditCoordinator(write: (path, edit) async {
      writes++;
      return path;
    }, synchronize: (audio, commit) async {
      if (++syncs == 1) throw StateError('disk busy');
    });
    final batch = BatchAudioMetadata(audios,
        inspect: (path) async => original[path]!, apply: coordinator.apply);
    addTearDown(batch.dispose);
    await batch.preview(BatchMetadataDraft(album: 'New'));
    await batch.apply();
    expect(writes, 1);
    expect(batch.targets.first.status, BatchMetadataStatus.pendingSync);
    expect(batch.targets.last.status, BatchMetadataStatus.ready);
    await batch.apply(retryOnly: true);
    expect(writes, 1);
    expect(batch.targets.first.status, BatchMetadataStatus.success);
    await batch.apply();
    expect(writes, 2);
    await batch.apply(retryOnly: true);
    expect(writes, 2);
  });

  test(
      'external file and model changes skip frozen targets instead of retargeting',
      () async {
    final audios = [
      CategoryTestAudio('a'),
      CategoryTestAudio('b'),
      CategoryTestAudio('c')
    ];
    final original = {for (final audio in audios) audio.path: snapshot(audio)};
    var writes = 0;
    final batch = BatchAudioMetadata(audios,
        inspect: (path) async => original[path]!,
        apply: (audio, edit) async {
          writes++;
          return audio;
        });
    addTearDown(batch.dispose);
    await batch.preview(BatchMetadataDraft(album: 'New'));
    original[audios.first.path] = snapshot(audios.first, fingerprint: '200_2');
    audios[1].title = 'edited elsewhere';
    audios.sort((a, b) => b.path.compareTo(a.path));
    await batch.apply();
    expect(writes, 1);
    expect(batch.count(BatchMetadataStatus.skipped), 2);
    expect(batch.targets.map((target) => target.path.split('/').last),
        ['a.mp3', 'b.mp3', 'c.mp3']);
  });

  test(
      'failure retry never rewrites successful entries and preserves absent fields',
      () async {
    final audios = [CategoryTestAudio('a'), CategoryTestAudio('b')];
    final attempts = <String, int>{};
    final batch = BatchAudioMetadata(audios,
        inspect: (path) async => MetadataFileSnapshot(
            fingerprint: '1_1', title: path, artist: '', album: ''),
        apply: (audio, edit) async {
          attempts.update(audio.path, (count) => count + 1, ifAbsent: () => 1);
          expect(edit.album, '');
          expect(edit.preserveEmptyValues, isTrue);
          if (audio == audios.last && attempts[audio.path] == 1) {
            throw StateError('TAG_FILE_BUSY|busy');
          }
          return audio;
        });
    addTearDown(batch.dispose);
    await batch.preview(BatchMetadataDraft(artist: 'New'));
    await batch.apply();
    await batch.apply(retryOnly: true);
    expect(attempts[audios.first.path], 1);
    expect(attempts[audios.last.path], 2);
  });
}
