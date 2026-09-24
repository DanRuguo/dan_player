import 'dart:async';
import 'dart:io';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_scrollbar.dart';
import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_content_transition.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/ffmpeg_setup_card.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/library/ffmpeg_runtime.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:dan_player/lyric/lyric_preview.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/tap_lyric_session.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';

Future<bool?> chooseLyricEditingMethod(BuildContext context) =>
    showAppDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: AppDialogTitle(ui('你想如何编辑歌词😋？')),
                content: SizedBox(
                    width: 540,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final quick in [true, false])
                        Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLow,
                                shape: AppShape.control,
                                clipBehavior: Clip.antiAlias,
                                child: ListTile(
                                    key: ValueKey(quick
                                        ? 'lyric-method-tap'
                                        : 'lyric-method-text'),
                                    leading: Icon(
                                        quick
                                            ? Symbols.keyboard
                                            : Symbols.edit_note,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary),
                                    title: Text(ui(quick ? '快捷点按' : '传统码字')),
                                    subtitle: Text(ui(quick
                                        ? '听歌点按，逐步制作逐句和逐字歌词。'
                                        : '选择格式，直接编辑歌词代码。')),
                                    trailing: const Icon(Symbols.chevron_right),
                                    onTap: () =>
                                        Navigator.pop(context, quick))))
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(ui('取消')))
                ]));

class TapLyricEditor extends StatefulWidget {
  const TapLyricEditor(
      {super.key,
      required this.audio,
      required this.fetchOnline,
      required this.saveLyric,
      this.preview,
      this.progressStore,
      this.initialSession,
      this.ensureTools});
  final Audio audio;
  final Future<Lyric?> Function() fetchOnline;
  final Future<bool> Function(Lyric lyric) saveLyric;
  final LyricAudioPreview? preview;
  final TapProgressStore? progressStore;
  final TapLyricSession? initialSession;
  final Future<bool> Function()? ensureTools;
  @override
  State<TapLyricEditor> createState() => _TapLyricEditorState();
}

