import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

Future<void> showSegmentLoopDialog(
        BuildContext context, PlaybackService service) =>
    showAppDialog<void>(
        context: context, builder: (_) => SegmentLoopDialog(service: service));

class SegmentLoopDialog extends StatelessWidget {
  const SegmentLoopDialog({super.key, required this.service});
  final PlaybackService service;

  static String _time(double? seconds) => seconds == null
      ? '--:--'
      : Duration(milliseconds: (seconds * 1000).round()).toStringHMMSS();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        service,
        service.segmentLoop,
        service.resolvingAudioPath,
        service.isChangingOutput
      ]),
      builder: (context, _) {
        final loop = service.segmentLoop;
        final available = service.canUseSegmentLoop;
        return AlertDialog(
          icon: const Icon(Symbols.repeat),
          title: Text(ui('A-B 片段循环')),
          content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(service.nowPlaying?.displayTitle ?? ui('尚未选择歌曲'),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 12),
                    Text(ui(available
                        ? '播放到需要的位置，分别标记 A 和 B；两点至少间隔 1 秒。'
                        : '请先加载一首本地歌曲，再设置片段循环。')),
                    const SizedBox(height: 16),
                    _SegmentPosition(
                        key: ValueKey(service.nowPlaying?.path),
                        service: service,
                        available: available),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton.icon(
                          key: const ValueKey('segment-loop-set-a'),
                          onPressed: available
                              ? () => loop.setStart(
                                  service.position, service.length)
                              : null,
                          icon: const Icon(Symbols.first_page),
                          label: Text(ui('标记 A：{0}', [_time(loop.start)]))),
                      OutlinedButton.icon(
                          key: const ValueKey('segment-loop-set-b'),
                          onPressed: available
                              ? () {
                                  if (!loop.setEnd(
                                      service.position, service.length)) {
                                    showTextOnSnackBar('B 点必须在 A 点至少 1 秒之后',
                                        context: context);
                                  }
                                }
                              : null,
                          icon: const Icon(Symbols.last_page),
                          label: Text(ui('标记 B：{0}', [_time(loop.end)]))),
                    ]),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(ui('循环播放此片段')),
                        value: loop.enabled,
                        onChanged: available && loop.hasRange
                            ? service.setSegmentLoopEnabled
                            : null),
                    Text(ui('切换歌曲会清除标记；手动跳到区间外会关闭循环。'),
                        style: Theme.of(context).textTheme.bodySmall),
                  ]))),
          actions: [
            TextButton(
                onPressed: loop.start != null ? loop.clear : null,
                child: Text(ui('清除标记'))),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(ui('完成'))),
          ],
        );
      },
    );
  }
}

class _SegmentPosition extends StatefulWidget {
  const _SegmentPosition(
      {super.key, required this.service, required this.available});
  final PlaybackService service;
  final bool available;

  @override
  State<_SegmentPosition> createState() => _SegmentPositionState();
}

class _SegmentPositionState extends State<_SegmentPosition> {
  double? _dragPosition;

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final maximum = widget.available ? service.length : 1.0;
    return StreamBuilder<double>(
      stream: service.positionStream,
      initialData: widget.available ? service.position : 0,
      builder: (context, snapshot) {
        final raw = _dragPosition ?? snapshot.data ?? 0;
        final value = raw.isFinite ? raw.clamp(0.0, maximum) : 0.0;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ui('当前位置：{0}', [SegmentLoopDialog._time(value)]),
                  style: Theme.of(context).textTheme.titleMedium),
              Slider(
                  key: const ValueKey('segment-loop-position'),
                  value: value,
                  max: maximum,
                  label: SegmentLoopDialog._time(value),
                  semanticFormatterCallback: SegmentLoopDialog._time,
                  onChanged: widget.available
                      ? (value) => setState(() => _dragPosition = value)
                      : null,
                  onChangeEnd: widget.available
                      ? (value) {
                          service.seek(value);
                          setState(() => _dragPosition = null);
                        }
                      : null),
            ]);
      },
    );
  }
}
