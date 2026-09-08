import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

Future<DateTimeRange?> showAppDateRangePicker(BuildContext context,
        {DateTimeRange? initialRange, required DateTime lastDate}) =>
    showAppDialog<DateTimeRange>(
        context: context,
        builder: (_) => AppDateRangeDialog(
            initialRange: initialRange,
            lastDate: DateUtils.dateOnly(lastDate)));

/// Desktop-sized range selection using the same dialog, fields and actions as
/// the player. The calendar scrolls inside the dialog at short window heights.
class AppDateRangeDialog extends StatefulWidget {
  const AppDateRangeDialog(
      {super.key, this.initialRange, required this.lastDate});
  final DateTimeRange? initialRange;
  final DateTime lastDate;
  @override
  State<AppDateRangeDialog> createState() => _AppDateRangeDialogState();
}

class _AppDateRangeDialogState extends State<AppDateRangeDialog> {
  late DateTime _start = widget.initialRange?.start ??
      widget.lastDate.subtract(const Duration(days: 7));
  late DateTime _end = widget.initialRange?.end ?? widget.lastDate;
  bool _editingStart = true, _typing = false;
  final _form = GlobalKey<FormState>();
  DateTime get _selected => _editingStart ? _start : _end;
  void _pick(DateTime date) => setState(() {
        if (_editingStart) {
          _start = date;
          if (_end.isBefore(date)) _end = date;
          _editingStart = false;
        } else {
          _end = date;
          if (_start.isAfter(date)) _start = date;
        }
      });
  void _save() {
    if (_typing) {
      if (!_form.currentState!.validate()) return;
      _form.currentState!.save();
    }
    Navigator.pop(context, DateTimeRange(start: _start, end: _end));
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final localizations = MaterialLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget endpoint(bool start) => OutlinedButton(
          key: ValueKey(start ? 'date-range-start' : 'date-range-end'),
          style: appToolbarControlStyle(context).copyWith(
              backgroundColor: _editingStart == start
                  ? WidgetStatePropertyAll(scheme.primaryContainer)
                  : null,
              foregroundColor: _editingStart == start
                  ? WidgetStatePropertyAll(scheme.onPrimaryContainer)
                  : null),
          onPressed: () => setState(() {
            _editingStart = start;
            _typing = false;
          }),
          child: Text(localizations.formatCompactDate(start ? _start : _end)),
        );
    return AlertDialog(
      key: const ValueKey('app-date-range-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: AppDialogTitle(ui('自选区间'),
          leading: const Icon(Symbols.date_range),
          trailing: IconButton(
              tooltip: ui('关闭'),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Symbols.close))),
      content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Text(ui('开始日期'),
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    endpoint(true)
                  ])),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Text(ui('结束日期'),
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    endpoint(false)
                  ])),
            ]),
            const SizedBox(height: 16),
            if (_typing)
              Form(
                  key: _form,
                  child: InputDatePickerFormField(
                    key: ValueKey(('date-input', _editingStart)),
                    initialDate: _selected,
                    firstDate: DateTime(1900),
                    lastDate: widget.lastDate,
                    onDateSaved: _pick,
                    autofocus: true,
                  ))
            else
              Material(
                  shape: AppShape.surface.copyWith(
                      side: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: .6))),
                  color: scheme.surfaceContainerLow,
                  child: CalendarDatePicker(
                    key: ValueKey(('date-calendar', _editingStart, _selected)),
                    initialDate: _selected,
                    firstDate: DateTime(1900),
                    lastDate: widget.lastDate,
                    onDateChanged: _pick,
                  )),
            const SizedBox(height: 8),
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: () => setState(() => _typing = !_typing),
                    icon: Icon(_typing ? Symbols.calendar_month : Symbols.edit),
                    label: Text(ui(_typing ? '日历选择' : '输入日期')))),
          ]))),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(ui('取消'))),
        FilledButton(onPressed: _save, child: Text(ui('应用')))
      ],
    );
  }
}
