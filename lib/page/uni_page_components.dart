import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/page/audio_sort_methods.dart';
import 'package:dan_player/component/playlist_destination_dialog.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class ShufflePlay<T> extends StatelessWidget {
  final List<T> contentList;
  const ShufflePlay({super.key, required this.contentList});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return FilledButton(
      key: const ValueKey('music-shuffle-action'),
      onPressed: contentList.isEmpty
          ? null
          : () => PlayService.instance.playbackService.shuffleAndPlay(
                contentList as List<Audio>,
              ),
      style: appToolbarControlStyle(context, primary: true),
      child: AppToolbarLabel(label: ui("随机播放"), icon: Symbols.shuffle),
    );
  }
}

class SortMethodComboBox<T> extends StatelessWidget {
  final List<T> contentList;
  final List<SortMethodDesc<T>> sortMethods;
  final SortMethodDesc<T> currSortMethod;
  final void Function(SortMethodDesc<T> sortMethod) setSortMethod;
  final SortOrder? sortOrder;
  final ValueChanged<SortOrder>? setSortOrder;
  final Object? scopeId;
  const SortMethodComboBox({
    super.key,
    required this.sortMethods,
    required this.contentList,
    required this.currSortMethod,
    required this.setSortMethod,
    this.sortOrder,
    this.setSortOrder,
    this.scopeId,
  });

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    var selected = sortMethods.indexOf(currSortMethod);
    if (selected < 0) {
      // Parent pages may rebuild their descriptors while retaining State.
      selected =
          sortMethods.indexWhere((item) => item.name == currSortMethod.name);
    }
    final audioMethod = currSortMethod is AudioSortMethodDesc
        ? currSortMethod as AudioSortMethodDesc
        : null;
    return AppSortButton<int>(
      value: selected < 0 ? 0 : selected,
      scopeId: scopeId,
      enabled: contentList.isNotEmpty,
      options: [
        for (var index = 0; index < sortMethods.length; index++)
          AppSortOption(
            value: index,
            key: ValueKey('sort-method-$index'),
            label: sortMethods[index].name,
            icon: sortMethods[index].icon,
            group: sortMethods[index] is AudioSortMethodDesc
                ? (sortMethods[index] as AudioSortMethodDesc).field.group
                : sortMethods[index].supportsReorder
                    ? ui("原始顺序")
                    : null,
          ),
      ],
      onChanged: (index) => setSortMethod(sortMethods[index]),
      direction: sortOrder == null || !currSortMethod.usesSortOrder
          ? null
          : sortOrder == SortOrder.ascending
              ? SortDirection.ascending
              : SortDirection.descending,
      onDirectionChanged: setSortOrder == null
          ? null
          : (direction) => setSortOrder!(direction == SortDirection.ascending
              ? SortOrder.ascending
              : SortOrder.decending),
      helpText: audioMethod != null
          ? [
              audioSortMissingValueNote,
              if (audioMethod.field.note != null) audioMethod.field.note!
            ].join('\n')
          : currSortMethod.supportsReorder
              ? ui("自定义顺序仅在主动拖动或移动条目时保存。")
              : audioSortMissingValueNote,
    );
  }
}

class SortOrderSwitch<T> extends StatelessWidget {
  final SortOrder sortOrder;
  final void Function(SortOrder order) setSortOrder;
  const SortOrderSwitch(
      {super.key, required this.sortOrder, required this.setSortOrder});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AppSegmentedControl<SortOrder>(
      value: sortOrder,
      options: [
        AppSegmentOption(
          value: SortOrder.ascending,
          key: const ValueKey('sort-order-ascending'),
          label: ui("升序"),
          icon: Icons.arrow_upward,
        ),
        AppSegmentOption(
          value: SortOrder.decending,
          key: const ValueKey('sort-order-descending'),
          label: ui("降序"),
          icon: Icons.arrow_downward,
        ),
      ],
      onChanged: setSortOrder,
    );
  }
}

class ContentViewSwitch<T> extends StatelessWidget {
  final ContentView contentView;
  final void Function(ContentView contentView) setContentView;
  const ContentViewSwitch(
      {super.key, required this.contentView, required this.setContentView});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AppSegmentedControl<ContentView>(
      value: contentView,
      semanticLabel: ui("页面视图"),
      options: [
        AppSegmentOption(
            value: ContentView.list, label: ui("列表"), icon: Symbols.list),
        AppSegmentOption(
            value: ContentView.table, label: ui("网格"), icon: Symbols.grid_view),
      ],
      onChanged: setContentView,
    );
  }
}

class AddAllToPlaylist extends StatelessWidget {
  const AddAllToPlaylist({super.key, required this.multiSelectController});

  final MultiSelectController<Audio> multiSelectController;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
      listenable: multiSelectController,
      builder: (context, _) => FilledButton(
        onPressed: multiSelectController.selected.isEmpty
            ? null
            : () => showAddAudiosToPlaylistDialog(
                  context,
                  multiSelectController.selected,
                ),
        style: appToolbarControlStyle(context, primary: true),
        child: AppToolbarLabel(label: ui("加入歌单…"), icon: Symbols.playlist_add),
      ),
    );
  }
}

class MultiSelectSelectOrClearAll<T> extends StatelessWidget {
  final MultiSelectController<T> multiSelectController;
  final List<T> contentList;

  const MultiSelectSelectOrClearAll(
      {super.key,
      required this.multiSelectController,
      required this.contentList});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
      listenable: multiSelectController,
      builder: (context, _) => IconButton.filledTonal(
        style: appToolbarControlStyle(context,
            primary: true, tonal: true, iconOnly: true),
        tooltip: multiSelectController.selected.isEmpty ? ui("全选") : ui("取消全选"),
        onPressed: () {
          if (multiSelectController.selected.isEmpty) {
            multiSelectController.selectAll(contentList);
          } else {
            multiSelectController.clear();
          }
        },
        icon: Icon(
          multiSelectController.selected.isEmpty
              ? Symbols.select_all
              : Symbols.clear_all,
        ),
      ),
    );
  }
}

class MultiSelectExit<T> extends StatelessWidget {
  final MultiSelectController<T> multiSelectController;

  const MultiSelectExit({super.key, required this.multiSelectController});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return IconButton.filledTonal(
      style: appToolbarControlStyle(context,
          primary: true, tonal: true, iconOnly: true),
      tooltip: ui("退出多选视图"),
      onPressed: () {
        multiSelectController.useMultiSelectView(false);
        multiSelectController.clear();
      },
      icon: const Icon(Symbols.cancel),
    );
  }
}
