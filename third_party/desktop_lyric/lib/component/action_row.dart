import 'dart:async';
import 'dart:io';

import 'package:desktop_lyric/component/desktop_lyric_body.dart';
import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:win32/win32.dart' as win32;
import 'package:window_manager/window_manager.dart';

class ActionRow extends StatelessWidget {
  const ActionRow({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeChangedMessage>();
    const spacer = SizedBox(width: 8.0);

    final textDisplayController = context.read<TextDisplayController>();

    return Stack(
      alignment: Alignment.centerRight,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton(
            onPressed: () async {
              hWnd = win32.GetForegroundWindow();

              if (hWnd != null) {
                final exStyle = win32.GetWindowLongPtr(
                  hWnd!,
                  win32.WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE,
                );

                win32.SetWindowLongPtr(
                  hWnd!,
                  win32.WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE,
                  exStyle |
                      win32.WINDOW_EX_STYLE.WS_EX_LAYERED |
                      win32.WINDOW_EX_STYLE.WS_EX_TRANSPARENT,
                );

                stdout.write(
                  const ControlEventMessage(ControlEvent.lock)
                      .buildMessageJson(),
                );
              }
            },
            color: Color(theme.onSurface),
            icon: const Icon(Symbols.lock),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: textDisplayController.increaseLyricFontSize,
              color: Color(theme.onSurface),
              icon: const Icon(Symbols.text_increase),
            ),
            spacer,
            IconButton(
              onPressed: textDisplayController.decreaseLyricFontSize,
              color: Color(theme.onSurface),
              icon: const Icon(Symbols.text_decrease),
            ),
            spacer,
            IconButton(
              onPressed: () {
                stdout.write(
                  const ControlEventMessage(ControlEvent.previousAudio)
                      .buildMessageJson(),
                );
              },
              color: Color(theme.onSurface),
              icon: const Icon(Symbols.skip_previous),
            ),
            spacer,
            ValueListenableBuilder(
              valueListenable: DesktopLyricController.instance.isPlaying,
              builder: (context, isPlaying, _) => IconButton(
                onPressed: () {
                  stdout.write(
                    ControlEventMessage(
                      isPlaying ? ControlEvent.pause : ControlEvent.start,
                    ).buildMessageJson(),
                  );
                },
                color: Color(theme.onSurface),
                icon: Icon(isPlaying ? Symbols.pause : Symbols.play_arrow),
              ),
            ),
            spacer,
            IconButton(
              onPressed: () {
                stdout.write(
                  const ControlEventMessage(ControlEvent.nextAudio)
                      .buildMessageJson(),
                );
              },
              color: Color(theme.onSurface),
              icon: const Icon(Symbols.skip_next),
            ),
            spacer,
            const _ShowColorSelectorBtn(),
            spacer,
            IconButton(
              onPressed: () {
                stdout.write(
                  const ControlEventMessage(ControlEvent.close)
                      .buildMessageJson(),
                );
              },
              color: Color(theme.onSurface),
              icon: const Icon(Symbols.close),
            ),
          ],
        ),
      ],
    );
  }
}

final _colorSelectorController = MenuController();

const Size _colorSelectorWindowSize = Size(800.0, 360.0);
const Size _colorSelectorMinimumSize = Size(520.0, 320.0);
const Size _compactMinimumSize = Size(320.0, 72.0);

void _showColorSelectorWindow() {
  ALWAYS_SHOW_ACTION_ROW = true;
  unawaited(windowManager.setMinimumSize(_colorSelectorMinimumSize));
  unawaited(windowManager.setSize(_colorSelectorWindowSize));
}

void _restoreCompactWindow() {
  ALWAYS_SHOW_ACTION_ROW = false;
  unawaited(windowManager.setMinimumSize(_compactMinimumSize));
  resizeWithForegroundSize();
}

