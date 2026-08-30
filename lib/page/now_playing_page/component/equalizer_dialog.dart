import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

Future<void> showEqualizerDialog(BuildContext context) {
  return showAppDialog(
    context: context,
    builder: (context) => const EqualizerDialog(),
  );
}

class EqualizerDialog extends StatefulWidget {
  const EqualizerDialog({super.key, this.playbackService});

  /// The normal app uses its existing playback service. Injection keeps layout
  /// and interaction tests independent of native audio/device initialization.
  final PlaybackService? playbackService;

  @override
  State<EqualizerDialog> createState() => _EqualizerDialogState();
}

class _EqualizerDialogState extends State<EqualizerDialog> {
  late final playbackService =
      widget.playbackService ?? PlayService.instance.playbackService;

  static const customPresetName = "自定义";
  static const Map<String, List<double>> presets = {
    "平坦": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    "流行": [-1.6, 4.8, 7.2, 8.0, 5.6, 0, -2.4, -2.4, -1.6, -1.6],
    "摇滚": [8.0, 4.8, -5.6, -8.0, -3.2, 4.0, 8.8, 11.2, 11.2, 11.2],
    "古典": [0, 0, 0, 0, 0, 0, -7.2, -7.2, -7.2, -9.6],
    "爵士": [4.0, 3.0, 1.5, 2.0, -1.5, -1.5, 0, 1.5, 3.0, 3.5],
    "人声": [-2.5, -1.0, 1.5, 3.5, 4.0, 3.5, 2.5, 1.0, 0, -1.5],
    "低音增强": [9.0, 7.0, 5.5, 3.0, 1.0, 0, 0, 0, 0, 0],
    "高音增强": [0, 0, 0, 0, 0, 1.0, 3.0, 5.5, 7.0, 9.0],
  };

  late bool enabled = playbackService.eqEnabled.value;
  late List<double> gains = List.of(playbackService.eqGains);
  late String preset = _matchPreset(gains);

  static String _matchPreset(List<double> gains) {
    for (final entry in presets.entries) {
      if (entry.value.length == gains.length &&
          Iterable<int>.generate(gains.length).every(
            (index) => (gains[index] - entry.value[index]).abs() < 0.01,
          )) {
        return entry.key;
      }
    }
    return customPresetName;
  }

  static String _bandLabel(double center) {
    if (center < 1000) return center.round().toString();
    final value = center / 1000;
    return value == value.roundToDouble() ? "${value.round()}k" : "${value}k";
  }

  void _toggleEnabled(bool value) {
    final applied = playbackService.setEqEnabled(value);
    if (!applied) {
      showTextOnSnackBar("当前输出模式不支持均衡器");
    }
    setState(() => enabled = playbackService.eqEnabled.value);
  }

  void _applyPreset(String name) {
    final values = presets[name];
    if (values == null) return;
    playbackService.applyEqGains(values);
    setState(() {
      gains = List.of(playbackService.eqGains);
      preset = name;
    });
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      // Title and controls scroll together; the completion action stays above
      // any notification even in the smallest supported window at 200% text.
      scrollable: true,
      title: AppDialogTitle(
        ui("均衡器"),
        sideExtent: 64,
        trailing: Switch(value: enabled, onChanged: _toggleEnabled),
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownMenu<String>(
                    // DropdownMenu caches its text controller. Recreate only
                    // this display control when language changes, not the EQ.
                    key: ValueKey((preset, uiLanguage.value)),
                    label: Text(ui("预设")),
                    initialSelection: preset,
                    requestFocusOnTap: false,
                    expandedInsets: EdgeInsets.zero,
                    onSelected: (name) {
                      if (name != null && name != customPresetName) {
                        _applyPreset(name);
                      }
                    },
                    dropdownMenuEntries: [
                      for (final name in presets.keys)
                        DropdownMenuEntry(value: name, label: ui(name)),
                      DropdownMenuEntry(
                        value: customPresetName,
                        label: ui(customPresetName),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: ui("重置为平坦"),
                  // Preset lookup IDs remain stable in every UI language.
                  onPressed: () => _applyPreset("平坦"),
                  icon: const Icon(Symbols.restart_alt),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var band = 0;
                      band < BassPlayer.eqBandCenters.length;
                      band++)
                    _BandSlider(
                      label: _bandLabel(BassPlayer.eqBandCenters[band]),
                      value: gains[band],
                      enabled: enabled,
                      onChanged: (value) {
                        playbackService.setEqBandGain(band, value);
                        setState(() {
                          gains[band] = value;
                          preset = customPresetName;
                        });
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ui("调节范围 ±15 dB，换歌后继续保持。"),
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ui("完成")),
        ),
      ],
    );
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 48,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "${value >= 0 ? "+" : ""}${value.toStringAsFixed(0)}",
            style: TextStyle(
              fontSize: 12,
              color: enabled ? scheme.onSurface : scheme.outline,
            ),
          ),
          SizedBox(
            height: 160,
            child: RotatedBox(
              quarterTurns: 3,
              child: Slider(
                min: -BassPlayer.eqMaxGainDb,
                max: BassPlayer.eqMaxGainDb,
                value: value
                    .clamp(
                      -BassPlayer.eqMaxGainDb,
                      BassPlayer.eqMaxGainDb,
                    )
                    .toDouble(),
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: enabled ? scheme.onSurfaceVariant : scheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
