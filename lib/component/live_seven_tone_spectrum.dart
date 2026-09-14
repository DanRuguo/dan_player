import 'dart:async';

import 'package:dan_player/component/seven_tone_spectrum.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Owns FFT demand only while the compact spectrum can actually be seen.
/// Nonopaque menus/dialogs keep it alive; native hide and offstage page/mini
/// transitions release demand without replacing the playback service.
class LiveSevenToneSpectrum extends StatefulWidget {
  const LiveSevenToneSpectrum({
    super.key,
    required this.samples,
    required this.readLevels,
    required this.isPlaying,
    required this.color,
    this.hidden,
  });

  final Stream<List<double>> samples;
  final List<double> Function() readLevels;
  final bool isPlaying;
  final Color color;
  final ValueListenable<bool>? hidden;

  @override
  State<LiveSevenToneSpectrum> createState() => _LiveSevenToneSpectrumState();
}

class _LiveSevenToneSpectrumState extends State<LiveSevenToneSpectrum>
    with WidgetsBindingObserver {
  static const _silence = <double>[0, 0, 0, 0, 0, 0, 0];
  final _levels = ValueNotifier<List<double>>(_silence);
  StreamSubscription<List<double>>? _subscription;
  Stream<List<double>>? _listeningTo;
  ValueListenable<RenderingPreferences>? _preferences;
  AppLifecycleState? _lifecycle;
  bool _treeVisible = false;
  bool _mediaAllowsMotion = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    widget.hidden?.addListener(_syncActivity);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final preferences = RenderingPreferencesScope.listenableOf(context);
    if (!identical(preferences, _preferences)) {
      _preferences?.removeListener(_syncActivity);
      _preferences = preferences..addListener(_syncActivity);
    }
    _treeVisible = TickerMode.valuesOf(context).enabled;
    _mediaAllowsMotion =
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    _syncActivity();
  }

  @override
  void didUpdateWidget(LiveSevenToneSpectrum oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hidden, widget.hidden)) {
      oldWidget.hidden?.removeListener(_syncActivity);
      widget.hidden?.addListener(_syncActivity);
    }
    _syncActivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _syncActivity();
  }

  @override
  void didChangeAccessibilityFeatures() => _syncActivity();

  void _setLevels(List<double> values) {
    double safe(int index) {
      final value = index < values.length ? values[index] : 0.0;
      return value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    }

    var changed = false;
    var nonzero = false;
    for (var i = 0; i < 7; i++) {
      final value = safe(i);
      changed = changed || _levels.value[i] != value;
      nonzero = nonzero || value != 0;
    }
    if (!changed) return;
    _levels.value =
        nonzero ? List<double>.unmodifiable(List.generate(7, safe)) : _silence;
  }

  void _detach() {
    _generation++;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _listeningTo = null;
  }

  void _syncActivity() {
    if (!mounted) return;
    final preferences = _preferences?.value ?? const RenderingPreferences();
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final enabled = widget.isPlaying &&
        preferences.compactSpectrum &&
        _mediaAllowsMotion &&
        !features.disableAnimations &&
        !features.reduceMotion &&
        preferences.allowsVisualUpdates(
          lifecycle: _lifecycle,
          treeVisible: _treeVisible,
          nativeHidden: widget.hidden?.value ?? false,
        );
    if (!enabled) {
      if (_listeningTo != null) _detach();
      _setLevels(_silence);
      return;
    }
    if (identical(_listeningTo, widget.samples)) return;
    _detach();
    _listeningTo = widget.samples;
    final generation = _generation;
    try {
      _setLevels(widget.readLevels());
    } catch (_) {
      _setLevels(_silence);
    }
    _subscription = widget.samples.listen((values) {
      if (mounted && generation == _generation) _setLevels(values);
    }, onError: (Object _, StackTrace __) {
      if (mounted && generation == _generation) _setLevels(_silence);
    }, onDone: () {
      if (mounted && generation == _generation) _setLevels(_silence);
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<double>>(
        valueListenable: _levels,
        builder: (_, levels, __) =>
            SevenToneSpectrum(levels: levels, color: widget.color),
      );

  @override
  void dispose() {
    _detach();
    widget.hidden?.removeListener(_syncActivity);
    _preferences?.removeListener(_syncActivity);
    WidgetsBinding.instance.removeObserver(this);
    _levels.dispose();
    super.dispose();
  }
}
