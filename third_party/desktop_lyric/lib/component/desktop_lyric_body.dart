import 'dart:ui';

import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

class DesktopLyricBody extends StatefulWidget {
  const DesktopLyricBody(
      {super.key, this.controller, this.windowLayout, this.sendMessage});
  final DesktopLyricController? controller;
  final DesktopLyricWindowLayout? windowLayout;
  final void Function(String message)? sendMessage;

  @override
  State<DesktopLyricBody> createState() => _DesktopLyricBodyState();
}

class _DesktopLyricBodyState extends State<DesktopLyricBody> {
  bool isHovering = false;
  bool _touchControlsVisible = false;
  bool _paletteWasActive = false;
  bool _paletteControlsVisible = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeChangedMessage>();
    final source = widget.controller ?? DesktopLyricController.instance;
    final window = widget.windowLayout ?? DesktopLyricWindowLayout.instance;

    return ListenableBuilder(
        listenable:
            Listenable.merge([source.appearance, window.palettePresentation]),
        builder: (context, _) => LayoutBuilder(builder: (context, constraints) {
              final appearance = source.appearance.value;
              final presentation = window.palettePresentation.value;
              final paletteActive = presentation != null;
              if (paletteActive && !_paletteWasActive) {
                _paletteControlsVisible = isHovering || _touchControlsVisible;
              }
              if (!paletteActive &&
                  _paletteWasActive &&
                  window.paletteExitHover != null) {
                isHovering = window.paletteExitHover!;
              }
              _paletteWasActive = paletteActive;
              final frame = Offset.zero & constraints.biggest;
              final surface = Color(theme.surfaceContainer);
              final showControls = paletteActive
                  ? _paletteControlsVisible
                  : isHovering || _touchControlsVisible;
              return Stack(children: [
                Positioned.fromRect(
                  rect: frame,
                  child: ClipRect(
                      child: TweenAnimationBuilder<double>(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : AppMotion.standard,
                    curve: AppMotion.standardCurve,
                    tween: Tween(end: showControls ? 1 : 0),
                    builder: (context, value, child) => DecoratedBox(
                      key: const ValueKey('desktop-lyric-surface'),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: value * 0.22,
                            ),
                            blurRadius: 20.0,
                            offset: const Offset(0.0, 8.0),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14.0),
                        child: BackdropFilter(
                          enabled:
                              value > 0 || appearance.backgroundOpacity > 0,
                          filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
                          child: DecoratedBox(
                            key: const ValueKey('desktop-lyric-background'),
                            decoration: BoxDecoration(
                              color: surface.withValues(
                                  alpha: appearance.backgroundOpacity +
                                      (0.86 - appearance.backgroundOpacity) *
                                          value),
                              borderRadius: BorderRadius.circular(14.0),
                              border: Border.all(
                                color: Color(theme.onSurface).withValues(
                                  alpha: value * 0.18,
                                ),
                              ),
                            ),
                            child: Scaffold(
                              backgroundColor: Colors.transparent,
                              body: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onLongPress: () => setState(() {
                        _touchControlsVisible = !_touchControlsVisible;
                      }),
                      onPanStart: appearance.taskbarMode
                          ? null
                          : (details) {
                              windowManager.startDragging();
                            },
                      child: MouseRegion(
                        onEnter: (_) {
                          setState(() {
                            isHovering = true;
                          });
                        },
                        onExit: (_) {
                          setState(() {
                            isHovering = false;
                          });
                        },
                        child: Center(
                            child: DesktopLyricForeground(
                                isHovering: showControls,
                                controller: source,
                                windowLayout: window,
                                sendMessage: widget.sendMessage)),
                      ),
                    ),
                  )),
                )
              ]);
            }));
  }
}
