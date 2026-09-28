// Copyright 2014 The Flutter Authors. All rights reserved.
// BSD license: ../shaders/FLUTTER-LICENSE.txt.
// Adapted from Flutter 3.47.1 overscroll_indicator.dart. Keep the native
// notification/spring contract, but retain one raster path at zero stretch.
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Keep the same image-filter coordinate space during pull, spring and rest.
/// Disabling the filter at zero lets Impeller rasterize text at a different
/// fractional origin; interpolating the shader alone cannot prevent that jump.
/// A retained filter has no ticker and does not schedule frames while idle.
class AppStretchEffect extends StatefulWidget {
  const AppStretchEffect(
      {super.key,
      required this.axis,
      required this.stretchStrength,
      required this.child});
  final Axis axis;
  final double stretchStrength;
  final Widget child;

  @override
  State<AppStretchEffect> createState() => _AppStretchEffectState();
}

class _AppStretchEffectState extends State<AppStretchEffect> {
  static Future<ui.FragmentProgram>? _loading;
  static ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    if (ui.ImageFilter.isShaderFilterSupported && _program == null) {
      (_loading ??=
              ui.FragmentProgram.fromAsset('shaders/app_edge_stretch.frag'))
          .then((program) {
        _program = program;
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ui.ImageFilter.isShaderFilterSupported) {
      final program = _program;
      if (program == null) return widget.child;
      _shader?.dispose();
      final shader = _shader = program.fragmentShader()
        ..setFloat(2, 1)
        ..setFloat(
            3, widget.axis == Axis.horizontal ? widget.stretchStrength : 0)
        ..setFloat(4, widget.axis == Axis.vertical ? widget.stretchStrength : 0)
        ..setFloat(5, .7);
      return ImageFiltered(
        imageFilter: ui.ImageFilter.shader(shader),
        // Material shadows/focus borders can introduce composited descendants.
        // Resolve them into one fixed viewport layer before the stretch filter.
        child: ClipRect(
            clipper: const _RasterGuard(),
            clipBehavior: Clip.antiAliasWithSaveLayer,
            child: CustomPaint(
                painter: const _ViewportCorners(), child: widget.child)),
      );
    }
    final leading = widget.stretchStrength >= 0;
    return Transform(
      alignment: widget.axis == Axis.vertical
          ? (leading ? Alignment.topCenter : Alignment.bottomCenter)
          : (leading ? Alignment.centerLeft : Alignment.centerRight),
      transform: Matrix4.diagonal3Values(
          widget.axis == Axis.horizontal ? 1 + widget.stretchStrength.abs() : 1,
          widget.axis == Axis.vertical ? 1 + widget.stretchStrength.abs() : 1,
          1),
      filterQuality: FilterQuality.medium,
      child: widget.child,
    );
  }
}

// Keep edge antialiasing inside the intermediate texture. The scroll viewport
// still clips the final result; this guard only protects the filter's input.
class _RasterGuard extends CustomClipper<Rect> {
  const _RasterGuard();
  @override
  Rect getClip(Size size) => (Offset.zero & size).inflate(2);
  @override
  bool shouldReclip(_RasterGuard oldClipper) => false;
}

/// Preserve the antialiased edge texels after filtering a fractional viewport.
/// Only the cross axis has an ink guard; scrolling content remains clipped at
/// the leading/trailing boundary, including during overscroll.
class AppStretchViewportClipper extends CustomClipper<Rect> {
  const AppStretchViewportClipper(this.axis);
  final Axis axis;
  @override
  Rect getClip(Size size) => axis == Axis.vertical
      ? Rect.fromLTRB(-2, 0, size.width + 2, size.height)
      : Rect.fromLTRB(0, -2, size.width, size.height + 2);
  @override
  bool shouldReclip(AppStretchViewportClipper oldClipper) =>
      axis != oldClipper.axis;
}

// Include the whole viewport in the filter texture, even for sparse contents.
class _ViewportCorners extends CustomPainter {
  const _ViewportCorners();
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()..color = const Color(0x01000000);
    for (final point in [
      const Offset(-2, -2),
      Offset(size.width + 1, -2),
      Offset(-2, size.height + 1),
      Offset(size.width + 1, size.height + 1),
    ]) {
      canvas.drawRect(point & const Size(1, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_ViewportCorners oldDelegate) => false;
}

class _AppIndicatorNotification extends OverscrollIndicatorNotification {
  _AppIndicatorNotification({required super.leading});
  bool isAllowed = true;
  @override
  void disallowIndicator() {
    isAllowed = false;
    super.disallowIndicator();
  }
}

class AppStretchingOverscrollIndicator extends StatefulWidget {
  /// Creates a visual indication that a scroll view has overscrolled by
  /// applying a stretch transformation to the content.
  ///
  /// In order for this widget to display an overscroll indication, the [child]
  /// widget must contain a widget that generates a [ScrollNotification], such
  /// as a [ListView] or a [GridView].
  const AppStretchingOverscrollIndicator({
    super.key,
    required this.axisDirection,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.clipBehavior = Clip.hardEdge,
    this.child,
  });

  /// {@macro flutter.overscroll.axisDirection}
  final AxisDirection axisDirection;

  /// {@macro flutter.overscroll.axis}
  Axis get axis => axisDirectionToAxis(axisDirection);

  /// {@macro flutter.overscroll.notificationPredicate}
  final ScrollNotificationPredicate notificationPredicate;

  /// {@macro flutter.material.Material.clipBehavior}
  ///
  /// Defaults to [Clip.hardEdge].
  final Clip clipBehavior;

  /// The widget below this widget in the tree.
  ///
  /// The overscroll indicator will apply a stretch effect to this child. This
  /// child (and its subtree) should include a source of [ScrollNotification]
  /// notifications.
  final Widget? child;

  @override
  State<AppStretchingOverscrollIndicator> createState() =>
      _AppStretchingOverscrollIndicatorState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<AxisDirection>('axisDirection', axisDirection));
  }
}

class _AppStretchingOverscrollIndicatorState
    extends State<AppStretchingOverscrollIndicator>
    with TickerProviderStateMixin {
  late final _StretchController _stretchController =
      _StretchController(vsync: this);
  ScrollNotification? _lastNotification;

  double _totalOverscroll = 0.0;

  bool _accepted = true;

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.notificationPredicate(notification)) {
      return false;
    }
    if (notification.metrics.axis != widget.axis) {
      // This widget is explicitly configured to one axis. If a notification
      // from a different axis bubbles up, do nothing.
      return false;
    }
    if (notification is ScrollStartNotification) {
      _accepted = true;
      _totalOverscroll = 0.0;
    } else if (notification is OverscrollNotification) {
      if (_lastNotification is! OverscrollNotification) {
        final confirmationNotification = _AppIndicatorNotification(
          leading: notification.overscroll < 0.0,
        );
        confirmationNotification.dispatch(context);
        _accepted = confirmationNotification.isAllowed;
      }

      if (_accepted) {
        _totalOverscroll += notification.overscroll;

        if (notification.velocity != 0.0) {
          assert(notification.dragDetails == null);
          _stretchController.absorbImpact(notification.velocity);
        } else {
          assert(notification.overscroll != 0.0);
          if (notification.dragDetails != null) {
            // We clamp the overscroll amount relative to the length of the viewport,
            // which is the furthest distance a single pointer could pull on the
            // screen. This is because more than one pointer will multiply the
            // amount of overscroll - https://github.com/flutter/flutter/issues/11884

            final double viewportDimension =
                notification.metrics.viewportDimension;
            final double distanceForPull = _totalOverscroll / viewportDimension;
            final double clampedOverscroll =
                clampDouble(distanceForPull, -1.0, 1.0);
            _stretchController.pull(clampedOverscroll);
          }
        }
      }
    } else if (notification is ScrollEndNotification) {
      double velocity = switch (widget.axis) {
        Axis.vertical =>
          notification.dragDetails?.velocity.pixelsPerSecond.dy ?? 0.0,
        Axis.horizontal =>
          notification.dragDetails?.velocity.pixelsPerSecond.dx ?? 0.0,
      };

      // Reverse axis directions report dragDetails velocity in
      // the opposite screen coordinate, so the value must be inverted.
      if (notification.metrics.axisDirection == AxisDirection.left ||
          notification.metrics.axisDirection == AxisDirection.up) {
        velocity = -velocity;
      }

      // Since the overscrolling ended, we reset the total overscroll amount.
      _totalOverscroll = 0.0;
      if (_accepted) {
        _stretchController.scrollEnd(velocity);
      }
    } else if (notification is ScrollUpdateNotification) {
      _totalOverscroll = 0.0;
      _stretchController.scrollEnd(0.0);
    }
    _lastNotification = notification;
    return false;
  }

  @override
  void dispose() {
    _stretchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: AnimatedBuilder(
        animation: _stretchController,
        builder: (BuildContext context, Widget? child) {
          final double stretch = _stretchController.overscroll;
          double overscroll = -stretch;

          // Adjust overscroll for reverse scroll directions.
          if (widget.axisDirection == AxisDirection.up ||
              widget.axisDirection == AxisDirection.left) {
            overscroll = -overscroll;
          }

          final Widget transform = AppStretchEffect(
            stretchStrength: overscroll,
            axis: widget.axis,
            child: widget.child ?? const SizedBox.shrink(),
          );

          // Keep clipping and filter bounds stable at rest as well. Toggling
          // either at zero can change the raster origin in a centred dialog.
          return ClipRect(
            clipper: AppStretchViewportClipper(widget.axis),
            clipBehavior: widget.clipBehavior,
            child: transform,
          );
        },
      ),
    );
  }
}

