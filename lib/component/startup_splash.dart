import 'dart:async';

import 'package:flutter/material.dart';

class StartupSplash extends StatefulWidget {
  const StartupSplash({
    super.key,
    required this.child,
    this.minimumVisibleDuration = const Duration(seconds: 2),
    this.fadeDuration = const Duration(milliseconds: 500),
  });

  final Widget child;
  final Duration minimumVisibleDuration;
  final Duration fadeDuration;

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash> {
  bool _firstFramePainted = false;
  bool _minimumTimeElapsed = false;
  bool _fading = false;
  bool _removed = false;
  Timer? _minimumTimer;

  @override
  void initState() {
    super.initState();

    _minimumTimer = Timer(widget.minimumVisibleDuration, () {
      _minimumTimeElapsed = true;
      _tryFadeOut();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstFramePainted = true;
      _tryFadeOut();
    });
  }

  @override
  void dispose() {
    _minimumTimer?.cancel();
    super.dispose();
  }

  void _tryFadeOut() {
    if (!mounted ||
        _fading ||
        _removed ||
        !_firstFramePainted ||
        !_minimumTimeElapsed) {
      return;
    }

    setState(() {
      _fading = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_removed)
          AnimatedOpacity(
            opacity: _fading ? 0.0 : 1.0,
            duration: widget.fadeDuration,
            curve: Curves.easeOutCubic,
            onEnd: () {
              if (_fading && mounted) {
                setState(() {
                  _removed = true;
                });
              }
            },
            child: const _StartupSplashOverlay(),
          ),
      ],
    );
  }
}

class _StartupSplashOverlay extends StatelessWidget {
  const _StartupSplashOverlay();

  static const _lightLogoAsset = "assets/images/RCE_logo_transparent.png";
  static const _darkLogoAsset = "assets/images/RCE_logo_white.png";

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return ColoredBox(
      color: isDark ? const Color(0xFF10100E) : scheme.surface,
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxLogoWidth = (constraints.maxWidth * 0.46).clamp(
              240.0,
              520.0,
            );

            return Align(
              alignment: const Alignment(0.0, -0.10),
              child: Image.asset(
                isDark ? _darkLogoAsset : _lightLogoAsset,
                width: maxLogoWidth,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
            );
          },
        ),
      ),
    );
  }
}
