import 'package:dan_player/component/app_presentation.dart';
import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class SetLyricSourceBtn extends StatelessWidget {
  const SetLyricSourceBtn({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
      listenable: PlayService.instance.lyricService,
      builder: (context, _) => FutureBuilder(
        future: PlayService.instance.lyricService.currLyricFuture,
        builder: (context, snapshot) {
          final audio = PlayService.instance.playbackService.nowPlaying;
          final loadingWidget = IconButton(
            onPressed: null,
            tooltip: ui("正在加载歌词"),
            icon: const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(),
            ),
          );
          final lyricNullable = snapshot.data;
          final isLocal = lyricNullable == null
              ? null
              : (lyricNullable is Lrc &&
                  lyricNullable.source == LrcSource.local);
          return switch (snapshot.connectionState) {
            ConnectionState.none => loadingWidget,
            ConnectionState.waiting => loadingWidget,
            ConnectionState.active => loadingWidget,
            ConnectionState.done => LyricSourceMenuButton(
                enabled: audio != null,
                showLocal: audio?.isLocal == true,
                isLocal: isLocal,
                onChooseDefault: () {
                  showAppDialog<String>(
                    context: context,
                    builder: (context) => LyricSourceDialog(audio: audio!),
                  );
                },
                onOnline: PlayService.instance.lyricService.useOnlineLyric,
                onLocal: PlayService.instance.lyricService.useLocalLyric,
              ),
          };
        },
      ),
    );
  }
}

class LyricSourceMenuButton extends StatelessWidget {
  const LyricSourceMenuButton({
    super.key,
    required this.enabled,
    required this.showLocal,
    required this.isLocal,
    required this.onChooseDefault,
    required this.onOnline,
    required this.onLocal,
  });

  final bool enabled;
  final bool showLocal;
  final bool? isLocal;
  final VoidCallback onChooseDefault;
  final VoidCallback onOnline;
  final VoidCallback onLocal;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      useRootOverlay: true,
      consumeOutsideTap: true,
      style: const MenuStyle(
        shape: WidgetStatePropertyAll(AppShape.control),
        minimumSize: WidgetStatePropertyAll(Size(220, 0)),
        maximumSize: WidgetStatePropertyAll(Size(320, double.infinity)),
      ),
      onOpen: () {
        ALWAYS_SHOW_LYRIC_VIEW_CONTROLS = true;
      },
      onClose: () {
        ALWAYS_SHOW_LYRIC_VIEW_CONTROLS = false;
      },
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('lyric-source-choose-default'),
          onPressed: onChooseDefault,
          leadingIcon: const Icon(Symbols.search),
          child: Text(
            ui("指定默认歌词"),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        MenuItemButton(
          key: const ValueKey('lyric-source-online'),
          onPressed: onOnline,
          leadingIcon: const Icon(Symbols.cloud),
          trailingIcon:
              isLocal == false ? const Icon(Symbols.check, size: 20) : null,
          child: Text(ui("在线")),
        ),
        if (showLocal)
          MenuItemButton(
            key: const ValueKey('lyric-source-local-menu-item'),
            onPressed: onLocal,
            leadingIcon: const Icon(Symbols.folder),
            trailingIcon:
                isLocal == true ? const Icon(Symbols.check, size: 20) : null,
            child: Text(ui("本地")),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        key: const ValueKey('lyric-source-menu-button'),
        onPressed: !enabled
            ? null
            : () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
        tooltip: ui("选择歌词来源"),
        icon: const Icon(Symbols.lyrics),
        color: scheme.onSecondaryContainer,
      ),
    );
  }
}

typedef LyricCandidateSearchCallback = Future<LyricSearchResponse> Function(
  Audio audio,
);
typedef LyricCandidateLoadCallback = Future<Lyric?> Function(
  SongSearchResult candidate,
);
typedef LyricSourcePersistCallback = Future<void> Function(
  String audioPath,
  LyricSource source,
);
typedef LyricCandidateApplyCallback = bool Function(
  String expectedTrackPath,
  Lyric lyric,
);
typedef LocalLyricApplyCallback = bool Function(String expectedTrackPath);

