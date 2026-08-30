import 'package:dan_player/page/settings_page/desktop_lyric_settings.dart';
import 'package:desktop_lyric/component/desktop_lyric_taskbar_options.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'settings share helper model, remain passive and debounce slider saves',
      (tester) async {
    final prefs = ValueNotifier(DesktopLyricAppearance.defaults);
    addTearDown(prefs.dispose);
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: DesktopLyricSettings(
                    preferences: prefs,
                    persist: () async {
                      saves++;
                    })))));
    expect(saves, 0);
    await tester
        .ensureVisible(find.byKey(const ValueKey('desktop-taskbar-mode')));
    await tester.tap(find.byKey(const ValueKey('desktop-taskbar-mode')));
    await tester.pump();
    expect(prefs.value.taskbarMode, true);
    expect(find.byType(DesktopLyricTaskbarOptions), findsOneWidget);
    final slider = tester
        .widget<Slider>(find.byKey(const ValueKey('desktop-taskbar-gap')));
    slider.onChanged!(10);
    slider.onChanged!(12);
    slider.onChanged!(16);
    await tester.pump(const Duration(milliseconds: 299));
    expect(saves, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(saves, 1);
    expect(prefs.value.taskbarGap, 16);
  });

  testWidgets('pending change is saved on disposal, failure can be retried',
      (tester) async {
    final prefs = ValueNotifier(DesktopLyricAppearance.defaults);
    addTearDown(prefs.dispose);
    var fail = true;
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: DesktopLyricSettings(
                    preferences: prefs,
                    persist: () async {
                      saves++;
                      if (fail) throw StateError('fixture write failure');
                    })))));
    await tester
        .ensureVisible(find.byKey(const ValueKey('desktop-taskbar-mode')));
    await tester.tap(find.byKey(const ValueKey('desktop-taskbar-mode')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('重试保存'), findsOneWidget);
    fail = false;
    await tester.ensureVisible(find.text('重试保存'));
    await tester.tap(find.text('重试保存'));
    await tester.pump();
    expect(find.text('重试保存'), findsNothing);
    final slider = tester
        .widget<Slider>(find.byKey(const ValueKey('desktop-taskbar-height')));
    slider.onChanged!(72);
    await tester.pumpWidget(const SizedBox());
    expect(saves, 3);
    expect(prefs.value.taskbarHeight, 72);
  });
}
