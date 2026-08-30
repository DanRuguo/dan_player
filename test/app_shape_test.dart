import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_shell.dart';
import 'package:dan_player/component/frosted_surface.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/page/now_playing_page/component/filled_icon_button_style.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shape tiers are explicit logical pixels', () {
    expect(AppShape.smallRadius, BorderRadius.circular(8));
    expect(AppShape.controlRadius, BorderRadius.circular(12));
    expect(AppShape.surfaceRadius, BorderRadius.circular(16));
    expect(AppShape.control.borderRadius, AppShape.controlRadius);
    expect(AppShape.surface.borderRadius, AppShape.surfaceRadius);
    expect(AppShape.inputBorder.borderRadius, AppShape.controlRadius);
  });

  for (final brightness in Brightness.values) {
    test('$brightness buttons keep the same shape through interaction states',
        () {
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: brightness,
      );
      final theme =
          Entry(welcome: false).fromSchemeAndFontFamily(colorScheme: scheme);
      final styles = [
        theme.iconButtonTheme.style!,
        theme.filledButtonTheme.style!,
        theme.elevatedButtonTheme.style!,
        theme.outlinedButtonTheme.style!,
        theme.textButtonTheme.style!,
        theme.segmentedButtonTheme.style!,
        LargeFilledIconButtonStyle(primary: true, scheme: scheme),
      ];
      for (final style in styles) {
        for (final states in [
          <WidgetState>{},
          {WidgetState.hovered},
          {WidgetState.focused},
          {WidgetState.pressed},
          {WidgetState.disabled},
        ]) {
          expect(style.shape!.resolve(states), AppShape.control);
        }
      }
      expect(theme.menuTheme.style!.shape!.resolve({}), AppShape.control);
      expect(theme.popupMenuTheme.shape, AppShape.control);
      expect(theme.listTileTheme.shape, AppShape.control);
      expect(theme.cardTheme.shape, AppShape.surface);
      expect(theme.dialogTheme.shape, AppShape.surface);
      expect(PlayService.isInitialized, isFalse);
    });

    for (final dpi in [1.0, 1.25, 1.5, 2.0]) {
      testWidgets('$brightness sort/menu and panel radii agree at DPI $dpi',
          (tester) async {
        tester.view.physicalSize = Size(800 * dpi, 600 * dpi);
        tester.view.devicePixelRatio = dpi;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final sort = SortMethodDesc<int>(
          icon: Icons.sort,
          name: '自定义',
          method: (_, __) {},
        );
        final scheme = ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: brightness,
        );
        await tester.pumpWidget(MaterialApp(
          theme: Entry(welcome: false)
              .fromSchemeAndFontFamily(colorScheme: scheme),
          home: Scaffold(
            body: AppContentSurface(
              child: Column(
                children: [
                  Row(children: [
                    SortMethodComboBox<int>(
                      sortMethods: [sort],
                      contentList: const [1],
                      currSortMethod: sort,
                      setSortMethod: (_) {},
                    ),
                    ContentViewSwitch<int>(
                      contentView: ContentView.list,
                      setContentView: (_) {},
                    ),
                  ]),
                  const FrostedSurface(child: SizedBox(width: 200, height: 72)),
                ],
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        final sortRoot = find.byType(SortMethodComboBox<int>);
        final sortMaterial = tester.widget<Material>(find.descendant(
          of: sortRoot,
          matching: find.byType(Material),
        ));
        final sortButton = tester.widget<OutlinedButton>(find.descendant(
          of: sortRoot,
          matching: find.byType(OutlinedButton),
        ));
        expect((sortMaterial.shape! as RoundedRectangleBorder).borderRadius,
            AppShape.controlRadius);
        expect(sortButton.style!.shape!.resolve({}), AppShape.control);
        expect(
            tester
                .widget<FrostedSurface>(find.byType(FrostedSurface))
                .borderRadius,
            AppShape.surfaceRadius);
        final contentClip = tester
            .widgetList<ClipRRect>(find.descendant(
              of: find.byType(AppContentSurface),
              matching: find.byType(ClipRRect),
            ))
            .first;
        expect(contentClip.borderRadius, AppShape.surfaceRadius);
        await tester.tap(find.text('自定义'));
        await tester.pumpAndSettle();
        final menuMaterials = tester.widgetList<Material>(find.ancestor(
          of: find.byKey(const ValueKey('sort-method-0')),
          matching: find.byType(Material),
        ));
        expect(menuMaterials.any((item) => item.shape == AppShape.control),
            isTrue);
        expect(tester.takeException(), isNull);
        expect(PlayService.isInitialized, isFalse);
      });
    }
  }
}
