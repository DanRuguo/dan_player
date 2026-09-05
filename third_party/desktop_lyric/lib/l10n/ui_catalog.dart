// Explicit application UI messages. Original media/user strings are not keys.
import 'ui_catalog_d.dart';
import 'ui_catalog_a.dart';
import 'ui_catalog_b.dart';
import 'ui_catalog_c.dart';
import 'ui_catalog_a_extra.dart';
import 'catalog_playlist_views.dart';
import 'catalog_controls.dart';
import 'catalog_tray.dart';
import 'catalog_palette_window.dart';
import 'catalog_rendering.dart';
import 'catalog_snapshot1.dart';
import 'catalog_metadata_editor.dart';
import 'catalog_incremental_library.dart';
import 'catalog_updates.dart';
import 'catalog_song_deletion.dart';
import 'catalog_snapshot2_localization.dart';
import 'catalog_custom_music_sources.dart';
import 'catalog_release_2604.dart';
import 'catalog_queue_tools.dart';
import 'catalog_song_comment_capabilities.dart';
import 'catalog_windows_tasks.dart';
import 'catalog_selection_release.dart';
import 'catalog_player_release.dart';
import 'catalog_api_release.dart';
import 'catalog_playlist_exchange.dart';

final Map<String, List<String>> uiCatalog = Map.unmodifiable({
  ...catalogSelectionRelease,
  ...catalogPlayerRelease,
  ...catalogApiRelease,
  ...catalogPlaylistExchange,
  ...uiCatalogA,
  ...uiCatalogB,
  ...uiCatalogC,
  ...uiCatalogD,
  ...uiCatalogAExtra,
  ...uiCatalogPlaylistViews,
  ...catalogControls,
  ...uiCatalogTray,
  ...catalogPaletteWindow,
  ...catalogRendering,
  ...catalogSnapshot1,
  ...catalogMetadataEditor,
  ...catalogIncrementalLibrary,
  ...catalogUpdates,
  ...uiCatalogSongDeletion,
  ...catalogSnapshot2Localization,
  ...catalogCustomMusicSources,
  ...catalogRelease2604,
  ...catalogQueueTools,
  ...uiCatalogSongCommentCapabilities,
  ...catalogWindowsTasks,
});
