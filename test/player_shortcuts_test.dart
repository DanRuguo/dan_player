import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key,
    {bool control = false,
    bool shift = false,
    bool alt = false,
    bool meta = false}) async {
  final modifiers = [
    if (control) LogicalKeyboardKey.controlLeft,
    if (shift) LogicalKeyboardKey.shiftLeft,
    if (alt) LogicalKeyboardKey.altLeft,
    if (meta) LogicalKeyboardKey.metaLeft,
  ];
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  for (final modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump();
}

Future<void> _show(
  WidgetTester tester, {
  required Widget child,
  FutureOr<void> Function(PlayerCommand)? onCommand,
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navigatorKey,
    theme: ThemeData(platform: TargetPlatform.windows),
    builder: (context, child) => PlayerShortcuts(
      onCommand: onCommand,
      child: child!,
    ),
    home: Scaffold(body: child),
  ));
  await tester.pump();
}

void main() {
  late ShortcutPreferences previousPreferences;

  setUp(() {
    previousPreferences = AppSettings.instance.shortcuts.value;
    AppSettings.instance.shortcuts.value = ShortcutPreferences.defaults();
    HotkeysHelper.registerHotKeys();
  });
  tearDown(() async {
    AppSettings.instance.shortcuts.value = previousPreferences;
    await HotkeysHelper.unregisterAll();
  });

  test('eleven unique commands share non-repeating exact activators', () {
    expect(playerShortcuts, hasLength(11));
    expect(playerShortcuts.map((shortcut) => shortcut.command).toSet(),
        PlayerCommand.values.toSet());
    for (final shortcut in playerShortcuts) {
      expect(shortcut.keys, isNotEmpty);
      expect(shortcut.description, isNotEmpty);
      expect(shortcut.activator.includeRepeats, isFalse);
    }
  });

  for (final shortcut in playerShortcuts) {
    testWidgets('${shortcut.keys} dispatches only ${shortcut.command.name}',
        (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final commands = <PlayerCommand>[];
      await _show(tester,
          child: Focus(focusNode: focus, child: const SizedBox.expand()),
          onCommand: commands.add);
      focus.requestFocus();
      await tester.pump();
      await _key(tester, shortcut.activator.trigger,
          control: shortcut.activator.control,
          shift: shortcut.activator.shift,
          alt: shortcut.activator.alt,
          meta: shortcut.activator.meta);
      expect(commands, [shortcut.command]);
      expect(PlayService.isInitialized, isFalse);
    });
  }

  testWidgets('extra modifiers and unlisted chords do not match a shortcut',
      (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final commands = <PlayerCommand>[];
    await _show(tester,
        child: Focus(focusNode: focus, child: const SizedBox.expand()),
        onCommand: commands.add);
    focus.requestFocus();
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.space, control: true);
    await _key(tester, LogicalKeyboardKey.space, shift: true);
    await _key(tester, LogicalKeyboardKey.arrowRight, alt: true);
    await _key(tester, LogicalKeyboardKey.arrowRight,
        control: true, shift: true);
    await _key(tester, LogicalKeyboardKey.keyM, control: true, shift: true);
    await _key(tester, LogicalKeyboardKey.keyM, meta: true);
    await _key(tester, LogicalKeyboardKey.f1, control: true);
    await _key(tester, LogicalKeyboardKey.f11, alt: true);
    await _key(tester, LogicalKeyboardKey.escape, shift: true);
    await _key(tester, LogicalKeyboardKey.keyM);
    expect(commands, isEmpty);
  });

  testWidgets('a saved binding is used immediately without remounting',
      (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final commands = <PlayerCommand>[];
    await _show(
      tester,
      child: Focus(focusNode: focus, child: const SizedBox.expand()),
      onCommand: commands.add,
    );
    focus.requestFocus();
    await tester.pump();

    AppSettings.instance.shortcuts.value =
        AppSettings.instance.shortcuts.value.withBinding(
      PlayerCommand.togglePlayback,
      ShortcutChord(LogicalKeyboardKey.keyP.keyId, control: true),
    );
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.space);
    await _key(tester, LogicalKeyboardKey.keyP, control: true);
    expect(commands, [PlayerCommand.togglePlayback]);
  });

  testWidgets('held keys do not repeatedly skip tracks or toggle mini',
      (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final commands = <PlayerCommand>[];
    await _show(tester,
        child: Focus(focusNode: focus, child: const SizedBox.expand()),
        onCommand: commands.add);
    focus.requestFocus();
    await tester.pump();
    for (final key in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.keyM
    ]) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlRight);
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlRight);
    }
    await tester.pump();
    expect(commands, [PlayerCommand.next, PlayerCommand.toggleMini]);
  });

  testWidgets(
      'ordinary editable text and IME composing text bypass all commands',
      (tester) async {
    final input = TextEditingController(text: 'draft');
    final focus = FocusNode();
    addTearDown(input.dispose);
    addTearDown(focus.dispose);
    final commands = <PlayerCommand>[];
    await _show(tester,
        child: TextField(controller: input, focusNode: focus),
        onCommand: commands.add);
    focus.requestFocus();
    await tester.pump();
    for (final composing in [false, true]) {
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: 'ni',
        selection: const TextSelection.collapsed(offset: 2),
        composing:
            composing ? const TextRange(start: 0, end: 2) : TextRange.empty,
      ));
      await tester.pump();
      for (final shortcut in playerShortcuts) {
        await _key(tester, shortcut.activator.trigger,
            control: shortcut.activator.control);
      }
      expect(commands, isEmpty, reason: 'IME composing=$composing');
    }
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets('a focused button receives Space before the player shortcut',
      (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final commands = <PlayerCommand>[];
    var activations = 0;
    await _show(tester,
        child: ElevatedButton(
          focusNode: focus,
          onPressed: () => activations++,
          child: const Text('Local button'),
        ),
        onCommand: commands.add);
    focus.requestFocus();
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.space);
    expect(activations, 1);
    expect(commands, isEmpty);
  });

  testWidgets('a focused slider receives arrows before global seek commands',
      (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final commands = <PlayerCommand>[];
    var value = 0.5;
    await _show(tester,
        child: StatefulBuilder(
          builder: (context, setState) => Slider(
            focusNode: focus,
            value: value,
            onChanged: (next) => setState(() => value = next),
          ),
        ),
        onCommand: commands.add);
    focus.requestFocus();
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(value, greaterThan(0.5));
    expect(commands, isEmpty);
  });

  for (final withButton in [false, true]) {
    testWidgets(
        'modal dialog (focused button=$withButton) blocks background keys',
        (tester) async {
      final focus = FocusNode();
      final dialogFocus = FocusNode();
      addTearDown(focus.dispose);
      addTearDown(dialogFocus.dispose);
      final commands = <PlayerCommand>[];
      final navigatorKey = GlobalKey<NavigatorState>();
      var dialogActivations = 0;
      await _show(tester,
          navigatorKey: navigatorKey,
          child: Focus(focusNode: focus, child: const Text('Underlying page')),
          onCommand: commands.add);
      focus.requestFocus();
      await tester.pump();
      final dialog = showDialog<void>(
        context: navigatorKey.currentContext!,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Modal confirmation'),
          actions: withButton
              ? [
                  TextButton(
                    autofocus: true,
                    focusNode: dialogFocus,
                    onPressed: () => dialogActivations++,
                    child: const Text('Confirm'),
                  )
                ]
              : null,
        ),
      );
      await tester.pumpAndSettle();
      if (withButton) {
        dialogFocus.requestFocus();
        await tester.pump();
      }
      await _key(tester, LogicalKeyboardKey.space);
      await _key(tester, LogicalKeyboardKey.arrowRight, control: true);
      await _key(tester, LogicalKeyboardKey.keyM, control: true);
      await _key(tester, LogicalKeyboardKey.f11);
      expect(commands, isEmpty);
      expect(dialogActivations, withButton ? 1 : 0);
      expect(find.text('Modal confirmation'), findsOneWidget);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await dialog;
    });
  }

  testWidgets('modal bottom sheet also blocks background playback',
      (tester) async {
    final commands = <PlayerCommand>[];
    final navigatorKey = GlobalKey<NavigatorState>();
    await _show(tester,
        navigatorKey: navigatorKey,
        child: const Text('Underlying page'),
        onCommand: commands.add);
    final sheet = showModalBottomSheet<void>(
      context: navigatorKey.currentContext!,
      builder: (context) =>
          const SizedBox(height: 180, child: Text('Modal sheet')),
    );
    await tester.pumpAndSettle();
    await _key(tester, LogicalKeyboardKey.space);
    await _key(tester, LogicalKeyboardKey.arrowRight, control: true);
    expect(commands, isEmpty);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await sheet;
  });

  testWidgets('disabled dispatcher leaves all registered keys alone',
      (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final commands = <PlayerCommand>[];
    await _show(tester,
        child: Focus(focusNode: focus, child: const SizedBox.expand()),
        onCommand: commands.add);
    focus.requestFocus();
    await tester.pump();
    await HotkeysHelper.unregisterAll();
    await _key(tester, LogicalKeyboardKey.space);
    await _key(tester, LogicalKeyboardKey.keyM, control: true);
    expect(commands, isEmpty);
  });

  test('playback commands before initialization never create BASS/PlayService',
      () async {
    expect(PlayService.isInitialized, isFalse);
    for (final command in [
      PlayerCommand.togglePlayback,
      PlayerCommand.previous,
      PlayerCommand.next,
      PlayerCommand.seekBack,
      PlayerCommand.seekForward,
      PlayerCommand.volumeDown,
      PlayerCommand.volumeUp,
    ]) {
      await HotkeysHelper.runCommand(command);
    }
    expect(PlayService.isInitialized, isFalse);
  });
}
