import 'package:dan_player/component/eq_presets_dialog.dart';
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

  late final _originalGains = List<double>.of(playbackService.eqGains);
  late final _originalEnabled = playbackService.eqEnabled.value;
  late int _ownedRevision;
  bool _comparingOriginal = false;
  List<double>? _adjusted;
  bool? _adjustedEnabled;
  @override
  void initState() {
    super.initState();
    _originalGains;
    _originalEnabled;
    _ownedRevision = playbackService.eqEditRevision;
  }

  bool _ownsEq() {
    if (_ownedRevision == playbackService.eqEditRevision) return true;
    showTextOnSnackBar('EQ 或输出已由其他入口更改，请重新打开对比');
    return false;
  }

  void _compare() {
    if (!_ownsEq()) return;
    if (!_comparingOriginal) {
      _adjusted = List.of(playbackService.eqGains);
      _adjustedEnabled = playbackService.eqEnabled.value;
    }
    playbackService
        .applyEqGains(_comparingOriginal ? _adjusted! : _originalGains);
    playbackService.setEqEnabled(
        _comparingOriginal ? _adjustedEnabled! : _originalEnabled);
    _ownedRevision = playbackService.eqEditRevision;
    setState(() => _comparingOriginal = !_comparingOriginal);
  }

  void _finishComparison(bool original) {
    if (!_ownsEq()) return;
    playbackService
        .applyEqGains(original ? _originalGains : (_adjusted ?? gains));
    playbackService.setEqEnabled(
        original ? _originalEnabled : (_adjustedEnabled ?? enabled));
    _ownedRevision = playbackService.eqEditRevision;
    setState(() {
      _comparingOriginal = false;
      _adjusted = null;
      gains = List.of(playbackService.eqGains);
      enabled = playbackService.eqEnabled.value;
    });
  }

  @override
  void dispose() {
    if (_comparingOriginal &&
        _ownedRevision == playbackService.eqEditRevision &&
        _adjusted != null) {
      playbackService.applyEqGains(_adjusted!);
      playbackService.setEqEnabled(_adjustedEnabled!);
    }
    super.dispose();
  }

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
    if (!_ownsEq()) return;
    final applied = playbackService.setEqEnabled(value);
    _ownedRevision = playbackService.eqEditRevision;
    if (!applied) {
      showTextOnSnackBar("当前输出模式不支持均衡器");
    }
    setState(() => enabled = playbackService.eqEnabled.value);
  }

  void _applyPreset(String name) {
    final values = presets[name];
    if (values == null) return;
    if (!_ownsEq()) return;
    playbackService.applyEqGains(values);
    _ownedRevision = playbackService.eqEditRevision;
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
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(
                  onPressed: () async {
                    await showEqPresets(context, playbackService);
                    if (mounted)
                      setState(() {
                        _ownedRevision = playbackService.eqEditRevision;
                        _adjusted = null;
                        _comparingOriginal = false;
                        gains = List.of(playbackService.eqGains);
                        enabled = playbackService.eqEnabled.value;
                        preset = _matchPreset(gains);
                      });
                  },
                  child: Text(ui('用户预设'))),
              OutlinedButton(
                  onPressed: _compare,
                  child: Text(ui(_comparingOriginal ? '试听当前调节 B' : '试听原设置 A'))),
              if (_adjusted != null) ...[
                TextButton(
                    onPressed: () => _finishComparison(false),
                    child: Text(ui('保留当前'))),
                TextButton(
                    onPressed: () => _finishComparison(true),
                    child: Text(ui('恢复原设置')))
              ],
            ]),
            const SizedBox(height: 12),
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
                        if (!_ownsEq()) return;
                        playbackService.setEqBandGain(band, value);
                        _ownedRevision = playbackService.eqEditRevision;
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
