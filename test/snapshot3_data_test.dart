import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:dan_player/data/cache_backup_service.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/smart_condition.dart';
import 'package:dan_player/data/snapshot3_upgrade.dart';
import 'package:dan_player/play_service/eq_preset_store.dart';
import 'package:dan_player/play_service/named_queue_store.dart';
import 'package:dan_player/play_service/seek_target.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const first = 'local:00000000-0000-4000-8000-000000000001';
  const second = 'local:00000000-0000-4000-8000-000000000002';
  late Directory root;
  setUp(() async =>
      root = await Directory.systemTemp.createTemp('dan-snapshot3-test-'));
  tearDown(() async => root.delete(recursive: true));

  test(
      'backup preserves path-like personal text without collecting it as an asset',
      () async {
    final source = Directory('${root.path}/source');
    await source.create();
    final label = '${root.path}/my-personal-label';
    await File(label).writeAsString('must not be included as an asset');
    await File('${source.path}/personal_library.json')
        .writeAsString(jsonEncode({
      'version': 1,
      'tracks': {
        first: {
          'tags': [label]
        }
      }
    }));
    final output = File('${root.path}/backup.zip');
    await const CacheBackupService()
        .exportBackup(source: source, destination: output);
    final archive = ZipDecoder().decodeBytes(await output.readAsBytes());
    final item = archive.files
        .singleWhere((f) => f.name.endsWith('personal_library.json'));
    expect(
        (jsonDecode(utf8.decode(item.content as List<int>)) as Map)['tracks']
            [first]['tags'],
        [label]);
    expect(archive.files.any((f) => f.name.contains('external')), isFalse);
  });

  test('old tracks use creation time once; new tracks keep the commit date',
      () async {
    final file = File('${root.path}/personal.json');
    final library = PersonalLibrary(file);
    final commit = DateTime.utc(2026, 9, 8);
    await library.observeCommitted({first: 1000}, commit);
    expect((await library.snapshot())[first]!.firstAddedAtUtc,
        DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true));
    expect((await library.snapshot())[first]!.addedFromCreation, isTrue);
    await library.observeCommitted({first: 9999, second: 2000}, commit);
    final reloaded = await PersonalLibrary(file).snapshot();
    expect(reloaded[first]!.firstAddedAtUtc!.millisecondsSinceEpoch, 1000000);
    expect(reloaded[second]!.firstAddedAtUtc, commit);
    expect(reloaded[second]!.addedFromCreation, isFalse);
  });

  test(
      'missing added date uses creation fallback without losing rating or tags',
      () async {
    final file = File('${root.path}/personal.json');
    await file.writeAsString(jsonEncode({
      'version': 1,
      'seeded': true,
      'tracks': {
        first: {
          'rating': 5,
          'tags': ['夜', 'Kanon']
        }
      }
    }));
    final library = PersonalLibrary(file);
    await library.observeCommitted({first: 1234}, DateTime.utc(2026));
    final record = (await library.snapshot())[first]!;
    expect(record.firstAddedAtUtc!.millisecondsSinceEpoch, 1234000);
    expect(record.addedFromCreation, isTrue);
    expect(record.rating, 5);
    expect(record.tags, ['夜', 'Kanon']);
  });

  test('unknown creation time is not fabricated and is filled when recovered',
      () async {
    final library = PersonalLibrary(File('${root.path}/personal.json'));
    await library.observeCommitted({first: 0}, DateTime.utc(2026));
    expect((await library.snapshot())[first]!.firstAddedAtUtc, isNull);
    await library.observeCommitted({first: 42}, DateTime.utc(2026));
    expect(
        (await library.snapshot())[first]!
            .firstAddedAtUtc!
            .millisecondsSinceEpoch,
        42000);
  });

  test('newer personal data is protected even with a readable older backup',
      () async {
    final file = File('${root.path}/personal.json');
    await file.writeAsString('{"version":2,"tracks":{}}');
    await File('${file.path}.bak').writeAsString('{"version":1,"tracks":{}}');
    await expectLater(
        PersonalLibrary(file).observeCommitted({first: 1}, DateTime.utc(2026)),
        throwsUnsupportedError);
    expect(await file.readAsString(), '{"version":2,"tracks":{}}');
  });

  test('unknown rating and missing playlist never turn true under NOT', () {
    expect(
        const SmartCondition.term(SmartField.ratingAtLeast, '4', exclude: true)
            .evaluate(first, null, {}),
        RuleTruth.unknown);
    expect(
        const SmartCondition.term(SmartField.playlist, 'missing', exclude: true)
            .evaluate(first, null, {}),
        RuleTruth.unknown);
    const group = SmartCondition.group([
      SmartCondition.term(SmartField.ratingAtLeast, '4'),
      SmartCondition.term(SmartField.personalTag, 'night'),
    ], any: true);
    expect(group.evaluate(first, const PersonalTrack(tags: ['night']), {}),
        RuleTruth.yes);
  });

  test('smart rules reject impossible dates, excessive leaves and depth', () {
    expect(
        () => SmartCondition.fromJson(
            const SmartCondition.term(SmartField.addedAfter, '2026-02-30')
                .toJson()),
        throwsFormatException);
    expect(
        () => SmartCondition.fromJson(SmartCondition.group(List.filled(
                33, const SmartCondition.term(SmartField.personalTag, 'a')))
            .toJson()),
        throwsFormatException);
    expect(
        () => SmartCondition.fromJson(const SmartCondition.group([
              SmartCondition.group([SmartCondition.group([])])
            ]).toJson()),
        throwsFormatException);
  });

  test('precise seek rejects overflow, malformed input and end-of-track', () {
    expect(SeekTarget.parse('01:02:03.125').resolve(0, 4000), 3723.125);
    expect(SeekTarget.parse('+30').resolve(10, 100), 40);
    expect(SeekTarget.parse('-10').resolve(30, 100), 20);
    for (final s in ['NaN', '1:60', '1:99:00', '1.5555', '--1', '']) {
      expect(() => SeekTarget.parse(s), throwsFormatException);
    }
    expect(
        () => SeekTarget.parse('100').resolve(0, 100), throwsFormatException);
    expect(
        () => SeekTarget.parse('-30').resolve(10, 100), throwsFormatException);
  });

  test('finite practice counts each round once and reset clears completion',
      () {
    final loop = SegmentLoopController()
      ..setStart(2, 20)
      ..setEnd(5, 20);
    loop.configurePractice(rounds: 2, interval: 1);
    loop.setEnabled(true);
    expect(loop.targetForPosition(5), 2);
    expect(loop.targetForPosition(5.1), isNull);
    expect(loop.completedRounds, 1);
    loop.targetForPosition(2);
    expect(loop.targetForPosition(5), 2);
    expect(loop.finished, isTrue);
    expect(loop.targetForPosition(6), isNull);
    loop.setStart(1, 20);
    expect(loop.finished, isFalse);
    expect(loop.completedRounds, 0);
    loop.dispose();
  });

  test(
      'queue format preserves distinct duplicate occurrences and rejects mismatched backup',
      () {
    final value = <String, dynamic>{
      'queue': ['1', '2'],
      'backup': ['2', '1'],
      'current': '2',
      'position': 4.5,
      'shuffle': true,
      'slots': {
        '1': {'track': first},
        '2': {'track': first}
      }
    };
    NamedQueueStore.validateSnapshot(value);
    value['backup'] = ['1', '1'];
    expect(
        () => NamedQueueStore.validateSnapshot(value), throwsFormatException);
  });

  test('EQ invalid import never alters saved presets', () async {
    final file = File('${root.path}/eq.json');
    final store = EqPresetStore(file);
    await store.add('Night', List.filled(10, 0.0));
    final previous = await file.readAsString();
    await expectLater(
        store.add('Bad', List.filled(10, double.nan)), throwsFormatException);
    expect(await file.readAsString(), previous);
    expect((await store.list()).length, 1);
  });

  test(
      'upgrade accepts legacy arrays and current statistics but blocks future stores',
      () {
    Snapshot3Upgrade.validateDocument('collections.json', []);
    Snapshot3Upgrade.validateDocument('custom_audio_order.json', []);
    Snapshot3Upgrade.validateDocument(
        'playback_statistics.json', {'version': 2});
    expect(
        () => Snapshot3Upgrade.validateDocument(
            'named_queues.json', {'version': 2}),
        throwsUnsupportedError);
  });
}
