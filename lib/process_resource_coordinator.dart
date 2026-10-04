import 'package:flutter/foundation.dart';

import 'process_resource_service.dart';

/// Combines visible resource surfaces into one native sampling session.
/// Views own leases, so leaving one view cannot stop another visible surface.
class ProcessResourceCoordinator {
  ProcessResourceCoordinator._(this.service);

  @visibleForTesting
  ProcessResourceCoordinator.forTesting(
      {required ProcessResourceService service})
      : this._(service);

  static ProcessResourceCoordinator? _instance;
  static ProcessResourceCoordinator get instance =>
      _instance ??= ProcessResourceCoordinator._(ProcessResourceService());

  final ProcessResourceService service;
  final Set<ProcessResourceLease> _leases = {};
  bool _disposed = false;
  int _intervalSeconds = 5;

  /// Acquiring a lease does not begin sampling until the view becomes visible.
  ProcessResourceLease acquire() {
    if (_disposed) throw StateError('Resource coordinator is disposed.');
    final lease = ProcessResourceLease._(this);
    _leases.add(lease);
    return lease;
  }

  Future<void> _update(ProcessResourceLease lease, bool active,
      {required int intervalSeconds}) {
    if (_disposed || lease._disposed) return service.settled;
    lease._active = active;
    // All surfaces use the same preference. A hidden view may still close with
    // an old value while route handoff is underway; it must not reconfigure the
    // remaining visible consumer's worker.
    if (active) {
      _intervalSeconds =
          [1, 5, 10].contains(intervalSeconds) ? intervalSeconds : 5;
    }
    return _reconcile();
  }

  Future<void> _reconcile() =>
      service.setActive(!_disposed && _leases.any((lease) => lease._active),
          intervalSeconds: _intervalSeconds);

  void _release(ProcessResourceLease lease) {
    if (!_leases.remove(lease) || _disposed) return;
    _reconcile();
  }

  Future<void> get settled => service.settled;

  /// Production keeps its idle singleton; injected coordinators can be closed
  /// after their final host has gone away.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final lease in _leases) {
      lease._disposed = true;
      lease._active = false;
    }
    _leases.clear();
    service.dispose();
  }
}

class ProcessResourceLease {
  ProcessResourceLease._(this._coordinator);

  final ProcessResourceCoordinator _coordinator;
  bool _active = false, _disposed = false;

  ProcessResourceService get service => _coordinator.service;
  Future<void> get settled => service.settled;

  Future<void> setActive(bool value, {int intervalSeconds = 5}) =>
      _coordinator._update(this, value, intervalSeconds: intervalSeconds);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _active = false;
    _coordinator._release(this);
  }
}
