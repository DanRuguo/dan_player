import 'dart:math' as math;
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_action_list_tile.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/play_service/named_queue_store.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/seek_target.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

Future<String?> _name(
    BuildContext context, String title, String initial) async {
  final controller = TextEditingController(text: initial);
  try {
    return await showAppDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: AppDialogTitle(ui(title)),
                content: Focus(
                    onFocusChange: HotkeysHelper.onFocusChanges,
                    child: TextField(
                        controller: controller,
                        autofocus: true,
                        maxLength: 80)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c), child: Text(ui('取消'))),
                  FilledButton(
                      onPressed: () {
                        if (controller.text.trim().isNotEmpty)
                          Navigator.pop(c, controller.text.trim());
                      },
                      child: Text(ui('保存')))
                ]));
  } finally {
    controller.dispose();
  }
}

Future<void> showNamedQueues(BuildContext context, PlaybackService service) =>
    showAppDialog<void>(
        context: context, builder: (_) => NamedQueuesDialog(service: service));

class NamedQueuesDialog extends StatefulWidget {
  const NamedQueuesDialog({super.key, required this.service, this.store});
  final NamedQueueStore? store;
  final PlaybackService service;
  @override
  State<NamedQueuesDialog> createState() => _NamedQueuesDialogState();
}

class _NamedQueuesDialogState extends State<NamedQueuesDialog> {
  List<Map<String, dynamic>> _items = [];
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items =
          await (widget.store ?? await NamedQueueStore.instance).list();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    Map<String, dynamic> snapshot;
    try {
      snapshot = widget.service.captureNamedQueue();
    } catch (e) {
      setState(() => _error = '$e');
      return;
    }
    final name = await _name(context, '保存当前收听会话', '');
    if (name != null && mounted)
      await _run(() async => (widget.store ?? await NamedQueueStore.instance)
          .save(name, snapshot));
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    final token = widget.service.playbackSessionToken;
    final resolved = widget.service.resolveNamedQueue(item);
    final approved = await showAppDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: AppDialogTitle(ui('恢复收听会话')),
                content: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Text(item['name'] as String),
                      Text(ui('将替换当前队列，恢复后保持暂停。')),
                      Text(ui('可用 {0} 项，暂不可用 {1} 项', [
                        resolved.length,
                        (item['queue'] as List).length - resolved.length
                      ])),
                      Text(ui(
                          item['shuffle'] == true ? '恢复随机播放模式' : '恢复顺序播放模式')),
                      for (final id in (item['queue'] as List).take(12))
                        Text(
                            '${id == item['current'] ? '▶ ' : ''}${resolved[id]?.displayTitle ?? ui('暂不可用')}')
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text(ui('取消'))),
                  FilledButton(
                      onPressed: resolved.isEmpty
                          ? null
                          : () => Navigator.pop(c, true),
                      child: Text(ui('恢复为暂停')))
                ]));
    if (approved == true && mounted)
      await _run(
          () => widget.service.restoreNamedQueue(item, expectedSession: token));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: AppDialogTitle(ui('收听会话')),
          content: AppDialogContent(
              width: 620,
              maxHeight: 440,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Align(
                    alignment: Alignment.center,
                    child: FilledButton.tonalIcon(
                        onPressed: _busy ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(ui('保存当前收听会话')))),
                const SizedBox(height: 12),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                Flexible(
                    child: ListView(shrinkWrap: true, children: [
                  for (final item in _items)
                    Card.outlined(
                        child: AppActionListTile(
                            title: item['name'] as String,
                            subtitle: ui(
                                '共 {0} 首歌曲', [(item['queue'] as List).length]),
                            onTap: _busy ? null : () => _restore(item),
                            actions: [
                          IconButton(
                              tooltip: ui('重命名'),
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final name = await _name(context, '重命名',
                                          item['name'] as String);
                                      if (name != null && mounted)
                                        await _run(() async => (widget.store ??
                                                await NamedQueueStore.instance)
                                            .rename(
                                                item['id'] as String, name));
                                    },
                              icon: const Icon(Icons.edit_outlined)),
                          IconButton(
                              tooltip: ui('删除'),
                              onPressed: _busy
                                  ? null
                                  : () => _run(() async => (widget.store ??
                                          await NamedQueueStore.instance)
                                      .remove(item['id'] as String)),
                              icon: const Icon(Icons.delete_outline))
                        ]))
                ])),
              ])),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: Text(ui('关闭')))
          ]);
}

Future<void> showBookmarkLibrary(BuildContext context) => showAppDialog<void>(
    context: context, builder: (_) => const BookmarkLibraryDialog());

