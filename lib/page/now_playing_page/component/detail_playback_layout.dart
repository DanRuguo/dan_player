import 'dart:math' as math;

import 'package:dan_player/component/app_scrollbar.dart';
import 'package:flutter/material.dart';

/// Retain an actual lyrics/artwork viewport at short window heights. Controls
/// keep their natural height in normal windows, and only their overflow scrolls.
class DetailPlaybackLayout extends StatefulWidget {
  const DetailPlaybackLayout(
      {super.key, required this.display, required this.controls});
  final Widget display, controls;
  @override
  State<DetailPlaybackLayout> createState() => _DetailPlaybackLayoutState();
}

class _DetailPlaybackLayoutState extends State<DetailPlaybackLayout> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        // The artwork view has a 20px title, a 14px artist line and 16px
        // spacing before its flexible cover. Reserve their scaled height too.
        final header = MediaQuery.textScalerOf(context).scale(34) * 1.5 + 24;
        final reserve = math.min(
            math.max(0, constraints.maxHeight - 64), math.max(100.0, header));
        return Column(children: [
          Expanded(child: widget.display),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: math.max(0, constraints.maxHeight - reserve)),
            child: AppScrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                key: const ValueKey('detail-playback-controls-scroll'),
                controller: _scroll,
                primary: false,
                child: widget.controls,
              ),
            ),
          ),
        ]);
      });
}
