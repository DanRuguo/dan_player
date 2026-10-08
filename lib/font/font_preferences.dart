import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';

class AppFontChoice {
  const AppFontChoice.bundled(this.id)
      : family = null,
        path = null;
  const AppFontChoice.custom(
      {required String this.family, required String this.path})
      : id = 'custom';
  final String id;
  final String? family, path;
  bool get isBundled => id != 'custom';
  AppFontFace get face => isBundled
      ? appBundledFonts.firstWhere((font) => font.id == id,
          orElse: () => appBundledFonts.first)
      : AppFontFace(id: id, family: family!, path: path, nativeFamily: family);
  Map<String, Object?> toJson() =>
      isBundled ? {'id': id} : {'id': id, 'family': family, 'path': path};
  static AppFontChoice? decode(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    if (appBundledFonts.any((font) => font.id == id)) {
      return AppFontChoice.bundled(id as String);
    }
    if (id == 'custom' &&
        value['family'] is String &&
        value['path'] is String &&
        (value['family'] as String).trim().isNotEmpty &&
        (value['path'] as String).isNotEmpty) {
      return AppFontChoice.custom(
          family: value['family'] as String, path: value['path'] as String);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is AppFontChoice &&
      id == other.id &&
      family == other.family &&
      path == other.path;
  @override
  int get hashCode => Object.hash(id, family, path);
}

class AppFontPreferences {
  const AppFontPreferences(
      {this.perLanguage = true,
      this.mixedScripts = true,
      this.shared = const AppFontChoice.bundled('source-han-sc'),
      this.zh = const AppFontChoice.bundled('source-han-sc'),
      this.en = const AppFontChoice.bundled('google-sans'),
      this.ja = const AppFontChoice.bundled('source-han-jp'),
      this.ko = const AppFontChoice.bundled('pretendard')});
  final bool perLanguage, mixedScripts;
  final AppFontChoice shared, zh, en, ja, ko;
  AppFontChoice choiceFor(UiLanguage language) => switch (language) {
        UiLanguage.zh => zh,
        UiLanguage.en => en,
        UiLanguage.ja => ja,
        UiLanguage.ko => ko
      };
  AppFontPreferences copyWith(
          {bool? perLanguage,
          bool? mixedScripts,
          AppFontChoice? shared,
          AppFontChoice? zh,
          AppFontChoice? en,
          AppFontChoice? ja,
          AppFontChoice? ko}) =>
      AppFontPreferences(
          perLanguage: perLanguage ?? this.perLanguage,
          mixedScripts: mixedScripts ?? this.mixedScripts,
          shared: shared ?? this.shared,
          zh: zh ?? this.zh,
          en: en ?? this.en,
          ja: ja ?? this.ja,
          ko: ko ?? this.ko);
  AppFontPreferences withChoice(UiLanguage? language, AppFontChoice choice) =>
      switch (language) {
        null => copyWith(shared: choice),
        UiLanguage.zh => copyWith(zh: choice),
        UiLanguage.en => copyWith(en: choice),
        UiLanguage.ja => copyWith(ja: choice),
        UiLanguage.ko => copyWith(ko: choice)
      };
  Map<String, Object?> toJson() => {
        'version': 1,
        'perLanguage': perLanguage,
        'mixedScripts': mixedScripts,
        'shared': shared.toJson(),
        'zh': zh.toJson(),
        'en': en.toJson(),
        'ja': ja.toJson(),
        'ko': ko.toJson()
      };
  static AppFontPreferences decode(Object? value,
      {String? legacyFamily, String? legacyPath}) {
    const defaults = AppFontPreferences();
    if (value is Map && value['version'] == 1) {
      return AppFontPreferences(
          perLanguage: value['perLanguage'] is bool
              ? value['perLanguage'] as bool
              : true,
          mixedScripts: value['mixedScripts'] is bool
              ? value['mixedScripts'] as bool
              : true,
          shared: AppFontChoice.decode(value['shared']) ?? defaults.shared,
          zh: AppFontChoice.decode(value['zh']) ?? defaults.zh,
          en: AppFontChoice.decode(value['en']) ?? defaults.en,
          ja: AppFontChoice.decode(value['ja']) ?? defaults.ja,
          ko: AppFontChoice.decode(value['ko']) ?? defaults.ko);
    }
    if (legacyFamily != null &&
        legacyFamily != 'DanPingFangSC' &&
        legacyFamily != appBundledFonts.first.family &&
        legacyPath != null) {
      return defaults.copyWith(
          perLanguage: false,
          mixedScripts: false,
          shared: AppFontChoice.custom(family: legacyFamily, path: legacyPath));
    }
    return defaults;
  }

  @override
  bool operator ==(Object other) =>
      other is AppFontPreferences &&
      perLanguage == other.perLanguage &&
      mixedScripts == other.mixedScripts &&
      shared == other.shared &&
      zh == other.zh &&
      en == other.en &&
      ja == other.ja &&
      ko == other.ko;
  @override
  int get hashCode =>
      Object.hash(perLanguage, mixedScripts, shared, zh, en, ja, ko);
}
