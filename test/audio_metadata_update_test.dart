import 'dart:async';
import 'package:dan_player/library/audio_metadata_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/metadata_test_audio.dart';

void main() {
  const edit = AudioMetadataEdit(
      fileName: 'new.mp3',
      title: 'New title',
      artist: 'Artist',
      album: 'Album');

  test('native failure changes no model and leaves no pending sync', () async {
    final audio = MetadataTestAudio();
    var writes = 0;
    var syncs = 0;
    final coordinator = AudioMetadataEditCoordinator(write: (_, __) async {
      if (++writes == 1) throw StateError('TAG_FILE_BUSY|busy');
      return 'D:/metadata-fixture/new.mp3';
    }, synchronize: (_, __) async {
      syncs++;
    });
    await expectLater(coordinator.apply(audio, edit),
        throwsA(isA<AudioMetadataEditException>()));
    expect(audio.path, endsWith('/old.mp3'));
    expect(audio.title, 'Old title');
    expect(syncs, 0);
    await coordinator.apply(audio, edit);
    expect(writes, 2);
    expect(syncs, 1);
  });

  test(
      'committed rename updates identity and retries sync without native write',
      () async {
    final audio = MetadataTestAudio();
    var writes = 0;
    var syncs = 0;
    AudioMetadataCommittedEdit? first;
    final coordinator = AudioMetadataEditCoordinator(write: (_, __) async {
      writes++;
      return 'D:/metadata-fixture/new.mp3';
    }, synchronize: (_, commit) async {
      if (++syncs == 1) {
        first = commit;
        commit.customOrderNeedsSave = true;
        commit.playlistsNeedSave = true;
        throw StateError('isolated index failure');
      }
      expect(identical(first, commit), isTrue);
      expect(commit.oldPath, endsWith('/old.mp3'));
      expect(commit.customOrderNeedsSave && commit.playlistsNeedSave, isTrue);
    });
    await expectLater(
        coordinator.apply(audio, edit),
        throwsA(isA<AudioMetadataEditException>()
            .having((e) => e.code, 'code', 'TAG_LIBRARY_SYNC_FAILED')
            .having((e) => e.fileWasUpdated, 'committed', isTrue)));
    expect(audio.path, endsWith('/new.mp3'));
    expect(audio.title, 'New title');
    await coordinator.apply(audio, edit);
    expect(writes, 1);
    expect(syncs, 2);
  });

  test('form changes during pending sync are applied afterwards to new path',
      () async {
    final audio = MetadataTestAudio();
    final writes = <String>[];
    var syncs = 0;
    final coordinator =
        AudioMetadataEditCoordinator(write: (path, request) async {
      writes.add('$path:${request.title}');
      return 'D:/metadata-fixture/${request.fileName}';
    }, synchronize: (_, __) async {
      if (++syncs == 1) throw StateError('isolated failure');
    });
    await expectLater(coordinator.apply(audio, edit),
        throwsA(isA<AudioMetadataEditException>()));
    await coordinator.apply(
        audio,
        const AudioMetadataEdit(
            fileName: 'next.mp3',
            title: 'Changed after warning',
            artist: 'Artist',
            album: 'Album'));
    expect(writes, [
      'D:/metadata-fixture/old.mp3:New title',
      'D:/metadata-fixture/new.mp3:Changed after warning'
    ]);
    expect(audio.path, endsWith('/next.mp3'));
    expect(audio.title, 'Changed after warning');
    expect(syncs, 3);
  });

  test('failed pending sync does not overwrite with a newer form prematurely',
      () async {
    final audio = MetadataTestAudio();
    var writes = 0;
    final coordinator = AudioMetadataEditCoordinator(write: (_, __) async {
      writes++;
      return 'D:/metadata-fixture/new.mp3';
    }, synchronize: (_, __) async {
      throw StateError('still unavailable');
    });
    await expectLater(coordinator.apply(audio, edit),
        throwsA(isA<AudioMetadataEditException>()));
    await expectLater(
        coordinator.apply(
            audio,
            const AudioMetadataEdit(
                fileName: 'next.mp3',
                title: 'Later edit',
                artist: 'Artist',
                album: 'Album')),
        throwsA(isA<AudioMetadataEditException>()));
    expect(writes, 1);
    expect(audio.title, 'New title');
  });

  test('retry with the same selected cover does not rewrite the cover',
      () async {
    final audio = MetadataTestAudio();
    var writes = 0;
    var syncs = 0;
    final coordinator = AudioMetadataEditCoordinator(write: (_, __) async {
      writes++;
      return 'D:/metadata-fixture/new.mp3';
    }, synchronize: (_, __) async {
      if (++syncs == 1) throw StateError('retry');
    });
    const coverEdit = AudioMetadataEdit(
        fileName: 'new.mp3',
        title: 'New title',
        artist: 'Artist',
        album: 'Album',
        picturePath: 'D:/synthetic/cover.png');
    await expectLater(coordinator.apply(audio, coverEdit),
        throwsA(isA<AudioMetadataEditException>()));
    await coordinator.apply(audio, coverEdit);
    expect(writes, 1);
  });

  test('concurrent same audio or same path is rejected and lock recovers',
      () async {
    final audio = MetadataTestAudio();
    final gate = Completer<String>();
    var writes = 0;
    final coordinator = AudioMetadataEditCoordinator(
        write: (_, __) {
          writes++;
          return gate.future;
        },
        synchronize: (_, __) async {});
    final first = coordinator.apply(audio, edit);
    final busy = isA<AudioMetadataEditException>()
        .having((e) => e.code, 'busy code', 'TAG_EDIT_IN_PROGRESS');
    await expectLater(coordinator.apply(audio, edit), throwsA(busy));
    await expectLater(
        coordinator.apply(MetadataTestAudio(), edit), throwsA(busy));
    gate.complete('D:/metadata-fixture/new.mp3');
    await first;
    await coordinator.apply(audio, edit);
    expect(writes, 1);
  });

  test('no-op uses no native or persistence and normalizes empty fields',
      () async {
    final audio = MetadataTestAudio();
    final requests = <AudioMetadataEdit>[];
    final coordinator = AudioMetadataEditCoordinator(
        write: (path, request) async {
          requests.add(request);
          return path;
        },
        synchronize: (_, __) async {});
    await coordinator.apply(
        audio,
        const AudioMetadataEdit(
            fileName: 'old.mp3',
            title: 'Old title',
            artist: 'Artist',
            album: 'Album'));
    expect(requests, isEmpty);
    await coordinator.apply(
        audio,
        const AudioMetadataEdit(
            fileName: ' old.mp3 ',
            title: ' Updated ',
            artist: ' ',
            album: ' ',
            picturePath: ' '));
    expect(requests.single.artist, 'UNKNOWN');
    expect(requests.single.album, 'UNKNOWN');
    expect(requests.single.picturePath, isNull);
  });

  test('native metadata errors expose a readable message and stable code', () {
    final error = AudioMetadataEditException.fromNative(
      'AnyhowException(TAG_FORMAT_UNKNOWN|无法根据文件内容识别音频格式)',
    );
    expect(error.code, 'TAG_FORMAT_UNKNOWN');
    expect(error.message, '无法根据文件内容识别音频格式');
    expect(error.toString(), error.message);
  });

  test('unexpected metadata errors remain readable', () {
    final error = AudioMetadataEditException.fromNative(
      StateError('unexpected failure'),
    );
    expect(error.code, 'TAG_UNKNOWN');
    expect(error.message, contains('unexpected failure'));
  });
}
