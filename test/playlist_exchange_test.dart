import 'dart:io';

import 'package:dan_player/component/playlist_exchange_dialog.dart';
import 'package:dan_player/component/playlist_toolbar.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist_exchange.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('M3U8 preserves BOM, relative/file URI paths, metadata and duplicates',
      () async {
    final parsed = parseM3u(
        '\uFEFF#EXTM3U\n#EXTINF:223,周杰伦 - 稻香\n../Music/稻香.flac\n'
        'file:///C:/Music/Good%20Time.mp3\n../Music/稻香.flac\n'
        'https://example.invalid/stream.mp3\nonline://qq/1\nnotes.txt\n',
        playlistPath: r'C:\Lists\mix.m3u8');
    expect(parsed.entries.map((entry) => entry.path),
        [r'C:\Music\稻香.flac', r'C:\Music\Good Time.mp3', r'C:\Music\稻香.flac']);
    expect(parsed.entries.first.duration, 223);
    expect(parsed.skipped, 3);
    final known =
        Audio.fromMap({'path': r'c:\music\稻香.flac', 'title': 'Original title'});
    final audios = await resolveM3uEntries(parsed, [known]);
    expect(identical(audios.first, known), isTrue);
    expect(identical(audios.last, known), isTrue);
    expect(audios[1].title, 'Good Time');
    expect(audios[1].isLocal, isTrue);
  });

  test('round trip supports cross-drive, hash names and rejects network URLs',
      () {
    const entries = [
      M3uEntry(r'C:\Music\#Canon.flac', title: 'Title\r\n#bad', duration: 60),
      M3uEntry(r'D:\Good Time.mp3'),
      M3uEntry(r'C:\Music\#Canon.flac')
    ];
    final text = encodeM3u(entries, playlistPath: r'C:\Music\list.m3u8');
    expect(text, contains('./#Canon.flac'));
    expect(text, contains('D:/Good Time.mp3'));
    expect(text, isNot(contains('\n#bad')));
    final read = parseM3u(text, playlistPath: r'C:\Music\list.m3u8');
    expect(read.entries.map((entry) => entry.path),
        entries.map((entry) => entry.path));
    expect(
        parseM3u(r'\\.\pipe\example.mp3', playlistPath: r'C:\list.m3u8')
            .entries,
        isEmpty);
  });

  test('bounded input and atomic export protect an existing playlist',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('dan-player-m3u-test-');
    addTearDown(() => directory.delete(recursive: true));
    final target = File('${directory.path}/playlist.m3u8');
    await target.writeAsString('old playlist');
    await writeM3uFile(
        target, [M3uEntry('${directory.path}/Canon.flac', title: '卡农')]);
    expect((await readM3uFile(target)).entries.single.title, '卡农');
    final valid = await target.readAsString();
    final oversized = List.filled(
        m3uMaxEntries + 1, M3uEntry('${directory.path}/Canon.flac'));
    await expectLater(writeM3uFile(target, oversized), throwsFormatException);
    expect(await target.readAsString(), valid);
    expect(
        await directory
            .list()
            .where((file) => file.path.endsWith('.tmp'))
            .isEmpty,
        isTrue);
    expect(() => parseM3u('x' * (m3uMaxBytes + 1), playlistPath: target.path),
        throwsFormatException);
  });

  testWidgets('import preview does not create a playlist before confirmation',
      (tester) async {
    const location = r'C:\Lists\Imported.m3u8';
    final document = parseM3u(
        '#EXTM3U\nCanon.flac\nCanon.flac\nhttps://example.invalid/a.mp3\n',
        playlistPath: location);
    PlaylistImportDetails? selected;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      selected = await importM3uPlaylist(context,
                          library: [],
                          pickFile: () => location,
                          readFile: (_) async => document);
                    },
                    child: const Text('Import'))))));
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.textContaining('2 个本地歌曲引用'), findsOneWidget);
    expect(find.textContaining('跳过 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('m3u-import-confirm')));
    await tester.pumpAndSettle();
    expect(selected!.name, 'Imported');
    expect(selected!.audios.length, 2);
    expect(selected!.audios.first.path, selected!.audios.last.path);
  });

  testWidgets(
      'export cancel does not open a save picker; dialog fits large text',
      (tester) async {
    var picked = false;
    tester.view.physicalSize = const Size(360, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => exportM3uPlaylist(context, [
                          Audio.fromMap({'path': r'C:\Music\Canon.flac'})
                        ], pickFile: (_) {
                          picked = true;
                          return null;
                        }),
                    child: const Text('Export'))))));
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('取消'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(picked, isFalse);
  });

  testWidgets('playlist menu exposes import and export with supplied callbacks',
      (tester) async {
    var imported = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PlaylistToolbar(
      isRoot: true,
      hasItems: false,
      canPlay: false,
      onCreate: () {},
      onPlayAll: () {},
      onStartSelection: () {},
      onEndSelection: () {},
      onSelectAll: () {},
      onRemoveSelected: () {},
      onSortChanged: (_) {},
      onImportM3u: () => imported++,
    ))));
    await tester.tap(find.byKey(const ValueKey('playlist-current-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playlist-import-m3u')));
    await tester.pumpAndSettle();
    expect(imported, 1);
  });

  testWidgets('import picker errors produce a notice without starting a read',
      (tester) async {
    var finished = false;
    var read = false;
    PlaylistImportDetails? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await importM3uPlaylist(context,
                          library: [],
                          pickFile: () =>
                              throw StateError('picker unavailable'),
                          readFile: (_) async {
                            read = true;
                            return const M3uDocument([]);
                          });
                      finished = true;
                    },
                    child: const Text('Import'))))));
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(result, isNull);
    expect(read, isFalse);
    expect(find.text('无法打开文件选择器，请稍后重试。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('export counts supported files and never changes a chosen suffix',
      (tester) async {
    final directory =
        Directory.systemTemp.createTempSync('dan-player-m3u-suffix-test-');
    addTearDown(() => directory.delete(recursive: true));
    final chosen = File('${directory.path}/keep.txt')
      ..writeAsStringSync('original chosen file');
    final appended = File('${chosen.path}.m3u8')
      ..writeAsStringSync('original unconfirmed file');
    var picked = false;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => exportM3uPlaylist(context, [
                          Audio.fromMap({'path': r'C:\Music\Canon.flac'}),
                          Audio.fromMap({'path': r'C:\Music\notes.txt'}),
                        ], pickFile: (_) {
                          picked = true;
                          return chosen.path;
                        }),
                    child: const Text('Export'))))));
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.text('导出 1 个本地歌曲引用，保留顺序与重复项。'), findsOneWidget);
    expect(find.text('跳过 1 项联网歌曲或不支持的文件引用。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('m3u-export-confirm')));
    await tester.pumpAndSettle();
    expect(picked, isTrue);
    expect(find.text('导出文件名请使用 .m3u8 后缀。'), findsOneWidget);
    expect(chosen.readAsStringSync(), 'original chosen file');
    expect(appended.readAsStringSync(), 'original unconfirmed file');
    expect(directory.listSync().length, 2);
    expect(tester.takeException(), isNull);
  });
}
