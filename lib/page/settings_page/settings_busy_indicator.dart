import 'package:dan_player/component/app_motion.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

/// Keeps a busy state visible without an endless repaint when motion is off.
class SettingsBusyIndicator extends StatelessWidget {
  const SettingsBusyIndicator.circular({super.key, this.size = 18, this.color})
      : linear = false,
        progress = null;

  const SettingsBusyIndicator.linear({super.key, this.progress})
      : linear = true,
        size = 18,
        color = null;

  final bool linear;
  final double size;
  final double? progress;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (linear && progress != null) {
      return LinearProgressIndicator(value: progress);
    }
    if (AppMotion.enabled(context, MotionKind.feedback)) {
      return linear
          ? const LinearProgressIndicator()
          : SizedBox.square(
              dimension: size,
              child: CircularProgressIndicator(strokeWidth: 2, color: color));
    }
    UiLanguageScope.watch(context);
    return Semantics(
      label: ui('正在处理…'),
      child: ExcludeSemantics(
        child: SizedBox(
          height: size,
          width: linear ? double.infinity : size,
          child: Align(
            alignment: linear ? Alignment.centerLeft : Alignment.center,
            child: Icon(Icons.hourglass_top,
                size: size,
                color: color ?? Theme.of(context).colorScheme.primary),
          ),
        ),
      ),
    );
  }
}
