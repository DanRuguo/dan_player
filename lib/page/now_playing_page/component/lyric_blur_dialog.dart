import 'dart:async';

import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'lyric_view_controls.dart';

Future<void> showLyricBlurDialog(
    BuildContext context, LyricViewController controller) async {
  await showAppDialog<void>(
      context: context,
      builder: (_) => LyricBlurDialog(controller: controller));
  await _persistBlur(context, controller);
}

Future<void> _persistBlur(
    BuildContext context, LyricViewController controller) async {
  try {
    await controller.persistBlurPreferences();
  } catch (_) {
    if (context.mounted) {
      showAppNotice(ui('设置保存失败，请重试'),
          context: context, kind: AppNoticeKind.error);
    }
  }
}

class LyricBlurDialog extends StatelessWidget {
  const LyricBlurDialog({super.key, required this.controller});

  final LyricViewController controller;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          final enabled = controller.lyricBlurEnabled;
          final top = controller.lyricBlurTopFraction;
          final bottom = controller.lyricBlurBottomFraction;
          final colors = (
            top: scheme.primaryContainer,
            clear: scheme.surfaceContainerHighest,
            bottom: scheme.tertiaryContainer,
          );
          return AlertDialog(
            key: const ValueKey('lyric-blur-dialog'),
            scrollable: true,
            icon: Icon(Symbols.blur_on, color: scheme.primary),
            title: AppDialogTitle(ui('调整模糊')),
            content: SizedBox(
                width: 420,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        key: const ValueKey('lyric-blur-enabled'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(ui('启用歌词模糊')),
                        value: enabled,
                        onChanged: (value) {
                          controller.setLyricBlurEnabled(value);
                          unawaited(_persistBlur(context, controller));
                        },
                      ),
                      const SizedBox(height: 12),
                      _BlurRangeSlider(
                        id: 'top',
                        label: ui('上方模糊范围'),
                        value: top,
                        enabled: enabled,
                        onChanged: (value) => controller.setLyricBlurRanges(
                            value, controller.lyricBlurBottomFraction),
                        onChangeEnd: (_) =>
                            unawaited(_persistBlur(context, controller)),
                      ),
                      const SizedBox(height: 12),
                      _BlurRangeSlider(
                        id: 'bottom',
                        label: ui('下方模糊范围'),
                        value: bottom,
                        enabled: enabled,
                        onChanged: (value) => controller.setLyricBlurRanges(
                            controller.lyricBlurTopFraction, value),
                        onChangeEnd: (_) =>
                            unawaited(_persistBlur(context, controller)),
                      ),
                      const SizedBox(height: 16),
                      Text(ui('拖动滑块调整上方和下方的模糊范围。'),
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 12),
                      Semantics(
                        label: '${ui('模糊区域预览')}，'
                            '${ui('上方模糊范围')} ${enabled ? _percent(top) : '0%'}，'
                            '${ui('清晰区域')} ${_percent(enabled ? 1 - top - bottom : 1)}，'
                            '${ui('下方模糊范围')} ${enabled ? _percent(bottom) : '0%'}',
                        image: true,
                        child: ExcludeSemantics(
                          child: Container(
                            key: const ValueKey('lyric-blur-preview'),
                            height: 220,
                            clipBehavior: Clip.antiAlias,
                            decoration: const BoxDecoration(
                                borderRadius: AppShape.controlRadius),
                            foregroundDecoration: BoxDecoration(
                                borderRadius: AppShape.controlRadius,
                                border:
                                    Border.all(color: scheme.outlineVariant)),
                            child: Stack(fit: StackFit.expand, children: [
                              ColoredBox(color: colors.clear),
                              Align(
                                alignment: Alignment.topCenter,
                                child: FractionallySizedBox(
                                  key: const ValueKey('lyric-blur-preview-top'),
                                  widthFactor: 1,
                                  heightFactor: enabled ? top : 0,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [colors.top, colors.clear],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  key: const ValueKey(
                                      'lyric-blur-preview-bottom'),
                                  widthFactor: 1,
                                  heightFactor: enabled ? bottom : 0,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [colors.clear, colors.bottom],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(spacing: 16, runSpacing: 8, children: [
                        _BlurRegionLegend(
                            color: colors.top, label: ui('上方模糊区域')),
                        _BlurRegionLegend(
                            color: colors.clear, label: ui('清晰区域')),
                        _BlurRegionLegend(
                            color: colors.bottom, label: ui('下方模糊区域')),
                      ]),
                    ])),
            actions: [
              AppDialogActions(children: [
                TextButton(
                    key: const ValueKey('lyric-blur-close'),
                    onPressed: () => Navigator.pop(context),
                    child: Text(ui('关闭'))),
              ]),
            ],
          );
        });
  }
}

String _percent(double value) => '${(value * 100).round()}%';

class _BlurRangeSlider extends StatelessWidget {
  const _BlurRangeSlider({
    required this.id,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String id;
  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
        const SizedBox(width: 8),
        Text(_percent(value),
            key: ValueKey('lyric-blur-$id-value'),
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.primary, fontSize: 18)),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          showValueIndicator: ShowValueIndicator.never,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        child: Slider(
          key: ValueKey('lyric-blur-$id-slider'),
          value: value,
          min: 0,
          max: .45,
          divisions: 45,
          allowedInteraction: SliderInteraction.tapAndSlide,
          semanticFormatterCallback: _percent,
          onChanged: enabled ? onChanged : null,
          onChangeEnd: enabled ? onChangeEnd : null,
        ),
      ),
      const Row(children: [Text('0%'), Spacer(), Text('45%')]),
    ]);
  }
}

class _BlurRegionLegend extends StatelessWidget {
  const _BlurRegionLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                color: color,
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: AppShape.smallRadius)),
        const SizedBox(width: 6),
        Flexible(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
      ]);
}
