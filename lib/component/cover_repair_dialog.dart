import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/cover_repair.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

Future<void> showCoverRepairDialog(BuildContext context, List<Audio> audios,
    {MusicCategoryGroup? album, CategoryCoverStore? covers}) async {
  final store = covers ?? CategoryCoverStore.shared;
  await store.load();
  if (!context.mounted) return;
  final repair = CoverRepair(audios, album: album, covers: store);
  try {
    await showAppDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CoverRepairDialog(repair: repair));
  } finally {
    repair.dispose();
  }
}

String coverRepairStatusLabel(CoverRepairStatus status) => switch (status) {
      CoverRepairStatus.ready => '待处理',
      CoverRepairStatus.success => '封面已更新',
      CoverRepairStatus.noArtwork => '源文件没有封面',
      CoverRepairStatus.unreadable => '来源不可访问',
      CoverRepairStatus.failed => '读取失败',
      CoverRepairStatus.cancelled => '未开始，已取消',
    };

class CoverRepairDialog extends StatelessWidget {
  const CoverRepairDialog({super.key, required this.repair});
  final CoverRepair repair;
  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
        listenable: repair,
        builder: (context, _) => PopScope(
              canPop: !repair.busy,
              child: Dialog(
                  child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: 700,
                          maxHeight: MediaQuery.sizeOf(context).height * .85),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          AppDialogTitle(ui('重新读取封面'),
                              leading: MediaQuery.sizeOf(context).width < 520
                                  ? null
                                  : const Icon(Symbols.image_search),
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          Text(
                              ui('仅处理以下 {0} 个来源，保留自定义封面和音乐文件。',
                                  [repair.targets.length]),
                              textAlign: TextAlign.center),
                          if (repair.busy)
                            const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: LinearProgressIndicator()),
                          const SizedBox(height: 12),
                          Flexible(
                              child: ListView(shrinkWrap: true, children: [
                            if (repair.started)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(CoverRepairStatus.values
                                      .where(
                                          (status) => repair.count(status) > 0)
                                      .map((status) =>
                                          '${ui(coverRepairStatusLabel(status))} ${repair.count(status)}')
                                      .join(' · '))),
                            for (final target in repair.targets)
                              Card(
                                  elevation: 0,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerLow,
                                  child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(target.title,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall),
                                            const SizedBox(height: 4),
                                            SelectableText(
                                                target.group == null
                                                    ? target.source
                                                    : ui(target.source),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall),
                                            const SizedBox(height: 8),
                                            Text(
                                                ui(coverRepairStatusLabel(
                                                    target.status)),
                                                style: TextStyle(
                                                    color: target.retryable
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .error
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .primary)),
                                            if (target.reason.isNotEmpty)
                                              Text(target.reason,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall),
                                          ]))),
                          ])),
                          const SizedBox(height: 12),
                          AppDialogActions(children: [
                            TextButton(
                                onPressed: repair.busy
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                child: Text(ui('关闭'))),
                            if (repair.busy)
                              OutlinedButton(
                                  onPressed: repair.cancellationRequested
                                      ? null
                                      : repair.cancel,
                                  child: Text(ui(repair.cancellationRequested
                                      ? '正在停止…'
                                      : '停止后续处理'))),
                            if (!repair.started)
                              FilledButton(
                                  onPressed:
                                      repair.busy ? null : () => repair.run(),
                                  child: Text(ui('开始读取'))),
                            if (repair.targets
                                .any((target) => target.retryable))
                              OutlinedButton(
                                  onPressed: repair.busy
                                      ? null
                                      : () => repair.run(retryOnly: true),
                                  child: Text(ui('仅重试失败项'))),
                          ]),
                        ]),
                      ))),
            ));
  }
}
