import 'package:flutter/foundation.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'dart:math' as math;
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_date_range_dialog.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

Future<void> showPersonalTrackEditor(
        BuildContext context, List<Audio> targets) =>
    showAppDialog<void>(
        context: context,
        builder: (_) =>
            PersonalTrackEditor(targets: List.unmodifiable(targets)));

class PersonalTrackEditor extends StatefulWidget {
  const PersonalTrackEditor({super.key, required this.targets, this.store});
  final PersonalLibrary? store;
  final List<Audio> targets;
  @override
  State<PersonalTrackEditor> createState() => _PersonalTrackEditorState();
}

class _PersonalTrackEditorState extends State<PersonalTrackEditor> {
  bool _saving = false, _ratingChanged = false, _mixedRating = false;
  int? _rating;
  String? _error;
  Map<String, PersonalTrack>? _before;
  final Set<String> _initialTags = {}, _draftTags = {};
  bool get _tagsChanged => !setEquals(_initialTags, _draftTags);
  bool get _ready => _before != null && !_saving;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data =
          await (widget.store ?? await PersonalLibrary.instance).snapshot();
      if (!mounted) return;
      final records = widget.targets
          .map((a) => data[a.stableTrackId] ?? const PersonalTrack())
          .toList();
      setState(() {
        _before = data;
        _rating = records.firstOrNull?.rating;
        _mixedRating = records.any((r) => r.rating != _rating);
        _initialTags.clear();
        _initialTags.addAll(records.expand((r) => r.tags));
        _draftTags
          ..clear()
          ..addAll(_initialTags);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _editTag([String? original]) async {
    var input = original ?? '';
    final value = await showAppDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: AppDialogTitle(ui(original == null ? '添加标签' : '编辑标签')),
              content: SizedBox(
                  width: 320,
                  child: TextFormField(
                      initialValue: input,
                      onChanged: (value) => input = value,
                      autofocus: true,
                      maxLength: 80,
                      decoration: InputDecoration(labelText: ui('标签名称')),
                      onFieldSubmitted: (v) {
                        if (v.trim().isNotEmpty)
                          Navigator.pop(context, v.trim());
                      })),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(ui('取消'))),
                FilledButton(
                    onPressed: () {
                      if (input.trim().isNotEmpty)
                        Navigator.pop(context, input.trim());
                    },
                    child: Text(ui('确定')))
              ],
            ));
    if (!mounted || value == null) return;
    setState(() {
      if (original != null) _draftTags.remove(original);
      _draftTags.add(value);
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await (widget.store ?? await PersonalLibrary.instance).apply(
          widget.targets,
          changeRating: _ratingChanged,
          rating: _rating,
          changeTags: _tagsChanged,
          addTags: _draftTags.difference(_initialTags).toList(),
          removeTags: _initialTags.difference(_draftTags).toList());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '${ui("保存失败，草稿已保留")}: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AlertDialog(
      title: AppDialogTitle(ui('个人评分与标签')),
      content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Text(ui('评分和标签仅保存在播放器中，不修改音乐文件。')),
                const SizedBox(height: 20),
                Text(ui('修改评分'),
                    style: Theme.of(context).textTheme.titleMedium),
                if (_mixedRating) Text(ui('所选歌曲评分不同，未修改时各自保留。')),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final stars in [0, 1, 2, 3, 4, 5])
                    ChoiceChip(
                        label: Text(stars == 0 ? ui('未评分') : '★' * stars),
                        selected: !_mixedRating && (_rating ?? 0) == stars,
                        onSelected: !_ready
                            ? null
                            : (_) => setState(() {
                                  _rating = stars == 0 ? null : stars;
                                  _ratingChanged = true;
                                  _mixedRating = false;
                                }))
                ]),
                const SizedBox(height: 20),
                Text(ui('修改个人标签'),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final tag in _draftTags)
                        _EditableTagPill(
                            key: ValueKey(tag),
                            label: tag,
                            onEdit: !_ready ? null : () => _editTag(tag),
                            onDelete: !_ready
                                ? null
                                : () => setState(() => _draftTags.remove(tag))),
                      OutlinedButton.icon(
                          onPressed: !_ready || _draftTags.length >= 32
                              ? null
                              : () => _editTag(),
                          icon: const Icon(Symbols.add),
                          label: Text(ui('添加标签'))),
                    ]),
                if (widget.targets.length > 1) ...[
                  const SizedBox(height: 12),
                  Text(ui('仅将新增或删除的标签应用到所选歌曲，其余标签保留。'))
                ],
                if (_before == null && _error == null)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator()),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
              ]))),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(ui('取消'))),
        if (_before == null)
          TextButton(onPressed: _saving ? null : _load, child: Text(ui('重试'))),
        FilledButton(
            onPressed:
                !_ready || (!_ratingChanged && !_tagsChanged) ? null : _save,
            child: Text(ui('保存')))
      ],
    );
  }
}