/// The dialog owns one search generation. It never creates a network Future in
/// build, and a selected lyric is committed only if the captured song is still
/// current after the download and source save have both completed.
class LyricSourceDialog extends StatefulWidget {
  const LyricSourceDialog({
    super.key,
    required this.audio,
    this.search,
    this.loadCandidate,
    this.persistSource,
    this.applyCandidate,
    this.applyLocal,
    this.currentTrackPath,
    this.playbackListenable,
  });

  final Audio audio;
  final LyricCandidateSearchCallback? search;
  final LyricCandidateLoadCallback? loadCandidate;
  final LyricSourcePersistCallback? persistSource;
  final LyricCandidateApplyCallback? applyCandidate;
  final LocalLyricApplyCallback? applyLocal;
  final String? Function()? currentTrackPath;
  final Listenable? playbackListenable;

  @override
  State<LyricSourceDialog> createState() => _LyricSourceDialogState();
}

class _LyricSourceDialogState extends State<LyricSourceDialog> {
  LyricSearchResponse? _response;
  bool _searching = true;
  bool _closed = false;
  bool _trackChanged = false;
  int _searchGeneration = 0;
  int _selectionGeneration = 0;
  String Function()? _searchError;
  String Function()? _operationError;
  String? _loadingCandidate;
  // Cache message sources, not already-translated text. Switching UI language
  // must not restart lyric lookup or change the captured track/provider IDs.
  final Map<String, String Function()> _candidateErrors = {};
  Listenable? _playbackListenable;

  String? _currentTrackPath() =>
      widget.currentTrackPath?.call() ??
      PlayService.instance.playbackService.nowPlaying?.path;

  @override
  void initState() {
    super.initState();
    _playbackListenable = widget.playbackListenable ??
        (widget.currentTrackPath == null
            ? PlayService.instance.playbackService
            : null);
    _playbackListenable?.addListener(_handlePlaybackChange);
    _trackChanged = _currentTrackPath() != widget.audio.path;
    unawaited(_search());
  }

