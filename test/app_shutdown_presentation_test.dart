import 'dart:async';

import 'package:dan_player/app_shutdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native desktop teardown waits for the parent to finish hiding',
      () async {
    final hidden = Completer<void>();
    final calls = <String>[];
    final future = prepareWindowForShutdown(
      hideWindow: () {
        calls.add('hide');
        return hidden.future;
      },
      disposeDesktop: () async => calls.add('dispose-desktop'),
      onHideError: (error, trace) => fail('unexpected hide error: $error'),
    );
    await Future<void>.value();
    expect(calls, ['hide']);
    hidden.complete();
    await future;
    expect(calls, ['hide', 'dispose-desktop']);
  });

  test('a hide failure is reported but does not skip resource cleanup',
      () async {
    final calls = <String>[];
    final failure = StateError('synthetic hide failure');
    await prepareWindowForShutdown(
      hideWindow: () async {
        calls.add('hide');
        throw failure;
      },
      disposeDesktop: () async => calls.add('dispose-desktop'),
      onHideError: (error, trace) {
        expect(error, same(failure));
        calls.add('report-hide');
      },
    );
    expect(calls, ['hide', 'report-hide', 'dispose-desktop']);
  });

  test('native disposal errors propagate only after hiding', () async {
    final calls = <String>[];
    final failure = StateError('synthetic desktop disposal failure');
    await expectLater(
      prepareWindowForShutdown(
        hideWindow: () async => calls.add('hide'),
        disposeDesktop: () async {
          calls.add('dispose-desktop');
          throw failure;
        },
        onHideError: (error, trace) => fail('unexpected hide error'),
      ),
      throwsA(same(failure)),
    );
    expect(calls, ['hide', 'dispose-desktop']);
  });
}
