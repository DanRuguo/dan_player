import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/component/frosted_surface.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/component/title_bar.dart';
import 'package:dan_player/component/window_chrome_theme.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

int? _argb(Color? color) => color?.toARGB32();

void main() {
  for (final foreground in [null, Colors.black, Colors.white]) {
    testWidgets('chrome foreground ${_argb(foreground)} leaves Theme untouched',
        (tester) async {
      final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF326991));
      ColorScheme? chrome;
      ColorScheme? original;
      Color? chromeForeground;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: WindowChromeTheme(
          foreground: foreground,
          child: Builder(builder: (context) {
            original = Theme.of(context).colorScheme;
            chrome = WindowChromeTheme.colorSchemeOf(context);
            chromeForeground = WindowChromeTheme.foregroundOf(context);
            return const SizedBox.shrink();
          }),
        ),
      ));
      expect(original, scheme);
      expect(chrome,
          foreground == null ? scheme : scheme.copyWith(onSurface: foreground));
      expect(_argb(chrome!.surface), _argb(scheme.surface));
      expect(_argb(chrome!.primaryContainer), _argb(scheme.primaryContainer));
      expect(
          _argb(chrome!.onPrimaryContainer), _argb(scheme.onPrimaryContainer));
      expect(
          _argb(chrome!.secondaryContainer), _argb(scheme.secondaryContainer));
      expect(_argb(chrome!.onSecondaryContainer),
          _argb(scheme.onSecondaryContainer));
      expect(_argb(chromeForeground), _argb(foreground ?? scheme.primary));
    });
  }

  for (final width in [900.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          '$width $brightness chrome uses contrasting system foreground',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const channel = MethodChannel('window_manager');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final calls = <String>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'isFullScreen' || call.method == 'isMaximized') {
            return false;
          }
          throw StateError('Unexpected native operation: ${call.method}');
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

        final scheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF326991),
          brightness: brightness,
        );
        // Deliberately oppose the app theme: a light app on a black HC desktop
        // needs white chrome, while a dark app on white needs black chrome.
        final systemForeground =
            brightness == Brightness.light ? Colors.white : Colors.black;
        final systemBackground =
            brightness == Brightness.light ? Colors.black : Colors.white;
        final foreground = ValueNotifier<Color?>(systemForeground);
        addTearDown(foreground.dispose);
        ColorScheme? contentScheme;
        ColorScheme? songScheme;
        final router = GoRouter(
          initialLocation: app_paths.AUDIOS_PAGE,
          routes: [
            GoRoute(
              path: app_paths.AUDIOS_PAGE,
              builder: (_, __) => ValueListenableBuilder<Color?>(
                valueListenable: foreground,
                builder: (_, color, child) => WindowChromeTheme(
                  foreground: color,
                  child: child!,
                ),
                child: Scaffold(
                  backgroundColor: systemBackground,
                  appBar: PreferredSize(
                    preferredSize: const Size.fromHeight(48),
                    child: TitleBar(
                      songContent: Builder(builder: (context) {
                        songScheme = Theme.of(context).colorScheme;
                        return const SizedBox.expand();
                      }),
                    ),
                  ),
                  body: Row(
                    children: [
                      const SideNav(),
                      Expanded(
                        child: Builder(builder: (context) {
                          contentScheme = Theme.of(context).colorScheme;
                          return const SizedBox.expand();
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(
          theme:
              ThemeData(colorScheme: scheme, platform: TargetPlatform.windows),
          routerConfig: router,
        ));
        await tester.pumpAndSettle();

        void expectChrome(Color color) {
          final title = tester.widget<Text>(find.text('Dan Player'));
          expect(_argb(title.style!.color), _argb(color));
          final unselectedLabel = DefaultTextStyle.of(
            tester.element(find.text('分类')),
          ).style.color;
          expect(_argb(unselectedLabel), _argb(color));
          final selectedLabel = DefaultTextStyle.of(
            tester.element(find.text('音乐')),
          ).style.color;
          expect(_argb(selectedLabel), _argb(scheme.onPrimaryContainer));
          final minimize = find.descendant(
            of: find.byType(WindowControlls),
            matching: find.byIcon(Symbols.remove),
          );
          expect(
            _argb(IconTheme.of(tester.element(minimize)).color),
            _argb(color),
          );
          expect(contentScheme, scheme);
          expect(songScheme, scheme);
          expect(PlayService.isInitialized, isFalse);
          expect(tester.takeException(), isNull);
        }

        expectChrome(systemForeground);
        foreground.value = null;
        await tester.pumpAndSettle();
        expectChrome(scheme.primary);
        foreground.value = systemForeground;
        await tester.pumpAndSettle();
        expectChrome(systemForeground);
        expect(calls, ['isFullScreen', 'isMaximized']);
      });
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('$brightness narrow HC drawer keeps its own paired colours',
        (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF326991),
        brightness: brightness,
      );
      final state = ValueNotifier<(Color?, bool)>((null, false));
      addTearDown(state.dispose);
      final scaffoldKey = GlobalKey<ScaffoldState>();
      final router = GoRouter(
        initialLocation: app_paths.AUDIOS_PAGE,
        routes: [
          GoRoute(
            path: app_paths.AUDIOS_PAGE,
            builder: (_, __) => ValueListenableBuilder<(Color?, bool)>(
              valueListenable: state,
              builder: (context, value, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(highContrast: value.$2),
                child: WindowChromeTheme(
                  foreground: value.$1,
                  child: child!,
                ),
              ),
              child: Scaffold(
                key: scaffoldKey,
                drawer: const SideNav(),
                body: const SizedBox.expand(),
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
      scaffoldKey.currentState!.openDrawer();
      await tester.pumpAndSettle();
      expect(find.byType(FrostedSurface), findsOneWidget);

      void expectOpaquePairedDrawer() {
        expect(find.byType(FrostedSurface), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);
        final surfaces = tester.widgetList<ColoredBox>(find.descendant(
          of: find.byType(SideNav),
          matching: find.byType(ColoredBox),
        ));
        expect(surfaces.any((box) => _argb(box.color) == _argb(scheme.surface)),
            isTrue);
        expect(
          _argb(
              DefaultTextStyle.of(tester.element(find.text('分类'))).style.color),
          _argb(scheme.onSurface),
        );
        expect(
          _argb(
              DefaultTextStyle.of(tester.element(find.text('音乐'))).style.color),
          _argb(scheme.onPrimaryContainer),
        );
        expect(scaffoldKey.currentState!.isDrawerOpen, isTrue);
        expect(PlayService.isInitialized, isFalse);
        expect(tester.takeException(), isNull);
      }

      // The native event may arrive first, while MediaQuery still reports false.
      state.value = (
        brightness == Brightness.light ? Colors.white : Colors.black,
        false,
      );
      await tester.pumpAndSettle();
      expectOpaquePairedDrawer();

      // MediaQuery alone must also be sufficient to turn off the glass.
      state.value = (null, true);
      await tester.pumpAndSettle();
      expectOpaquePairedDrawer();

      state.value = (null, false);
      await tester.pumpAndSettle();
      expect(find.byType(FrostedSurface), findsOneWidget);
      expect(scaffoldKey.currentState!.isDrawerOpen, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