class BookmarkLibraryDialog extends StatefulWidget {
  const BookmarkLibraryDialog(
      {super.key, this.embedded = false, this.store, this.header});
  final Widget? header;
  final bool embedded;
  final PlaybackBookmarkStore? store;
  @override
  State<BookmarkLibraryDialog> createState() => _BookmarkLibraryDialogState();
}

class _BookmarkLibraryDialogState extends State<BookmarkLibraryDialog> {
  final _search = TextEditingController();
  final _selected = <String>{};
  List<PlaybackBookmark> _items = [];
  String? _error;
  bool _busy = true;
  bool _canRetryLoad = false;
  @override
  void initState() {
    super.initState();
    _load();
    AudioLibrary.changes.addListener(_libraryChanged);
  }

  void _libraryChanged() {
    if (mounted) setState(_resolveBookmarks);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _canRetryLoad = false;
    });
    try {
      final items =
          await (widget.store ?? await PlaybackBookmarkStore.instance).all();
      if (mounted)
        setState(() {
          _items = items;
          _error = null;
          final ids = items.map((item) => item.id).toSet();
          _selected.retainAll(ids);
          _resolveBookmarks();
        });
    } catch (e) {
      if (mounted) {
        setState(() {
          _canRetryLoad = e is! UnsupportedError;
          _error = e is UnsupportedError
              ? '书签由更新版本创建，请更新播放器后再打开。'
              : '无法读取书签，请重试';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, Audio> _resolved = {};
  void _resolveBookmarks() {
    final byId = {
      for (final a in [
        ...AudioLibrary.instance.audioCollection,
        ...AudioLibrary.instance.onlineAudioCollection,
        ...PLAYLISTS.expand((p) => p.flattenAudios())
      ])
        a.stableTrackId: a
    };
    _resolved = {
      for (final item in _items)
        if ((byId[item.track] ??
                byId[TrackIdentityRegistry.instance.resolvePath(item.track)])
            case final Audio audio)
          item.id: audio
    };
  }

  String _bookmarkTime(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Audio? _audio(PlaybackBookmark item) => _resolved[item.id];

  Future<void> _change(Future<void> Function(PlaybackBookmarkStore) f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f(widget.store ?? await PlaybackBookmarkStore.instance);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _play(PlaybackBookmark item, Audio audio) async {
    if (!item.fitsDuration(audio.duration.toDouble())) {
      setState(() => _error = ui('书签超出当前有效时长'));
      return;
    }
    final service = PlayService.instance.playbackService;
    final played = await service.playAudioAt(audio,
        position: item.position, stillCurrent: () => mounted);
    if (played &&
        mounted &&
        item.end != null &&
        service.nowPlaying?.stableTrackId == audio.stableTrackId) {
      service.segmentLoop.setStart(item.position, service.length);
      service.segmentLoop.setEnd(item.end!, service.length);
      service.setSegmentLoopEnabled(true);
    }
  }

  @override
  void dispose() {
    AudioLibrary.changes.removeListener(_libraryChanged);
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final visible = _items
        .where((b) =>
            '${b.label} ${_audio(b)?.displayTitle ?? ''} ${_audio(b)?.artist ?? ''}'
                .toLowerCase()
                .contains(_search.text.toLowerCase()))
        .toList();
    final content = Column(
        mainAxisSize: widget.embedded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          SettingsSurface(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                if (widget.header != null) ...[
                  Align(alignment: Alignment.centerLeft, child: widget.header!),
                  const SizedBox(height: 12)
                ],
                TextField(
                    controller: _search,
                    decoration: InputDecoration(
                        labelText: ui('搜索书签或歌曲'),
                        prefixIcon: const Icon(Icons.search)),
                    onChanged: (_) => setState(() {})),
              ])),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(ui(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_canRetryLoad)
            TextButton(
                onPressed: _busy ? null : _load, child: Text(ui('重试'))),
          Flexible(
              fit: widget.embedded ? FlexFit.tight : FlexFit.loose,
              child: visible.isEmpty
                  ? Center(heightFactor: 2, child: Text(ui('没有匹配的书签')))
                  : LayoutBuilder(
                      builder: (context, constraints) => GridView.builder(
                          shrinkWrap: !widget.embedded,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: math.max(
                                      1,
                                      (constraints.maxWidth /
                                              math.max(
                                                  240,
                                                  MediaQuery.textScalerOf(
                                                          context)
                                                      .scale(240)))
                                          .floor()),
                                  mainAxisExtent: 88 +
                                      MediaQuery.textScalerOf(context)
                                              .scale(24) *
                                          4,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final b = visible[index];
                            final audio = _audio(b);
                            return _BookmarkCard(
                                selected: _selected.contains(b.id),
                                title: b.label,
                                subtitle:
                                    audio?.displayTitle ?? ui("暂不可用／需要重新关联"),
                                time:
                                    '${_bookmarkTime(b.positionMs)}${b.endMs == null ? '' : ' – ${_bookmarkTime(b.endMs!)}'}',
                                onTap: _busy
                                    ? null
                                    : () => setState(() {
                                          if (!_selected.add(b.id))
                                            _selected.remove(b.id);
                                        }),
                                actions: [
                                  IconButton(
                                      tooltip: ui('从书签播放'),
                                      onPressed: _busy || audio == null
                                          ? null
                                          : () => _play(b, audio),
                                      icon: const Icon(Icons.play_arrow)),
                                  IconButton(
                                      tooltip: ui('重命名'),
                                      onPressed: _busy
                                          ? null
                                          : () async {
                                              final name = await _name(
                                                  context, '重命名', b.label);
                                              if (name != null && mounted)
                                                await _change((s) =>
                                                    s.rename(b.id, name));
                                            },
                                      icon: const Icon(Icons.edit_outlined))
                                ]);
                          }))),
        ]);
    final actions = [
      FilledButton.icon(
          onPressed: _busy || _selected.isEmpty
              ? null
              : () => _change((s) => s.removeMany(Set.of(_selected))),
          icon: const Icon(Icons.delete_outline),
          label: Text(ui('删除所选'))),
      if (!widget.embedded)
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(ui('关闭'))),
    ];
    if (widget.embedded)
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: content),
        Align(
            alignment: Alignment.centerRight,
            child: Wrap(spacing: 8, children: actions)),
      ]);
    return AlertDialog(
        title: AppDialogTitle(ui('全库书签')),
        content: AppDialogContent(width: 700, maxHeight: 510, child: content),
        actions: actions);
  }
}

