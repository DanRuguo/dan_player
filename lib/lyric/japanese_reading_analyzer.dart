import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/japanese_dictionary_runtime.dart';
import 'package:dan_player/lyric/japanese_online_readings.dart';
import 'package:dan_player/lyric/japanese_phonetic_channel.dart';
import 'package:flutter/foundation.dart';

enum JapaneseReadingRequestMode { automatic, online, offline }

/// One policy for automatic, manual and bulk readings. Remembered UI choices
/// never bypass the global automatic-network gate. Only an explicit online
/// request can use the service while that gate is closed.
class JapaneseReadingAnalyzerPolicy {
  JapaneseReadingAnalyzerPolicy({
    required bool Function() onlineAllowed,
    required String Function() clientId,
    required JapaneseChunkAnalyzer offline,
    required VoidCallback cancelOffline,
    required Future<bool> Function() hasDictionary,
    JapaneseOnlineReadingAnalyzer? online,
  })  : _onlineAllowed = onlineAllowed,
        _clientId = clientId,
        _offline = offline,
        _cancelOffline = cancelOffline,
        _hasDictionary = hasDictionary,
        _online = online ?? JapaneseOnlineReadingAnalyzer();

  factory JapaneseReadingAnalyzerPolicy._default(bool background) {
    final channel = background
        ? JapanesePhoneticChannel.background
        : JapanesePhoneticChannel.instance;
    return JapaneseReadingAnalyzerPolicy(
      onlineAllowed: () => AppSettings.instance.automaticOnlineLyrics.value,
      clientId: () => AppSettings.instance.japaneseReadings.value.yahooClientId,
      offline: channel.analyze,
      cancelOffline: channel.cancel,
      hasDictionary: () => JapaneseDictionaryRuntime.shared.inspect(),
    ).._observeSettings = true;
  }

  static final shared = JapaneseReadingAnalyzerPolicy._default(false);
  static final background = JapaneseReadingAnalyzerPolicy._default(true);
  final bool Function() _onlineAllowed;
  final String Function() _clientId;
  final JapaneseChunkAnalyzer _offline;
  final VoidCallback _cancelOffline;
  final Future<bool> Function() _hasDictionary;
  final JapaneseOnlineReadingAnalyzer _online;
  bool _observeSettings = false, _observing = false;
  int _generation = 0;
  JapaneseReadingRequestMode? _activeMode;
  String? _observedClientId;
  bool _observedEnabled = false;

  String _onlineNamespace() =>
      'online/${sha256.convert(utf8.encode(_clientId()))}';

  List<String> get cacheNamespaces =>
      cacheNamespacesFor(JapaneseReadingRequestMode.automatic);

  List<String> cacheNamespacesFor(JapaneseReadingRequestMode mode) =>
      mode == JapaneseReadingRequestMode.offline || _clientId().isEmpty
          ? const ['offline']
          : [_onlineNamespace(), 'offline'];

  bool canAnalyze(JapaneseReadingRequestMode mode) =>
      mode != JapaneseReadingRequestMode.automatic || _onlineAllowed();

  Future<JapanesePhoneticBatch> analyze(List<String> chunks) =>
      analyzeWithMode(chunks, JapaneseReadingRequestMode.automatic);

  void _attach() {
    if (!_observeSettings || _observing) return;
    _observing = true;
    _observedClientId = _clientId();
    _observedEnabled = AppSettings.instance.japaneseReadings.value.enabled;
    AppSettings.instance.automaticOnlineLyrics
        .addListener(_handleAutomaticOnlineChange);
    AppSettings.instance.japaneseReadings.addListener(_handlePreferencesChange);
  }

  void _handleAutomaticOnlineChange() {
    if (_activeMode == JapaneseReadingRequestMode.automatic &&
        !_onlineAllowed()) {
      cancel();
    }
  }

  void _handlePreferencesChange() {
    final preferences = AppSettings.instance.japaneseReadings.value;
    final disabled = _observedEnabled && !preferences.enabled;
    final clientChanged = _observedClientId != _clientId();
    _observedClientId = _clientId();
    _observedEnabled = preferences.enabled;
    // Remembering a batch-dialog mode does not change a running request.
    // A real OFF action revokes either mode; client changes affect online work.
    if (disabled ||
        (clientChanged &&
            _activeMode != null &&
            _activeMode != JapaneseReadingRequestMode.offline)) {
      cancel();
    }
  }

  Future<JapanesePhoneticBatch> analyzeWithMode(
      List<String> chunks, JapaneseReadingRequestMode mode) async {
    _attach();
    final generation = ++_generation;
    _activeMode = mode;
    bool current() => generation == _generation;
    try {
      if (!canAnalyze(mode)) {
        return const JapanesePhoneticBatch([], available: false);
      }
      final clientId = _clientId();
      final online =
          mode != JapaneseReadingRequestMode.offline && clientId.isNotEmpty;
      if (mode == JapaneseReadingRequestMode.online && clientId.isEmpty) {
        return const JapanesePhoneticBatch([], available: false);
      }
      if (online) {
        final result = await _online.analyze(chunks,
            clientId: clientId,
            stillCurrent: () =>
                current() &&
                _clientId() == clientId &&
                (mode == JapaneseReadingRequestMode.online ||
                    _onlineAllowed()));
        if (!current())
          return const JapanesePhoneticBatch([], available: false);
        if (result.available &&
            _clientId() == clientId &&
            (mode == JapaneseReadingRequestMode.online || _onlineAllowed())) {
          return result;
        }
      }
      if (!current() || !canAnalyze(mode)) {
        return const JapanesePhoneticBatch([], available: false);
      }
      if (!await _hasDictionary()) {
        return const JapanesePhoneticBatch([],
            available: false, dictionaryMissing: true);
      }
      if (!current() || !canAnalyze(mode)) {
        return const JapanesePhoneticBatch([], available: false);
      }
      final result = await _offline(chunks);
      return current() && canAnalyze(mode)
          ? result
          : const JapanesePhoneticBatch([], available: false);
    } finally {
      if (current()) _activeMode = null;
    }
  }

  void cancel() {
    _generation++;
    _activeMode = null;
    _online.cancel();
    _cancelOffline();
  }

  void dispose() {
    cancel();
    if (_observing) {
      AppSettings.instance.automaticOnlineLyrics
          .removeListener(_handleAutomaticOnlineChange);
      AppSettings.instance.japaneseReadings
          .removeListener(_handlePreferencesChange);
      _observing = false;
    }
  }
}
