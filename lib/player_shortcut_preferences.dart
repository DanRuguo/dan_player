import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum PlayerCommand {
  togglePlayback,
  previous,
  next,
  seekBack,
  seekForward,
  volumeDown,
  volumeUp,
  toggleMini,
  toggleFullScreen,
  escape,
  help,
}

@immutable
class ShortcutChord {
  const ShortcutChord(
    this.keyId, {
    this.control = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });

  final int keyId;
  final bool control;
  final bool alt;
  final bool shift;
  final bool meta;

  LogicalKeyboardKey get trigger => LogicalKeyboardKey(keyId);

  SingleActivator get activator => SingleActivator(
        trigger,
        control: control,
        alt: alt,
        shift: shift,
        meta: meta,
        includeRepeats: false,
      );

  String get signature => '$keyId:$control:$alt:$shift:$meta';

  String get label {
    final parts = <String>[
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      if (meta) 'Win',
      _keyLabel(trigger),
    ];
    return parts.join(' + ');
  }

  Map<String, Object> toMap() => {
        'keyId': keyId,
        'control': control,
        'alt': alt,
        'shift': shift,
        'meta': meta,
      };

  static ShortcutChord? fromMap(Object? value) {
    if (value is! Map) return null;
    final keyId = value['keyId'];
    if (keyId is! int || keyId <= 0) return null;
    bool flag(String key) {
      final raw = value[key];
      return raw is bool ? raw : false;
    }

    final chord = ShortcutChord(
      keyId,
      control: flag('control'),
      alt: flag('alt'),
      shift: flag('shift'),
      meta: flag('meta'),
    );
    return chord.isModifierOnly ? null : chord;
  }

  bool get isModifierOnly => _modifierKeyIds.contains(keyId);

  @override
  bool operator ==(Object other) =>
      other is ShortcutChord && other.signature == signature;

  @override
  int get hashCode => Object.hash(keyId, control, alt, shift, meta);
}

@immutable
class PlayerShortcutDefinition {
  const PlayerShortcutDefinition(
    this.command,
    this.description,
    this.defaultChord,
  );

  final PlayerCommand command;
  final String description;
  final ShortcutChord defaultChord;
}

final List<PlayerShortcutDefinition> playerShortcutDefinitions =
    List.unmodifiable([
  PlayerShortcutDefinition(
    PlayerCommand.togglePlayback,
    '播放 / 暂停',
    ShortcutChord(LogicalKeyboardKey.space.keyId),
  ),
  PlayerShortcutDefinition(
    PlayerCommand.previous,
    '上一首',
    ShortcutChord(LogicalKeyboardKey.arrowLeft.keyId, control: true),
  ),
  PlayerShortcutDefinition(
    PlayerCommand.next,
    '下一首',
    ShortcutChord(LogicalKeyboardKey.arrowRight.keyId, control: true),
  ),
  PlayerShortcutDefinition(
    PlayerCommand.seekBack,
    '快退 5 秒',
    ShortcutChord(LogicalKeyboardKey.arrowLeft.keyId),
  ),
  PlayerShortcutDefinition(
    PlayerCommand.seekForward,
    '快进 5 秒',
    ShortcutChord(LogicalKeyboardKey.arrowRight.keyId),
  ),
  PlayerShortcutDefinition(
    PlayerCommand.volumeDown,
    '播放器音量降低 5%',
    ShortcutChord(LogicalKeyboardKey.arrowDown.keyId, control: true),
  ),
  PlayerShortcutDefinition(
    PlayerCommand.volumeUp,
    '播放器音量提高 5%',
    ShortcutChord(LogicalKeyboardKey.arrowUp.keyId, control: true),
  ),
  PlayerShortcutDefinition(
    PlayerCommand.toggleMini,
    '切换迷你播放器',
    ShortcutChord(LogicalKeyboardKey.keyM.keyId, control: true),
  ),
  PlayerShortcutDefinition(
    PlayerCommand.toggleFullScreen,
    '进入 / 退出全屏',
    ShortcutChord(LogicalKeyboardKey.f11.keyId),
  ),
  PlayerShortcutDefinition(
    PlayerCommand.escape,
    '关闭弹窗 / 退出迷你或全屏 / 返回',
    ShortcutChord(LogicalKeyboardKey.escape.keyId),
  ),
  PlayerShortcutDefinition(
    PlayerCommand.help,
    '查看快捷键',
    ShortcutChord(LogicalKeyboardKey.f1.keyId),
  ),
]);

@immutable
class PlayerShortcut {
  const PlayerShortcut({
    required this.command,
    required this.description,
    required this.chord,
  });

  final PlayerCommand command;
  final String description;
  final ShortcutChord chord;

  String get keys => chord.label;
  SingleActivator get activator => chord.activator;
}

@immutable
class ShortcutPreferences {
  ShortcutPreferences._(Map<PlayerCommand, ShortcutChord> bindings)
      : bindings = Map.unmodifiable(bindings);

