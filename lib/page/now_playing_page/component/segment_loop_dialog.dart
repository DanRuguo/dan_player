import 'package:dan_player/component/app_toolbar_style.dart';
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

class SegmentLoopDialog extends StatefulWidget {
  const SegmentLoopDialog({super.key, required this.service});
  final PlaybackService service;
  @override
  State<SegmentLoopDialog> createState() => _SegmentLoopDialogState();
}

class _SegmentLoopDialogState extends State<SegmentLoopDialog> {
  PlaybackService get service => widget.service;
  bool _roundsValid = true, _intervalValid = true;

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
          icon: Icon(Symbols.repeat,
              color: Theme.of(context).colorScheme.primary),
          title: Text(ui('A-B 片段循环'), textAlign: TextAlign.center),
          content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    _SegmentControlPair(children: [
                      OutlinedButton.icon(
                          key: const ValueKey('segment-loop-set-a'),
                          style: appToolbarControlStyle(context),
                          onPressed: available
                              ? () => loop.setStart(
                                  service.position, service.length)
                              : null,
                          icon: const Icon(Symbols.first_page),
                          label: Text(ui('标记 A：{0}', [_time(loop.start)]))),
                      OutlinedButton.icon(
                          key: const ValueKey('segment-loop-set-b'),
                          style: appToolbarControlStyle(context),
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
                    const SizedBox(height: 20),
                    _SegmentControlPair(children: [
                      _PracticeField(
                          label: ui('总次数（留空无限）'),
                          child: TextFormField(
                              initialValue: loop.totalRounds?.toString() ?? '',
                              decoration: const InputDecoration(),
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              validator: (v) => v == null ||
                                      v.isEmpty ||
                                      ((int.tryParse(v) ?? 0) >= 2 &&
                                          (int.tryParse(v) ?? 1000) <= 999)
                                  ? null
                                  : ui('请输入 2–999'),
                              keyboardType: TextInputType.number,
                              onChanged: (v) {
                                final n = int.tryParse(v);
                                setState(() => _roundsValid = v.isEmpty ||
                                    (n != null && n >= 2 && n <= 999));
                                if (!_roundsValid) loop.setEnabled(false);
                                if (v.isEmpty ||
                                    (n != null && n >= 2 && n <= 999))
                                  loop.configurePractice(
                                      rounds: n,
                                      interval: loop.intervalSeconds);
                              })),
                      _PracticeField(
                          label: ui('轮间间隔（0–10 秒）'),
                          child: TextFormField(
                              initialValue: loop.intervalSeconds.toString(),
                              decoration: const InputDecoration(),
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              validator: (v) {
                                final n = double.tryParse(v ?? '');
                                return n != null &&
                                        n.isFinite &&
                                        n >= 0 &&
                                        n <= 10
                                    ? null
                                    : ui('请输入 0–10 秒');
                              },
                              keyboardType: TextInputType.number,
                              onChanged: (v) {
                                final n = double.tryParse(v);
                                setState(() => _intervalValid = n != null &&
                                    n.isFinite &&
                                    n >= 0 &&
                                    n <= 10);
                                if (!_intervalValid) loop.setEnabled(false);
                                if (n != null &&
                                    n.isFinite &&
                                    n >= 0 &&
                                    n <= 10)
                                  loop.configurePractice(
                                      rounds: loop.totalRounds, interval: n);
                              })),
                    ]),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(ui('循环播放此片段')),
                        subtitle: Text(ui('已完成 {0} 轮', [loop.completedRounds])),
                        value: loop.enabled,
                        onChanged: available &&
                                loop.hasRange &&
                                _roundsValid &&
                                _intervalValid
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
              Text(ui('当前位置：{0}', [_SegmentLoopDialogState._time(value)]),
                  style: Theme.of(context).textTheme.titleMedium),
              Slider(
                  key: const ValueKey('segment-loop-position'),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  value: value,
                  max: maximum,
                  label: _SegmentLoopDialogState._time(value),
                  semanticFormatterCallback: _SegmentLoopDialogState._time,
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

class _SegmentControlPair extends StatelessWidget {
  const _SegmentControlPair({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        const gap = 12.0;
        final minimumWidth = MediaQuery.textScalerOf(context).scale(220);
        final columns = constraints.maxWidth >= minimumWidth * 2 + gap ? 2 : 1;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        double labelHeight = 0;
        if (columns == 2) {
          for (final child in children.whereType<_PracticeField>()) {
            final painter = TextPainter(
              text: TextSpan(
                  text: child.label,
                  style: Theme.of(context).textTheme.bodySmall),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: width);
            if (painter.height > labelHeight) labelHeight = painter.height;
            painter.dispose();
          }
        }
        return Wrap(spacing: gap, runSpacing: 16, children: [
          for (final child in children)
            SizedBox(
                width: width,
                child: child is _PracticeField && labelHeight > 0
                    ? _PracticeField(
                        label: child.label,
                        labelHeight: labelHeight,
                        child: child.child)
                    : child),
        ]);
      });
}

class _PracticeField extends StatelessWidget {
  const _PracticeField(
      {required this.label, required this.child, this.labelHeight});
  final double? labelHeight;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
              height: labelHeight,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: 8),
          child,
        ]),
      );
}
