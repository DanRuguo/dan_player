import 'dart:convert';
import 'dart:io';

import 'package:dan_player/data/cache_backup_service.dart';
import 'package:dan_player/library/track_resume_store.dart';
import 'package:dan_player/play_service/track_resume_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
      'portable cache backup relocates remembered local paths and drops missing tracks',
      () async {
    final qaRoot = await Directory(
            p.absolute('..', 'tool', 'qa-local', '2605-track-resume'))
        .create(recursive: true);
    final sandbox = await qaRoot.createTemp('backup-');
    addTearDown(() => sandbox.delete(recursive: true));
    final source = await Directory(p.join(sandbox.path, 'source')).create();
    final current = await Directory(p.join(sandbox.path, 'current')).create();
    final oldMusic =
        await Directory(p.join(sandbox.path, 'old-music')).create();
    final newMusic =
        await Directory(p.join(sandbox.path, 'new-music')).create();
    final oldSong = File(p.join(oldMusic.path, 'book.mp3'));
    final missing = File(p.join(oldMusic.path, 'missing.mp3'));
    final newSong = File(p.join(newMusic.path, 'book.mp3'));
    await oldSong.writeAsBytes([1, 2, 3]);
    await missing.writeAsBytes([4, 5]);
    await newSong.writeAsBytes([1, 2, 3]);
    Map<String, Object> index(Directory music, List<File> songs) => {
          'version': 1,
          'roots': [music.path],
          'folders': [
            {
              'path': music.path,
              'audios': [
                for (final song in songs)
                  {
                    'kind': 'local',
                    'path': song.path,
                    'title': p.basenameWithoutExtension(song.path),
                    'file_size': song.path == missing.path ? 2 : 3,
                  }
              ],
            }
          ],
        };
    await File(p.join(source.path, 'index.json'))
        .writeAsString(jsonEncode(index(oldMusic, [oldSong, missing])));
    await File(p.join(current.path, 'index.json'))
        .writeAsString(jsonEncode(index(newMusic, [newSong])));
    const prefs = TrackResumePreferences(mode: TrackResumeMode.allLocal);
    final store =
        TrackResumeStore(File(p.join(source.path, 'track_resume.json')));
    for (final song in [oldSong, missing]) {
      await store.remember(
          track: song.path,
          position: 450,
          duration: 3600,
          preferences: prefs,
          force: true);
    }
    final backup = File(p.join(sandbox.path, 'resume.bak'));
    await const CacheBackupService()
        .exportBackup(source: source, destination: backup);
    Directory? staged;
    await const CacheBackupService().restoreBackup(
      backup: backup,
      destination: Directory(p.join(sandbox.path, 'restored')),
      currentData: current,
      activateLocation: (_, value) async {
        staged = value;
      },
    );
    final restored =
        TrackResumeStore(File(p.join(staged!.path, 'track_resume.json')));
    expect(
        await restored.resumePosition(
            track: newSong.path, duration: 3600, preferences: prefs),
        450);
    expect(
        await restored.resumePosition(
            track: missing.path, duration: 3600, preferences: prefs),
        isNull);
  });
}
