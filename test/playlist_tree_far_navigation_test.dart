import 'package:dan_player/component/playlist_tree_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

Finder _focus(int index) =>
    find.byKey(ValueKey('playlist-tree-focus-folder-$index'));

ScrollController _scroll(WidgetTester tester) => tester
    .widget<ListView>(find.byKey(const PageStorageKey('playlist-tree-scroll')))
    .controller!;

void main() {
  setUpAll(loadPlaylistFeatureFonts);

  Future<void> mount(WidgetTester tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 650);
    await tester.pumpWidget(playlistFeatureHost(PlaylistTreePane<int>(
        nodes: [
          for (var index = 0; index < 1000; index++)
            PlaylistTreeNode(
                id: 'folder-$index',
                parentId: null,
                depth: 0,
                branch: true,
                searchText: 'Folder $index',
                value: index),
        ],
        expanded: const {},
        revealId: () => 'folder-0',
        onExpandedChanged: (_) {},
        itemBuilder: (_, node, __) {
          return SizedBox(
              height: 112, child: Center(child: Text('Folder ${node.value}')));
        })));
    await tester.pumpAndSettle();
    tester.widget<Focus>(_focus(0)).focusNode!.requestFocus();
    await tester.pump();
    expect(tester.widget<Focus>(_focus(0)).focusNode!.hasFocus, isTrue);
  }

  testWidgets('End reaches the last of one thousand virtualized root folders',
      (tester) async {
    await mount(tester);
    expect(_focus(999), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    final scroll = _scroll(tester);
    expect(_focus(999), findsOneWidget,
        reason: 'End stopped at ${scroll.offset} of '
            '${scroll.position.maxScrollExtent} scrollable pixels');
    expect(tester.widget<Focus>(_focus(999)).focusNode!.hasFocus, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('reveal at the start supersedes an unfinished far End navigation',
      (tester) async {
    await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('playlist-tree-reveal')));
    await tester.pumpAndSettle();
    expect(_focus(0), findsOneWidget);
    expect(tester.widget<Focus>(_focus(0)).focusNode!.hasFocus, isTrue);
    expect(_scroll(tester).offset, lessThan(132));
    expect(_focus(999), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
