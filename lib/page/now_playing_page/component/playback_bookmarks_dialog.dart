import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

Future<void> showPlaybackBookmarksDialog(
        BuildContext context, PlaybackService service) =>
    showAppDialog<void>(
        context: context,
        builder: (_) => PlaybackBookmarksDialog(service: service));

class PlaybackBookmarksDialog extends StatefulWidget {
  const PlaybackBookmarksDialog({super.key, required this.service, this.store});
  final PlaybackService service;
  final PlaybackBookmarkStore? store;

  @override
  State<PlaybackBookmarksDialog> createState() =>
      _PlaybackBookmarksDialogState();
}

class _PlaybackBookmarksDialogState extends State<PlaybackBookmarksDialog> {
  final _name = TextEditingController();
  late final _audio = widget.service.nowPlaying;
  PlaybackBookmarkStore? _store;
  List<PlaybackBookmark> _items = [];
  bool _busy = true;
  String? _error;
  bool _selectRange = false;
  double _point = 0;
  RangeValues _range = const RangeValues(0, 1);

  static String _time(double seconds) =>
      Duration(milliseconds: (seconds * 1000).round()).toStringHMMSS();

  bool get _available =>
      _audio?.isLocal == true &&
      widget.service.nowPlaying?.path == _audio?.path &&
      widget.service.canUseSegmentLoop;

