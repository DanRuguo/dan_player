import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/detail_volume_panel.dart';
import 'package:dan_player/component/player_number_dialog.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/now_playing_page/component/queue_stop_status.dart';
import 'package:dan_player/page/now_playing_page/component/sleep_timer_submenu.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/queue_stop_boundary.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Playback extends ChangeNotifier implements PlaybackService {
  @override
  final sleepTimerRemaining = ValueNotifier<Duration?>(null);
  @override
  final sleepTimerPaused = ValueNotifier(false);
  @override
  final sleepTimerFinishCurrent = ValueNotifier(false);
  @override
  final stopAfterCurrent = ValueNotifier(false);
  @override
  final queueStopBoundary = QueueStopBoundary();
  @override
  final segmentLoop = SegmentLoopController();
  @override
  final playMode = ValueNotifier(PlayMode.forward);
  @override
  final playlist = ValueNotifier<List<Audio>>([]);
  @override
  String? get queueStopBlockedReason => null;
  @override
  String? get queueStopTargetLabel => null;
  @override
  void startSleepTimer(Duration duration) {
    sleepTimerRemaining.value = duration;
    sleepTimerPaused.value = false;
  }

  @override
  void adjustSleepTimer(Duration delta) =>
      sleepTimerRemaining.value = sleepTimerRemaining.value! + delta;
  @override
  void toggleSleepTimerPaused() =>
      sleepTimerPaused.value = !sleepTimerPaused.value;
  @override
  void setSleepTimerFinishCurrent(bool enabled) =>
      sleepTimerFinishCurrent.value = enabled;
  @override
  void setStopAfterCurrent(bool value) => stopAfterCurrent.value = value;
  @override
  void cancelSleepTimer() {
    sleepTimerRemaining.value = null;
    sleepTimerPaused.value = false;
  }

  @override
  void dispose() {
    sleepTimerRemaining.dispose();
    sleepTimerPaused.dispose();
    sleepTimerFinishCurrent.dispose();
    stopAfterCurrent.dispose();
    queueStopBoundary.dispose();
    segmentLoop.dispose();
    playMode.dispose();
    playlist.dispose();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child,
        {double scale = 1, bool dark = false, bool reduced = true}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Entry(welcome: false).fromSchemeAndFontFamily(
          fontFamily: danEmbeddedFontFamily,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: dark ? Brightness.dark : Brightness.light)),
      builder: (context, child) => UiLanguageScope(
          child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: reduced),
              child: child!)),
      home: Scaffold(body: child),
    );

