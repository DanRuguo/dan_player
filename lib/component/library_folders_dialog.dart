import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/utils.dart' show showAppNotice;
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Edits only the caller's draft; saving and scanning remain caller-owned.
class LibraryFoldersDialog extends StatefulWidget {
  const LibraryFoldersDialog({
    super.key,
    required this.folders,
    required this.folderName,
    required this.onAdd,
    required this.onRemove,
    required this.onCancel,
    required this.onConfirm,
    this.editing = true,
    this.progress,
  });

  final List<String> folders;
  final String Function(String path) folderName;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final bool editing;
  final Widget? progress;

  @override
  State<LibraryFoldersDialog> createState() => _LibraryFoldersDialogState();
}

class _LibraryFoldersDialogState extends State<LibraryFoldersDialog> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: ListView(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  children: [
                    LayoutBuilder(builder: (context, constraints) {
                      final compact = constraints.maxWidth < 420 &&
                          MediaQuery.textScalerOf(context).scale(1) > 1.4;
                      return AppDialogTitle(
                        ui('管理文件夹'),
                        style: theme.textTheme.titleLarge,
                        leading: compact
                            ? null
                            : Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    borderRadius: AppShape.controlRadius),
                                child: Icon(Symbols.folder_managed,
                                    color: scheme.onPrimaryContainer),
                              ),
                        trailing: compact
                            ? null
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                    borderRadius: AppShape.controlRadius),
                                child: Text('${widget.folders.length}',
                                    semanticsLabel:
                                        ui('{0} 个文件夹', [widget.folders.length]),
                                    style: theme.textTheme.labelLarge
                                        ?.copyWith(color: scheme.primary)),
                              ),
                        subtitle: compact
                            ? Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                    ui('{0} 个文件夹', [widget.folders.length]),
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(color: scheme.primary)),
                              )
                            : null,
                      );
                    }),
                    const SizedBox(height: 14),
                    Text(
                      ui('添加音乐所在的文件夹，确认后刷新曲库。'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ui('移除仅取消收录，不会删除音乐文件。'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    if (!widget.editing)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: widget.progress ??
                            Center(child: Text(ui('正在准备扫描'))),
                      )
                    else if (widget.folders.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 28),
                        decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: AppShape.surfaceRadius),
                        child: Column(
                          children: [
                            Icon(Symbols.create_new_folder,
                                size: 36, color: scheme.primary),
                            const SizedBox(height: 12),
                            Text(ui('还没有音乐文件夹'),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium),
                            const SizedBox(height: 6),
                            Text(ui('添加文件夹，开始整理你的音乐。'),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      )
                    else
                      for (var index = 0;
                          index < widget.folders.length;
                          index++) ...[
                        if (index > 0) const SizedBox(height: 10),
                        _FolderCard(
                          key: ValueKey('library-folder-$index'),
                          path: widget.folders[index],
                          name: widget.folderName(widget.folders[index]),
                          onRemove: () => widget.onRemove(index),
                        ),
                      ],
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(16),
              child: AppDialogActions(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: widget.editing ? widget.onAdd : null,
                    icon: const Icon(Symbols.create_new_folder, size: 20),
                    label: Text(ui('添加文件夹')),
                  ),
                  TextButton(
                      onPressed: widget.editing ? widget.onCancel : null,
                      child: Text(ui('取消'))),
                  FilledButton.icon(
                      onPressed: widget.editing ? widget.onConfirm : null,
                      icon: const Icon(Symbols.check, size: 20),
                      label: Text(ui('确定'))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard(
      {super.key,
      required this.path,
      required this.name,
      required this.onRemove});

  final String path;
  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: AppShape.surfaceRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Symbols.folder, size: 24, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Tooltip(
                    message: name,
                    child: Text(name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: scheme.onSurface)),
                  ),
                ),
                IconButton(
                  tooltip: ui('复制路径'),
                  style: IconButton.styleFrom(foregroundColor: scheme.primary),
                  icon: const Icon(Symbols.content_copy, size: 20),
                  onPressed: () async {
                    try {
                      await Clipboard.setData(ClipboardData(text: path));
                      if (context.mounted) {
                        showAppNotice(ui('已复制路径'), context: context);
                      }
                    } catch (_) {
                      if (context.mounted) {
                        showAppNotice(ui('复制失败，请选择路径文字后重试。'),
                            context: context, kind: AppNoticeKind.error);
                      }
                    }
                  },
                ),
                IconButton(
                  tooltip: ui('移除文件夹'),
                  style: IconButton.styleFrom(foregroundColor: scheme.error),
                  icon: const Icon(Symbols.folder_off, size: 20),
                  onPressed: onRemove,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: SelectableText(path,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5)),
            ),
          ],
        ),
      ),
    );
  }
}
