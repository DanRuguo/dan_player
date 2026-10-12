import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/component/audio_selection_toolbar.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/page/audio_sort_methods.dart';
import 'package:dan_player/component/playlist_destination_dialog.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

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
            : () async {
                final session = multiSelectController.session;
                final committed = await showAddAudiosToPlaylistDialog(
                    context, List<Audio>.of(multiSelectController.selected));
                if (committed && multiSelectController.enableMultiSelectView) {
                  multiSelectController.exitMultiSelect(
                      expectedSession: session);
                }
              },
        style: appToolbarControlStyle(context, primary: true),
        child: AppToolbarLabel(label: ui("加入歌单…"), icon: Symbols.playlist_add),
      ),
    );
  }
}

class AudioMultiSelectionActions extends StatelessWidget {
  const AudioMultiSelectionActions({
    super.key,
    required this.controller,
    required this.contentList,
    this.onPlay,
    this.onPlayCommitted,
    this.onAddToPlaylist,
    this.onExport,
    this.onAddToPlaylistCommitted,
    this.onExportCommitted,
  });

  final MultiSelectController<Audio> controller;
  final List<Audio> contentList;
  final SelectedAudioAction? onPlay;
  final SelectedAudioCommitAction? onPlayCommitted;
  final SelectedAudioAction? onAddToPlaylist;
  final SelectedAudioAction? onExport;
  final SelectedAudioCommitAction? onAddToPlaylistCommitted, onExportCommitted;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final selected = controller.selectedInOrder(contentList);
          final session = controller.session;
          VoidCallback? range(MultiSelectRange kind) =>
              controller.canSelectRange(contentList, kind)
                  ? () => controller.selectRange(contentList, kind)
                  : null;
          return AudioSelectionToolbar(
            selected: selected,
            hiddenSelectionCount: controller.selected.length - selected.length,
            hasItems: contentList.isNotEmpty,
            allVisibleSelected: contentList.isNotEmpty &&
                contentList.every(controller.selected.contains),
            onToggleAll: () => controller.toggleAllVisible(contentList),
            onInvert: () => controller.invertVisible(contentList),
            onExit: controller.exitMultiSelect,
            onPlay: onPlay,
            onPlayCommitted: onPlayCommitted,
            onAddToPlaylist: onAddToPlaylist,
            onExport: onExport,
            onAddToPlaylistCommitted: onAddToPlaylistCommitted,
            onExportCommitted: onExportCommitted,
            onCommitted: () {
              if (controller.enableMultiSelectView) {
                controller.exitMultiSelect(expectedSession: session);
              }
            },
            isActionCurrent: () => controller.isSessionCurrent(session),
            includeRangeActions: true,
            onSelectBetween: range(MultiSelectRange.between),
            onSelectAbove: range(MultiSelectRange.above),
            onSelectBelow: range(MultiSelectRange.below),
          );
        },
      );
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
        tooltip: contentList.isNotEmpty &&
                contentList.every(multiSelectController.selected.contains)
            ? ui("取消全选")
            : ui("全选"),
        onPressed: () {
          multiSelectController.toggleAllVisible(contentList);
        },
        icon: Icon(
          contentList.isNotEmpty &&
                  contentList.every(multiSelectController.selected.contains)
              ? Symbols.clear_all
              : Symbols.select_all,
        ),
      ),
    );
  }
}

class MultiSelectRangeActions<T> extends StatelessWidget {
  const MultiSelectRangeActions(
      {super.key, required this.controller, required this.contentList});
  final MultiSelectController<T> controller;
  final List<T> contentList;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        VoidCallback? range(MultiSelectRange kind) =>
            controller.canSelectRange(contentList, kind)
                ? () => controller.selectRange(contentList, kind)
                : null;
        return SelectionRangeMenuButton(
            onBetween: range(MultiSelectRange.between),
            onAbove: range(MultiSelectRange.above),
            onBelow: range(MultiSelectRange.below));
      });
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
        multiSelectController.exitMultiSelect();
      },
      icon: const Icon(Symbols.cancel),
    );
  }
}
