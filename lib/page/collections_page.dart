import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/utils.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:dan_player/app_paths.dart' as app_paths;

class CollectionsPage extends StatefulWidget {
  const CollectionsPage({super.key});

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  Future<void> createCollection() async {
    final result = await showDialog<_CollectionDialogResult>(
      context: context,
      builder: (context) => const _CreateCollectionDialog(),
    );
    if (result == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    userCollections.add(
      UserCollection(
        id: createCollectionId(),
        name: result.name,
        audioPaths: result.audioPaths,
        imagePath: result.imagePath,
        createdAt: now,
        modifiedAt: now,
      ),
    );
    await saveCollections();
    setState(() {});
  }

  Future<void> editCollectionSongs(UserCollection collection) async {
    final audioPaths = await showDialog<List<String>>(
      context: context,
      builder: (context) => _EditCollectionSongsDialog(collection: collection),
    );
    if (audioPaths == null) return;

    collection
      ..audioPaths = audioPaths
      ..modifiedAt = DateTime.now().millisecondsSinceEpoch;
    await saveCollections();
    setState(() {});
  }

  Future<void> renameCollection(UserCollection collection) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameCollectionDialog(collection: collection),
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;

    collection
      ..name = trimmed
      ..modifiedAt = DateTime.now().millisecondsSinceEpoch;
    await saveCollections();
    setState(() {});
  }

  Future<void> changeCollectionImage(UserCollection collection) async {
    final imagePath = pickCollectionImage();
    if (imagePath == null) return;

    collection
      ..imagePath = imagePath
      ..modifiedAt = DateTime.now().millisecondsSinceEpoch;
    await saveCollections();
    setState(() {});
  }

  Future<void> deleteCollection(UserCollection collection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteCollectionDialog(collection: collection),
    );
    if (confirmed != true) return;

    userCollections.remove(collection);
    await saveCollections();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final contentList = allCollectionEntries();

