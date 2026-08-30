import 'dart:async';

import 'package:dan_player/component/app_window_mode_host.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/window_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_window_mode_adapter.dart';

class _PageProbe extends StatefulWidget {
  const _PageProbe({super.key});

  @override
  State<_PageProbe> createState() => _PageProbeState();
}

class _PageProbeState extends State<_PageProbe>
    with SingleTickerProviderStateMixin {
  final input = TextEditingController(text: 'unsaved draft');
  final focus = FocusNode();
  final scroll = ScrollController();
  late final ticker = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500))
    ..addListener(() => ticks++)
    ..repeat();
  int ticks = 0;
  bool disposed = false;
  Size? layoutSize;
  Size? mediaSize;

  @override
  void initState() {
    super.initState();
    ticker;
  }

  @override
  void dispose() {
    disposed = true;
    ticker.dispose();
    scroll.dispose();
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    mediaSize = MediaQuery.sizeOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      layoutSize = constraints.biggest;
      return Scaffold(
        body: Column(children: [
          SizedBox(
            height: 280,
            child: Column(children: [
              const Text('Original normal page'),
              TextField(
                key: const ValueKey('normal-editor'),
                controller: input,
                focusNode: focus,
              ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: 100,
              itemExtent: 40,
              itemBuilder: (context, index) => Text('Row $index'),
            ),
          ),
        ]),
      );
    });
  }
}

