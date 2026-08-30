import 'dart:async';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';

class RectangleProgressIndicator extends StatefulWidget {
  const RectangleProgressIndicator({
    super.key,
    required this.size,
    required this.child,
    this.positionStream,
    this.lengthProvider,
  });

  final Size size;
  final Widget child;

  /// Test seams also make this component reusable without creating another
  /// player. Production callers leave both null and use the single PlayService.
  final Stream<double>? positionStream;
  final double Function()? lengthProvider;

  @override
  State<RectangleProgressIndicator> createState() =>
      _RectangleProgressIndicatorState();
}

class _RectangleProgressIndicatorState
    extends State<RectangleProgressIndicator> {
  /// [positionStream] 的订阅，在dispose取消订阅
  late StreamSubscription<double> subscription;

  /// position / length, [0, 1]
  final progress = ValueNotifier<double>(0);
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    subscription = (widget.positionStream ??
            PlayService.instance.playbackService.positionStream)
        .listen((event) {
      if (_disposed) return;
      final length = widget.lengthProvider?.call() ??
          PlayService.instance.playbackService.length;
      progress.value = length <= 0 ? 0 : (event / length).clamp(0.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: widget.size,
      painter: RectangleProgressPainter(progress: progress, scheme: scheme),
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    subscription.cancel();
    progress.dispose();
    super.dispose();
  }
}

class RectangleProgressPainter extends CustomPainter {
  /// position / length, [0, 1]
  final ValueNotifier<double> progress;

  final ColorScheme scheme;

  RectangleProgressPainter({required this.progress, required this.scheme})
      : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final progressPainter = Paint();
    progressPainter.color = scheme.primary.withValues(alpha: 0.16);

    final trackPainter = Paint();
    trackPainter.color = scheme.surfaceContainerHighest.withValues(alpha: 0.42);

    /// 进度条背景
    canvas.drawRect(
      Rect.fromLTWH(0.0, 0.0, size.width, size.height),
      trackPainter,
    );

    /// 进度
    canvas.drawRect(
      Rect.fromLTWH(0.0, 0.0, size.width * progress.value, size.height),
      progressPainter,
    );
  }

  @override
  bool shouldRepaint(RectangleProgressPainter oldDelegate) => false;

  @override
  bool shouldRebuildSemantics(RectangleProgressPainter oldDelegate) => false;
}
