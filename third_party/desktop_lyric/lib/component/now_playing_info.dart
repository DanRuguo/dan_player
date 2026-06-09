import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class NowPlayingInfo extends StatelessWidget {
  const NowPlayingInfo({super.key});

  @override
  Widget build(BuildContext context) {
    final textDisplayController = context.watch<TextDisplayController>();
    final theme = context.watch<ThemeChangedMessage>();

    final textColor = textDisplayController.hasSpecifiedColor
        ? textDisplayController.specifiedColor
        : Color(theme.primary);
    final textStyle = TextStyle(
      color: textColor,
      fontWeight: FontWeight.w600,
    );

    return ValueListenableBuilder(
      valueListenable: DesktopLyricController.instance.nowPlaying,
      builder: (context, nowPlaying, _) {
        return AnimatedSwitcher(
          duration: AppMotion.standard,
          switchInCurve: AppMotion.standardCurve,
          switchOutCurve: Curves.easeInCubic,
          child: Column(
            key: ValueKey(nowPlaying.title),
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                nowPlaying.title,
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                "${nowPlaying.artist} - ${nowPlaying.album}",
                style: textStyle.copyWith(
                  color: textColor.withValues(alpha: 0.82),
                  fontSize: 12.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}
