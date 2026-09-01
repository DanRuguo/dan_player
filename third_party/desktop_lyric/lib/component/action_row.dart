import 'dart:async';
import 'dart:io';

import 'package:desktop_lyric/appearance_controller.dart';
import 'package:desktop_lyric/appearance_palette_bridge.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:desktop_lyric/ui_language.dart';

class ActionRow extends StatelessWidget {
  const ActionRow(
      {super.key, this.controller, this.windowLayout, this.sendMessage});
  final DesktopLyricController? controller;
  final DesktopLyricWindowLayout? windowLayout;
  final void Function(String message)? sendMessage;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = context.watch<ThemeChangedMessage>();
    final source = controller ?? DesktopLyricController.instance;
    final texts = context.read<TextDisplayController>();
    final layout = windowLayout ?? DesktopLyricWindowLayout.instance;
    void send(Message message) =>
        (sendMessage ?? stdout.write)(message.buildMessageJson());
    Widget button(String tooltip, IconData icon, VoidCallback onPressed,
            {Key? key}) =>
        IconButton(
            key: key,
            tooltip: tooltip,
            onPressed: onPressed,
            color: Color(theme.primary),
            style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                visualDensity: VisualDensity.standard,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            icon: Icon(icon));
    return ListenableBuilder(
      listenable: Listenable.merge([source.isPlaying, source.vertical]),
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            button(
                ui("增大字号"), Symbols.text_increase, texts.increaseLyricFontSize),
            button(
                ui("减小字号"), Symbols.text_decrease, texts.decreaseLyricFontSize),
            button(
                ui("上一首"),
                Symbols.skip_previous,
                () => send(
                    const ControlEventMessage(ControlEvent.previousAudio))),
            button(
                source.isPlaying.value ? ui("暂停") : ui("播放"),
                source.isPlaying.value ? Symbols.pause : Symbols.play_arrow,
                () => send(ControlEventMessage(source.isPlaying.value
                    ? ControlEvent.pause
                    : ControlEvent.start))),
            button(ui("下一首"), Symbols.skip_next,
                () => send(const ControlEventMessage(ControlEvent.nextAudio))),
            DesktopLyricAppearanceButton(
                windowLayout: layout,
                controller: source,
                textController: texts),
            button(source.vertical.value ? ui("切换为横排歌词") : ui("切换为竖排歌词"),
                source.vertical.value ? Icons.swap_horiz : Icons.swap_vert, () {
              final next = !source.vertical.value;
              source.vertical.value = next;
              send(DesktopLyricDisplayChangedMessage(vertical: next));
            }, key: const ValueKey('desktop-lyric-direction')),
            button(ui("锁定歌词；可在播放器中解锁"), Symbols.lock, () async {
              try {
                await source.setLocked(true);
                send(const ControlEventMessage(ControlEvent.lock));
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(content: Text(ui("无法锁定歌词：{0}", [error]))));
              }
            }, key: const ValueKey('desktop-lyric-lock')),
            button(ui("关闭桌面歌词"), Symbols.close,
                () => send(const ControlEventMessage(ControlEvent.close)),
                key: const ValueKey('desktop-lyric-close')),
          ],
        ),
      ),
    );
  }
}

/// Opens an independently owned native palette; the lyric surface is untouched.
class DesktopLyricAppearanceButton extends StatefulWidget {
  const DesktopLyricAppearanceButton(
      {super.key,
      required this.windowLayout,
      required this.controller,
      this.textController,
      this.paletteHost,
      this.iconSize = 24});
  final DesktopLyricWindowLayout windowLayout;
  final DesktopLyricController controller;
  final TextDisplayController? textController;
  final DesktopLyricPaletteHost? paletteHost;
  final double iconSize;
  @override
  State<DesktopLyricAppearanceButton> createState() =>
      _DesktopLyricAppearanceButtonState();
}

class _DesktopLyricAppearanceButtonState
    extends State<DesktopLyricAppearanceButton> {
  bool _opening = false;
  bool _starting = false;
  Future<void> _open() async {
    if (_opening) return;
    final host = widget.paletteHost ??
        DesktopLyricPaletteScope.maybeOf(context) ??
        DesktopLyricPaletteHost.instance;
    setState(() {
      _opening = true;
      _starting = true;
    });
    void startingChanged() {
      if (mounted) setState(() => _starting = host.isStarting.value);
    }

    host.isStarting.addListener(startingChanged);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await host.open();
    } catch (error) {
      if (messenger?.mounted == true) {
        messenger!.showSnackBar(
            SnackBar(content: Text(ui('无法打开歌词外观窗口：{0}', [error]))));
      }
    } finally {
      host.isStarting.removeListener(startingChanged);
      if (mounted) {
        setState(() {
          _opening = false;
          _starting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ValueListenableBuilder(
      valueListenable: widget.controller.theme,
      builder: (context, theme, _) => ValueListenableBuilder(
        valueListenable: widget.windowLayout.lastError,
        builder: (context, error, _) => IconButton(
          key: const ValueKey('desktop-appearance-open'),
          tooltip: error == null ? ui('歌词外观') : ui('歌词外观\n{0}', [ui(error)]),
          onPressed: _opening ? null : _open,
          color: Color(theme.primary),
          style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          icon: _starting
              ? SizedBox.square(
                  dimension: widget.iconSize - 4,
                  child: CircularProgressIndicator(
                      key: const ValueKey('desktop-appearance-starting'),
                      value:
                          MediaQuery.maybeDisableAnimationsOf(context) == true
                              ? .75
                              : null,
                      strokeWidth: 2,
                      color: Color(theme.primary)))
              : Icon(Symbols.palette, size: widget.iconSize),
        ),
      ),
    );
  }
}
