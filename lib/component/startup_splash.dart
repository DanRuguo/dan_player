import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/brand_logo.dart';
import 'package:dan_player/startup_progress.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class StartupSplash extends StatefulWidget {
  const StartupSplash({
    super.key,
    required this.child,
    this.minimumVisibleDuration = const Duration(milliseconds: 950),
    this.fadeDuration = AppMotion.long,
    this.logoTransitionDuration = AppMotion.emphasized,
    this.progress,
    this.showProgress = false,
  });

  static const totalDuration = Duration(milliseconds: 1250);
  static const rcePhaseDuration = Duration(milliseconds: 750);
  static const danRuguoPhaseDuration = Duration(milliseconds: 500);
  static const overlayKey = ValueKey('startup-brand-overlay');
  static const surfaceKey = ValueKey('startup-brand-surface');
  static const rceOpacityKey = ValueKey('startup-rce-opacity');
  static const danRuguoOpacityKey = ValueKey('startup-danruguo-opacity');
  static const playerSignatureKey = ValueKey('startup-player-signature');
  static const playerIconKey = ValueKey('startup-player-icon');
  static const playerNameKey = ValueKey('startup-player-name');
  static const progressKey = ValueKey('startup-progress');
  static const progressLabelKey = ValueKey('startup-progress-label');

  final Widget child;
  final StartupProgress? progress;
  final bool showProgress;

  /// Time before the final fade begins; the fade is part of the 1.25-second
  /// sequence, rather than an extra delay after both brand presentations.
  final Duration minimumVisibleDuration;
  final Duration fadeDuration;
  final Duration logoTransitionDuration;

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _timeline;
  bool _removed = false;
  bool _reducedMotion = false;
  double? _loadingFinishedAt;

  StartupProgressValue get _loading =>
      widget.progress?.value ?? const StartupProgressValue();

  bool get _platformReducesMotion {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return features.disableAnimations || features.reduceMotion;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timeline = AnimationController(
      vsync: this,
      duration: widget.minimumVisibleDuration + widget.fadeDuration,
      // Accessibility disables visual interpolation, not either brand's dwell
      // time. Otherwise Flutter may shorten this entire clock to a few frames.
      animationBehavior: AnimationBehavior.preserve,
    )..addListener(_onTimelineTick);
    widget.progress?.addListener(_onProgress);
    if (_loading.ready) _loadingFinishedAt = 0;
    if (_loading.failed) {
      _removed = true;
    } else {
      _timeline.forward();
    }
  }

  @override
  void didUpdateWidget(StartupSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress != oldWidget.progress) {
      oldWidget.progress?.removeListener(_onProgress);
      widget.progress?.addListener(_onProgress);
      _onProgress();
    }
  }

  void _onProgress() {
    if (!mounted || _removed) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onProgress());
      return;
    }
    if (_loading.ready) _loadingFinishedAt ??= _timeline.value;
    setState(() {
      if (_loading.failed || (_loading.ready && _timeline.value >= 1)) {
        _timeline.stop(canceled: false);
        _removed = true;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = (!AppMotion.enabled(context, MotionKind.startup)) ||
        _platformReducesMotion;
    if (!MotionPreferencesScope.of(context).allows(MotionKind.startup)) {
      _timeline.value = 1;
      // Disabling the splash exposes the ordinary loading/recovery page;
      // it never conceals or blocks unfinished initialization work.
      _removed = true;
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    setState(() {
      _reducedMotion = (!AppMotion.enabled(context, MotionKind.startup)) ||
          _platformReducesMotion;
    });
  }

  void _onTimelineTick() {
    // Flutter's interpolation simulation reports `completed` only on the
    // first frame strictly after its duration. Retire the overlay when the
    // value reaches its endpoint so the 1250 ms frame is already interactive.
    if (_timeline.value >= 1 && !_removed && mounted) {
      _timeline.stop(canceled: false);
      if (_loading.ready || _loading.failed) {
        setState(() => _removed = true);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.progress?.removeListener(_onProgress);
    _timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: !_removed,
          child: ExcludeSemantics(
            excluding: !_removed,
            child: AppEntranceScope(
              // Preload once, then begin content motion only after the opaque
              // startup sequence leaves. Theme changes never restart startup.
              ready: _removed,
              child: widget.child,
            ),
          ),
        ),
        if (!_removed)
          Listener(
            key: StartupSplash.overlayKey,
            behavior: HitTestBehavior.opaque,
            child: RepaintBoundary(
              child: _StartupSplashOverlay(
                timeline: _timeline,
                fadeDuration: widget.fadeDuration,
                logoTransitionDuration: widget.logoTransitionDuration,
                reducedMotion: _reducedMotion,
                loading: _loading,
                loadingFinishedAt: _loadingFinishedAt,
                showProgress: widget.showProgress,
              ),
            ),
          ),
      ],
    );
  }
}

class _StartupSplashOverlay extends StatelessWidget {
  const _StartupSplashOverlay({
    required this.timeline,
    required this.fadeDuration,
    required this.logoTransitionDuration,
    required this.reducedMotion,
    required this.loading,
    required this.loadingFinishedAt,
    required this.showProgress,
  });

  final AnimationController timeline;
  final Duration fadeDuration;
  final Duration logoTransitionDuration;
  final bool reducedMotion;
  final StartupProgressValue loading;
  final double? loadingFinishedAt;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final total = timeline.duration!.inMicroseconds;
    final transitionFraction = total == 0
        ? 0.0
        : (logoTransitionDuration.inMicroseconds / total).clamp(0.0, 1.0);
    final fadeFraction = total == 0
        ? 0.0
        : (fadeDuration.inMicroseconds / total).clamp(0.0, 1.0);
    final fadeStart = (loadingFinishedAt ?? 1.0).clamp(1 - fadeFraction, 1.0);
    final handoff = StartupSplash.rcePhaseDuration.inMicroseconds /
        StartupSplash.totalDuration.inMicroseconds;

    return AnimatedBuilder(
      animation: timeline,
      builder: (context, child) {
        final progress = timeline.value;
        final secondBrand = progress >= handoff;
        final blend = reducedMotion || transitionFraction == 0
            ? (secondBrand ? 1.0 : 0.0)
            : Curves.easeInOut.transform(
                ((progress - (handoff - transitionFraction / 2)) /
                        transitionFraction)
                    .clamp(0.0, 1.0),
              );
        final fade = reducedMotion ||
                fadeFraction == 0 ||
                !loading.ready ||
                fadeStart >= 1
            ? 0.0
            : Curves.easeInOutCubic.transform(
                ((progress - fadeStart) / (1 - fadeStart)).clamp(0.0, 1.0),
              );

        return Opacity(
          opacity: 1 - fade,
          child: ColoredBox(
            key: StartupSplash.surfaceKey,
            color: Theme.of(context).colorScheme.surface,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth * 0.46).clamp(0.0, 500.0);
                final height = (constraints.maxHeight * 0.52).clamp(0.0, 310.0);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ExcludeSemantics(
                      excluding: secondBrand,
                      child: Opacity(
                        key: StartupSplash.rceOpacityKey,
                        opacity: 1 - blend,
                        child: SafeArea(
                          minimum: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Expanded(
                                child: Center(
                                  child: BrandLogo(
                                    brand: AppBrand.rce,
                                    width: width,
                                    height: (width / BrandLogo.rceAspectRatio)
                                        .clamp(0.0, height),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (!showProgress) const _PlayerSignature(),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (showProgress)
                      SafeArea(
                        minimum: const EdgeInsets.all(16),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: _StartupProgressFooter(value: loading),
                        ),
                      ),
                    if (!showProgress && loading.cancelScan != null)
                      SafeArea(
                        minimum: const EdgeInsets.all(16),
                        child: Align(
                          alignment: Alignment.bottomRight,
                          child: TextButton(
                            onPressed: loading.cancelScan,
                            child: Text(ui('取消扫描')),
                          ),
                        ),
                      ),
                    ExcludeSemantics(
                      excluding: !secondBrand,
                      child: Opacity(
                        key: StartupSplash.danRuguoOpacityKey,
                        opacity: blend,
                        child: Align(
                          alignment: const Alignment(0, -0.10),
                          child: BrandLogo(
                            brand: AppBrand.danRuguo,
                            width: width,
                            height: height,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _StartupProgressFooter extends StatelessWidget {
  const _StartupProgressFooter({required this.value});
  final StartupProgressValue value;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 148,
          child: LinearProgressIndicator(
            key: StartupSplash.progressKey,
            value: value.progress,
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          ui(value.label),
          key: StartupSplash.progressLabelKey,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
        ),
        if (value.cancelScan != null || value.cancelling)
          TextButton(
            onPressed: value.cancelScan,
            child: Text(ui(value.cancelling ? '正在取消扫描' : '取消扫描')),
          ),
      ],
    );
  }
}

class _PlayerSignature extends StatelessWidget {
  const _PlayerSignature();

  @override
  Widget build(BuildContext context) => Wrap(
        key: StartupSplash.playerSignatureKey,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          Image.asset(
            'app_icon.ico',
            key: StartupSplash.playerIconKey,
            width: 24,
            height: 24,
            excludeFromSemantics: true,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.music_note,
              size: 24,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          // Keep the name intact even in a window narrower than the text. The
          // Wrap moves it beneath the icon before this last-resort scaling.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Dan Player',
              key: StartupSplash.playerNameKey,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
          ),
        ],
      );
}
