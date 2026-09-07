import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    final parent = Directory(
        Platform.environment['DAN_PLAYER_DATA_DIR'] ?? 'build/qa-custom-order');
    await parent.create(recursive: true);
    directory = await parent.createTemp('order-');
    file = File(p.join(directory.path, 'custom_audio_order.json'));
  });
  tearDown(() => directory.delete(recursive: true));

  test('v1 writes are serialized snapshots and retain previous committed order',
      () async {
    final store = CustomAudioOrderPersistence(file);
    final first = [r'C:\Music\first.flac'];
    final saving = store.save(first);
    first[0] = 'mutated while initializing';
    final second = store.save([r'C:\Music\second.flac']);
    await Future.wait([saving, second]);
    expect((jsonDecode(await file.readAsString()) as Map)['paths'],
        [r'C:\Music\second.flac']);
    expect(
        (jsonDecode(await File('${file.path}.bak').readAsString())
            as Map)['paths'],
        [r'C:\Music\first.flac']);
    expect((jsonDecode(await file.readAsString()) as Map)['version'], 1);
  });

  test('failure before replacement preserves target and permits explicit retry',
      () async {
    final initial = CustomAudioOrderPersistence(file);
    await initial.save(['first']);
    final original = await file.readAsString();
    var fail = true;
    final store = CustomAudioOrderPersistence(file, beforeReplace: () async {
      if (fail) throw const FileSystemException('Injected save failure');
    });
    await expectLater(
        store.save(['next']), throwsA(isA<FileSystemException>()));
    expect(await file.readAsString(), original);
    expect(await File('${file.path}.tmp').exists(), isFalse);
    fail = false;
    await store.save(['next']);
    expect(await CustomAudioOrderPersistence(file).read(), ['next']);
  });

  test('valid backup restores primary while preserving damaged bytes',
      () async {
    final store = CustomAudioOrderPersistence(file);
    await store.save(['first']);
    await store.save(['second']);
    await file.writeAsString('{broken');
    final recovered = CustomAudioOrderPersistence(file);
    expect(await recovered.read(), ['first']);
    expect(recovered.warning, contains('从备份恢复'));
    expect((jsonDecode(await file.readAsString()) as Map)['paths'], ['first']);
    final damaged =
        directory.listSync().where((entry) => entry.path.contains('.damaged-'));
    expect(damaged, hasLength(1));
    expect(await File(damaged.single.path).readAsString(), '{broken');
  });

  test('two damaged copies block later saves until successful recovery',
      () async {
    await file.writeAsString('{broken-primary');
    await File('${file.path}.bak').writeAsString('{broken-backup');
    final store = CustomAudioOrderPersistence(file);
    await expectLater(store.read(), throwsFormatException);
    expect(store.warning, contains('不会覆盖'));
    await expectLater(store.save(['would erase user order']), throwsStateError);
    expect(await file.readAsString(), '{broken-primary');
    expect(await File('${file.path}.bak').readAsString(), '{broken-backup');
    await File('${file.path}.bak').writeAsString(jsonEncode({
      'version': 1,
      'paths': ['recovered']
    }));
    expect(await store.read(), ['recovered']);
    await store.save(['recovered', 'new']);
    expect(
        await CustomAudioOrderPersistence(file).read(), ['recovered', 'new']);
  });

  test('unsupported schema stays protected and missing paths retain order',
      () async {
    await file.writeAsString(jsonEncode({
      'version': 99,
      'paths': ['future']
    }));
    final store = CustomAudioOrderPersistence(file);
    await expectLater(store.read(), throwsFormatException);
    await expectLater(store.save([]), throwsStateError);
    final order = CustomAudioOrder();
    expect(
        order.tryReadFromMap({
          'version': 1,
          'paths': [
            r'Z:\Offline\B.flac',
            r'Z:\Offline\A.flac',
            r'Z:\Offline\B.flac'
          ]
        }),
        isTrue);
    expect(order.paths.take(2), [r'Z:\Offline\B.flac', r'Z:\Offline\A.flac']);
  });
}
