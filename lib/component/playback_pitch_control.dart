import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/play_service/playback_pitch.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

String playbackPitchLabel(double pitch) =>
    pitch == 0 ? ui('原调') : ui('{0} 半音', [PlaybackPitch.label(pitch)]);

List<Widget> playbackPitchMenuItems({
  required BuildContext context,
  required double pitch,
  required ValueChanged<double> onSelected,
}) {
  Widget label(String text) => ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth:
              (MediaQuery.sizeOf(context).width - 128).clamp(80.0, 360.0)),
      child: Text(text));
  return [
    MenuItemButton(
      key: const ValueKey('playback-pitch-step-down'),
      onPressed: pitch > PlaybackPitch.min
          ? () => onSelected(
              (pitch - 1).clamp(PlaybackPitch.min, PlaybackPitch.max))
          : null,
      leadingIcon: const Icon(Icons.remove),
      child: label(ui('降低一个半音')),
    ),
    MenuItemButton(
      key: const ValueKey('playback-pitch-step-up'),
      onPressed: pitch < PlaybackPitch.max
          ? () => onSelected(
              (pitch + 1).clamp(PlaybackPitch.min, PlaybackPitch.max))
          : null,
      leadingIcon: const Icon(Icons.add),
      child: label(ui('升高一个半音')),
    ),
    const Divider(),
    for (final value in PlaybackPitch.presets)
      MenuItemButton(
        key: ValueKey(('playback-pitch', value)),
        onPressed: () => onSelected(value),
        leadingIcon: SizedBox.square(
          dimension: 20,
          child: (value - pitch).abs() < .001
              ? const Icon(Icons.check, size: 20)
              : null,
        ),
        child: Semantics(
          selected: (value - pitch).abs() < .001,
          child: label(playbackPitchLabel(value)),
        ),
      ),
  ];
}

/// A shared selection menu and one-semitone steps, using the current theme.
/// This presentation does not initialize an audio device or start a ticker.
class PlaybackPitchControl extends StatelessWidget {
  const PlaybackPitchControl({
    super.key,
    required this.pitch,
    required this.onChanged,
    this.enabled = true,
  });

  final double pitch;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton.outlined(
          key: const ValueKey('playback-pitch-down'),
          tooltip: ui('降低一个半音'),
          style: appToolbarControlStyle(context),
          onPressed: enabled && pitch > PlaybackPitch.min
              ? () => onChanged(
                  (pitch - 1).clamp(PlaybackPitch.min, PlaybackPitch.max))
              : null,
          icon: const Icon(Icons.remove),
        ),
        AppMenuAnchor(
          style:
              const MenuStyle(shape: WidgetStatePropertyAll(AppShape.control)),
          menuChildren: playbackPitchMenuItems(
              context: context, pitch: pitch, onSelected: onChanged),
          builder: (context, controller, _) => OutlinedButton.icon(
            key: const ValueKey('playback-pitch-menu'),
            style: appToolbarControlStyle(context),
            onPressed: enabled
                ? () =>
                    controller.isOpen ? controller.close() : controller.open()
                : null,
            icon: const Icon(Icons.music_note_outlined),
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(playbackPitchLabel(pitch))),
              const SizedBox(width: 8),
              const Icon(Icons.expand_more, size: 20),
            ]),
          ),
        ),
        IconButton.outlined(
          key: const ValueKey('playback-pitch-up'),
          tooltip: ui('升高一个半音'),
          style: appToolbarControlStyle(context),
          onPressed: enabled && pitch < PlaybackPitch.max
              ? () => onChanged(
                  (pitch + 1).clamp(PlaybackPitch.min, PlaybackPitch.max))
              : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
