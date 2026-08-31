import 'dart:async';

import 'package:dan_player/app_shutdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('failed close releases the quit lock and a later quit can retry',
      () async {
    final coordinator = AppShutdownCoordinator();
    var calls = 0;
    Future<void> close() async {
      calls++;
      if (calls == 1) throw StateError('synthetic close failure');
    }

    await coordinator.run(close);
    expect(coordinator.isShuttingDown, isFalse);
    await coordinator.run(close);
    expect(calls, 2);
    expect(coordinator.isShuttingDown, isTrue);
    await coordinator.run(close);
    expect(calls, 2);
  });

  test('update caller sees close failure without permanently locking quit',
      () async {
    final coordinator = AppShutdownCoordinator();
    await expectLater(
      coordinator.run(() async => throw StateError('close failed'),
          throwOnError: true),
      throwsStateError,
    );
    expect(coordinator.isShuttingDown, isFalse);
    await coordinator.run(() async {}, throwOnError: true);
    expect(coordinator.isShuttingDown, isTrue);
  });

  test('concurrent update does not mistake an in-flight quit for completion',
      () async {
    final coordinator = AppShutdownCoordinator();
    final closing = Completer<void>();
    var calls = 0;
    var updateCompleted = false;
    Future<void> close() {
      calls++;
      return closing.future;
    }

    final ordinary = coordinator.run(close);
    final update = coordinator.run(close, throwOnError: true)
      ..then<void>((_) {
        updateCompleted = true;
      }, onError: (_) {});
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(updateCompleted, isFalse);
    final failed = expectLater(update, throwsStateError);
    closing.completeError(StateError('synthetic failure'));
    await ordinary;
    await failed;
    expect(coordinator.isShuttingDown, isFalse);
    expect(updateCompleted, isFalse);
  });

  test('synchronous errors are observed and can be retried', () async {
    final coordinator = AppShutdownCoordinator();
    await expectLater(
      coordinator.run(() => throw StateError('sync'), throwOnError: true),
      throwsStateError,
    );
    expect(coordinator.isShuttingDown, isFalse);
    await coordinator.run(() async {});
    expect(coordinator.isShuttingDown, isTrue);
  });
}
