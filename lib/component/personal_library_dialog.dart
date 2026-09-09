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
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/component/bounded_tag_wrap.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'now_playing_bar_metrics.dart';

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
                SizedBox(
                    width: 400,
                    child: Builder(builder: (context) {
                      final available =
                          math.min(400, MediaQuery.sizeOf(context).width - 128);
                      final delete = original == null
                          ? null
                          : TextButton.icon(
                              onPressed: () => Navigator.pop(context, ''),
                              icon: const Icon(Symbols.delete),
                              label: Text(ui('删除')),
                              style: TextButton.styleFrom(
                                  foregroundColor:
                                      Theme.of(context).colorScheme.error));
                      final actions = Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(ui('取消'))),
                            FilledButton(
                                onPressed: () {
                                  if (input.trim().isNotEmpty)
                                    Navigator.pop(context, input.trim());
                                },
                                child: Text(ui('确定')))
                          ]);
                      if (available <
                          340 * MediaQuery.textScalerOf(context).scale(14) / 14)
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (delete != null)
                                Align(
                                    alignment: Alignment.centerLeft,
                                    child: delete),
                              Align(
                                  alignment: Alignment.centerRight,
                                  child: actions)
                            ]);
                      return Row(children: [
                        if (delete != null) delete,
                        const Spacer(),
                        actions
                      ]);
                    }))
              ],
            ));
    if (!mounted || value == null) return;
    setState(() {
      if (original != null) _draftTags.remove(original);
      if (value.isNotEmpty) _draftTags.add(value);
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
                        labelStyle: TextStyle(
                            color: Theme.of(context).colorScheme.primary),
                        checkmarkColor: Theme.of(context).colorScheme.primary,
                        selectedColor:
                            Theme.of(context).colorScheme.primaryContainer,
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
                            onEdit: !_ready ? null : () => _editTag(tag)),
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

class _EditableTagPill extends StatelessWidget {
  const _EditableTagPill({super.key, required this.label, this.onEdit});
  final String label;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) => Tooltip(
      message: label,
      child: OutlinedButton(
        onPressed: onEdit,
        style: OutlinedButton.styleFrom(
            shape: const StadiumBorder(),
            foregroundColor: Theme.of(context).colorScheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
        child: Text(label, textAlign: TextAlign.center),
      ));
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
  String _sort = 'date';
  SortDirection _direction = SortDirection.descending;
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
    final audios =
        (widget.audios ?? AudioLibrary.instance.audioCollection).where((a) {
      final item = _data?[a.stableTrackId] ?? const PersonalTrack();
      return (item.rating != null || item.tags.isNotEmpty) &&
          (_stars == 0 || (item.rating != null && item.rating! >= _stars)) &&
          (_tag.text.trim().isEmpty ||
              item.tags.any((t) =>
                  t.toLowerCase().contains(_tag.text.trim().toLowerCase()))) &&
          (from == null ||
              (item.modifiedAtUtc != null &&
                  !item.modifiedAtUtc!.isBefore(from) &&
                  item.modifiedAtUtc!.isBefore(until)));
    }).toList()
          ..sort((a, b) {
            final x = _data?[a.stableTrackId], y = _data?[b.stableTrackId];
            final order = switch (_sort) {
              'name' => a.displayTitle
                  .toLowerCase()
                  .compareTo(b.displayTitle.toLowerCase()),
              'rating' => (x?.rating ?? 0).compareTo(y?.rating ?? 0),
              _ => (x?.modifiedAtUtc?.millisecondsSinceEpoch ?? -1)
                  .compareTo(y?.modifiedAtUtc?.millisecondsSinceEpoch ?? -1),
            };
            return order == 0
                ? a.displayTitle.compareTo(b.displayTitle)
                : (_direction == SortDirection.ascending ? order : -order);
          });
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
                            AppSortButton<String>(
                                value: _sort,
                                direction: _direction,
                                onChanged: (v) => setState(() => _sort = v),
                                onDirectionChanged: (v) =>
                                    setState(() => _direction = v),
                                options: [
                                  AppSortOption(
                                      value: 'date',
                                      label: ui('评定日期'),
                                      icon: Symbols.schedule),
                                  AppSortOption(
                                      value: 'name',
                                      label: ui('名称'),
                                      icon: Symbols.sort_by_alpha),
                                  AppSortOption(
                                      value: 'rating',
                                      label: ui('评分'),
                                      icon: Symbols.star),
                                ]),
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
                              padding: EdgeInsets.only(
                                  bottom: widget.embedded
                                      ? NowPlayingBarMetrics.reservedSpace(
                                          context)
                                      : 0),
                              shrinkWrap: !widget.embedded,
                              itemCount: audios.length,
                              itemBuilder: (context, i) {
                                final item = _data?[audios[i].stableTrackId] ??
                                    const PersonalTrack();
                                return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Material(
                                        color: Colors.transparent,
                                        borderRadius: AppShape.controlRadius,
                                        clipBehavior: Clip.antiAlias,
                                        child: AudioTile(
                                            playlist: audios,
                                            audioIndex: i,
                                            content: _PersonalSongContent(
                                                audio: audios[i],
                                                item: item))));
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

class _PersonalSongContent extends StatelessWidget {
  const _PersonalSongContent({required this.audio, required this.item});
  final Audio audio;
  final PersonalTrack item;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = Theme.of(context).colorScheme;
    final rating = Text(item.rating == null ? ui('未评分') : '★' * item.rating!,
        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.primary));
    final date = Text(
        item.modifiedAtUtc == null
            ? ui('评定日期未知')
            : MaterialLocalizations.of(context)
                .formatCompactDate(item.modifiedAtUtc!.toLocal()),
        style: theme.textTheme.bodySmall);
    final title = Text(audio.displayTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge);
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >=
              760 * MediaQuery.textScalerOf(context).scale(14) / 14;
          final tags = BoundedTagWrap(tags: item.tags);
          return Row(children: [
            ClipRRect(
                borderRadius: AppShape.smallRadius,
                child: AudioArtwork(
                    audio: audio,
                    size: 48,
                    placeholder: Icon(Symbols.audio_file,
                        size: 48, color: scheme.primary))),
            const SizedBox(width: 16),
            if (wide) ...[
              Expanded(flex: 3, child: title),
              const SizedBox(width: 16),
              SizedBox(width: 100, child: rating),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: tags),
              const SizedBox(width: 16),
              SizedBox(width: 120, child: date)
            ] else
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    title,
                    const SizedBox(height: 6),
                    Wrap(spacing: 16, runSpacing: 6, children: [rating, date]),
                    if (item.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      tags
                    ]
                  ]))
          ]);
        }));
  }
}
