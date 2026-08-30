import 'package:dan_player/component/compact_player.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/component/scene_background.dart';
import 'package:dan_player/window_mode_controller.dart';
import 'package:flutter/material.dart';

/// This is a Flutter navigator inside the same native window, not a second
/// window/player. Dialogs remain usable while the normal router is offstage.
final compactNavigatorKey = GlobalKey<NavigatorState>();

class AppWindowModeHost extends StatefulWidget {
  const AppWindowModeHost({
    super.key,
    required this.child,
    this.controller,
    this.compactBuilder,
    this.navigatorKey,
  });

  final Widget child;
  final WindowModeController? controller;
  final WidgetBuilder? compactBuilder;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<AppWindowModeHost> createState() => _AppWindowModeHostState();
}

class _AppWindowModeHostState extends State<AppWindowModeHost> {
  Size? _normalViewport;
  Size? _compactViewport;
  FocusNode? _normalFocus;
  bool _wasMini = false;
  bool _waitingForNormalViewport = false;

  WindowModeController get _controller =>
      widget.controller ?? WindowModeController.instance;

  @override
  void initState() {
    super.initState();
    _wasMini = _controller.isMini;
    _controller.addListener(_onModeChanged);
  }

  @override
  void didUpdateWidget(covariant AppWindowModeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.controller ?? WindowModeController.instance;
    if (!identical(previous, _controller)) {
      previous.removeListener(_onModeChanged);
      _controller.addListener(_onModeChanged);
      _wasMini = _controller.isMini;
    }
  }

  void _onModeChanged() {
    if (_controller.isMini && !_wasMini) {
      _normalFocus = FocusManager.instance.primaryFocus;
      _compactViewport = null;
      _waitingForNormalViewport = false;
    } else if (!_controller.isMini && _wasMini) {
      // A successful native setBounds reply can precede Flutter's metrics
      // notification. Do not reflow the normal page into the stale mini size.
      _waitingForNormalViewport = true;
      final focus = _normalFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_controller.isMini &&
            focus != null &&
            focus.context?.mounted == true &&
            focus.canRequestFocus) {
          focus.requestFocus();
        }
      });
      _normalFocus = null;
    }
    _wasMini = _controller.isMini;
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onModeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final mini = _controller.isMini;
          final size = constraints.biggest;
          if (mini && !_controller.isBusy && size != _normalViewport) {
            _compactViewport = size;
          }
          final restoredMetrics = size == _normalViewport ||
              (_compactViewport != null
                  ? size != _compactViewport
                  : size.width >= _controller.normalMinimumSize.width &&
                      size.height >= _controller.normalMinimumSize.height);
          if (!mini &&
              !_controller.isBusy &&
              (!_waitingForNormalViewport || restoredMetrics)) {
            _normalViewport = size;
            _waitingForNormalViewport = false;
          }
          final viewport = _normalViewport ?? const Size(1280, 756);
          return Stack(
            fit: StackFit.expand,
            children: [
              // Do not replace/unmount the router or reflow it into a 200px
              // window. Queue, page state, scroll positions and pending edits
              // survive switching; the preference controls invisible tickers.
              Offstage(
                offstage: mini,
                child: TickerMode(
                  enabled: !mini ||
                      !RenderingPreferencesScope.of(context).pauseWhenHidden,
                  child: ExcludeFocus(
                    excluding: mini,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: viewport.width,
                      maxWidth: viewport.width,
                      minHeight: viewport.height,
                      maxHeight: viewport.height,
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(size: viewport),
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              ),
              if (mini)
                ScaffoldMessenger(
                  // MaterialApp's HeroController belongs to the normal router.
                  // The sibling mini navigator must not borrow that controller.
                  child: HeroControllerScope.none(
                    child: Navigator(
                      key: widget.navigatorKey ?? compactNavigatorKey,
                      onGenerateRoute: (_) => PageRouteBuilder<void>(
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                        pageBuilder: (context, _, __) => Scaffold(
                          backgroundColor: Colors.transparent,
                          // Keep controls outside the configurable layer, so
                          // source changes cannot reset lyrics or a seek drag.
                          body: AppContentRegion(
                              child: Stack(fit: StackFit.expand, children: [
                            const SceneBackground(scene: BackgroundScene.mini),
                            widget.compactBuilder?.call(context) ??
                                CompactPlayer(controller: _controller),
                          ])),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
}
