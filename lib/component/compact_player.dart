import 'package:dan_player/app_settings.dart';
import 'package:dan_player/app_shutdown.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/compact_lyric_view.dart';
import 'package:dan_player/component/window_chrome_theme.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/player_shortcut_preferences.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/window_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_lyric/ui_language.dart';

/// The live adapter. Mount only in mini mode; it never creates another player.
class CompactPlayer extends StatefulWidget {
  const CompactPlayer({
    super.key,
    this.controller,
  });

  final WindowModeController? controller;

  @override
  State<CompactPlayer> createState() => _CompactPlayerState();
}

class _CompactPlayerState extends State<CompactPlayer> {
  Object? _coverKey;
  Future<ImageProvider?>? _coverFuture;

  WindowModeController get _controller =>
      widget.controller ?? WindowModeController.instance;

  Future<void> _windowAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, trace) {
      LOGGER.w('[compact window] $error', stackTrace: trace);
      if (!mounted) return;
      showAppNotice(
        error is WindowModeException ? error.toString() : ui("窗口操作失败，请重试"),
        context: context,
        kind: AppNoticeKind.error,
      );
    }
  }

  CompactPlayerView _view({
    String title = 'Dan Player',
    String? artist,
    Object? trackIdentity,
    ImageProvider? cover,
    Future<Lyric?>? lyricFuture,
    double position = 0,
    double duration = 0,
    bool isPlaying = false,
    bool isBuffering = false,
    VoidCallback? onPrevious,
    VoidCallback? onPlayPause,
    VoidCallback? onNext,
    ValueChanged<double>? onSeek,
  }) =>
      CompactPlayerView(
        title: title,
        artist: artist,
        trackIdentity: trackIdentity,
        cover: cover,
        lyricFuture: lyricFuture,
        position: position,
        duration: duration,
        isPlaying: isPlaying,
        isBuffering: isBuffering,
        isPinned: _controller.isPinned,
        isBusy: _controller.isBusy,
        onPrevious: onPrevious,
        onPlayPause: onPlayPause,
        onNext: onNext,
        onSeek: onSeek,
        onRestore: () => _windowAction(_controller.exit),
        onTogglePinned: () => _windowAction(_controller.togglePinned),
        onMinimize: () => _windowAction(windowManager.minimize),
        onClose: requestAppClose,
        onDragStart: () => _windowAction(windowManager.startDragging),
      );

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => PlaybackReadyBuilder(
        waitingBuilder: (_) => _view(),
        readyBuilder: (context) {
          final playback = PlayService.instance.playbackService;
          final lyricService = PlayService.instance.lyricService;
          return ListenableBuilder(
            listenable: Listenable.merge([
              playback,
              playback.isBuffering,
              playback.playlist,
              lyricService,
            ]),
            builder: (context, _) {
              final audio = playback.nowPlaying;
              final target = ArtworkSize.forDisplay(
                logicalWidth: 80,
                logicalHeight: 80,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              );
              final coverKey = (
                audio?.path,
                audio?.modified,
                audio?.artworkUrl,
                AudioLibrary.revision,
                target
              );
              if (_coverKey != coverKey) {
                _coverKey = coverKey;
                _coverFuture = audio?.artworkForSize(target);
              }
              return FutureBuilder<ImageProvider?>(
                key: ValueKey(audio?.path),
                future: _coverFuture,
                builder: (context, cover) => StreamBuilder<PlayerState>(
                  stream: playback.playerStateStream,
                  initialData: playback.playerState,
                  builder: (context, state) => StreamBuilder<double>(
                    stream: playback.positionStream,
                    initialData: playback.position,
                    builder: (context, position) {
                      final playing = state.data == PlayerState.playing;
                      return _view(
                        title: audio?.displayTitle ?? 'Dan Player',
                        artist: audio?.artist ?? ui("尚未选择歌曲"),
                        // Every load gets a new lyric future, even when the next
                        // queue occurrence has the same audio path. Cancelling a
                        // pending seek also on a source change is conservative:
                        // an old drag must never seek the newly loaded session.
                        trackIdentity: audio == null
                            ? null
                            : (audio.path, lyricService.currLyricFuture),
                        cover: cover.data,
                        lyricFuture: lyricService.currLyricFuture,
                        position: position.data ?? 0,
                        duration: playback.length,
                        isPlaying: playing,
                        isBuffering: playback.isBuffering.value,
                        onPrevious: playback.playlist.value.isEmpty
                            ? null
                            : playback.lastAudio,
                        onPlayPause: audio == null
                            ? null
                            : playing
                                ? playback.pause
                                : state.data == PlayerState.completed
                                    ? playback.playAgain
                                    : playback.start,
                        onNext: playback.playlist.value.isEmpty
                            ? null
                            : playback.nextAudio,
                        onSeek: audio == null ? null : playback.seek,
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Presentation-only compact controls: safe to render without BASS or an HWND.
///
/// Its backing stays transparent; the window host owns the paired opaque mini
/// surface. Native drag targets and backing never participate in animations.
/// Transport is centered on the whole window, independent of the cover/title.
/// Large text may scroll the information area, never shrink or hide controls.
class CompactPlayerView extends StatefulWidget {
  const CompactPlayerView({
    super.key,
    this.title = 'Dan Player',
    this.artist,
    this.trackIdentity,
    this.cover,
    this.lyricFuture,
    this.position = 0,
    this.duration = 0,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isPinned = false,
    this.isBusy = false,
    this.onPrevious,
    this.onPlayPause,
    this.onNext,
    this.onSeek,
    this.onRestore,
    this.onTogglePinned,
    this.onMinimize,
    this.onClose,
    this.onDragStart,
  });

  final String title;
  final String? artist;
  final Object? trackIdentity;
  final ImageProvider? cover;
  final Future<Lyric?>? lyricFuture;
  final double position;
  final double duration;
  final bool isPlaying;
  final bool isBuffering;
  final bool isPinned;
  final bool isBusy;
  final VoidCallback? onPrevious;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onRestore;
  final VoidCallback? onTogglePinned;
  final VoidCallback? onMinimize;
  final VoidCallback? onClose;
  final VoidCallback? onDragStart;

  @override
  State<CompactPlayerView> createState() => _CompactPlayerViewState();
}

class _CompactPlayerViewState extends State<CompactPlayerView>
    with WidgetsBindingObserver {
  double? _dragPosition;
  Object? _dragTrackIdentity;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  double get _duration =>
      widget.duration.isFinite && widget.duration > 0 ? widget.duration : 0;

  double get _position {
    final value = _dragPosition ?? widget.position;
    return value.isFinite ? value.clamp(0, _duration).toDouble() : 0;
  }

  bool get _canSeek =>
      widget.onSeek != null && _duration > 0 && !widget.isBuffering;

  @override
  void didUpdateWidget(CompactPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackIdentity != widget.trackIdentity || !_canSeek) {
      _dragPosition = null;
      _dragTrackIdentity = null;
      _dragging = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    // Mini is an opaque content panel, not exposed native window chrome. Pair
    // foregrounds with its host's Theme.surface, including a HC native fallback
    // whose chrome foreground may differ from this independent content theme.
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: IconTheme(
        data: IconThemeData(color: scheme.primary, size: 20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            children: [
              _header(scheme),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    key: const ValueKey('compact-content-scroll'),
                    primary: false,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AppEntrance(
                            identity: 'compact-track-content',
                            child: _track(scheme),
                          ),
                          const SizedBox(height: 6),
                          CompactLyricView(
                            trackIdentity: widget.trackIdentity,
                            lyricFuture: widget.lyricFuture,
                            position: _dragPosition ?? widget.position,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              AppEntrance(
                identity: 'compact-transport',
                order: 1,
                child: _transport(scheme),
              ),
              AppEntrance(
                identity: 'compact-progress',
                order: 2,
                child: _progress(scheme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    final restore = widget.isBusy ? null : widget.onRestore;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: MouseRegion(
              cursor: widget.onDragStart == null || widget.isBusy
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.move,
              child: GestureDetector(
                key: const ValueKey('compact-drag-region'),
                behavior: HitTestBehavior.opaque,
                onPanStart: widget.onDragStart == null || widget.isBusy
                    ? null
                    : (_) => widget.onDragStart!(),
                // DragToMoveArea would maximize this compact window on double
                // tap. Restore the full layout through the controller instead.
                onDoubleTap: restore,
                child: SizedBox.expand(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AppEntrance(
                      identity: 'compact-window-title',
                      child: Text(
                        ui("迷你播放器"),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: scheme.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _button(
            key: 'compact-restore',
            tooltip: ui("还原完整播放器（{0}）", [
              AppSettings.instance.shortcuts.value
                  .chordFor(PlayerCommand.toggleMini)
                  .label
            ]),
            icon: Icons.open_in_full,
            onPressed: restore,
          ),
          _button(
            key: 'compact-pin',
            tooltip: widget.isPinned ? ui("取消置顶") : ui("窗口置顶"),
            icon: widget.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            onPressed: widget.isBusy ? null : widget.onTogglePinned,
            selected: widget.isPinned,
          ),
          _button(
            key: 'compact-minimize',
            tooltip: ui("最小化"),
            icon: Icons.remove,
            onPressed: widget.isBusy ? null : widget.onMinimize,
          ),
          _button(
            key: 'compact-close',
            tooltip: ui("退出播放器"),
            icon: Icons.close,
            onPressed: widget.isBusy ? null : widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _track(ColorScheme scheme) {
    final textScaler = MediaQuery.textScalerOf(context);
    final textHeight =
        textScaler.scale(16) * 1.15 + 4 + textScaler.scale(13) * 1.15;
    return SizedBox(
      height: textHeight > 80 ? textHeight : 80,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox.square(
              dimension: 80,
              child: ClipRRect(
                borderRadius: AppShape.controlRadius,
                child: widget.cover == null
                    ? _coverPlaceholder(scheme)
                    : Image(
                        image: widget.cover!,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, __, ___) => _coverPlaceholder(scheme),
                      ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Tooltip(
                  message: widget.title,
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: scheme.primary,
                        fontSize: 16,
                        height: 1.15,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 4),
                Tooltip(
                  message: widget.artist ?? ui('尚未选择歌曲'),
                  child: Text(
                    widget.artist ?? ui('尚未选择歌曲'),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: scheme.onSurface
                            .withValues(alpha: _highContrast ? 1 : .72),
                        fontSize: 13,
                        height: 1.15),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _highContrast =>
      (MediaQuery.maybeHighContrastOf(context) ?? false) ||
      context
              .dependOnInheritedWidgetOfExactType<WindowChromeTheme>()
              ?.foreground !=
          null;

  bool get _reduced {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        features.disableAnimations ||
        features.reduceMotion ||
        !TickerMode.valuesOf(context).enabled;
  }

  Widget _transport(ColorScheme scheme) => SizedBox(
        key: const ValueKey('compact-transport-region'),
        height: 52,
        width: double.infinity,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _button(
              key: 'compact-previous',
              tooltip: ui("上一首"),
              icon: Icons.skip_previous,
              onPressed: widget.onPrevious,
            ),
            const SizedBox(width: 20),
            SizedBox.square(
              dimension: 52,
              child: IconButton.filled(
                key: const ValueKey('compact-play-pause'),
                tooltip: widget.isBuffering
                    ? ui("正在缓冲")
                    : widget.isPlaying
                        ? ui("暂停")
                        : ui("播放"),
                onPressed: widget.isBuffering ? null : widget.onPlayPause,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(52),
                  padding: EdgeInsets.zero,
                  shape: AppShape.control,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  animationDuration: _reduced ? Duration.zero : AppMotion.quick,
                ),
                icon: widget.isBuffering
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          // A static loading ring communicates state without
                          // running an infinite animation in reduced motion.
                          value: _reduced ? .72 : null,
                          strokeWidth: 2,
                          color: scheme.onPrimaryContainer,
                        ),
                      )
                    : Icon(
                        widget.isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 28,
                      ),
              ),
            ),
            const SizedBox(width: 20),
            _button(
              key: 'compact-next',
              tooltip: ui("下一首"),
              icon: Icons.skip_next,
              onPressed: widget.onNext,
            ),
          ],
        ),
      );

  Widget _coverPlaceholder(ColorScheme scheme) => ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.music_note, size: 32, color: scheme.onSurfaceVariant),
      );

  Widget _progress(ColorScheme scheme) {
    final timeStyle = TextStyle(
      color: scheme.onSurface.withValues(alpha: _highContrast ? 1 : .8),
      fontSize: 12,
      height: 1.1,
    );
    final timeWidth =
        (MediaQuery.textScalerOf(context).scale(12) * 4.2).clamp(52.0, 96.0);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          SizedBox(
            width: timeWidth,
            child: Tooltip(
              message: _timeText(_position),
              child: Text(_timeText(_position),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: timeStyle),
            ),
          ),
          Expanded(
            child: Semantics(
              label: ui("播放进度"),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 18),
                ),
                child: Slider(
                  key: const ValueKey('compact-progress-slider'),
                  value: _position,
                  max: _duration > 0 ? _duration : 1,
                  semanticFormatterCallback: (value) =>
                      '${_timeText(value)} / ${_timeText(_duration)}',
                  onChanged: _canSeek
                      ? (value) {
                          if (_dragging) {
                            setState(() => _dragPosition = value);
                          }
                        }
                      : null,
                  onChangeStart: _canSeek
                      ? (value) => setState(() {
                            _dragging = true;
                            _dragTrackIdentity = widget.trackIdentity;
                            _dragPosition = value;
                          })
                      : null,
                  onChangeEnd: _canSeek
                      ? (value) {
                          final shouldSeek = _dragging &&
                              _dragTrackIdentity == widget.trackIdentity;
                          setState(() {
                            _dragging = false;
                            _dragTrackIdentity = null;
                            _dragPosition = null;
                          });
                          if (shouldSeek) widget.onSeek!(value);
                        }
                      : null,
                ),
              ),
            ),
          ),
          SizedBox(
            width: timeWidth,
            child: Tooltip(
              message: _timeText(_duration),
              child: Text(_timeText(_duration),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: timeStyle),
            ),
          ),
        ],
      ),
    );
  }

  Widget _button({
    required String key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    double? iconSize,
    bool selected = false,
  }) =>
      SizedBox.square(
        dimension: 44,
        child: IconButton(
          key: ValueKey(key),
          tooltip: tooltip,
          iconSize: iconSize,
          isSelected: selected,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(44),
            padding: EdgeInsets.zero,
            shape: AppShape.control,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            animationDuration: _reduced ? Duration.zero : AppMotion.quick,
            foregroundColor: selected
                ? Theme.of(context).colorScheme.onSecondaryContainer
                : Theme.of(context).colorScheme.primary,
            backgroundColor: selected
                ? Theme.of(context).colorScheme.secondaryContainer
                : Colors.transparent,
          ),
          icon: AppEntrance(identity: key, child: Icon(icon)),
        ),
      );
}

String _timeText(double seconds) {
  final total = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
  final hours = total ~/ 3600;
  final minutes = (total ~/ 60) % 60;
  final remainder = total % 60;
  final suffix =
      '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  return hours == 0 ? suffix : '$hours:$suffix';
}
