import 'dart:math' as math;
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/player_number_dialog.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class DetailVolumeButton extends StatefulWidget {
  const DetailVolumeButton(
      {super.key,
      required this.readVolume,
      required this.onChanged,
      this.changes,
      this.compact = false});
  final double Function() readVolume;
  final ValueChanged<double> onChanged;
  final Listenable? changes;
  final bool compact;

  @override
  State<DetailVolumeButton> createState() => _DetailVolumeButtonState();
}

class _DetailVolumeButtonState extends State<DetailVolumeButton> {
  late double _value = _read();
  late double _lastAudible = _value > 0 ? _value : .5;
  double _read() {
    final value = widget.readVolume();
    return value.isFinite ? value.clamp(0, 1) : 0;
  }

  @override
  void initState() {
    super.initState();
    widget.changes?.addListener(_sync);
  }

  void _sync() {
    final value = _read();
    if (value > 0) _lastAudible = value;
    if (mounted && value != _value) setState(() => _value = value);
  }

  void _change(double value) {
    setState(() {
      if (_value > 0) _lastAudible = _value;
      _value = value;
      if (value > 0) _lastAudible = value;
    });
    widget.onChanged(value);
  }

  @override
  void didUpdateWidget(covariant DetailVolumeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.changes != widget.changes) {
      oldWidget.changes?.removeListener(_sync);
      widget.changes?.addListener(_sync);
    }
    _value = _read();
    if (_value > 0) _lastAudible = _value;
  }

  @override
  void dispose() {
    widget.changes?.removeListener(_sync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return AppMenuAnchor(
      consumeOutsideTap: true,
      style: MenuStyle(
        shape: const WidgetStatePropertyAll(AppShape.surface),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      menuChildren: [
        DetailVolumePanel(
            value: _value,
            onToggleMute: () => _change(_value > 0 ? 0 : _lastAudible),
            onChanged: _change)
      ],
      builder: (context, controller, _) => IconButton(
        style: widget.compact
            ? IconButton.styleFrom(
                minimumSize: const Size.square(44),
                fixedSize: const Size.square(44),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.standard,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )
            : null,
        tooltip: ui('音量'),
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            _sync();
            controller.open();
          }
        },
        icon: Icon(_value == 0 ? Symbols.volume_off : Symbols.volume_up),
        color: scheme.primary,
      ),
    );
  }
}

class DetailVolumePanel extends StatefulWidget {
  const DetailVolumePanel(
      {super.key,
      required this.value,
      required this.onChanged,
      this.onToggleMute,
      this.onChangeStart,
      this.onChangeEnd});
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback? onToggleMute;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  @override
  State<DetailVolumePanel> createState() => _DetailVolumePanelState();
}

class _DetailVolumePanelState extends State<DetailVolumePanel> {
  late double _lastAudible = widget.value > 0 ? widget.value : .5;
  double get _volume =>
      widget.value.isFinite ? widget.value.clamp(0.0, 1.0) : 0;

  @override
  void didUpdateWidget(covariant DetailVolumePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_volume > 0) _lastAudible = _volume;
  }

  void _apply(double value) {
    widget.onChangeStart?.call(_volume);
    widget.onChanged(value);
    widget.onChangeEnd?.call(value);
  }

  void _mute() {
    if (widget.onToggleMute != null) {
      widget.onToggleMute!();
      return;
    }
    if (_volume > 0) _lastAudible = _volume;
    _apply(_volume > 0 ? 0 : _lastAudible);
  }

  Future<void> _exact() async {
    final result = await showAppDialog<int>(
        context: context,
        builder: (_) => PlayerNumberDialog(
            title: ui('精确音量'),
            label: ui('音量百分比'),
            value: (_volume * 100).round(),
            minimum: 0,
            maximum: 100));
    if (mounted && result != null) _apply(result / 100);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final volume = _volume;
    final width =
        math.max(120.0, math.min(280.0, MediaQuery.sizeOf(context).width - 48));
    final presetMinimum = math.max(
        42.0,
        MediaQuery.textScalerOf(context)
                    .scale(theme.textTheme.labelLarge?.fontSize ?? 14) *
                2.1 +
            20);
    final columns = width - 32 >= presetMinimum * 4 + 18 ? 4 : 2;
    final presetWidth = (width - 32 - (columns - 1) * 6) / columns;
    return SizedBox(
        width: width,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                IconButton(
                    key: const ValueKey('volume-toggle-mute'),
                    tooltip: ui(volume == 0 ? '恢复音量' : '静音'),
                    onPressed: _mute,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                        volume == 0
                            ? Icons.volume_off_outlined
                            : Icons.volume_up_outlined,
                        size: 20,
                        color: theme.colorScheme.primary)),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(ui('音量'), style: theme.textTheme.titleSmall)),
                const SizedBox(width: 8),
                Tooltip(
                    message: ui('精确音量'),
                    child: TextButton(
                        key: const ValueKey('volume-exact'),
                        onPressed: _exact,
                        child: Text('${(volume * 100).round()}%',
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: theme.colorScheme.primary)))),
              ]),
              SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    showValueIndicator: ShowValueIndicator.never,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: Slider(
                      value: volume,
                      onChanged: widget.onChanged,
                      semanticFormatterCallback: (value) =>
                          '${(value * 100).round()}%',
                      onChangeStart: widget.onChangeStart,
                      onChangeEnd: widget.onChangeEnd)),
              const SizedBox(height: 12),
              Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final percent in [25, 50, 75, 100])
                      SizedBox(
                          width: presetWidth,
                          child: Tooltip(
                              message: ui('音量设为 {0}%', [percent]),
                              child: OutlinedButton(
                                key: ValueKey('volume-preset-$percent'),
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(42, 36),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    backgroundColor:
                                        (volume * 100 - percent).abs() < .001
                                            ? theme.colorScheme.primaryContainer
                                            : null,
                                    foregroundColor:
                                        (volume * 100 - percent).abs() < .001
                                            ? theme
                                                .colorScheme.onPrimaryContainer
                                            : null),
                                onPressed: () => _apply(percent / 100),
                                child: Text('$percent'),
                              )))
                  ]),
            ])));
  }
}
