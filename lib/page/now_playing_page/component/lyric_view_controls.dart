import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/lyric_share_dialog.dart';
import 'package:dan_player/lyric/lyric_share_projection.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_text_search.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/component/lyric_editor_dialog.dart';
import 'package:dan_player/component/lyric_workbench_dialog.dart';
import 'package:dan_player/component/player_number_dialog.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_source_view.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'lyric_reading_tools.dart';
import 'lyric_segment_practice_dialog.dart';
import 'lyric_find_dialog.dart';

enum LyricTextAlign {
  left,
  center,
  right;

  static LyricTextAlign? fromString(String lyricTextAlign) {
    for (var value in LyricTextAlign.values) {
      if (value.name == lyricTextAlign) return value;
    }
    return null;
  }
}

class LyricViewController extends ChangeNotifier {
  LyricViewController({NowPlayingPagePreference? preferences})
      : nowPlayingPagePref =
            preferences ?? AppPreference.instance.nowPlayingPagePref;
  final NowPlayingPagePreference nowPlayingPagePref;
  late LyricTextAlign lyricTextAlign = nowPlayingPagePref.lyricTextAlign;
  late double lyricFontSize = nowPlayingPagePref.lyricFontSize;
  late double translationFontSize = nowPlayingPagePref.translationFontSize;
  late double _translationSizeOffset = translationFontSize - lyricFontSize;
  bool directFontSize = false;
  bool fontSizeAdjusting = false;
  double? fontDragPreviewSize;
  double? get translationDragPreviewSize => fontDragPreviewSize == null
      ? null
      : (fontDragPreviewSize! + _translationSizeOffset).clamp(14.0, 64.0);
  late bool showTranslation = nowPlayingPagePref.showLyricTranslation;
  late bool showRomanization = nowPlayingPagePref.showLyricRomanization;
  late bool showTimestamps = nowPlayingPagePref.showLyricTimestamps;
  bool readingMode = false;
  int returnRequest = 0;
  int readingRequest = 0;
  LyricReadingTarget? readingTarget;
  bool _finding = false;
  bool _disposed = false;
  bool _fontCancellationPending = false;

  void revealForReading(LyricReadingTarget target) {
    if (_disposed || !target.belongsTo(target.lyric)) return;
    readingTarget = target;
    readingMode = true;
    readingRequest++;
    notifyListeners();
  }

  void discardReadingTarget() {
    if (_disposed || readingTarget == null) return;
    readingTarget = null;
    readingRequest++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    readingTarget = null;
    super.dispose();
  }

  void setShowTranslation(bool value) {
    if (showTranslation == value) return;
    nowPlayingPagePref.showLyricTranslation = showTranslation = value;
    notifyListeners();
  }

  void setShowRomanization(bool value) {
    if (showRomanization == value) return;
    nowPlayingPagePref.showLyricRomanization = showRomanization = value;
    notifyListeners();
  }

  void setShowTimestamps(bool value) {
    if (showTimestamps == value) return;
    nowPlayingPagePref.showLyricTimestamps = showTimestamps = value;
    notifyListeners();
  }

  void setReadingMode(bool value) {
    if (readingMode == value) return;
    readingMode = value;
    if (!value) {
      readingTarget = null;
      returnRequest++;
    }
    notifyListeners();
  }

  void returnToCurrent() {
    readingMode = false;
    readingTarget = null;
    returnRequest++;
    notifyListeners();
  }

  void resetFontSize() {
    directFontSize = true;
    _translationSizeOffset = -4;
    nowPlayingPagePref.lyricFontSize = lyricFontSize = 22;
    nowPlayingPagePref.translationFontSize = translationFontSize = 18;
    notifyListeners();
  }

  /// Apply the slider position directly, retaining the original/auxiliary
  /// size relationship even when the auxiliary size reaches its limit.
  void setFontSize(double value) => _applyFontSize(value);

  void setPresetFontSize(double value) => _applyFontSize(value);

