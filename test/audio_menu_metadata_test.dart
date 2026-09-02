import 'package:dan_player/component/audio_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'support/music_category_fixtures.dart';

void main() {
  testWidgets('artist and album are direct, distinctly iconed song menu items',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    final audio = CategoryTestAudio(
      'menu metadata',
      artist: 'Artist A / Artist B',
      album: 'Album C',
    )..splitedArtists = ['Artist A', 'Artist B'];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: AudioTile(audioIndex: 0, playlist: [audio]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(AudioTile));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SubmenuButton, '艺术家'), findsNothing);
    for (final artistName in audio.splitedArtists) {
      final item = tester.widget<MenuItemButton>(
        find.widgetWithText(MenuItemButton, artistName),
      );
      expect((item.leadingIcon! as Icon).icon, Symbols.artist);
    }
    final albumItem = tester.widget<MenuItemButton>(
      find.widgetWithText(MenuItemButton, audio.album),
    );
    expect((albumItem.leadingIcon! as Icon).icon, Symbols.album);
    expect(tester.takeException(), isNull);
  });
}
