import 'dart:ui';

import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

const WHITE_TRANSPARENT = Color.fromARGB(0, 255, 255, 255);
const BLACK_TRANSPARENT = Color.fromARGB(0, 0, 0, 0);
final ValueNotifier<double> BACKGROUND_OPACITY = ValueNotifier(0);

class DesktopLyricBody extends StatefulWidget {
  const DesktopLyricBody({super.key});

  @override
  State<DesktopLyricBody> createState() => _DesktopLyricBodyState();
}

class _DesktopLyricBodyState extends State<DesktopLyricBody> {
  bool isHovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeChangedMessage>();

    return ValueListenableBuilder(
        valueListenable: BACKGROUND_OPACITY,
        builder: (context, opacity, _) {
          final surface = Color(theme.surfaceContainer);
          final background = surface.withValues(
            alpha: isHovering ? 0.86 : opacity,
          );
          return TweenAnimationBuilder(
            duration: AppMotion.standard,
            curve: AppMotion.standardCurve,
            tween: ColorTween(end: background),
            builder: (context, value, child) => DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isHovering ? 0.22 : 0.0,
                    ),
                    blurRadius: 20.0,
                    offset: const Offset(0.0, 8.0),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14.0),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: value ?? background,
                      borderRadius: BorderRadius.circular(14.0),
                      border: Border.all(
                        color: Color(theme.onSurface).withValues(
                          alpha: isHovering ? 0.18 : 0.0,
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
              onPanStart: (details) {
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
                    child: DesktopLyricForeground(isHovering: isHovering)),
              ),
            ),
          );
        });
  }
}
