import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:flutter/foundation.dart';

/// Display framing for English IPA phonetics above lyric words.
enum EnglishPhoneticStyle {
  plain('plain'),
  slashes('slashes'),
  brackets('brackets');

  const EnglishPhoneticStyle(this.id);
  final String id;

  static EnglishPhoneticStyle parse(Object? value) {
    for (final style in values) {
      if (style.id == value) return style;
    }
    return plain;
  }

  String format(String ipa) {
    if (ipa.isEmpty) return '';
    return switch (this) {
      plain => ipa,
      slashes => '/$ipa/',
      brackets => '[$ipa]',
    };
  }
}

/// The reader checkbox and settings switch represent the same explicit intent.
void setEnglishPhoneticGeneration({
  required ValueNotifier<EnglishPhoneticPreferences> preferences,
  required ValueNotifier<DesktopLyricAppearance> appearance,
  required bool enabled,
}) {
  appearance.value = appearance.value.copyWith(showEnglishPhonetics: enabled);
  preferences.value = preferences.value.copyWith(enabled: enabled);
}

/// Derived English word IPA preferences. Phonetics are display-only and never
/// modify saved lyric sources or authored documents.
@immutable
class EnglishPhoneticPreferences {
  const EnglishPhoneticPreferences({
    this.enabled = false,
    this.style = EnglishPhoneticStyle.plain,
  });

  final bool enabled;
  final EnglishPhoneticStyle style;

  factory EnglishPhoneticPreferences.fromJson(Object? value) =>
      EnglishPhoneticPreferences(
        enabled: value is Map && value['enabled'] == true,
        style: value is Map
            ? EnglishPhoneticStyle.parse(value['style'])
            : EnglishPhoneticStyle.plain,
      );

  Map<String, Object> toJson() => {
        'enabled': enabled,
        'style': style.id,
      };

  EnglishPhoneticPreferences copyWith({
    bool? enabled,
    EnglishPhoneticStyle? style,
  }) =>
      EnglishPhoneticPreferences(
        enabled: enabled ?? this.enabled,
        style: style ?? this.style,
      );

  @override
  bool operator ==(Object other) =>
      other is EnglishPhoneticPreferences &&
      other.enabled == enabled &&
      other.style == style;

  @override
  int get hashCode => Object.hash(enabled, style);
}
