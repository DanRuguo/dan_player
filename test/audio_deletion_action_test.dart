import 'package:dan_player/component/audio_delete_action.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/library/audio_deletion.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'support/music_category_fixtures.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: Scaffold(body: child),
    );

void main() {
  test('playlist cleanup removes nested references using Windows path identity',
      () {
    final audio =
        CategoryTestAudio('cleanup', path: r'D:\Music\Album\Track.flac');
    final root = Playlist('Root', {});
    final tree = PlaylistTree([root]);
    final child = tree.createPlaylist('Child', parent: root);
    tree.addAudio(root, audio);
    tree.addAudio(child, audio);

    expect(tree.removeAudioReferences(r'd:\music\album\TRACK.flac'), 2);
    expect(root.flattenAudios(), isEmpty);
    expect(root.entries.single.childPlaylist, same(child));
  });

  testWidgets(
      'transient menu closes before confirmation and still deletes exactly once',
      (tester) async {
    final audio = CategoryTestAudio('stable-context');
    var calls = 0;
    late BuildContext stableContext;
    await tester.pumpWidget(_host(Builder(builder: (context) {
      stableContext = context;
      return MenuAnchor(
        menuChildren: [
          DeleteAudioMenuItem(
            audio: audio,
            hostContext: stableContext,
            delete: (_) async {
              calls++;
              return const AudioDeletionOutcome(
                  playlistReferencesRemoved: 0, persistenceWarnings: 0);
            },
          ),
        ],
        builder: (context, controller, _) => FilledButton(
          onPressed: controller.open,
          child: const Text('Open'),
        ),
      );
    })));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final destructive = find.text(ui('删除歌曲…'));
    expect(destructive, findsOneWidget);
    final button = tester.widget<MenuItemButton>(
      find.ancestor(of: destructive, matching: find.byType(MenuItemButton)),
    );
    final error = Theme.of(stableContext).colorScheme.error;
    expect(button.style?.foregroundColor?.resolve({}), error);
    expect(find.byIcon(Symbols.delete_forever), findsOneWidget);

    await tester.tap(destructive);
    await tester.pumpAndSettle();
    expect(find.text(ui('永久删除歌曲？')), findsOneWidget);
    expect(calls, 0);
    await tester.tap(find.byKey(const ValueKey('confirm-delete-audio')));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('AudioTile exposes disk deletion only for local tracks',
      (tester) async {
    final local = CategoryTestAudio('local-menu');
    await tester.pumpWidget(_host(AudioTile(
      audioIndex: 0,
      playlist: [local],
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text(local.displayTitle),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text(ui('删除歌曲…')), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    final online = CategoryTestAudio('online-menu', online: true);
    await tester.pumpWidget(_host(AudioTile(
      audioIndex: 0,
      playlist: [online],
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text(online.displayTitle),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text(ui('删除歌曲…')), findsNothing);
  });
}
