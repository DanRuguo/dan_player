import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/online/online_source_preferences.dart';
import 'package:dan_player/page/settings_page/music_source_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child,
        {double scale = 1, Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(
          platform: TargetPlatform.windows,
          useMaterial3: true,
          visualDensity: VisualDensity.compact,
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue, brightness: brightness)),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale), disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
          body: ListView(padding: const EdgeInsets.all(16), children: [child])),
    );

Finder _source(String id) => find.byKey(ValueKey('online-source-$id'));

bool _focusIsInside(Finder finder) {
  final target = finder.evaluate().single;
  final context = FocusManager.instance.primaryFocus?.context;
  var containsFocus = identical(context, target);
  context?.visitAncestorElements((element) {
    if (identical(element, target)) {
      containsFocus = true;
      return false;
    }
    return true;
  });
  return containsFocus;
}

Future<void> _toggle(WidgetTester tester, String id) async {
  final control =
      find.descendant(of: _source(id), matching: find.byType(Switch));
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
}

void main() {
  late bool previousLrclib;
  setUp(() {
    previousLrclib = AppSettings.instance.lrclibEnabled.value;
    AppSettings.instance.lrclibEnabled.value = false;
  });
  tearDown(() => AppSettings.instance.lrclibEnabled.value = previousLrclib);
  testWidgets(
      'initial view is descriptive only and never probes a network or saves',
      (tester) async {
    final preferences = ValueNotifier(const OnlineSourcePreferences());
    addTearDown(preferences.dispose);
    var saves = 0;
    var clients = 0;
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(_host(MusicSourceSettings(
        preferences: preferences,
        persist: () async => saves++,
      )));
      await tester.pumpAndSettle();
    }, createHttpClient: (_) {
      clients++;
      throw StateError('Unexpected HTTP request');
    });
    expect(clients, 0);
    expect(saves, 0);
    expect(tester.widget<SwitchListTile>(_source('qq')).value, isTrue);
    expect(tester.widget<SwitchListTile>(_source('netease')).value, isTrue);
    expect(find.text('下载按接口实际返回执行，需登录或受限时会提示。'), findsNWidgets(2));
    expect(find.textContaining('接口域名（只读）'), findsNWidgets(3));
    expect(find.textContaining('只读公开评论'), findsNWidgets(2));
    expect(find.byType(Chip), findsNothing);
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets(
      'each switch persists independently and explicit all-off remains allowed',
      (tester) async {
    final preferences = ValueNotifier(const OnlineSourcePreferences());
    addTearDown(preferences.dispose);
    final snapshots = <List<String>>[];
    await tester.pumpWidget(_host(MusicSourceSettings(
      preferences: preferences,
      persist: () async => snapshots.add(preferences.value.toJson()),
    )));
    await tester.pumpAndSettle();
    await _toggle(tester, 'qq');
    expect(preferences.value.toJson(), ['netease']);
    await _toggle(tester, 'netease');
    expect(preferences.value.isEmpty, isTrue);
    expect(find.text('此类来源均已停用'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(_source('qq')).onChanged, isNotNull);
    expect(
        tester.widget<SwitchListTile>(_source('netease')).onChanged, isNotNull);
    await _toggle(tester, 'qq');
    expect(preferences.value.toJson(), ['qq']);
    expect(snapshots, [
      ['netease'],
      <String>[],
      ['qq']
    ]);
    expect(find.textContaining('不会删除收藏、歌单或队列'), findsOneWidget);
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets(
      'external settings reload updates switches without triggering a save',
      (tester) async {
    final preferences = ValueNotifier(const OnlineSourcePreferences());
    addTearDown(preferences.dispose);
    var saves = 0;
    await tester.pumpWidget(_host(MusicSourceSettings(
      preferences: preferences,
      persist: () async => saves++,
    )));
    preferences.value =
        const OnlineSourcePreferences(qqEnabled: false, neteaseEnabled: false);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(_source('qq')).value, isFalse);
    expect(tester.widget<SwitchListTile>(_source('netease')).value, isFalse);
    expect(saves, 0);
  });

  testWidgets('keyboard Space changes the focused switch and saves once',
      (tester) async {
    final preferences = ValueNotifier(const OnlineSourcePreferences());
    addTearDown(preferences.dispose);
    var saves = 0;
    await tester.pumpWidget(_host(MusicSourceSettings(
      preferences: preferences,
      persist: () async => saves++,
    )));
    await tester.pumpAndSettle();
    // SwitchListTile deliberately excludes its decorative Switch from focus;
    // the full ListTile is the keyboard target. Exercise actual Tab traversal
    // instead of requesting an ancestor of that excluded inner control.
    for (var step = 0; step < 4 && !_focusIsInside(_source('qq')); step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(_focusIsInside(_source('qq')), isTrue,
        reason: 'The QQ source switch must be reachable by keyboard Tab.');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(preferences.value.qqEnabled, isFalse);
    expect(saves, 1);
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 440.0]) {
      testWidgets(
          '$brightness at ${width}px / 200% keeps controls and full capabilities reachable',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 507);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final preferences = ValueNotifier(const OnlineSourcePreferences());
        addTearDown(preferences.dispose);
        await tester.pumpWidget(_host(
            MusicSourceSettings(preferences: preferences, persist: () async {}),
            scale: 2,
            brightness: brightness));
        await tester.pumpAndSettle();
        for (final id in ['qq', 'netease']) {
          await tester.ensureVisible(_source(id));
          await tester.pumpAndSettle();
          expect(tester.getSize(_source(id)).height, greaterThanOrEqualTo(48));
          final texts =
              find.descendant(of: _source(id), matching: find.byType(Text));
          for (final element in texts.evaluate()) {
            expect((element.widget as Text).maxLines, isNull,
                reason:
                    'Source labels must wrap instead of hiding enabled state.');
          }
          await _toggle(tester, id);
          expect(tester.takeException(), isNull);
        }
        final status = find.byKey(const ValueKey('music-source-status'));
        await tester.ensureVisible(status);
        await tester.pumpAndSettle();
        expect(find.text('此类来源均已停用'), findsOneWidget);
        expect(preferences.value.isEmpty, isTrue);
      });
    }
  }

  testWidgets(
      'a persistence failure is visible while retaining the current session choice',
      (tester) async {
    final preferences = ValueNotifier(const OnlineSourcePreferences());
    addTearDown(preferences.dispose);
    await tester.pumpWidget(_host(MusicSourceSettings(
        preferences: preferences,
        persist: () async => throw StateError('Synthetic write failure'))));
    await _toggle(tester, 'qq');
    expect(find.text('保存歌源设置失败；当前选择仍对本次会话生效。'), findsOneWidget);
    expect(preferences.value.qqEnabled, isFalse);
  });

  testWidgets(
      'a late failed save cannot replace the newest choice or report stale errors',
      (tester) async {
    final preferences = ValueNotifier(const OnlineSourcePreferences());
    addTearDown(preferences.dispose);
    final first = Completer<void>();
    var saves = 0;
    await tester.pumpWidget(_host(MusicSourceSettings(
        preferences: preferences,
        persist: () {
          saves++;
          return saves == 1 ? first.future : Future.value();
        })));
    await _toggle(tester, 'qq');
    await _toggle(tester, 'netease');
    first.completeError(StateError('Stale save'));
    await tester.pumpAndSettle();
    expect(preferences.value.isEmpty, isTrue);
    expect(find.textContaining('保存歌源设置失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing during save has no late state update', (tester) async {
    final preferences = ValueNotifier(const OnlineSourcePreferences());
    addTearDown(preferences.dispose);
    final save = Completer<void>();
    await tester.pumpWidget(_host(MusicSourceSettings(
        preferences: preferences, persist: () => save.future)));
    await _toggle(tester, 'qq');
    await tester.pumpWidget(const SizedBox.shrink());
    save.completeError(StateError('Late save'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('LRCLIB is a separate read-only lyric source with its own switch',
      (tester) async {
    final preferences = ValueNotifier(const OnlineSourcePreferences());
    final lrclib = ValueNotifier(true);
    addTearDown(preferences.dispose);
    addTearDown(lrclib.dispose);
    var saves = 0;
    await tester.pumpWidget(_host(MusicSourceSettings(
      preferences: preferences,
      lrclibEnabled: lrclib,
      persist: () async => saves++,
    )));
    expect(find.text('LRCLIB'), findsOneWidget);
    expect(find.text('参与歌词匹配'), findsOneWidget);
    await _toggle(tester, 'lrclib');
    expect(lrclib.value, isFalse);
    expect(preferences.value.qqEnabled, isTrue);
    expect(preferences.value.neteaseEnabled, isTrue);
    expect(saves, 1);
    expect(find.text('不参与歌词匹配'), findsOneWidget);
  });

  for (final language in UiLanguage.values) {
    testWidgets('${language.code} source groups fit 320px at 200%',
        (tester) async {
      final previous = uiLanguage.value;
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = previous);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 560);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final preferences = ValueNotifier(const OnlineSourcePreferences());
      final lrclib = ValueNotifier(true);
      addTearDown(preferences.dispose);
      addTearDown(lrclib.dispose);
      await tester.pumpWidget(_host(
          MusicSourceSettings(
            preferences: preferences,
            lrclibEnabled: lrclib,
            persist: () async {},
          ),
          scale: 2));
      for (final id in ['qq', 'netease', 'lrclib']) {
        await tester.ensureVisible(_source(id));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.byType(Chip), findsNothing);
    });
  }
}