  void _applyFontSize(double value) {
    if (!value.isFinite) return;
    final primary = value.clamp(14.0, 64.0);
    final auxiliary = (primary + _translationSizeOffset).clamp(14.0, 64.0);
    if (primary == lyricFontSize && auxiliary == translationFontSize) return;
    directFontSize = true;
    nowPlayingPagePref.lyricFontSize = lyricFontSize = primary;
    nowPlayingPagePref.translationFontSize = translationFontSize = auxiliary;
    notifyListeners();
  }

  void setFontSizeAdjusting(bool value) {
    if (fontSizeAdjusting == value) return;
    fontSizeAdjusting = value;
    notifyListeners();
  }

  /// Preview a thumb drag using the currently shaped glyphs. The actual
  /// paragraph size and saved preference change only on pointer release.
  void setFontDragPreview(double? value) {
    final next = value == null || value == lyricFontSize
        ? null
        : value.clamp(14.0, 64.0);
    if (fontDragPreviewSize == next) return;
    fontDragPreviewSize = next;
    notifyListeners();
  }

  /// A hidden or removed menu no longer owns its unfinished pointer preview.
  /// Dependencies and disposal can change during a build; clear the draft now
  /// and notify from the next microtask rather than dirtying that build.
  void cancelFontSizeAdjustment() {
    if (_disposed || (!fontSizeAdjusting && fontDragPreviewSize == null)) {
      return;
    }
    fontSizeAdjusting = false;
    fontDragPreviewSize = null;
    if (_fontCancellationPending) return;
    _fontCancellationPending = true;
    scheduleMicrotask(() {
      _fontCancellationPending = false;
      if (!_disposed) notifyListeners();
    });
  }

  /// 在左对齐、居中、右对齐之间循环切换
  void switchLyricTextAlign() {
    lyricTextAlign = switch (lyricTextAlign) {
      LyricTextAlign.left => LyricTextAlign.center,
      LyricTextAlign.center => LyricTextAlign.right,
      LyricTextAlign.right => LyricTextAlign.left,
    };

    nowPlayingPagePref.lyricTextAlign = lyricTextAlign;
    notifyListeners();
  }

  void increaseFontSize() {
    if (lyricFontSize >= 64 || translationFontSize >= 64) return;
    directFontSize = false;
    lyricFontSize += 1;
    translationFontSize += 1;

    nowPlayingPagePref.lyricFontSize = lyricFontSize;
    nowPlayingPagePref.translationFontSize = translationFontSize;
    notifyListeners();
  }

  void decreaseFontSize() {
    if (lyricFontSize <= 14 || translationFontSize <= 14) return;
    directFontSize = false;

    lyricFontSize -= 1;
    translationFontSize -= 1;

    nowPlayingPagePref.lyricFontSize = lyricFontSize;
    nowPlayingPagePref.translationFontSize = translationFontSize;
    notifyListeners();
  }
}

class LyricViewControls extends StatelessWidget {
  const LyricViewControls({super.key, this.hidden});

  final ValueListenable<bool>? hidden;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SetLyricSourceBtn(),
          const SizedBox(height: 8.0),
          const _LyricWorkbenchBtn(),
          const SizedBox(height: 8.0),
          const _LyricEditBtn(),
          const SizedBox(height: 8.0),
          const _LyricAlignSwitchBtn(),
          const SizedBox(height: 8.0),
          const _LyricReadingMenu(),
          const SizedBox(height: 8.0),
          LyricFontSizeMenu(hidden: hidden),
        ],
      )),
    );
  }
}

class _LyricReadingMenu extends StatelessWidget {
  const _LyricReadingMenu();

