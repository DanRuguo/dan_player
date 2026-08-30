import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/component/app_shell.dart';
import 'package:dan_player/component/app_window_mode_host.dart';
import 'package:dan_player/component/compact_player.dart';
import 'package:dan_player/component/frosted_surface.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/component/title_bar.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:dan_player/window_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fake_window_mode_adapter.dart';

Future<List<Color>> _sample(
  WidgetTester tester,
  GlobalKey key,
  List<Offset> points,
) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData())!;
      return points.map((point) {
        final offset = (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
        return Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
      }).toList();
    } finally {
      image.dispose();
    }
  }))!;
}

void _expectNear(Color first, Color second, int tolerance) {
  final a = first.toARGB32();
  final b = second.toARGB32();
  for (final shift in [0, 8, 16, 24]) {
    expect((((a >> shift) & 0xFF) - ((b >> shift) & 0xFF)).abs(),
        lessThanOrEqualTo(tolerance));
  }
}

void main() {
  for (final brightness in Brightness.values) {
    for (final effect in ['acrylic', 'blur']) {
      testWidgets(
          '$brightness $effect chrome shares one stronger live-desktop veil',
          (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final scheme = ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        );
        final available = WindowBackdropStatus(available: true, effect: effect);
        const channel = MethodChannel('dan_player/window_backdrop');
        final nativeCalls = <String>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call.method);
          throw StateError('Painting the veil must not reconfigure Windows');
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final compositor = ValueNotifier<(Color, WindowBackdropStatus)>(
            (Colors.red, available));
        addTearDown(compositor.dispose);
        final boundaryKey = GlobalKey();
        final router = GoRouter(
          initialLocation: app_paths.AUDIOS_PAGE,
          routes: [
            GoRoute(
              path: app_paths.AUDIOS_PAGE,
              builder: (_, __) => RepaintBoundary(
                key: boundaryKey,
                child: ValueListenableBuilder<(Color, WindowBackdropStatus)>(
                  valueListenable: compositor,
                  builder: (_, state, child) => Stack(
                    fit: StackFit.expand,
                    children: [
                      // Test-only compositor stand-in; no screen is captured.
                      ColoredBox(color: state.$1),
                      AppWindowSurface(status: state.$2, child: child!),
                    ],
                  ),
                  child: const Scaffold(
                    backgroundColor: Colors.transparent,
                    appBar: PreferredSize(
                      preferredSize: Size.fromHeight(48),
                      child: TitleBarSurface(child: SizedBox.expand()),
                    ),
                    body: Row(
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ));

        Future<List<Color>> render(
            Color backdrop, WindowBackdropStatus status) async {
          compositor.value = (backdrop, status);
          await tester.pumpAndSettle();
          expect(find.byType(AppBackdrop), findsOneWidget);
          expect(tester.getRect(find.byType(AppBackdrop)),
              const Rect.fromLTWH(0, 0, 1280, 900));
          return _sample(tester, boundaryKey, const [
            Offset(20, 20), // Title bar.
            Offset(20, 47), // Last title-bar pixel.
            Offset(20, 48), // First body pixel.
            Offset(20, 899), // Bottom-left navigation background.
            Offset(1260, 899), // Exposed bottom-right margin, below the frame.
            Offset(500, 250), // Opaque content.
          ]);
        }

        final red = await render(Colors.red, available);
        final blue = await render(Colors.blue, available);
        for (final pixels in [red, blue]) {
          expect(pixels.take(4).toSet(), hasLength(1),
              reason:
                  'Title, navigation and bottom-left must not add local washes.');
          _expectNear(
              pixels[3], pixels[4], 2); // Allow the subtle frame shadow.
          expect(pixels[5], scheme.surface);
        }
        final veil = brightness == Brightness.dark
            ? const Color(0xB3202020)
            : const Color(0xB3F3F3F3);
        _expectNear(red[0], Color.alphaBlend(veil, Colors.red), 1);
        _expectNear(blue[0], Color.alphaBlend(veil, Colors.blue), 1);
        expect(red[0], isNot(blue[0]),
            reason: 'The native desktop must remain visible and dynamic.');
        for (final shift in [0, 8, 16]) {
          final desktopDelta = (((Colors.red.toARGB32() >> shift) & 0xFF) -
                  ((Colors.blue.toARGB32() >> shift) & 0xFF))
              .abs();
          final chromeDelta = (((red[0].toARGB32() >> shift) & 0xFF) -
                  ((blue[0].toARGB32() >> shift) & 0xFF))
              .abs();
          expect(chromeDelta, closeTo(desktopDelta * (76 / 255), 2),
              reason: 'Busy desktop contrast should be reduced by about 70%.');
        }
        final fallback = await render(Colors.blue,
            const WindowBackdropStatus(reason: 'transparency_disabled'));
        final fallbackColor = brightness == Brightness.dark
            ? const Color(0xFF202020)
            : const Color(0xFFF3F3F3);
        expect(fallback.take(4), everyElement(fallbackColor));
        expect(nativeCalls, isEmpty);
        expect(find.byType(Image), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byType(ImageFiltered), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        '$brightness real title controls remain transparent and drawer works',
        (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const channel = MethodChannel('window_manager');
      final windowCalls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        windowCalls.add(call.method);
        if (call.method == 'isFullScreen' || call.method == 'isMaximized') {
          return false;
        }
        throw StateError('Unexpected native window operation: ${call.method}');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final scaffoldKey = GlobalKey<ScaffoldState>();
      final router = GoRouter(
        initialLocation: app_paths.AUDIOS_PAGE,
        routes: [
          GoRoute(
            path: app_paths.AUDIOS_PAGE,
            builder: (_, __) => AppWindowSurface(
              child: Scaffold(
                key: scaffoldKey,
                backgroundColor: Colors.transparent,
                appBar: const PreferredSize(
                  preferredSize: Size.fromHeight(48),
                  child: TitleBar(),
                ),
                drawer: const SideNav(),
                body: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        )),
        routerConfig: router,
      ));
      await tester.pumpAndSettle();
      final material = tester
          .widgetList<Material>(find.descendant(
            of: find.byType(TitleBarSurface),
            matching: find.byType(Material),
          ))
          .first;
      expect(material.type, MaterialType.transparency);
      expect(material.color, isNull);
      expect(material.elevation, 0);
      expect(windowCalls, ['isFullScreen', 'isMaximized']);

      await tester.tap(find.byTooltip('打开导航栏'));
      await tester.pumpAndSettle();
      expect(scaffoldKey.currentState!.isDrawerOpen, isTrue);
      final glass = tester.widget<FrostedSurface>(find.byType(FrostedSurface));
      expect(glass.blur, 34);
      expect(glass.showBorder, isFalse);
      expect(glass.boxShadow, isEmpty);
      scaffoldKey.currentState!.closeDrawer();
      await tester.pumpAndSettle();
      expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '$brightness mini stays opaque and touchable above normal glass',
        (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final mode = WindowModeController(adapter: FakeWindowModeAdapter());
      addTearDown(mode.dispose);
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: brightness,
      );
      final boundaryKey = GlobalKey();
      var pinTaps = 0;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: scheme, platform: TargetPlatform.windows),
        home: RepaintBoundary(
          key: boundaryKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.red),
              AppWindowModeHost(
                controller: mode,
                compactBuilder: (_) => CompactPlayerView(
                  onTogglePinned: () => pinTaps++,
                  onRestore: () => mode.exit(),
                ),
                child: const AppWindowSurface(
                  status: WindowBackdropStatus(available: true, effect: 'blur'),
                  child: SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await mode.enter();
      tester.view.physicalSize = const Size(520, 200);
      await tester.pumpAndSettle();
      expect(find.byType(AppBackdrop), findsNothing,
          reason: 'The full-window veil belongs only to the offstage normal.'
              ' Mini must keep its own opaque content surface.');
      final miniPixels =
          await _sample(tester, boundaryKey, [const Offset(1, 1)]);
      expect(miniPixels.single, scheme.surface);
      await tester.tap(find.byKey(const ValueKey('compact-pin')));
      await tester.pump();
      expect(pinTaps, 1);
      await tester.tap(find.byKey(const ValueKey('compact-restore')));
      await tester.pumpAndSettle();
      expect(mode.isMini, isFalse);
      tester.view.physicalSize = const Size(900, 700);
      await tester.pumpAndSettle();
      expect(find.byType(AppBackdrop), findsOneWidget);
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
