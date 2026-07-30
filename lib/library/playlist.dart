// ignore_for_file: non_constant_identifier_names

import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/utils.dart';

List<Playlist> PLAYLISTS = [];

Future<void> readPlaylists() async {
  try {
    final supportPath = (await getAppDataDir()).path;
    final playlistsPath = "$supportPath\\playlists.json";
    final playlistsFile = File(playlistsPath);
    if (!await playlistsFile.exists()) {
      PLAYLISTS.clear();
      return;
    }

    final playlistsStr = await playlistsFile.readAsString();
    final List playlistsJson = json.decode(playlistsStr);
    final loaded = <Playlist>[];

    for (Map item in playlistsJson) {
      loaded.add(Playlist.fromMap(item));
    }
    PLAYLISTS
      ..clear()
      ..addAll(loaded);
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }
}

Future<void> savePlaylists() async {
  try {
    final supportPath = (await getAppDataDir()).path;
    final playlistsPath = "$supportPath\\playlists.json";

    List<Map> playlistMaps = [];
    for (final item in PLAYLISTS) {
      playlistMaps.add(item.toMap());
    }

    final playlistsJson = json.encode(playlistMaps);
    final output = await File(playlistsPath).create(recursive: true);
    await output.writeAsString(playlistsJson);
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }
}

class Playlist {
  String name;

  /// path, audio
  Map<String, Audio> audios;

  Playlist(this.name, this.audios);

  Map toMap() {
    final List<Map> audioMaps = [];
    for (var item in audios.values) {
      audioMaps.add(item.toMap());
    }
    return {"name": name, "audios": audioMaps};
  }

  factory Playlist.fromMap(Map map) {
    final Map<String, Audio> audios = {};
    final List audioMaps = map["audios"];
    for (var item in audioMaps) {
      final path = item["path"] as String;
      final audio =
          AudioLibrary.instance.audioByPath[path] ?? Audio.fromMap(item);
      audios[audio.path] = audio;
    }
    return Playlist(map["name"], audios);
  }
}
