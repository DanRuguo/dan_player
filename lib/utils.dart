// ignore_for_file: unnecessary_this

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:pinyin/pinyin.dart';

extension StringHMMSS on Duration {
  /// Returns a string with hours, minutes, seconds,
  /// in the following format: H:MM:SS
  String toStringHMMSS() {
    return toString().split(".").first;
  }
}

/// 把 dec 表示成两位 hex
String _toHexString(int dec) {
  assert(dec >= 0 && dec <= 0xff);

  var hex = dec.toRadixString(16);
  if (hex.length == 1) hex = "0$hex";
  return hex;
}

extension RGBHexString on Color {
  String toRGBHexString() {
    final redHex = _toHexString(red);
    final greenHex = _toHexString(green);
    final blueHex = _toHexString(blue);

    return "#$redHex$greenHex$blueHex";
  }
}

/// [rgbHexStr] 必须是 #RRGGBB
Color? fromRGBHexString(String rgbHexStr) {
  if (rgbHexStr.startsWith("#") && rgbHexStr.length == 7) {
    return Color(0xff000000 + int.parse(rgbHexStr.substring(1), radix: 16));
  }

  return null;
}

Map<String, String> _sortKeyCache = {};

extension PinyinCompare on String {
  String _normalizeForSort() {
    return trim().toLowerCase().replaceFirst(
          RegExp(r'^[\s\-_.,，。:：;；!！?？()\[\]{}【】《》「」『』]+'),
          '',
        );
  }

  /// convert str to pinyin sort key, cache it when it hasn't been converted;
  String _getSortKey() {
    final normalized = _normalizeForSort();
    final cachedSortKey = _sortKeyCache[normalized];
    if (cachedSortKey != null) return cachedSortKey;

    final sortKey = ChineseHelper.containsChinese(normalized)
        ? PinyinHelper.getPinyin(
            normalized,
            separator: '',
            format: PinyinFormat.WITHOUT_TONE,
          )
        : normalized;

    _sortKeyCache[normalized] = sortKey;
    return sortKey;
  }

  /// Compares this string to [other] with pinyin first, else use the ordering of the code units.
  ///
  /// Returns a negative value if `this` is ordered before `other`,
  /// a positive value if `this` is ordered after `other`,
  /// or zero if `this` and `other` are equivalent.
  int localeCompareTo(String other) {
    final sortResult = _getSortKey().compareTo(other._getSortKey());
    if (sortResult != 0) return sortResult;

    return _normalizeForSort().compareTo(other._normalizeForSort());
  }
}

final GlobalKey<NavigatorState> ROUTER_KEY = GlobalKey();

final SCAFFOLD_MESSAGER = GlobalKey<ScaffoldMessengerState>();
void showTextOnSnackBar(String text) {
  SCAFFOLD_MESSAGER.currentState?.showSnackBar(SnackBar(content: Text(text)));
}

final LOGGER_MEMORY = MemoryOutput(
  secondOutput: kDebugMode ? ConsoleOutput() : null,
);
final LOGGER = Logger(
  filter: ProductionFilter(),
  printer: SimplePrinter(colors: false),
  output: LOGGER_MEMORY,
  level: Level.all,
);
