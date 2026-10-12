import 'dart:async';
import 'dart:io';

import 'package:dan_player/component/batch_audio_metadata_dialog.dart';
import 'package:dan_player/component/cover_repair_dialog.dart';
import 'package:dan_player/component/local_lyric_batch_dialog.dart';
import 'package:dan_player/component/personal_library_dialog.dart';
import 'package:dan_player/component/playlist_exchange_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_metadata_update.dart';
import 'package:dan_player/library/batch_audio_metadata.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/cover_repair.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/playlist_exchange.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/music_category_fixtures.dart';

class _Invocation {
  bool? result;
  Future<bool>? pending;
}

class _PendingPersonalStore extends PersonalLibrary {
  _PendingPersonalStore(super.file);
  final started = Completer<void>();
  final finish = Completer<void>();
  Object? failure;

  @override
  Future<void> apply(Iterable<Audio> targets,
      {bool changeRating = false,
      int? rating,
      bool changeTags = false,
      List<String> addTags = const [],
      List<String> removeTags = const []}) async {
    started.complete();
    await finish.future;
    if (failure != null) throw failure!;
    await super.apply(targets,
        changeRating: changeRating,
        rating: rating,
        changeTags: changeTags,
        addTags: addTags,
        removeTags: removeTags);
  }
}

class _PendingLyricStore extends LyricDocumentStore {
  _PendingLyricStore(Directory directory) : super(storageDirectory: directory);
  final started = Completer<void>();
  final finish = Completer<void>();
  var calls = 0;

  @override
  Future<Set<String>> selectLocalBatch(
      List<({Audio audio, Lyric lyric, int revision})> entries,
      {bool keepOffset = true}) async {
    calls++;
    if (calls == 1) {
      started.complete();
      await finish.future;
    }
    return super.selectLocalBatch(entries, keepOffset: keepOffset);
  }
}

Future<_Invocation> _open(
    WidgetTester tester, Future<bool> Function(BuildContext) action) async {
  final invocation = _Invocation();
  tester.view.physicalSize = const Size(1100, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!),
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                  onPressed: () {
                    invocation.pending = action(context).then((result) {
                      invocation.result = result;
                      return result;
                    });
                  },
                  child: const Text('open'))))));
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return invocation;
}

// Real file/Isolate work is allowed to finish outside the fake widget clock.
// The bounded wait never drives an indeterminate progress ticker to "settled".
Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), isTrue, reason: 'The controlled operation must finish');
  expect(tester.takeException(), isNull);
}

Future<void> _press(WidgetTester tester, String label) async {
  final button = find.text(label).hitTestable();
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}

Future<void> _close(WidgetTester tester, _Invocation invocation,
    {String label = '关闭'}) async {
  await _press(tester, label);
  await _until(tester, () => invocation.result != null);
}

