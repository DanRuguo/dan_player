import 'dart:math' as math;
import 'package:dan_player/component/app_shape.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class DetailVolumeButton extends StatefulWidget {
  const DetailVolumeButton(
      {super.key,
      required this.readVolume,
      required this.onChanged,
      this.changes});
  final double Function() readVolume;
  final ValueChanged<double> onChanged;
  final Listenable? changes;

  @override
  State<DetailVolumeButton> createState() => _DetailVolumeButtonState();
}

class _DetailVolumeButtonState extends State<DetailVolumeButton> {
  late double _value = _read();
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
    if (mounted && value != _value) setState(() => _value = value);
  }

  @override
  void didUpdateWidget(covariant DetailVolumeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.changes != widget.changes) {
      oldWidget.changes?.removeListener(_sync);
      widget.changes?.addListener(_sync);
    }
    _value = _read();
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
    return MenuAnchor(
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
            onChanged: (value) {
              setState(() => _value = value);
              widget.onChanged(value);
            })
      ],
      builder: (context, controller, _) => IconButton(
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

class DetailVolumePanel extends StatelessWidget {
  const DetailVolumePanel(
      {super.key,
      required this.value,
      required this.onChanged,
      this.onChangeStart,
      this.onChangeEnd});
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final volume = value.clamp(0.0, 1.0);
    return SizedBox(
        width: math.min(280, MediaQuery.sizeOf(context).width - 48),
        child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Icon(
                    volume == 0
                        ? Icons.volume_off_outlined
                        : Icons.volume_up_outlined,
                    size: 20,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(ui('音量'), style: theme.textTheme.titleSmall)),
                const SizedBox(width: 8),
                Text('${(volume * 100).round()}%',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.primary)),
              ]),
              SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    showValueIndicator: ShowValueIndicator.never,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: Slider(
                      value: volume,
                      onChanged: onChanged,
                      semanticFormatterCallback: (value) =>
                          '${(value * 100).round()}%',
                      onChangeStart: onChangeStart,
                      onChangeEnd: onChangeEnd)),
            ])));
  }
}
