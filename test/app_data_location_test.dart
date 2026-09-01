import 'dart:convert';
import 'dart:io';

import 'package:dan_player/data/app_data_location.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory sandbox;
  late File pointer;

  setUp(() async {
    sandbox =
        await Directory.systemTemp.createTemp('dan-player-location-test-');
    pointer = File(path.join(sandbox.path, 'stable', 'data_location.json'));
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('next launch atomically replaces target and promotes pointer', () async {
    final current =
        await Directory(path.join(sandbox.path, 'current')).create();
    final target = await Directory(path.join(sandbox.path, 'target')).create();
    await File(path.join(target.path, 'old.txt')).writeAsString('old');
    final staged = await Directory(path.join(sandbox.path, 'staged')).create();
    await File(path.join(staged.path, appDataReadyMarkerName))
        .writeAsString('ok');
    await File(path.join(staged.path, 'new.txt')).writeAsString('new');

    final store = AppDataLocationStore(pointer);
    await store.schedule(
      nextPath: target.path,
      currentPath: current.path,
      stagedPath: staged.path,
    );
    expect(await store.activatePendingOrReadActive(), target.path);
    expect(await File(path.join(target.path, 'new.txt')).readAsString(), 'new');
    expect(await File(path.join(target.path, 'old.txt')).exists(), isFalse);
    final state = json.decode(await pointer.readAsString()) as Map;
    expect(state['activePath'], target.path);
    expect(state['pendingPath'], isNull);
    expect(state['pendingStagedPath'], isNull);
  });

  test('missing staged restore cannot change the existing pointer', () async {
    final current =
        await Directory(path.join(sandbox.path, 'current')).create();
    await pointer.parent.create(recursive: true);
    await pointer.writeAsString(json.encode({
      'version': 1,
      'activePath': current.path,
      'pendingPath': null,
    }));
    final original = await pointer.readAsString();
    await expectLater(
      AppDataLocationStore(pointer).schedule(
        nextPath: path.join(sandbox.path, 'target'),
        currentPath: current.path,
        stagedPath: path.join(sandbox.path, 'missing'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await pointer.readAsString(), original);
  });

  test('failed activation restores target and clears pending transaction',
      () async {
    final current =
        await Directory(path.join(sandbox.path, 'current')).create();
    final target = await Directory(path.join(sandbox.path, 'target')).create();
    await File(path.join(target.path, 'old.txt')).writeAsString('old');
    // Moving target also moves this intentionally nested staging directory, so
    // activation fails after the old target was renamed and exercises rollback.
    final staged = await Directory(path.join(target.path, 'staged')).create();
    await File(path.join(staged.path, appDataReadyMarkerName))
        .writeAsString('ok');
    final store = AppDataLocationStore(pointer);
    await store.schedule(
      nextPath: target.path,
      currentPath: current.path,
      stagedPath: staged.path,
    );
    expect(await store.activatePendingOrReadActive(), current.path);
    expect(await File(path.join(target.path, 'old.txt')).readAsString(), 'old');
    final state = json.decode(await pointer.readAsString()) as Map;
    expect(state['activePath'], current.path);
    expect(state['pendingPath'], isNull);
  });

  test('startup propagates when rollback has no usable active cache', () async {
    final missingCurrent =
        Directory(path.join(sandbox.path, 'missing-current'));
    final target = await Directory(path.join(sandbox.path, 'target')).create();
    await File(path.join(target.path, 'old.txt')).writeAsString('old');
    // As above, nesting staging makes installation fail after target moved.
    // With no usable active directory, startup must surface the failure rather
    // than create an empty default cache and silently lose the user's state.
    final staged = await Directory(path.join(target.path, 'staged')).create();
    await File(path.join(staged.path, appDataReadyMarkerName))
        .writeAsString('ok');
    final store = AppDataLocationStore(pointer);
    await store.schedule(
      nextPath: target.path,
      currentPath: missingCurrent.path,
      stagedPath: staged.path,
    );

    await expectLater(
      store.activatePendingOrReadActive(),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(path.join(target.path, 'old.txt')).readAsString(), 'old');
    final state = json.decode(await pointer.readAsString()) as Map;
    expect(state['activePath'], missingCurrent.path);
    expect(state['pendingPath'], target.path,
        reason: 'an incomplete transaction remains recoverable for diagnosis');
  });
}