class _ShowColorSelectorBtn extends StatelessWidget {
  const _ShowColorSelectorBtn();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeChangedMessage>();
    return MenuAnchor(
      controller: _colorSelectorController,
      consumeOutsideTap: true,
      onOpen: () {
        _showColorSelectorWindow();
      },
      onClose: () {
        _restoreCompactWindow();
      },
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          Color(theme.surfaceContainer).withValues(alpha: 0.94),
        ),
        elevation: const WidgetStatePropertyAll(12.0),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: 0.24),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
            side: BorderSide(
              color: Color(theme.onSurface).withValues(alpha: 0.12),
            ),
          ),
        ),
      ),
      menuChildren: [
        SizedBox(
          width: 360.0,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PanelHeader(theme: theme),
                const SizedBox(height: 14.0),
                _OpacityControl(theme: theme),
                const SizedBox(height: 14.0),
                _ThemeColorButton(theme: theme),
                const SizedBox(height: 14.0),
                _SectionLabel(text: "文字颜色", theme: theme),
                const SizedBox(height: 8.0),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: List.generate(
                    Colors.primaries.length,
                    (i) => _ColorTile(color: Colors.primaries[i]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
        color: Color(theme.onSurface),
        icon: const Icon(Symbols.palette),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.theme});

  final ThemeChangedMessage theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Color(theme.primary).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10.0),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              Symbols.palette,
              size: 20.0,
              color: Color(theme.primary),
            ),
          ),
        ),
        const SizedBox(width: 10.0),
        Expanded(
          child: Text(
            "歌词外观",
            style: TextStyle(
              color: Color(theme.onSurface),
              fontSize: 15.0,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _OpacityControl extends StatelessWidget {
  const _OpacityControl({required this.theme});

  final ThemeChangedMessage theme;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: BACKGROUND_OPACITY,
      builder: (context, opacity, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SectionLabel(text: "背景不透明度", theme: theme),
              ),
              SizedBox(
                width: 48.0,
                child: Text(
                  "${(opacity * 100).round()}%",
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Color(theme.onSurface).withValues(alpha: 0.72),
                    fontSize: 12.0,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              thumbColor: Color(theme.primary),
              overlayColor: Color(theme.primary).withValues(alpha: 0.08),
              activeTrackColor: Color(theme.primary),
              inactiveTrackColor: Color(theme.primary).withValues(alpha: 0.15),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              trackHeight: 4.0,
            ),
            child: Slider(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              value: opacity,
              onChanged: (newOpacity) {
                BACKGROUND_OPACITY.value = newOpacity;
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeColorButton extends StatelessWidget {
  const _ThemeColorButton({required this.theme});

  final ThemeChangedMessage theme;

  @override
  Widget build(BuildContext context) {
    final textDisplayController = context.watch<TextDisplayController>();
    final usingTheme = !textDisplayController.hasSpecifiedColor;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: () {
          textDisplayController.usePlayerTheme();
          _colorSelectorController.close();
        },
        style: FilledButton.styleFrom(
          backgroundColor: Color(theme.primary).withValues(alpha: 0.13),
          foregroundColor: Color(theme.primary),
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
        ),
        icon: Icon(usingTheme ? Symbols.check : Symbols.palette),
        label: Text(
          usingTheme ? "正在跟随播放器主题" : "跟随播放器主题",
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.text,
    required this.theme,
  });

  final String text;
  final ThemeChangedMessage theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Color(theme.onSurface).withValues(alpha: 0.72),
        fontSize: 12.0,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ColorTile extends StatelessWidget {
  const _ColorTile({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final textDisplayController = context.watch<TextDisplayController>();
    final selected = textDisplayController.hasSpecifiedColor &&
        textDisplayController.specifiedColor == color;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      width: 28.0,
      height: 28.0,
      padding: const EdgeInsets.all(2.0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? color
              : Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.38),
          width: selected ? 2.0 : 1.0,
        ),
      ),
      child: Material(
        color: color,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            textDisplayController.spcifiyColor(color);
            _colorSelectorController.close();
          },
          child: selected
              ? const Center(
                  child: Icon(
                    Symbols.check,
                    color: Colors.white,
                    size: 16.0,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