Future<void> showPreciseSeek(BuildContext context, PlaybackService service) =>
    showAppDialog<void>(
        context: context, builder: (_) => PreciseSeekDialog(service: service));

class PreciseSeekDialog extends StatefulWidget {
  const PreciseSeekDialog({super.key, required this.service});
  final PlaybackService service;
  @override
  State<PreciseSeekDialog> createState() => _PreciseSeekDialogState();
}

class _PreciseSeekDialogState extends State<PreciseSeekDialog> {
  final _input = TextEditingController();
  late final _session = widget.service.playbackSessionToken;
  String? _error;
  void _submit() {
    try {
      final target = SeekTarget.parse(_input.text)
          .resolve(widget.service.position, widget.service.length);
      widget.service.seekPrecisely(target, _session);
      Navigator.pop(context);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String preview = '';
    try {
      preview = Duration(
              milliseconds: (SeekTarget.parse(_input.text).resolve(
                          widget.service.position, widget.service.length) *
                      1000)
                  .round())
          .toString();
    } catch (_) {}
    return AlertDialog(
        title: AppDialogTitle(ui('精确定位')),
        content: SizedBox(
            width: 420,
            child: Focus(
                onFocusChange: HotkeysHelper.onFocusChanges,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                          controller: _input,
                          autofocus: true,
                          decoration: const InputDecoration(
                              hintText: 'mm:ss / hh:mm:ss.fff / +30 / -10'),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _submit()),
                      const SizedBox(height: 12),
                      Text(ui('相对跳转以确认时的当前位置计算，暂停状态保持不变。')),
                      if (preview.isNotEmpty)
                        Text(preview, textAlign: TextAlign.center),
                      if (_error != null)
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))
                    ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(ui('取消'))),
          FilledButton(
              onPressed: widget.service.canEditQueue &&
                      widget.service.nowPlaying != null
                  ? _submit
                  : null,
              child: Text(ui('定位')))
        ]);
  }
}

class _BookmarkCard extends StatelessWidget {
  const _BookmarkCard(
      {required this.title,
      required this.subtitle,
      required this.time,
      required this.actions,
      required this.selected,
      this.onTap});
  final String title, subtitle, time;
  final List<Widget> actions;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
          borderRadius: AppShape.controlRadius,
          side: BorderSide(
              color: selected
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: .5),
              width: selected ? 2 : 1)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                        height: MediaQuery.textScalerOf(context).scale(24) * 2,
                        child: Row(children: [
                          Icon(Icons.bookmark_outline, color: scheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.titleMedium)),
                        ])),
                    const SizedBox(height: 6),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium),
                    Text(time,
                        key: ValueKey(('bookmark-time', time)),
                        maxLines: 1,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const Spacer(),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: actions),
                  ]))),
    );
  }
}
