import 'dart:async';
import 'dart:io';

import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/library/playlist_exchange.dart';
import 'package:path/path.dart' as p;

/// Event-driven scheduling only. The native incremental scanner remains the
/// authority for complete enumeration and atomic commit (including removals).
class LibraryWatch {
  LibraryWatch({
    required this.refresh,
    Stream<FileSystemEvent> Function(String)? watch,
    Future<bool> Function(String)? accessible,
    bool Function()? busy,
    this.onError,
    this.quietPeriod = const Duration(seconds: 2),
    this.maximumDelay = const Duration(seconds: 15),
    this.recoveryPeriod = const Duration(seconds: 30),
    this.checkTimeout = const Duration(seconds: 2),
  })  : _watch = watch ?? ((root) => Directory(root).watch(recursive: true)),
        _accessible = accessible ?? ((root) => Directory(root).exists()),
        _busy = busy ?? (() => LibraryMutationGate.shared.isBusy);

  final Future<void> Function() refresh;
  final Stream<FileSystemEvent> Function(String) _watch;
  final Future<bool> Function(String) _accessible;
  final bool Function() _busy;
  final void Function(Object, StackTrace)? onError;
  final Duration quietPeriod, maximumDelay, recoveryPeriod, checkTimeout;
  final Set<void Function()> _cancelChecks = {};
  final Map<String, StreamSubscription<FileSystemEvent>> _subscriptions = {};
  Map<String, String> _roots = {};
  Timer? _quiet, _deadline, _recovery;
  Future<void>? _running;
  bool _enabled = false, _dirty = false, _disposed = false;
  bool _failureRetried = false;
  int _generation = 0;
  Future<void> _configuration = Future.value();

  static Map<String, String> normalizeRoots(Iterable<String> roots) {
    final unique = <String, String>{};
    for (final root in roots) {
      if (!p.windows.isAbsolute(root) ||
          p.windows.isRootRelative(root) ||
          root.contains('\u0000')) {
        continue;
      }
      final normalized = p.windows.normalize(root);
      unique[normalized.toLowerCase()] = normalized;
    }
    return {
      for (final key in unique.keys)
        if (!unique.keys
            .any((other) => other != key && p.windows.isWithin(other, key)))
          key: unique[key]!,
    };
  }

  Future<void> configure(
      {required bool enabled, required Iterable<String> roots}) {
    if (_disposed) return Future.value();
    final next = normalizeRoots(roots);
    if (_enabled == enabled &&
        next.length == _roots.length &&
        next.keys.every(_roots.containsKey)) {
      return _configuration;
    }
    _enabled = enabled;
    _roots = next;
    final generation = ++_generation;
    _cancelTimers();
    _abortChecks();
    _dirty = false;
    _configuration = _configuration.then((_) async {
      final previous = _subscriptions.values.toList();
      _subscriptions.clear();
      await Future.wait(previous.map(_cancelSubscription));
      if (!_current(generation)) return;
      await _attach(generation, refreshOnRecovery: false);
      // Reconcile changes in the gap before the event streams were attached.
      if (_current(generation) && _roots.isNotEmpty) _request();
    }).catchError((Object error, StackTrace trace) {
      onError?.call(error, trace);
    });
    return _configuration;
  }

  bool _current(int generation) =>
      !_disposed && _enabled && generation == _generation;

  Future<void> _attach(int generation,
      {required bool refreshOnRecovery}) async {
    var restored = false;
    for (final entry in Map<String, String>.of(_roots).entries) {
      if (!_current(generation)) return;
      if (_subscriptions.containsKey(entry.key)) continue;
      try {
        if (!await _checkRoot(entry.value) || !_current(generation)) continue;
        final subscription = _watch(entry.value).listen(
          (event) {
            if (_current(generation) && _relevant(event)) _request();
          },
          onError: (Object error, StackTrace trace) =>
              _lost(entry.key, generation, error, trace),
          onDone: () => _lost(entry.key, generation, null, null),
          cancelOnError: true,
        );
        _subscriptions[entry.key] = subscription;
        restored = true;
      } catch (error, trace) {
        onError?.call(error, trace);
      }
    }
    if (!_current(generation)) return;
    if (restored && refreshOnRecovery) _request();
    _scheduleRecovery(generation);
  }

