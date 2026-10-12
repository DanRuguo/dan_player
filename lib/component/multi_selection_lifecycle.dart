import 'package:flutter/material.dart';

/// One instance per Navigator. Popup routes never retire page selections.
class MultiSelectionRouteObserver extends NavigatorObserver {
  final _subscribers = <PageRoute<dynamic>, Set<VoidCallback>>{};
  final _pages = <PageRoute<dynamic>>[];

  void subscribe(PageRoute<dynamic> route, VoidCallback onLeave) =>
      (_subscribers[route] ??= {}).add(onLeave);

  void unsubscribe(VoidCallback onLeave) {
    for (final callbacks in _subscribers.values) {
      callbacks.remove(onLeave);
    }
    _subscribers.removeWhere((_, callbacks) => callbacks.isEmpty);
  }

  void _leave(PageRoute<dynamic> route) {
    for (final callback in List<VoidCallback>.of(_subscribers[route] ?? {})) {
      callback();
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute<dynamic>) return;
    if (_pages.isNotEmpty) _leave(_pages.last);
    _pages.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute<dynamic>) return;
    _leave(route);
    _pages.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute<dynamic>) return;
    _leave(route);
    _pages.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute is PageRoute<dynamic>) {
      _leave(oldRoute);
      final at = _pages.indexOf(oldRoute);
      if (at >= 0) {
        if (newRoute is PageRoute<dynamic>) {
          _pages[at] = newRoute;
        } else {
          _pages.removeAt(at);
        }
        return;
      }
    }
    if (newRoute is PageRoute<dynamic>) _pages.add(newRoute);
  }
}

/// Subscribes to the page in each ancestor Navigator, including a root Shell
/// page. Opening a root-level playback page therefore also retires an inner
/// library selection. Every subscription belongs to this mounted subtree.
class SelectionPageLifecycle extends StatefulWidget {
  const SelectionPageLifecycle(
      {super.key, required this.onLeave, required this.child});

  final VoidCallback onLeave;
  final Widget child;

  @override
  State<SelectionPageLifecycle> createState() => _SelectionPageLifecycleState();
}

class _SelectionPageLifecycleState extends State<SelectionPageLifecycle> {
  final _observers = <MultiSelectionRouteObserver>[];
  void _leave() => widget.onLeave();

  void _unsubscribe() {
    for (final observer in _observers) {
      observer.unsubscribe(_leave);
    }
    _observers.clear();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _unsubscribe();
    BuildContext lookup = context;
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is NavigatorState) {
        final navigator = element.state as NavigatorState;
        final route = ModalRoute.of(lookup);
        if (route is PageRoute<dynamic> &&
            identical(route.navigator, navigator)) {
          for (final observer in navigator.widget.observers) {
            if (observer is MultiSelectionRouteObserver) {
              observer.subscribe(route, _leave);
              _observers.add(observer);
            }
          }
        }
        // A Navigator's own context is outside its inner route scopes and
        // finds the enclosing page using the public ModalRoute lookup API.
        lookup = element;
      }
      return true;
    });
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