MetadataFileSnapshot _snapshot(Audio audio, {bool readOnly = false}) =>
    MetadataFileSnapshot(
        fingerprint: '100_1',
        title: audio.title,
        artist: audio.artist,
        album: audio.album,
        readOnly: readOnly);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory directory;
  var fixture = 0;
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() async {
    final parent = Directory(p.join(Directory.current.parent.path, 'tool',
        'qa-local', 'selection-folders-oct11', 'batch-commit'));
    await parent.create(recursive: true);
    root = await parent.createTemp('results-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => root.path);
    await TrackIdentityRegistry.instance.initialize(directory: root);
  });
  setUp(() async {
    uiLanguage.value = UiLanguage.zh;
    directory = await Directory(p.join(root.path, '${fixture++}')).create();
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
  });

  testWidgets(
      'M3U dialog cancellation returns false without opening the picker',
      (tester) async {
    var picks = 0;
    final invocation = await _open(
        tester,
        (context) =>
            exportM3uPlaylist(context, [CategoryTestAudio('a')], pickFile: (_) {
              picks++;
              return null;
            }));
    await _close(tester, invocation, label: '取消');
    expect(invocation.result, isFalse);
    expect(picks, 0);
  });

  testWidgets('M3U picker cancellation and invalid suffix never report commit',
      (tester) async {
    for (final destination in [null, p.join(directory.path, 'wrong.txt')]) {
      final invocation = await _open(
          tester,
          (context) => exportM3uPlaylist(context, [CategoryTestAudio('a')],
              pickFile: (_) => destination));
      await tester.tap(find.byKey(const ValueKey('m3u-export-confirm')));
      await _until(tester, () => invocation.result != null);
      expect(invocation.result, isFalse);
      if (destination != null) {
        expect(
            await tester.runAsync(() => File(destination).exists()), isFalse);
      }
    }
  });

  testWidgets(
      'M3U success is published only after the real file preserves repeats',
      (tester) async {
    final output = File(p.join(directory.path, 'actual.m3u8'));
    final a = CategoryTestAudio('a'), b = CategoryTestAudio('b');
    final invocation = await _open(
        tester,
        (context) => exportM3uPlaylist(context, [a, b, a],
            pickFile: (_) => output.path));
    expect(invocation.result, isNull);
    await tester.tap(find.byKey(const ValueKey('m3u-export-confirm')));
    await _until(tester, () => invocation.result != null);
    expect(invocation.result, isTrue);
    final text = await tester.runAsync(output.readAsString);
    expect(
        parseM3u(text!, playlistPath: output.path).entries.map((e) => e.path), [
      a.path.replaceAll('/', '\\'),
      b.path.replaceAll('/', '\\'),
      a.path.replaceAll('/', '\\')
    ]);
  });

  testWidgets('M3U failed real destination write returns false',
      (tester) async {
    final invocation = await _open(
        tester,
        (context) => exportM3uPlaylist(context, [CategoryTestAudio('a')],
            pickFile: (_) => p.join(directory.path, 'missing', 'fail.m3u8')));
    await tester.tap(find.byKey(const ValueKey('m3u-export-confirm')));
    await _until(tester, () => invocation.result != null);
    expect(invocation.result, isFalse);
  });

  testWidgets('personal cancel and empty targets do not report a saved draft',
      (tester) async {
    final store =
        PersonalLibrary(File(p.join(directory.path, 'personal.json')));
    final invocation = await _open(
        tester,
        (context) => showPersonalTrackEditor(context, [CategoryTestAudio('a')],
            store: store));
    await _until(
        tester,
        () =>
            tester
                .widget<ChoiceChip>(find.byType(ChoiceChip).first)
                .onSelected !=
            null);
    await _close(tester, invocation, label: '取消');
    expect(invocation.result, isFalse);
    final empty = await _open(tester,
        (context) => showPersonalTrackEditor(context, [], store: store));
    await _until(tester, () => empty.result != null);
    expect(empty.result, isFalse);
    expect(find.byType(PersonalTrackEditor), findsNothing);
  });

  testWidgets(
      'personal commit waits for persistence and survives a fresh store read',
      (tester) async {
    final file = File(p.join(directory.path, 'personal.json'));
    final store = _PendingPersonalStore(file);
    final audio = CategoryTestAudio('personal');
    final invocation = await _open(tester,
        (context) => showPersonalTrackEditor(context, [audio], store: store));
    await _until(
        tester,
        () =>
            tester
                .widget<ChoiceChip>(find.byType(ChoiceChip).first)
                .onSelected !=
            null);
    await _press(tester, '★★★');
    await _press(tester, '保存');
    expect(store.started.isCompleted, isTrue);
    expect(invocation.result, isNull);
    store.finish.complete();
    await _until(tester, () => invocation.result != null);
    expect(invocation.result, isTrue);
    final saved = await tester.runAsync(() => PersonalLibrary(file).snapshot());
    expect(saved![audio.stableTrackId]!.rating, 3);
  });

  testWidgets(
      'personal failed persistence keeps the draft and cancel returns false',
      (tester) async {
    final store =
        _PendingPersonalStore(File(p.join(directory.path, 'personal.json')))
          ..failure = StateError('controlled persistence failure');
    final invocation = await _open(
        tester,
        (context) => showPersonalTrackEditor(context, [CategoryTestAudio('a')],
            store: store));
    await _until(
        tester,
        () =>
            tester
                .widget<ChoiceChip>(find.byType(ChoiceChip).first)
                .onSelected !=
            null);
    await _press(tester, '★★');
    await _press(tester, '保存');
    store.finish.complete();
    await _until(
        tester, () => find.textContaining('保存失败，草稿已保留').evaluate().isNotEmpty);
    expect(invocation.result, isNull);
    await _close(tester, invocation, label: '取消');
    expect(invocation.result, isFalse);
  });

  testWidgets('local lyric picker cancellation and failure return false',
      (tester) async {
    for (final fails in [false, true]) {
      final invocation = await _open(
          tester,
          (context) => showLocalLyricBatch(context, [CategoryTestAudio('a')],
                  pickDirectory: () {
                if (fails) throw StateError('controlled picker failure');
                return null;
              }));
      await _until(tester, () => invocation.result != null);
      expect(invocation.result, isFalse);
      expect(find.byType(LocalLyricBatchDialog), findsNothing);
    }
  });

  Future<(Audio, LyricDocumentStore)> localFixture(String id) async {
    await File(p.join(directory.path, '$id.lrc'))
        .writeAsString('[00:01.00]Actual saved lyric');
    final store = LyricDocumentStore(storageDirectory: directory);
    addTearDown(store.dispose);
    return (
      CategoryTestAudio(id, path: p.join(directory.path, '$id.mp3')),
      store
    );
  }

  Future<void> localReady(WidgetTester tester) => _until(
      tester,
      () =>
          find.byType(LocalLyricBatchDialog).evaluate().isNotEmpty &&
          tester
                  .widget<FilledButton>(
                      find.widgetWithText(FilledButton, '确认关联'))
                  .onPressed !=
              null);

  testWidgets('local lyric preview alone is not a commit', (tester) async {
    final (audio, store) = await tester.runAsync(() => localFixture('local'))
        as (Audio, LyricDocumentStore);
    final invocation = await _open(
        tester,
        (context) => showLocalLyricBatch(context, [audio],
            pickDirectory: () => directory, store: store));
    await localReady(tester);
    await _close(tester, invocation);
    expect(invocation.result, isFalse);
    expect(store.forAudio(audio), isNull);
  });

  testWidgets('local lyric completed commit has a durable locked document',
      (tester) async {
    final (audio, store) = await tester.runAsync(() => localFixture('saved'))
        as (Audio, LyricDocumentStore);
    final invocation = await _open(
        tester,
        (context) => showLocalLyricBatch(context, [audio, audio],
            pickDirectory: () => directory, store: store));
    await localReady(tester);
    await _press(tester, '确认关联');
    await _until(tester, () => store.forAudio(audio)?.locked == true);
    await localReady(tester);
    await _close(tester, invocation);
    expect(invocation.result, isTrue);
    final restored = LyricDocumentStore(storageDirectory: directory);
    addTearDown(restored.dispose);
    await tester.runAsync(restored.load);
    expect(
        (restored.forAudio(audio)!.render()!.lines.single as UnsyncLyricLine)
            .content,
        'Actual saved lyric');
  });

  testWidgets('local lyric late revision conflict never claims a commit',
      (tester) async {
    final (audio, store) = await tester.runAsync(() => localFixture('conflict'))
        as (Audio, LyricDocumentStore);
    final invocation = await _open(
        tester,
        (context) => showLocalLyricBatch(context, [audio],
            pickDirectory: () => directory, store: store));
    await localReady(tester);
    await tester.runAsync(() => store.setNoLyrics(audio, true));
    await _press(tester, '确认关联');
    await _until(
        tester, () => find.textContaining('修订冲突').evaluate().isNotEmpty);
    await _close(tester, invocation);
    expect(invocation.result, isFalse);
    expect(store.forAudio(audio)!.noLyrics, isTrue);
  });

  testWidgets(
      'local lyric partial cancellation retains saved documents but returns false',
      (tester) async {
    final audios = <Audio>[];
    await tester.runAsync(() async {
      for (var i = 0; i < 17; i++) {
        await File(p.join(directory.path, 'part-$i.lrc'))
            .writeAsString('[00:01.00]Part $i');
        audios.add(CategoryTestAudio('part-$i',
            path: p.join(directory.path, 'part-$i.mp3')));
      }
    });
    final store = _PendingLyricStore(directory);
    addTearDown(store.dispose);
    final invocation = await _open(
        tester,
        (context) => showLocalLyricBatch(context, audios,
            pickDirectory: () => directory, store: store));
    await localReady(tester);
    await _press(tester, '确认关联');
    await _until(tester, () => store.started.isCompleted);
    await _press(tester, '停止后续提交');
    store.finish.complete();
    await _until(tester, () => store.documents.length == 16);
    await localReady(tester);
    await _close(tester, invocation);
    expect(store.calls, 1);
    expect(invocation.result, isFalse);
    expect(store.forAudio(audios.last), isNull);
  });

  testWidgets('metadata preview or unchanged targets alone never report commit',
      (tester) async {
    for (final change in [false, true]) {
      final audio = CategoryTestAudio('preview');
      final batch = BatchAudioMetadata([audio],
          currentAudio: (_) => audio,
          inspect: (_) async => _snapshot(audio),
          apply: (audio, _) async => throw StateError('must not write'));
      await batch
          .preview(BatchMetadataDraft(artist: change ? 'New artist' : null));
      final invocation = await _open(
          tester,
          (context) => showBatchAudioMetadataDialog(context, [audio],
              createBatch: (_) => batch));
      await _close(tester, invocation);
      expect(invocation.result, isFalse);
    }
  });

  testWidgets(
      'metadata commit waits for the writer and allows unchanged neighbours',
      (tester) async {
    final a = CategoryTestAudio('write'), b = CategoryTestAudio('unchanged');
    final finish = Completer<void>();
    var writes = 0;
    final batch = BatchAudioMetadata([a, b],
        currentAudio: (path) => path == a.path ? a : b,
        inspect: (path) async => _snapshot(path == a.path ? a : b),
        apply: (audio, _) async {
          writes++;
          await finish.future;
          return audio;
        });
    await batch
        .preview(BatchMetadataDraft(titles: {a.stableTrackId: 'Written'}));
    final invocation = await _open(
        tester,
        (context) => showBatchAudioMetadataDialog(context, [a, b],
            createBatch: (_) => batch));
    await _press(tester, '应用预览');
    expect(invocation.result, isNull);
    finish.complete();
    await _until(tester, () => !batch.busy);
    expect(writes, 1);
    expect(batch.count(BatchMetadataStatus.success), 1);
    await _close(tester, invocation);
    expect(invocation.result, isTrue);
  });

  testWidgets(
      'metadata blocked neighbour keeps selection after a partial write',
      (tester) async {
    final a = CategoryTestAudio('write'), b = CategoryTestAudio('read-only');
    var writes = 0;
    final batch = BatchAudioMetadata([a, b],
        currentAudio: (path) => path == a.path ? a : b,
        inspect: (path) async =>
            _snapshot(path == a.path ? a : b, readOnly: path == b.path),
        apply: (audio, _) async {
          writes++;
          return audio;
        });
    await batch.preview(BatchMetadataDraft(artist: 'New'));
    final invocation = await _open(
        tester,
        (context) => showBatchAudioMetadataDialog(context, [a, b],
            createBatch: (_) => batch));
    await _press(tester, '应用预览');
    await _until(tester, () => !batch.busy);
    await _close(tester, invocation);
    expect(writes, 1);
    expect(invocation.result, isFalse);
  });

  testWidgets(
      'metadata disk success with pending synchronization returns false',
      (tester) async {
    final audio = CategoryTestAudio('pending-sync');
    final batch = BatchAudioMetadata([audio],
        currentAudio: (_) => audio,
        inspect: (_) async => _snapshot(audio),
        apply: (_, __) async => throw const AudioMetadataEditException(
            'TAG_LIBRARY_SYNC_FAILED', 'controlled sync failure',
            fileWasUpdated: true));
    await batch.preview(BatchMetadataDraft(artist: 'New'));
    final invocation = await _open(
        tester,
        (context) => showBatchAudioMetadataDialog(context, [audio],
            createBatch: (_) => batch));
    await _press(tester, '应用预览');
    await _until(tester, () => !batch.busy);
    expect(batch.count(BatchMetadataStatus.pendingSync), 1);
    await _close(tester, invocation);
    expect(invocation.result, isFalse);
  });

  testWidgets('metadata cancellation never reports a complete partial write',
      (tester) async {
    final a = CategoryTestAudio('a'), b = CategoryTestAudio('b');
    final finish = Completer<void>();
    var writes = 0;
    final batch = BatchAudioMetadata([a, b],
        currentAudio: (path) => path == a.path ? a : b,
        inspect: (path) async => _snapshot(path == a.path ? a : b),
        apply: (audio, _) async {
          writes++;
          await finish.future;
          return audio;
        });
    await batch.preview(BatchMetadataDraft(artist: 'New'));
    final invocation = await _open(
        tester,
        (context) => showBatchAudioMetadataDialog(context, [a, b],
            createBatch: (_) => batch));
    await _press(tester, '应用预览');
    await _until(tester, () => writes == 1);
    await _press(tester, '停止后续处理');
    finish.complete();
    await _until(tester, () => !batch.busy);
    expect(batch.count(BatchMetadataStatus.success), 1);
    expect(batch.count(BatchMetadataStatus.cancelled), 1);
    await _close(tester, invocation);
    expect(writes, 1);
    expect(invocation.result, isFalse);
  });

  testWidgets(
      'metadata failed operation can commit only after the real retry succeeds',
      (tester) async {
    final audio = CategoryTestAudio('retry');
    var attempts = 0;
    final batch = BatchAudioMetadata([audio],
        currentAudio: (_) => audio,
        inspect: (_) async => _snapshot(audio),
        apply: (audio, _) async {
          if (++attempts == 1) throw StateError('first write fails');
          return audio;
        });
    await batch.preview(BatchMetadataDraft(artist: 'New'));
    final invocation = await _open(
        tester,
        (context) => showBatchAudioMetadataDialog(context, [audio],
            createBatch: (_) => batch));
    await _press(tester, '应用预览');
    await _until(tester, () => !batch.busy);
    expect(batch.count(BatchMetadataStatus.failed), 1);
    expect(invocation.result, isNull);
    await _press(tester, '仅重试失败和待同步项');
    await _until(tester, () => !batch.busy);
    await _close(tester, invocation);
    expect(attempts, 2);
    expect(invocation.result, isTrue);
  });

  Future<CategoryCoverStore> coverStore() async {
    final store = CategoryCoverStore(dataDirectory: () async => directory);
    await store.load();
    addTearDown(store.dispose);
    return store;
  }

  testWidgets('cover preview close is false even though the dialog completed',
      (tester) async {
    final store = await tester.runAsync(coverStore) as CategoryCoverStore;
    final audio = CategoryTestAudio('cover');
    var reads = 0;
    final invocation = await _open(
        tester,
        (context) => showCoverRepairDialog(context, [audio],
            covers: store,
            createRepair: (targets) => CoverRepair(targets, repair: (_) async {
                  reads++;
                  return CoverRepairStatus.success;
                })));
    await _close(tester, invocation);
    expect(invocation.result, isFalse);
    expect(reads, 0);
  });

  testWidgets('cover completion waits for every actual reread', (tester) async {
    final store = await tester.runAsync(coverStore) as CategoryCoverStore;
    final finish = Completer<void>();
    late CoverRepair repair;
    var reads = 0;
    final invocation = await _open(
        tester,
        (context) => showCoverRepairDialog(
            context, [CategoryTestAudio('a'), CategoryTestAudio('b')],
            covers: store,
            createRepair: (targets) =>
                repair = CoverRepair(targets, repair: (_) async {
                  reads++;
                  await finish.future;
                  return CoverRepairStatus.success;
                })));
    await _press(tester, '开始读取');
    expect(invocation.result, isNull);
    expect(reads, 1);
    finish.complete();
    await _until(tester, () => !repair.busy);
    await _close(tester, invocation);
    expect(reads, 2);
    expect(invocation.result, isTrue);
  });

  testWidgets('cover missing artwork and failed neighbours return false',
      (tester) async {
    final store = await tester.runAsync(coverStore) as CategoryCoverStore;
    for (final incomplete in [
      CoverRepairStatus.noArtwork,
      CoverRepairStatus.failed
    ]) {
      late CoverRepair repair;
      final invocation = await _open(
          tester,
          (context) => showCoverRepairDialog(
              context, [CategoryTestAudio('a'), CategoryTestAudio('b')],
              covers: store,
              createRepair: (targets) => repair = CoverRepair(targets,
                  repair: (target) async => target.audio!.title == 'a'
                      ? CoverRepairStatus.success
                      : incomplete)));
      await _press(tester, '开始读取');
      await _until(tester, () => !repair.busy);
      expect(repair.count(CoverRepairStatus.success), 1);
      await _close(tester, invocation);
      expect(invocation.result, isFalse);
    }
  });

  testWidgets(
      'cover cancellation preserves completed work without reporting full commit',
      (tester) async {
    final store = await tester.runAsync(coverStore) as CategoryCoverStore;
    final finish = Completer<void>();
    late CoverRepair repair;
    var reads = 0;
    final invocation = await _open(
        tester,
        (context) => showCoverRepairDialog(
            context, [CategoryTestAudio('a'), CategoryTestAudio('b')],
            covers: store,
            createRepair: (targets) =>
                repair = CoverRepair(targets, repair: (_) async {
                  reads++;
                  await finish.future;
                  return CoverRepairStatus.success;
                })));
    await _press(tester, '开始读取');
    await _press(tester, '停止后续处理');
    finish.complete();
    await _until(tester, () => !repair.busy);
    expect(repair.count(CoverRepairStatus.success), 1);
    expect(repair.count(CoverRepairStatus.cancelled), 1);
    await _close(tester, invocation);
    expect(reads, 1);
    expect(invocation.result, isFalse);
  });
}