Future<void> _render(WidgetTester tester, GlobalKey key, String name) async {
  const output = String.fromEnvironment('DAN_COMFORT_RENDER');
  if (output.isEmpty) return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    final data = await image.toByteData(format: raster.ImageByteFormat.png);
    final file = File('$output/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final korean = File('${Platform.environment['WINDIR']}/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final reduced in [false, true]) {
    testWidgets(
        'nested more menu custom timer survives menu disposal reduced=$reduced',
        (tester) async {
      final service = _Playback();
      addTearDown(service.dispose);
      await tester.pumpWidget(_app(
          Center(
              child: MenuAnchor(
            menuChildren: [SleepTimerSubmenu(playbackService: service)],
            builder: (_, menu, __) => TextButton(
                key: const ValueKey('comfort-more-menu'),
                onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                child: const Text('More')),
          )),
          reduced: reduced));
      Future<void> openDialog() async {
        await tester.tap(find.byKey(const ValueKey('comfort-more-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(SubmenuButton));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sleep-custom')));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerNumberDialog), findsOneWidget);
        expect(find.byType(SleepTimerSubmenu), findsNothing,
            reason: 'The real nested menu is gone before dialog confirmation.');
      }

      await openDialog();
      await tester.enterText(find.byType(TextField), '17');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(service.sleepTimerRemaining.value, const Duration(minutes: 17));
      await openDialog();
      await tester.enterText(find.byType(TextField), '81');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(service.sleepTimerRemaining.value, const Duration(minutes: 17));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'volume mute restores across popup reopen and follows external volume',
      (tester) async {
    final volume = ValueNotifier(.63);
    addTearDown(volume.dispose);
    await tester.pumpWidget(_app(Center(
        child: DetailVolumeButton(
            readVolume: () => volume.value,
            changes: volume,
            onChanged: (value) => volume.value = value))));
    await tester.tap(find.byTooltip('音量'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('volume-toggle-mute')));
    await tester.pumpAndSettle();
    expect(volume.value, 0);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('音量'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('volume-toggle-mute')));
    await tester.pumpAndSettle();
    expect(volume.value, .63);
    volume.value = .37;
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('volume-toggle-mute')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('volume-toggle-mute')));
    await tester.pump();
    expect(volume.value, .37);
    await tester.tap(find.byKey(const ValueKey('volume-preset-75')));
    await tester.pump();
    expect(volume.value, .75);
  });

  testWidgets('exact volume validates range and cancel preserves latest volume',
      (tester) async {
    final volume = ValueNotifier(.63);
    addTearDown(volume.dispose);
    await tester.pumpWidget(_app(Center(
        child: DetailVolumeButton(
            readVolume: () => volume.value,
            changes: volume,
            onChanged: (value) => volume.value = value))));
    await tester.tap(find.byTooltip('音量'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('volume-exact')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '101');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(volume.value, .63);
    expect(find.byType(PlayerNumberDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), '37');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(volume.value, .37);
    await tester.tap(find.byKey(const ValueKey('volume-exact')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '80');
    volume.value = .2;
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(volume.value, .2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'custom sleep validates then status pauses and cancels the same timer',
      (tester) async {
    final service = _Playback();
    addTearDown(service.dispose);
    await tester.pumpWidget(_app(Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
      SleepTimerSubmenu(playbackService: service),
      QueueStopStatus(playbackService: service),
    ]))));
    await tester.tap(find.byType(SubmenuButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sleep-custom')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1441');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(service.sleepTimerRemaining.value, isNull);
    await tester.enterText(find.byType(TextField), '17');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(service.sleepTimerRemaining.value, const Duration(minutes: 17));
    expect(find.byKey(const ValueKey('sleep-timer-status')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sleep-status-pause')));
    await tester.pump();
    expect(service.sleepTimerPaused.value, isTrue);
    await tester.tap(find.byType(SubmenuButton));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('sleep-adjust-more')));
    await tester.tap(find.byKey(const ValueKey('sleep-adjust-more')));
    await tester.pumpAndSettle();
    expect(service.sleepTimerRemaining.value, const Duration(minutes: 22));
    expect(service.sleepTimerPaused.value, isTrue);
    await tester.tap(find.byKey(const ValueKey('sleep-status-cancel')));
    await tester.pump();
    expect(service.sleepTimerRemaining.value, isNull);
    expect(find.byKey(const ValueKey('sleep-timer-status')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('queue status keeps both sleep controls and its stop target',
      (tester) async {
    final service = _Playback()..startSleepTimer(const Duration(minutes: 20));
    addTearDown(service.dispose);
    await tester.pumpWidget(_app(Column(children: [
      QueueStopStatus(playbackService: service),
    ])));
    expect(find.byKey(const ValueKey('sleep-timer-status')), findsOneWidget);
    expect(find.byKey(const ValueKey('sleep-status-pause')), findsOneWidget);
    service.setStopAfterCurrent(true);
    await tester.pump();
    expect(find.byKey(const ValueKey('queue-stop-target')), findsOneWidget);
  });

  for (final active in [false, true]) {
    for (final density in [VisualDensity.standard, VisualDensity.compact]) {
      testWidgets(
          'sleep submenu bottom follows its trigger active=$active density=$density',
          (tester) async {
        tester.view.physicalSize = const Size(900, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = _Playback();
        if (active) service.startSleepTimer(const Duration(minutes: 20));
        addTearDown(service.dispose);
        final menu = MenuController();
        await tester.pumpWidget(_app(Builder(
            builder: (context) => Theme(
                data: Theme.of(context).copyWith(visualDensity: density),
                child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                        padding: const EdgeInsets.only(right: 48, bottom: 32),
                        child: MenuAnchor(
                            controller: menu,
                            menuChildren: [
                              const MenuItemButton(child: Text('First')),
                              const MenuItemButton(child: Text('Second')),
                              SleepTimerSubmenu(playbackService: service),
                            ],
                            builder: (context, controller, child) =>
                                const SizedBox(width: 48, height: 48))))))));
        menu.open();
        await tester.pumpAndSettle();
        final trigger = find.byType(SubmenuButton);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        final triggerBottom = tester.getRect(trigger).bottom;
        // The quantity action is now required below all dynamic timer rows.
        final lastItemBottom = tester
            .getRect(find.byKey(const ValueKey('sleep-stop-after-count')))
            .bottom;
        expect(lastItemBottom, closeTo(triggerBottom - 8, 2));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets('render comfort ${language.name} narrow=$narrow',
          (tester) async {
        tester.view.physicalSize = Size(narrow ? 360 : 900, narrow ? 720 : 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        uiLanguage.value = language;
        final service = _Playback()
          ..startSleepTimer(const Duration(minutes: 23, seconds: 45));
        addTearDown(service.dispose);
        final volume = ValueNotifier(.63);
        addTearDown(volume.dispose);
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: _app(
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SleepTimerSubmenu(playbackService: service),
                          QueueStopStatus(playbackService: service),
                          const SizedBox(height: 24),
                          DetailVolumeButton(
                              readVolume: () => volume.value,
                              changes: volume,
                              onChanged: (value) => volume.value = value),
                        ])),
                scale: narrow ? 2 : 1,
                dark: !narrow)));
        await tester.tap(find.byTooltip(ui('音量')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final panel = tester.getRect(find.byType(DetailVolumePanel));
        expect(panel.left, greaterThanOrEqualTo(0));
        expect(panel.right, lessThanOrEqualTo(narrow ? 360 : 900));
        await _render(tester, key, '${language.name}-$narrow-volume');
        await tester.tap(find.byKey(const ValueKey('volume-exact')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _render(tester, key, '${language.name}-$narrow-number');
        await tester.tap(find.text(ui('取消')));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(SubmenuButton));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _render(tester, key, '${language.name}-$narrow-sleep');
        final cancel = find.byKey(const ValueKey('sleep-menu-cancel'));
        await tester.ensureVisible(cancel);
        await tester.pumpAndSettle();
        expect(tester.getRect(cancel).right,
            lessThanOrEqualTo(narrow ? 360 : 900));
        await _render(tester, key, '${language.name}-$narrow-sleep-bottom');
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(service.sleepTimerRemaining.value, isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }
}
