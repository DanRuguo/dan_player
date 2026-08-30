import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_lyric/component/action_row.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:desktop_lyric/ui_language.dart';

/// One bounded line and compact controls. No translation column, hover toolbar,
/// layout on clock ticks, or independent playback/settings path.
class TaskbarLyricRow extends StatelessWidget {
  const TaskbarLyricRow(
      {super.key,
      required this.controller,
      required this.windowLayout,
      this.sendMessage});
  final DesktopLyricController controller;
  final DesktopLyricWindowLayout windowLayout;
  final void Function(String)? sendMessage;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = context.watch<ThemeChangedMessage>();
    final primary = Color(theme.primary);
    void send(ControlEvent event) => (sendMessage ??
        stdout.write)(ControlEventMessage(event).buildMessageJson());
    Widget button(String label, IconData icon, VoidCallback onPressed) =>
        IconButton(
            tooltip: label,
            onPressed: onPressed,
            color: primary,
            style: IconButton.styleFrom(
                fixedSize: const Size(44, 44),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.standard,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            icon: Icon(icon, size: 22));
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.appearance,
        controller.isPlaying,
        controller.lyricLine,
        controller.detailedLyricLine,
        controller.nowPlaying
      ]),
      builder: (context, _) => LayoutBuilder(builder: (context, bounds) {
        final prefs = controller.appearance.value;
        final detailed = controller.detailedLyricLine.value;
        final legacy = controller.lyricLine.value;
        final translation =
            detailed == null ? legacy.translation : detailed.translation;
        final translated =
            prefs.taskbarTranslation && translation?.trim().isNotEmpty == true;
        final raw =
            translated ? translation! : detailed?.content ?? legacy.content;
        // One line even for malformed/multiline input; bounded work for huge tags.
        final text =
            (raw.trim().isEmpty ? controller.nowPlaying.value.title : raw)
                .replaceAll(RegExp(r'[\r\n\t]+'), ' ');
        final visibleText = text.characters.take(2048).toString();
        final compact = bounds.maxWidth < 520;
        final controls = <Widget>[
          if (!compact)
            button(ui("上一首"), Symbols.skip_previous,
                () => send(ControlEvent.previousAudio)),
          button(
              controller.isPlaying.value ? ui("暂停") : ui("播放"),
              controller.isPlaying.value ? Symbols.pause : Symbols.play_arrow,
              () => send(controller.isPlaying.value
                  ? ControlEvent.pause
                  : ControlEvent.start)),
          if (!compact)
            button(ui("下一首"), Symbols.skip_next,
                () => send(ControlEvent.nextAudio)),
          DesktopLyricAppearanceButton(
              controller: controller, windowLayout: windowLayout, iconSize: 22),
          button(ui("恢复悬浮歌词"), Symbols.open_in_full,
              () => controller.appearance.setTaskbarMode(false)),
        ];
        // Extremely small work areas still keep every control inside the HWND.
        final controlWidth = controls.length * 44.0;
        final horizontalPadding = math.min(8.0, bounds.maxWidth / 20);
        final available =
            math.max(0.0, bounds.maxWidth - horizontalPadding * 2);
        final controlScale = math.min(
            1.0, math.min(available / controlWidth, bounds.maxHeight / 44));
        return ClipRect(
            child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Row(children: [
            Expanded(child: LayoutBuilder(builder: (context, lineBounds) {
              final baseStyle = DefaultTextStyle.of(context).style.merge(
                  const TextStyle(height: 1.25, fontWeight: FontWeight.w700));
              final scaler = MediaQuery.textScalerOf(context);
              final fontSize = taskbarLyricFontSize(visibleText,
                  style: baseStyle,
                  scaler: scaler,
                  direction: Directionality.of(context),
                  width: lineBounds.maxWidth,
                  height: lineBounds.maxHeight - 4,
                  preferred: prefs.lyricFontSize,
                  minimum: prefs.taskbarMinimumFontSize);
              final color = prefs.customColor == null
                  ? primary
                  : Color(prefs.customColor!);
              return Semantics(
                  label: text,
                  child: ExcludeSemantics(
                      child: Center(
                    child: Opacity(
                        opacity: prefs.textOpacity,
                        child: DesktopLyricText(
                          key: const ValueKey('taskbar-single-line-text'),
                          text: visibleText,
                          clock: controller.playbackClock,
                          style: baseStyle.copyWith(fontSize: fontSize),
                          maxHorizontalWidth: lineBounds.maxWidth,
                          playedColor: color,
                          unplayedColor: color.withValues(alpha: .7),
                          strokeColor: prefs.strokeEnabled
                              ? (color.computeLuminance() > .45
                                  ? Colors.black
                                  : Colors.white)
                              : null,
                          words: translated
                              ? const []
                              : detailed?.words ?? const [],
                          reducedMotion:
                              MediaQuery.disableAnimationsOf(context),
                        )),
                  )));
            })),
            SizedBox(
                width: controlWidth * controlScale,
                height: 44 * controlScale,
                child: FittedBox(
                    fit: BoxFit.contain,
                    child: Row(
                        mainAxisSize: MainAxisSize.min, children: controls))),
          ]),
        ));
      }),
    );
  }
}

/// Binary search only on line/width/preferences changes, never on playback ticks.
double taskbarLyricFontSize(String text,
    {required TextStyle style,
    required TextScaler scaler,
    required TextDirection direction,
    required double width,
    required double height,
    required double preferred,
    required double minimum}) {
  final painter =
      TextPainter(textDirection: direction, textScaler: scaler, maxLines: 1);
  bool fits(double size) {
    painter.text = TextSpan(text: text, style: style.copyWith(fontSize: size));
    painter.layout();
    return painter.width <= width && painter.height <= height;
  }

  try {
    var low = minimum;
    var high = math.max(minimum, preferred);
    // A high system text scale can exceed even the smallest configured row.
    // Fit height first; width overflow remains ellipsized, never multiline.
    fits(low);
    if (painter.height > height && height > 0) {
      low = math.max(1.0, low * height / painter.height);
    }
    if (fits(high)) return high;
    if (!fits(low)) return low; // Cached paragraph supplies safe ellipsis.
    for (var i = 0; i < 8; i++) {
      final mid = (low + high) / 2;
      if (fits(mid)) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return low;
  } finally {
    painter.dispose();
  }
}
