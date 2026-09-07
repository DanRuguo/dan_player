import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_lyric/appearance_controller.dart';
import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/app_presentation.dart';
import 'package:desktop_lyric/component/action_row.dart';
import 'package:desktop_lyric/component/lyric_line_view.dart';
import 'package:desktop_lyric/component/now_playing_info.dart';
import 'package:desktop_lyric/component/taskbar_lyric_row.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
export 'package:desktop_lyric/appearance_controller.dart';
import 'package:desktop_lyric/ui_language.dart';

bool ALWAYS_SHOW_ACTION_ROW = false;

class DesktopLyricForeground extends StatefulWidget {
  const DesktopLyricForeground(
      {super.key,
      required this.isHovering,
      this.controller,
      this.textController,
      this.windowLayout,
      this.sendMessage});

  final bool isHovering;
  final DesktopLyricController? controller;
  final TextDisplayController? textController;
  final DesktopLyricWindowLayout? windowLayout;
  final void Function(String message)? sendMessage;

  @override
  State<DesktopLyricForeground> createState() => _DesktopLyricForegroundState();
}

class _DesktopLyricForegroundState extends State<DesktopLyricForeground> {
  Object? _minimumIdentity;
  int _layoutGeneration = 0;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final source = widget.controller ?? DesktopLyricController.instance;
    final texts = widget.textController ?? source.appearance;
    final window = widget.windowLayout ?? DesktopLyricWindowLayout.instance;
    return ChangeNotifierProvider.value(
      value: texts,
      child: ListenableBuilder(
        listenable: Listenable.merge([source.vertical, texts]),
        builder: (context, _) => LayoutBuilder(builder: (context, constraints) {
          if (texts.value.taskbarMode) {
            final height = math.max(
                44.0,
                MediaQuery.textScalerOf(context)
                            .scale(texts.value.taskbarMinimumFontSize) *
                        1.3 +
                    4);
            final identity = ('taskbar', height, window);
            if (_minimumIdentity != identity) {
              _minimumIdentity = identity;
              final generation = ++_layoutGeneration;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || generation != _layoutGeneration) return;
                unawaited(window
                    .ensureTaskbarMinimumHeight(height)
                    .catchError((Object error) {
                  window.lastError.value = ui("调整单行歌词高度失败：{0}", [error]);
                }));
              });
            }
            return TaskbarLyricRow(
                controller: source,
                windowLayout: window,
                sendMessage: widget.sendMessage);
          }
          final vertical = source.vertical.value;
          final scaler = MediaQuery.textScalerOf(context);
          final columns =
              math.max(1, ((constraints.maxWidth - 8) / 48).floor());
          final rows = (9 / columns).ceil();
          final controlsHeight = rows * 44.0 + (rows - 1) * 4;
          final infoHeight =
              math.max(44.0, scaler.scale(14) * 1.5 + scaler.scale(12) * 1.5);
          final showControls = widget.isHovering || ALWAYS_SHOW_ACTION_ROW;
          // Both children coexist during the switch animation. A stable slot
          // prevents the outgoing large-text metadata from being squeezed and
          // also avoids changing HWND minimum geometry on each hover change.
          final headerHeight = math.max(controlsHeight, infoHeight);
          final minimum = Size(
            vertical
                ? math.max(
                    200,
                    32 +
                        scaler.scale(texts.lyricFontSize +
                                texts.translationFontSize) *
                            1.3)
                : 320,
            headerHeight +
                24 +
                (vertical
                    ? math.max(96, scaler.scale(texts.lyricFontSize) * 2.6)
                    : scaler.scale(texts.lyricFontSize +
                                texts.translationFontSize) *
                            1.3 +
                        4),
          );
          final identity = (minimum, vertical, window);
          if (_minimumIdentity != identity) {
            _minimumIdentity = identity;
            final generation = ++_layoutGeneration;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || generation != _layoutGeneration) return;
              unawaited(window
                  .ensureContentMinimum(minimum, vertical: vertical)
                  .catchError((Object error) {
                if (!context.mounted) return;
                showPresentationNotice(ui("调整歌词窗口失败：{0}", [error]),
                    context: context, kind: AppNoticeKind.error);
              }));
            });
          }
          final reduced = MediaQuery.disableAnimationsOf(context) ||
              !TickerMode.valuesOf(context).enabled;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              SizedBox(
                height: headerHeight,
                child: AnimatedSwitcher(
                  duration: reduced ? Duration.zero : AppMotion.standard,
                  switchInCurve: AppMotion.standardCurve,
                  switchOutCurve: Curves.easeInCubic,
                  child: showControls
                      ? RepaintBoundary(
                          key: const ValueKey('desktop-actions'),
                          child: ActionRow(
                              controller: source,
                              windowLayout: window,
                              sendMessage: widget.sendMessage))
                      : RepaintBoundary(
                          key: const ValueKey('desktop-now-playing'),
                          child: NowPlayingInfo(controller: source)),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: LyricLineView(controller: source)),
            ]),
          );
        }),
      ),
    );
  }

  @override
  void dispose() {
    ++_layoutGeneration;
    super.dispose();
  }
}
