import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class AudiosPage extends StatelessWidget {
  final Audio? locateTo;
  const AudiosPage({super.key, this.locateTo});

  @override
  Widget build(BuildContext context) {
    final contentList = List<Audio>.from(AudioLibrary.instance.audioCollection);
    final multiSelectController = MultiSelectController<Audio>();
    return UniPage<Audio>(
      pref: AppPreference.instance.audiosPagePref,
      title: "音乐",
      subtitle: "${contentList.length} 首乐曲",
      contentList: contentList,
      contentBuilder: (context, item, i, multiSelectController) => AudioTile(
        audioIndex: i,
        playlist: contentList,
        focus: item == locateTo,
        multiSelectController: multiSelectController,
      ),
      primaryAction: FilledButton.tonalIcon(
        onPressed: () => context.push(app_paths.SEARCH_PAGE),
        icon: const Icon(Symbols.search),
        label: const Text("搜索"),
        style: const ButtonStyle(
          fixedSize: WidgetStatePropertyAll(Size.fromHeight(40)),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18.0),
          ),
        ),
      ),
      enableShufflePlay: true,
      enableSortMethod: true,
      enableSortOrder: true,
      enableContentViewSwitch: true,
      locateTo: locateTo,
      multiSelectController: multiSelectController,
      multiSelectViewActions: [
        MultiSelectSelectOrClearAll(
          multiSelectController: multiSelectController,
          contentList: contentList,
        ),
        MultiSelectExit(multiSelectController: multiSelectController),
      ],
      sortMethods: [
        SortMethodDesc(
          icon: Symbols.title,
          name: "标题",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort(
                    (a, b) => a.displayTitle.localeCompareTo(b.displayTitle));
                break;
              case SortOrder.decending:
                list.sort(
                    (a, b) => b.displayTitle.localeCompareTo(a.displayTitle));
                break;
            }
          },
        ),
        SortMethodDesc(
          icon: Symbols.artist,
          name: "艺术家",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.artist.localeCompareTo(b.artist));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.artist.localeCompareTo(a.artist));
                break;
            }
          },
        ),
        SortMethodDesc(
          icon: Symbols.album,
          name: "专辑",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.album.localeCompareTo(b.album));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.album.localeCompareTo(a.album));
                break;
            }
          },
        ),
        SortMethodDesc(
          icon: Symbols.add,
          name: "创建时间",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.created.compareTo(b.created));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.created.compareTo(a.created));
                break;
            }
          },
        ),
        SortMethodDesc(
          icon: Symbols.edit,
          name: "修改时间",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.modified.compareTo(b.modified));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.modified.compareTo(a.modified));
                break;
            }
          },
        ),
        SortMethodDesc(
          icon: Symbols.drag_handle,
          name: "自定义",
          usesSortOrder: false,
          supportsReorder: true,
          method: (list, order) {
            customAudioOrder.applyTo(list);
          },
          onReorder: (list) => customAudioOrder.setFromAudios(list),
        ),
      ],
    );
  }
}