  static bool _relevant(FileSystemEvent event) {
    if (event.isDirectory) return true;
    if (event is FileSystemModifyEvent && !event.contentChanged) {
      return false;
    }
    return isM3uLocalAudioPath(event.path) ||
        (event is FileSystemMoveEvent &&
            event.destination != null &&
            isM3uLocalAudioPath(event.destination!));
  }

  void _lost(String key, int generation, Object? error, StackTrace? trace) {
    if (!_current(generation)) return;
    final subscription = _subscriptions.remove(key);
    if (subscription != null) unawaited(_cancelSubscription(subscription));
    if (error != null) onError?.call(error, trace ?? StackTrace.current);
    _dirty = true;
    _scheduleRecovery(generation);
  }

  void _scheduleRecovery(int generation) {
    if (_subscriptions.length >= _roots.length || _recovery?.isActive == true) {
      return;
    }
    _recovery = Timer(recoveryPeriod,
        () => unawaited(_attach(generation, refreshOnRecovery: true)));
  }

  void _request({bool retry = false}) {
    if (_disposed || !_enabled || _roots.isEmpty) return;
    if (!retry) _failureRetried = false;
    _dirty = true;
    _quiet?.cancel();
    _quiet = Timer(quietPeriod, _beginRefresh);
    if (_deadline?.isActive != true) {
      _deadline = Timer(maximumDelay, _beginRefresh);
    }
  }

  void _beginRefresh() {
    _quiet?.cancel();
    _deadline?.cancel();
    if (_disposed || !_enabled || !_dirty || _running != null) return;
    if (_busy()) {
      _quiet = Timer(quietPeriod, _beginRefresh);
      return;
    }
    final generation = _generation;
    _dirty = false;
    _running = _refresh(generation).whenComplete(() {
      _running = null;
      if (!_disposed && _enabled && _dirty) _request();
    });
  }

  Future<void> _refresh(int generation) async {
    try {
      for (final entry in Map<String, String>.of(_roots).entries) {
        if (!_current(generation)) return;
        if (!await _checkRoot(entry.value)) {
          _lost(entry.key, generation, null, null);
          // No retry scan until this root becomes available again.
          _dirty = false;
          return;
        }
      }
      if (!_current(generation)) return;
      await refresh();
    } on LibraryMutationBusy {
      // A manual edit may acquire the gate during the asynchronous root check.
      if (_current(generation)) _dirty = true;
    } catch (error, trace) {
      onError?.call(error, trace);
      // One delayed retry covers files still being copied / temporarily locked.
      // A failure never replaces the native index or becomes a tight loop.
      if (_current(generation)) {
        _quiet?.cancel();
        _deadline?.cancel();
        _dirty = false;
        if (!_failureRetried) {
          _failureRetried = true;
          _quiet = Timer(recoveryPeriod, () => _request(retry: true));
        }
      }
    }
  }

  void _cancelTimers() {
    _quiet?.cancel();
    _deadline?.cancel();
    _recovery?.cancel();
  }

  Future<void> _cancelSubscription(
      StreamSubscription<FileSystemEvent> subscription) async {
    try {
      await subscription.cancel().timeout(checkTimeout);
    } catch (error, trace) {
      onError?.call(error, trace);
    }
  }

  Future<bool> _checkRoot(String root) async {
    final done = Completer<bool>();
    void finish(bool value) {
      if (!done.isCompleted) done.complete(value);
    }

    void cancel() => finish(false);
    _cancelChecks.add(cancel);
    final timer = Timer(checkTimeout, cancel);
    try {
      unawaited(Future<bool>.sync(() => _accessible(root)).then<void>(finish,
          onError: (Object error, StackTrace trace) {
        onError?.call(error, trace);
        finish(false);
      }));
      return await done.future;
    } finally {
      timer.cancel();
      _cancelChecks.remove(cancel);
    }
  }

  void _abortChecks() {
    for (final cancel in _cancelChecks.toList()) {
      cancel();
    }
  }

  /// Native scanning cannot be cancelled after entry; wait for its transaction
  /// before app teardown. All new events and delayed retries are stopped first.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _cancelTimers();
    _abortChecks();
    await _configuration;
    final subscriptions = _subscriptions.values.toList();
    _subscriptions.clear();
    await Future.wait(subscriptions.map(_cancelSubscription));
    final running = _running;
    if (running != null) await running;
  }
}
