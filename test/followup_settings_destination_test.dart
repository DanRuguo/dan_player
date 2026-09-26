import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/page/settings_page/animation_settings.dart';
import 'package:dan_player/page/settings_page/grouped_settings.dart';
import 'package:dan_player/page/settings_page/lyric_experience_settings.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in UiLanguage.values) {
    for (final title in ['本地歌词多轨顺序', '歌词页进度条', '波形音柱密度', '滚动边缘拉伸']) {
      testWidgets('${language.name} $title reaches its stable settings group',
          (tester) async {
        final previous = uiLanguage.value;
        uiLanguage.value = language;
        addTearDown(() => uiLanguage.value = previous);
        final destination = searchSettings(translateUi(title, language)).single;
        final route = Uri.parse(destination.location);
        await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MotionPreferencesScope(
                preferences: const MotionPreferences().all(false),
                child: child!),
            home: Scaffold(
                body: GroupedSettings(
                    initialSection: route.queryParameters['section'],
                    initialSetting: route.queryParameters['setting'],
                    sections: [
                  const SettingsSection(
                      id: 'library',
                      title: 'Library',
                      icon: Icons.library_music,
                      children: [Text('Unvisited library')]),
                  SettingsSection(
                      id: 'lyrics',
                      title: 'Lyrics',
                      icon: Icons.lyrics,
                      children: [
                        const SizedBox(height: 1000),
                        LyricExperienceSettings(
                            key: const ValueKey('setting-experience'),
                            persist: () async {}),
                      ]),
                  SettingsSection(
                      id: 'effects',
                      title: 'Effects',
                      icon: Icons.animation,
                      children: [
                        const SizedBox(height: 1000),
                        AnimationSettings(
                            key: const ValueKey('setting-animation'),
                            persist: () async {}),
                      ]),
                ]))));
        await tester.pumpAndSettle();
        final target = find.byKey(ValueKey('setting-${destination.id}'));
        expect(target, findsOneWidget);
        final scroll = tester.widget<SingleChildScrollView>(find
            .byKey(PageStorageKey('settings-scroll-${destination.section}')));
        expect(scroll.controller!.offset, greaterThan(900));
        expect(tester.getTopLeft(target).dy, inInclusiveRange(0, 200));
        expect(find.text('Unvisited library'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
