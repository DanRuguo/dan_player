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

final Map<String, List<String>> uiCatalog = Map.unmodifiable({
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
});
