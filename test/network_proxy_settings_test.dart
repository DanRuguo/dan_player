import 'dart:async';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/online/app_network_proxy.dart';
import 'package:dan_player/online/network_proxy_preferences.dart';
import 'package:dan_player/page/settings_page/network_proxy_settings.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      home: UiLanguageScope(
          child: Scaffold(
              body: ListView(
                  padding: const EdgeInsets.all(16), children: [child]))),
    );

Future<void> _mode(WidgetTester tester, NetworkProxyMode value) async {
  tester
      .widget<AppSegmentedControl<NetworkProxyMode>>(
          find.byKey(const ValueKey('network-proxy-mode')))
      .onChanged!(value);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets(
      'draft can probe a proxy before saving without changing live routing',
      (tester) async {
    final preferences = ValueNotifier(const NetworkProxyPreferences());
    addTearDown(preferences.dispose);
    final probes = <NetworkProxyPreferences>[];
    var saves = 0;
    await tester.pumpWidget(_host(NetworkProxySettings(
      preferences: preferences,
      persist: () async => saves++,
      probe: (candidate) async {
        probes.add(candidate);
        return const NetworkProxyProbeResult(
            reachable: true,
            elapsed: Duration(milliseconds: 23),
            statusCode: 200);
      },
    )));
    expect(probes, isEmpty);
    expect(saves, 0);
    expect(preferences.value.mode, NetworkProxyMode.system);

    await _mode(tester, NetworkProxyMode.custom);
    await tester.enterText(
        find.byKey(const ValueKey('network-proxy-address')), '127.0.0.1');
    await tester.enterText(
        find.byKey(const ValueKey('network-proxy-port')), '7890');
    await _tap(tester, 'network-proxy-test');
    await tester.pump();
    expect(probes, hasLength(1));
    expect(probes.single.mode, NetworkProxyMode.custom);
    expect(probes.single.customProxyUrl, 'http://127.0.0.1:7890');
    expect(preferences.value.mode, NetworkProxyMode.system);
    expect(saves, 0);
    expect(find.textContaining('GitHub 连接成功'), findsOneWidget);

    await tester.pumpAndSettle();
    await _tap(tester, 'network-proxy-save');
    await tester.pump();
    expect(preferences.value.customProxyUrl, 'http://127.0.0.1:7890');
    expect(saves, 1);
  });

  testWidgets('invalid custom address cannot be tested or applied',
      (tester) async {
    final preferences = ValueNotifier(const NetworkProxyPreferences());
    addTearDown(preferences.dispose);
    var probes = 0, saves = 0;
    await tester.pumpWidget(_host(NetworkProxySettings(
      preferences: preferences,
      persist: () async => saves++,
      probe: (_) async {
        probes++;
        throw StateError('Must not probe');
      },
    )));
    await _mode(tester, NetworkProxyMode.custom);
    await tester.enterText(find.byKey(const ValueKey('network-proxy-address')),
        'http://127.0.0.1:7890/secret');
    await _tap(tester, 'network-proxy-test');
    expect(find.textContaining('请输入有效的 HTTP 代理地址'), findsOneWidget);
    await tester.pumpAndSettle();
    await _tap(tester, 'network-proxy-save');
    expect(probes, 0);
    expect(saves, 0);
    expect(preferences.value.mode, NetworkProxyMode.system);
  });

  testWidgets('failed save keeps the selected proxy ready for retry',
      (tester) async {
    final preferences = ValueNotifier(const NetworkProxyPreferences());
    addTearDown(preferences.dispose);
    var attempts = 0;
    await tester.pumpWidget(_host(NetworkProxySettings(
      preferences: preferences,
      persist: () async {
        if (++attempts == 1) throw StateError('superseded');
      },
    )));
    await _mode(tester, NetworkProxyMode.direct);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('network-proxy-save')), findsNothing);
    expect(preferences.value.mode, NetworkProxyMode.direct);
    expect(find.textContaining('保存失败；请重试'), findsOneWidget);
    await _tap(tester, 'network-proxy-retry');
    await tester.pump();
    expect(attempts, 2);
    expect(find.textContaining('已应用并保存'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('network-proxy-retry')), findsNothing);
  });

  testWidgets('system and direct apply immediately and hide save after motion',
      (tester) async {
    final preferences = ValueNotifier(const NetworkProxyPreferences());
    addTearDown(preferences.dispose);
    final persisted = <NetworkProxyMode>[];
    await tester.pumpWidget(_host(NetworkProxySettings(
      preferences: preferences,
      persist: () async => persisted.add(preferences.value.mode),
    )));
    expect(find.byKey(const ValueKey('network-proxy-save')), findsNothing);
    await _mode(tester, NetworkProxyMode.direct);
    expect(preferences.value.mode, NetworkProxyMode.direct);
    await tester.pumpAndSettle();
    expect(persisted, [NetworkProxyMode.direct]);
    expect(find.byKey(const ValueKey('network-proxy-save')), findsNothing);
    expect(find.byKey(const ValueKey('network-proxy-retry')), findsNothing);
    await _mode(tester, NetworkProxyMode.system);
    expect(preferences.value.mode, NetworkProxyMode.system);
    await tester.pumpAndSettle();
    expect(persisted, [NetworkProxyMode.direct, NetworkProxyMode.system]);
    expect(find.byKey(const ValueKey('network-proxy-save')), findsNothing);
    expect(find.byKey(const ValueKey('network-proxy-test')), findsOneWidget);
  });

  testWidgets('rapid choices serialize writes and persist the latest selection',
      (tester) async {
    final preferences = ValueNotifier(const NetworkProxyPreferences());
    addTearDown(preferences.dispose);
    final first = Completer<void>();
    final saves = <NetworkProxyMode>[];
    await tester.pumpWidget(_host(NetworkProxySettings(
      preferences: preferences,
      persist: () {
        saves.add(preferences.value.mode);
        return saves.length == 1 ? first.future : Future<void>.value();
      },
    )));
    await _mode(tester, NetworkProxyMode.direct);
    expect(saves, [NetworkProxyMode.direct]);
    await _mode(tester, NetworkProxyMode.system);
    expect(preferences.value.mode, NetworkProxyMode.system);
    expect(saves, [NetworkProxyMode.direct]);
    first.complete();
    await tester.pumpAndSettle();
    expect(saves, [NetworkProxyMode.direct, NetworkProxyMode.system]);
    expect(find.textContaining('已应用并保存'), findsOneWidget);
    expect(find.byKey(const ValueKey('network-proxy-retry')), findsNothing);
  });

  testWidgets('an older failed write cannot replace the latest choice',
      (tester) async {
    final preferences = ValueNotifier(const NetworkProxyPreferences());
    addTearDown(preferences.dispose);
    final first = Completer<void>();
    final saves = <NetworkProxyMode>[];
    await tester.pumpWidget(_host(NetworkProxySettings(
      preferences: preferences,
      persist: () {
        saves.add(preferences.value.mode);
        return saves.length == 1 ? first.future : Future<void>.value();
      },
    )));
    await _mode(tester, NetworkProxyMode.direct);
    await _mode(tester, NetworkProxyMode.system);
    first.completeError(StateError('old write failed'));
    await tester.pumpAndSettle();
    expect(saves, [NetworkProxyMode.direct, NetworkProxyMode.system]);
    expect(preferences.value.mode, NetworkProxyMode.system);
    expect(find.byKey(const ValueKey('network-proxy-retry')), findsNothing);
    expect(find.textContaining('保存失败'), findsNothing);
  });

  testWidgets(
      'custom draft survives immediate mode changes and stays unapplied',
      (tester) async {
    final preferences = ValueNotifier(const NetworkProxyPreferences());
    addTearDown(preferences.dispose);
    await tester.pumpWidget(_host(NetworkProxySettings(
      preferences: preferences,
      persist: () async {},
    )));
    await _mode(tester, NetworkProxyMode.custom);
    await tester.enterText(
        find.byKey(const ValueKey('network-proxy-address')), '127.0.0.1');
    await tester.enterText(
        find.byKey(const ValueKey('network-proxy-port')), '7890');
    await _mode(tester, NetworkProxyMode.direct);
    await tester.pumpAndSettle();
    expect(preferences.value.mode, NetworkProxyMode.direct);
    expect(preferences.value.customProxyUrl, isNull);
    await _mode(tester, NetworkProxyMode.custom);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('network-proxy-save')), findsOneWidget);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('network-proxy-address')))
            .controller!
            .text,
        '127.0.0.1');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('network-proxy-port')))
            .controller!
            .text,
        '7890');
    expect(preferences.value.mode, NetworkProxyMode.direct);
  });

  testWidgets('save button disappearance obeys layout motion settings',
      (tester) async {
    final preferences = ValueNotifier(const NetworkProxyPreferences(
        mode: NetworkProxyMode.custom,
        customProxyUrl: 'http://127.0.0.1:7890'));
    addTearDown(preferences.dispose);
    await tester.pumpWidget(MaterialApp(
      home: MotionPreferencesScope(
        preferences: const MotionPreferences(disabled: {MotionKind.layout}),
        child: UiLanguageScope(
          child: Scaffold(
            body: NetworkProxySettings(
                preferences: preferences, persist: () async {}),
          ),
        ),
      ),
    ));
    expect(
        tester
            .widget<AnimatedSwitcher>(
                find.byKey(const ValueKey('network-proxy-save-transition')))
            .duration,
        Duration.zero);
    await _mode(tester, NetworkProxyMode.direct);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('network-proxy-save')), findsNothing);
  });

  testWidgets('system reduced motion removes the layout animation',
      (tester) async {
    final preferences = ValueNotifier(const NetworkProxyPreferences(
        mode: NetworkProxyMode.custom,
        customProxyUrl: 'http://127.0.0.1:7890'));
    addTearDown(preferences.dispose);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: UiLanguageScope(
          child: Scaffold(
            body: NetworkProxySettings(
                preferences: preferences, persist: () async {}),
          ),
        ),
      ),
    ));
    expect(
        tester
            .widget<AnimatedSwitcher>(
                find.byKey(const ValueKey('network-proxy-save-transition')))
            .duration,
        Duration.zero);
  });

  testWidgets('editing while a probe is pending discards its late result',
      (tester) async {
    final preferences = ValueNotifier(const NetworkProxyPreferences());
    addTearDown(preferences.dispose);
    final pending = Completer<NetworkProxyProbeResult>();
    await tester.pumpWidget(_host(NetworkProxySettings(
      preferences: preferences,
      persist: () async {},
      probe: (_) => pending.future,
    )));
    await _tap(tester, 'network-proxy-test');
    await _mode(tester, NetworkProxyMode.direct);
    pending.complete(const NetworkProxyProbeResult(
        reachable: true, elapsed: Duration(milliseconds: 10), statusCode: 200));
    await tester.pump();
    expect(find.textContaining('GitHub 连接成功'), findsNothing);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('network-proxy-test')))
            .onPressed,
        isNotNull);
  });

  testWidgets('PAC limitation is explained instead of reported as timeout',
      (tester) async {
    final preferences = ValueNotifier(const NetworkProxyPreferences());
    addTearDown(preferences.dispose);
    await tester.pumpWidget(_host(NetworkProxySettings(
      preferences: preferences,
      persist: () async {},
      probe: (_) async => const NetworkProxyProbeResult(
          reachable: false,
          elapsed: Duration(milliseconds: 1),
          error: 'system_pac_unsupported'),
    )));
    await _tap(tester, 'network-proxy-test');
    await tester.pump();
    expect(find.textContaining('自动代理脚本暂不能用于应用内 HTTP 请求'), findsOneWidget);
    expect(find.textContaining('超时'), findsNothing);
  });

  testWidgets('GitHub API rate limit is distinguished from lost connectivity',
      (tester) async {
    final preferences = ValueNotifier(const NetworkProxyPreferences());
    addTearDown(preferences.dispose);
    await tester.pumpWidget(_host(NetworkProxySettings(
      preferences: preferences,
      persist: () async {},
      probe: (_) async => const NetworkProxyProbeResult(
          reachable: true,
          statusCode: 403,
          elapsed: Duration(milliseconds: 17)),
    )));
    await _tap(tester, 'network-proxy-test');
    await tester.pump();
    expect(find.textContaining('已连接 GitHub，但接口返回 HTTP 403'), findsOneWidget);
    expect(find.textContaining('连接失败'), findsNothing);
  });

  testWidgets('external settings reload refreshes an untouched draft',
      (tester) async {
    final preferences = ValueNotifier(const NetworkProxyPreferences());
    addTearDown(preferences.dispose);
    await tester.pumpWidget(_host(NetworkProxySettings(
      preferences: preferences,
      persist: () async {},
    )));
    preferences.value = const NetworkProxyPreferences(
        mode: NetworkProxyMode.custom, customProxyUrl: 'http://localhost:8080');
    await tester.pump();
    expect(
        tester
            .widget<AppSegmentedControl<NetworkProxyMode>>(
                find.byKey(const ValueKey('network-proxy-mode')))
            .value,
        NetworkProxyMode.custom);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('network-proxy-address')))
            .controller!
            .text,
        'http://localhost:8080');
  });

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

  for (final language in UiLanguage.values) {
    for (final width in [360.0, 840.0]) {
      for (final mode in NetworkProxyMode.values) {
        testWidgets('proxy card renders ${language.name} $mode at $width',
            (tester) async {
          final oldLanguage = uiLanguage.value;
          uiLanguage.value = language;
          addTearDown(() => uiLanguage.value = oldLanguage);
          tester.view.physicalSize = Size(width, 920);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final preferences = ValueNotifier(NetworkProxyPreferences(
              mode: mode, customProxyUrl: 'http://127.0.0.1:7890'));
          addTearDown(preferences.dispose);
          final boundary = GlobalKey();
          await tester.pumpWidget(MaterialApp(
            theme: applyAppControlTheme(ThemeData(
                fontFamily: danEmbeddedFontFamily,
                fontFamilyFallback: danFontFamilyFallback,
                colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.deepOrange,
                    brightness: Brightness.light))),
            home: UiLanguageScope(
              child: Scaffold(
                body: RepaintBoundary(
                  key: boundary,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: NetworkProxySettings(
                          preferences: preferences, persist: () async {}),
                    ),
                  ),
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text(ui('网络代理')), findsOneWidget);
          expect(find.text(ui('测试 GitHub 连接')), findsOneWidget);
          const output = String.fromEnvironment('DAN_PROXY_SETTINGS_RENDER');
          if (output.isNotEmpty) {
            await tester.runAsync(() async {
              final image = await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
              await Directory(output).create(recursive: true);
              await File(
                      '$output/proxy-${language.name}-${mode.name}-${width.toInt()}.png')
                  .writeAsBytes((await image.toByteData(
                          format: drawing.ImageByteFormat.png))!
                      .buffer
                      .asUint8List());
              image.dispose();
            });
          }
        });
      }
    }
  }
}