  Future<void> _practiceSegment(NavigatorState navigator) async {
    if (!navigator.mounted) return;
    final playback = PlayService.instance.playbackService;
    final lyricService = PlayService.instance.lyricService;
    final future = lyricService.currLyricFuture;
    final audio = playback.nowPlaying;
    final session = playback.playbackSessionToken;
    bool current() =>
        identical(future, lyricService.currLyricFuture) &&
        session == playback.playbackSessionToken;
    if (audio == null || !playback.canUseSegmentLoop) {
      showAppNotice(ui('请先加载一首本地歌曲，再设置片段循环。'), context: navigator.context);
      return;
    }
    try {
      final lyric = await future;
      if (!navigator.mounted) return;
      if (!current()) {
        showAppNotice(ui('歌曲或歌词已改变，请重新选择练习片段'), context: navigator.context);
        return;
      }
      if (lyric == null || lyric is PlainLyric) {
        showAppNotice(ui('没有可选择的带时间歌词'), context: navigator.context);
        return;
      }
      final position = playback.position;
      await showLyricSegmentPracticeDialog(navigator.context,
          playback: playback,
          lyric: lyric,
          playbackSession: session,
          isCurrentLyric: current,
          songTitle: audio.displayTitle,
          lyricChanges: lyricService,
          initialPosition: position.isFinite
              ? Duration(milliseconds: (position * 1000).round())
              : Duration.zero);
    } catch (_) {
      if (navigator.mounted && current()) {
        showAppNotice(ui('无法打开歌词片段练习，请重新加载歌词后重试。'),
            context: navigator.context, kind: AppNoticeKind.error);
      }
    }
  }

  Future<void> _createCard(
      NavigatorState navigator, LyricViewController controller) async {
    if (!navigator.mounted) return;
    final playback = PlayService.instance.playbackService;
    final lyricService = PlayService.instance.lyricService;
    final future = lyricService.currLyricFuture;
    final audio = playback.nowPlaying;
    if (audio == null) {
      showAppNotice(ui('没有可制作卡片的歌词'), context: navigator.context);
      return;
    }
    final session = playback.playbackSessionToken;
    final position = Duration(milliseconds: (playback.position * 1000).round());
    final title = audio.displayTitle;
    final artist = audio.artist;
    final album = audio.album;
    final translation = controller.showTranslation;
    final romanization = controller.showRomanization;
    final timestamp = controller.showTimestamps;
    try {
      final lyric = await future;
      if (!navigator.mounted) return;
      if (!identical(future, lyricService.currLyricFuture) ||
          session != playback.playbackSessionToken) {
        showAppNotice(ui('歌曲或歌词已改变，请重新制作卡片'), context: navigator.context);
        return;
      }
      final selection = lyric == null
          ? (lines: <String>[], initialIndex: 0)
          : lyricShareProjection(lyric,
              position: position,
              project: (line) => lyricReadingText(line,
                  translation: translation,
                  romanization: romanization,
                  timestamp: timestamp && lyric is! PlainLyric));
      if (selection.lines.isEmpty) {
        showAppNotice(ui('没有可制作卡片的歌词'), context: navigator.context);
        return;
      }
      ImageProvider? artwork;
      if (audio.isLocal) {
        try {
          artwork = await audio.largeCover;
        } catch (_) {}
      }
      if (!navigator.mounted) return;
      // Lyrics and metadata already belong to this captured song. A later
      // switch leaves an open card as a stable snapshot of the chosen content.
      await showLyricShareDialog(navigator.context,
          title: title,
          artist: artist,
          album: album,
          lines: selection.lines,
          initialIndex: selection.initialIndex,
          artwork: artwork);
    } catch (error) {
      if (navigator.mounted &&
          identical(future, lyricService.currLyricFuture) &&
          session == playback.playbackSessionToken) {
        showAppNotice(ui('制作歌词卡片失败：{0}', [error]),
            context: navigator.context, kind: AppNoticeKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LyricViewController>();
    return LyricReadingMenu(
        controller: controller,
        readLyric: () => PlayService.instance.lyricService.currLyricFuture,
        onFind: (navigator) => findCurrentLyrics(navigator, controller),
        onCreateCard: (navigator) => _createCard(navigator, controller),
        onPracticeSegment: _practiceSegment);
  }
}

/// The entry captures one loaded document/session. Closing a stale dialog can
/// never move the replacement song's viewport or its transport.
Future<void> findCurrentLyrics(
    NavigatorState navigator, LyricViewController controller) async {
  if (!navigator.mounted) return;
  final playback = PlayService.instance.playbackService;
  final lyrics = PlayService.instance.lyricService;
  final future = lyrics.currLyricFuture;
  final session = playback.playbackSessionToken;
  final title = playback.nowPlaying?.displayTitle ?? '';
  bool current() =>
      identical(future, lyrics.currLyricFuture) &&
      session == playback.playbackSessionToken;
  await findLyricsForReading(navigator, controller,
      lyricFuture: future,
      isCurrentLyric: current,
      songTitle: title,
      lyricChanges: Listenable.merge([lyrics, playback]));
}

Future<void> findLyricsForReading(
    NavigatorState navigator, LyricViewController controller,
    {required Future<Lyric?>? lyricFuture,
    required bool Function() isCurrentLyric,
    required String songTitle,
    Listenable? lyricChanges}) async {
  if (!navigator.mounted ||
      controller._disposed ||
      controller._finding ||
      !isCurrentLyric()) {
    return;
  }
  controller._finding = true;
  try {
    final lyric = await lyricFuture;
    if (!navigator.mounted || controller._disposed || !isCurrentLyric()) return;
    if (lyric == null || lyric.lines.isEmpty) {
      showAppNotice(ui('没有可查找的歌词'), context: navigator.context);
      return;
    }
    final target = await showLyricFindDialog(navigator.context,
        lyric: lyric,
        isCurrentLyric: isCurrentLyric,
        songTitle: songTitle,
        lyricChanges: lyricChanges);
    if (navigator.mounted &&
        !controller._disposed &&
        isCurrentLyric() &&
        target != null &&
        target.belongsTo(lyric)) {
      controller.revealForReading(target);
    }
  } catch (_) {
    if (navigator.mounted && isCurrentLyric()) {
      showAppNotice(ui('无法查找歌词，请重新加载歌词后重试。'),
          context: navigator.context, kind: AppNoticeKind.error);
    }
  } finally {
    controller._finding = false;
  }
}

class _LyricWorkbenchBtn extends StatelessWidget {
  const _LyricWorkbenchBtn();
  @override
  Widget build(BuildContext context) {
    final audio = PlayService.instance.playbackService.nowPlaying;
    return IconButton(
      key: const ValueKey('lyric-workbench-open'),
      onPressed:
          audio == null ? null : () => showLyricWorkbenchDialog(context, audio),
      tooltip: ui('歌词校准与锁定'),
      color: Theme.of(context).colorScheme.primary,
      icon: const Icon(Symbols.tune),
    );
  }
}

class _LyricEditBtn extends StatelessWidget {
  const _LyricEditBtn();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final audio = PlayService.instance.playbackService.nowPlaying;
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: audio == null || audio.isOnline
          ? null
          : () => showLyricEditorDialog(context, audio),
      tooltip: audio?.isOnline == true ? ui("联网歌词为只读") : ui("编辑本地歌词"),
      color: scheme.primary,
      icon: const Icon(Symbols.edit_document),
    );
  }
}

class _LyricAlignSwitchBtn extends StatelessWidget {
  const _LyricAlignSwitchBtn();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final lyricViewController = context.watch<LyricViewController>();

