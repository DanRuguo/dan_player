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

class AudiosPage extends StatefulWidget {
  final Audio? locateTo;
  const AudiosPage({super.key, this.locateTo});

  @override
  State<AudiosPage> createState() => _AudiosPageState();
}

class _AudiosPageState extends State<AudiosPage> {
  final multiSelectController = MultiSelectController<Audio>();

  @override
  void dispose() {
    multiSelectController.dispose();
    super.dispose();
  }

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
    return UniPage<Audio>(
      pref: AppPreference.instance.audiosPagePref,
      title: ui("音乐"),
      subtitle: ui("{0} 首乐曲", [contentList.length]),
      contentList: contentList,
      contentBuilder: (context, item, i, multiSelectController) => AudioTile(
        audioIndex: i,
        playlist: contentList,
        focus: item == widget.locateTo,
        multiSelectController: multiSelectController,
        columns: AudioColumnsScope.of(context),
      ),
      primaryAction: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.tonal(
            key: const ValueKey('music-search-action'),
            onPressed: () => context.push(app_paths.SEARCH_PAGE),
            style: appToolbarControlStyle(context, primary: true, tonal: true),
            child: AppToolbarLabel(label: ui("搜索"), icon: Symbols.search),
          ),
        ],
      ),
      enableShufflePlay: true,
      enableSortMethod: true,
      enableSortOrder: true,
      enableContentViewSwitch: true,
      enableAudioColumns: true,
      locateTo: widget.locateTo,
      multiSelectController: multiSelectController,
      multiSelectViewActions: [
        AudioMultiSelectionActions(
          controller: multiSelectController,
          contentList: contentList,
        ),
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
