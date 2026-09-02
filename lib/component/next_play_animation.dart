import 'dart:math' as math;

import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Coordinates the short, top-most artwork flight used by “Play next”.
///
/// The queue button registers [targetKey]. Song rows pass the already-mounted
/// artwork context, so the animation does not add a GlobalKey/RepaintBoundary
/// to every visible song. A global pointer route observes later interactions
/// without blocking their hit test.
class NextPlayAnimation {
  NextPlayAnimation._();

  static final GlobalKey targetKey =
      GlobalKey(debugLabel: 'next-play-queue-target');

  static OverlayEntry? _entry;
  static int _generation = 0;
  static bool _pointerRouteRegistered = false;

  static bool fly({
    required BuildContext context,
    required BuildContext sourceContext,
    required Audio audio,
  }) {
    cancel();
    if (!context.mounted || !sourceContext.mounted) return false;
    if (MediaQuery.maybeOf(context)?.disableAnimations == true) return false;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayBox = overlay?.context.findRenderObject();
    final sourceBox = sourceContext.findRenderObject();
    final targetBox = targetKey.currentContext?.findRenderObject();
    if (overlay == null ||
        overlayBox is! RenderBox ||
        sourceBox is! RenderBox ||
        targetBox is! RenderBox ||
        !overlayBox.hasSize ||
        !sourceBox.hasSize ||
        !targetBox.hasSize) {
      return false;
    }

    Rect localRect(RenderBox box) {
      final topLeft = overlayBox.globalToLocal(box.localToGlobal(Offset.zero));
      return topLeft & box.size;
    }

    final source = localRect(sourceBox);
    final target = localRect(targetBox);
    if (!source.isFinite ||
        !target.isFinite ||
        source.isEmpty ||
        target.isEmpty) {
      return false;
    }

    final generation = ++_generation;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => _NextPlayFlight(
        key: ValueKey('next-play-flight-$generation'),
        source: source,
        target: target,
        audio: audio,
        onFinished: () => _finish(generation),
      ),
    );
    try {
      overlay.insert(entry);
    } catch (_) {
      entry.dispose();
      return false;
    }
    _entry = entry;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointer);
    _pointerRouteRegistered = true;
    return true;
  }

  static void _handlePointer(PointerEvent event) {
    if (event is PointerDownEvent) cancel();
  }

  static void _finish(int generation) {
    if (generation != _generation) return;
    _removeCurrent();
  }

  /// Immediately removes an in-flight cover. Safe to call when none exists.
  static void cancel() {
    _generation++;
    _removeCurrent();
  }

  static void _removeCurrent() {
    if (_pointerRouteRegistered) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_handlePointer);
      _pointerRouteRegistered = false;
    }
    final entry = _entry;
    _entry = null;
    if (entry == null) return;
    // `mounted` remains false between insert() and the first overlay build,
    // even though the entry already belongs to the Overlay and must be removed.
    entry.remove();
    entry.dispose();
  }
}

/// Quadratic path used by the flight. Kept public for deterministic geometry
/// tests; callers normally use [NextPlayAnimation.fly].
Offset nextPlayFlightPosition(Rect source, Rect target, double progress) {
  final t = progress.clamp(0.0, 1.0);
  final start = source.center;
  final end = target.center;
  final distance = (end - start).distance;
  final lift = math.min(150.0, math.max(44.0, distance * .24));
  final control = Offset(
    start.dx + (end.dx - start.dx) * .38,
    // Keep the arc inside the root overlay when a source sits near the title
    // bar. The asymmetric x control still guarantees a curve in that case.
    math.max(8.0, math.min(start.dy, end.dy) - lift),
  );
  final inverse = 1 - t;
  return Offset(
    inverse * inverse * start.dx +
        2 * inverse * t * control.dx +
        t * t * end.dx,
    inverse * inverse * start.dy +
        2 * inverse * t * control.dy +
        t * t * end.dy,
  );
}

class _NextPlayFlight extends StatefulWidget {
  const _NextPlayFlight({
    super.key,
    required this.source,
    required this.target,
    required this.audio,
    required this.onFinished,
  });

  final Rect source;
  final Rect target;
  final Audio audio;
  final VoidCallback onFinished;

  @override
  State<_NextPlayFlight> createState() => _NextPlayFlightState();
}

class _NextPlayFlightState extends State<_NextPlayFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 430),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onFinished();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final startSize = math.max(
      34.0,
      math.min(widget.source.width, widget.source.height),
    );
    final artwork = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppShape.smallRadius,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: .24),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppShape.smallRadius,
        child: AudioArtwork(
          audio: widget.audio,
          size: startSize,
          placeholder: ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Icon(
              Icons.music_note_rounded,
              color: scheme.primary,
            ),
          ),
        ),
      ),
    );
    return IgnorePointer(
      key: const ValueKey('next-play-flight-surface'),
      child: AnimatedBuilder(
        animation: _controller,
        child: artwork,
        builder: (context, child) {
          // Ease-in produces the requested slow departure and fast arrival.
          final progress = Curves.easeInCubic.transform(_controller.value);
          final center = nextPlayFlightPosition(
            widget.source,
            widget.target,
            progress,
          );
          final endSize = math.max(
            8.0,
            math.min(widget.target.width, widget.target.height) * .18,
          );
          final size = startSize + (endSize - startSize) * progress;
          return Stack(children: [
            Positioned(
              left: center.dx - size / 2,
              top: center.dy - size / 2,
              width: size,
              height: size,
              child: Opacity(
                opacity: (1 - progress * .42).clamp(0.0, 1.0),
                child: child,
              ),
            ),
          ]);
        },
      ),
    );
  }
}
