import 'package:dan_player/theme_mode_preference.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('explicit mode survives serialization without a second startup switch',
      () {
    for (final mode in ThemeMode.values) {
      final saved = ThemeModePreference.encode(mode);
      expect(ThemeModePreference.decode(saved), mode);
      expect(saved['UseSystemThemeMode'], mode == ThemeMode.system);
      expect(
          ThemeModePreference.decode(
              {...saved, 'UseSystemThemeMode': mode != ThemeMode.system}),
          mode,
          reason: 'The explicit new preference is authoritative.');
    }
  });

  test('old bool/int startup settings migrate and missing values follow OS',
      () {
    expect(ThemeModePreference.decode({}), ThemeMode.system);
    for (final follow in [true, 1]) {
      expect(
          ThemeModePreference.decode(
              {'UseSystemThemeMode': follow, 'ThemeMode': true}),
          ThemeMode.system);
    }
    for (final follow in [false, 0]) {
      for (final dark in [true, 1]) {
        expect(
            ThemeModePreference.decode(
                {'UseSystemThemeMode': follow, 'ThemeMode': dark}),
            ThemeMode.dark);
      }
      expect(
          ThemeModePreference.decode(
              {'UseSystemThemeMode': follow, 'ThemeMode': false}),
          ThemeMode.light);
    }
    expect(ThemeModePreference.decode({'AppearanceThemeMode': 'invalid'}),
        ThemeMode.system);
  });

  testWidgets(
      'system changes publish immediately without overriding manual mode',
      (tester) async {
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(binding.platformDispatcher.clearPlatformBrightnessTestValue);
    final theme = ThemeProvider.forTesting(
        seedColor: Colors.teal,
        themeMode: ThemeMode.system,
        dynamicThemeEnabled: () => false,
        loadArtwork: (_) async => null,
        extractScheme: (_, brightness) async => ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: brightness));
    var notifications = 0;
    theme.addListener(() => notifications++);
    await tester.pumpWidget(ListenableBuilder(
        listenable: theme,
        builder: (context, _) => MaterialApp(
            themeMode: theme.themeMode,
            theme: ThemeData(colorScheme: theme.lightScheme),
            darkTheme: ThemeData(colorScheme: theme.darkScheme),
            home: Builder(
                builder: (context) =>
                    Text(Theme.of(context).brightness.name)))));
    expect(theme.currScheme.brightness, Brightness.light);
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(theme.themeMode, ThemeMode.system);
    expect(theme.currScheme.brightness, Brightness.dark);
    expect(find.text('dark'), findsOneWidget);
    expect(notifications, 1);
    theme.applyThemeMode(ThemeMode.dark);
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(theme.currScheme.brightness, Brightness.dark);
    expect(find.text('dark'), findsOneWidget);
    expect(notifications, 2,
        reason: 'OS changes do not alter explicit dark mode.');
    theme.applyThemeMode(ThemeMode.system);
    await tester.pumpAndSettle();
    expect(theme.currScheme.brightness, Brightness.light);
    expect(find.text('light'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    theme.dispose();
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    expect(notifications, 3,
        reason: 'Disposed observers must not receive OS events.');
  });
}