    return IconButton(
      onPressed: lyricViewController.switchLyricTextAlign,
      tooltip: ui("切换歌词对齐方向"),
      color: scheme.primary,
      icon: Icon(switch (lyricViewController.lyricTextAlign) {
        LyricTextAlign.left => Symbols.format_align_left,
        LyricTextAlign.center => Symbols.format_align_center,
        LyricTextAlign.right => Symbols.format_align_right,
      }),
    );
  }
}

class LyricFontSizeMenu extends StatefulWidget {
  const LyricFontSizeMenu({super.key, this.hidden});

  final ValueListenable<bool>? hidden;

  @override
  State<LyricFontSizeMenu> createState() => _LyricFontSizeMenuState();
}

class _LyricFontSizeMenuState extends State<LyricFontSizeMenu>
    with WidgetsBindingObserver {
  LyricViewController? _controller;
  AppLifecycleState? _lifecycle;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    widget.hidden?.addListener(_syncAvailability);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<LyricViewController>();
    if (!identical(_controller, controller)) {
      _controller?.cancelFontSizeAdjustment();
      _controller = controller;
    }
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncAvailability();
  }

  @override
  void didUpdateWidget(LyricFontSizeMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hidden, widget.hidden)) {
      oldWidget.hidden?.removeListener(_syncAvailability);
      widget.hidden?.addListener(_syncAvailability);
      _syncAvailability();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _syncAvailability();
  }

  void _syncAvailability() {
    if (!_tickerEnabled ||
        widget.hidden?.value == true ||
        _lifecycle == AppLifecycleState.hidden ||
        _lifecycle == AppLifecycleState.paused ||
        _lifecycle == AppLifecycleState.detached) {
      _controller?.cancelFontSizeAdjustment();
    }
  }

  @override
  void dispose() {
    widget.hidden?.removeListener(_syncAvailability);
    WidgetsBinding.instance.removeObserver(this);
    _controller?.cancelFontSizeAdjustment();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final lyricViewController = context.watch<LyricViewController>();

    return AppMenuAnchor(
      consumeOutsideTap: true,
      onClose: lyricViewController.cancelFontSizeAdjustment,
      style: MenuStyle(
        shape: const WidgetStatePropertyAll(AppShape.surface),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      menuChildren: [
        _LyricFontSizePanel(controller: lyricViewController),
      ],
      builder: (context, menu, _) => IconButton(
        key: const ValueKey('lyric-font-size-open'),
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        tooltip: ui('歌词字号'),
        color: scheme.primary,
        icon: Text(
          'A±',
          style: TextStyle(
            color: scheme.primary,
            fontSize: 18,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.6,
          ),
        ),
      ),
    );
  }
}