class _TapLyricEditorState extends State<TapLyricEditor> {
  late TapLyricSession session = widget.initialSession ?? TapLyricSession();
  late final text = TextEditingController(text: session.text);
  final keyboard = FocusNode();
  final contentScroll = ScrollController();
  late final player = widget.preview ??
      LyricAudioPreview(widget.audio,
          launch: (file, start, duration, clock) => launchLyricPreview(
              file, start, duration, clock,
              rate: session.rate));
  StreamSubscription<double>? subscription;
  bool busy = false, closing = false, ready = false, checked = false;
  String? error;
  Lyric? reviewLyric;
  bool get review =>
      [TapStage.lineReview, TapStage.wordReview].contains(session.stage);
  bool get timing =>
      [TapStage.lines, TapStage.words].contains(session.stage) || review;
  @override
  void initState() {
    super.initState();
    player.addListener(_changed);
    subscription = player.positionStream.listen((p) {
      session.position = p;
      if (mounted) setState(() {});
    });
    if (timing) unawaited(_run(_prepare));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() work) async {
    if (busy || closing) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) {
        setState(() =>
            error = e is FormatException ? ui(e.message) : ui('操作失败，请重试。'));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (timing) keyboard.requestFocus();
      }
    }
  }

  Future<TapProgressStore> _store() async =>
      widget.progressStore ??
      TapProgressStore(
          Directory('${(await getAppDataDir()).path}/lyric_tap_progress'),
          widget.audio.stableTrackId);
  void _syncText() {
    if (session.stage == TapStage.text) session.text = text.text;
  }

  Future<void> _saveProgress() async {
    await player.pause();
    _syncText();
    if (widget.progressStore == null) {
      await TrackIdentityRegistry.instance.flush();
    }
    await (await _store()).save(session);
    showAppNotice(ui('点按进度已保存，可下次继续。'), kind: AppNoticeKind.success);
  }

  Future<bool> _replace() async {
    if (text.text.trim().isEmpty) return true;
    return await showAppDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
                    title: AppDialogTitle(ui('替换编辑中的内容？')),
                    content: Text(ui('尚未保存的内容将丢失。')),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: Text(ui('取消'))),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: Text(ui('替换')))
                    ])) ==
        true;
  }

  Future<void> _loadProgress() async {
    final restored = await (await _store()).load();
    if (!mounted) return;
    if (restored == null) {
      error = ui('没有已保存的点按进度。');
      return;
    }
    if (!await _replace() || !mounted) return;
    session = restored;
    reviewLyric = null;
    text.text = session.text;
    if (timing) await _prepare();
  }

  Future<void> _prepare() async {
    ready = await (widget.ensureTools ?? () => FfmpegRuntime.shared.ensure())();
    checked = true;
    if (ready && widget.preview == null) await player.prepare();
    if (ready &&
        (player.duration <= 0 ||
            session.mediaDuration > 0 &&
                (session.mediaDuration - player.duration).abs() > .1 ||
            session.position > player.duration + .1 ||
            session.rows.any((r) => (r.end ?? 0) > player.duration + .1))) {
      ready = false;
      throw const FormatException('歌曲时长与进度不符，请重新编辑。');
    }
    if (ready) session.mediaDuration = player.duration;
    if (mounted) keyboard.requestFocus();
  }

  Future<void> _online() async {
    final lyric = await widget.fetchOnline();
    if (lyric == null || !mounted || !await _replace() || !mounted) return;
    final result = tapTextFromLyric(lyric);
    session.spaces = result.spaces;
    text.text = result.text;
    _syncText();
  }

  Future<void> _beginLines() async {
    _syncText();
    session.beginLines();
    await _prepare();
  }

  Future<void> _toggle() async {
    if (!timing || !ready) return;
    if (player.playing || player.loading) {
      await player.pause();
      return;
    }
    var start = session.position;
    double end;
    if (review) {
      reviewLyric = null;
      final range = session.reviewRange(player.duration);
      end = range.end;
      if (start < range.start || start >= end) start = range.start;
    } else if (session.stage == TapStage.words) {
      end = session.row.end!;
      if (start >= end) {
        error = ui('音乐已到句尾，请重录本句；未完成的字不会自动确认。');
        return;
      }
      session.wordStarted = true;
    } else {
      end = player.duration;
      if (start >= end) {
        error = ui('歌曲已结束，但歌词尚未完成。请检查歌词文本与歌曲版本是否一致，或本句打点是否有误。');
        return;
      }
    }
    await player.play(start, end);
  }

  Future<void> _mark() async {
    if (!player.playing || !player.clockReady || review || !timing) return;
    if (!session.mark(player.position)) return;
    if (review) {
      reviewLyric = null;
      await player.pause();
      final range = session.reviewRange(player.duration);
      session.position = range.start;
      if (session.stage == TapStage.lineReview) {
        await player.play(range.start, range.end);
      }
    }
  }

  Future<void> _retry() async {
    await player.pause();
    reviewLyric = null;
    session.retry();
    keyboard.requestFocus();
  }

  Future<void> _accept() async {
    await player.pause();
    reviewLyric = null;
    session.accept();
    keyboard.requestFocus();
  }

  Future<void> _rate(double rate) async {
    final wasPlaying = player.playing;
    await player.pause();
    session.rate = rate;
    if (wasPlaying) await _toggle();
  }

  Future<void> _editText() async {
    await player.pause();
    if (!mounted) return;
    final confirmed = await showAppDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: AppDialogTitle(ui('返回修改文本')),
                content: Text(ui('返回修改会清除本次打点，但保留纯文本。建议先保存当前进度。')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text(ui('取消'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(ui('返回修改文本')))
                ]));
    if (confirmed != true || !mounted) return;
    session = TapLyricSession()
      ..text = session.text
      ..spaces = session.spaces;
    reviewLyric = null;
    text.text = session.text;
  }

  Future<void> _saveLyric() async {
    await player.pause();
    _syncText();
    final lyric = session.stage == TapStage.text
        ? PlainLyric(parseTapText(session.text, session.spaces).isNotEmpty
            ? session.text
            : '')
        : session.lyric(words: session.stage == TapStage.done);
    final saved = await widget.saveLyric(lyric);
    if (saved && mounted) {
      closing = true;
      await player.close();
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _exit() async {
    if (busy || closing) return;
    await player.pause();
    if (!mounted) return;
    final action = await showAppDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: AppDialogTitle(ui('退出快捷点按？')),
                content: Text(ui('不保存退出会丢失本次全部进度，包括纯文本歌词。上次手动保存的进度仍保留。')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: Text(ui('继续编辑'))),
                  TextButton(
                      onPressed: () => Navigator.pop(c, 'discard'),
                      child: Text(ui('不保存退出'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, 'save'),
                      child: Text(ui('保存进度并退出')))
                ]));
    if (action == null || !mounted) return;
    await _run(() async {
      if (action == 'save') await _saveProgress();
      closing = true;
      await player.close();
      if (mounted) Navigator.pop(context, false);
    });
  }

  @override
  void dispose() {
    player.removeListener(_changed);
    unawaited(subscription?.cancel());
    player.dispose();
    text.dispose();
    contentScroll.dispose();
    keyboard.dispose();
    super.dispose();
  }

  Widget _button(String label, IconData icon, Future<void> Function() callback,
      {bool filled = false, String? key}) {
    final onPressed = busy || closing ? null : () => _run(callback);
    return filled
        ? FilledButton.icon(
            key: key == null ? null : ValueKey(key),
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(ui(label)))
        : OutlinedButton.icon(
            key: key == null ? null : ValueKey(key),
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(ui(label)));
  }

  Widget _textStage() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(ui('每行：歌词正文|翻译|注音；缺翻译时用正文||注音。')),
        const SizedBox(height: 8),
        Text(ui('正文含有分隔符时，增加两侧空格数；输入的分隔符必须与下方示例一致。')),
        const SizedBox(height: 8),
        Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(ui('分隔符空格数')),
              IconButton(
                  tooltip: ui('减少'),
                  onPressed: busy || session.spaces == 0
                      ? null
                      : () => setState(() => session.spaces--),
                  icon: const Icon(Symbols.remove)),
              Text('${session.spaces}'),
              IconButton(
                  tooltip: ui('增加'),
                  onPressed: busy || session.spaces >= 32
                      ? null
                      : () => setState(() => session.spaces++),
                  icon: const Icon(Symbols.add)),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: AppShape.controlRadius),
                  child: Text(
                      'A${tapDelimiter(session.spaces)}B${tapDelimiter(session.spaces)}C',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer))),
            ]),
        const SizedBox(height: 8),
        TextField(
            key: const ValueKey('tap-text'),
            controller: text,
            minLines: 6,
            maxLines: 10,
            enabled: !busy,
            decoration: InputDecoration(
                border: const OutlineInputBorder(), labelText: ui('纯文本歌词'))),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _button('联网填入纯文本', Symbols.cloud_download, _online),
          _button('加载上次进度', Symbols.history, _loadProgress),
        ]),
        const SizedBox(height: 12),
      ]);
  Widget _textActions() => Wrap(spacing: 8, runSpacing: 8, children: [
        _button('保存纯文本歌词', Symbols.save, _saveLyric),
        _button('继续编写逐句歌词', Symbols.arrow_forward, _beginLines,
            filled: true, key: 'tap-begin-lines')
      ]);

  Widget _currentRow() {
    final row = session.row, scheme = Theme.of(context).colorScheme;
    final words =
        session.stage == TapStage.words || session.stage == TapStage.wordReview;
    final tokens = row.tokens;
    return Container(
        width: double.infinity,
        padding: EdgeInsets.all(review ? 12 : 20),
        decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: AppShape.controlRadius),
        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (!review)
            Text(ui('第 {0} / {1} 行',
                ['${session.index + 1}', '${session.rows.length}'])),
          if (!review) const SizedBox(height: 20),
          if (review)
            SizedBox(
                height: MediaQuery.sizeOf(context).height < 700 ? 140 : 260,
                child: ChangeNotifierProvider(
                    key: ValueKey(
                        'review-${session.index}-${session.stage.name}'),
                    create: (_) => LyricViewController(),
                    child: VerticalLyricScrollView(
                        onSeek: (_) {},
                        lyric: reviewLyric ??=
                            session.lyric(words: words, onlyCurrent: true),
                        positionStream: player.positionStream,
                        readPosition: () => session.position,
                        playing: player.playing,
                        springLyrics: AppSettings
                            .instance.experience.value.springLyrics)))
          else if (words)
            Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < tokens.length; i++)
                    InkWell(
                        key: ValueKey('tap-word-$i'),
                        borderRadius: AppShape.controlRadius,
                        onTap: !busy &&
                                !review &&
                                player.playing &&
                                player.clockReady &&
                                session.wordStarted &&
                                i == row.wordEnds.length
                            ? () => _run(_mark)
                            : null,
                        child: AnimatedContainer(
                            duration:
                                (!AppMotion.enabled(context, MotionKind.feedback) ||
                                        WidgetsBinding
                                            .instance
                                            .platformDispatcher
                                            .accessibilityFeatures
                                            .reduceMotion)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 120),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 8),
                            decoration: BoxDecoration(
                                borderRadius: AppShape.controlRadius,
                                color: !review &&
                                        session.wordStarted &&
                                        i == row.wordEnds.length
                                    ? scheme.primary
                                    : i < row.wordEnds.length
                                        ? scheme.primary.withValues(alpha: .14)
                                        : Colors.transparent),
                            child: Text(tokens[i],
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                        color: !review && session.wordStarted && i == row.wordEnds.length ? scheme.onPrimary : scheme.onSurface))))
                ])
          else
            Text(row.text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall),
          if (!review && row.translation.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(row.translation, textAlign: TextAlign.center)),
          if (!review && row.romanization.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(row.romanization,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall)),
          if (!review) const SizedBox(height: 20),
        ]));
  }

  Widget _timingStage() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(ui(review
            ? '试听检查：满意后继续；不满意只重录当前行。'
            : session.stage == TapStage.words
                ? '空格播放或暂停；Enter 或点按强调的字，记录该字结束。'
                : '空格播放或暂停；Enter 标记本句开始，再按一次标记结束。')),
        const SizedBox(height: 12),
        if (checked && !ready)
          FfmpegSetupCard(lyricPreview: true, onReady: () => _run(_prepare))
        else ...[
          _currentRow(),
          if (!player.playing &&
              !review &&
              session.stage == TapStage.words &&
              session.position >= session.row.end!)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(ui('音乐已到句尾，请重录本句；未完成的字不会自动确认。'))),
          if (!player.playing &&
              !review &&
              session.stage == TapStage.lines &&
              session.position >= player.duration)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(ui('歌曲已结束，但歌词尚未完成。请检查歌词文本与歌曲版本是否一致，或本句打点是否有误。'))),
        ]
      ]);
  Widget _transport() {
    final row = session.row, scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (session.stage == TapStage.lines)
        Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
                key: const ValueKey('tap-mark'),
                onPressed: busy || !player.playing || !player.clockReady
                    ? null
                    : () => _run(_mark),
                style: row.start == null
                    ? FilledButton.styleFrom(
                        backgroundColor: scheme.secondaryContainer,
                        foregroundColor: scheme.onSecondaryContainer)
                    : null,
                icon: Icon(row.start == null ? Symbols.flag : Symbols.stop),
                label: AnimatedSwitcher(
                    duration: AppMotion.duration(
                        context, MotionKind.feedback, AppMotion.quick),
                    child: Text(
                        ui(row.start == null ? '开始本句 · Enter' : '结束本句 · Enter'),
                        key: ValueKey(row.start == null))))),
      const SizedBox(height: 16),
      LinearProgressIndicator(
          value: player.duration > 0
              ? (session.position / player.duration).clamp(0, 1)
              : 0),
      const SizedBox(height: 8),
      Text(
          '${lyricStamp(Duration(milliseconds: (session.position * 1000).round()))} / ${lyricStamp(Duration(milliseconds: (player.duration * 1000).round()))}',
          textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _button(player.playing ? '暂停 · 空格' : '播放 · 空格',
                player.playing ? Symbols.pause : Symbols.play_arrow, _toggle,
                filled: true, key: 'tap-play'),
            AppMenuAnchor(
                menuChildren: [
                  for (final rate in [.25, .5, .75, 1.0])
                    MenuItemButton(
                        onPressed: busy ? null : () => _run(() => _rate(rate)),
                        leadingIcon: Icon(rate == session.rate
                            ? Symbols.check
                            : Symbols.speed),
                        child: Text('${rate}x'))
                ],
                builder: (context, controller, child) => OutlinedButton.icon(
                    key: const ValueKey('tap-rate'),
                    onPressed: busy
                        ? null
                        : () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                    icon: const Icon(Symbols.speed),
                    label: Text('${session.rate}x'))),
            _button(review ? '不满意，重录本句' : '重录本句', Symbols.replay, _retry),
            if (review)
              _button('满意，继续', Symbols.check, _accept,
                  filled: true, key: 'tap-accept'),
          ]),
    ]);
  }

  Widget _finishedStage() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Icon(Symbols.task_alt,
            color: Theme.of(context).colorScheme.primary, size: 48),
        const SizedBox(height: 16),
        Text(ui(session.stage == TapStage.done ? '逐字打点完成' : '逐句打点完成'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Text(ui(
            'LRC 兼容广但不能完整保留句尾和逐字时间；增强 LRC、QRC、KRC、YRC 支持逐字。播放器无损副本保留全部时间、翻译和注音。')),
        const SizedBox(height: 10),
        Text(ui('QRC 为文本，KRC 为压缩格式，YRC 常见于网易。其他播放器对翻译与注音的支持不同，导出会保留辅助文件。')),
        const SizedBox(height: 10),
        Text(ui('暂不支持独立的对唱角色和重叠声部；可在正文注明演唱者。')),
        const SizedBox(height: 20),
      ]);
  Widget _finishActions() => Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _button('选择格式并保存歌词', Symbols.save, _saveLyric, filled: true),
            if (session.stage == TapStage.lineDone)
              _button('继续编写逐字歌词', Symbols.arrow_forward, () async {
                session.beginWords();
                keyboard.requestFocus();
              }, key: 'tap-begin-words')
          ]);

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: closing,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) unawaited(_exit());
      },
      child: Focus(
          focusNode: keyboard,
          autofocus: true,
          onKeyEvent: (_, event) {
            if (!timing || busy || closing) return KeyEventResult.ignored;
            if (event.logicalKey != LogicalKeyboardKey.space &&
                event.logicalKey != LogicalKeyboardKey.enter &&
                event.logicalKey != LogicalKeyboardKey.numpadEnter) {
              return KeyEventResult.ignored;
            }
            if (event is KeyDownEvent) {
              unawaited(_run(event.logicalKey == LogicalKeyboardKey.space
                  ? _toggle
                  : _mark));
            }
            return KeyEventResult.handled;
          },
          child: Dialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: AppDialogContent(
                  width: 900,
                  maxHeight: 820,
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppDialogTitle(ui('快捷点按'),
                                leading: const Icon(Symbols.keyboard),
                                trailing: IconButton(
                                    tooltip: ui('关闭'),
                                    onPressed: busy ? null : _exit,
                                    icon: const Icon(Symbols.close))),
                            const SizedBox(height: 8),
                            Text(widget.audio.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 12),
                            if (player.loading) const LinearProgressIndicator(),
                            Flexible(
                                child: AppScrollbar(
                                    controller: contentScroll,
                                    child: SingleChildScrollView(
                                        controller: contentScroll,
                                        child: AppContentTransition(
                                            identity: (
                                              session.stage,
                                              session.index
                                            ),
                                            child:
                                                session.stage == TapStage.text
                                                    ? _textStage()
                                                    : timing
                                                        ? _timingStage()
                                                        : _finishedStage())))),
                            const SizedBox(height: 8),
                            if (timing && ready) _transport(),
                            if (session.stage == TapStage.text) _textActions(),
                            if (!timing && session.stage != TapStage.text)
                              _finishActions(),
                            if (error != null || player.error != null)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(error ?? ui(player.error!),
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error))),
                            const SizedBox(height: 12),
                            Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (timing)
                                    IconButton(
                                        tooltip: ui('返回修改文本'),
                                        onPressed:
                                            busy ? null : () => _run(_editText),
                                        icon: const Icon(Symbols.edit_note)),
                                  TextButton(
                                      onPressed: busy ? null : _exit,
                                      child: Text(ui('退出'))),
                                  _button('保存当前进度', Symbols.save_clock,
                                      _saveProgress,
                                      key: 'tap-save-progress')
                                ]),
                          ]))))));
}
