import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as path;

/// Real constant IconData keeps these exact native glyphs in Flutter's
/// release font subset. Ordering is shared with the native tray protocol.
const desktopTrayIcons = <IconData>[
  Symbols.open_in_new,
  Symbols.picture_in_picture_alt,
  Symbols.skip_previous,
  Symbols.play_arrow,
  Symbols.pause,
  Symbols.skip_next,
  Symbols.lyrics,
  Symbols.power_settings_new,
  Symbols.check,
];

Map<String, Object> desktopTrayIconConfiguration() => {
      'trayIconFontPath': path.join(
          File(Platform.resolvedExecutable).parent.path,
          'data',
          'flutter_assets',
          'packages',
          'material_symbols_icons',
          'lib',
          'fonts',
          'MaterialSymbolsOutlined.ttf'),
      'trayIconCodepoints':
          desktopTrayIcons.map((icon) => icon.codePoint).toList(),
    };