class _StretchController extends Listenable {
  _StretchController({required this.vsync});

  final TickerProvider vsync;
  AnimationController? _controller;

  /// Manages and notifies changes to the current [overscroll] value.
  final ValueNotifier<double> _overscrollNotifier = ValueNotifier<double>(0.0);
  double get overscroll => _overscrollNotifier.value;
  set overscroll(double newValue) {
    _overscrollNotifier.value =
        clampDouble(newValue, minOverscroll, maxOverscroll);
  }

  /// Stores the `overscroll` value from an ongoing animation at the precise
  /// moment it is interrupted by a new `pull()` gesture.
  ///
  /// When `pull()` is called while an animation (triggered by `absorbImpact`
  /// or `scrollEnd`) is active, this field captures the animation's current
  /// `_controller.value` (which represents the overscroll amount) immediately
  /// before the animation controller is disposed.
  ///
  /// This captured value is then added to the overscroll amount calculated
  /// by the `pull()` method. The primary purpose is to create a smoother
  /// visual transition from an animated overscroll state to a direct,
  /// user-driven pull, minimizing any abrupt visual "jumps" in the
  /// stretch effect.
  ///
  /// It is reset to `0.0` when an animation completes naturally via `animate()`
  /// or when a new pull starts without a preceding active animation.
  double _interruptedOverscroll = 0.0;

