import 'dart:async';

import 'package:dan_player/page/settings_page/lyric_experience_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(ValueNotifier<PlayerExperiencePreferences> preferences,
        Future<void> Function() save,
        {double scale = 1}) =>
    MaterialApp(
      theme: ThemeData(
          platform: TargetPlatform.windows,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      home: Scaffold(
          body: Builder(
              builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: Center(
                        child: SizedBox(
                      width: 320,
                      height: 500,
                      child: SingleChildScrollView(
                          child: LyricExperienceSettings(
                        preferences: preferences,
                        persist: save,
                      )),
                    )),
                  ))),
    );

void main() {
  testWidgets('settings are passive and preserve other experience preferences',
      (tester) async {
    final preferences = ValueNotifier(const PlayerExperiencePreferences(
      playbackRate: 1.75,
      closeToTray: true,
      exclusiveOutput: true,
    ));
    addTearDown(preferences.dispose);
    var saves = 0;
    expect(PlayService.isInitialized, false);
    await tester.pumpWidget(_app(preferences, () async {
      saves++;
    }));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(PlayService.isInitialized, false);
    await tester.tap(find.byKey(const ValueKey('spring-lyrics-switch')));
    await tester.pumpAndSettle();
    expect(preferences.value.springLyrics, false);
    expect(preferences.value.playbackRate, 1.75);
    expect(preferences.value.closeToTray, true);
    expect(preferences.value.exclusiveOutput, true);
    expect(saves, 1);
    expect(PlayService.isInitialized, false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'vertical preference applies without opening desktop or native audio',
      (tester) async {
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    addTearDown(preferences.dispose);
    var saves = 0;
    await tester.pumpWidget(_app(preferences, () async {
      saves++;
    }));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('desktop-lyric-vertical-switch')));
    await tester.pumpAndSettle();
    expect(preferences.value.desktopLyricVertical, true);
    expect(saves, 1);
    expect(PlayService.isInitialized, false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed save keeps live selection and provides a working retry',
      (tester) async {
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    addTearDown(preferences.dispose);
    var attempts = 0;
    await tester.pumpWidget(_app(preferences, () async {
      attempts++;
      if (attempts == 1) throw StateError('fixture write failed');
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('spring-lyrics-switch')));
    await tester.pumpAndSettle();
    expect(preferences.value.springLyrics, false);
    expect(find.textContaining('歌词设置保存失败'), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('lyric-experience-retry')));
    await tester.tap(find.byKey(const ValueKey('lyric-experience-retry')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.textContaining('歌词设置保存失败'), findsNothing);
    expect(preferences.value.springLyrics, false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late earlier failure cannot overwrite a newer successful save',
      (tester) async {
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    addTearDown(preferences.dispose);
    final first = Completer<void>();
    var attempts = 0;
    await tester.pumpWidget(_app(preferences, () async {
      attempts++;
      if (attempts == 1) await first.future;
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('spring-lyrics-switch')));
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('desktop-lyric-vertical-switch')));
    await tester.pump();
    first.completeError(StateError('old failure'));
    await tester.pumpAndSettle();
    expect(preferences.value.springLyrics, false);
    expect(preferences.value.desktopLyricVertical, true);
    expect(find.textContaining('歌词设置保存失败'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      '200% text wraps at 320px and both switch hit regions remain touchable',
      (tester) async {
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    addTearDown(preferences.dispose);
    await tester.pumpWidget(_app(preferences, () async {}, scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final key in [
      'spring-lyrics-switch',
      'desktop-lyric-vertical-switch'
    ]) {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(44));
      final tile = tester.widget<SwitchListTile>(finder);
      expect(tile.visualDensity, VisualDensity.standard);
      expect(tile.onChanged, isNotNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposing while persistence is pending does not update dead UI',
      (tester) async {
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    addTearDown(preferences.dispose);
    final pending = Completer<void>();
    await tester.pumpWidget(_app(preferences, () => pending.future));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('spring-lyrics-switch')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(StateError('late failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
