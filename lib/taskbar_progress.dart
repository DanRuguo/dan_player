import 'dart:async';

import 'package:flutter/foundation.dart';

enum TaskbarProgressState { none, indeterminate, normal, paused, error }

@immutable
class TaskbarProgressValue {
  const TaskbarProgressValue._(this.state, [this.completed = 0]);
  static const none = TaskbarProgressValue._(TaskbarProgressState.none);
  static const indeterminate =
      TaskbarProgressValue._(TaskbarProgressState.indeterminate);

  factory TaskbarProgressValue.fraction(double fraction,
      {bool paused = false}) {
    if (!fraction.isFinite) return indeterminate;
    return TaskbarProgressValue._(
        paused ? TaskbarProgressState.paused : TaskbarProgressState.normal,
        (fraction.clamp(0.0, 1.0) * 1000).round());
  }

  final TaskbarProgressState state;
  final int completed;

  Map<String, Object> toMap() => {
        'state': state.name,
        if (state == TaskbarProgressState.normal ||
            state == TaskbarProgressState.paused ||
            state == TaskbarProgressState.error) ...{
          'completed': completed,
          'total': 1000,
        },
      };

  @override
  bool operator ==(Object other) =>
      other is TaskbarProgressValue &&
      state == other.state &&
      completed == other.completed;

  @override
  int get hashCode => Object.hash(state, completed);
}

/// A passive registry, independent of Windows, the UI and audio startup.
/// The newest running operation owns the one Shell progress indicator. An
/// older operation cannot steal it by reporting more frequently.
class TaskbarProgress extends ValueNotifier<TaskbarProgressValue?> {
  TaskbarProgress() : super(null);
  static final instance = TaskbarProgress();
  final _tasks = <TaskbarProgressTask>[];
  bool _closed = false;

  TaskbarProgressTask begin() {
    if (_closed) throw StateError('Taskbar progress registry is closed');
    final task = TaskbarProgressTask._(this);
    _tasks.add(task);
    value = task._value;
    return task;
  }

  void _update(TaskbarProgressTask task) {
    if (!_closed && _tasks.isNotEmpty && identical(_tasks.last, task)) {
      value = task._value;
    }
  }

  void _end(TaskbarProgressTask task) {
    if (_closed) return;
    _tasks.remove(task);
    value = _tasks.lastOrNull?._value;
  }

  @override
  void dispose() {
    _closed = true;
    _tasks.clear();
    super.dispose();
  }
}

class TaskbarProgressTask {
  TaskbarProgressTask._(this._owner);
  final TaskbarProgress _owner;
  var _value = TaskbarProgressValue.indeterminate;
  bool _closed = false;

  /// Null/unknown totals use the system's indeterminate animation. No fake
  /// percentage, Flutter frame, timer or disk write is generated here.
  void update(double? fraction) {
    if (_closed) return;
    _value = fraction == null
        ? TaskbarProgressValue.indeterminate
        : TaskbarProgressValue.fraction(fraction);
    _owner._update(this);
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _owner._end(this);
  }
}

typedef TaskbarProgressInvoke = Future<Object?> Function(
    String method, Map<String, Object> arguments);

/// Coalesces task and playback reports into at most four value updates/second.
/// State changes (loading, pause, completion) are immediate. There is no
/// recurring timer: an unchanged/paused/idle indicator does no polling work.
class TaskbarProgressPublisher {
  TaskbarProgressPublisher({
    required this.operations,
    required this.invoke,
    this.onError,
    this.interval = const Duration(milliseconds: 250),
  }) {
    operations.addListener(_refresh);
    _refresh();
  }

  final ValueListenable<TaskbarProgressValue?> operations;
  final TaskbarProgressInvoke invoke;
  final void Function(Object)? onError;
  final Duration interval;
  var _playback = TaskbarProgressValue.none;
  var _desired = TaskbarProgressValue.none;
  TaskbarProgressValue? _sent = TaskbarProgressValue.none;
  Timer? _gate;
  Future<void>? _flight;
  bool _closed = false;
  bool _failed = false;

  void setPlayback(TaskbarProgressValue value) {
    if (_closed || value == _playback) return;
    _playback = value;
    _refresh();
  }

  /// Explicit recovery only; a failed native channel must not retry for every
  /// incoming audio position. Explorer recreation also replays on the native
  /// side without waiting for a Dart playback change.
  void retry() {
    if (_closed) return;
    _failed = false;
    _sent = null;
    _refresh();
  }

  void _refresh() {
    if (_closed) return;
    _desired = operations.value ?? _playback;
    if (_sent?.state != _desired.state) {
      _gate?.cancel();
      _gate = null;
    }
    _drain();
  }

  void _drain() {
    if (_closed ||
        _failed ||
        _flight != null ||
        _gate != null ||
        _desired == _sent) {
      return;
    }
    final value = _desired;
    // Schedule invocation after assigning _flight; synchronous adapters and
    // reentrant operation notifications cannot create overlapping sends.
    _flight = Future<void>.microtask(() async {
      if (_closed) return;
      try {
        await invoke('setProgress', value.toMap());
        _sent = value;
      } catch (error) {
        _failed = true;
        onError?.call(error);
      }
    }).whenComplete(() {
      _flight = null;
      if (_closed || _failed) return;
      if (_desired.state == value.state) {
        _gate = Timer(interval, () {
          _gate = null;
          _drain();
        });
      }
      _drain();
    });
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    operations.removeListener(_refresh);
    _gate?.cancel();
    _gate = null;
    await _flight;
    if (_sent != TaskbarProgressValue.none || _failed) {
      try {
        await invoke('setProgress', TaskbarProgressValue.none.toMap());
      } catch (_) {
        // Native DesktopIntegration.Dispose clears Shell state as well.
      }
    }
  }
}