void main() {
  late FakeWindowModeAdapter window;
  late WindowModeController mode;
  late GlobalKey<_PageProbeState> probeKey;
  late GlobalKey<NavigatorState> normalNavigatorKey;
  late GlobalKey<NavigatorState> miniNavigatorKey;

  setUp(() {
    window = FakeWindowModeAdapter();
    probeKey = GlobalKey<_PageProbeState>();
    normalNavigatorKey = GlobalKey<NavigatorState>();
    miniNavigatorKey = GlobalKey<NavigatorState>();
  });
  tearDown(() => mode.dispose());

  Future<void> show(WidgetTester tester,
      {WidgetBuilder? compactBuilder, bool liveCompact = false}) async {
    // Construct queued Futures inside testWidgets' fake-async zone.
    mode = WindowModeController(adapter: window);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: normalNavigatorKey,
      scaffoldMessengerKey: SCAFFOLD_MESSAGER,
      theme: ThemeData(platform: TargetPlatform.windows),
      builder: (context, child) => AppWindowModeHost(
        controller: mode,
        navigatorKey: miniNavigatorKey,
        compactBuilder: liveCompact
            ? null
            : compactBuilder ?? (context) => const Text('Visible compact page'),
        child: child!,
      ),
      home: _PageProbe(key: probeKey),
    ));
    await tester.pump();
  }

  Future<void> enter(WidgetTester tester) async {
    await mode.enter();
    tester.view.physicalSize = const Size(520, 200);
    await tester.pump();
  }

  Future<void> exit(WidgetTester tester) async {
    await mode.exit();
    tester.view.physicalSize = const Size(900, 700);
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
      'mini preserves page instance, draft, scroll, and normal viewport',
      (tester) async {
    await show(tester);
    final original = probeKey.currentState!;
    await tester.enterText(
        find.byKey(const ValueKey('normal-editor')), 'still editing this song');
    original.scroll.jumpTo(650);
    await tester.pump();
    await enter(tester);
    expect(probeKey.currentState, same(original));
    expect(original.disposed, isFalse);
    expect(original.input.text, 'still editing this song');
    expect(original.scroll.offset, 650);
    expect(original.layoutSize, const Size(900, 700));
    expect(original.mediaSize, const Size(900, 700));
    expect(find.text('Original normal page'), findsNothing);
    expect(
        find.text('Original normal page', skipOffstage: false), findsOneWidget);
    expect(find.text('Visible compact page'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await exit(tester);
    expect(probeKey.currentState, same(original));
    expect(original.input.text, 'still editing this song');
    expect(original.scroll.offset, 650);
    expect(find.text('Original normal page'), findsOneWidget);
    expect(find.text('Visible compact page'), findsNothing);
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets('hidden route tickers and input focus stop, then resume on exit',
      (tester) async {
    await show(tester);
    final original = probeKey.currentState!;
    original.focus.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(original.focus.hasFocus, isTrue);
    await enter(tester);
    final miniTicks = original.ticks;
    expect(TickerMode.valuesOf(probeKey.currentContext!).enabled, isFalse);
    expect(original.focus.hasFocus, isFalse);
    expect(original.focus.canRequestFocus, isFalse);
    original.focus.requestFocus();
    await tester.pump(const Duration(milliseconds: 500));
    expect(original.ticks, miniTicks);
    expect(original.focus.hasFocus, isFalse);
    await exit(tester);
    expect(original.focus.hasFocus, isTrue);
    expect(TickerMode.valuesOf(probeKey.currentContext!).enabled, isTrue);
    final restoredTicks = original.ticks;
    await tester.pump(const Duration(milliseconds: 100));
    expect(original.ticks, greaterThan(restoredTicks));
  });

  testWidgets('normal route stays laid out safely until exit metrics arrive',
      (tester) async {
    await show(tester);
    await enter(tester);
    await mode.exit();
    // Native state/method replies can precede the next Flutter metrics frame.
    // The old compact client size must not become the saved normal viewport.
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(probeKey.currentState!.layoutSize, const Size(900, 700));
    expect(probeKey.currentState!.mediaSize, const Size(900, 700));
    tester.view.physicalSize = const Size(900, 700);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'quick enter-exit before any mini frame retains the normal viewport',
      (tester) async {
    await show(tester);
    await mode.enter();
    await mode.exit();
    tester.view.physicalSize = const Size(520, 200);
    await tester.pump();
    expect(probeKey.currentState!.layoutSize, const Size(900, 700));
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(900, 700);
    await tester.pump();
    expect(probeKey.currentState!.layoutSize, const Size(900, 700));
  });

  testWidgets('an early mini frame with old normal metrics is not a mini size',
      (tester) async {
    await show(tester);
    await mode.enter();
    // The mini layout can mount before the native shrink metrics arrive.
    await tester.pump();
    await mode.exit();
    tester.view.physicalSize = const Size(520, 200);
    await tester.pump();
    expect(probeKey.currentState!.layoutSize, const Size(900, 700));
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(900, 700);
    await tester.pump();
  });

  for (final compactSize in [const Size(620, 240), const Size(820, 600)]) {
    testWidgets(
        'a resized mini $compactSize is not mistaken for restored metrics',
        (tester) async {
      await show(tester);
      await enter(tester);
      tester.view.physicalSize = compactSize;
      await tester.pump();
      await mode.exit();
      await tester.pump();
      expect(probeKey.currentState!.layoutSize, const Size(900, 700));
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(900, 700);
      await tester.pump();
    });
  }

  testWidgets(
      'normal metrics arriving while exit is busy are retained on commit',
      (tester) async {
    await show(tester);
    await enter(tester);
    tester.view.physicalSize = const Size(620, 240);
    await tester.pump();
    final gate = Completer<void>();
    final started = Completer<void>();
    window.beforeCall = (method) async {
      if (method == 'setAlwaysOnTop' && !started.isCompleted) {
        started.complete();
        await gate.future;
      }
    };
    final exiting = mode.exit();
    await started.future;
    tester.view.physicalSize = const Size(900, 700);
    await tester.pump();
    expect(mode.isBusy, isTrue);
    expect(probeKey.currentState!.layoutSize, const Size(900, 700));
    gate.complete();
    await exiting;
    await tester.pump();
    expect(mode.isMini, isFalse);
    expect(probeKey.currentState!.layoutSize, const Size(900, 700));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the normal Navigator retains its current route and back stack',
      (tester) async {
    await show(tester);
    final normalNavigator = normalNavigatorKey.currentState!;
    final detailRoute = MaterialPageRoute<void>(
      builder: (context) =>
          const Scaffold(body: Text('Preserved detail route')),
    );
    normalNavigator.push(detailRoute);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await enter(tester);
    expect(normalNavigatorKey.currentState, same(normalNavigator));
    expect(normalNavigator.canPop(), isTrue);
    expect(detailRoute.isCurrent, isTrue);
    expect(find.text('Preserved detail route'), findsNothing);
    await exit(tester);
    expect(find.text('Preserved detail route'), findsOneWidget);
    expect(normalNavigator.canPop(), isTrue);
    expect(detailRoute.isCurrent, isTrue);
    normalNavigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('mini has an independent visible navigator for shortcut help',
      (tester) async {
    await show(tester,
        compactBuilder: (context) => Center(
              child: TextButton(
                onPressed: () => HotkeysHelper.showShortcuts(context),
                child: const Text('Open compact help'),
              ),
            ));
    await enter(tester);
    expect(find.byType(Navigator), findsOneWidget);
    expect(find.byType(Navigator, skipOffstage: false), findsNWidgets(2));
    await tester.tap(find.text('Open compact help'));
    await tester.pumpAndSettle();
    expect(find.text('快捷键'), findsOneWidget);
    expect(miniNavigatorKey.currentState!.canPop(), isTrue);
    expect(normalNavigatorKey.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('关闭快捷键说明'));
    await tester.pumpAndSettle();
    expect(find.text('快捷键'), findsNothing);
    expect(find.text('Open compact help'), findsOneWidget);
  });

  testWidgets('compact window failures show a visible local snackbar',
      (tester) async {
    await show(tester, liveCompact: true);
    await enter(tester);
    var failPin = true;
    window.beforeCall = (method) {
      if (method == 'setAlwaysOnTop' && failPin) {
        failPin = false;
        throw StateError('simulated pin rejection');
      }
    };
    await tester.tap(find.byKey(const ValueKey('compact-pin')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('切换窗口置顶失败'), findsOneWidget);
    final snackContext = tester.element(find.byType(SnackBar));
    expect(ScaffoldMessenger.of(snackContext),
        isNot(same(SCAFFOLD_MESSAGER.currentState)));
    expect(PlayService.isInitialized, isFalse);
    expect(mode.isBusy, isFalse);
    expect(mode.isMini, isTrue);
    expect(tester.takeException(), isNull);
    ScaffoldMessenger.of(snackContext).removeCurrentSnackBar();
    await tester.pump();
  });
}
