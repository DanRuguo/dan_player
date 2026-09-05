import 'dart:async';

import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/audio_selection_toolbar.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/playlist_destination_dialog.dart';
import 'package:dan_player/component/playlist_exchange_dialog.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

Future<void> showSmartPlaylists(BuildContext context,
        {List<Audio> Function()? library,
        Future<SmartPlaylistStore> Function()? loadStore,
        Listenable? libraryChanges}) =>
    showAppDialog<void>(
        context: context,
        builder: (_) => SmartPlaylistsDialog(
            library: library,
            loadStore: loadStore,
            libraryChanges: libraryChanges));

class SmartPlaylistsDialog extends StatefulWidget {
  const SmartPlaylistsDialog(
      {super.key,
      this.library,
      this.loadStore,
      this.libraryChanges,
      this.evaluate,
      this.onPlay,
      this.onAddToPlaylist,
      this.onExport});

  final List<Audio> Function()? library;
  final Future<SmartPlaylistStore> Function()? loadStore;
  final Listenable? libraryChanges;
  final Future<List<Audio>> Function(SmartPlaylist, List<Audio>)? evaluate;
  final SelectedAudioAction? onPlay;
  final SelectedAudioAction? onAddToPlaylist;
  final SelectedAudioAction? onExport;

  @override
  State<SmartPlaylistsDialog> createState() => _SmartPlaylistsDialogState();
}

