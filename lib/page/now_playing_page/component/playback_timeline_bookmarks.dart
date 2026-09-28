import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Read-only projection of existing bookmarks. The timeline never creates a
/// second store, scans audio, or rewrites bookmarks when a track is unavailable.
class PlaybackTimelineBookmarks extends StatefulWidget {
  const PlaybackTimelineBookmarks({
    super.key,
    required this.audio,
    required this.builder,
    this.hidden,
    this.store,
  });
  final Audio? audio;
  final Widget Function(List<PlaybackBookmark>) builder;
  final ValueListenable<bool>? hidden;
  final PlaybackBookmarkStore? store;
  @override
  State<PlaybackTimelineBookmarks> createState() =>
      _PlaybackTimelineBookmarksState();
}

class _PlaybackTimelineBookmarksState extends State<PlaybackTimelineBookmarks>
    with WidgetsBindingObserver {
  Object? _request;
  Object? _track;
  List<PlaybackBookmark> _items = const [];
  int _generation = 0;
  bool _treeVisible = true;
  AppLifecycleState? _lifecycle;
  bool get _visible =>
      _treeVisible &&
      widget.hidden?.value != true &&
      (_lifecycle == null ||
          _lifecycle == AppLifecycleState.resumed ||
          _lifecycle == AppLifecycleState.inactive);

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    PlaybackBookmarkStore.changes.addListener(_changed);
    widget.hidden?.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _treeVisible = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(PlaybackTimelineBookmarks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hidden, widget.hidden)) {
      oldWidget.hidden?.removeListener(_changed);
      widget.hidden?.addListener(_changed);
    }
    _sync();
  }

  void _changed() {
    if (mounted) setState(_sync);
  }

  void _sync() {
    final audio = widget.audio;
    final track = (audio?.path, audio?.stableTrackId, widget.store);
    final request = (
      audio?.path,
      audio?.stableTrackId,
      _visible,
      PlaybackBookmarkStore.changes.value,
      widget.store
    );
    if (request == _request) return;
    _request = request;
    final generation = ++_generation;
    if (_track != track || !_visible || audio?.isLocal != true) {
      _items = const [];
    }
    _track = track;
    // Track changes clear before I/O, never flash the previous song's marks.
    if (audio == null || !_visible || !audio.isLocal) return;
    unawaited((() async {
      try {
        final store = widget.store ?? await PlaybackBookmarkStore.instance;
        final items = await store.forTrack(audio.path,
            stableTrackId: audio.stableTrackId);
        if (mounted && generation == _generation) {
          setState(() => _items = items);
        }
      } catch (_) {
        // The existing bookmark dialog owns recovery/retry messages. An
        // optional read-only timeline must not block ordinary playback.
        if (mounted && generation == _generation) {
          setState(() => _items = const []);
        }
      }
    })());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _changed();
  }

  @override
  void dispose() {
    _generation++;
    PlaybackBookmarkStore.changes.removeListener(_changed);
    widget.hidden?.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_items);
}