    return UniPage<CollectionEntry>(
      pref: AppPreference.instance.collectionsPagePref,
      title: "合集",
      subtitle: "${contentList.length} 个合集",
      contentList: contentList,
      contentBuilder: (context, item, i, multiSelectController) =>
          _CollectionTile(
        entry: item,
        onEditSongs: editCollectionSongs,
        onRename: renameCollection,
        onChangeImage: changeCollectionImage,
        onDelete: deleteCollection,
      ),
      primaryAction: FilledButton.icon(
        onPressed: createCollection,
        icon: const Icon(Symbols.playlist_add_check),
        label: const Text("创建合集"),
        style: const ButtonStyle(
          fixedSize: WidgetStatePropertyAll(Size.fromHeight(40)),
        ),
      ),
      enableShufflePlay: false,
      enableSortMethod: true,
      enableSortOrder: true,
      enableContentViewSwitch: true,
      sortMethods: [
        SortMethodDesc(
          icon: Symbols.title,
          name: "名称",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.name.localeCompareTo(b.name));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.name.localeCompareTo(a.name));
                break;
            }
          },
        ),
        SortMethodDesc(
          icon: Symbols.music_note,
          name: "歌曲数量",
          method: (list, order) {
            switch (order) {
              case SortOrder.ascending:
                list.sort((a, b) => a.count.compareTo(b.count));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.count.compareTo(a.count));
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
                list.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
                break;
              case SortOrder.decending:
                list.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
                break;
            }
          },
        ),
      ],
    );
  }
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({
    required this.entry,
    required this.onEditSongs,
    required this.onRename,
    required this.onChangeImage,
    required this.onDelete,
  });

  final CollectionEntry entry;
  final Future<void> Function(UserCollection collection) onEditSongs;
  final Future<void> Function(UserCollection collection) onRename;
  final Future<void> Function(UserCollection collection) onChangeImage;
  final Future<void> Function(UserCollection collection) onDelete;

  @override
  Widget build(BuildContext context) {
    final collection = entry.collection;
    final scheme = Theme.of(context).colorScheme;

    return MenuAnchor(
      consumeOutsideTap: true,
      menuChildren: collection == null
          ? []
          : [
              MenuItemButton(
                leadingIcon: const Icon(Symbols.checklist),
                onPressed: () => onEditSongs(collection),
                child: const Text("更改所选歌曲"),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Symbols.drive_file_rename_outline),
                onPressed: () => onRename(collection),
                child: const Text("更改合集名"),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Symbols.image),
                onPressed: () => onChangeImage(collection),
                child: const Text("更改合集图片"),
              ),
              MenuItemButton(
                leadingIcon: Icon(Symbols.delete, color: scheme.error),
                onPressed: () => onDelete(collection),
                child: Text("删除合集", style: TextStyle(color: scheme.error)),
              ),
            ],
      builder: (context, controller, _) => InkWell(
        borderRadius: BorderRadius.circular(8.0),
        onTap: () {
          if (entry.isAlbumCollection) {
            context.push(app_paths.ALBUMS_PAGE);
          } else {
            context.push(app_paths.COLLECTION_DETAIL_PAGE, extra: collection);
          }
        },
        onSecondaryTapDown: (details) {
          if (collection == null) return;
          controller.open(position: details.localPosition.translate(0, -160));
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              _CollectionCover(entry: entry),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 16.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      entry.isAlbumCollection
                          ? "${entry.count} 张专辑"
                          : "${entry.count} 首歌曲",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionCover extends StatelessWidget {
  const _CollectionCover({required this.entry});

  final CollectionEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final collection = entry.collection;
    final imagePath = collection?.imagePath;

    if (entry.isAlbumCollection) {
      return _CoverFrame(
        child: Icon(
          Symbols.album,
          color: scheme.primary,
          size: 30.0,
        ),
      );
    }

    if (imagePath != null && File(imagePath).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10.0),
        child: Image.file(
          File(imagePath),
          width: 48.0,
          height: 48.0,
          fit: BoxFit.cover,
        ),
      );
    }

    final audios = collection?.audios ?? [];
    if (audios.isEmpty) {
      return _CoverFrame(
        child: Icon(
          Symbols.collections_bookmark,
          color: scheme.onSurfaceVariant,
          size: 30.0,
        ),
      );
    }

    return FutureBuilder(
      future: audios.first.cover,
      builder: (context, snapshot) {
        if (snapshot.data == null) {
          return _CoverFrame(
            child: Icon(
              Symbols.collections_bookmark,
              color: scheme.onSurfaceVariant,
              size: 30.0,
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(10.0),
          child: Image(
            image: snapshot.data!,
            width: 48.0,
            height: 48.0,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }
}

class _CoverFrame extends StatelessWidget {
  const _CoverFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 48.0,
      height: 48.0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.44),
          ),
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _CollectionDialogResult {
  const _CollectionDialogResult({
    required this.name,
    required this.audioPaths,
    this.imagePath,
  });

  final String name;
  final List<String> audioPaths;
  final String? imagePath;
}

class _CreateCollectionDialog extends StatefulWidget {
  const _CreateCollectionDialog();

  @override
  State<_CreateCollectionDialog> createState() =>
      _CreateCollectionDialogState();
}

class _CreateCollectionDialogState extends State<_CreateCollectionDialog> {
  final nameController = TextEditingController();
  final searchController = TextEditingController();
  final selectedPaths = <String>{};
  bool showSearch = false;
  String? imagePath;

  @override
  void initState() {
    super.initState();
    searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    nameController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void pickImage() {
    final path = pickCollectionImage();
    if (path == null) return;
    setState(() {
      imagePath = path;
    });
  }

  void submit() {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      showTextOnSnackBar("请先命名合集");
      return;
    }
    if (selectedPaths.isEmpty) {
      showTextOnSnackBar("请至少选择一首歌曲");
      return;
    }

    Navigator.pop(
      context,
      _CollectionDialogResult(
        name: name,
        audioPaths: selectedPaths.toList(),
        imagePath: imagePath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(24.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.0)),
      child: SizedBox(
        width: 760.0,
        height: 620.0,
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    "创建合集",
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 20.0,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    tooltip: showSearch ? "收起搜索" : "搜索歌曲",
                    onPressed: () {
                      setState(() {
                        showSearch = !showSearch;
                        if (!showSearch) searchController.clear();
                      });
                    },
                    icon: Icon(showSearch ? Symbols.close : Symbols.search),
                  ),
                ],
              ),
              if (showSearch) ...[
                const SizedBox(height: 10.0),
                Focus(
                  onFocusChange: HotkeysHelper.onFocusChanges,
                  child: TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Symbols.search),
                      labelText: "搜索歌曲",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14.0),
              Row(
                children: [
                  Expanded(
                    child: Focus(
                      onFocusChange: HotkeysHelper.onFocusChanges,
                      child: TextField(
                        autofocus: true,
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: "合集名称",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  FilledButton.tonalIcon(
                    onPressed: pickImage,
                    icon: const Icon(Symbols.image),
                    label: Text(imagePath == null ? "选择图片" : "已选择图片"),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),
              Expanded(
                child: _AudioSelectionList(
                  selectedPaths: selectedPaths,
                  searchQuery: searchController.text,
                  onChanged: () => setState(() {}),
                ),
              ),
              const SizedBox(height: 12.0),
              Row(
                children: [
                  Text(
                    "已选择 ${selectedPaths.length} 首",
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("取消"),
                  ),
                  const SizedBox(width: 8.0),
                  FilledButton(
                    onPressed: submit,
                    child: const Text("确定"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditCollectionSongsDialog extends StatefulWidget {
  const _EditCollectionSongsDialog({required this.collection});

  final UserCollection collection;

  @override
  State<_EditCollectionSongsDialog> createState() =>
      _EditCollectionSongsDialogState();
}

class _EditCollectionSongsDialogState
    extends State<_EditCollectionSongsDialog> {
  late final selectedPaths = widget.collection.audioPaths.toSet();
  final searchController = TextEditingController();
  bool showSearch = false;

  @override
  void initState() {
    super.initState();
    searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(24.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.0)),
      child: SizedBox(
        width: 720.0,
        height: 580.0,
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    "更改所选歌曲",
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 20.0,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    tooltip: showSearch ? "收起搜索" : "搜索歌曲",
                    onPressed: () {
                      setState(() {
                        showSearch = !showSearch;
                        if (!showSearch) searchController.clear();
                      });
                    },
                    icon: Icon(showSearch ? Symbols.close : Symbols.search),
                  ),
                ],
              ),
              if (showSearch) ...[
                const SizedBox(height: 10.0),
                Focus(
                  onFocusChange: HotkeysHelper.onFocusChanges,
                  child: TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Symbols.search),
                      labelText: "搜索歌曲",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12.0),
              Expanded(
                child: _AudioSelectionList(
                  selectedPaths: selectedPaths,
                  searchQuery: searchController.text,
                  onChanged: () => setState(() {}),
                ),
              ),
              const SizedBox(height: 12.0),
              Row(
                children: [
                  Text(
                    "已选择 ${selectedPaths.length} 首",
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("取消"),
                  ),
                  const SizedBox(width: 8.0),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, selectedPaths.toList()),
                    child: const Text("确定"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioSelectionList extends StatefulWidget {
  const _AudioSelectionList({
    required this.selectedPaths,
    required this.searchQuery,
    required this.onChanged,
  });

  final Set<String> selectedPaths;
  final String searchQuery;
  final VoidCallback onChanged;

  @override
  State<_AudioSelectionList> createState() => _AudioSelectionListState();
}

class _AudioSelectionListState extends State<_AudioSelectionList> {
  final scrollController = ScrollController();

  late final audios = List<Audio>.from(AudioLibrary.instance.audioCollection)
    ..sort((a, b) => a.displayTitle.localeCompareTo(b.displayTitle));

  List<Audio> get filteredAudios {
    final query = widget.searchQuery.trim().toLowerCase();
    if (query.isEmpty) return audios;

    return audios.where((audio) {
      final text =
          "${audio.displayTitle} ${audio.title} ${audio.artist} ${audio.album}"
              .toLowerCase();
      return text.contains(query);
    }).toList();
  }

  void toggle(Audio audio) {
    setState(() {
      if (!widget.selectedPaths.add(audio.path)) {
        widget.selectedPaths.remove(audio.path);
      }
    });
    widget.onChanged();
  }

  void select(Audio audio) {
    if (widget.selectedPaths.contains(audio.path)) return;
    setState(() {
      widget.selectedPaths.add(audio.path);
    });
    widget.onChanged();
  }

  void unselect(Audio audio) {
    if (!widget.selectedPaths.contains(audio.path)) return;
    setState(() {
      widget.selectedPaths.remove(audio.path);
    });
    widget.onChanged();
  }

  void handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !scrollController.hasClients) return;

    final position = scrollController.position;
    final target = (position.pixels + event.scrollDelta.dy)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    scrollController.jumpTo(target);
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _AudioSelectionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery &&
        scrollController.hasClients) {
      scrollController.jumpTo(scrollController.position.minScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visibleAudios = filteredAudios;

    if (visibleAudios.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.search_off,
              size: 36.0,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8.0),
            Text(
              "没有找到匹配歌曲",
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Listener(
      onPointerSignal: handlePointerSignal,
      child: Material(
        type: MaterialType.transparency,
        child: ListView.builder(
          controller: scrollController,
          primary: false,
          physics: const ClampingScrollPhysics(),
          itemCount: visibleAudios.length,
          itemExtent: 56.0,
          itemBuilder: (context, i) {
            final audio = visibleAudios[i];
            final selected = widget.selectedPaths.contains(audio.path);

            return GestureDetector(
              onTap: () => select(audio),
              onDoubleTap: () {
                if (selected) {
                  unselect(audio);
                } else {
                  select(audio);
                }
              },
              onSecondaryTapDown: (_) => unselect(audio),
              child: ListTile(
                leading: Checkbox(
                  value: selected,
                  onChanged: (_) => toggle(audio),
                ),
                title: Text(
                  audio.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  "${audio.artist} - ${audio.album}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: selected,
                selectedTileColor:
                    scheme.secondaryContainer.withValues(alpha: 0.40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RenameCollectionDialog extends StatelessWidget {
  const _RenameCollectionDialog({required this.collection});

  final UserCollection collection;

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: collection.name);

    return AlertDialog(
      title: const Text("更改合集名"),
      content: Focus(
        onFocusChange: HotkeysHelper.onFocusChanges,
        child: TextField(
          autofocus: true,
          controller: controller,
          decoration: const InputDecoration(
            labelText: "合集名称",
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("取消"),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text("确定"),
        ),
      ],
    );
  }
}

class _DeleteCollectionDialog extends StatelessWidget {
  const _DeleteCollectionDialog({required this.collection});

  final UserCollection collection;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("删除合集"),
      content: Text("确定删除“${collection.name}”吗？歌曲文件不会被删除。"),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("取消"),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text("删除"),
        ),
      ],
    );
  }
}

String? pickCollectionImage() {
  final picker = OpenFilePicker();
  picker
    ..title = "选择合集图片"
    ..filterSpecification = {
      "图片文件": "*.jpg;*.jpeg;*.png;*.webp;*.bmp",
      "所有文件": "*.*",
    };

  return picker.getFile()?.path;
}
