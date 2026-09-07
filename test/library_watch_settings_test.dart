import 'package:dan_player/page/settings_page/library_watch_settings.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'library watching opt-in persists; failures are visible in narrow English layout',
      (tester) async {
    final value = ValueNotifier(false);
    addTearDown(value.dispose);
    uiLanguage.value = UiLanguage.en;
    addTearDown(() => uiLanguage.value = UiLanguage.zh);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: UiLanguageScope(child: AppPresentationHost(child: child!))),
      home: Scaffold(
          body: SingleChildScrollView(
              child: LibraryWatchSettings(
                  enabled: value,
                  save: () async {
                    saves++;
                    if (saves == 2) throw StateError('disk unavailable');
                  }))),
    ));
    expect(find.text('Automatically update library'), findsOneWidget);
    final control = find.byKey(const ValueKey('library-auto-refresh'));
    expect(tester.widget<SwitchListTile>(control).value, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(value.value, isTrue);
    expect(saves, 1);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Automatic update preferences were not saved. Try again.'),
        findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const ValueKey('app-notice-bubble')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-notice-close')), findsOneWidget);
    expect(value.value, isFalse);
    expect(tester.takeException(), isNull);
  });
}
