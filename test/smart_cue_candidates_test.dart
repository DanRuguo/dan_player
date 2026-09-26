import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_ui_actions.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/smart_condition.dart';
import 'package:dan_player/library/smart_library_candidates.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/playlist_actions.dart';

Audio _file(String name) => Audio(name, 'Artist', 'Album', 1, 300, 900, 48000,
    'C:\\unmounted-smart-fixture\\$name.flac', 1, 1, 'fixture');

Audio _cue(int number) {
  final reference = CueTrackReference(
      cuePath: r'C:\unmounted-smart-fixture\album.cue',
      sourcePath: r'C:\unmounted-smart-fixture\album.flac',
      number: number,
      startFrame: (number - 1) * 75 * 60,
      endFrame: number * 75 * 60);
  return _CueAudio(number, reference);
}

class _CueAudio extends Audio {
  _CueAudio(int number, CueTrackReference reference)
      : super('CUE $number', 'CUE artist', 'CUE album', number, 60, 900, 48000,
            reference.identity, 1, 1, 'CUE',
            cueTrack: reference,
            composer: 'CUE composer',
            language: 'ja',
            fileSizeBytes: 8192);

  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) =>
      SynchronousFuture<ImageProvider?>(null);
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() complete) async {
  await tester.runAsync(() async {
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (complete()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('CUE smart preview did not finish: '
        '${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).join(' | ')}');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory data;

  setUpAll(() async {
    final temporary = await Directory.systemTemp.createTemp('smart-cue-data-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => temporary.path);
    data = await getAppDataDir();
    final qa = p.join(Directory.current.parent.path, 'tool', 'qa-local');
    expect(p.isWithin(qa, data.path) || p.isWithin(temporary.path, data.path),
        isTrue,
        reason: 'Never write a fixture in the real user profile.');
  });

  setUp(() async {
    uiLanguage.value = UiLanguage.zh;
    await File(p.join(data.path, 'playlists.json')).writeAsString(jsonEncode({
      'version': 4,
      'playlists': [],
      'trash': [],
      'migratedCollectionKeys': [],
      'legacyCollectionsMigrated': true,
    }));
    await readPlaylists();
    expect(playlistsReadBlocked, isFalse);
    playlistUiSaveError.value = null;
    playlistUiSaving.value = false;
  });

  test(
      'nested direct CUE references are deduplicated; unrelated references stay out',
      () {
    final indexed = _file('indexed');
    final first = _cue(1);
    final other = _cue(2);
    final duplicate = Audio.fromMap(first.toMap());
    final roots = <Playlist>[];
    final tree = PlaylistTree(roots);
    final parent = tree.createPlaylist('Parent');
    final child = tree.createPlaylist('Child', parent: parent);
    tree.addAudio(parent, first);
    tree.addAudio(child, duplicate);
    tree.addAudio(child, other);
    tree.addAudio(child, _file('unindexed-missing'));
    tree.addAudio(
        child,
        Audio.online(
            provider: 'qq',
            id: 'playlist-only',
            title: 'Online',
            artist: 'Artist',
            album: 'Album',
            duration: 60));
    final candidates = smartLibraryCandidates([indexed], tree: tree);
    expect(candidates, [same(indexed), same(first), same(other)]);
    expect(candidates.last.language, 'ja');
    expect(candidates.last.composer, 'CUE composer');
    expect(candidates.last.localFilePath, other.localFilePath);
  });

  test(
      'indexed descriptors win; one physical source does not collapse its CUE tracks',
      () {
    final source = _file('album');
    final first = _cue(1);
    final saved = Audio.fromMap(first.toMap())..title = 'Older saved title';
    final tree = PlaylistTree([]);
    final list = tree.createPlaylist('Saved');
    tree.addAudio(list, saved);
    tree.addAudio(list, _cue(2));
    final online = Audio.online(
        provider: 'qq',
        id: 'indexed-online',
        title: 'Online',
        artist: 'Artist',
        album: 'Album',
        duration: 60);
    expect(smartLibraryCandidates([source, first, first, online], tree: tree),
        [same(source), same(first), same(online), isA<Audio>()]);
    expect(smartLibraryCandidates([source, first], tree: tree).last.track, 2);
  });

  test(
      'default candidates follow CUE add and removal from the live ordinary tree',
      () {
    final tree = playlistTree;
    final list = tree.createPlaylist('CUE');
    final cue = _cue(1);
    tree.addAudio(list, cue);
    expect(smartLibraryCandidates([]), [same(cue)]);
    tree.removeAudioReferences(cue.path);
    expect(smartLibraryCandidates([]), isEmpty);
  });

  test('successful reload and submitted memory snapshots notify consumers',
      () async {
    final tree = playlistTree;
    tree.createPlaylistFromAudios('CUE', [_cue(1)]);
    final beforeSave = playlistChanges.value;
    final save = savePlaylists();
    expect(playlistChanges.value, beforeSave + 1);
    await save;
    PLAYLISTS.clear();
    final beforeRead = playlistChanges.value;
    await readPlaylists();
    expect(playlistChanges.value, beforeRead + 1);
    expect(smartLibraryCandidates([]).single.isCueTrack, isTrue);
  });

  test('failed persistence still publishes valid CUE memory and permits retry',
      () async {
    final tree = playlistTree;
    final list = tree.createPlaylist('CUE');
    tree.addAudio(list, _cue(1));
    final obstruction = Directory(p.join(data.path, 'playlists.json.tmp'));
    await obstruction.create();
    final before = playlistChanges.value;
    try {
      await expectLater(savePlaylists(), throwsA(isA<FileSystemException>()));
      expect(playlistChanges.value, before + 1);
      expect(smartLibraryCandidates([]).single.isCueTrack, isTrue);
      expect(playlistsHaveUnsavedChanges, isTrue);
    } finally {
      await obstruction.delete();
      await savePlaylists();
    }
  });

  test('failed read keeps CUE candidates and does not publish a replacement',
      () async {
    final list = playlistTree.createPlaylistFromAudios('Kept CUE', [_cue(1)]);
    final original = list.audios.values.single;
    final before = playlistChanges.value;
    final primary = File(p.join(data.path, 'playlists.json'));
    final backup = File('${primary.path}.bak');
    await primary.writeAsString('{damaged');
    await backup.writeAsString('{damaged');
    await readPlaylists();
    expect(playlistsReadBlocked, isTrue);
    expect(playlistChanges.value, before);
    expect(smartLibraryCandidates([]), [same(original)]);
    // Restore only this isolated fixture so later tests can read normally.
    await primary.writeAsString(jsonEncode({
      'version': 4,
      'playlists': [],
      'trash': [],
      'migratedCollectionKeys': [],
      'legacyCollectionsMigrated': true,
    }));
    await readPlaylists();
    expect(playlistsReadBlocked, isFalse);
  });

  testWidgets(
      'real PlaylistBrowser smart entry refreshes when CUE playlists change',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() =>
        SmartPlaylistStore(File(p.join(data.path, 'smart_playlists.json')))
            .upsert(const SmartPlaylist(
                id: 'cue-rule',
                name: 'CUE only',
                condition: SmartCondition.term(SmartField.cueTrack, 'true'))));
    final tree = playlistTree;
    final list = tree.createPlaylist('CUE');
    final first = _cue(1);
    tree.addAudio(list, first);
    await tester.runAsync(savePlaylists);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: UiLanguageScope(child: child!)),
        home: Scaffold(
            body: PlaylistBrowser(
                tree: tree,
                initialPlaylist: list,
                library: [_file('album')],
                persist: savePlaylists,
                onPlay: (_, __) {},
                trackBuilder: (_, audio, __, ___) => Text(audio.title)))));
    await tester.pumpAndSettle();
    await tapPlaylistAction(tester, 'playlist-smart-playlists');
    final savedRule = find.byKey(const ValueKey('smart-rule-cue-rule'));
    await _pumpUntil(tester, () => savedRule.evaluate().isNotEmpty);
    await tester.tap(savedRule);
    await _pumpUntil(
        tester,
        () => find
            .byKey(ValueKey('smart-result-${first.path}'))
            .evaluate()
            .isNotEmpty);
    expect(find.byKey(ValueKey('smart-result-${first.path}')), findsOneWidget);
    final second = _cue(2);
    tree.addAudio(list, second);
    await tester.runAsync(savePlaylists);
    await _pumpUntil(
        tester,
        () => find
            .byKey(ValueKey('smart-result-${second.path}'))
            .evaluate()
            .isNotEmpty);
    expect(find.byKey(ValueKey('smart-result-${second.path}')), findsOneWidget);
    tree.removeAudioReferences(first.path);
    await tester.runAsync(savePlaylists);
    await _pumpUntil(
        tester,
        () =>
            find
                .byKey(ValueKey('smart-result-${first.path}'))
                .evaluate()
                .isEmpty &&
            find
                .byKey(ValueKey('smart-result-${second.path}'))
                .evaluate()
                .isNotEmpty);
    expect(find.byKey(ValueKey('smart-result-${first.path}')), findsNothing);
    expect(find.byKey(ValueKey('smart-result-${second.path}')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
