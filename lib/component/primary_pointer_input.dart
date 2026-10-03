import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps a physical drag with its first pointer without changing keyboard or
/// semantics actions. Material Slider otherwise lets a later contact take over
/// its drag recognizer and waits for that contact before ending the drag.
class PrimaryPointerInput extends SingleChildRenderObjectWidget {
  const PrimaryPointerInput({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPrimaryPointerInput();
}

class _RenderPrimaryPointerInput extends RenderProxyBox {
  int? _pointer;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _pointer == null && super.hitTestChildren(result, position: position);

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    // Flutter retains the original hit-test path until this pointer ends.
    // Later contacts hit only this box, never the child's drag recognizer.
    if (event is PointerDownEvent) {
      _pointer ??= event.pointer;
    } else if ((event is PointerUpEvent || event is PointerCancelEvent) &&
        event.pointer == _pointer) {
      _pointer = null;
    }
  }

  @override
  void detach() {
    _pointer = null;
    super.detach();
  }
}
