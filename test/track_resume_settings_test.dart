import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/page/settings_page/track_resume_settings.dart';
import 'package:dan_player/play_service/track_resume_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'narrow English resume controls preserve selection on save failure and clear only automatic memory',
      (tester) async {
    final prefs = ValueNotifier(const TrackResumePreferences());
    addTearDown(prefs.dispose);
    uiLanguage.value = UiLanguage.en;
    addTearDown(() => uiLanguage.value = UiLanguage.zh);
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saves = 0, clears = 0;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.5)),
        child: UiLanguageScope(child: child!),
      ),
      home: Scaffold(
          body: SingleChildScrollView(
              child: TrackResumeSettings(
        preferences: prefs,
        save: () async {
          if (++saves == 1) throw StateError('disk full');
        },
        clear: () async {
          clears++;
        },
      ))),
    ));
    expect(find.text('Remember position per track'), findsOneWidget);
    expect(prefs.value.mode, TrackResumeMode.off);
    final segment = tester.widget<AppSegmentedControl<TrackResumeMode>>(
        find.byKey(const ValueKey('track-resume-mode')));
    segment.onChanged!(TrackResumeMode.longAudio);
    await tester.pumpAndSettle();
    expect(prefs.value.mode, TrackResumeMode.longAudio);
    expect(
        find.text(
            'Resume preferences are applied for this session but were not saved. Try again.'),
        findsOneWidget);
    final dropdown = find.byKey(const ValueKey('track-resume-minimum'));
    expect(
        tester.widget<DropdownButtonFormField<int>>(dropdown).initialValue, 20);
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(saves, 2);
    final clear = find.byKey(const ValueKey('track-resume-clear'));
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(clears, 1);
    expect(
        find.text(
            'Remembered positions cleared. Manual bookmarks are unchanged.'),
        findsOneWidget);
    expect(prefs.value.mode, TrackResumeMode.longAudio);
    expect(tester.takeException(), isNull);
  });
}
