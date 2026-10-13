import 'package:flutter/widgets.dart';

/// A mode-switch entry supplies its existing opacity animation to the lyric
/// surface. Its backdrop stays outside the content's fading layer.
class LyricViewTransition extends InheritedWidget {
  const LyricViewTransition({
    super.key,
    required this.opacity,
    required super.child,
  });

  final Animation<double> opacity;

  static const _opaque = AlwaysStoppedAnimation<double>(1);

  static Animation<double> opacityOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<LyricViewTransition>()
          ?.opacity ??
      _opaque;

  static Widget transition(
    Widget child,
    Animation<double> opacity, {
    required bool lyric,
  }) =>
      // AnimatedSwitcher owns each entry's unique key. Reusing child.key on
      // these wrappers would collide with an earlier entry on a rapid return.
      lyric
          ? LyricViewTransition(opacity: opacity, child: child)
          : FadeTransition(opacity: opacity, child: child);

  // Consumers listen to the supplied animation themselves. Replacing an entry
  // updates ownership; its individual ticks do not rebuild the whole surface.
  @override
  bool updateShouldNotify(LyricViewTransition oldWidget) =>
      !identical(opacity, oldWidget.opacity);
}
