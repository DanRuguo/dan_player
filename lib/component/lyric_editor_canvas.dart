import 'package:dan_player/component/app_dialog_content.dart';
import 'package:flutter/material.dart';

/// Editing keeps a stable surface when tabs or recording stages change.
/// The shared dialog viewport still caps it to the available window height.
class LyricEditorCanvas extends StatelessWidget {
  const LyricEditorCanvas({
    super.key,
    this.width = 900,
    this.maxHeight = 800,
    required this.child,
  });

  final double width;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppDialogContent(
      width: width,
      maxHeight: maxHeight,
      child: SizedBox(height: maxHeight, child: child));
}
