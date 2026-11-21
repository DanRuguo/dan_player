import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

String formatDesktopNowPlayingSubtitle(String artist, String album) {
  final trimmedArtist = artist.trim();
  final trimmedAlbum = album.trim();
  if (trimmedArtist.isEmpty) return trimmedAlbum;
  if (trimmedAlbum.isEmpty || trimmedAlbum == trimmedArtist) {
    return trimmedArtist;
  }
  return '$trimmedArtist · $trimmedAlbum';
}

class NowPlayingInfo extends StatelessWidget {
  const NowPlayingInfo({super.key, this.controller});

  final DesktopLyricController? controller;

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
      valueListenable:
          (controller ?? DesktopLyricController.instance).nowPlaying,
      builder: (context, nowPlaying, _) {
        final subtitle = formatDesktopNowPlayingSubtitle(
          nowPlaying.artist,
          nowPlaying.album,
        );
        return AnimatedSwitcher(
          duration: !AppMotion.enabled(context, MotionKind.transitions) ||
                  !TickerMode.valuesOf(context).enabled
              ? Duration.zero
              : AppMotion.standard,
          switchInCurve: AppMotion.standardCurve,
          switchOutCurve: Curves.easeInCubic,
          child: Column(
            key: ValueKey(
              (nowPlaying.title, nowPlaying.artist, nowPlaying.album),
            ),
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppFontText(
                nowPlaying.title,
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle.isNotEmpty)
                AppFontText(
                  subtitle,
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
