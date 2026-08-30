import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/component/app_shell.dart';
import 'package:dan_player/component/frosted_surface.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/component/window_chrome_theme.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [900.0, 1280.0]) {
      testWidgets('$brightness $width bottom backdrop has no sidebar seam',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final scheme = ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        );
        final boundaryKey = GlobalKey();
        // A uniform backdrop isolates an unwanted navigation wash from the
        // intentional desktop colour changes and the content panel shadow.
        const backdrop = Color(0xFF47718D);
        final router = GoRouter(
          initialLocation: app_paths.AUDIOS_PAGE,
          routes: [
            GoRoute(
              path: app_paths.AUDIOS_PAGE,
              builder: (_, __) => Scaffold(
                body: RepaintBoundary(
                  key: boundaryKey,
                  child: const ColoredBox(
                    color: backdrop,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SideNav(),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(0, 0, 12, 12),
                            child: AppContentSurface(child: SizedBox.expand()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(
          theme: ThemeData(colorScheme: scheme),
          routerConfig: router,
        ));
        await tester.pumpAndSettle();
        final navEdge = tester.getRect(find.byType(SideNav)).right.round();
        final boundary = boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final pixels = (await tester.runAsync(() async {
          final captured = await boundary.toImage();
          try {
            final data = (await captured.toByteData())!;
            List<int> rgbAt(int x) {
              final offset = ((captured.height - 1) * captured.width + x) * 4;
              return List.generate(
                  3, (channel) => data.getUint8(offset + channel));
            }

            return [rgbAt(navEdge - 32), rgbAt(navEdge + 64)];
          } finally {
            captured.dispose();
          }
        }))!;
        expect(pixels[0], [0x47, 0x71, 0x8D],
            reason: 'Desktop navigation must not add its own bottom mask.');
        for (var channel = 0; channel < 3; channel++) {
          expect((pixels[0][channel] - pixels[1][channel]).abs(),
              lessThanOrEqualTo(2),
              reason: 'Only the subtle content-frame shadow may affect the '
                  'shared bottom backdrop.');
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('$brightness $width navigation has no separate frame or tint',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final scheme = ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        );
        final router = GoRouter(
          initialLocation: app_paths.AUDIOS_PAGE,
          routes: [
            GoRoute(
              path: app_paths.AUDIOS_PAGE,
              builder: (_, __) => const Scaffold(
                body: Row(children: [SideNav(), Expanded(child: SizedBox())]),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(
          theme: ThemeData(colorScheme: scheme),
          routerConfig: router,
        ));
        await tester.pumpAndSettle();
        // The shared AppBackdrop already supplies the frosted background.
        // Persistent navigation must never add a rectangular tint or filter.
        expect(find.byType(FrostedSurface), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);
        if (width >= 1100) {
          final drawer =
              tester.widget<NavigationDrawer>(find.byType(NavigationDrawer));
          expect(drawer.backgroundColor, Colors.transparent);
          expect(drawer.surfaceTintColor, Colors.transparent);
          expect(drawer.shadowColor, Colors.transparent);
          expect(drawer.elevation, 0);
        } else {
          final rail =
              tester.widget<NavigationRail>(find.byType(NavigationRail));
          expect(rail.backgroundColor, Colors.transparent);
          expect(
            NavigationRailTheme.of(tester.element(find.byType(NavigationRail)))
                .elevation,
            0,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$brightness content has one uniform clipped rounded frame',
        (tester) async {
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: brightness,
      );
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: const AppContentSurface(child: SizedBox.expand()),
      ));
      final frame = find.byType(AppContentSurface);
      final clip = tester.widget<ClipRRect>(find.descendant(
        of: frame,
        matching: find.byType(ClipRRect),
      ));
      const radius = BorderRadius.all(Radius.circular(16));
      expect(clip.borderRadius, radius);
      expect(clip.clipBehavior, Clip.antiAlias);
      final decorations = tester.widgetList<DecoratedBox>(find.descendant(
        of: frame,
        matching: find.byType(DecoratedBox),
      ));
      final foreground = decorations.singleWhere(
        (widget) => widget.position == DecorationPosition.foreground,
      );
      final outline = foreground.decoration as BoxDecoration;
      expect(outline.borderRadius, radius);
      expect(outline.border!.isUniform, isTrue);
      expect((outline.border! as Border).top.width, 1);
      final shadow =
          (decorations.first.decoration as BoxDecoration).boxShadow!.single;
      expect(shadow.color.a, lessThanOrEqualTo(0.13));
      expect(shadow.blurRadius, lessThanOrEqualTo(12));
      final fill = tester.widget<ColoredBox>(find.descendant(
        of: frame,
        matching: find.byType(ColoredBox),
      ));
      expect(fill.color, scheme.surface);
      expect(fill.color.a, 1);
    });
  }

  testWidgets('native backdrop remains dynamic under the veil, content opaque',
      (tester) async {
    final boundaryKey = GlobalKey();
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);

    Future<List<Color>> render(Color backdrop) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: RepaintBoundary(
            key: boundaryKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // A simulated compositor colour only tests Flutter alpha;
                // it does not claim to verify native desktop blur itself.
                ColoredBox(color: backdrop),
                const AppBackdrop(
                  status:
                      WindowBackdropStatus(available: true, effect: 'acrylic'),
                ),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 200,
                      child: SizedBox.expand(),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: AppContentSurface(child: SizedBox.expand()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final captured = await boundary.toImage();
        final data = await captured.toByteData();
        Color pixel(int x, int y) {
          final offset = (y * captured.width + x) * 4;
          return Color.fromARGB(
            data!.getUint8(offset + 3),
            data.getUint8(offset),
            data.getUint8(offset + 1),
            data.getUint8(offset + 2),
          );
        }

        final pixels = [pixel(100, 250), pixel(400, 250)];
        captured.dispose();
        return pixels;
      }))!;
    }

    final red = await render(Colors.red);
    final blue = await render(Colors.blue);
    void expectVeiled(Color actual, Color desktop) {
      final expected = Color.alphaBlend(
              const Color(0xFFF3F3F3).withValues(
                  alpha: const BackgroundPreferences().main.opacity),
              desktop)
          .toARGB32();
      for (final shift in [0, 8, 16, 24]) {
        expect((actual.toARGB32() >> shift) & 0xFF,
            closeTo((expected >> shift) & 0xFF, 1));
      }
    }

    expectVeiled(red[0], Colors.red);
    expectVeiled(blue[0], Colors.blue);
    expect(red[0], isNot(blue[0]));
    expect(red[1], scheme.surface);
    expect(blue[1], scheme.surface);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fallback remains opaque and reduced motion has no transition',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: AppBackdrop(),
      ),
    ));
    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(find.byType(Image), findsNothing);
    final background = tester.widget<ColoredBox>(find.descendant(
      of: find.byType(AppBackdrop),
      matching: find.byType(ColoredBox),
    ));
    expect(background.color.a, 1);
    expect(background.color, const Color(0xFFF3F3F3));
  });

  for (final brightness in Brightness.values) {
    testWidgets('$brightness window backdrop is independent of album palette',
        (tester) async {
      Color background() => tester
          .widget<ColoredBox>(find.descendant(
            of: find.byType(AppBackdrop),
            matching: find.byType(ColoredBox),
          ))
          .color;

      for (final seed in [Colors.red, Colors.blue, Colors.green]) {
        for (final available in [false, true]) {
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: seed,
                brightness: brightness,
              ),
            ),
            home: AppBackdrop(
              status: WindowBackdropStatus(
                available: available,
                effect: available ? 'acrylic' : 'solid',
              ),
            ),
          ));
          await tester.pumpAndSettle();
          expect(
            background(),
            (brightness == Brightness.dark
                    ? const Color(0xFF202020)
                    : const Color(0xFFF3F3F3))
                .withValues(
                    alpha: available
                        ? const BackgroundPreferences().main.opacity
                        : 1),
          );
          expect(find.byType(Image), findsNothing);
          expect(find.byType(BackdropFilter), findsNothing);
          expect(find.byType(ImageFiltered), findsNothing);
          if (available) {
            expect(background().a, closeTo(0.70, 0.005));
            final scheme =
                Theme.of(tester.element(find.byType(AppBackdrop))).colorScheme;
            final worstDesktop =
                brightness == Brightness.dark ? Colors.white : Colors.black;
            final chromeLuminance =
                Color.alphaBlend(background(), worstDesktop).computeLuminance();
            final textLuminance = scheme.onSurface.computeLuminance();
            final contrast = textLuminance > chromeLuminance
                ? (textLuminance + 0.05) / (chromeLuminance + 0.05)
                : (chromeLuminance + 0.05) / (textLuminance + 0.05);
            expect(contrast, greaterThanOrEqualTo(4.5),
                reason: 'Neutral title/navigation text should remain legible '
                    'even against the most adverse solid desktop colour.');
          }
        }
      }
    });
  }

  testWidgets('high contrast blocks alpha even before the native event arrives',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(highContrast: true),
        child: AppBackdrop(
          status: WindowBackdropStatus(
            available: true,
            effect: 'acrylic',
            fallbackColor: Colors.black,
          ),
        ),
      ),
    ));
    final background = tester.widget<ColoredBox>(find.descendant(
      of: find.byType(AppBackdrop),
      matching: find.byType(ColoredBox),
    ));
    expect(background.color, Colors.black);
    expect(background.color.a, 1);
  });

  testWidgets('native high contrast blocks the veil before MediaQuery changes',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(highContrast: false),
        child: AppBackdrop(
          status: WindowBackdropStatus(
            available: true,
            effect: 'blur',
            reason: 'high_contrast',
            fallbackColor: Colors.black,
          ),
        ),
      ),
    ));
    final background = tester.widget<ColoredBox>(find.descendant(
      of: find.byType(AppBackdrop),
      matching: find.byType(ColoredBox),
    ));
    expect(background.color, Colors.black);
    expect(background.color.a, 1);
  });

  for (final effect in ['acrylic', 'blur']) {
    testWidgets('$effect veil cannot intercept touch or create another filter',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox.expand(),
            ),
            // Put it above the target deliberately: the background's explicit
            // IgnorePointer must still allow the same touch to pass through.
            AppBackdrop(
              status: WindowBackdropStatus(available: true, effect: effect),
            ),
          ],
        ),
      ));
      await tester.tapAt(const Offset(150, 120));
      await tester.pump();
      expect(taps, 1);
      expect(find.byType(AppBackdrop), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(AnimatedSwitcher), findsNothing);
      final pointer = tester.widget<IgnorePointer>(find.descendant(
        of: find.byType(AppBackdrop),
        matching: find.byType(IgnorePointer),
      ));
      expect(pointer.ignoring, isTrue);
      expect(
          find.descendant(
            of: find.byType(AppBackdrop),
            matching: find.byType(ExcludeSemantics),
          ),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('$brightness native high-contrast event pairs chrome colours',
        (tester) async {
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: brightness,
      );
      final systemBackground =
          brightness == Brightness.light ? Colors.black : Colors.white;
      final foreground =
          brightness == Brightness.light ? Colors.white : Colors.black;
      ColorScheme? chromeScheme;
      ColorScheme? contentScheme;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: AppWindowSurface(
          status: WindowBackdropStatus(
            reason: 'high_contrast',
            fallbackColor: systemBackground,
          ),
          child: Builder(builder: (context) {
            chromeScheme = WindowChromeTheme.colorSchemeOf(context);
            contentScheme = Theme.of(context).colorScheme;
            return const AppContentSurface(child: SizedBox.expand());
          }),
        ),
      ));
      expect(chromeScheme!.onSurface, foreground);
      expect(contentScheme, scheme);
      final backdrop = tester.widget<ColoredBox>(find.descendant(
        of: find.byType(AppBackdrop),
        matching: find.byType(ColoredBox),
      ));
      expect(backdrop.color, systemBackground);
    });
  }
}