  factory ShortcutPreferences.defaults() => ShortcutPreferences._({
        for (final definition in playerShortcutDefinitions)
          definition.command: definition.defaultChord,
      });

  final Map<PlayerCommand, ShortcutChord> bindings;

  ShortcutChord chordFor(PlayerCommand command) =>
      bindings[command] ?? _definitionFor(command).defaultChord;

  PlayerCommand? conflictingCommand(
    PlayerCommand command,
    ShortcutChord candidate,
  ) {
    for (final entry in bindings.entries) {
      if (entry.key != command && entry.value == candidate) return entry.key;
    }
    return null;
  }

  ShortcutPreferences withBinding(
    PlayerCommand command,
    ShortcutChord chord,
  ) {
    if (chord.isModifierOnly) {
      throw ArgumentError.value(chord, 'chord', '不能只使用修饰键');
    }
    final conflict = conflictingCommand(command, chord);
    if (conflict != null) {
      throw ArgumentError.value(chord, 'chord', '快捷键与 ${conflict.name} 冲突');
    }
    return ShortcutPreferences._({...bindings, command: chord});
  }

  List<PlayerShortcut> resolve() => List.unmodifiable([
        for (final definition in playerShortcutDefinitions)
          PlayerShortcut(
            command: definition.command,
            description: definition.description,
            chord: chordFor(definition.command),
          ),
      ]);

  Map<String, Object> toMap() => {
        'version': 1,
        'bindings': {
          for (final definition in playerShortcutDefinitions)
            definition.command.name: chordFor(definition.command).toMap(),
        },
      };

  factory ShortcutPreferences.fromMap(Object? value) {
    final defaults = ShortcutPreferences.defaults();
    if (value is! Map) return defaults;
    final rawBindings = value['bindings'];
    if (rawBindings is! Map) return defaults;
    final parsed = Map<PlayerCommand, ShortcutChord>.from(defaults.bindings);
    for (final definition in playerShortcutDefinitions) {
      final raw = rawBindings[definition.command.name];
      if (raw == null) continue;
      final chord = ShortcutChord.fromMap(raw);
      if (chord == null) continue;
      parsed[definition.command] = chord;
    }
    final signatures = <String>{};
    for (final chord in parsed.values) {
      if (!signatures.add(chord.signature)) return defaults;
    }
    return ShortcutPreferences._(parsed);
  }

  @override
  bool operator ==(Object other) {
    if (other is! ShortcutPreferences ||
        other.bindings.length != bindings.length) {
      return false;
    }
    return bindings.entries.every(
      (entry) => other.bindings[entry.key] == entry.value,
    );
  }

  @override
  int get hashCode => Object.hashAll([
        for (final command in PlayerCommand.values) chordFor(command),
      ]);
}

PlayerShortcutDefinition _definitionFor(PlayerCommand command) =>
    playerShortcutDefinitions.firstWhere(
      (definition) => definition.command == command,
    );

ShortcutChord? shortcutChordFromEvent(
  KeyEvent event,
  HardwareKeyboard keyboard,
) {
  if (event is! KeyDownEvent ||
      _modifierKeyIds.contains(event.logicalKey.keyId)) {
    return null;
  }
  return ShortcutChord(
    event.logicalKey.keyId,
    control: keyboard.isControlPressed,
    alt: keyboard.isAltPressed,
    shift: keyboard.isShiftPressed,
    meta: keyboard.isMetaPressed,
  );
}

String _keyLabel(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.space) return '空格';
  if (key == LogicalKeyboardKey.arrowLeft) return '←';
  if (key == LogicalKeyboardKey.arrowRight) return '→';
  if (key == LogicalKeyboardKey.arrowUp) return '↑';
  if (key == LogicalKeyboardKey.arrowDown) return '↓';
  if (key == LogicalKeyboardKey.escape) return 'Esc';
  final label = key.keyLabel.trim();
  if (label.isNotEmpty) return label.length == 1 ? label.toUpperCase() : label;
  return key.debugName ?? '0x${key.keyId.toRadixString(16)}';
}

final Set<int> _modifierKeyIds = {
  LogicalKeyboardKey.control.keyId,
  LogicalKeyboardKey.controlLeft.keyId,
  LogicalKeyboardKey.controlRight.keyId,
  LogicalKeyboardKey.alt.keyId,
  LogicalKeyboardKey.altLeft.keyId,
  LogicalKeyboardKey.altRight.keyId,
  LogicalKeyboardKey.shift.keyId,
  LogicalKeyboardKey.shiftLeft.keyId,
  LogicalKeyboardKey.shiftRight.keyId,
  LogicalKeyboardKey.meta.keyId,
  LogicalKeyboardKey.metaLeft.keyId,
  LogicalKeyboardKey.metaRight.keyId,
};
