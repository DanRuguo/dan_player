import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/lyric_editor_dialog.dart';
import 'package:dan_player/component/lyric_workbench_dialog.dart';
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
    nowPlayingPagePref.lyricFontSize = lyricFontSize = 22;
    nowPlayingPagePref.translationFontSize = translationFontSize = 18;
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
    lyricFontSize += 1;
    translationFontSize += 1;

    nowPlayingPagePref.lyricFontSize = lyricFontSize;
    nowPlayingPagePref.translationFontSize = translationFontSize;
    notifyListeners();
  }

  void decreaseFontSize() {
    if (lyricFontSize <= 14 || translationFontSize <= 14) return;

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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IncreaseFontSizeBtn(),
              SizedBox(width: 8.0),
              _DecreaseFontSizeBtn(),
            ],
          )
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

class _IncreaseFontSizeBtn extends StatelessWidget {
  const _IncreaseFontSizeBtn();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final lyricViewController = context.watch<LyricViewController>();

    return IconButton(
      onPressed: lyricViewController.increaseFontSize,
      tooltip: ui("增大歌词字体"),
      color: scheme.primary,
      icon: const Icon(Symbols.text_increase),
    );
  }
}

class _DecreaseFontSizeBtn extends StatelessWidget {
  const _DecreaseFontSizeBtn();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final lyricViewController = context.watch<LyricViewController>();

    return IconButton(
      onPressed: lyricViewController.decreaseFontSize,
      tooltip: ui("减小歌词字体"),
      color: scheme.primary,
      icon: const Icon(Symbols.text_decrease),
    );
  }
}
