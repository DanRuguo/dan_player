import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:flutter/material.dart';

/// Edits notify the pipe owner; applying a player snapshot never echoes it.
class TextDisplayController extends ValueNotifier<DesktopLyricAppearance> {
  TextDisplayController({this.onChanged})
      : super(DesktopLyricAppearance.defaults);
  final void Function(DesktopLyricAppearance)? onChanged;

  double get lyricFontSize => value.lyricFontSize;
  double get translationFontSize => value.translationFontSize;
  bool get hasSpecifiedColor => value.customColor != null;
  Color get specifiedColor => Color(value.customColor ?? 0xff2196f3);

  void _edit(DesktopLyricAppearance next) {
    if (value == next) return;
    value = next;
    onChanged?.call(next);
  }

  void increaseLyricFontSize() {
    if (lyricFontSize >= 64 || translationFontSize >= 60) return;
    _edit(value.copyWith(
        lyricFontSize: (lyricFontSize + 1).clamp(18, 64),
        translationFontSize: (translationFontSize + 1).clamp(14, 60)));
  }

  void decreaseLyricFontSize() {
    if (lyricFontSize <= 18 || translationFontSize <= 14) return;
    _edit(value.copyWith(
        lyricFontSize: (lyricFontSize - 1).clamp(18, 64),
        translationFontSize: (translationFontSize - 1).clamp(14, 60)));
  }

  void spcifiyColor(Color color) =>
      _edit(value.copyWith(customColor: color.toARGB32()));

  /// Shared options widgets submit a complete immutable appearance snapshot.
  void update(DesktopLyricAppearance appearance) => _edit(appearance);
  void usePlayerTheme() => _edit(value.copyWith(followTheme: true));
  void setBackgroundOpacity(double opacity) =>
      _edit(value.copyWith(backgroundOpacity: opacity));
  void setTextOpacity(double opacity) =>
      _edit(value.copyWith(textOpacity: opacity));
  void setStrokeEnabled(bool enabled) =>
      _edit(value.copyWith(strokeEnabled: enabled));
  void setTaskbarMode(bool enabled) =>
      _edit(value.copyWith(taskbarMode: enabled));
  void setTaskbarGap(double gap) => _edit(value.copyWith(taskbarGap: gap));
  void setTaskbarHeight(double height) =>
      _edit(value.copyWith(taskbarHeight: height));
  void setTaskbarMinimumFontSize(double size) =>
      _edit(value.copyWith(taskbarMinimumFontSize: size));
  void setTaskbarTranslation(bool enabled) =>
      _edit(value.copyWith(taskbarTranslation: enabled));
}
