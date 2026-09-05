import 'package:dan_player/library/audio_library.dart';
import 'package:flutter_test/flutter_test.dart';

/// No settings singleton, native reader, music files or persistence.
class MetadataTestAudio extends Fake implements Audio {
  @override
  String path = 'D:/metadata-fixture/old.mp3';
  @override
  String title = 'Old title';
  @override
  String artist = 'Artist';
  @override
  String album = 'Album';
  @override
  int modified = 1;
  @override
  bool get isOnline => false;
  @override
  bool get isLocal => true;
  @override
  bool get isCueTrack => false;
  @override
  bool get canEditLocalFile => true;
  @override
  String get localFilePath => path;

  @override
  void applyEditedMetadata(
      {required String newPath,
      required String newTitle,
      required String newArtist,
      required String newAlbum,
      required int newModified}) {
    path = newPath;
    title = newTitle;
    artist = newArtist;
    album = newAlbum;
    modified = newModified;
  }
}
