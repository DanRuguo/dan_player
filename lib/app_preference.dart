import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/utils.dart';

class PagePreference {
  int sortMethod;
  SortOrder sortOrder;
  ContentView contentView;

  PagePreference(this.sortMethod, this.sortOrder, this.contentView);

  Map toMap() => {
        "sortMethod": sortMethod,
        "sortOrder": sortOrder.name,
        "contentView": contentView.name,
      };

  factory PagePreference.fromMap(Map map) => PagePreference(
        map["sortMethod"] ?? 0,
        SortOrder.fromString(map["sortOrder"]) ?? SortOrder.ascending,
        ContentView.fromString(map["contentView"]) ?? ContentView.list,
      );
}

class NowPlayingPagePreference {
  NowPlayingViewMode nowPlayingViewMode;
  LyricTextAlign lyricTextAlign;
  double lyricFontSize;
  double translationFontSize;

  NowPlayingPagePreference(
    this.nowPlayingViewMode,
    this.lyricTextAlign,
    this.lyricFontSize,
    this.translationFontSize,
  );

  Map toMap() => {
        "nowPlayingViewMode": nowPlayingViewMode.name,
        "lyricTextAlign": lyricTextAlign.name,
        "lyricFontSize": lyricFontSize,
        "translationFontSize": translationFontSize,
      };

  factory NowPlayingPagePreference.fromMap(Map map) {
    return NowPlayingPagePreference(
      NowPlayingViewMode.fromString(map["nowPlayingViewMode"]) ??
          NowPlayingViewMode.withLyric,
      LyricTextAlign.fromString(map["lyricTextAlign"]) ?? LyricTextAlign.left,
      map["lyricFontSize"] ?? 22.0,
      map["translationFontSize"] ?? 18.0,
    );
  }
}

class PlaybackPreference {
  PlayMode playMode;
  double volumeDsp;
  bool eqEnabled;
  List<double> eqGains;

  PlaybackPreference(
    this.playMode,
    this.volumeDsp, {
    this.eqEnabled = false,
    List<double>? eqGains,
  }) : eqGains = eqGains ?? List.filled(BassPlayer.eqBandCenters.length, 0.0);

  Map toMap() => {
        "playMode": playMode.name,
        "volumeDsp": volumeDsp,
        "eqEnabled": eqEnabled,
        "eqGains": eqGains,
      };

  factory PlaybackPreference.fromMap(Map map) {
    final rawGains = map["eqGains"];
    final gains = rawGains is List
        ? [
            for (final value in rawGains) value is num ? value.toDouble() : 0.0,
          ]
        : null;
    return PlaybackPreference(
      PlayMode.fromString(map["playMode"]) ?? PlayMode.forward,
      (map["volumeDsp"] as num?)?.toDouble() ?? 1.0,
      eqEnabled: map["eqEnabled"] == true,
      eqGains: gains,
    );
  }
}

class AppPreference {
  var audiosPagePref = PagePreference(0, SortOrder.ascending, ContentView.list);