  @override
  void initState() {
    super.initState();
    final length = widget.service.length;
    if (length.isFinite && length > 0) {
      _point = widget.service.position.clamp(0, length).toDouble();
      final start = _point.clamp(0, (length - 1).clamp(0, length)).toDouble();
      _range = RangeValues(start, (start + 10).clamp(start, length).toDouble());
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final store = widget.store ?? await PlaybackBookmarkStore.instance;
      final entries = _audio == null
          ? <PlaybackBookmark>[]
          : await store.forTrack(_audio!.path,
              stableTrackId: _audio!.stableTrackId);
      if (!mounted) return;
      setState(() {
        _store = store;
        _items = entries;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取书签，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mutate(
      Future<void> Function(PlaybackBookmarkStore) action) async {
    if (_busy || _store == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(_store!);
      final entries = await _store!
          .forTrack(_audio!.path, stableTrackId: _audio!.stableTrackId);
      if (mounted) setState(() => _items = entries);
    } catch (_) {
      if (mounted) setState(() => _error = '书签保存失败，请重试；已有书签已保留');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(
      {bool segment = false,
      double? selectedPosition,
      double? selectedEnd}) async {
    if (!_available) return;
    final service = widget.service;
    final loop = service.segmentLoop;
    final position =
        selectedPosition ?? (segment ? loop.start : service.position);
    final end = selectedEnd ?? (segment ? loop.end : null);
    if (position == null ||
        !position.isFinite ||
        position < 0 ||
        position >= service.length ||
        (end != null &&
            (!end.isFinite || end > service.length || end - position < 1))) {
      return;
    }
    final label = _name.text.trim().isEmpty
        ? (end == null ? _time(position) : '${_time(position)} – ${_time(end)}')
        : _name.text.trim();
    await _mutate((store) => store.add(
        localPath: _audio!.path,
        stableTrackId: _audio!.stableTrackId,
        label: label,
        position: position,
        end: end));
    if (mounted && _error == null) _name.clear();
  }

  void _activate(PlaybackBookmark bookmark) {
    final service = widget.service;
    if (!_available || !bookmark.fitsDuration(service.length)) return;
    if (bookmark.end != null) {
      service.segmentLoop.setStart(bookmark.position, service.length);
      service.segmentLoop.setEnd(bookmark.end!, service.length);
      service.setSegmentLoopEnabled(true);
    } else {
      service.segmentLoop.setEnabled(false);
      service.seek(bookmark.position);
    }
  }

  Future<void> _rename(PlaybackBookmark bookmark) async {
    final name = await showAppDialog<String>(
        context: context,
        builder: (context) => _BookmarkNameDialog(initialName: bookmark.label));
    if (!mounted || name == null) return;
    await _mutate((store) => store.rename(bookmark.id, name));
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final service = widget.service;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
        listenable: Listenable.merge([
          service,
          service.segmentLoop,
          service.resolvingAudioPath,
          service.isChangingOutput
        ]),
        builder: (context, _) {
          final canSave = !_busy &&
              _store != null &&
              _available &&
              _items.length < PlaybackBookmarkStore.maxPerTrack;
          return AlertDialog(
              icon: const Icon(Symbols.bookmarks),
              title: Text(ui('播放书签')),
              content: SizedBox(
                  width: 480,
                  child: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(_audio?.displayTitle ?? ui('尚未选择歌曲'),
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        Text(ui(_available
                            ? '保存喜欢的位置或 A-B 片段，下次打开这首歌仍可使用。'
                            : '回到这首本地歌曲后，即可跳转或保存书签。')),
                        const SizedBox(height: 16),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          ChoiceChip(
                              label: Text(ui('时间点')),
                              selected: !_selectRange,
                              labelStyle: TextStyle(color: scheme.primary),
                              checkmarkColor: scheme.primary,
                              onSelected: canSave
                                  ? (_) => setState(() => _selectRange = false)
                                  : null),
                          ChoiceChip(
                              label: Text(ui('时间段')),
                              selected: _selectRange,
                              labelStyle: TextStyle(color: scheme.primary),
                              checkmarkColor: scheme.primary,
                              onSelected: canSave
                                  ? (_) => setState(() => _selectRange = true)
                                  : null),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                            _selectRange
                                ? '${_time(_range.start)} — ${_time(_range.end)}'
                                : _time(_point),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: scheme.primary)),
                        if (service.length.isFinite && service.length > 0)
                          _selectRange
                              ? RangeSlider(
                                  key: const ValueKey('bookmark-range-picker'),
                                  min: 0,
                                  max: service.length,
                                  values: RangeValues(
                                      _range.start.clamp(0, service.length),
                                      _range.end.clamp(0, service.length)),
                                  labels: RangeLabels(
                                      _time(_range.start), _time(_range.end)),
                                  onChanged: canSave
                                      ? (v) => setState(() => _range = v)
                                      : null)
                              : Slider(
                                  key: const ValueKey('bookmark-time-picker'),
                                  min: 0,
                                  max: service.length,
                                  value: _point.clamp(0, service.length),
                                  label: _time(_point),
                                  onChanged: canSave
                                      ? (v) => setState(() => _point = v)
                                      : null),
                        const SizedBox(height: 8),
                        TextField(
                            controller: _name,
                            enabled: canSave,
                            maxLength: 80,
                            decoration: InputDecoration(
                                labelText: ui('书签名称（可选）'),
                                border: const OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(14))),
                                counterText: ''),
                            onSubmitted: canSave
                                ? (_) => _save(
                                    selectedPosition:
                                        _selectRange ? _range.start : _point,
                                    selectedEnd:
                                        _selectRange ? _range.end : null)
                                : null),
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          FilledButton.icon(
                              key: const ValueKey('bookmark-save-selection'),
                              onPressed: canSave &&
                                      (_selectRange
                                          ? _range.end - _range.start >= 1
                                          : _point < service.length)
                                  ? () => _save(
                                      selectedPosition:
                                          _selectRange ? _range.start : _point,
                                      selectedEnd:
                                          _selectRange ? _range.end : null)
                                  : null,
                              icon: const Icon(Symbols.bookmark_add),
                              label: Text(ui('保存所选时间'))),
                          FilledButton.tonalIcon(
                              key: const ValueKey('bookmark-save-position'),
                              onPressed: canSave ? () => _save() : null,
                              icon: const Icon(Symbols.bookmark_add),
                              label: Text(ui('保存当前位置'))),
                          OutlinedButton.icon(
                              key: const ValueKey('bookmark-save-segment'),
                              onPressed: canSave && service.segmentLoop.hasRange
                                  ? () => _save(segment: true)
                                  : null,
                              icon: const Icon(Symbols.repeat),
                              label: Text(ui('保存 A-B 片段'))),
                        ]),
                        if (_items.length >= PlaybackBookmarkStore.maxPerTrack)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(ui('每首歌最多保存 100 个书签，可先删除不需要的书签。'))),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(ui(_error!),
                              style: TextStyle(color: scheme.error)),
                          if (_store == null)
                            TextButton(
                                onPressed: _busy ? null : _load,
                                child: Text(ui('重试'))),
                        ],
                        const SizedBox(height: 16),
                        if (_busy) const LinearProgressIndicator(),
                        if (!_busy && _items.isEmpty && _error == null)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(ui('还没有书签，先保存一个喜欢的位置吧。'))),
                        if (_items.isNotEmpty)
                          ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 240),
                              child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: _items.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 6),
                                  itemBuilder: (context, index) {
                                    final bookmark = _items[index];
                                    final enabled = !_busy &&
                                        _available &&
                                        bookmark.fitsDuration(service.length);
                                    return Material(
                                        color: scheme.surfaceContainerLow,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            side: BorderSide(
                                                color: scheme.outlineVariant)),
                                        clipBehavior: Clip.antiAlias,
                                        child: Row(children: [
                                          Expanded(
                                              child: InkWell(
                                                  key: ValueKey(
                                                      'bookmark-open-${bookmark.id}'),
                                                  onTap: enabled
                                                      ? () =>
                                                          _activate(bookmark)
                                                      : null,
                                                  child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              12),
                                                      child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(bookmark.label,
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: TextStyle(
                                                                    color: enabled
                                                                        ? scheme
                                                                            .onSurface
                                                                        : scheme
                                                                            .onSurfaceVariant)),
                                                            const SizedBox(
                                                                height: 4),
                                                            Text(
                                                                bookmark.end ==
                                                                        null
                                                                    ? _time(bookmark
                                                                        .position)
                                                                    : 'A ${_time(bookmark.position)} · B ${_time(bookmark.end!)}',
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .labelMedium),
                                                          ])))),
                                          PopupMenuButton<String>(
                                              enabled: !_busy,
                                              tooltip: ui('更多'),
                                              icon:
                                                  const Icon(Symbols.more_vert),
                                              onSelected: (action) {
                                                if (action == 'rename') {
                                                  _rename(bookmark);
                                                } else {
                                                  _mutate((store) => store
                                                      .remove(bookmark.id));
                                                }
                                              },
                                              itemBuilder: (_) => [
                                                    PopupMenuItem(
                                                        value: 'rename',
                                                        child:
                                                            Text(ui('重命名书签'))),
                                                    PopupMenuItem(
                                                        value: 'remove',
                                                        child:
                                                            Text(ui('删除书签'))),
                                                  ]),
                                        ]));
                                  })),
                      ]))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(ui('完成')))
              ]);
        });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }
}

class _BookmarkNameDialog extends StatefulWidget {
  const _BookmarkNameDialog({required this.initialName});
  final String initialName;

  @override
  State<_BookmarkNameDialog> createState() => _BookmarkNameDialogState();
}

class _BookmarkNameDialogState extends State<_BookmarkNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  void _submit() {
    if (_controller.text.trim().isNotEmpty) {
      Navigator.pop(context, _controller.text);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(ui('重命名书签')),
        content: TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 80,
            decoration: InputDecoration(labelText: ui('书签名称')),
            onSubmitted: (_) => _submit()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(ui('取消'))),
          FilledButton(onPressed: _submit, child: Text(ui('保存'))),
        ],
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
