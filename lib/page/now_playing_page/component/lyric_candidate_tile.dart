import 'dart:async';

import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/compact_lyric_frame.dart';
import 'package:dan_player/lyric/krc.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:desktop_lyric/app_motion.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class LyricCandidateTile extends StatefulWidget {
  const LyricCandidateTile({
    super.key,
    required this.candidate,
    required this.audio,
    required this.positionStream,
    required this.readPosition,
    required this.load,
    required this.release,
    required this.retryRevision,
    required this.previewGeneration,
    required this.versionWarning,
    required this.enabled,
    required this.current,
    required this.loading,
    required this.error,
    required this.onTap,
  });

  final SongSearchResult candidate;
  final Audio audio;
  final Stream<double> positionStream;
  final double Function() readPosition;
  final Future<Lyric?> Function(SongSearchResult candidate) load;
  final void Function(String identity) release;
  final int retryRevision;
  final int previewGeneration;
  final bool versionWarning;
  final bool enabled;
  final bool current;
  final bool loading;
  final String Function()? error;
  final VoidCallback onTap;

  @override
  State<LyricCandidateTile> createState() => _LyricCandidateTileState();
}

class _LyricCandidateTileState extends State<LyricCandidateTile>
    with WidgetsBindingObserver {
  Future<Lyric?>? _lyricFuture;
  CompactLyricTimeline? _timeline;
  Lyric? _lyric;
  bool _loadFinished = false;
  String _previewText = '';
  bool _previewIsMessage = false;
  StreamSubscription<double>? _positionSubscription;
  ValueListenable<RenderingPreferences>? _preferences;
  AppLifecycleState? _lifecycle;
  bool _treeVisible = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    _load();
  }

  void _load() {
    final generation = ++_loadGeneration;
    _lyric = null;
    _timeline = null;
    _loadFinished = false;
    if (!widget.enabled) {
      _lyricFuture = null;
      _previewText = '';
      _previewIsMessage = false;
      return;
    }
    _previewText = '正在加载歌词…';
    _previewIsMessage = true;
    _lyricFuture = widget.load(widget.candidate);
    _lyricFuture!.then((lyric) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _lyric = lyric;
        _loadFinished = true;
        _timeline = lyric == null || lyric.lines.isEmpty
            ? null
            : CompactLyricTimeline(lyric);
        final preview = _timeline == null
            ? (text: '无法预览歌词，点选可重试。', message: true)
            : _previewAt(widget.readPosition());
        _previewText = preview.text;
        _previewIsMessage = preview.message;
      });
      _syncPositionSubscription();
    }, onError: (Object _, StackTrace __) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadFinished = true;
        _previewText = '无法预览歌词，点选可重试。';
        _previewIsMessage = true;
      });
    });
  }

  ({String text, bool message}) _previewAt(double seconds) {
    final timeline = _timeline;
    if (timeline == null) {
      return (text: '无法预览歌词，点选可重试。', message: true);
    }
    if (!seconds.isFinite) seconds = 0;
    final offsetMs =
        LyricDocumentStore.instance.forAudio(widget.audio)?.offsetMs ?? 0;
    final frame = timeline
        .at(Duration(milliseconds: (seconds * 1000).round() - offsetMs));
    // Before the first timestamp, show the actual first lyric as context.
    if (frame.status == CompactLyricStatus.upcoming &&
        frame.secondary.isNotEmpty) {
      return (text: frame.secondary, message: false);
    }
    return (
      text: frame.primary,
      message: frame.status != CompactLyricStatus.active,
    );
  }

  void _updatePosition(double seconds) {
    if (!mounted || _timeline == null) return;
    final next = _previewAt(seconds);
    if (next.text != _previewText || next.message != _previewIsMessage) {
      setState(() {
        _previewText = next.text;
        _previewIsMessage = next.message;
      });
    }
  }

  void _syncPositionSubscription() {
    final active = widget.enabled &&
        _timeline != null &&
        (_preferences?.value ?? const RenderingPreferences())
            .allowsVisualUpdates(
                lifecycle: _lifecycle, treeVisible: _treeVisible);
    if (!active) {
      _positionSubscription?.cancel();
      _positionSubscription = null;
      return;
    }
    if (_positionSubscription != null) return;
    _updatePosition(widget.readPosition());
    _positionSubscription = widget.positionStream.listen(_updatePosition);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final preferences = RenderingPreferencesScope.listenableOf(context);
    if (!identical(preferences, _preferences)) {
      _preferences?.removeListener(_syncPositionSubscription);
      _preferences = preferences..addListener(_syncPositionSubscription);
    }
    _treeVisible = TickerMode.valuesOf(context).enabled;
    _syncPositionSubscription();
  }

  @override
  void didUpdateWidget(covariant LyricCandidateTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.candidate.identity != widget.candidate.identity) {
      oldWidget.release(oldWidget.candidate.identity);
    }
    if (oldWidget.candidate.identity != widget.candidate.identity ||
        oldWidget.retryRevision != widget.retryRevision ||
        oldWidget.previewGeneration != widget.previewGeneration) {
      _positionSubscription?.cancel();
      _positionSubscription = null;
      _load();
    } else if (oldWidget.positionStream != widget.positionStream) {
      _positionSubscription?.cancel();
      _positionSubscription = null;
      _syncPositionSubscription();
    } else if (oldWidget.audio.stableTrackId != widget.audio.stableTrackId) {
      _updatePosition(widget.readPosition());
    } else if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled && _lyricFuture == null) {
        _load();
      } else {
        _syncPositionSubscription();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _syncPositionSubscription();
  }

  @override
  void dispose() {
    _loadGeneration++;
    widget.release(widget.candidate.identity);
    _preferences?.removeListener(_syncPositionSubscription);
    _positionSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String get _format => switch (_lyric) {
        Krc() => 'KRC',
        Qrc() => 'QRC/YRC',
        Lrc() => 'LRC',
        PlainLyric() => 'TXT',
        null => _loadFinished ? '?' : '…',
        _ => '?',
      };

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final metadata = [
      widget.candidate.title.trim(),
      widget.candidate.artists.trim(),
      widget.candidate.album.trim(),
    ].where((value) => value.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        key: ValueKey('lyric-candidate-${widget.candidate.identity}'),
        enabled: widget.enabled,
        shape: AppShape.control,
        leading: Tooltip(
          message: _format == '…'
              ? ui('正在识别歌词格式')
              : _format == '?'
                  ? ui('歌词格式未知')
                  : _format,
          child: Container(
            width: 56,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: AppShape.controlRadius,
            ),
            child: Text(_format,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontSize: _format.length > 5 ? 10 : null,
                    )),
          ),
        ),
        title: Tooltip(
          message: metadata,
          child: Text(metadata,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall),
        ),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.candidate.scoreVerified
                  ? ui('来源：{0} · 匹配 {1}%', [
                      ui(widget.candidate.sourceLabel),
                      widget.candidate.matchPercent
                    ])
                  : ui('来源：{0} · 匹配度未知，仅供手动选择',
                      [ui(widget.candidate.sourceLabel)]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _previewIsMessage ? ui(_previewText) : _previewText,
              key: ValueKey('lyric-preview-${widget.candidate.identity}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                  ),
            ),
            if (widget.versionWarning)
              Text(ui('版本可能不同：当前歌曲为短版，候选未注明短版。'),
                  style: Theme.of(context).textTheme.bodySmall),
            if (widget.error != null)
              Text(widget.error!(), style: TextStyle(color: scheme.error)),
          ],
        ),
        trailing: widget.loading
            ? SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: AppMotion.enabled(context, MotionKind.feedback)
                        ? null
                        : .7),
              )
            : widget.current
                ? Tooltip(
                    message: ui('当前使用'),
                    child: const Icon(Symbols.check_circle))
                : const Icon(Symbols.chevron_right),
        onTap: widget.loading ? null : widget.onTap,
      ),
    );
  }
}
