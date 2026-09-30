import 'dart:math' as math;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/lyric_editor_dialog.dart';
import 'package:dan_player/component/lyric_workbench_dialog.dart';
import 'package:dan_player/component/player_number_dialog.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_source_view.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'lyric_reading_tools.dart';

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
    if (!value) returnRequest++;
    notifyListeners();
  }

  void returnToCurrent() {
    readingMode = false;
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
  const LyricViewControls({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return const Padding(
      padding: EdgeInsets.all(8.0),
      child: SingleChildScrollView(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SetLyricSourceBtn(),
          SizedBox(height: 8.0),
          _LyricWorkbenchBtn(),
          SizedBox(height: 8.0),
          _LyricEditBtn(),
          SizedBox(height: 8.0),
          _LyricAlignSwitchBtn(),
          SizedBox(height: 8.0),
          _LyricReadingMenu(),
          SizedBox(height: 8.0),
          LyricFontSizeMenu(),
        ],
      )),
    );
  }
}

class _LyricReadingMenu extends StatelessWidget {
  const _LyricReadingMenu();
  @override
  Widget build(BuildContext context) => LyricReadingMenu(
      controller: context.watch<LyricViewController>(),
      readLyric: () => PlayService.instance.lyricService.currLyricFuture);
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

class LyricFontSizeMenu extends StatelessWidget {
  const LyricFontSizeMenu({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final lyricViewController = context.watch<LyricViewController>();

    return AppMenuAnchor(
      consumeOutsideTap: true,
      onClose: () {
        lyricViewController.setFontDragPreview(null);
        lyricViewController.setFontSizeAdjusting(false);
      },
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
  Offset? _pointerDown;
  bool _dragged = false;

  void _finishSizeChange(double value) {
    widget.controller.setFontDragPreview(null);
    setState(() => _draftSize = null);
    widget.controller.setFontSize(value.roundToDouble());
    widget.controller.setFontSizeAdjusting(false);
    _pointerDown = null;
    _dragged = false;
  }

  void _cancelSizeChange() {
    widget.controller.setFontDragPreview(null);
    widget.controller.setFontSizeAdjusting(false);
    if (mounted) setState(() => _draftSize = null);
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
              _pointerDown = event.localPosition;
              _dragged = false;
            },
            onPointerMove: (event) {
              if (_pointerDown == null ||
                  (event.localPosition - _pointerDown!).distanceSquared <= 16) {
                return;
              }
              _dragged = true;
              if (_draftSize != null) {
                widget.controller.setFontDragPreview(_draftSize);
              }
            },
            onPointerCancel: (_) => _cancelSizeChange(),
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
                onChangeStart: (_) =>
                    widget.controller.setFontSizeAdjusting(true),
                onChanged: (value) {
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