  // Constants from Android.
  static const double _exponentialScalar = math.e / 0.33;
  static const double _stretchIntensity = 0.016;

  static const double minOverscroll = -1.0;
  static const double maxOverscroll = 1.0;

  /// A fraction used to adjust the input velocity, measured in pixels,
  /// to a value between -1 and 1 when gesture fling.
  static const double _flingVelocityFriction = 1 / 6000;

  /// A fraction used to scale the absorbed impact velocity,
  /// converting raw velocity into a normalized value for simulation.
  static const double _absorbImpactVelocityFriction = 1 / 3000;

  /// The maximum velocity allowed for a fling after scaling
  /// to prevent applying an excessive stretch effect.
  static const double _maxFlingVelocity = 0.5;

  /// The maximum velocity allowed when absorbing an impact,
  /// ensuring the stretch effect does not exceed a reasonable limit.
  static const double _maxAbsorbImpactVelocity = 1.25;

  // Physical constants ported directly from Android's EdgeEffect.java.
  //
  // Android's EdgeEffect.java:
  // https://cs.android.com/android/platform/superproject/main/+/main:frameworks/base/core/java/android/widget/EdgeEffect.java
  static const double kNaturalFrequency = 24.657;
  static const double kDampingRatio = 0.98;

  /// A correction factor applied to the simulation time.
  ///
  /// The physical constants `kNaturalFrequency ` and `kDampingRatio ` were ported
  /// directly from Android's `EdgeEffect.java` source. However, using these
  /// constants as-is resulted in an animation that was noticeably faster than
  /// the native Android behavior. The underlying reason for this discrepancy is
  /// unknown.
  ///
  /// This factor, determined by visual comparison ("eyeballing") to match the
  /// platform's timing, is applied to the elapsed time `t` to slow down the
  /// simulation.
  ///
  /// Based on the damped harmonic oscillator equations, an alternative,
  /// mathematically equivalent, approach would be to multiply both the
  /// `kNaturalFrequency ` and the initial velocity by this same factor,
  /// rather than scaling the time input.
  static const double kTimeCorrectionFactor = 0.8;

