import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/audio_deletion.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

typedef DeleteAudio = Future<AudioDeletionOutcome> Function(Audio audio);

class DeleteAudioMenuItem extends StatelessWidget {
  const DeleteAudioMenuItem({
    super.key,
    required this.audio,
    this.hostContext,
    this.delete,
  });

  final Audio audio;
  final BuildContext? hostContext;
  final DeleteAudio? delete;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return MenuItemButton(
      key: ValueKey('delete-audio-${audio.path}'),
      onPressed: () async {
        // Menu entries live in a transient overlay and unmount as soon as the
        // menu closes. AudioTile supplies its stable page context so the
        // confirmation can safely outlive that overlay.
        final presentationContext = hostContext ?? context;
        await showDeleteAudioConfirmation(
          presentationContext,
          audio,
          delete: delete,
        );
      },
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(error),
      ),
      // delete_forever is intentionally distinct from the outlined bin used
      // by “从当前歌单移除”, which only removes a relationship.
      leadingIcon: Icon(Symbols.delete_forever, color: error),
      child: Text(
        ui('删除歌曲…'),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

Future<bool> showDeleteAudioConfirmation(
  BuildContext context,
  Audio audio, {
  DeleteAudio? delete,
}) async {
  final confirmed = await showAppDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: AppDialogTitle(ui('永久删除歌曲？')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ui(
                '将从磁盘永久删除“{0}”，并从总乐库、播放队列及所有歌单中移除。此操作不可撤销。',
                [audio.displayTitle],
              )),
              const SizedBox(height: 12),
              Text(
                ui('文件位置'),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                audio.path,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel-delete-audio'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(ui('取消')),
          ),
          FilledButton.icon(
            key: const ValueKey('confirm-delete-audio'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            icon: const Icon(Symbols.delete_forever),
            label: Text(ui('删除文件')),
          ),
        ],
      );
    },
  );
  if (confirmed != true || !context.mounted) return false;

  try {
    final outcome =
        await (delete ?? AudioDeletionService.instance.delete)(audio);
    if (outcome.playlistReferencesRemoved > 0) {
      // Persistence already happened in the shared deletion service. This is
      // one UI invalidation only, not a second save or derived-data rebuild.
      playlistUiRevision.value++;
    }
    // Removing the song rebuilds its parent list and normally disposes this
    // AudioTile before the persistence work finishes. Fall back to the global
    // presentation host so successful deletion still gives visible feedback.
    final message =
        outcome.fullyPersisted ? '已删除歌曲“{0}”' : '歌曲文件已删除，但部分列表状态尚未保存；刷新后可重试同步。';
    final arguments = outcome.fullyPersisted ? [audio.displayTitle] : const [];
    if (context.mounted) {
      showTextOnSnackBar(message, arguments: arguments, context: context);
    } else {
      showTextOnSnackBar(message, arguments: arguments);
    }
    return true;
  } on AudioDeletionException catch (error) {
    if (context.mounted) {
      showTextOnSnackBar(error.message, context: context);
    } else {
      showTextOnSnackBar(error.message);
    }
  } catch (error) {
    if (context.mounted) {
      showTextOnSnackBar('删除歌曲失败：{0}', arguments: [error], context: context);
    } else {
      showTextOnSnackBar('删除歌曲失败：{0}', arguments: [error]);
    }
  }
  return false;
}
