import 'dart:io';
import 'package:dan_player/component/eq_presets_dialog.dart';
import 'package:dan_player/component/playlist_management_dialog.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/play_service/eq_preset_store.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Playback extends Fake implements PlaybackService {}

class _Presets extends EqPresetStore {
  _Presets(this.count) : super(File('unused-preset-test'));
  final int count;
  @override
  Future<List<Map<String, dynamic>>> list() async => List.generate(
      count,
      (i) => {
            'id': '$i',
            'name': 'Preset $i',
            'gains': List.filled(10, 0.0),
          });
}

void main() {
  testWidgets('preset and recycle dialogs fit contents and cap long lists',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final savedTrash = List<Map<String, dynamic>>.of(playlistTrash);
    addTearDown(() => playlistTrash
      ..clear()
      ..addAll(savedTrash));
    final theme = Entry(welcome: false).fromSchemeAndFontFamily(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal));
    for (final recycle in [false, true]) {
      final heights = <double>[];
      for (final count in [0, 1, 30]) {
        playlistTrash
          ..clear()
          ..addAll(List.generate(
              count,
              (i) => {
                    'id': '$i',
                    'deletedAt': 1788825600000,
                    'playlist': {'name': 'Playlist $i'}
                  }));
        await tester.pumpWidget(MaterialApp(
            theme: theme,
            home: Scaffold(
                body: recycle
                    ? PlaylistTrashDialog(key: ValueKey((recycle, count)))
                    : EqPresetsDialog(
                        key: ValueKey((recycle, count)),
                        service: _Playback(),
                        store: _Presets(count)))));
        await tester.pumpAndSettle();
        final surface = find
            .descendant(
                of: find.byType(AlertDialog), matching: find.byType(Material))
            .first;
        heights.add(tester.getSize(surface).height);
        expect(tester.takeException(), isNull);
      }
      expect(heights[0], lessThan(heights[2]));
      expect(heights[1], lessThan(heights[2]));
      expect(heights[2], lessThan(800));
    }
  });
}
