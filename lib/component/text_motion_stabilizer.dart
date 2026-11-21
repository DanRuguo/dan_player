import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

export 'package:desktop_lyric/component/text_pixel_snap.dart';

/// Uniform-width tabular digits prevent live counters, percentages and dB
/// readouts from shifting horizontally when digits change.
const List<FontFeature> tabularFiguresFeatures = <FontFeature>[
  FontFeature.tabularFigures(),
];

/// Locks a child subtree into a single 1:1 raster texture while an ancestor
/// scales it (for example a menu open rebound), preventing Skia/DirectWrite
/// from re-hinting individual glyphs across discrete scale buckets.
///
/// Place inside frosted surfaces so any outer [BackdropFilter] stays intact.
/// Automatically releases the raster texture on the resting frame and forwards
/// hit-testing, focus and semantics transparently.
class CrispScaleSnapshot extends StatefulWidget {
  const CrispScaleSnapshot({
    super.key,
    required this.active,
    required this.child,
  });

  final ValueListenable<bool> active;
  final Widget child;

  @override
  State<CrispScaleSnapshot> createState() => _CrispScaleSnapshotState();
}

class _CrispScaleSnapshotState extends State<CrispScaleSnapshot> {
  late final SnapshotController _controller = SnapshotController(
    allowSnapshotting: widget.active.value,
  );

  @override
  void initState() {
    super.initState();
    widget.active.addListener(_sync);
  }

  @override
  void didUpdateWidget(CrispScaleSnapshot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.active, widget.active)) {
      oldWidget.active.removeListener(_sync);
      widget.active.addListener(_sync);
    }
    _sync();
  }

  void _sync() {
    final allow = widget.active.value;
    if (_controller.allowSnapshotting != allow) {
      _controller.allowSnapshotting = allow;
    }
  }

  @override
  void dispose() {
    widget.active.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SnapshotWidget(
        controller: _controller,
        mode: SnapshotMode.permissive,
        autoresize: true,
        child: widget.child,
      );
}