class _SmartPlaylistsDialogState extends State<SmartPlaylistsDialog> {
  final _name = TextEditingController();
  final _query = TextEditingController();
  final _artist = TextEditingController();
  final _album = TextEditingController();
  final _formats = TextEditingController();
  final _minimum = TextEditingController();
  final _maximum = TextEditingController();
  final _scroll = ScrollController();
  late final Listenable _libraryChanges =
      widget.libraryChanges ?? AudioLibrary.changes;
  SmartPlaylistStore? _store;
  List<SmartPlaylist> _rules = [];
  String? _editingId;
  bool _newRule = false;
  SmartPlaylistSort _sort = SmartPlaylistSort.name;
  List<Audio> _audios = [];
  final Set<String> _selectedPaths = {};
  bool _selecting = false;
  bool _loading = true;
  bool _saving = false;
  bool _confirmingRemoval = false;
  bool _previewing = false;
  String? _storageError;
  String? _previewError;
  int _generation = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _libraryChanges.addListener(_libraryChanged);
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _storageError = null;
    });
    try {
      final store =
          await (widget.loadStore?.call() ?? SmartPlaylistStore.instance);
      final rules = await store.list();
      if (!mounted) return;
      setState(() {
        _store = store;
        _rules = rules;
      });
    } catch (_) {
      if (mounted) setState(() => _storageError = '无法读取智能歌单，请检查数据目录后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(SmartPlaylist? rule) {
    _debounce?.cancel();
    _generation++;
    _name.text = rule?.name ?? '';
    _query.text = rule?.query ?? '';
    _artist.text = rule?.artist ?? '';
    _album.text = rule?.album ?? '';
    _formats.text = rule?.formats ?? '';
    _minimum.text = rule?.minSeconds?.toString() ?? '';
    _maximum.text = rule?.maxSeconds?.toString() ?? '';
    setState(() {
      _editingId = rule?.id ?? 'smart-${DateTime.now().microsecondsSinceEpoch}';
      _newRule = rule == null;
      _sort = rule?.sort ?? SmartPlaylistSort.name;
      _storageError = null;
      _previewError = null;
      _audios = [];
      _selectedPaths.clear();
      _selecting = false;
    });
    _top();
    _queuePreview(immediate: true);
  }

  void _back() {
    _debounce?.cancel();
    _generation++;
    setState(() {
      _editingId = null;
      _audios = [];
      _previewError = null;
      _storageError = null;
      _previewing = false;
    });
    _top();
  }

  void _top() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _libraryChanged() {
    if (_editingId != null) _queuePreview(immediate: true);
  }

  SmartPlaylist _draft({bool forPreview = false}) => SmartPlaylist(
      id: _editingId!,
      name: forPreview && _name.text.trim().isEmpty
          ? 'preview'
          : _name.text.trim(),
      query: _query.text.trim(),
      artist: _artist.text.trim(),
      album: _album.text.trim(),
      formats: _formats.text.trim(),
      minSeconds: int.tryParse(_minimum.text.trim()),
      maxSeconds: int.tryParse(_maximum.text.trim()),
      sort: _sort);

  String? _durationError() => [_minimum.text, _maximum.text].any(
          (text) => text.trim().isNotEmpty && int.tryParse(text.trim()) == null)
      ? '时长须为 0–86400 秒，最短时长不能超过最长时长。'
      : null;

  void _queuePreview({bool immediate = false}) {
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _previewing = true;
      _previewError = null;
    });
    if (immediate) {
      unawaited(_preview(generation));
    } else {
      _debounce = Timer(const Duration(milliseconds: 220),
          () => unawaited(_preview(generation)));
    }
  }

  Future<void> _preview(int generation) async {
    if (_editingId == null) return;
    final draft = _draft(forPreview: true);
    final validation = _durationError() ?? draft.validate();
    if (validation != null) {
      setState(() {
        _previewError = validation;
        _previewing = false;
        _audios = [];
      });
      return;
    }
    try {
      final library = List<Audio>.of(
          widget.library?.call() ?? AudioLibrary.instance.audioCollection);
      final results = await (widget.evaluate?.call(draft, library) ??
          draft.evaluate(library,
              shouldCancel: () => !mounted || generation != _generation));
      if (!mounted || generation != _generation) return;
      setState(() {
        _audios = results;
        final visible = results.map((audio) => audio.path).toSet();
        _selectedPaths.removeWhere((path) => !visible.contains(path));
        _previewing = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _previewError = '无法更新结果预览，请重试。';
          _audios = [];
          _previewing = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_saving || _store == null || _editingId == null) return;
    final rule = _draft();
    final validation = _durationError() ?? rule.validate();
    if (validation != null) {
      setState(() => _storageError = validation);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _storageError = null;
    });
    try {
      await _store!.upsert(rule);
      final rules = await _store!.list();
      if (!mounted) return;
      setState(() => _rules = rules);
      _back();
    } catch (error) {
      if (mounted) {
        setState(() => _storageError = error is FormatException
            ? error.message.toString()
            : '智能歌单尚未保存，编辑内容已保留，请重试。');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(SmartPlaylist rule) async {
    if (_saving || _confirmingRemoval || _store == null) return;
    _confirmingRemoval = true;
    try {
      final confirmed = await showAppDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                scrollable: true,
                title: AppDialogTitle(ui('删除智能歌单规则')),
                content: Text(ui('删除“{0}”的规则？音乐文件和普通歌单会保留。', [rule.name])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(ui('取消'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(ui('删除'))),
                ],
              ));
      if (confirmed != true || !mounted) return;
      setState(() {
        _saving = true;
        _storageError = null;
      });
      await _store!.remove(rule.id);
      final rules = await _store!.list();
      if (mounted) setState(() => _rules = rules);
    } catch (_) {
      if (mounted) setState(() => _storageError = '删除规则失败，请重试。');
    } finally {
      _confirmingRemoval = false;
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Audio> get _selected => _previewing || _previewError != null
      ? []
      : _selecting
          ? _audios
              .where((audio) => _selectedPaths.contains(audio.path))
              .toList()
          : List<Audio>.of(_audios);

  Future<void> _play(List<Audio> audios) async {
    if (widget.onPlay != null) {
      await widget.onPlay!(audios);
    } else {
      PlayService.instance.playbackService.play(0, audios);
    }
  }

  Future<void> _add(List<Audio> audios) async {
    if (widget.onAddToPlaylist != null) {
      await widget.onAddToPlaylist!(audios);
    } else {
      await showAddAudiosToPlaylistDialog(context, audios);
    }
  }

  Future<void> _export(List<Audio> audios) async {
    if (widget.onExport != null) {
      await widget.onExport!(audios);
    } else {
      await exportM3uPlaylist(context, audios,
          name: _name.text.trim().isEmpty ? ui('智能歌单') : _name.text.trim());
    }
  }

  Future<void> _action(SelectedAudioAction action) async {
    try {
      await action(List<Audio>.of(_selected));
    } catch (_) {
      if (mounted) setState(() => _storageError = '处理所选歌曲失败，请重试');
    }
  }

  Widget _field(String id, String label, TextEditingController controller,
          {bool number = false, String? hint}) =>
      TextField(
        key: ValueKey('smart-$id'),
        enabled: !_saving,
        controller: controller,
        maxLength: id == 'name' ? 120 : 160,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
            labelText: ui(label),
            hintText: hint == null ? null : ui(hint),
            border: AppShape.inputBorder,
            counterText: ''),
        onChanged: (_) => _queuePreview(),
      );

  Widget _fields() => ExpansionTile(
          key: ValueKey('smart-fields-$_editingId'),
          initiallyExpanded: _newRule,
          maintainState: true,
          tilePadding: EdgeInsets.zero,
          title: Text(ui('筛选规则')),
          children: [
            Focus(
              onFocusChange: HotkeysHelper.onFocusChanges,
              child: LayoutBuilder(builder: (context, constraints) {
                final width = constraints.maxWidth >= 600
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final field in [
                    _field('name', '智能歌单名称', _name),
                    _field('query', '关键词（标题、歌手、专辑）', _query),
                    _field('artist', '歌手包含', _artist),
                    _field('album', '专辑包含', _album),
                    _field('formats', '文件格式', _formats,
                        hint: '例如 flac, mp3；留空不限'),
                    DropdownButtonFormField<SmartPlaylistSort>(
                      key: ValueKey('smart-sort-$_editingId'),
                      initialValue: _sort,
                      isExpanded: true,
                      itemHeight: null,
                      decoration: InputDecoration(
                          labelText: ui('结果排序'), border: AppShape.inputBorder),
                      items: [
                        for (final sort in SmartPlaylistSort.values)
                          DropdownMenuItem(
                              value: sort, child: Text(ui(_sortLabel(sort))))
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value != null) {
                                _sort = value;
                                _queuePreview();
                              }
                            },
                    ),
                    _field('minimum', '最短时长（秒）', _minimum, number: true),
                    _field('maximum', '最长时长（秒）', _maximum, number: true),
                  ])
                    SizedBox(width: width, child: field),
                ]);
              }),
            ),
            const SizedBox(height: 12),
          ]);

  Widget _actions() {
    final selected = _selected;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_selecting)
        AudioSelectionToolbar(
          selected: selected,
          hasItems: !_previewing && _audios.isNotEmpty,
          allVisibleSelected:
              _audios.isNotEmpty && selected.length == _audios.length,
          onToggleAll: () => setState(() {
            if (selected.length == _audios.length) {
              _selectedPaths.clear();
            } else {
              _selectedPaths.addAll(_audios.map((a) => a.path));
            }
          }),
          onInvert: () => setState(() {
            final next = _audios
                .where((a) => !_selectedPaths.contains(a.path))
                .map((a) => a.path)
                .toSet();
            _selectedPaths
              ..clear()
              ..addAll(next);
          }),
          onExit: () => setState(() => _selecting = false),
          onPlay: _play,
          onAddToPlaylist: _add,
          onExport: _export,
        )
      else
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
              key: const ValueKey('smart-play'),
              onPressed:
                  selected.isEmpty ? null : () => unawaited(_action(_play)),
              icon: const Icon(Symbols.play_arrow),
              label: Text(ui('播放全部'))),
          AudioSelectionMenu(
              selected: selected, onAddToPlaylist: _add, onExport: _export),
          IconButton(
              key: const ValueKey('smart-select'),
              tooltip: ui('多选'),
              onPressed: selected.isEmpty
                  ? null
                  : () => setState(() {
                        _selecting = true;
                        _selectedPaths
                          ..clear()
                          ..addAll(_audios.map((audio) => audio.path));
                      }),
              icon: const Icon(Symbols.checklist)),
        ]),
      const SizedBox(height: 8),
      OutlinedButton.icon(
          key: const ValueKey('smart-ordinary'),
          onPressed: selected.isEmpty ? null : () => unawaited(_action(_add)),
          icon: const Icon(Symbols.playlist_add),
          label: Text(ui('加入或新建普通歌单…'))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return PopScope(
        canPop: !_saving,
        child: Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 920,
            height: MediaQuery.sizeOf(context).height * .88,
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  AppDialogTitle(ui(_editingId == null ? '智能歌单' : '智能歌单预览'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                      leading: _editingId == null
                          ? null
                          : IconButton(
                              tooltip: ui('返回'),
                              onPressed: _saving ? null : _back,
                              icon: const Icon(Symbols.arrow_back)),
                      trailing: IconButton(
                          tooltip: ui('关闭'),
                          onPressed:
                              _saving ? null : () => Navigator.pop(context),
                          icon: const Icon(Symbols.close))),
                  const SizedBox(height: 8),
                  if (_saving) const LinearProgressIndicator(),
                  Expanded(
                      child: AbsorbPointer(
                          absorbing: _saving,
                          child: CustomScrollView(
                            key: const ValueKey('smart-scroll'),
                            controller: _scroll,
                            slivers: [
                              SliverToBoxAdapter(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    if (_editingId != null)
                                      Text(ui(
                                          '只筛选本地曲库，须满足全部条件；曲库变化会更新预览，已播放的队列保持原顺序。')),
                                    if (_storageError != null)
                                      Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          child: Text(ui(_storageError!),
                                              key: const ValueKey(
                                                  'smart-storage-error'),
                                              style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .error))),
                                    if (_editingId == null) ...[
                                      const SizedBox(height: 12),
                                      FilledButton.icon(
                                          key: const ValueKey('smart-new'),
                                          onPressed: _store == null ||
                                                  _loading ||
                                                  _rules.length >=
                                                      SmartPlaylistStore
                                                          .maxPlaylists
                                              ? null
                                              : () => _open(null),
                                          icon: const Icon(Symbols.add),
                                          label: Text(ui('新建智能歌单'))),
                                      const SizedBox(height: 12),
                                      Text(ui(
                                          '只筛选本地曲库，须满足全部条件；曲库变化会更新预览，已播放的队列保持原顺序。')),
                                      if (_rules.length >=
                                          SmartPlaylistStore.maxPlaylists)
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8),
                                            child:
                                                Text(ui('最多可保存 100 个智能歌单。'))),
                                      if (_loading)
                                        const Padding(
                                            padding: EdgeInsets.all(24),
                                            child: Center(
                                                child:
                                                    CircularProgressIndicator())),
                                      if (!_loading && _store == null)
                                        TextButton(
                                            onPressed: _load,
                                            child: Text(ui('重试'))),
                                      if (!_loading &&
                                          _store != null &&
                                          _rules.isEmpty)
                                        Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 24),
                                            child: Text(
                                                ui('还没有智能歌单，创建规则即可自动归集歌曲。'))),
                                    ] else ...[
                                      _fields(),
                                      if (_previewing)
                                        const LinearProgressIndicator(),
                                      if (_previewError != null) ...[
                                        Text(ui(_previewError!),
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error)),
                                        TextButton(
                                            onPressed: () =>
                                                _queuePreview(immediate: true),
                                            child: Text(ui('重试'))),
                                      ],
                                      Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          child: Text(
                                              ui('匹配 {0} 首本地歌曲', [
                                                _previewing
                                                    ? '…'
                                                    : _audios.length
                                              ]),
                                              key: const ValueKey(
                                                  'smart-result-count'))),
                                      _actions(),
                                      const SizedBox(height: 12),
                                    ],
                                  ])),
                              if (_editingId == null)
                                SliverList.builder(
                                    itemCount: _rules.length,
                                    itemBuilder: (context, index) {
                                      final rule = _rules[index];
                                      return ListTile(
                                          key:
                                              ValueKey('smart-rule-${rule.id}'),
                                          title: Text(rule.name),
                                          subtitle: Text(ui('查看结果或编辑规则')),
                                          leading:
                                              const Icon(Symbols.auto_awesome),
                                          onTap: () => _open(rule),
                                          trailing: IconButton(
                                              tooltip: ui('删除智能歌单规则'),
                                              onPressed: () =>
                                                  unawaited(_remove(rule)),
                                              icon:
                                                  const Icon(Symbols.delete)));
                                    })
                              else if (!_previewing && _previewError == null)
                                SliverList.builder(
                                    itemCount: _audios.length,
                                    itemBuilder: (context, index) {
                                      final audio = _audios[index];
                                      void toggle() => setState(() {
                                            if (!_selectedPaths
                                                .remove(audio.path)) {
                                              _selectedPaths.add(audio.path);
                                            }
                                          });
                                      return AudioTile(
                                          key: ValueKey(
                                              'smart-result-${audio.path}'),
                                          audioIndex: index,
                                          playlist: _audios,
                                          selection: AudioTileSelection(
                                              enabled: _selecting,
                                              selected: _selectedPaths
                                                  .contains(audio.path),
                                              onToggle: toggle,
                                              onStart: () => setState(() {
                                                    _selecting = true;
                                                    _selectedPaths
                                                        .add(audio.path);
                                                  })));
                                    }),
                            ],
                          ))),
                  if (_editingId != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Wrap(spacing: 8, runSpacing: 8, children: [
                          TextButton(
                              onPressed: _saving ? null : _back,
                              child: Text(ui('取消'))),
                          FilledButton(
                              key: const ValueKey('smart-save'),
                              onPressed: _saving ? null : _save,
                              child: Text(ui('保存规则'))),
                        ])),
                ])),
          ),
        ));
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _libraryChanges.removeListener(_libraryChanged);
    for (final controller in [
      _name,
      _query,
      _artist,
      _album,
      _formats,
      _minimum,
      _maximum
    ]) {
      controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }
}

String _sortLabel(SmartPlaylistSort sort) => switch (sort) {
      SmartPlaylistSort.name => '歌曲名称',
      SmartPlaylistSort.artist => '歌手',
      SmartPlaylistSort.album => '专辑',
      SmartPlaylistSort.newest => '最近加入优先',
      SmartPlaylistSort.duration => '时长从短到长',
    };
