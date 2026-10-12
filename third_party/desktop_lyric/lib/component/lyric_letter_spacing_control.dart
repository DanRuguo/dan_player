import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

/// One finite pointer draft; commit shared glyph spacing only on release.
/// An optional isolated preview can display the draft without publishing it.
class LyricLetterSpacingControl extends StatefulWidget {
  const LyricLetterSpacingControl(
      {super.key,
      required this.value,
      required this.onChanged,
      this.id = 'lyric-letter-spacing',
      this.visible = true,
      this.hidden,
      this.primary,
      this.foreground,
      this.heading,
      this.previewBuilder,
      this.alignResetToEnd = false});
  final double value;
  final ValueChanged<double> onChanged;
  final String id;

  /// Input availability is independent of hidden visual-update preferences.
  /// Standalone desktop and lyric controls remain available by default.
  final bool visible;
  final ValueListenable<bool>? hidden;
  final Color? primary;
  final Color? foreground;

  /// Settings may supply their shared icon/title/subtitle header. The default
  /// desktop and lyric-popup label keeps its existing compact presentation.
  final Widget? heading;
  final bool alignResetToEnd;

  /// Builds only this control's local draft preview. Appearance and media
  /// consumers keep the committed value until the physical release.
  final Widget Function(BuildContext context, double value)? previewBuilder;
  @override
  State<LyricLetterSpacingControl> createState() =>
      _LyricLetterSpacingControlState();
}

class _LyricLetterSpacingControlState extends State<LyricLetterSpacingControl>
    with WidgetsBindingObserver {
  double? _draft;
  int? _pointer;
  bool _pointerCycle = false, _ignoreCycle = false, _cancelled = false;
  bool _tickerEnabled = true;
  bool get _active =>
      widget.visible &&
      _tickerEnabled &&
      !(widget.hidden?.value ?? false) &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.inactive);

  void _discard({bool releaseOwner = false}) {
    _cancelled = true;
    if (releaseOwner) _pointer = null;
    _pointerCycle = _ignoreCycle = false;
    _draft = null;
  }

  void _availabilityChanged() {
    if (!_active && mounted) setState(_discard);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.hidden?.addListener(_availabilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (!_active) _discard();
  }

  @override
  void didUpdateWidget(LyricLetterSpacingControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hidden, widget.hidden)) {
      oldWidget.hidden?.removeListener(_availabilityChanged);
      widget.hidden?.addListener(_availabilityChanged);
    }
    if (oldWidget.value != widget.value || !_active) _discard();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _availabilityChanged();
  @override
  void dispose() {
    _discard(releaseOwner: true);
    widget.hidden?.removeListener(_availabilityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final value = _draft ?? widget.value;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(
          crossAxisAlignment: widget.heading == null
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Expanded(
                child: widget.heading ??
                    Text(ui('歌词字间距'),
                        style: TextStyle(color: widget.foreground))),
            const SizedBox(width: 8),
            Text(value.toStringAsFixed(1),
                key: ValueKey('${widget.id}-value'),
                style: widget.heading == null
                    ? TextStyle(color: widget.foreground)
                    : Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: widget.foreground)),
          ]),
      if (widget.heading != null) const SizedBox(height: 10),
      if (widget.previewBuilder != null) ...[
        widget.previewBuilder!(context, value),
        const SizedBox(height: 8),
      ],
      Listener(
        onPointerDown: (event) {
          _pointer ??= event.pointer;
        },
        onPointerUp: (event) {
          if (_pointer == event.pointer) _pointer = null;
        },
        onPointerCancel: (event) {
          if (_pointer == event.pointer) {
            setState(() => _discard(releaseOwner: true));
          }
        },
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
              activeTrackColor: widget.primary ?? scheme.primary,
              thumbColor: widget.primary ?? scheme.primary,
              showValueIndicator: ShowValueIndicator.never),
          child: Slider(
            key: ValueKey('${widget.id}-slider'),
            value: value.clamp(0.0, 12.0),
            min: 0,
            max: 12,
            divisions: 24,
            semanticFormatterCallback: (value) => value.toStringAsFixed(1),
            onChangeStart: (_) {
              if (_pointerCycle) {
                _ignoreCycle = true;
                return;
              }
              _pointerCycle = _pointer != null;
              _cancelled = !_active;
            },
            onChanged: (value) {
              if (!_active || _cancelled || _ignoreCycle) return;
              setState(() => _draft = value);
            },
            onChangeEnd: (value) {
              if (_ignoreCycle) {
                _ignoreCycle = false;
                return;
              }
              // Arena cancellation and an early semantic cycle can end the
              // Slider interaction while the physical owner is still held.
              // Retire that draft without treating it as a pointer release.
              if (_pointer != null) {
                setState(() {
                  _pointerCycle = false;
                  _cancelled = true;
                  _draft = null;
                });
                return;
              }
              _pointerCycle = false;
              if (!_active || _cancelled) return;
              setState(() => _draft = null);
              widget.onChanged(value);
            },
          ),
        ),
      ),
      Align(
        alignment: widget.alignResetToEnd
            ? AlignmentDirectional.centerEnd
            : Alignment.center,
        child: TextButton(
            key: ValueKey('${widget.id}-reset'),
            style: widget.heading == null
                ? null
                : TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    visualDensity: VisualDensity.standard,
                    tapTargetSize: MaterialTapTargetSize.padded),
            onPressed: () {
              if (!_active) return;
              setState(_discard);
              widget.onChanged(0);
            },
            child: Text(ui('恢复默认字间距'),
                textAlign: widget.alignResetToEnd ? TextAlign.end : null)),
      ),
    ]);
  }
}
