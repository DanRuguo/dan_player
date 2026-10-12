import 'package:flutter/foundation.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';

/// The reader checkbox and settings switch represent the same explicit intent.
/// Legacy visibility-only state remains readable without granting generation.
void setJapaneseReadingGeneration({
  required ValueNotifier<JapaneseReadingPreferences> preferences,
  required ValueNotifier<DesktopLyricAppearance> appearance,
  required bool enabled,
}) {
  appearance.value = appearance.value.copyWith(showJapaneseReading: enabled);
  preferences.value = preferences.value
      .copyWith(enabled: enabled, offlineGenerationAllowed: enabled);
}

/// Generated readings are a display aid, never a saved lyric source.
@immutable
class JapaneseReadingPreferences {
  const JapaneseReadingPreferences({
    this.enabled = false,
    this.offlineGenerationAllowed = false,
    this.yahooClientId = '',
    this.lastManualMode = 'offline',
  });

  final bool enabled;

  /// Explicit continuous generation may use the local analyzer when automatic
  /// network access is off. Legacy enabled values alone grant no such intent.
  final bool offlineGenerationAllowed;
  final String yahooClientId;

  /// A remembered UI choice, not permission for automatic network requests.
  final String lastManualMode;

  factory JapaneseReadingPreferences.fromJson(Object? value) =>
      JapaneseReadingPreferences(
          enabled: value is Map && value['enabled'] == true,
          offlineGenerationAllowed:
              value is Map && value['offlineGenerationAllowed'] == true,
          yahooClientId: value is Map
              ? normalizeJapaneseReadingClientId(value['yahooClientId']) ?? ''
              : '',
          lastManualMode: value is Map && value['lastManualMode'] == 'online'
              ? 'online'
              : 'offline');

  Map<String, Object> toJson() => {
        'enabled': enabled,
        if (offlineGenerationAllowed) 'offlineGenerationAllowed': true,
        if (yahooClientId.isNotEmpty) 'yahooClientId': yahooClientId,
        'lastManualMode': lastManualMode,
      };

  JapaneseReadingPreferences copyWith({
    bool? enabled,
    bool? offlineGenerationAllowed,
    String? yahooClientId,
    String? lastManualMode,
  }) =>
      JapaneseReadingPreferences(
          enabled: enabled ?? this.enabled,
          offlineGenerationAllowed:
              offlineGenerationAllowed ?? this.offlineGenerationAllowed,
          yahooClientId: yahooClientId ?? this.yahooClientId,
          lastManualMode: lastManualMode ?? this.lastManualMode);

  @override
  bool operator ==(Object other) =>
      other is JapaneseReadingPreferences &&
      other.enabled == enabled &&
      other.offlineGenerationAllowed == offlineGenerationAllowed &&
      other.yahooClientId == yahooClientId &&
      other.lastManualMode == lastManualMode;

  @override
  int get hashCode => Object.hash(
      enabled, offlineGenerationAllowed, yahooClientId, lastManualMode);
}

/// A header-safe, bounded client identifier. Invalid legacy values are ignored.
String? normalizeJapaneseReadingClientId(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  if (text.length > 2048 ||
      text.codeUnits.any((unit) => unit < 0x21 || unit > 0x7e)) {
    return null;
  }
  return text;
}
