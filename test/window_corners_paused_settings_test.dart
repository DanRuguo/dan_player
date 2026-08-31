import 'package:dan_player/page/settings_page/sidebar_layout_settings.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final storedRequest in [false, true]) {
    testWidgets(
        'paused outer corners hide setting without changing saved $storedRequest',
        (tester) async {
      final original = PlayerExperiencePreferences.fromMap({
        'roundedWindowCorners': storedRequest,
      });
      final preferences = ValueNotifier(original);
      addTearDown(preferences.dispose);
      var saves = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SidebarLayoutSettings(
              preferences: preferences,
              persist: () async {
                saves++;
              },
            ),
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('rounded-window-corners-setting')),
          findsNothing);
      expect(find.text('窗口圆角'), findsNothing);
      expect(
          find.byKey(const ValueKey('sidebar-width-setting')), findsOneWidget);
      expect(preferences.value, same(original));
      expect(preferences.value.toMap()['roundedWindowCorners'], storedRequest);
      expect(saves, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