  var artistsPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.table);

  var artistDetailPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.list);

  var albumsPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.table);

  var albumDetailPagePref =
      PagePreference(2, SortOrder.ascending, ContentView.list);

  var collectionsPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.table);

  var collectionDetailPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.list);

  var foldersPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.list);

  var folderDetailPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.list);

  var playlistsPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.list);

  var playlistDetailPagePref =
      PagePreference(0, SortOrder.ascending, ContentView.list);

  // Old preference records remain intact. The unified view inherits the
  // collection layout once and then stores its own explicit user choice.
  ContentView? unifiedPlaylistsView;
  ContentView? unifiedPlaylistDetailsView;
  // Three-way playlist layouts are separate from the old library/list enum.
  // Keep old fields intact so older versions retain their last known layout.
  PlaylistViewMode? unifiedPlaylistsLayout;
  PlaylistViewMode? unifiedPlaylistDetailsLayout;
  // Display sorting never rewrites a playlist's drag-defined custom order.
  // Separate per-level preferences also retain a child's chosen default when
  // a parent queue is expanded depth-first.
  final Map<String, String> unifiedPlaylistSortModes = {};

  int startPage = 0;

  var playbackPref = PlaybackPreference(PlayMode.forward, 1.0);

  var nowPlayingPagePref = NowPlayingPagePreference(
      NowPlayingViewMode.withLyric, LyricTextAlign.left, 22.0, 18.0);

  Future<void> save() async {
    try {
      final supportPath = (await getAppDataDir()).path;
      final appPreferencePath = "$supportPath\\app_preference.json";

      Map prefMap = {
        "audiosPagePref": audiosPagePref.toMap(),
        "artistsPagePref": artistsPagePref.toMap(),
        "artistDetailPagePref": artistDetailPagePref.toMap(),
        "albumsPagePref": albumsPagePref.toMap(),
        "albumDetailPagePref": albumDetailPagePref.toMap(),
        "collectionsPagePref": collectionsPagePref.toMap(),
        "collectionDetailPagePref": collectionDetailPagePref.toMap(),
        "foldersPagePref": foldersPagePref.toMap(),
        "folderDetailPagePref": folderDetailPagePref.toMap(),
        "playlistsPagePref": playlistsPagePref.toMap(),
        "playlistDetailPagePref": playlistDetailPagePref.toMap(),
        "unifiedPlaylistsView": unifiedPlaylistsView?.name,
        "unifiedPlaylistDetailsView": unifiedPlaylistDetailsView?.name,
        "unifiedPlaylistsLayout": unifiedPlaylistsLayout?.name,
        "unifiedPlaylistDetailsLayout": unifiedPlaylistDetailsLayout?.name,
        "unifiedPlaylistSortModes": unifiedPlaylistSortModes,
        "startPage": startPage,
        "playbackPref": playbackPref.toMap(),
        "nowPlayingPagePref": nowPlayingPagePref.toMap(),
      };

      final prefJson = json.encode(prefMap);
      final output = await File(appPreferencePath).create(recursive: true);
      await output.writeAsString(prefJson);
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
    }
  }

  static Future<void> read() async {
    try {
      final supportPath = (await getAppDataDir()).path;
      final appPreferencePath = "$supportPath\\app_preference.json";

      final prefJson = await File(appPreferencePath).readAsString();
      final Map prefMap = json.decode(prefJson);

      instance.audiosPagePref =
          PagePreference.fromMap(prefMap["audiosPagePref"]);
      instance.artistsPagePref =
          PagePreference.fromMap(prefMap["artistsPagePref"]);
      instance.artistDetailPagePref = PagePreference.fromMap(
        prefMap["artistDetailPagePref"],
      );
      instance.albumsPagePref =
          PagePreference.fromMap(prefMap["albumsPagePref"]);
      instance.albumDetailPagePref = PagePreference.fromMap(
        prefMap["albumDetailPagePref"],
      );
      if (prefMap["collectionsPagePref"] != null) {
        instance.collectionsPagePref = PagePreference.fromMap(
          prefMap["collectionsPagePref"],
        );
      }
      if (prefMap["collectionDetailPagePref"] != null) {
        instance.collectionDetailPagePref = PagePreference.fromMap(
          prefMap["collectionDetailPagePref"],
        );
      }
      instance.foldersPagePref =
          PagePreference.fromMap(prefMap["foldersPagePref"]);
      instance.folderDetailPagePref = PagePreference.fromMap(
        prefMap["folderDetailPagePref"],
      );
      if (prefMap['playlistsPagePref'] is Map) {
        instance.playlistsPagePref =
            PagePreference.fromMap(prefMap['playlistsPagePref']);
      }
      if (prefMap['playlistDetailPagePref'] is Map) {
        instance.playlistDetailPagePref =
            PagePreference.fromMap(prefMap['playlistDetailPagePref']);
      }
      if (prefMap['unifiedPlaylistsView'] is String) {
        instance.unifiedPlaylistsView =
            ContentView.fromString(prefMap['unifiedPlaylistsView']);
      }
      if (prefMap['unifiedPlaylistDetailsView'] is String) {
        instance.unifiedPlaylistDetailsView =
            ContentView.fromString(prefMap['unifiedPlaylistDetailsView']);
      }
      instance.unifiedPlaylistsLayout =
          PlaylistViewMode.parse(prefMap['unifiedPlaylistsLayout']);
      instance.unifiedPlaylistDetailsLayout =
          PlaylistViewMode.parse(prefMap['unifiedPlaylistDetailsLayout']);
      instance.unifiedPlaylistSortModes.clear();
      final savedPlaylistSorts = prefMap['unifiedPlaylistSortModes'];
      if (savedPlaylistSorts is Map) {
        for (final entry in savedPlaylistSorts.entries) {
          if (entry.key is String && entry.value is String) {
            instance.unifiedPlaylistSortModes[entry.key] = entry.value;
          }
        }
      }
      instance.startPage = prefMap["startPage"] ?? 0;
      if (instance.startPage < 0 || instance.startPage >= 5) {
        instance.startPage = 0;
      }
      instance.playbackPref =
          PlaybackPreference.fromMap(prefMap["playbackPref"]);
      instance.nowPlayingPagePref =
          NowPlayingPagePreference.fromMap(prefMap["nowPlayingPagePref"]);
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
    }
  }

  static final AppPreference instance = AppPreference();
}
