import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

Future<(int, int)?> showLyricTimingDialog(BuildContext context,
        {required int startMs, required int endMs}) =>
    showAppDialog<(int, int)>(
        context: context, builder: (_) => _TimingDialog(startMs, endMs));

class _TimingDialog extends StatefulWidget {
  const _TimingDialog(this.start, this.end);
  final int start, end;
  @override
  State<_TimingDialog> createState() => _TimingDialogState();
}

class _TimingDialogState extends State<_TimingDialog> {
  late final start = TextEditingController(text: '${widget.start}');
  late final end = TextEditingController(text: '${widget.end}');
  String? error;
  @override
  void dispose() {
    start.dispose();
    end.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: AppDialogTitle(ui('设置歌词时间')),
        content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Text(ui('单位为毫秒，使用歌曲时间轴。逐字内容必须位于该行的起止时间内。')),
                  const SizedBox(height: 20),
                  TextField(
                      key: const ValueKey('lyric-time-start'),
                      controller: start,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: ui('开始时间'), suffixText: 'ms')),
                  const SizedBox(height: 16),
                  TextField(
                      key: const ValueKey('lyric-time-end'),
                      controller: end,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: ui('结束时间'), suffixText: 'ms')),
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(ui('取消'))),
          FilledButton(
              onPressed: () {
                final a = int.tryParse(start.text), b = int.tryParse(end.text);
                if (a == null || b == null || a < 0 || b < a || b > 86400000) {
                  setState(() => error = ui('请输入有效起止时间（0 至 86400000 毫秒）'));
                  return;
                }
                Navigator.pop(context, (a, b));
              },
              child: Text(ui('应用')))
        ],
      );
}
