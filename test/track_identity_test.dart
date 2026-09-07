import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late TrackIdentityRegistry registry;

  setUp(() async {
    final parent = Directory(p.join(
        Platform.environment['DAN_PLAYER_DATA_DIR'] ?? Directory.current.path,
        'identity-tests'));
    await parent.create(recursive: true);
    directory = await parent.createTemp('registry-');
    registry = TrackIdentityRegistry.inMemory();
    await registry.initialize(directory: directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test('rescanning and restarting reuse IDs independently of index metadata',
      () async {
    final id = registry.idFor(r'C:\music\Track.flac');
    expect(TrackIdentityRegistry.isTrackId(id), isTrue);
    expect(registry.idFor('c:/music/track.flac'), id);
    await registry.flush();
    final restarted = TrackIdentityRegistry.inMemory();
    await restarted.initialize(directory: directory);
    expect(restarted.idFor(r'C:\music\Track.flac'), id);
    expect(restarted.idFor(r'C:\music\other.flac'), isNot(id));
  });

  test('explicit relink preserves ID and alias without conflating reused paths',
      () async {
    final id = registry.idFor(r'C:\old\track.flac');
    registry.remapPaths(
        (path) => path == r'C:\old\track.flac' ? r'D:\new\track.flac' : path);
    expect(registry.idFor(r'D:\new\track.flac'), id);
    expect(registry.resolvePath(r'C:\old\track.flac'), id);
    final replacement = registry.idFor(r'C:\old\track.flac');
    expect(replacement, isNot(id));
    expect(registry.resolvePath(r'C:\old\track.flac'), isNull);
    await registry.flush();
    final restarted = TrackIdentityRegistry.inMemory();
    await restarted.initialize(directory: directory);
    expect(restarted.idFor(r'D:\new\track.flac'), id);
    expect(restarted.idFor(r'C:\old\track.flac'), replacement);
  });

  test('conflicting mapping is rejected before any mutation', () {
    final first = registry.idFor(r'C:\a.flac');
    final second = registry.idFor(r'C:\b.flac');
    expect(() => registry.remapPaths((_) => r'D:\same.flac'), throwsStateError);
    expect(registry.idFor(r'C:\a.flac'), first);
    expect(registry.idFor(r'C:\b.flac'), second);
  });

  test(
      'CUE boundaries and physical files are independent, relocation is stable',
      () {
    const cue = CueTrackReference(
        cuePath: r'C:\music\album.cue',
        sourcePath: r'C:\music\album.flac',
        number: 1,
        startFrame: 0,
        endFrame: 15001);
    final physical = registry.idFor(cue.sourcePath);
    final segment = registry.idFor(cue.identity, cue: cue);
    expect(segment, isNot(physical));
    const changed = CueTrackReference(
        cuePath: r'C:\music\album.cue',
        sourcePath: r'C:\music\album.flac',
        number: 1,
        startFrame: 1,
        endFrame: 15001);
    expect(registry.idFor(changed.identity, cue: changed, preferredId: segment),
        isNot(segment));
    const moved = CueTrackReference(
        cuePath: r'D:\library\album.cue',
        sourcePath: r'D:\library\album.flac',
        number: 1,
        startFrame: 0,
        endFrame: 15001);
    registry.remapPaths((path) => path == cue.identity
        ? moved.identity
        : path == cue.sourcePath
            ? moved.sourcePath
            : path);
    expect(registry.idFor(moved.identity, cue: moved), segment);
    expect(registry.idFor(moved.sourcePath), physical);
  });

  test('copied index IDs do not merge different file instances', () {
    final first = registry.idFor(r'C:\a.flac');
    expect(registry.idFor(r'C:\b.flac', preferredId: first), isNot(first));
  });

  test('damaged target recovers valid backup and keeps failed bytes', () async {
    final first = registry.idFor(r'C:\a.flac');
    await registry.flush();
    registry.idFor(r'C:\b.flac');
    await registry.flush();
    final target = File(p.join(directory.path, TrackIdentityRegistry.fileName));
    await target.writeAsString('{broken');
    final recovered = TrackIdentityRegistry.inMemory();
    await recovered.initialize(directory: directory);
    expect(recovered.idFor(r'C:\a.flac'), first);
    await recovered.flush();
    expect(jsonDecode(await target.readAsString())['version'], 1);
    expect(
        directory.listSync().where((file) => file.path.contains('.damaged-')),
        hasLength(1));
  });

  test('unrecoverable or duplicate registry never silently resets IDs',
      () async {
    final target = File(p.join(directory.path, TrackIdentityRegistry.fileName));
    final id = registry.idFor(r'C:\a.flac');
    final data = registry.toMap();
    final records = data['records'] as List;
    records.add(<String, Object?>{
      ...Map<String, Object?>.from(records.single as Map),
      'path': r'C:\b.flac',
    });
    await target.writeAsString(jsonEncode(data));
    final restarted = TrackIdentityRegistry.inMemory();
    await expectLater(
        restarted.initialize(directory: directory), throwsFormatException);
    expect(await target.readAsString(), contains(id));
  });

  test('Audio metadata changes and index serialization keep stable identity',
      () {
    const path = r'C:\identity-audio-regression\track.flac';
    final audio = Audio(
        'Before', 'Artist', 'Album', 1, 180, 900, 44100, path, 0, 0, 'Test');
    final id = audio.trackId;
    audio.applyEditedMetadata(
        newPath: r'C:\identity-audio-regression\renamed.flac',
        newTitle: 'After',
        newArtist: 'Another',
        newAlbum: 'Changed',
        newModified: 1);
    audio.duration = 181;
    expect(audio.trackId, id);
    final serialized = audio.toMap();
    expect(serialized['track_id'], id);
    expect(Audio.fromMap(serialized).stableTrackId, id);
    serialized
        .remove('track_id'); // Native scanner does not preserve this field.
    expect(Audio.fromMap(serialized).stableTrackId, id);
  });

  test('stale editor and rescanned reference share the explicit rename ID', () {
    final original = Audio('Song', 'Artist', 'Album', 1, 180, 900, 44100,
        r'C:\identity-multiple-references\track.flac', 0, 0, 'Test');
    final rescanned = Audio.fromMap(original.toMap()..remove('track_id'));
    final id = original.trackId;
    for (final audio in [original, rescanned]) {
      audio.applyEditedMetadata(
          newPath: r'D:\identity-multiple-references\renamed.flac',
          newTitle: 'Song',
          newArtist: 'Artist',
          newAlbum: 'Album',
          newModified: 1);
    }
    expect(rescanned.trackId, id);
  });
}
