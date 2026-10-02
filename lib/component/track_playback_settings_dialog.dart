import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_pitch.dart';
import 'package:dan_player/play_service/playback_rate.dart';
import 'package:dan_player/play_service/track_playback_settings.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

Future<void> showTrackPlaybackSettings(BuildContext context, Audio audio) {
  final playback = PlayService.playbackReady.value
      ? PlayService.instance.playbackService
      : null;
  var captured = playback?.captureTrackPlaybackSettings();
  final defaults = AppSettings.instance.experience.value;
  return showAppDialog<void>(
      context: context,
      builder: (_) => TrackPlaybackSettingsDialog(
          audio: audio,
          defaults: TrackPlaybackSettings(
              rate: defaults.playbackRate, pitch: defaults.playbackPitch),
          effective: captured?.track == audio.stableTrackId
              ? TrackPlaybackSettings(
                  rate: playback!.playbackRate.value,
                  pitch: playback.playbackPitch.value)
              : null,
          onSaved: playback == null || captured == null
              ? null
              : (settings) async {
                  final applied = playback.applySavedTrackPlaybackSettings(
                      audio.stableTrackId, settings, captured!);
                  // A second explicit save/clear may follow our own successful
                  // apply, but never an intervening external command/session.
                  if (applied) {
                    captured = playback.captureTrackPlaybackSettings();
                  }
                  return applied;
                }));
}

/// The dialog owns a draft for the captured song; no preview alters defaults.
class TrackPlaybackSettingsDialog extends StatefulWidget {
  const TrackPlaybackSettingsDialog(
      {super.key,
      required this.audio,
      required this.defaults,
      this.effective,
      this.store,
      this.onSaved});
  final Audio audio;
  final TrackPlaybackSettings defaults;
  final TrackPlaybackSettings? effective;
  final PersonalLibrary? store;
  final Future<bool> Function(TrackPlaybackSettings?)? onSaved;
  @override
  State<TrackPlaybackSettingsDialog> createState() =>
      _TrackPlaybackSettingsDialogState();
}