class _LyricFontSizePanel extends StatefulWidget {
  const _LyricFontSizePanel({required this.controller});

  final LyricViewController controller;

  @override
  State<_LyricFontSizePanel> createState() => _LyricFontSizePanelState();
}

class _LyricFontSizePanelState extends State<_LyricFontSizePanel> {
  double? _draftSize;
  int? _sizingPointer;
  Offset? _pointerDown;
  bool _dragged = false;
  bool _cancelled = false;

  void _discardLocalDraft() {
    _cancelled = true;
    _draftSize = null;
    _sizingPointer = null;
    _pointerDown = null;
    _dragged = false;
  }

  @override
  void didUpdateWidget(_LyricFontSizePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.cancelFontSizeAdjustment();
      _discardLocalDraft();
    }
  }

  void _finishSizeChange(double value) {
    // Material Slider also sends onChangeEnd after a pointer cancellation.
    // The Listener has already discarded that draft, so do not persist it.
    if (_cancelled) {
      _discardLocalDraft();
      return;
    }
    if (_sizingPointer != null && !widget.controller.fontSizeAdjusting) {
      // The menu's onClose also discards a drag, while its Slider can remain
      // mounted throughout the exit fade and receive a late pointer release.
      _cancelSizeChange();
      return;
    }
    widget.controller.setFontDragPreview(null);
    setState(() => _draftSize = null);
    widget.controller.setFontSize(value.roundToDouble());
    widget.controller.setFontSizeAdjusting(false);
    _sizingPointer = null;
    _pointerDown = null;
    _dragged = false;
  }

  void _cancelSizeChange() {
    _cancelled = true;
    widget.controller.setFontDragPreview(null);
    widget.controller.setFontSizeAdjusting(false);
    if (mounted) setState(() => _draftSize = null);
    _sizingPointer = null;
    _pointerDown = null;
    _dragged = false;
  }

  Future<void> _exact(BuildContext context) async {
    final result = await showAppDialog<int>(
      context: context,
      builder: (_) => PlayerNumberDialog(
        title: ui('精确歌词字号'),
        label: ui('歌词字号'),
        value: widget.controller.lyricFontSize.round(),
        minimum: 14,
        maximum: 64,
      ),
    );
    if (context.mounted && result != null) {
      widget.controller.setFontSize(result.toDouble());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_draftSize != null && !widget.controller.fontSizeAdjusting) {
      _discardLocalDraft();
    }
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = _draftSize ?? widget.controller.lyricFontSize;
    final valueLabel = size == size.roundToDouble()
        ? '${size.round()}'
        : size.toStringAsFixed(1);
    final width =
        math.max(120.0, math.min(272.0, MediaQuery.sizeOf(context).width - 48));
    final presetMinimum = math.max(
      42.0,
      MediaQuery.textScalerOf(context)
                  .scale(theme.textTheme.labelLarge?.fontSize ?? 14) *
              2.1 +
          20,
    );
    final columns = width - 24 >= presetMinimum * 4 + 18 ? 4 : 2;
    final presetWidth = (width - 24 - (columns - 1) * 6) / columns;

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
                child: Text(ui('歌词字号'), style: theme.textTheme.titleSmall)),
            Tooltip(
              message: ui('精确歌词字号'),
              child: TextButton(
                key: const ValueKey('lyric-font-size-exact'),
                onPressed: () => _exact(context),
                child: Text(
                  valueLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.primary,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ]),
          Listener(
            onPointerDown: (event) {
              if (_sizingPointer != null || event.buttons != kPrimaryButton) {
                return;
              }
              _sizingPointer = event.pointer;
              _cancelled = false;
              _pointerDown = event.localPosition;
              _dragged = false;
            },
            onPointerMove: (event) {
              if (_sizingPointer != event.pointer ||
                  _pointerDown == null ||
                  (event.localPosition - _pointerDown!).distanceSquared <= 16) {
                return;
              }
              _dragged = true;
              if (_draftSize != null) {
                if (!widget.controller.fontSizeAdjusting) {
                  _cancelSizeChange();
                  return;
                }
                widget.controller.setFontDragPreview(_draftSize);
              }
            },
            onPointerCancel: (event) {
              if (_sizingPointer == event.pointer) _cancelSizeChange();
            },
            onPointerUp: (event) {
              if (_sizingPointer != event.pointer) return;
              // Pointer up can precede Slider's onChangeEnd, or no slider
              // recognizer may have accepted this hit at all.
              if (!widget.controller.fontSizeAdjusting) {
                _cancelSizeChange();
              } else {
                _sizingPointer = null;
                _pointerDown = null;
                _dragged = false;
              }
            },
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                showValueIndicator: ShowValueIndicator.never,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              child: Slider(
                key: const ValueKey('lyric-font-size-slider'),
                value: size.clamp(14.0, 64.0),
                min: 14,
                max: 64,
                divisions: 50,
                allowedInteraction: SliderInteraction.tapAndSlide,
                semanticFormatterCallback: (value) => '${value.round()}',
                onChangeStart: (_) {
                  // Keyboard/semantics adjustments do not deliver pointer down.
                  _cancelled = false;
                  widget.controller.setFontSizeAdjusting(true);
                },
                onChanged: (value) {
                  if (_cancelled ||
                      (_sizingPointer != null &&
                          !widget.controller.fontSizeAdjusting)) {
                    return;
                  }
                  final draft = value.roundToDouble();
                  setState(() => _draftSize = draft);
                  if (_dragged) widget.controller.setFontDragPreview(draft);
                },
                onChangeEnd: _finishSizeChange,
              ),
            ),
          ),
          const Row(children: [
            Text('14'),
            Spacer(),
            Text('64'),
          ]),
          TextButton(
            onPressed: widget.controller.resetFontSize,
            child: Text(ui('恢复歌词字号')),
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in [18, 22, 32, 48])
                SizedBox(
                  width: presetWidth,
                  child: Tooltip(
                    message: ui('字号设为 {0}', [preset]),
                    child: OutlinedButton(
                      key: ValueKey('lyric-font-size-preset-$preset'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(42, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        backgroundColor:
                            size == preset ? scheme.primaryContainer : null,
                        foregroundColor:
                            size == preset ? scheme.onPrimaryContainer : null,
                      ),
                      onPressed: () => widget.controller
                          .setPresetFontSize(preset.toDouble()),
                      child: Text('$preset'),
                    ),
                  ),
                ),
            ],
          ),
        ]),
      ),
    );
  }
}
