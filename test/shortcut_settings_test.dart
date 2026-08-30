import 'package:dan_player/app_settings.dart';
import 'package:dan_player/page/settings_page/shortcut_settings.dart';
import 'package:dan_player/player_shortcut_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _sendChord(
  WidgetTester tester,
  LogicalKeyboardKey trigger, {
  bool control = false,
  bool alt = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyDownEvent(trigger);
  await tester.sendKeyUpEvent(trigger);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows, useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(padding: const EdgeInsets.all(16), children: [child]),
      ),
    );

void main() {
  late ShortcutPreferences previous;

  setUp(() {
    previous = AppSettings.instance.shortcuts.value;
    AppSettings.instance.shortcuts.value = ShortcutPreferences.defaults();
  });

  tearDown(() {
    AppSettings.instance.shortcuts.value = previous;
  });

  testWidgets('recorder captures a complete chord and returns it on save',
      (tester) async {
    ShortcutChord? result;
    await tester.pumpWidget(_host(Builder(
      builder: (context) => FilledButton(
        onPressed: () async {
          result = await showDialog<ShortcutChord>(
            context: context,
            builder: (_) => ShortcutRecorderDialog(
              definition: playerShortcutDefinitions.first,
              preferences: ShortcutPreferences.defaults(),
            ),
          );
        },
        child: const Text('Open'),
      ),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.text('请按下新的组合键'), findsOneWidget);
    await _sendChord(
      tester,
      LogicalKeyboardKey.keyP,
      control: true,
      alt: true,
    );
    expect(find.text('Ctrl + Alt + P'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('save-shortcut-recording')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('save-shortcut-recording')));
    await tester.pumpAndSettle();
    expect(result?.label, 'Ctrl + Alt + P');
  });

  testWidgets('recorder blocks a conflicting chord', (tester) async {
    await tester.pumpWidget(_host(Builder(
      builder: (context) => FilledButton(
        onPressed: () async {
          await showDialog<ShortcutChord>(
            context: context,
            builder: (_) => ShortcutRecorderDialog(
              definition: playerShortcutDefinitions.first,
              preferences: ShortcutPreferences.defaults(),
            ),
          );
        },
        child: const Text('Open'),
      ),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await _sendChord(
      tester,
      LogicalKeyboardKey.arrowRight,
      control: true,
    );
    expect(find.textContaining('与“下一首”冲突'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('save-shortcut-recording')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('cancel leaves the live preferences unchanged', (tester) async {
    final before = AppSettings.instance.shortcuts.value;
    var saves = 0;
    await tester.pumpWidget(_host(ShortcutSettings(
      persist: () async {
        saves++;
      },
    )));
    await tester.tap(
      find.byKey(const ValueKey('shortcut-togglePlayback')),
    );
    await tester.pumpAndSettle();
    await _sendChord(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.tap(find.byKey(const ValueKey('cancel-shortcut-recording')));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.shortcuts.value, same(before));
    expect(saves, 0);
    expect(find.text('Ctrl + P'), findsNothing);
  });

  testWidgets('save applies once and restore default also persists once',
      (tester) async {
    var saves = 0;
    await tester.pumpWidget(_host(ShortcutSettings(
      persist: () async {
        saves++;
      },
    )));
    await tester.tap(
      find.byKey(const ValueKey('shortcut-togglePlayback')),
    );
    await tester.pumpAndSettle();
    await _sendChord(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.tap(find.byKey(const ValueKey('save-shortcut-recording')));
    await tester.pumpAndSettle();
    expect(
      AppSettings.instance.shortcuts.value
          .chordFor(PlayerCommand.togglePlayback)
          .label,
      'Ctrl + P',
    );
    expect(saves, 1);

    await tester.tap(find.byKey(const ValueKey('restore-default-shortcuts')));
    await tester.pump();
    expect(
      AppSettings.instance.shortcuts.value,
      ShortcutPreferences.defaults(),
    );
    expect(saves, 2);
  });

  testWidgets('failed persistence restores the previous binding',
      (tester) async {
    final before = AppSettings.instance.shortcuts.value;
    await tester.pumpWidget(_host(ShortcutSettings(
      persist: () async => throw StateError('read-only fixture'),
    )));
    await tester.tap(
      find.byKey(const ValueKey('shortcut-togglePlayback')),
    );
    await tester.pumpAndSettle();
    await _sendChord(tester, LogicalKeyboardKey.keyP, control: true);
    await tester.tap(find.byKey(const ValueKey('save-shortcut-recording')));
    await tester.pump();
    await tester.pump();
    expect(AppSettings.instance.shortcuts.value, same(before));
    expect(find.byKey(const ValueKey('shortcut-save-error')), findsOneWidget);
    expect(find.text('快捷键保存失败，已恢复原设置'), findsOneWidget);
  });

  testWidgets('shortcut rows fit a narrow view at 200 percent text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(
        ShortcutSettings(
          persist: () async {},
        ),
        scale: 2));
    expect(tester.takeException(), isNull);
    final first = find.byKey(const ValueKey('shortcut-togglePlayback'));
    expect(tester.getSize(first).height, greaterThanOrEqualTo(44));
  });
}
