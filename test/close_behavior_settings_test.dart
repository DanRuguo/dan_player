import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/touch_gestures.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/page/settings_page/cache_backup_settings.dart';
import 'package:dan_player/page/settings_page/close_behavior_settings.dart';
import 'package:dan_player/page/settings_page/grouped_settings.dart';
import 'package:dan_player/page/settings_page/page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';

Widget _host(Widget child, {double scale = 1, bool dark = false}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      scrollBehavior: const DanPlayerScrollBehavior(),
      theme: Entry(welcome: false).fromSchemeAndFontFamily(
        fontFamily: danEmbeddedFontFamily,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: dark ? Brightness.dark : Brightness.light),
      ),
      builder: (context, child) => MotionPreferencesScope(
          preferences: const MotionPreferences().all(false),
          child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!)),
      home: Scaffold(body: child),
    );

Future<void> _choose(WidgetTester tester, bool tray) async {
  final choice = find.byKey(const ValueKey('close-to-tray-setting'));
  await tester.ensureVisible(choice);
  await tester.tap(choice);
  await tester.pumpAndSettle();
  await tester.tap(find
      .byKey(ValueKey(tray ? 'close-behavior-tray' : 'close-behavior-exit')));
  await tester.pumpAndSettle();
}

(Rect, int) _inkBounds(Uint8List rgba, int imageWidth, Rect area) {
  final left = area.left.ceil(), right = area.right.floor();
  final top = area.top.ceil(), bottom = area.bottom.floor();
  final background = (top * imageWidth + left) * 4;
  var minX = right, maxX = left, minY = bottom, maxY = top;
  var inkPixels = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final pixel = (y * imageWidth + x) * 4;
      final difference = (rgba[pixel] - rgba[background]).abs() +
          (rgba[pixel + 1] - rgba[background + 1]).abs() +
          (rgba[pixel + 2] - rgba[background + 2]).abs();
      if (difference > 100) {
        inkPixels++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  expect(minX, lessThan(maxX), reason: 'rendered glyph must contain real ink');
  expect(minY, lessThan(maxY), reason: 'rendered glyph must contain real ink');
  return (
    Rect.fromLTRB(minX.toDouble(), minY.toDouble(), maxX.toDouble() + 1,
        maxY.toDouble() + 1),
    inkPixels,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets('existing close preference moves without playback or native work',
      (tester) async {
    final rig = DesktopTestRig();
    addTearDown(rig.dispose);
    rig.preferences.value = rig.preferences.value.copyWith(
        springLyrics: false, playbackRate: 1.5, desktopLyricVertical: true);
    var saves = 0;
    await tester.pumpWidget(_host(CloseBehaviorSettings(
        preferences: rig.preferences, persist: () async => saves++)));
    expect(PlayService.isInitialized, isFalse);
    expect(rig.preferences.value.closeToTray, isFalse);
    expect(find.text(ui('直接退出程序')), findsOneWidget);
    await _choose(tester, true);
    final selected = rig.preferences.value;
    expect(selected.closeToTray, isTrue);
    expect(selected.taskbarControls, isTrue);
    expect(selected.springLyrics, isFalse);
    expect(selected.desktopLyricVertical, isTrue);
    expect(selected.playbackRate, 1.5);
    expect(saves, 1);
    expect(rig.native.calls, isEmpty);
    expect(rig.playback.starts, 0);
    expect(PlayService.isInitialized, isFalse);
    await _choose(tester, true);
    expect(saves, 1,
        reason: 'selecting the current action does not write again');
    await _choose(tester, false);
    expect(rig.preferences.value.closeToTray, isFalse);
    expect(saves, 2);
  });

  testWidgets('external restored preference updates the actual selected text',
      (tester) async {
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    addTearDown(preferences.dispose);
    await tester.pumpWidget(_host(
        CloseBehaviorSettings(preferences: preferences, persist: () async {})));
    preferences.value = preferences.value.copyWith(closeToTray: true);
    await tester.pumpAndSettle();
    expect(find.text(ui('缩小到任务栏托盘')), findsOneWidget);
    expect(find.text(ui('直接退出程序')), findsNothing);
    preferences.value = const PlayerExperiencePreferences();
    await tester.pumpAndSettle();
    expect(find.text(ui('直接退出程序')), findsOneWidget);
  });

  testWidgets(
      'expand button supports keyboard choice and native menu dismissal',
      (tester) async {
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    addTearDown(preferences.dispose);
    var saves = 0;
    await tester.pumpWidget(_host(CloseBehaviorSettings(
        preferences: preferences, persist: () async => saves++)));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('close-behavior-tray')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(preferences.value.closeToTray, isTrue);
    expect(saves, 1);
    expect(find.byKey(const ValueKey('close-behavior-tray')), findsNothing);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save failure keeps the choice and shared retry saves it',
      (tester) async {
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    addTearDown(preferences.dispose);
    var saves = 0;
    await tester.pumpWidget(_host(SingleChildScrollView(
        child: CloseBehaviorSettings(
            preferences: preferences,
            persist: () async {
              if (++saves == 1) throw StateError('synthetic I/O failure');
            }))));
    await _choose(tester, true);
    expect(preferences.value.closeToTray, isTrue);
    expect(find.text(ui('设置保存失败，本次会话仍保留当前选择')), findsOneWidget);
    await tester.tap(find.text(ui('重试保存')));
    await tester.pumpAndSettle();
    expect(saves, 2);
    expect(find.text(ui('设置保存失败，本次会话仍保留当前选择')), findsNothing);
    expect(find.text(ui('缩小到任务栏托盘')), findsOneWidget);
  });

  testWidgets('older save failure cannot replace a newer successful action',
      (tester) async {
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    final oldSave = Completer<void>();
    addTearDown(preferences.dispose);
    var saves = 0;
    await tester.pumpWidget(_host(CloseBehaviorSettings(
        preferences: preferences,
        persist: () {
          return ++saves == 1 ? oldSave.future : Future<void>.value();
        })));
    await _choose(tester, true);
    preferences.value = preferences.value.copyWith(playbackRate: 1.5);
    await _choose(tester, false);
    oldSave.completeError(StateError('late synthetic I/O failure'));
    await tester.pumpAndSettle();
    expect(preferences.value.closeToTray, isFalse);
    expect(preferences.value.playbackRate, 1.5);
    expect(find.text(ui('设置保存失败，本次会话仍保留当前选择')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    testWidgets('${language.name} old close search reaches the real backup row',
        (tester) async {
      uiLanguage.value = language;
      for (final alias in [
        '退出后操作',
        '关闭窗口后在后台继续播放',
        '关闭窗口',
        '直接退出程序',
        '缩小到任务栏托盘',
        'Alt+F4',
      ]) {
        final destinations = searchSettings(translateUi(alias, language));
        expect(
            destinations.map((entry) => entry.id), contains('close-behavior'));
        expect(destinations.map((entry) => entry.id),
            isNot(contains('integration')));
      }
      final destination = searchSettings(translateUi('退出后操作', language)).single;
      final route = Uri.parse(destination.location);
      expect(route.queryParameters['section'], 'backup');
      await tester.pumpWidget(_host(SettingsPage(
          initialSection: route.queryParameters['section'],
          initialSetting: route.queryParameters['setting'])));
      await tester.pumpAndSettle();
      final target = find.byKey(const ValueKey('setting-close-behavior'));
      expect(target, findsOneWidget);
      final sections =
          tester.widget<GroupedSettings>(find.byType(GroupedSettings)).sections;
      final backup = sections.singleWhere((section) => section.id == 'backup');
      expect(backup.children.whereType<CloseBehaviorSettings>(), hasLength(1));
      expect(backup.children.whereType<CacheBackupSettings>(), hasLength(1));
      expect(tester.getTopLeft(target).dy, inInclusiveRange(0, 320));
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  const renderDirectory = String.fromEnvironment('DAN_CLOSE_BEHAVIOR_RENDER');
  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets('${language.name} actual close menu narrow=$narrow',
          (tester) async {
        final previousShadows = debugDisableShadows;
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = previousShadows);
        uiLanguage.value = language;
        tester.view.physicalSize =
            Size(narrow ? 360 : 1000, narrow ? 800 : 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final original = AppSettings.instance.experience.value;
        AppSettings.instance.experience.value =
            original.copyWith(closeToTray: false);
        addTearDown(() => AppSettings.instance.experience.value = original);
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: boundaryKey,
            child: _host(
                const SettingsPage(
                    initialSection: 'backup', initialSetting: 'close-behavior'),
                scale: narrow ? 2 : 1,
                dark: narrow)));
        await tester.pumpAndSettle();
        final choice = find.byKey(const ValueKey('close-to-tray-setting'));
        expect(choice, findsOneWidget);
        expect(tester.takeException(), isNull);
        Future<void> render(String stage) async {
          final menu = stage.endsWith('menu');
          if (renderDirectory.isEmpty && !menu) return;
          final glyphAreas = menu
              ? [
                  for (final entry in [
                    ('close-behavior-exit', Icons.exit_to_app, '直接退出程序'),
                    ('close-behavior-tray', Icons.exit_to_app, '缩小到任务栏托盘'),
                  ])
                    (
                      entry.$1,
                      tester.getRect(find.descendant(
                          of: find.byKey(ValueKey(entry.$1)),
                          matching: find.byIcon(entry.$2))),
                      tester.getRect(find.descendant(
                          of: find.byKey(ValueKey(entry.$1)),
                          matching: find.text(ui(entry.$3)))),
                    ),
                ]
              : <(String, Rect, Rect)>[];
          await tester.runAsync(() async {
            final boundary = boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await boundary.toImage();
            try {
              final metrics = <Map<String, Object>>[];
              if (menu) {
                final rgba = (await image.toByteData(
                        format: raster.ImageByteFormat.rawRgba))!
                    .buffer
                    .asUint8List();
                for (final area in glyphAreas) {
                  final iconMeasurement =
                      _inkBounds(rgba, image.width, area.$2);
                  final iconInk = iconMeasurement.$1;
                  final textInk = _inkBounds(rgba, image.width, area.$3).$1;
                  final frameOffset = iconInk.center.dy - area.$2.center.dy;
                  final textOffset = iconInk.center.dy - textInk.center.dy;
                  expect(frameOffset.abs(), lessThanOrEqualTo(1.5),
                      reason: '${area.$1} actual icon ink must be centered');
                  expect(textOffset.abs(), lessThanOrEqualTo(4),
                      reason:
                          '${area.$1} actual ink aligns with multiline text');
                  metrics.add({
                    'item': area.$1,
                    'iconInkCenterY': iconInk.center.dy,
                    'iconFrameCenterY': area.$2.center.dy,
                    'textInkCenterY': textInk.center.dy,
                    'iconFrameOffset': frameOffset,
                    'textInkOffset': textOffset,
                    'inkWidth': iconInk.width,
                    'inkHeight': iconInk.height,
                    'inkPixels': iconMeasurement.$2,
                  });
                }
                for (final dimension in ['inkWidth', 'inkHeight']) {
                  final difference = ((metrics.first[dimension] as double) -
                          (metrics.last[dimension] as double))
                      .abs();
                  expect(difference, lessThanOrEqualTo(1),
                      reason: 'paired window arrows match actual $dimension');
                }
                final areaRatio = (metrics.first['inkPixels'] as int) /
                    (metrics.last['inkPixels'] as int);
                expect(areaRatio, inInclusiveRange(.9, 1.1),
                    reason: 'paired window arrows match visible ink area');
              }
              if (renderDirectory.isEmpty) return;
              final bytes =
                  (await image.toByteData(format: raster.ImageByteFormat.png))!
                      .buffer
                      .asUint8List();
              final file = File(
                  '$renderDirectory/close-${language.name}-${narrow ? 'narrow' : 'wide'}-$stage.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes, flush: true);
              if (menu) {
                await File('${file.path}.ink.json').writeAsString(
                    const JsonEncoder.withIndent('  ').convert(metrics),
                    flush: true);
              }
            } finally {
              image.dispose();
            }
          });
        }

        await render('selected');
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(find.text(ui('直接退出程序')), findsNWidgets(2));
        expect(find.text(ui('缩小到任务栏托盘')), findsOneWidget);
        final exit = tester.widget<MenuItemButton>(
            find.byKey(const ValueKey('close-behavior-exit')));
        final tray = tester.widget<MenuItemButton>(
            find.byKey(const ValueKey('close-behavior-tray')));
        expect(
            find.descendant(
                of: find.byWidget(exit.trailingIcon!),
                matching: find.byIcon(Icons.check)),
            findsOneWidget);
        expect(
            find.descendant(
                of: find.byWidget(tray.trailingIcon!),
                matching: find.byIcon(Icons.check)),
            findsNothing);
        final menuOption = find.text(ui('缩小到任务栏托盘'));
        expect(tester.getRect(menuOption).width,
            lessThanOrEqualTo(tester.view.physicalSize.width));
        await render('menu');
        // Dismiss without choosing: render tests do not persist any preference.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(AppSettings.instance.experience.value.closeToTray, isFalse);
        AppSettings.instance.experience.value =
            AppSettings.instance.experience.value.copyWith(closeToTray: true);
        await tester.pumpAndSettle();
        await render('tray-selected');
        await tester.tap(choice);
        await tester.pumpAndSettle();
        final selectedTray = tester.widget<MenuItemButton>(
            find.byKey(const ValueKey('close-behavior-tray')));
        expect(
            find.descendant(
                of: find.byWidget(selectedTray.trailingIcon!),
                matching: find.byIcon(Icons.check)),
            findsOneWidget);
        await render('tray-menu');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(AppSettings.instance.experience.value.closeToTray, isTrue);
        expect(PlayService.isInitialized, isFalse);
        expect(tester.takeException(), isNull);
        debugDisableShadows = previousShadows;
      });
    }
  }
}
