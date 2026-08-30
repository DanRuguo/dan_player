import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/page/settings_page/grouped_settings.dart';
import 'package:dan_player/page/settings_page/interface_settings.dart';
import 'package:dan_player/page/settings_page/page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _selectCategory(WidgetTester tester, String id) async {
  final picker = find.byKey(const ValueKey('settings-category-picker'));
  if (picker.evaluate().isNotEmpty) {
    if (tester.widget<DropdownButton<String>>(picker).value == id) return;
    await tester.tap(picker);
    await tester.pumpAndSettle();
    final menuScroll = find
        .ancestor(
          of: find.byType(DropdownMenuItem<String>).first,
          matching: find.byType(Scrollable),
        )
        .first;
    // Large translated menu items can be outside the lazy viewport entirely.
    // Scroll the actual menu, not the settings page behind its barrier.
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('settings-category-$id')),
      80,
      scrollable: menuScroll,
    );
  }
  final item = find.byKey(ValueKey('settings-category-$id')).last;
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
  if (picker.evaluate().isNotEmpty) {
    expect(tester.widget<DropdownButton<String>>(picker).value, id);
  } else {
    expect(tester.widget<ChoiceChip>(item).selected, isTrue);
  }
}

void main() {
  testWidgets(
      'compact and hidden-rendering switches share label, icon, control and surface metrics',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body:
          SingleChildScrollView(child: InterfaceSettings(persist: () async {})),
    )));
    final compact = find.text('紧凑歌单');
    final rendering = find.text('不可见时暂停视觉更新');
    expect(tester.getTopLeft(compact).dx,
        closeTo(tester.getTopLeft(rendering).dx, .01));
    for (final label in ['界面语言', '音乐列表样式']) {
      expect(tester.getTopLeft(find.text(label)).dx,
          closeTo(tester.getTopLeft(compact).dx, .01),
          reason: 'Group and switch headings use the same leading column');
    }
    final compactRow =
        find.ancestor(of: compact, matching: find.byType(SwitchListTile));
    final renderingRow = find.byKey(const ValueKey('pause-hidden-visuals'));
    final compactSwitch =
        find.descendant(of: compactRow, matching: find.byType(Switch));
    final renderingSwitch =
        find.descendant(of: renderingRow, matching: find.byType(Switch));
    expect(tester.getTopRight(compactSwitch).dx,
        closeTo(tester.getTopRight(renderingSwitch).dx, .01));
    for (final row in [compactRow, renderingRow]) {
      final tile = tester.widget<SwitchListTile>(row);
      expect(tile.secondary, isNotNull);
      expect(tile.contentPadding, SettingsSurface.rowPadding);
      expect(find.ancestor(of: row, matching: find.byType(SettingsSurface)),
          findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final highContrast in [false, true]) {
      testWidgets(
          '$brightness highContrast=$highContrast surface and typography use the current theme',
          (tester) async {
        final scheme = ColorScheme.fromSeed(
            seedColor: Colors.deepOrange,
            brightness: brightness,
            contrastLevel: highContrast ? 1 : 0);
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(colorScheme: scheme, fontFamily: 'FixtureFont'),
          home: MediaQuery(
            data: MediaQueryData(highContrast: highContrast),
            child: Scaffold(
                body: SettingsSwitchTile(
              title: const Text('Theme-bound setting'),
              subtitle: const Text('Theme-bound description'),
              icon: Icons.visibility_off_outlined,
              value: true,
              onChanged: (_) {},
            )),
          ),
        ));
        final surface = find.byType(SettingsSurface);
        final material = tester.widget<Material>(find
            .descendant(of: surface, matching: find.byType(Material))
            .first);
        expect(material.color, scheme.surfaceContainerLow);
        expect(
            (material.shape! as OutlinedBorder).side.color,
            highContrast
                ? scheme.outline
                : scheme.outlineVariant.withValues(alpha: .45));
        final icon =
            tester.widget<Icon>(find.byIcon(Icons.visibility_off_outlined));
        expect(icon.color, scheme.primary);
        final style =
            ListTileTheme.of(tester.element(find.byType(SwitchListTile)));
        expect(style.titleTextStyle?.color, scheme.onSurface);
        expect(style.subtitleTextStyle?.color, scheme.onSurfaceVariant);
        expect(style.titleTextStyle?.fontFamily, 'FixtureFont');
        expect(style.subtitleTextStyle?.fontFamily, 'FixtureFont');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'shared switch retains full-row click, keyboard semantics and disabled state',
      (tester) async {
    var value = false;
    var enabled = true;
    var changes = 0;
    late StateSetter change;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, setState) {
        change = setState;
        return SettingsSwitchTile(
          controlKey: const ValueKey('toggle'),
          icon: Icons.animation,
          title: const Text('Visual preference'),
          value: value,
          onChanged: enabled
              ? (next) => setState(() {
                    value = next;
                    changes++;
                  })
              : null,
        );
      },
    ))));
    final semantics = tester.ensureSemantics();
    await tester.tap(find.text('Visual preference'));
    await tester.pumpAndSettle();
    expect(value, isTrue);
    expect(changes, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(changes, 2);
    expect(value, isFalse);
    change(() => enabled = false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Visual preference'));
    await tester.pumpAndSettle();
    expect(changes, 2);
    expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('toggle')))
            .onChanged,
        isNull);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final width in [320.0, 1000.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            'all five settings groups fit ${language.code} / $width / $scale',
            (tester) async {
          final original = uiLanguage.value;
          uiLanguage.value = language;
          addTearDown(() => uiLanguage.value = original);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 700);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(UiLanguageScope(
              child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true),
              child: child!,
            ),
            home: const SettingsPage(),
          )));
          await tester.pumpAndSettle();
          final groups =
              tester.widget<GroupedSettings>(find.byType(GroupedSettings));
          expect(groups.sections.map((group) => group.id),
              ['library', 'lyrics', 'appearance', 'desktop', 'about']);
          for (final group in groups.sections) {
            await _selectCategory(tester, group.id);
            expect(tester.takeException(), isNull, reason: group.id);
            // Each ordinary setting group has an explicit themed surface;
            // branding signatures and dialog contents are intentionally not cards.
            expect(find.byType(SettingsSurface), findsWidgets);
            for (final control in [
              ...tester.elementList(find.byType(SwitchListTile)),
              ...tester.elementList(find.byType(Slider)),
            ]) {
              expect(
                  find.ancestor(
                      of: find.byElementPredicate(
                          (element) => identical(element, control)),
                      matching: find.byType(SettingsSurface)),
                  findsWidgets,
                  reason:
                      '${group.id} controls must keep their themed surface');
            }
          }
          expect(PlayService.isInitialized, isFalse);
          await tester.pumpWidget(const SizedBox.shrink());
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