class _TrackPlaybackSettingsDialogState
    extends State<TrackPlaybackSettingsDialog> {
  late double _rate = widget.effective?.rate ?? widget.defaults.rate;
  late double _pitch = widget.effective?.pitch ?? widget.defaults.pitch;
  PersonalLibrary? _store;
  TrackPlaybackSettings? _saved;
  bool _loaded = false, _saving = false;
  String? _message, _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final store = widget.store ?? await PersonalLibrary.instance;
      final saved = await store.playbackFor(widget.audio.stableTrackId);
      if (!mounted) return;
      setState(() {
        _store = store;
        _saved = saved;
        _loaded = true;
        if (saved != null) {
          _rate = saved.rate;
          _pitch = saved.pitch;
        }
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = ui('读取本曲设置失败：{0}', [error]));
    }
  }

  Future<void> _save({bool clear = false}) async {
    if (!_loaded || _saving) return;
    final settings =
        clear ? null : TrackPlaybackSettings(rate: _rate, pitch: _pitch);
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    var persisted = false;
    try {
      await _store!.setPlayback(widget.audio, settings);
      persisted = true;
      if (!mounted) return;
      setState(() => _saved = settings);
      final applied = await widget.onSaved?.call(settings) ?? false;
      if (!mounted) return;
      setState(() {
        if (clear) {
          _rate = widget.defaults.rate;
          _pitch = widget.defaults.pitch;
        }
        _message = ui(clear
            ? (applied ? '已清除本曲设置，当前播放已恢复全局默认' : '已清除本曲设置，下次播放使用全局默认')
            : (applied ? '已记住本曲设置，当前播放已应用' : '已记住本曲设置，下次播放时生效'));
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            ui(persisted ? '设置已保存，但当前应用失败：{0}' : '保存本曲设置失败：{0}', [error]));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _choice(
          String label,
          double value,
          List<double> presets,
          String Function(double) format,
          ValueChanged<double> change,
          String key) =>
      Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ui(label), style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 6),
            AppMenuAnchor(
                style: const MenuStyle(
                    shape: WidgetStatePropertyAll(AppShape.control)),
                menuChildren: [
                  for (final v in {...presets, value}.toList()..sort())
                    MenuItemButton(
                        key: ValueKey('$key-option-$v'),
                        onPressed: _loaded && !_saving
                            ? () {
                                if (!mounted || _saving) return;
                                setState(() {
                                  change(v);
                                  _message = null;
                                });
                              }
                            : null,
                        leadingIcon: SizedBox.square(
                            dimension: 20,
                            child: v == value
                                ? const Icon(Icons.check, size: 20)
                                : null),
                        child: Semantics(
                            selected: v == value, child: Text(format(v))))
                ],
                builder: (context, controller, _) => OutlinedButton(
                    key: ValueKey(key),
                    style: appToolbarControlStyle(context),
                    onPressed: _loaded && !_saving
                        ? () => controller.isOpen
                            ? controller.close()
                            : controller.open()
                        : null,
                    child: AppToolbarLabel(
                        label: format(value),
                        semanticsLabel: '${ui(label)}: ${format(value)}',
                        icon: key == 'track-rate'
                            ? Symbols.speed
                            : Symbols.music_note,
                        trailing: const Icon(Icons.expand_more, size: 18))))
          ]);

  double _choiceWidth(BuildContext context, String title, String value) {
    double measure(String text, TextStyle? style) {
      final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1)
        ..layout();
      final width = painter.width.ceilToDouble();
      painter.dispose();
      return width;
    }

    final theme = Theme.of(context).textTheme;
    final label = measure(ui(title), theme.bodyMedium);
    final control = measure(value, theme.labelLarge) +
        appToolbarPadding.horizontal +
        appToolbarIconSize +
        appToolbarLabelGap +
        appToolbarTrailingGap +
        18;
    return label > control ? label : control;
  }

  Widget _parameters(BuildContext context, double width) {
    final rate = _choice('本曲播放速度', _rate, PlaybackRate.presets,
        PlaybackRate.label, (v) => _rate = v, 'track-rate');
    final pitch = _choice('本曲音调（半音）', _pitch, PlaybackPitch.presets,
        PlaybackPitch.label, (v) => _pitch = v, 'track-pitch');
    // Equal columns must fit the wider title and its real scaled label.
    // A window-width breakpoint alone truncates translated large text.
    final rateWidth =
        _choiceWidth(context, '本曲播放速度', PlaybackRate.label(_rate));
    final pitchWidth =
        _choiceWidth(context, '本曲音调（半音）', PlaybackPitch.label(_pitch));
    final columnWidth = rateWidth > pitchWidth ? rateWidth : pitchWidth;
    if (columnWidth * 2 + 16 <= width) {
      return Row(
          key: const ValueKey('track-parameters-columns'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: rate),
            const SizedBox(width: 16),
            Expanded(child: pitch),
          ]);
    }
    return Column(
        key: const ValueKey('track-parameters-rows'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [rate, const SizedBox(height: 12), pitch]);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return LayoutBuilder(builder: (context, constraints) {
      final insets = DialogTheme.of(context).insetPadding ??
          const EdgeInsets.symmetric(horizontal: 40, vertical: 24);
      // AlertDialog asks its content for intrinsic sizes. Measure the actual
      // available width above that boundary, never run a LayoutBuilder below it.
      final width = (constraints.maxWidth -
              insets.horizontal -
              MediaQuery.viewInsetsOf(context).horizontal -
              48)
          .clamp(0.0, 420.0);
      return _dialog(context, width);
    });
  }

  Widget _dialog(BuildContext context, double width) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
        key: const ValueKey('track-playback-dialog'),
        scrollable: true,
        title: AppDialogTitle(ui('本曲设置')),
        content: AppDialogResize(
            child: SizedBox(
                width: width,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(widget.audio.displayTitle,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Text(ui('只记住这首歌的速度与音调，不改变全局默认，也不修改音乐文件。')),
                      const SizedBox(height: 12),
                      Text(
                          ui('全局默认：{0} · {1} 半音', [
                            PlaybackRate.label(widget.defaults.rate),
                            PlaybackPitch.label(widget.defaults.pitch)
                          ]),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant)),
                      if (widget.effective != null)
                        Text(
                            ui('打开时的实际播放：{0} · {1} 半音', [
                              PlaybackRate.label(widget.effective!.rate),
                              PlaybackPitch.label(widget.effective!.pitch)
                            ]),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant)),
                      const SizedBox(height: 16),
                      _parameters(context, width),
                      const SizedBox(height: 12),
                      Text(ui('再次播放自动使用已记住的值；手动调整全局参数仍会立即生效。')),
                      if (!_loaded && _error == null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: appToolbarReduceMotion(context)
                                ? Semantics(
                                    label: ui('正在读取本曲设置'),
                                    liveRegion: true,
                                    child: SizedBox(
                                        key: const ValueKey(
                                            'track-settings-loading-static'),
                                        height: 4,
                                        width: double.infinity,
                                        child: DecoratedBox(
                                            decoration: BoxDecoration(
                                                color: colors
                                                    .surfaceContainerHighest,
                                                borderRadius:
                                                    AppShape.smallRadius))))
                                : LinearProgressIndicator(
                                    semanticsLabel: ui('正在读取本曲设置'))),
                      if (_message != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Semantics(
                                liveRegion: true, child: Text(_message!))),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Semantics(
                                liveRegion: true,
                                child: Text(_error!,
                                    style: TextStyle(color: colors.error)))),
                    ]))),
        actions: [
          TextButton(
              key: const ValueKey('track-settings-clear'),
              onPressed: _loaded && !_saving && _saved != null
                  ? () => _save(clear: true)
                  : null,
              child: Text(ui('清除本曲设置'))),
          if (!_loaded && _error != null)
            TextButton(onPressed: _load, child: Text(ui('重试'))),
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: Text(ui('关闭'))),
          FilledButton(
              key: const ValueKey('track-settings-save'),
              onPressed: _loaded && !_saving ? _save : null,
              child: Text(ui('记住本曲设置')))
        ]);
  }
}
