import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:dan_player/app_paths.dart' as paths;
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/compact_process_resource_monitor.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/process_resource_chart.dart';
import 'package:dan_player/component/process_resource_monitor.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/component/title_bar.dart';
import 'package:dan_player/page/now_playing_page/page.dart';
import 'package:dan_player/process_resource_coordinator.dart';
import 'package:dan_player/process_resource_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';
import 'support/process_resource_fixture.dart';

const _allSurfaces = ProcessResourcePreferences(
    enabled: true, showInSidebar: true, showInLyrics: true);

Future<void> _sample(MethodChannel channel, int session,
    {double? cpu = 12.5,
    double? gpu = 23.4,
    int? memory = 1024 * 1024 * 256,
    int? total = 1024 * 1024 * 1024 * 8}) async {
  final done = Completer<void>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall('sample', {
            'session': session,
            'cpuPercent': cpu,
            'gpuPercent': gpu,
            'workingSetBytes': memory,
            'totalPhysicalMemoryBytes': total,
            'cpuStatus': cpu == null ? 'unavailable' : 'ready',
            'gpuStatus': gpu == null ? 'unavailable' : 'ready',
          })),
          (_) => done.complete());
  await done.future;
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('window_manager'),
            (call) async =>
                call.method == 'isFullScreen' || call.method == 'isMaximized'
                    ? false
                    : null);
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets(
      'three actual resource surfaces share one worker and last visible lease stops it',
      (tester) async {
    sizePlaylistFeature(tester, width: 1100, height: 1000);
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final prefs = ValueNotifier(_allSurfaces);
    final hidden = ValueNotifier(false);
    Widget host({bool backup = true}) => listeningStatusHost(Column(children: [
          Row(children: [
            SizedBox(
                width: 260,
                child: CompactProcessResourceMonitor(
                    surface: ProcessResourceSurface.sidebar,
                    preferences: prefs,
                    coordinator: coordinator,
                    isHidden: hidden)),
            SizedBox(
                width: 180,
                child: CompactProcessResourceMonitor(
                    surface: ProcessResourceSurface.lyrics,
                    preferences: prefs,
                    coordinator: coordinator,
                    isHidden: hidden)),
          ]),
          if (backup)
            Expanded(
                child: SingleChildScrollView(
                    child: ProcessResourceMonitor(
                        coordinator: coordinator,
                        preferences: prefs,
                        isHidden: hidden,
                        onPreferencesChanged: (value) async =>
                            prefs.value = value))),
        ]));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(rig.calls.map((call) => call.method), ['start']);
    await _sample(rig.channel, rig.session);
    await tester.pump();
    expect(find.byTooltip('CPU: 12.5%'), findsOneWidget);
    expect(find.byTooltip('${ui('内存')}: 3.1% · 256.0 MiB'), findsOneWidget);
    await tester.pumpWidget(host(backup: false));
    await tester.pumpAndSettle();
    expect(rig.calls, hasLength(1),
        reason: 'closing backup leaves compact leases active');
    prefs.value = prefs.value.copyWith(display: ProcessResourceDisplay.line);
    await tester.pumpAndSettle();
    final graphs = tester
        .widgetList<ProcessResourceChart>(find.byType(ProcessResourceChart));
    expect(graphs, hasLength(6));
    expect(graphs.every((graph) => graph.maximum == 100), isTrue);
    expect(tester.getSize(find.byType(ProcessResourceChart).first).width,
        greaterThan(20));
    prefs.value =
        prefs.value.copyWith(intervalSeconds: 1, showInSidebar: false);
    await tester.pumpAndSettle();
    expect(rig.calls.map((call) => call.method), ['start', 'stop', 'start']);
    expect((rig.calls.last.arguments as Map)['intervalSeconds'], 1);
    hidden.value = true;
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'stop');
    final count = rig.service.history.length;
    await _sample(rig.channel, rig.session);
    expect(rig.service.history, hasLength(count));
    hidden.value = false;
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'start');
    prefs.value = prefs.value.copyWith(enabled: false);
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'stop');
    expect(find.byType(ProcessResourceChart), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
    await rig.close();
    prefs.dispose();
    hidden.dispose();
  });

  testWidgets(
      'compact visibility follows viewport lifecycle TickerMode and route coverage',
      (tester) async {
    sizePlaylistFeature(tester, width: 800, height: 600);
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final prefs = ValueNotifier(_allSurfaces);
    final hidden = ValueNotifier(false);
    final scroll = ScrollController();
    final navigator = GlobalKey<NavigatorState>();
    final tickers = ValueNotifier(true);
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
            body: ValueListenableBuilder(
                valueListenable: tickers,
                builder: (context, ticking, _) => TickerMode(
                    enabled: ticking,
                    child: SingleChildScrollView(
                        controller: scroll,
                        child: Column(children: [
                          const SizedBox(height: 900),
                          SizedBox(
                              width: 180,
                              child: CompactProcessResourceMonitor(
                                  surface: ProcessResourceSurface.lyrics,
                                  preferences: prefs,
                                  coordinator: coordinator,
                                  isHidden: hidden))
                        ])))))));
    await tester.pumpAndSettle();
    expect(rig.calls, isEmpty);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'start');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'stop');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'start');
    tickers.value = false;
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'stop');
    tickers.value = true;
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'start');
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('covered')))));
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'stop');
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'start');
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(rig.calls.last.method, 'stop');
    final calls = rig.calls.length;
    await tester.pump(const Duration(seconds: 30));
    expect(rig.calls, hasLength(calls));
    await tester.pumpWidget(const SizedBox());
    await rig.close();
    prefs.dispose();
    hidden.dispose();
    scroll.dispose();
    tickers.dispose();
  });

  testWidgets(
      'real sidebar monitor leaves adaptive bottom space with 76px large text and keeps last navigation reachable',
      (tester) async {
    sizePlaylistFeature(tester, width: 1200, height: 800);
    final saved = AppSettings.instance.processResources.value;
    AppSettings.instance.processResources.value = _allSurfaces;
    addTearDown(() => AppSettings.instance.processResources.value = saved);
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final channel = rig.channel, calls = rig.calls;
    final width = ValueNotifier(300.0), height = ValueNotifier(700.0);
    final boundary = GlobalKey();
    final router = GoRouter(initialLocation: paths.AUDIOS_PAGE, routes: [
      GoRoute(
          path: paths.AUDIOS_PAGE,
          builder: (_, __) => Scaffold(
              body: ValueListenableBuilder(
                  valueListenable: width,
                  builder: (context, w, _) => ValueListenableBuilder(
                      valueListenable: height,
                      builder: (context, h, _) => Align(
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                              width: w,
                              height: h,
                              child: SideNav(
                                  desktopWidth: w,
                                  resourceCoordinator: coordinator)))))))
    ]);
    Widget host(double scale, Color seed) => UiLanguageScope(
        child: MaterialApp.router(
            routerConfig: router,
            theme: ThemeData(
                fontFamily: danEmbeddedFontFamily,
                fontFamilyFallback: danFontFamilyFallback,
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(seedColor: seed)),
            builder: (context, child) => RepaintBoundary(
                key: boundary,
                child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        disableAnimations: true),
                    child: child!))));
    await tester.pumpWidget(host(1, Colors.indigo));
    await tester.pumpAndSettle();
    final session = (calls.lastWhere((call) => call.method == 'start').arguments
        as Map)['session'] as int;
    await _sample(channel, session);
    await tester.pump();
    expect(
        tester
            .getBottomLeft(
                find.byKey(const ValueKey('sidebar-process-resources')))
            .dy,
        652);
    await capturePlaylistFeature(tester, boundary, 'sidebar-wide');
    final cpuMetric =
        find.byKey(const ValueKey('compact-resource-sidebar-CPU'));
    final cpuIcon = find.descendant(of: cpuMetric, matching: find.byType(Icon));
    expect(tester.getCenter(cpuIcon).dx, 40);
    expect(tester.widget<Icon>(cpuIcon).size, 28);
    expect(tester.getTopLeft(find.text('12.5%')).dx, closeTo(66, .01));
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('sidebar-process-resources')),
            matching: find.byType(Tooltip)),
        findsNothing);
    width.value = 76;
    height.value = 360;
    uiLanguage.value = UiLanguage.ko;
    await tester.pumpWidget(host(1.8, Colors.pink));
    await tester.pumpAndSettle();
    final monitor = find.byKey(const ValueKey('sidebar-process-resources'));
    expect(tester.getSize(monitor).width, 76);
    expect(tester.getBottomLeft(monitor).dy, 350);
    expect(find.descendant(of: monitor, matching: find.byType(Text)),
        findsNothing);
    expect(
        find.descendant(
            of: monitor, matching: find.byType(ProcessResourceChart)),
        findsNothing);
    expect(tester.getCenter(cpuIcon).dx, 38);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: const Offset(500, 500));
    await pointer.moveTo(tester.getCenter(cpuIcon));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('CPU: 12.5%'), findsOneWidget);
    await pointer.moveTo(const Offset(500, 500));
    await tester.pumpAndSettle();
    await pointer.removePointer();
    await tester.drag(find.byKey(const ValueKey('continuous-side-nav-list')),
        const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(
        find
            .byKey(const ValueKey('continuous-nav-${paths.SETTINGS_PAGE}'))
            .hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await capturePlaylistFeature(tester, boundary, 'sidebar-76-large-ko');
    height.value = 160;
    await tester.pumpAndSettle();
    expect(monitor, findsNothing);
    expect(calls.last.method, 'stop');
    await tester.pumpWidget(const SizedBox());
    await rig.close();
    router.dispose();
    width.dispose();
    height.dispose();
  });

  testWidgets(
      'real lyric title resources fit 400px and use theme with unknown values intact',
      (tester) async {
    sizePlaylistFeature(tester, width: 400, height: 300);
    final saved = AppSettings.instance.processResources.value;
    AppSettings.instance.processResources.value =
        _allSurfaces.copyWith(display: ProcessResourceDisplay.bar);
    addTearDown(() => AppSettings.instance.processResources.value = saved);
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final channel = rig.channel, calls = rig.calls;
    final boundary = GlobalKey();
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      await tester.pumpWidget(listeningStatusHost(
          SizedBox(
              height: 56,
              child:
                  NowPlayingResourceTitleBar(resourceCoordinator: coordinator)),
          scale: 2,
          seed: language == UiLanguage.en ? Colors.orange : Colors.indigo,
          boundary: boundary));
      await tester.pumpAndSettle();
      final session = (calls
          .lastWhere((call) => call.method == 'start')
          .arguments as Map)['session'] as int;
      await _sample(channel, session, gpu: null, total: null);
      await tester.pump();
      final resources = find.byKey(const ValueKey('lyrics-process-resources'));
      expect(resources, findsOneWidget);
      final resourcesRect = tester.getRect(resources);
      final controlsRect = tester.getRect(find.byType(WindowControlls));
      final windowButtons = find.descendant(
          of: find.byType(WindowControlls), matching: find.byType(IconButton));
      expect(windowButtons, findsNWidgets(5));
      for (final element in windowButtons.evaluate()) {
        expect(tester.getSize(find.byWidget(element.widget)),
            const Size.square(40));
      }
      for (final name in ['CPU', 'GPU', 'RAM']) {
        final metric = find.byKey(ValueKey('compact-resource-lyrics-$name'));
        expect(tester.getSize(metric).width, 40);
        final icon = find.descendant(of: metric, matching: find.byType(Icon));
        expect(tester.widget<Icon>(icon).size, 24);
      }
      expect(resourcesRect.right, lessThanOrEqualTo(controlsRect.left - 24));
      expect(
          tester
              .getSize(find.byKey(const ValueKey('lyrics-title-drag-region')))
              .width,
          greaterThanOrEqualTo(24));
      final charts = tester
          .widgetList<ProcessResourceChart>(find.descendant(
              of: resources, matching: find.byType(ProcessResourceChart)))
          .toList();
      final chartElements = find
          .descendant(
              of: resources, matching: find.byType(ProcessResourceChart))
          .evaluate()
          .toList();
      final chartRects = chartElements
          .map((element) => tester.getRect(find.byWidget(element.widget)))
          .toList();
      expect(chartRects.every((rect) => rect.width == 24), isTrue);
      for (var index = 1; index < chartRects.length; index++) {
        expect(chartRects[index].left - chartRects[index - 1].right,
            greaterThanOrEqualTo(16));
      }
      expect(charts, hasLength(3));
      expect(charts.map((chart) => chart.value), [12.5, null, null]);
      expect(
          charts.every((chart) =>
              chart.color ==
              Theme.of(tester.element(resources)).colorScheme.primary),
          isTrue);
      expect(find.byTooltip('GPU: ${ui('不可用')}'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureListeningStatus(
          tester, boundary, 'lyric-title-${language.name}');
    }
    AppSettings.instance.processResources.value =
        _allSurfaces.copyWith(display: ProcessResourceDisplay.line);
    await tester.pumpAndSettle();
    final graphs = find.byType(ProcessResourceChart);
    expect(tester.getSize(graphs.first).width, greaterThan(10));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
    await rig.close();
  });

  testWidgets(
      'real closed drawer and initial paused mount stay idle and leaving root sidebar releases sampling',
      (tester) async {
    sizePlaylistFeature(tester, width: 400, height: 800);
    final saved = AppSettings.instance.processResources.value;
    AppSettings.instance.processResources.value = _allSurfaces;
    addTearDown(() => AppSettings.instance.processResources.value = saved);
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final channel = rig.channel, calls = rig.calls;
    final scaffold = GlobalKey<ScaffoldState>();
    final boundary = GlobalKey();
    final router = GoRouter(initialLocation: paths.AUDIOS_PAGE, routes: [
      GoRoute(
          path: paths.AUDIOS_PAGE,
          builder: (_, __) => Scaffold(
              key: scaffold,
              drawer: SideNav(resourceCoordinator: coordinator),
              body: const Text('main'))),
      GoRoute(
          path: '/covered',
          builder: (_, __) => const Scaffold(body: Text('covered'))),
    ]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpWidget(UiLanguageScope(
        child: MaterialApp.router(
            theme: ThemeData(
                useMaterial3: true,
                fontFamily: danEmbeddedFontFamily,
                fontFamilyFallback: danFontFamilyFallback,
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
            routerConfig: router,
            builder: (context, child) => RepaintBoundary(
                key: boundary,
                child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(disableAnimations: true),
                    child: child!)))));
    await tester.pumpAndSettle();
    expect(calls, isEmpty,
        reason: 'closed overlay drawer is not a resource surface');
    scaffold.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(calls, isEmpty,
        reason: 'initially paused drawer mount must not sample');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls.map((call) => call.method), ['start']);
    await _sample(channel, (calls.last.arguments as Map)['session'] as int);
    await tester.pump();
    final resources = find.byKey(const ValueKey('sidebar-process-resources'));
    expect(tester.getSize(resources).width, 304);
    await capturePlaylistFeature(tester, boundary, 'sidebar-drawer');
    scaffold.currentState!.closeDrawer();
    await tester.pumpAndSettle();
    expect(calls.last.method, 'stop');
    scaffold.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(calls.last.method, 'start');
    unawaited(router.push<void>('/covered'));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'stop');
    router.pop();
    await tester.pumpAndSettle();
    expect(calls.last.method, 'start');
    router.go('/covered');
    await tester.pumpAndSettle();
    expect(calls.last.method, 'stop');
    expect(resources, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await rig.close();
    router.dispose();
  });

  testWidgets(
      'mini percentage and line surfaces render readable current values with hover precision',
      (tester) async {
    sizePlaylistFeature(tester, width: 400, height: 180);
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final prefs = ValueNotifier(_allSurfaces);
    final hidden = ValueNotifier(false);
    final boundary = GlobalKey();
    await tester.pumpWidget(listeningStatusHost(
        Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
                width: 108,
                child: CompactProcessResourceMonitor(
                    surface: ProcessResourceSurface.lyrics,
                    preferences: prefs,
                    coordinator: coordinator,
                    isHidden: hidden))),
        scale: 2,
        boundary: boundary));
    await tester.pumpAndSettle();
    await _sample(rig.channel, rig.session);
    await tester.pump();
    expect(find.byTooltip('CPU: 12.5%'), findsOneWidget);
    expect(find.text('12.5%'), findsOneWidget);
    expect(find.text('3.1%'), findsOneWidget);
    await captureListeningStatus(tester, boundary, 'lyric-mini-numbers');
    prefs.value = prefs.value.copyWith(display: ProcessResourceDisplay.line);
    await tester.pumpAndSettle();
    await _sample(rig.channel, rig.session, cpu: 37.8, gpu: 52.3);
    await tester.pump();
    expect(tester.getSize(find.byType(ProcessResourceChart).first).width,
        greaterThan(20));
    await captureListeningStatus(tester, boundary, 'lyric-mini-line');
    await tester.pumpWidget(const SizedBox());
    await rig.close();
    prefs.dispose();
    hidden.dispose();
  });

  testWidgets(
      'medium navigation rail resources remain icon only without overflow',
      (tester) async {
    sizePlaylistFeature(tester, width: 1000, height: 700);
    final saved = AppSettings.instance.processResources.value;
    AppSettings.instance.processResources.value = _allSurfaces;
    addTearDown(() => AppSettings.instance.processResources.value = saved);
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final boundary = GlobalKey();
    final router = GoRouter(initialLocation: paths.AUDIOS_PAGE, routes: [
      GoRoute(
          path: paths.AUDIOS_PAGE,
          builder: (_, __) => Scaffold(
              body: Align(
                  alignment: Alignment.topLeft,
                  child: SideNav(resourceCoordinator: coordinator)))),
    ]);
    await tester.pumpWidget(UiLanguageScope(
        child: MaterialApp.router(
            routerConfig: router,
            theme: ThemeData(
                useMaterial3: true,
                fontFamily: danEmbeddedFontFamily,
                fontFamilyFallback: danFontFamilyFallback),
            builder: (context, child) => RepaintBoundary(
                key: boundary,
                child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(disableAnimations: true),
                    child: child!)))));
    await tester.pumpAndSettle();
    await _sample(rig.channel, rig.session);
    await tester.pump();
    final monitor = find.byKey(const ValueKey('sidebar-process-resources'));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.getSize(monitor).width, 80);
    expect(find.descendant(of: monitor, matching: find.byType(Text)),
        findsNothing);
    final icon = find.descendant(
        of: find.byKey(const ValueKey('compact-resource-sidebar-CPU')),
        matching: find.byType(Icon));
    expect(tester.getCenter(icon).dx, 40);
    expect(find.byTooltip('CPU: 12.5%'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capturePlaylistFeature(tester, boundary, 'sidebar-medium-rail');
    await tester.pumpWidget(const SizedBox());
    await rig.close();
    router.dispose();
  });

  testWidgets(
      'hidden compact consumer freezes its view while another lease continues sampling',
      (tester) async {
    sizePlaylistFeature(tester, width: 700, height: 300);
    final rig = ResourceTestRig();
    final coordinator =
        ProcessResourceCoordinator.forTesting(service: rig.service);
    final prefs = ValueNotifier(_allSurfaces);
    final hidden = ValueNotifier(false);
    final visible = ValueNotifier(true);
    final sidebar = SizedBox(
        width: 260,
        child: CompactProcessResourceMonitor(
            surface: ProcessResourceSurface.sidebar,
            preferences: prefs,
            coordinator: coordinator,
            isHidden: hidden));
    await tester.pumpWidget(listeningStatusHost(Column(children: [
      ValueListenableBuilder(
          valueListenable: visible,
          child: sidebar,
          builder: (context, value, child) =>
              TickerMode(enabled: value, child: child!)),
      SizedBox(
          width: 180,
          child: CompactProcessResourceMonitor(
              surface: ProcessResourceSurface.lyrics,
              preferences: prefs,
              coordinator: coordinator,
              isHidden: hidden)),
    ])));
    await tester.pumpAndSettle();
    await _sample(rig.channel, rig.session);
    await tester.pump();
    visible.value = false;
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('compact-resource-sidebar-CPU'),
        skipOffstage: false);
    final cpuText = find.descendant(
        of: row, matching: find.byType(Text), skipOffstage: false);
    final frozen = tester.widget<Text>(cpuText);
    await _sample(rig.channel, rig.session, cpu: 78.1);
    await tester.pump();
    expect(tester.widget<Text>(cpuText), same(frozen));
    expect(frozen.data, '12.5%');
    expect(find.text('78.1%'), findsOneWidget);
    expect(rig.calls.map((call) => call.method), ['start']);
    visible.value = true;
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(cpuText).data, '78.1%');
    expect(rig.calls.map((call) => call.method), ['start']);
    await tester.pumpWidget(const SizedBox());
    await rig.close();
    prefs.dispose();
    hidden.dispose();
    visible.dispose();
  });
}