class _EditableTagPill extends StatefulWidget {
  const _EditableTagPill(
      {super.key, required this.label, this.onEdit, this.onDelete});
  final String label;
  final VoidCallback? onEdit, onDelete;
  @override
  State<_EditableTagPill> createState() => _EditableTagPillState();
}

class _EditableTagPillState extends State<_EditableTagPill> {
  bool _hover = false, _focus = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Focus(
            onFocusChange: (v) => setState(() => _focus = v),
            child: Tooltip(
                message: widget.label,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: InputChip(
                      shape: const StadiumBorder(),
                      label: Text(widget.label,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onPressed: widget.onEdit,
                      onDeleted: widget.onDelete,
                      deleteButtonTooltipMessage: ui('删除标签'),
                      deleteIcon: Opacity(
                          opacity: _hover ||
                                  _focus ||
                                  Theme.of(context).platform ==
                                      TargetPlatform.android ||
                                  Theme.of(context).platform ==
                                      TargetPlatform.iOS
                              ? 1
                              : 0,
                          child: Icon(Symbols.close,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary)),
                    )))),
      );
}

Future<void> showPersonalLibrary(BuildContext context) => showAppDialog<void>(
    context: context, builder: (_) => const PersonalLibraryDialog());

class PersonalLibraryDialog extends StatefulWidget {
  const PersonalLibraryDialog(
      {super.key, this.embedded = false, this.store, this.audios, this.header});
  final bool embedded;
  final PersonalLibrary? store;
  final List<Audio>? audios;
  final Widget? header;
  @override
  State<PersonalLibraryDialog> createState() => _PersonalLibraryDialogState();
}

class _PersonalLibraryDialogState extends State<PersonalLibraryDialog> {
  Map<String, PersonalTrack>? _data;
  String? _error;
  int _stars = 0, _days = 0;
  int _loadRevision = 0;
  DateTimeRange? _range;
  final _tag = TextEditingController();
  @override
  void initState() {
    super.initState();
    PersonalLibrary.changes.addListener(_load);
    AudioLibrary.changes.addListener(_load);
    _load();
  }