  /// Stiffness coefficient for the spring, derived from the natural frequency.
  ///
  /// Calculated as `kStiffness = kNaturalFrequency^2`, this is the baseline
  /// spring constant used in the damped harmonic oscillator model.
  static const double kStiffness = kNaturalFrequency * kNaturalFrequency;

  /// Spring description representing the stretch behavior of the edge effect.
  ///
  /// This [SpringDescription] is used to simulate the overscroll stretch
  /// in Flutter. The spring has a mass of 1, a stiffness adjusted by the
  /// [kTimeCorrectionFactor] squared to match platform timing, and
  /// a damping ratio corresponding to Android's native `EdgeEffect`.
  static final SpringDescription _kStretchSpringDescription =
      SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: kStiffness * kTimeCorrectionFactor * kTimeCorrectionFactor,
    ratio: kDampingRatio,
  );

  @override
  void addListener(VoidCallback listener) {
    _overscrollNotifier.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _overscrollNotifier.removeListener(listener);
  }

  /// Creates a stretching-only [Simulation] ported from Android 12.
  SpringSimulation _createStretchSimulation(double velocity) {
    return SpringSimulation(
      _kStretchSpringDescription,
      overscroll,
      0.0,
      velocity * kTimeCorrectionFactor,
    );
  }

  /// Handle a fling to the edge of the viewport at a particular velocity.
  ///
  /// The velocity must be positive.
  void absorbImpact(double velocity) {
    if (velocity == 0.0) {
      return;
    }
    final double scaledVelocity = clampDouble(
      velocity * _absorbImpactVelocityFriction,
      -_maxAbsorbImpactVelocity,
      _maxAbsorbImpactVelocity,
    );

    animate(_createStretchSimulation(scaledVelocity));
  }

  /// Called when the overscroll ends to trigger a fling animation if needed.
  void scrollEnd(double velocity) {
    if (velocity == 0.0 && overscroll == 0.0) {
      return;
    }
    final double scaledVelocity = clampDouble(
      -(velocity * _flingVelocityFriction),
      -_maxFlingVelocity,
      _maxFlingVelocity,
    );

    if (_controller == null) {
      animate(_createStretchSimulation(scaledVelocity));
    }
  }

  /// Starts a new animation using the given [simulation].
  ///
  /// Disposes any existing animation controller before starting a new one.
  /// Updates the [overscroll] value on each animation frame.
  /// Automatically disposes the controller when the animation completes.
  void animate(Simulation simulation) {
    final controller = AnimationController.unbounded(vsync: vsync)
      ..addListener(() {
        final double newOverscroll = _controller?.value ?? 0.0;
        overscroll = newOverscroll;
      })
      ..animateWith(simulation).whenComplete(() {
        overscroll = 0.0;
        _interruptedOverscroll = 0.0;
        _controller!.dispose();
        _controller = null;
      });

    _controller?.dispose();
    _controller = controller;
  }

  /// Handle a user-driven overscroll.
  ///
  /// The `normalizedOverscroll` argument should be the scroll distance in
  /// logical pixels, divided by the extent of the viewport in the main axis.
  void pull(double normalizedOverscroll) {
    if (_controller != null) {
      _interruptedOverscroll = _controller!.value;
      _controller!.dispose();
      _controller = null;
    }

    final pullDistance = normalizedOverscroll;
    final double absDistance = pullDistance.abs();
    final double linearIntensity = _stretchIntensity * absDistance;
    final double exponentialIntensity =
        _stretchIntensity * (1 - math.exp(-absDistance * _exponentialScalar));

    // Maintain sign of overscroll for direction.
    final double directionSign = pullDistance.sign;
    final double newOverscroll =
        directionSign * (linearIntensity + exponentialIntensity);
    overscroll = newOverscroll + _interruptedOverscroll;
  }

  void dispose() {
    _controller?.dispose();
    _overscrollNotifier.dispose();
  }

  @override
  String toString() => '_StretchController()';
}
