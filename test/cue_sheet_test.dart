import 'dart:convert';
import 'dart:io';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_metadata_update.dart';
import 'package:dan_player/library/cue_sheet.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/playlist_exchange.dart';
import 'package:dan_player/src/bass/audio_segment.dart';
import 'package:dan_player/play_service/playback_state_store.dart';
import 'package:dan_player/component/audio_selection_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';

const _sheet = '''PERFORMER "Album artist"
TITLE "Album"
FILE "disc.flac" WAVE
 TRACK 01 AUDIO
  TITLE "卡农"
  INDEX 01 00:00:00
 TRACK 02 AUDIO
  TITLE "稻香"
  PERFORMER "Track artist"
  INDEX 00 00:00:70
  INDEX 01 00:01:01
 TRACK 03 AUDIO
  TITLE "Good Time"
  INDEX 01 00:02:00
''';

void main() {
  test('CUE retains frame precision, metadata, pregap and multiple file EOF',
      () {
    final doc = parseCue(
        '$_sheet FILE "second.wav" WAVE\n TRACK 04 AUDIO\n INDEX 01 00:00:00\n',
        cuePath: r'C:\Music\album.cue');
    expect(
        doc.entries.map((t) => t.title), ['卡农', '稻香', 'Good Time', 'Track 04']);
    expect(doc.entries.map((t) => t.reference.startFrame), [0, 76, 150, 0]);
    expect(doc.entries.map((t) => t.reference.endFrame), [76, 150, null, null]);
    expect(doc.entries[1].artist, 'Track artist');
    expect(doc.entries[1].albumArtist, 'Album artist');
    expect(doc.entries.first.reference.sourcePath, r'C:\Music\disc.flac');
    expect(doc.entries.map((t) => t.reference.identity).toSet().length, 4);
  });
  test(
      'invalid and ambiguous references fail whole import without partial songs',
      () {
    for (final source in [
      _sheet.replaceFirst('00:01:01', '00:60:01'),
      _sheet.replaceFirst('00:01:01', '00:01:75'),
      _sheet.replaceFirst('00:01:01', '00:00:00'),
      _sheet.replaceFirst('INDEX 01 00:00:00', 'REM Missing start'),
      _sheet.replaceFirst('TRACK 02 AUDIO', 'TRACK 01 AUDIO'),
      _sheet.replaceFirst('TRACK 02 AUDIO', 'TRACK 02 MODE1/2352'),
      _sheet.replaceFirst('disc.flac', 'https://invalid.example/album.flac'),
      _sheet.replaceFirst('disc.flac', 'album.cue'),
      '$_sheet FILE "disc.flac" WAVE\n TRACK 04 AUDIO\n INDEX 01 00:00:00',
    ]) {
      expect(() => parseCue(source, cuePath: r'C:\Music\album.cue'),
          throwsFormatException);
    }
    expect(() => parseCue('x' * (cueMaxBytes + 1), cuePath: r'C:\album.cue'),
        throwsFormatException);
  });
  test('Unicode and Chinese legacy encodings retain non-ASCII source filenames',
      () {
    expect(decodeCueText(utf8.encode('\uFEFF卡农')), '卡农');
    expect(decodeCueText([255, 254, 97, 83, 156, 81]), '卡农');
    expect(decodeCueText([254, 255, 83, 97, 81, 156]), '卡农');
    expect(() => decodeCueText([255, 254, 97]), throwsFormatException);
    if (Platform.isWindows) {
      expect(decodeCueText([0xbf, 0xa8, 0xc5, 0xa9]), '卡农');
    }
  });
  test(
      'native segment coordinates are relative, clamped and reject mismatched media',
      () {
    const segment = AudioSegment(1, 2);
    expect(segment.duration(3), 1);
    expect(segment.sourcePosition(-1, 1), 1);
    expect(segment.sourcePosition(0.5, 1), 1.5);
    expect(segment.sourcePosition(10, 1), 2);
    expect(segment.relativePosition(1.5, 1), 0.5);
    expect(const AudioSegment(2).duration(3), 1);
    expect(() => segment.duration(1.5), throwsFormatException);
    expect(() => const AudioSegment(3).duration(3), throwsFormatException);
  });
  test(
      'file read, playlist JSON restore, physical edit guard and M3U export isolation',
      () async {
    final root =
        Directory('${Directory.current.parent.path}/tool/qa-local/cue-tests');
    await root.create(recursive: true);
    final directory = await root.createTemp('sheet-');
    final audioFile = File('${directory.path}/disc.flac');
    await audioFile.writeAsBytes([1, 2, 3, 4]);
    final cueFile = File('${directory.path}/album.cue');
    await cueFile.writeAsString(_sheet);
    final original = Audio.fromMap(
        {'path': audioFile.path, 'duration': 3, 'artist': 'Source artist'});
    final audios =
        await resolveCueEntries(await readCueFile(cueFile), [original]);
    expect(audios.map((a) => a.displayTitle), ['卡农', '稻香', 'Good Time']);
    expect(audios.last.duration, 1);
    expect(
        audios.every((a) => a.isCueTrack && a.isLocal && !a.canEditLocalFile),
        isTrue);
    expect(audios.first.localFilePath, audioFile.path.replaceAll('/', '\\'));
    final restored = decodePlaylists([
      {
        'version': 3,
        'id': 'cue-playlist',
        'name': 'Cue',
        'entries': [
          for (var i = 0; i < audios.length; i++)
            {
              'type': 'audio',
              'id': 'cue-entry-$i',
              'audio': jsonDecode(jsonEncode(audios[i].toMap()))
            }
        ]
      }
    ]).single.flattenAudios();
    expect(restored.map((a) => a.path), audios.map((a) => a.path));
    expect(restored[1].cueTrack!.startFrame, 76);
    expect(restored[1].cueTrack!.endFrame, 150);
    final cleanup = Playlist('Cleanup', {
      original.path: original,
      for (final a in restored) a.path: a,
      r'C:\Other\keep.flac': Audio.fromMap({'path': r'C:\Other\keep.flac'}),
    });
    expect(PlaylistTree([cleanup]).removeAudioReferences(original.path), 4);
    expect(cleanup.flattenAudios().single.path, r'C:\Other\keep.flac');
    expect(restored.every((a) => !isM3uLocalAudioPath(a.path)), isTrue);
    expect(selectedLocalPaths(restored),
        [for (final a in restored) a.localFilePath]);
    final session = SavedPlaybackState.fromMap(jsonDecode(jsonEncode(
        SavedPlaybackState(
                queuePaths: restored.map((a) => a.path).toList(),
                backupPaths: [],
                index: 1,
                position: 0.4,
                shuffle: false,
                cueTracks: restored)
            .toMap())))!;
    expect(session.cueTracks[1].path, session.queuePaths[1]);
    expect(session.cueTracks[1].cueTrack!.startFrame, 76);
    expect(session.position, 0.4);
    var wrote = false;
    final edits = AudioMetadataEditCoordinator(
        write: (_, __) async {
          wrote = true;
          return '{}';
        },
        synchronize: (_, __) async {});
    await expectLater(
        edits.apply(
            restored.first,
            const AudioMetadataEdit(
                fileName: 'renamed.flac',
                title: 'Changed',
                artist: 'X',
                album: 'Y')),
        throwsA(isA<AudioMetadataEditException>()));
    expect(wrote, isFalse);
    expect(await audioFile.readAsBytes(), [1, 2, 3, 4]);
    await audioFile.rename('${directory.path}/missing.flac');
    await expectLater(resolveCueEntries(await readCueFile(cueFile), []),
        throwsFormatException);
    expect(() => Audio.fromMap({'path': audios.first.path}),
        throwsFormatException);
  });
}
