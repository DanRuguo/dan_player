import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/page/settings_page/playback_settings.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

Rect panelRect(WidgetTester tester, Finder item) => tester.getRect(
      find
          .ancestor(
            of: item,
            matching: find.byWidgetPredicate((widget) =>
                widget is Material && widget.type == MaterialType.canvas),
          )
          .first,
    );

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  Future<void> mount(WidgetTester tester, Widget child,
      {double width = 1100,
      double height = 1100,
      double scale = 1,
      bool animate = false,
      TextDirection direction = TextDirection.ltr,
      GlobalKey? boundary}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final host =
        playlistFeatureHost(child, textScale: scale, boundary: boundary)
            as MaterialApp;
    await tester.pumpWidget(UiLanguageScope(
        child: MaterialApp(
      theme: host.theme,
      locale: uiLanguage.value.locale,
      supportedLocales: UiLanguage.values.map((v) => v.locale),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => RepaintBoundary(
        key: boundary,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
              disableAnimations: !animate,
              textScaler: TextScaler.linear(scale)),
          child: Directionality(textDirection: direction, child: child!),
        ),
      ),
      home: Scaffold(
          body: Padding(
              padding: const EdgeInsets.all(24),
              child: Align(alignment: Alignment.bottomLeft, child: child))),
    )));
    await tester.pumpAndSettle();
  }

  for (final language in UiLanguage.values) {
    for (final width in [1100.0, 360.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            'pitch submenu hugs trigger and content ${language.name} $width $scale',
            (tester) async {
          uiLanguage.value = language;
          final boundary = GlobalKey();
          await mount(
              tester,
              PlaybackRateMenu(
                  rate: 1.25, onSelected: (_) {}, onPitchSelected: (_) {}),
              width: width,
              scale: scale,
              boundary: boundary);
          await tester.tap(find.byKey(const ValueKey('playback-rate-menu')));
          await tester.pumpAndSettle();
          final trigger = find.byKey(const ValueKey('playback-pitch-submenu'));
          await tester.ensureVisible(trigger);
          await tester.tap(trigger);
          await tester.pumpAndSettle();
          final item = find.byKey(const ValueKey('playback-pitch-step-down'));
          final panel = panelRect(tester, item);
          final triggerRect = tester.getRect(trigger);
          expect(panel.bottom, closeTo(triggerRect.bottom, .01));
          expect(panel.left, greaterThanOrEqualTo(0));
          expect(panel.right, lessThanOrEqualTo(width));
          if (width == 1100 && scale == 1) {
            expect(panel.width, lessThan(300),
                reason: 'Short pitch labels must not reserve 360 px of text.');
          }
          expect(tester.takeException(), isNull);
          await capturePlaylistFeature(tester, boundary,
              'pitch-submenu-${language.name}-${width.toInt()}-$scale');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          expect(tester.binding.transientCallbackCount, 0);
        });
      }
    }
  }

  for (final direction in TextDirection.values) {
    for (final limited in [false, true]) {
      testWidgets(
          'measured submenu uses actual panel $direction limited=$limited',
          (tester) async {
        final submenu = MenuController();
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var rows = 3;
        late StateSetter update;
        await mount(tester, StatefulBuilder(builder: (context, setState) {
          update = setState;
          return AppMenuAnchor(
              menuChildren: [
                AppSubmenuButton(
                  key: const ValueKey('measured-submenu'),
                  controller: submenu,
                  focusNode: focus,
                  menuStyle: MenuStyle(
                      padding: const WidgetStatePropertyAll(
                          EdgeInsets.fromLTRB(6, 13, 6, 19)),
                      maximumSize: limited
                          ? const WidgetStatePropertyAll(Size(260, 180))
                          : null),
                  menuChildren: [
                    for (var index = 0; index < rows; index++) ...[
                      MenuItemButton(
                          key: ValueKey(('measured-item', index)),
                          onPressed: () {},
                          child: SizedBox(
                              height: 50.0 + index * 11,
                              child: Text('Item $index'))),
                      if (index < rows - 1) const Divider(height: 23),
                    ],
                  ],
                  child: const Text('Submenu'),
                ),
              ],
              builder: (context, controller, _) {
                // The callback below opens the actual application anchor.
                return TextButton(
                    onPressed: controller.open, child: const Text('Open'));
              });
        }), direction: direction);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final trigger = find.byKey(const ValueKey('measured-submenu'));
        await tester.tap(trigger);
        await tester.pump();
        expect(
            panelRect(tester, find.byKey(const ValueKey(('measured-item', 0))))
                .bottom,
            closeTo(tester.getRect(trigger).bottom, .01),
            reason: 'The first laid-out frame must already be attached.');
        await tester.pumpAndSettle();
        Rect rect() =>
            panelRect(tester, find.byKey(const ValueKey(('measured-item', 0))));
        final initial = rect();
        expect(initial.bottom, closeTo(tester.getRect(trigger).bottom, .01));
        if (limited) expect(initial.height, 180);
        update(() => rows = 5);
        await tester.pumpAndSettle();
        final expanded = rect();
        expect(expanded.bottom, closeTo(tester.getRect(trigger).bottom, .01));
        expect(expanded.height,
            limited ? equals(180) : greaterThan(initial.height));
        update(() => rows = 2);
        await tester.pumpAndSettle();
        final contracted = rect();
        expect(contracted.bottom, closeTo(tester.getRect(trigger).bottom, .01));
        expect(contracted.height, lessThanOrEqualTo(expanded.height));
        submenu.close();
        await tester.pumpAndSettle();
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        expect(rect().bottom, closeTo(tester.getRect(trigger).bottom, .01));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }

  testWidgets('submenu follows a local overlay and nullable themed padding',
      (tester) async {
    final boundary = GlobalKey();
    final entry = OverlayEntry(
        builder: (context) => Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: AppMenuAnchor(
                    menuChildren: [
                      AppSubmenuButton(
                        key: const ValueKey('local-submenu'),
                        menuStyle: MenuStyle(
                            padding:
                                WidgetStateProperty.resolveWith((_) => null)),
                        menuChildren: [
                          for (var index = 0; index < 3; index++)
                            MenuItemButton(
                                key: ValueKey(('local-item', index)),
                                onPressed: () {},
                                child: Text('Local item $index')),
                        ],
                        child: const Text('Local submenu'),
                      ),
                    ],
                    builder: (_, controller, __) => TextButton(
                        onPressed: controller.open,
                        child: const Text('Open local'))))));
    await mount(
        tester,
        MenuTheme(
            data: const MenuThemeData(
                style: MenuStyle(
                    padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(vertical: 15)))),
            child: SizedBox(
                width: 400,
                height: 300,
                child: RepaintBoundary(
                    key: boundary, child: Overlay(initialEntries: [entry])))));
    final localRect = tester.getRect(find.byKey(boundary));
    await tester.tap(find.text('Open local'));
    await tester.pumpAndSettle();
    final trigger = find.byKey(const ValueKey('local-submenu'));
    await tester.tap(trigger);
    await tester.pump();
    final panel =
        panelRect(tester, find.byKey(const ValueKey(('local-item', 0))));
    expect(panel.bottom, closeTo(tester.getRect(trigger).bottom, .01));
    expect(panel.left, greaterThanOrEqualTo(localRect.left));
    expect(panel.right, lessThanOrEqualTo(localRect.right));
    expect(panel.top, greaterThanOrEqualTo(localRect.top));
    expect(tester.takeException(), isNull);
    entry.remove();
    await tester.pumpAndSettle();
    entry.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });
}
