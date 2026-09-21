import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/smart_condition.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Track extends Audio {
  _Track(String id)
      : _id = 'local:00000000-0000-4000-8000-${id.padLeft(12, '0')}',
        super(id, 'Artist', 'Album', 1, 180, 320, 44100,
            'J:/synthetic/smart/$id.flac', 1, 1, 'test');

  final String _id;
  var identityReads = 0;
  @override
  String get stableTrackId {
    identityReads++;
    return _id;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;
  late File personal;

  setUpAll(() async {
    // This suite supplies its own isolated data path, including corrupt data.
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final parent =
        await Directory(p.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    root = await parent.createTemp('smart-boundary-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    final data = await getAppDataDir();
    expect(p.isWithin(root.path, data.path), isTrue);
    personal = File(p.join(data.path, 'personal_library.json'));
    await personal.writeAsString('{damaged unused personal data');
  });
  tearDown(() => PLAYLISTS.clear());
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final parent = p.join(Directory.current.path, 'build', 'test-data');
    final resolved = await root.resolveSymbolicLinks();
    if (!p.isWithin(parent, resolved) ||
        !p.basename(resolved).startsWith('smart-boundary-')) {
      throw StateError('Refusing to delete an unverified test fixture');
    }
    await Directory(resolved).delete(recursive: true);
  });

  test('CUE format rules use the physical source without losing slice identity',
      () async {
    const reference = CueTrackReference(
        cuePath: 'J:/synthetic/album.cue',
        sourcePath: 'J:/synthetic/album.FLAC',
        number: 2,
        startFrame: 750,
        endFrame: 1500);
    final cue = Audio.fromMap({
      'path': reference.identity,
      'title': 'Movement',
      'duration': 10,
      'cue_track': reference.toMap(),
    });
    final matching = await const SmartPlaylist(
            id: 'flac', name: 'Lossless', formats: '.flac, wav')
        .evaluate([cue]);
    expect(matching, [same(cue)]);
    expect(matching.single.cueTrack, same(cue.cueTrack));
    expect(
        await const SmartPlaylist(id: 'mp3', name: 'MP3', formats: 'mp3')
            .evaluate([cue]),
        isEmpty);
  });

  test('cancelled previews never open unrelated personal storage', () async {
    final result = await const SmartPlaylist(
            id: 'cancelled',
            name: 'Cancelled',
            condition: SmartCondition.term(SmartField.ratingAtLeast, '4'))
        .evaluate([_Track('1')], shouldCancel: () => true);
    expect(result, isEmpty);
    expect(await personal.readAsString(), '{damaged unused personal data');
  });

  test('membership-only rules ignore unavailable personal data and other trees',
      () async {
    final first = _Track('1'), second = _Track('2'), unrelated = _Track('3');
    final tree = playlistTree;
    final selected = tree.createPlaylist('Selected');
    final child = tree.createPlaylist('Child', parent: selected);
    tree.addAudio(selected, first);
    tree.addAudio(child, second);
    final outside = tree.createPlaylist('Outside');
    tree.addAudio(outside, unrelated);
    final condition = SmartCondition.group([
      SmartCondition.group([
        SmartCondition.term(SmartField.playlist, selected.id),
        const SmartCondition.term(SmartField.playlist, 'missing'),
      ], any: true),
      const SmartCondition.term(SmartField.playlist, 'missing', exclude: true),
    ], any: true);
    final result =
        await SmartPlaylist(id: 'member', name: 'Members', condition: condition)
            .evaluate([first, second]);
    expect(result, [same(first), same(second)]);
    expect(unrelated.identityReads, 0,
        reason: 'Unreferenced playlists need no membership expansion.');
  });

  test('an empty condition does not inspect any playlist or personal data',
      () async {
    final unrelated = _Track('3');
    final outside = playlistTree.createPlaylist('Outside');
    playlistTree.addAudio(outside, unrelated);
    final result = await const SmartPlaylist(
        id: 'all',
        name: 'All',
        condition: SmartCondition.group([])).evaluate([_Track('1')]);
    expect(result, hasLength(1));
    expect(unrelated.identityReads, 0);
  });

  test('mixed nested all/any/exclude rules retain both required data sources',
      () async {
    final first = _Track('1'), second = _Track('2'), third = _Track('3');
    await personal.writeAsString(jsonEncode({
      'version': 1,
      'tracks': {
        first.stableTrackId: {
          'rating': 5,
          'tags': ['night']
        },
        second.stableTrackId: {
          'rating': 2,
          'tags': ['night']
        },
        third.stableTrackId: {
          'rating': 5,
          'tags': ['day']
        },
      },
    }));
    final selected = playlistTree.createPlaylist('Selected');
    playlistTree.addAudios(selected, [first, second]);
    final rule = SmartPlaylist(
      id: 'mixed',
      name: 'Mixed',
      condition: SmartCondition.group([
        SmartCondition.term(SmartField.playlist, selected.id),
        const SmartCondition.group([
          SmartCondition.term(SmartField.ratingAtLeast, '4'),
          SmartCondition.term(SmartField.personalTag, 'night', exclude: true),
        ], any: true),
      ]),
    );
    expect(await rule.evaluate([first, second, third]), [same(first)]);
    final excluded = SmartPlaylist(
      id: 'excluded',
      name: 'Outside',
      condition: SmartCondition.group([
        SmartCondition.group([
          SmartCondition.term(SmartField.playlist, selected.id, exclude: true),
        ]),
      ]),
    );
    expect(await excluded.evaluate([first, second, third]), [same(third)]);
    const personalOnly = SmartPlaylist(
      id: 'personal',
      name: 'Rated',
      condition: SmartCondition.term(SmartField.ratingAtLeast, '4'),
    );
    final unrelated = _Track('4');
    final outside = playlistTree.createPlaylist('Unrelated');
    playlistTree.addAudio(outside, unrelated);
    expect(await personalOnly.evaluate([first, second, third]),
        [same(first), same(third)]);
    expect(unrelated.identityReads, 0,
        reason: 'Rating conditions must not expand playlist membership.');
  });
}
