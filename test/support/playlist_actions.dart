import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercise the explicit batch-play flow without using the mode-only header.
Future<void> playVisiblePlaylistSelection(WidgetTester tester) async {
  await tapPlaylistAction(tester, 'playlist-start-selection');
  await tapPlaylistAction(tester, 'playlist-select-all');
  await tapPlaylistAction(tester, 'playlist-play-selected');
  await tapPlaylistAction(tester, 'playlist-end-selection');
}

/// The same three options are inline on wide hosts and in the selector's menu
/// on narrow hosts. Tests activate the real control in either presentation.
Future<void> selectPlaylistView(WidgetTester tester, String view) async {
  final option = find.byKey(ValueKey('playlist-view-$view'));
  if (option.hitTestable().evaluate().isEmpty) {
    final selector = find.byKey(const ValueKey('playlist-view-selector'));
    final button = find.descendant(
        of: selector,
        matching: find.byWidgetPredicate(
            (widget) => widget is OutlinedButton || widget is IconButton));
    await tester.ensureVisible(button.first);
    await tester.tap(button.first);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(option.hitTestable().last);
  await tester.tap(option.hitTestable().last);
  await tester.pumpAndSettle();
}

/// Actions intentionally moved out of the persistent toolbar remain reachable
/// via the actual menus, rather than invoking their callbacks directly.
Future<void> tapPlaylistAction(WidgetTester tester, String key) async {
  final action = find.byKey(ValueKey(key));
  if (action.hitTestable().evaluate().isEmpty) {
    final addMenu = find.byKey(const ValueKey('playlist-add-menu'));
    final useAddMenu =
        (key == 'playlist-create' || key == 'playlist-add-songs') &&
            addMenu.hitTestable().evaluate().isNotEmpty;
    await tester.tap(useAddMenu
        ? addMenu
        : find.byKey(const ValueKey('playlist-current-settings')));
    await tester.pumpAndSettle();
  }
  await tester.tap(action.hitTestable().last);
  await tester.pumpAndSettle();
}
