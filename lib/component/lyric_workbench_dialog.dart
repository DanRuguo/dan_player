import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/lyric_editor_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_source_view.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

Future<void> showLyricWorkbenchDialog(BuildContext context, Audio audio) =>
    showAppDialog<void>(
        context: context, builder: (_) => LyricWorkbenchDialog(audio: audio));

class LyricWorkbenchDialog extends StatefulWidget {
  const LyricWorkbenchDialog(
      {super.key, required this.audio, this.store, this.currentLyric});
  final Audio audio;
  final LyricDocumentStore? store;
  final Lyric? Function()? currentLyric;

  @override
  State<LyricWorkbenchDialog> createState() => _LyricWorkbenchDialogState();
}

class _LyricWorkbenchDialogState extends State<LyricWorkbenchDialog> {
  late final store = widget.store ?? LyricDocumentStore.instance;
  final offset = TextEditingController();
  final scrollController = ScrollController();
  bool busy = true;
  String? error;
  LyricDocument? document;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await store.load();
      if (!mounted) return;
      document = store.forAudio(widget.audio);
      offset.text = (document?.offsetMs ?? 0).toString();
    } catch (failure) {
      if (!mounted) return;
      error = failure.toString();
    }
    if (mounted) setState(() => busy = false);
  }

  Lyric? _current() {
    if (widget.currentLyric != null) return widget.currentLyric!();
    final player = PlayService.instance;
    return player.playbackService.nowPlaying?.stableTrackId ==
            widget.audio.stableTrackId
        ? player.lyricService.rawCurrentLyric
        : null;
  }

  Future<void> _change(Future<void> Function(int revision) work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work(document?.revision ?? 0);
      if (!mounted) return;
      document = store.forAudio(widget.audio);
      offset.text = (document?.offsetMs ?? 0).toString();
    } catch (failure) {
      if (!mounted) return;
      error = failure.toString();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _saveOffset([int? value]) async {
    final milliseconds = value ?? int.tryParse(offset.text.trim());
    if (milliseconds == null ||
        milliseconds.abs() > LyricDocument.maxOffsetMs) {
      setState(() => error = ui('请输入 -600000 至 600000 的整数毫秒值。'));
      return;
    }
    await _change((revision) async {
      await store.setOffset(widget.audio, milliseconds,
          expectedRevision: revision);
    });
  }

  @override
  void dispose() {
    offset.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 480;
    return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: 600, maxHeight: MediaQuery.sizeOf(context).height - 48),
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heading(context),
                const SizedBox(height: 20),
                Flexible(
                    child: _scrollableBody(context,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                '${widget.audio.displayTitle} · ${widget.audio.artist}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            Text(ui(document?.stateLabel ?? '自动匹配'),
                                key: const ValueKey('lyric-document-status'),
                                style: TextStyle(color: scheme.primary)),
                            if (document?.source != null) ...[
                              const SizedBox(height: 4),
                              Text(ui('来源：{0}', [ui(document!.sourceLabel!)]),
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant)),
                            ],
                            if (busy) ...[
                              const SizedBox(height: 12),
                              const LinearProgressIndicator(),
                            ],
                            if (error != null)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(error!,
                                      key: const ValueKey(
                                          'lyric-document-error'),
                                      style: TextStyle(color: scheme.error))),
                            const SizedBox(height: 20),
                            _section(context, ui('时间校准'), [
                              Text(ui('正值延后歌词，负值提前歌词。'),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurfaceVariant)),
                              const SizedBox(height: 16),
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    IconButton.outlined(
                                        key: const ValueKey(
                                            'lyric-offset-earlier'),
                                        tooltip: ui('提前 500 ms'),
                                        style: IconButton.styleFrom(
                                            minimumSize: const Size(44, 44),
                                            visualDensity:
                                                VisualDensity.standard),
                                        onPressed: busy
                                            ? null
                                            : () => _saveOffset(
                                                (document?.offsetMs ?? 0) -
                                                    500),
                                        icon: const Icon(Symbols.remove)),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: TextField(
                                            key: const ValueKey(
                                                'lyric-offset-value'),
                                            controller: offset,
                                            enabled: !busy,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                                signed: true),
                                            decoration: const InputDecoration(
                                                border: AppShape.inputBorder,
                                                suffixText: 'ms',
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        horizontal: 16,
                                                        vertical: 16)),
                                            textAlign: TextAlign.center,
                                            onSubmitted: (_) => _saveOffset())),
                                    const SizedBox(width: 12),
                                    IconButton.outlined(
                                        key: const ValueKey(
                                            'lyric-offset-later'),
                                        tooltip: ui('延后 500 ms'),
                                        style: IconButton.styleFrom(
                                            minimumSize: const Size(44, 44),
                                            visualDensity:
                                                VisualDensity.standard),
                                        onPressed: busy
                                            ? null
                                            : () => _saveOffset(
                                                (document?.offsetMs ?? 0) +
                                                    500),
                                        icon: const Icon(Symbols.add)),
                                  ]),
                              const SizedBox(height: 8),
                              Text(ui('+500 ms 表示歌词晚显示 500 ms'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant)),
                              const SizedBox(height: 16),
                              _actionGrid(context, [
                                OutlinedButton(
                                    key: const ValueKey('lyric-offset-reset'),
                                    style: _actionStyle,
                                    onPressed:
                                        busy ? null : () => _saveOffset(0),
                                    child: Text(ui('重置偏移'))),
                                FilledButton.icon(
                                    key: const ValueKey('lyric-offset-save'),
                                    style: _actionStyle,
                                    onPressed:
                                        busy ? null : () => _saveOffset(),
                                    icon: const Icon(Symbols.check, size: 20),
                                    label: Text(ui('保存偏移'))),
                              ]),
                              const SizedBox(height: 12),
                              Text(ui('同步主窗口、迷你播放器与桌面歌词，不改写原文件。'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant)),
                            ]),
                            const SizedBox(height: 16),
                            _section(context, ui('匹配与保护'), [
                              SwitchListTile(
                                key: const ValueKey('lyric-document-lock'),
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                visualDensity: VisualDensity.standard,
                                title: Text(ui('确认并锁定当前歌词')),
                                subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(ui('保存当前版本；网络内容变化不会覆盖人工成果。'))),
                                value: document?.locked ?? false,
                                onChanged: busy || document?.noLyrics == true
                                    ? null
                                    : (value) => _change((revision) async {
                                          await store.setLocked(
                                              widget.audio, value,
                                              current: _current(),
                                              expectedRevision: revision);
                                        }),
                              ),
                              const Divider(height: 24),
                              SwitchListTile(
                                key: const ValueKey('lyric-document-no-lyrics'),
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                visualDensity: VisualDensity.standard,
                                title: Text(ui('无歌词，不再自动查找')),
                                subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(ui('适用于纯音乐；关闭后仍可恢复之前的歌词。'))),
                                value: document?.noLyrics ?? false,
                                onChanged: busy
                                    ? null
                                    : (value) => _change((revision) async {
                                          await store.setNoLyrics(
                                              widget.audio, value,
                                              expectedRevision: revision);
                                        }),
                              ),
                            ]),
                            const SizedBox(height: 16),
                            _section(context, ui('歌词内容与版本'), [
                              _actionGrid(context, [
                                if (!widget.audio.isOnline)
                                  OutlinedButton.icon(
                                      style: _actionStyle,
                                      onPressed: busy
                                          ? null
                                          : () async {
                                              await showLyricEditorDialog(
                                                  context, widget.audio);
                                              if (mounted) await _load();
                                            },
                                      icon: const Icon(Symbols.edit_document),
                                      label: Text(ui('编辑修订'))),
                                OutlinedButton.icon(
                                    style: _actionStyle,
                                    onPressed: busy
                                        ? null
                                        : () async {
                                            await showAppDialog<void>(
                                                context: context,
                                                builder: (_) =>
                                                    LyricSourceDialog(
                                                        audio: widget.audio));
                                            if (mounted) await _load();
                                          },
                                    icon: const Icon(Symbols.search),
                                    label: Text(ui('切换歌词来源'))),
                                if (document?.edited != null &&
                                    document?.original != null)
                                  OutlinedButton.icon(
                                      style: _actionStyle,
                                      onPressed: busy
                                          ? null
                                          : () => _change((revision) async {
                                                await store.restoreOriginal(
                                                    widget.audio,
                                                    expectedRevision: revision);
                                              }),
                                      icon: const Icon(Symbols.restore),
                                      label: Text(ui('恢复原始歌词'))),
                                if (document?.history.isNotEmpty == true)
                                  PopupMenuButton<int>(
                                      enabled: !busy,
                                      tooltip: ui('恢复之前的版本'),
                                      onSelected: (index) =>
                                          _change((revision) async {
                                            await store.restoreVersion(
                                                widget.audio, index,
                                                expectedRevision: revision);
                                          }),
                                      itemBuilder: (_) => [
                                            for (var i =
                                                    document!.history.length -
                                                        1;
                                                i >= 0;
                                                i--)
                                              PopupMenuItem(
                                                  value: i,
                                                  child:
                                                      Text(ui('版本 {0} · {1}', [
                                                    document!.history[i]
                                                        ['revision'],
                                                    ui(document!.history[i]
                                                                ['edited'] !=
                                                            null
                                                        ? '人工修订'
                                                        : '原始副本')
                                                  ]))),
                                          ],
                                      child: Container(
                                          constraints: const BoxConstraints(
                                              minHeight: 44),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 12),
                                          decoration: BoxDecoration(
                                              border: Border.all(
                                                  color: scheme.outline),
                                              borderRadius:
                                                  AppShape.controlRadius),
                                          child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(Symbols.history,
                                                    size: 20,
                                                    color: scheme.primary),
                                                const SizedBox(width: 8),
                                                Flexible(
                                                    child: Text(ui('恢复之前的版本'),
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                            color: scheme
                                                                .primary))),
                                              ]))),
                              ]),
                            ]),
                          ],
                        ))),
              ],
            ),
          ),
        ));
  }

  static final _actionStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      visualDensity: VisualDensity.standard,
      shape: AppShape.control);

  Widget _heading(BuildContext context) {
    final theme = Theme.of(context);
    final title = ui('歌词校准与锁定');
    final style =
        theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600);
    final leading = Icon(Symbols.tune, color: theme.colorScheme.primary);
    final close = IconButton(
        tooltip: ui('关闭'),
        onPressed: busy ? null : () => Navigator.pop(context),
        icon: const Icon(Symbols.close));
    return LayoutBuilder(builder: (context, constraints) {
      final measure = TextPainter(
          text: TextSpan(text: title, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1)
        ..layout();
      final needsFullWidth = measure.width > constraints.maxWidth - 96;
      measure.dispose();
      if (needsFullWidth) {
        // Give large text the entire row instead of orphaning the last
        // character between the two action slots. Respect the user's scale.
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            SizedBox.square(dimension: 48, child: Center(child: leading)),
            close,
          ]),
          const SizedBox(height: 4),
          Text(title, textAlign: TextAlign.center, style: style),
        ]);
      }
      return AppDialogTitle(title,
          style: style, leading: leading, trailing: close);
    });
  }

  Widget _scrollableBody(BuildContext context, {required Widget child}) =>
      ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                  key: const ValueKey('lyric-workbench-scroll'),
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: child)));

  Widget _section(BuildContext context, String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Material(
        color: theme.colorScheme.surfaceContainerLow,
        shape: AppShape.surface.copyWith(
            side: BorderSide(color: theme.colorScheme.outlineVariant)),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  ...children,
                ])));
  }

  Widget _actionGrid(BuildContext context, List<Widget> children) =>
      LayoutBuilder(builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 400 &&
            MediaQuery.textScalerOf(context).scale(14) <= 20;
        final width =
            twoColumns ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final child in children) SizedBox(width: width, child: child),
        ]);
      });
}
