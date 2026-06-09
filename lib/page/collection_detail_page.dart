import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class CollectionDetailPage extends StatefulWidget {
  const CollectionDetailPage({super.key, required this.collection});

  final UserCollection collection;

  @override
  State<CollectionDetailPage> createState() => _CollectionDetailPageState();
}

class _CollectionDetailPageState extends State<CollectionDetailPage> {
  final multiSelectController = MultiSelectController<Audio>();

  @override
  Widget build(BuildContext context) {
    widget.collection.sanitize();
    final contentList = widget.collection.audios;
    final scheme = Theme.of(context).colorScheme;

    return UniPage<Audio>(
      pref: AppPreference.instance.collectionDetailPagePref,
      title: widget.collection.name,
      subtitle: "${contentList.length} 首歌曲",
      contentList: contentList,
      contentBuilder: (context, item, i, multiSelectController) => AudioTile(
        audioIndex: i,
        playlist: contentList,
        multiSelectController: multiSelectController,
      ),
      enableShufflePlay: true,
      enableSortMethod: true,
      enableSortOrder: true,
      enableContentViewSwitch: true,
      multiSelectController: multiSelectController,
      multiSelectViewActions: [
        IconButton.filled(
          tooltip: "移除选中歌曲",
          onPressed: () async {
            final selectedPaths = multiSelectController.selected
                .map((audio) => audio.path)
                .toSet();
            setState(() {
              widget.collection.audioPaths
                  .removeWhere((path) => selectedPaths.contains(path));
              widget.collection.modifiedAt =
                  DateTime.now().millisecondsSinceEpoch;
            });
            await saveCollections();
            multiSelectController.useMultiSelectView(false);
          },
          style: ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(scheme.error),
            foregroundColor: WidgetStatePropertyAll(scheme.onError),
          ),
          icon: const Icon(Symbols.delete),
        ),
        MultiSelectSelectOrClearAll(
          multiSelectController: multiSelectController,
          contentList: contentList,
        ),
        MultiSelectExit(multiSelectController: multiSelectController),
      ],
      sortMethods: [
        SortMethodDesc(
          icon: Symbols.title,
          name: "名称",
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
          name: "最新",
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
          name: "最近修改",
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
            final byPath = {for (final audio in list) audio.path: audio};
            final ordered = <Audio>[];
            for (final path in widget.collection.audioPaths) {
              final audio = byPath[path];
              if (audio != null) ordered.add(audio);
            }
            list
              ..clear()
              ..addAll(ordered);
          },
          onReorder: (list) async {
            widget.collection
              ..audioPaths = list.map((audio) => audio.path).toList()
              ..modifiedAt = DateTime.now().millisecondsSinceEpoch;
            await saveCollections();
          },
        ),
      ],
    );
  }
}
