import 'package:dan_player/app_preference.dart';
import 'package:dan_player/page/audio_sort_methods.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/audio_columns.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/online_library.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class AudiosPage extends StatelessWidget {
  final Audio? locateTo;
  const AudiosPage({super.key, this.locateTo});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        OnlineLibrary.instance,
        AudioLibrary.changes,
      ]),
      builder: (context, _) => _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    final contentList = List<Audio>.from(AudioLibrary.instance.audioCollection);
    final multiSelectController = MultiSelectController<Audio>();
    return UniPage<Audio>(
      pref: AppPreference.instance.audiosPagePref,
      title: ui("音乐"),
      subtitle: ui("{0} 首乐曲", [contentList.length]),
      contentList: contentList,
      contentBuilder: (context, item, i, multiSelectController) => AudioTile(
        audioIndex: i,
        playlist: contentList,
        focus: item == locateTo,
        multiSelectController: multiSelectController,
        columns: AudioColumnsScope.of(context),
      ),
      primaryAction: FilledButton.tonal(
        key: const ValueKey('music-search-action'),
        onPressed: () => context.push(app_paths.SEARCH_PAGE),
        style: appToolbarControlStyle(context, primary: true, tonal: true),
        child: AppToolbarLabel(label: ui("搜索"), icon: Symbols.search),
      ),
      enableShufflePlay: true,
      enableSortMethod: true,
      enableSortOrder: true,
      enableContentViewSwitch: true,
      enableAudioColumns: true,
      locateTo: locateTo,
      multiSelectController: multiSelectController,
      multiSelectViewActions: [
        AddAllToPlaylist(multiSelectController: multiSelectController),
        MultiSelectSelectOrClearAll(
          multiSelectController: multiSelectController,
          contentList: contentList,
        ),
        MultiSelectExit(multiSelectController: multiSelectController),
      ],
      sortMethods: audioSortMethods(
        AudioSortProfile.library,
        custom: SortMethodDesc<Audio>(
          icon: Symbols.drag_handle,
          name: ui("自定义"),
          usesSortOrder: false,
          supportsReorder: true,
          method: (list, order) => customAudioOrder.applyTo(list),
          onReorder: (list) => customAudioOrder.setFromAudios(list),
        ),
      ),
    );
  }
}
