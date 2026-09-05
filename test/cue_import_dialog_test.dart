import 'package:dan_player/component/cue_import_dialog.dart';
import 'package:dan_player/component/playlist_exchange_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_sheet.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CueAudio extends Audio {
  _CueAudio(CueTrackReference cue)
      : super('卡农', 'Artist', 'Album', 1, 200, null, null, cue.identity, 0, 0,
            'CUE',
            cueTrack: cue);
  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) =>
      SynchronousFuture(null);
}

void main() {
  testWidgets(
      'CUE track menus expose playlist actions but no whole-file editors or deletion',
      (tester) async {
    final cue = _CueAudio(const CueTrackReference(
        cuePath: r'C:\Music\Album.cue',
        sourcePath: r'C:\Music\Album.flac',
        number: 1,
        startFrame: 0,
        endFrame: 15000));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AudioTile(audioIndex: 0, playlist: [cue]))));
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(AudioTile));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, '编辑歌曲信息'), findsNothing);
    expect(find.widgetWithText(MenuItemButton, '编辑歌词'), findsNothing);
    expect(find.widgetWithText(MenuItemButton, '删除歌曲…'), findsNothing);
    expect(find.widgetWithText(MenuItemButton, '详细信息'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'preview confirms independent tracks and remains usable at narrow large text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const location = r'C:\Music\Album.cue';
    final document = parseCue(
        'FILE "album.flac" WAVE\nTRACK 01 AUDIO\nTITLE "卡农"\nINDEX 01 00:00:00\nTRACK 02 AUDIO\nTITLE "Good Time"\nINDEX 01 03:20:00',
        cuePath: location);
    PlaylistImportDetails? selected;
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!),
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        selected = await importCuePlaylist(context,
                            library: [],
                            pickFile: () => location,
                            readFile: (_) async => document,
                            resolveEntries: (doc, _) async => [
                                  for (final e in doc.entries)
                                    Audio(
                                        e.title,
                                        'Artist',
                                        'Album',
                                        e.reference.number,
                                        200,
                                        null,
                                        null,
                                        e.reference.identity,
                                        0,
                                        0,
                                        'CUE',
                                        cueTrack: e.reference)
                                ]);
                      },
                      child: const Text('Import'))))));
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(find.textContaining('2 首 CUE 分轨'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('新建歌单'));
      await tester.pumpAndSettle();
      expect(selected!.name, 'Album');
      expect(selected!.audios.map((a) => a.displayTitle), ['卡农', 'Good Time']);
      expect(selected!.audios[0].path, isNot(selected!.audios[1].path));
      expect(tester.takeException(), isNull);
      selected = null;
    }
  });
  testWidgets('bad file shows useful error and cannot confirm', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => importCuePlaylist(context,
                        library: [],
                        pickFile: () => r'C:\bad.cue',
                        readFile: (_) async =>
                            throw const FormatException('CUE INDEX 时间格式无效。')),
                    child: const Text('Import'))))));
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(find.text('CUE INDEX 时间格式无效。'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '新建歌单'))
            .onPressed,
        isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(CueImportDialog), findsNothing);
  });
}
