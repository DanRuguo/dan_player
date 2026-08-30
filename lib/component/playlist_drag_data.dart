import 'package:dan_player/library/playlist.dart';

/// An existing tree relationship, never a request to move a music file.
class PlaylistDragData {
  const PlaylistDragData({
    required this.entryId,
    required this.sourceParent,
    required this.label,
  });

  final String entryId;
  final Playlist? sourceParent;
  final String label;
}
