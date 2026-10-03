import 'dart:async';

enum LyricDisplayMode { desktop, taskbar }

/// Serializes the two external lyric surfaces without constructing either one.
/// A later request wins even while the previous actor is starting or closing.
class LyricDisplayCoordinator {
  static final shared = LyricDisplayCoordinator();

  final _closers = <LyricDisplayMode, Future<void> Function()>{};
  final _cancelPending = <LyricDisplayMode, void Function()>{};
  Future<void> _tail = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;
  LyricDisplayMode? _desired;
  LyricDisplayMode? _active;
  void Function()? beforeDesktopRequest;
  Future<bool> Function()? requestTaskbar;
  bool get coordinatesTaskbar => _closers.containsKey(LyricDisplayMode.taskbar);

  void register(LyricDisplayMode mode, Future<void> Function() close,
      {void Function()? cancelPending}) {
    _closers[mode] = close;
    if (cancelPending != null) _cancelPending[mode] = cancelPending;
  }

  void unregister(LyricDisplayMode mode, Future<void> Function() close) {
    if (identical(_closers[mode], close)) {
      _closers.remove(mode);
      _cancelPending.remove(mode);
    }
  }

  Future<bool> show(LyricDisplayMode mode, Future<void> Function() open) {
    if (_disposed) return Future.value(false);
    final generation = ++_generation;
    _desired = mode;
    if (mode == LyricDisplayMode.desktop) beforeDesktopRequest?.call();
    for (final other in LyricDisplayMode.values) {
      if (other != mode) _cancelPending[other]?.call();
    }
    return _enqueue(() async {
      if (!_current(generation)) return false;
      for (final other in LyricDisplayMode.values) {
        if (other == mode) continue;
        await _closers[other]?.call();
        if (_active == other) _active = null;
        if (!_current(generation)) return false;
      }
      await open();
      if (!_current(generation)) {
        await _closers[mode]?.call();
        return false;
      }
      _active = mode;
      return true;
    });
  }

  /// Hiding one surface must not cancel a request to open the other one.
  Future<void> hide(LyricDisplayMode mode) {
    cancel(mode);
    return _enqueue(() async {
      await _closers[mode]?.call();
      if (_active == mode) _active = null;
    });
  }

  void cancel(LyricDisplayMode mode) {
    if (_desired != mode) return;
    _desired = null;
    _generation++;
    _cancelPending[mode]?.call();
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    await _enqueue(() async {
      for (final close in _closers.values.toList()) {
        await close();
      }
      _closers.clear();
      _cancelPending.clear();
      beforeDesktopRequest = null;
      _active = null;
    });
  }
}
