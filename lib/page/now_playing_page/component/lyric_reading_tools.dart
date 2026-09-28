import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_checkbox_menu_button.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'lyric_view_controls.dart';

Widget _readingMenuLabel(BuildContext context, String label) => ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width - 112).clamp(120, 320)),
      child: Text(ui(label), softWrap: true),
    );

String lyricReadingTimestamp(Duration time) {
  final milliseconds = time.inMilliseconds.clamp(0, 999999999);
  final minutes = milliseconds ~/ 60000;
  final seconds = (milliseconds ~/ 1000) % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.'
      '${(milliseconds % 1000).toString().padLeft(3, '0')}';
}

/// Display/copy projection only; never edits the lyric or its word timeline.
String lyricReadingText(LyricLine line,
    {bool translation = true,
    bool romanization = true,
    bool timestamp = false}) {
  final primary = switch (line) {
    SyncLyricLine() => line.content,
    UnsyncLyricLine() => line.content.split('┃').first,
    _ => '',
  };
  final translations = switch (line) {
    SyncLyricLine() => [if (line.translation != null) line.translation!],
    UnsyncLyricLine() => line.content.split('┃').skip(1).toList(),
    _ => <String>[],
  };
  final rows = [
    if (romanization && (line.romanization?.trim().isNotEmpty ?? false))
      line.romanization!,
    if (primary.trim().isNotEmpty)
      '${timestamp ? '[${lyricReadingTimestamp(line.start)}] ' : ''}$primary',
    if (translation) ...translations.where((text) => text.trim().isNotEmpty),
  ];
  return rows.join('\n');
}

Future<void> copyLyricReadingText(BuildContext context, String text) async {
  if (text.trim().isEmpty) {
    showAppNotice(ui('没有可复制的歌词'), context: context);
    return;
  }
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showAppNotice(ui('已复制歌词'), context: context);
  } catch (error) {
    if (context.mounted) {
      showAppNotice(ui('复制歌词失败：{0}', [error]),
          context: context, kind: AppNoticeKind.error);
    }
  }
}

class LyricReadingMenu extends StatelessWidget {
  const LyricReadingMenu(
      {super.key, required this.controller, required this.readLyric});
  final LyricViewController controller;
  final Future<Lyric?>? Function() readLyric;

  Future<void> _copyAll(BuildContext context) async {
    final future = readLyric();
    if (future == null) return;
    try {
      final lyric = await future;
      if (!context.mounted || !identical(future, readLyric())) return;
      await copyLyricReadingText(
          context,
          lyric == null
              ? ''
              : lyric.lines
                  .map((line) => lyricReadingText(line,
                      translation: controller.showTranslation,
                      romanization: controller.showRomanization,
                      timestamp:
                          controller.showTimestamps && lyric is! PlainLyric))
                  .where((text) => text.isNotEmpty)
                  .join('\n'));
    } catch (error) {
      if (context.mounted && identical(future, readLyric())) {
        showAppNotice(ui('复制歌词失败：{0}', [error]),
            context: context, kind: AppNoticeKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
        listenable: controller,
        builder: (context, _) => AppMenuAnchor(
              menuChildren: [
                AppCheckboxMenuButton(
                    value: controller.showTranslation,
                    onChanged: (value) =>
                        controller.setShowTranslation(value ?? true),
                    child: _readingMenuLabel(context, '显示歌词译文')),
                AppCheckboxMenuButton(
                    value: controller.showRomanization,
                    onChanged: (value) =>
                        controller.setShowRomanization(value ?? true),
                    child: _readingMenuLabel(context, '显示歌词注音')),
                AppCheckboxMenuButton(
                    value: controller.showTimestamps,
                    onChanged: (value) =>
                        controller.setShowTimestamps(value ?? false),
                    child: _readingMenuLabel(context, '显示歌词时间')),
                const Divider(),
                AppCheckboxMenuButton(
                    value: controller.readingMode,
                    onChanged: (value) =>
                        controller.setReadingMode(value ?? false),
                    child: _readingMenuLabel(context, '手动阅读歌词')),
                MenuItemButton(
                    onPressed: controller.returnToCurrent,
                    leadingIcon: const Icon(Symbols.my_location),
                    child: _readingMenuLabel(context, '回到当前歌词')),
                MenuItemButton(
                    onPressed: controller.resetFontSize,
                    leadingIcon: const Icon(Symbols.text_fields),
                    child: _readingMenuLabel(context, '恢复歌词字号')),
                MenuItemButton(
                    onPressed:
                        readLyric() == null ? null : () => _copyAll(context),
                    leadingIcon: const Icon(Symbols.copy_all),
                    child: _readingMenuLabel(context, '复制完整显示歌词')),
              ],
              builder: (context, menu, _) => IconButton(
                key: const ValueKey('lyric-reading-tools'),
                tooltip: ui('歌词阅读工具'),
                color: Theme.of(context).colorScheme.primary,
                onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                icon: const Icon(Symbols.chrome_reader_mode),
              ),
            ));
  }
}

/// Secondary click and touch long press expose copying without changing the
/// existing primary click that seeks to a timestamped line.
class LyricLineReadingActions extends StatelessWidget {
  const LyricLineReadingActions(
      {super.key,
      required this.line,
      required this.controller,
      required this.timed,
      required this.child});
  final LyricLine line;
  final LyricViewController controller;
  final bool timed;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppMenuAnchor(
        menuChildren: [
          MenuItemButton(
              onPressed: () => copyLyricReadingText(
                  context,
                  lyricReadingText(line,
                      translation: controller.showTranslation,
                      romanization: controller.showRomanization)),
              leadingIcon: const Icon(Symbols.content_copy),
              child: _readingMenuLabel(context, '复制这一句歌词')),
          if (timed)
            MenuItemButton(
                onPressed: () => copyLyricReadingText(
                    context,
                    lyricReadingText(line,
                        translation: controller.showTranslation,
                        romanization: controller.showRomanization,
                        timestamp: true)),
                leadingIcon: const Icon(Symbols.schedule),
                child: _readingMenuLabel(context, '复制歌词与时间')),
        ],
        builder: (context, menu, _) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f10, shift: true): () =>
                menu.open(),
            const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
                copyLyricReadingText(
                    context,
                    lyricReadingText(line,
                        translation: controller.showTranslation,
                        romanization: controller.showRomanization)),
          },
          child: GestureDetector(
            onSecondaryTapUp: (event) =>
                menu.open(position: event.localPosition),
            onLongPressStart: (event) =>
                menu.open(position: event.localPosition),
            child: timed ? child : Focus(child: child),
          ),
        ),
      );
}
