import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A point in the current process's resource history. Unknown is null, not zero.
class ProcessResourceSample {
  const ProcessResourceSample(
      {required this.time,
      this.cpuPercent,
      this.gpuPercent,
      this.workingSetBytes,
      this.totalPhysicalMemoryBytes,
      this.gpuStatus = 'unavailable',
      this.cpuStatus = 'unavailable'});
  final DateTime time;
  final double? cpuPercent, gpuPercent;
  final int? workingSetBytes, totalPhysicalMemoryBytes;
  final String gpuStatus, cpuStatus;

  /// Current process working set as a share of physical system memory.
  /// A missing denominator cannot be replaced with the observed history peak.
  double? get ramPercent {
    final used = workingSetBytes, total = totalPhysicalMemoryBytes;
    if (used == null ||
        used < 0 ||
        total == null ||
        total <= 0 ||
        used > total) {
      return null;
    }
    return used / total * 100;
  }

  factory ProcessResourceSample.fromMap(
      Map<dynamic, dynamic> map, DateTime time) {
    double? percent(dynamic value) =>
        value is num && value.isFinite && value >= 0 && value <= 100
            ? value.toDouble()
            : null;
    final memory = map['workingSetBytes'];
    final totalMemory = map['totalPhysicalMemoryBytes'];
    final gpu = percent(map['gpuPercent']);
    final cpu = percent(map['cpuPercent']);
    return ProcessResourceSample(
        time: time,
        cpuPercent: cpu,
        cpuStatus: cpu != null
            ? 'ready'
            : map['cpuStatus'] == 'warming'
                ? 'warming'
                : 'unavailable',
        gpuPercent: gpu,
        workingSetBytes: memory is int && memory >= 0 ? memory : null,
        totalPhysicalMemoryBytes:
            totalMemory is int && totalMemory > 0 ? totalMemory : null,
        gpuStatus: gpu != null
            ? 'ready'
            : map['gpuStatus'] == 'warming'
                ? 'warming'
                : 'unavailable');
  }
}

/// One native worker, with serialized close-before-open and no Dart polling.
/// Hidden/removed widgets stop the native worker and reject its late snapshots.
class ProcessResourceService extends ChangeNotifier {
  ProcessResourceService({MethodChannel? channel, DateTime Function()? now})
      : _channel =
            channel ?? const MethodChannel('dan_player/process_resources'),
        _now = now ?? DateTime.now;
  final MethodChannel _channel;
  final DateTime Function() _now;
  static int _nextSession = 0;
  // Routes can overlap while an old native stop acknowledgement is pending.
  // Serialize per channel and never let an old dispose remove the new owner.
  static final _channelTails = <String, Future<void>>{};
  static final _handlerOwners = <String, ProcessResourceService>{};
  Future<void> _tail = Future.value();
  bool _wanted = false, _disposed = false, _handlerInstalled = false;
  int _interval = 5, _runningInterval = 0, _session = 0;
  final List<ProcessResourceSample> _history = [];
  List<ProcessResourceSample> get history => List.unmodifiable(_history);
  ProcessResourceSample? get latest => _history.lastOrNull;
  bool get active => _wanted && _session != 0 && !_disposed;
  bool get unavailable => _unavailable;
  bool _unavailable = false;

  Future<void> setActive(bool value, {int intervalSeconds = 5}) {
    if (_disposed) return _tail;
    final period = [1, 5, 10].contains(intervalSeconds) ? intervalSeconds : 5;
    if (value == _wanted && period == _interval) return _tail;
    _wanted = value;
    _interval = period;
    _enqueue();
    return _tail;
  }

  Future<void> _enqueue() {
    final previous = _channelTails[_channel.name] ?? Future<void>.value();
    _tail = previous.then((_) => _reconcile());
    _channelTails[_channel.name] = _tail;
    return _tail;
  }

  Future<void> _reconcile() async {
    if (_session != 0 &&
        (!_wanted || _disposed || _runningInterval != _interval)) {
      final old = _session;
      _session = 0; // Reject already queued events before native shutdown.
      try {
        await _channel.invokeMethod<void>('stop', {'session': old});
      } catch (_) {
        _unavailable = true;
      }
    }
    if (_wanted && !_disposed && _session == 0) {
      final previous = _handlerOwners[_channel.name];
      if (previous != null && previous != this && previous._session != 0) {
        final old = previous._session;
        previous._wanted = false;
        previous._session = 0;
        try {
          await _channel.invokeMethod<void>('stop', {'session': old});
        } catch (_) {
          _unavailable = true;
          return;
        }
      }
      if (_handlerOwners[_channel.name] != this) {
        _handlerInstalled = true;
        _handlerOwners[_channel.name] = this;
        _channel.setMethodCallHandler(_onMethod);
      }
      final current = _session = ++_nextSession;
      _runningInterval = _interval;
      _unavailable = false;
      _history.clear();
      try {
        await _channel.invokeMethod<void>(
            'start', {'session': current, 'intervalSeconds': _runningInterval});
      } catch (_) {
        if (_session == current) {
          _session = 0;
          _unavailable = true;
        }
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _onMethod(MethodCall call) async {
    if (_disposed || !_wanted || _session == 0 || call.method != 'sample') {
      return;
    }
    final map = call.arguments;
    if (map is! Map ||
        map['session'] != _session ||
        _interval != _runningInterval) {
      return;
    }
    _history.add(ProcessResourceSample.fromMap(map, _now()));
    if (_history.length > 60) _history.removeAt(0);
    notifyListeners();
  }

  /// Awaitable for lifecycle tests/hosts which must finish closing before reuse.
  Future<void> get settled => _tail;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _wanted = false;
    _tail = _enqueue().whenComplete(() {
      if (_handlerInstalled && _handlerOwners[_channel.name] == this) {
        _handlerOwners.remove(_channel.name);
        _channel.setMethodCallHandler(null);
      }
    });
    super.dispose();
  }
}