  @override
  void didUpdateWidget(covariant LyricSourceDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackListenable != widget.playbackListenable ||
        oldWidget.currentTrackPath != widget.currentTrackPath) {
      _playbackListenable?.removeListener(_handlePlaybackChange);
      _playbackListenable = widget.playbackListenable ??
          (widget.currentTrackPath == null
              ? PlayService.instance.playbackService
              : null);
      _playbackListenable?.addListener(_handlePlaybackChange);
    }
    if (oldWidget.audio.path != widget.audio.path ||
        oldWidget.search != widget.search) {
      _selectionGeneration++;
      unawaited(_search());
    }
    _handlePlaybackChange();
  }

  void _handlePlaybackChange() {
    final changed = _currentTrackPath() != widget.audio.path;
    if (_trackChanged == changed) return;
    _selectionGeneration++;
    if (mounted) {
      setState(() {
        _trackChanged = changed;
        if (changed) _loadingCandidate = null;
      });
    }
  }

  Future<void> _search() async {
    final generation = ++_searchGeneration;
    _selectionGeneration++;
    if (mounted) {
      setState(() {
        _searching = true;
        _searchError = null;
        _operationError = null;
        _response = null;
        _loadingCandidate = null;
        _candidateErrors.clear();
      });
    }
    try {
      final result =
          await (widget.search ?? searchLyricCandidates)(widget.audio);
      if (!_isSearchCurrent(generation)) return;
      setState(() {
        _response = result;
        _searching = false;
      });
    } catch (_) {
      if (!_isSearchCurrent(generation)) return;
      setState(() {
        _searching = false;
        _searchError = () => ui("搜索歌词候选失败，请检查网络后重试。");
      });
    }
  }

  bool _isSearchCurrent(int generation) =>
      mounted && !_closed && generation == _searchGeneration;

  bool _isSelectionCurrent(int generation) =>
      mounted && !_closed && generation == _selectionGeneration;

  Future<void> _selectLocal() async {
    if (_trackChanged) return;
    final generation = ++_selectionGeneration;
    setState(() {
      _loadingCandidate = 'local';
      _operationError = null;
    });
    try {
      await (widget.persistSource ?? persistLyricSource)(
        widget.audio.path,
        LyricSource(LyricSourceType.local),
      );
      if (!_isSelectionCurrent(generation)) return;
      final applied = (widget.applyLocal ??
          PlayService.instance.lyricService.useLocalLyricForTrack)(
        widget.audio.path,
      );
      if (!applied) {
        _markTrackChanged(() => ui("歌曲已切换；已保存原歌曲的歌词来源，但没有应用到当前歌曲。"));
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (_isSelectionCurrent(generation)) {
        setState(() => _operationError = () => ui("保存本地歌词来源失败，旧设置已保留，请重试。"));
      }
    } finally {
      if (_isSelectionCurrent(generation)) {
        setState(() => _loadingCandidate = null);
      }
    }
  }

  Future<void> _selectCandidate(SongSearchResult candidate) async {
    if (_trackChanged || _loadingCandidate == candidate.identity) return;
    final generation = ++_selectionGeneration;
    setState(() {
      _loadingCandidate = candidate.identity;
      _operationError = null;
      _candidateErrors.remove(candidate.identity);
    });
    try {
      final lyric =
          await (widget.loadCandidate ?? getLyricForCandidate)(candidate);
      if (!_isSelectionCurrent(generation)) return;
      if (_currentTrackPath() != widget.audio.path) {
        _markTrackChanged(() => ui("歌曲已切换，旧歌曲的候选没有应用。"));
        return;
      }
      if (lyric == null || lyric.lines.isEmpty) {
        setState(() => _candidateErrors[candidate.identity] =
            () => ui("{0}未返回可用歌词，可选择其他候选或重试。", [ui(candidate.sourceLabel)]));
        return;
      }
      final source = _sourceFor(candidate);
      await (widget.persistSource ?? persistLyricSource)(
        widget.audio.path,
        source,
      );
      if (!_isSelectionCurrent(generation)) return;
      final applied = (widget.applyCandidate ??
          PlayService.instance.lyricService.useSpecificLyricForTrack)(
        widget.audio.path,
        lyric,
      );
      if (!applied) {
        _markTrackChanged(() => ui("歌曲已切换；已保存原歌曲的歌词来源，但没有应用到当前歌曲。"));
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (_isSelectionCurrent(generation)) {
        setState(() => _candidateErrors[candidate.identity] =
            () => ui("获取或保存歌词失败，旧设置已保留，请重试。"));
      }
    } finally {
      if (_isSelectionCurrent(generation)) {
        setState(() => _loadingCandidate = null);
      }
    }
  }

  void _markTrackChanged(String Function() message) {
    _selectionGeneration++;
    if (!mounted || _closed) return;
    setState(() {
      _trackChanged = true;
      _loadingCandidate = null;
      _operationError = message;
    });
  }

  LyricSource _sourceFor(SongSearchResult candidate) =>
      switch (candidate.source) {
        ResultSource.qq => LyricSource(
            LyricSourceType.qq,
            qqSongId: candidate.qqSongId,
            qqSongMid: candidate.qqSongMid,
          ),
        ResultSource.kugou => LyricSource(
            LyricSourceType.kugou,
            kugouSongHash: candidate.kugouSongHash,
          ),
        ResultSource.netease => LyricSource(
            LyricSourceType.netease,
            neteaseSongId: candidate.neteaseSongId,
          ),
        ResultSource.lrclib => LyricSource(
            LyricSourceType.lrclib,
            lrclibId: candidate.lrclibId,
          ),
      };

  bool _isCurrentCandidate(SongSearchResult candidate) {
    final configured = LYRIC_SOURCES[widget.audio.path];
    if (configured != null) {
      return configured.matches(
        candidateSource: switch (candidate.source) {
          ResultSource.qq => LyricSourceType.qq,
          ResultSource.kugou => LyricSourceType.kugou,
          ResultSource.netease => LyricSourceType.netease,
          ResultSource.lrclib => LyricSourceType.lrclib,
        },
        candidateQqSongId: candidate.qqSongId,
        candidateQqSongMid: candidate.qqSongMid,
        candidateKugouSongHash: candidate.kugouSongHash,
        candidateNeteaseSongId: candidate.neteaseSongId,
        candidateLrclibId: candidate.lrclibId,
      );
    }
    if (!widget.audio.isOnline) return false;
    return switch (candidate.source) {
      ResultSource.qq => widget.audio.onlineProvider == 'qq' &&
          ((widget.audio.onlineNumericId != null &&
                  widget.audio.onlineNumericId == candidate.qqSongId) ||
              widget.audio.onlineId == candidate.qqSongMid),
      ResultSource.netease => widget.audio.onlineProvider == 'netease' &&
          widget.audio.onlineId == candidate.neteaseSongId,
      ResultSource.kugou => false,
      ResultSource.lrclib => false,
    };
  }

  @override
  void dispose() {
    _closed = true;
    _searchGeneration++;
    _selectionGeneration++;
    _playbackListenable?.removeListener(_handlePlaybackChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final height =
        (MediaQuery.sizeOf(context).height - 48).clamp(320, 680).toDouble();
    return Dialog(
      child: SizedBox(
        width: 620,
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogTitle(
                ui("默认歌词"),
                style: Theme.of(context).textTheme.titleLarge,
                leading: const Icon(Symbols.lyrics),
                trailing: IconButton(
                  key: const ValueKey('lyric-source-close'),
                  tooltip: ui("关闭"),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Symbols.close),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                  child: CustomScrollView(
                key: const ValueKey('lyric-source-scroll'),
                slivers: [
                  SliverToBoxAdapter(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${widget.audio.displayTitle} · ${widget.audio.artist}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      if (_trackChanged)
                        _MessagePanel(
                          key: const ValueKey('lyric-source-track-changed'),
                          message: ui("当前播放歌曲已经改变。为避免歌词串歌，请关闭后从新歌曲重新选择。"),
                          color: scheme.errorContainer,
                        ),
                      if (_operationError != null)
                        _MessagePanel(
                          key: const ValueKey('lyric-source-operation-error'),
                          message: _operationError!(),
                          color: scheme.errorContainer,
                        ),
                      if ((AppSettings.instance.lyricApiUrl ?? '')
                          .trim()
                          .isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _MessagePanel(
                            key: const ValueKey('lyric-source-custom-api-note'),
                            message: ui(
                                "自动匹配会先尝试自定义歌词接口；接口结果没有平台歌曲 ID，因此不会出现在下面的内置平台候选中。"),
                            color: scheme.secondaryContainer,
                          ),
                        ),
                      if (widget.audio.isLocal) ...[
                        ListTile(
                          key: const ValueKey('lyric-source-local'),
                          enabled: !_trackChanged,
                          leading: const Icon(Symbols.folder),
                          title: Text(ui("使用本地歌词")),
                          subtitle: Text(ui("读取内嵌歌词或同目录同名 LRC 文件")),
                          trailing: _loadingCandidate == 'local'
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : LYRIC_SOURCES[widget.audio.path]?.source ==
                                      LyricSourceType.local
                                  ? const Icon(Symbols.check_circle)
                                  : null,
                          shape: AppShape.control,
                          onTap: _selectLocal,
                        ),
                        const Divider(),
                      ],
                    ],
                  )),
                  ..._buildResults(context),
                ],
              )),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildResults(BuildContext context) {
    final response = _response;
    if (_searching) {
      return [
        const SliverToBoxAdapter(
            child: Center(
          child: SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ))
      ];
    }
    if (_searchError != null) {
      return [
        SliverToBoxAdapter(
            child: _RetryState(message: _searchError!(), onRetry: _search))
      ];
    }
    if (response == null) {
      return [
        SliverToBoxAdapter(
            child: _RetryState(message: ui("候选状态不可用，请重试。"), onRetry: _search))
      ];
    }
    if (response.sourcesDisabled) {
      return [
        SliverToBoxAdapter(
            child: Center(child: Text(ui("当前没有可用的联网歌词来源，请检查歌词与歌源设置。"))))
      ];
    }

    final failureText = response.failures.entries
        .map((entry) => '${ui(entry.key.sourceLabel)}：${entry.value}')
        .join('\n');
    return [
      if (failureText.isNotEmpty)
        SliverToBoxAdapter(
            child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _MessagePanel(
            key: const ValueKey('lyric-source-partial-failure'),
            message: failureText,
            color: Theme.of(context).colorScheme.errorContainer,
            action: TextButton.icon(
              key: const ValueKey('lyric-source-retry'),
              onPressed: _search,
              icon: const Icon(Symbols.refresh),
              label: Text(ui("重试")),
            ),
          ),
        )),
      if (response.candidates.isEmpty)
        SliverToBoxAdapter(
            child: Center(
          child: Text(failureText.isEmpty
              ? ui("没有找到相关歌词候选，可检查歌曲标签后重试。")
              : ui("可用来源没有返回候选。")),
        ))
      else
        SliverList.builder(
          key: const ValueKey('lyric-source-candidates'),
          itemCount: response.candidates.length,
          itemBuilder: (context, index) =>
              _candidateTile(response.candidates[index]),
        ),
    ];
  }

  Widget _candidateTile(SongSearchResult candidate) {
    final current = _isCurrentCandidate(candidate);
    final loading = _loadingCandidate == candidate.identity;
    final error = _candidateErrors[candidate.identity];
    final details = [
      if (candidate.artists.trim().isNotEmpty) candidate.artists,
      if (candidate.album.trim().isNotEmpty) candidate.album,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        key: ValueKey('lyric-candidate-${candidate.identity}'),
        enabled: !_trackChanged,
        shape: AppShape.control,
        leading: CircleAvatar(
          child: Text(switch (candidate.source) {
            ResultSource.qq => 'QQ',
            ResultSource.netease => ui("网"),
            ResultSource.kugou => ui("酷"),
            ResultSource.lrclib => 'LR',
          }),
        ),
        title:
            Text(candidate.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (details.isNotEmpty)
              Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              ui("来源：{0} · 匹配 {1}%",
                  [ui(candidate.sourceLabel), (candidate.score * 100).round()]),
            ),
            if (error != null)
              Text(
                error(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
        trailing: loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : current
                ? Tooltip(
                    message: ui("当前使用"),
                    child: const Icon(Symbols.check_circle))
                : const Icon(Symbols.chevron_right),
        onTap: loading ? null : () => _selectCandidate(candidate),
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    super.key,
    required this.message,
    required this.color,
    this.action,
  });

  final String message;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppShape.controlRadius,
      ),
      child: Row(children: [
        Expanded(child: Text(message)),
        if (action != null) action!,
      ]),
    );
  }
}

class _RetryState extends StatelessWidget {
  const _RetryState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          key: const ValueKey('lyric-source-retry'),
          onPressed: onRetry,
          icon: const Icon(Symbols.refresh),
          label: Text(ui("重试")),
        ),
      ]),
    );
  }
}
