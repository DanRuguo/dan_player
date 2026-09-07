// ignore_for_file: unnecessary_this

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:dan_player/component/app_presentation.dart';
export 'package:dan_player/component/app_presentation.dart' show AppNoticeKind;
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:pinyin/pinyin.dart';
import 'package:desktop_lyric/ui_language.dart';

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
    final argb = toARGB32();
    final redHex = _toHexString((argb >> 16) & 0xff);
    final greenHex = _toHexString((argb >> 8) & 0xff);
    final blueHex = _toHexString(argb & 0xff);

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

const int _sortKeyCacheLimit = 4096;
final LinkedHashMap<String, String> _sortKeyCache = LinkedHashMap();

@visibleForTesting
int get debugSortKeyCacheSize => _sortKeyCache.length;

@visibleForTesting
int get debugSortKeyCacheLimit => _sortKeyCacheLimit;

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
    final cachedSortKey = _sortKeyCache.remove(normalized);
    if (cachedSortKey != null) {
      // Refresh recency so frequently visible names survive bounded eviction.
      _sortKeyCache[normalized] = cachedSortKey;
      return cachedSortKey;
    }

    final sortKey = ChineseHelper.containsChinese(normalized)
        ? PinyinHelper.getPinyin(
            normalized,
            separator: '',
            format: PinyinFormat.WITHOUT_TONE,
          )
        : normalized;

    _sortKeyCache[normalized] = sortKey;
    if (_sortKeyCache.length > _sortKeyCacheLimit) {
      _sortKeyCache.remove(_sortKeyCache.keys.first);
    }
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

/// Shows one current result message. A newer result clears both the visible
/// message and any queued messages before it is presented, so stale feedback
/// can never appear after the operation that superseded it.
void showAppNotice(
  String text, {
  BuildContext? context,
  AppNoticeKind kind = AppNoticeKind.info,
  Duration duration = const Duration(seconds: 4),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  showPresentationNotice(text,
      context: context,
      kind: kind,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
      fallbackMessenger: SCAFFOLD_MESSAGER.currentState);
}

/// Compatibility entry for existing call sites. New code should provide an
/// explicit [AppNoticeKind]; conservative wording inference keeps old success
/// and error feedback visually distinct until each feature is migrated.
void showTextOnSnackBar(
  String text, {
  AppNoticeKind? kind,
  BuildContext? context,
  List<Object?> arguments = const [],
}) {
  showAppNotice(
    ui(text, arguments),
    context: context,
    kind: kind ?? _noticeKindForText(text),
  );
}

AppNoticeKind _noticeKindForText(String text) {
  final normalized = text.toLowerCase();
  if (text.contains('失败') ||
      text.contains('错误') ||
      text.contains('无法') ||
      text.contains('未能') ||
      text.contains('异常') ||
      normalized.contains('exception') ||
      normalized.contains('error')) {
    return AppNoticeKind.error;
  }
  if (text.contains('不可用') ||
      text.contains('请等待') ||
      text.contains('已阻止') ||
      text.contains('不能') ||
      text.contains('不支持') ||
      text.contains('只读')) {
    return AppNoticeKind.warning;
  }
  if (text.startsWith('已') || text.contains('成功') || text.contains('完成')) {
    return AppNoticeKind.success;
  }
  return AppNoticeKind.info;
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
