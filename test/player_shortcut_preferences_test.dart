import 'dart:convert';

import 'package:dan_player/player_shortcut_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults cover every command with unique chords', () {
    final preferences = ShortcutPreferences.defaults();
    final resolved = preferences.resolve();
    expect(resolved, hasLength(PlayerCommand.values.length));
    expect(
      resolved.map((shortcut) => shortcut.command).toSet(),
      PlayerCommand.values.toSet(),
    );
    expect(
      resolved.map((shortcut) => shortcut.chord.signature).toSet(),
      hasLength(PlayerCommand.values.length),
    );
    expect(preferences.chordFor(PlayerCommand.togglePlayback).trigger,
        LogicalKeyboardKey.space);
    expect(preferences.chordFor(PlayerCommand.toggleMini).label, 'Ctrl + M');
  });

  test('custom bindings survive a JSON persistence round trip', () {
    final customized = ShortcutPreferences.defaults().withBinding(
      PlayerCommand.togglePlayback,
      ShortcutChord(LogicalKeyboardKey.keyP.keyId, control: true, alt: true),
    );
    final decoded = jsonDecode(jsonEncode(customized.toMap()));
    final restored = ShortcutPreferences.fromMap(decoded);
    expect(restored, customized);
    expect(
      restored.chordFor(PlayerCommand.togglePlayback).label,
      'Ctrl + Alt + P',
    );
  });

  test('modifier ordering has one canonical conflict signature', () {
    final controlThenAlt = ShortcutChord(
      LogicalKeyboardKey.keyA.keyId,
      control: true,
      alt: true,
    );
    final altThenControl = ShortcutChord(
      LogicalKeyboardKey.keyA.keyId,
      alt: true,
      control: true,
    );
    expect(controlThenAlt, altThenControl);
    expect(controlThenAlt.signature, altThenControl.signature);
    expect(controlThenAlt.label, 'Ctrl + Alt + A');
  });

  test('one malformed binding falls back without losing valid custom bindings',
      () {
    final stored = ShortcutPreferences.defaults().toMap();
    final bindings = stored['bindings']! as Map<String, Object>;
    bindings[PlayerCommand.togglePlayback.name] = {
      'keyId': LogicalKeyboardKey.keyP.keyId,
      'control': true,
    };
    bindings[PlayerCommand.toggleMini.name] = {'keyId': -1};

    final restored = ShortcutPreferences.fromMap(stored);
    expect(restored.chordFor(PlayerCommand.togglePlayback).label, 'Ctrl + P');
    expect(
      restored.chordFor(PlayerCommand.toggleMini),
      ShortcutPreferences.defaults().chordFor(PlayerCommand.toggleMini),
    );
  });

  test('conflicting or duplicate persisted maps fail closed to all defaults',
      () {
    final stored = ShortcutPreferences.defaults().toMap();
    final bindings = stored['bindings']! as Map<String, Object>;
    bindings[PlayerCommand.togglePlayback.name] =
        bindings[PlayerCommand.previous.name]!;

    expect(
      ShortcutPreferences.fromMap(stored),
      ShortcutPreferences.defaults(),
    );
  });

  test('withBinding rejects a chord already owned by another command', () {
    final preferences = ShortcutPreferences.defaults();
    expect(
      () => preferences.withBinding(
        PlayerCommand.togglePlayback,
        preferences.chordFor(PlayerCommand.next),
      ),
      throwsArgumentError,
    );
    expect(
      preferences.chordFor(PlayerCommand.togglePlayback).trigger,
      LogicalKeyboardKey.space,
    );
  });
}