  Future<void> _load() async {
    final revision = ++_loadRevision;
    try {
      final data =
          await (widget.store ?? await PersonalLibrary.instance).snapshot();
      if (mounted && revision == _loadRevision)
        setState(() {
          _data = data;
          _error = null;
        });
    } catch (e) {
      if (mounted && revision == _loadRevision) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    PersonalLibrary.changes.removeListener(_load);
    AudioLibrary.changes.removeListener(_load);
    _tag.dispose();
    super.dispose();
  }

  ButtonStyle _filterStyle(BuildContext context, bool selected) {
    final scheme = Theme.of(context).colorScheme;
    return appToolbarControlStyle(context).copyWith(
      backgroundColor:
          selected ? WidgetStatePropertyAll(scheme.primaryContainer) : null,
      foregroundColor:
          selected ? WidgetStatePropertyAll(scheme.onPrimaryContainer) : null,
    );
  }

  Future<void> _chooseRange() async {
    final range = await showAppDateRangePicker(context,
        initialRange: _range, lastDate: DateTime.now());
    if (mounted && range != null) setState(() => _range = range);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final now = DateTime.now();
    final from = _range?.start ??
        (_days == 0 ? null : now.subtract(Duration(days: _days)));
    final until = _range == null
        ? now
        : DateTime(_range!.end.year, _range!.end.month, _range!.end.day + 1);
    final audios = (widget.audios ?? AudioLibrary.instance.audioCollection)
        .where((a) {
      final item = _data?[a.stableTrackId] ?? const PersonalTrack();
      return (_stars == 0 || (item.rating != null && item.rating! >= _stars)) &&
          (_tag.text.trim().isEmpty ||
              item.tags.any((t) =>
                  t.toLowerCase().contains(_tag.text.trim().toLowerCase()))) &&
          (from == null ||
              (item.firstAddedAtUtc != null &&
                  !item.firstAddedAtUtc!.isBefore(from) &&
                  item.firstAddedAtUtc!.isBefore(until)));
    }).toList()
      ..sort((a, b) =>
          (_data?[b.stableTrackId]?.firstAddedAtUtc?.millisecondsSinceEpoch ??
                  -1)
              .compareTo(_data?[a.stableTrackId]
                      ?.firstAddedAtUtc
                      ?.millisecondsSinceEpoch ??
                  -1));
    final rating = MenuAnchor(
      style: const MenuStyle(shape: WidgetStatePropertyAll(AppShape.control)),
      menuChildren: [
        for (var i = 0; i <= 5; i++)
          MenuItemButton(
            key: ValueKey('personal-rating-$i'),
            leadingIcon: const Icon(Symbols.star, size: 20),
            trailingIcon:
                _stars == i ? const Icon(Symbols.check, size: 18) : null,
            onPressed: () => setState(() => _stars = i),
            child: Text(i == 0 ? ui('全部评分') : '≥ $i ★'),
          ),
      ],
      builder: (context, controller, _) => OutlinedButton(
        key: const ValueKey('personal-rating-menu'),
        style: _filterStyle(context, _stars > 0)
            .copyWith(minimumSize: const WidgetStatePropertyAll(Size(64, 48))),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        child: AppToolbarLabel(
            label: _stars == 0 ? ui('全部评分') : '≥ $_stars ★',
            icon: Symbols.star,
            trailing: const Icon(Symbols.expand_more, size: 18)),
      ),
    );
    final filters = SettingsSurface(
        child: LayoutBuilder(
            builder: (context, width) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (widget.header != null)
                              SizedBox(
                                  width: math.min(
                                      width.maxWidth,
                                      310 *
                                          MediaQuery.textScalerOf(context)
                                              .scale(14) /
                                          14),
                                  child: widget.header!),
                            for (final days in [0, 7, 30])
                              OutlinedButton(
                                key: ValueKey('personal-days-$days'),
                                style: _filterStyle(
                                    context, _days == days && _range == null),
                                onPressed: () => setState(() {
                                  _days = days;
                                  _range = null;
                                }),
                                child: Text(days == 0
                                    ? ui('全部')
                                    : ui('最近 {0} 天', [days])),
                              ),
                            OutlinedButton(
                              key: const ValueKey('personal-date-range'),
                              style: _filterStyle(context, _range != null),
                              onPressed: _chooseRange,
                              child: AppToolbarLabel(
                                  label: ui('自选区间'), icon: Symbols.date_range),
                            ),
                          ]),
                      if (_range != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                                '${MaterialLocalizations.of(context).formatCompactDate(_range!.start)} — ${MaterialLocalizations.of(context).formatCompactDate(_range!.end)}',
                                style: Theme.of(context).textTheme.bodySmall)),
                      const SizedBox(height: 12),
                      Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                                width: width.maxWidth < 600
                                    ? width.maxWidth
                                    : width.maxWidth - 216,
                                child: TextField(
                                    controller: _tag,
                                    decoration: InputDecoration(
                                        prefixIcon:
                                            const Icon(Symbols.label, size: 20),
                                        hintText: ui('筛选个人标签')),
                                    onChanged: (_) => setState(() {}))),
                            SizedBox(
                                width:
                                    width.maxWidth < 600 ? width.maxWidth : 204,
                                child: rating),
                          ]),
                    ])));
    final content = LayoutBuilder(
        builder: (context, constraints) => Column(
                mainAxisSize:
                    widget.embedded ? MainAxisSize.max : MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                      constraints:
                          BoxConstraints(maxHeight: constraints.maxHeight * .5),
                      child: SingleChildScrollView(
                          primary: false, child: filters)),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (_data == null && _error == null)
                    const LinearProgressIndicator(),
                  Flexible(
                      fit: widget.embedded ? FlexFit.tight : FlexFit.loose,
                      child: _data != null && audios.isEmpty
                          ? Center(
                              heightFactor: 1,
                              child: Text(ui('没有符合条件的歌曲'),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyLarge))
                          : ListView.builder(
                              shrinkWrap: !widget.embedded,
                              itemCount: audios.length,
                              itemBuilder: (context, i) {
                                final item = _data?[audios[i].stableTrackId] ??
                                    const PersonalTrack();
                                final details = [
                                  item.rating == null
                                      ? ui('未评分')
                                      : '★' * item.rating!,
                                  if (item.tags.isNotEmpty)
                                    item.tags.join(', '),
                                  item.firstAddedAtUtc == null
                                      ? ui('创建时间不可用')
                                      : MaterialLocalizations.of(context)
                                          .formatCompactDate(
                                              item.firstAddedAtUtc!.toLocal()),
                                  if (item.addedFromCreation) ui('文件创建时间（兜底）'),
                                ];
                                return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          AudioTile(
                                              playlist: audios, audioIndex: i),
                                          Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      72, 0, 16, 6),
                                              child: Text(details.join(' · '),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                          color: Theme.of(
                                                                  context)
                                                              .colorScheme
                                                              .onSurfaceVariant))),
                                        ]));
                              })),
                ]));
    if (widget.embedded) return content;
    return AlertDialog(
      title: AppDialogTitle(ui('个人整理与最近添加')),
      content: AppDialogContent(width: 760, maxHeight: 580, child: content),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(ui('关闭')))
      ],
    );
  }
}
