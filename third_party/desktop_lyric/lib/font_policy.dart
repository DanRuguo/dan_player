import 'package:flutter/material.dart';
import 'ui_language.dart';

/// Logical IDs persist independently of the installation directory.
class AppFontFace {
  const AppFontFace(
      {required this.id,
      required this.family,
      this.asset,
      this.path,
      this.nativeFamily});
  final String id;
  final String family;
  final String? asset;
  final String? path;
  final String? nativeFamily;
  AppFontFace withPath(String? value) => AppFontFace(
      id: id,
      family: family,
      asset: asset,
      path: value,
      nativeFamily: nativeFamily);
  Map<String, Object?> toJson() => {
        'id': id,
        'family': family,
        'asset': asset,
        'path': path,
        'nativeFamily': nativeFamily
      };
  static AppFontFace? fromJson(Object? value) {
    if (value is! Map ||
        value['id'] is! String ||
        value['family'] is! String ||
        (value['family'] as String).isEmpty) {
      return null;
    }
    String? field(String key) =>
        value[key] is String ? value[key] as String : null;
    return AppFontFace(
        id: value['id'] as String,
        family: value['family'] as String,
        asset: field('asset'),
        path: field('path'),
        nativeFamily: field('nativeFamily'));
  }

  @override
  bool operator ==(Object other) =>
      other is AppFontFace &&
      id == other.id &&
      family == other.family &&
      asset == other.asset &&
      path == other.path &&
      nativeFamily == other.nativeFamily;
  @override
  int get hashCode => Object.hash(id, family, asset, path, nativeFamily);
}

const appBundledFonts = <AppFontFace>[
  AppFontFace(
      id: 'source-han-sc',
      family: 'packages/desktop_lyric/DanPingFangSC',
      asset: 'packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf',
      nativeFamily: 'Source Han Sans SC'),
  AppFontFace(
      id: 'google-sans',
      family: 'packages/desktop_lyric/DanGoogleSans',
      asset: 'packages/desktop_lyric/assets/fonts/GoogleSans-VF.ttf',
      nativeFamily: 'Google Sans'),
  AppFontFace(
      id: 'source-han-jp',
      family: 'packages/desktop_lyric/DanSourceHanJP',
      asset: 'packages/desktop_lyric/assets/fonts/SourceHanSansJP-Regular.otf',
      nativeFamily: 'Source Han Sans JP'),
  AppFontFace(
      id: 'pretendard',
      family: 'packages/desktop_lyric/DanPretendard',
      asset: 'packages/desktop_lyric/assets/fonts/Pretendard-Regular.otf',
      nativeFamily: 'Pretendard'),
];

class AppFontPolicy {
  const AppFontPolicy(
      {required this.language,
      required this.mixedScripts,
      required this.zh,
      required this.en,
      required this.ja,
      required this.ko,
      AppFontFace? baseFallback})
      : _baseFallback = baseFallback;
  factory AppFontPolicy.defaults({UiLanguage language = UiLanguage.zh}) =>
      AppFontPolicy(
          language: language,
          mixedScripts: true,
          zh: appBundledFonts[0],
          en: appBundledFonts[1],
          ja: appBundledFonts[2],
          ko: appBundledFonts[3]);
  final UiLanguage language;
  final bool mixedScripts;
  final AppFontFace zh, en, ja, ko;
  final AppFontFace? _baseFallback;
  AppFontFace get baseFallback => _baseFallback ?? appBundledFonts[0];
  AppFontPolicy withLanguage(UiLanguage value) => AppFontPolicy(
      language: value,
      mixedScripts: mixedScripts,
      zh: zh,
      en: en,
      ja: ja,
      ko: ko,
      baseFallback: baseFallback);
  AppFontFace faceFor(UiLanguage value) => switch (value) {
        UiLanguage.zh => zh,
        UiLanguage.en => en,
        UiLanguage.ja => ja,
        UiLanguage.ko => ko
      };
  AppFontFace get uiFace => faceFor(language);
  String get uiFamily => uiFace.family;
  List<String> get fallback => <String>{
        baseFallback.family,
        ja.family,
        ko.family,
        en.family,
        'Segoe UI',
        'Segoe UI Symbol',
        'Segoe UI Emoji'
      }.toList();
  Iterable<AppFontFace> get faces => <AppFontFace>{zh, en, ja, ko};
  Map<String, Object?> toJson() => {
        'language': language.code,
        'mixedScripts': mixedScripts,
        'zh': zh.toJson(),
        'en': en.toJson(),
        'ja': ja.toJson(),
        'ko': ko.toJson(),
        'baseFallback': baseFallback.toJson()
      };
  static AppFontPolicy fromJson(Object? value) {
    if (value is! Map) return AppFontPolicy.defaults();
    final defaults =
        AppFontPolicy.defaults(language: UiLanguage.parse(value['language']));
    return AppFontPolicy(
        language: defaults.language,
        mixedScripts: value['mixedScripts'] == true,
        zh: AppFontFace.fromJson(value['zh']) ?? defaults.zh,
        en: AppFontFace.fromJson(value['en']) ?? defaults.en,
        ja: AppFontFace.fromJson(value['ja']) ?? defaults.ja,
        ko: AppFontFace.fromJson(value['ko']) ?? defaults.ko,
        baseFallback: AppFontFace.fromJson(value['baseFallback']) ??
            defaults.baseFallback);
  }

  @override
  bool operator ==(Object other) =>
      other is AppFontPolicy &&
      language == other.language &&
      mixedScripts == other.mixedScripts &&
      zh == other.zh &&
      en == other.en &&
      ja == other.ja &&
      ko == other.ko &&
      baseFallback == other.baseFallback;
  @override
  int get hashCode =>
      Object.hash(language, mixedScripts, zh, en, ja, ko, baseFallback);
}

class AppFontScope extends InheritedWidget {
  const AppFontScope({super.key, required this.policy, required super.child});
  final AppFontPolicy policy;
  static AppFontPolicy? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppFontScope>()?.policy;
  static AppFontPolicy of(BuildContext context) {
    final scoped = maybeOf(context);
    if (scoped != null) return scoped;
    // Standalone consumers keep their authored style unless a font policy is
    // supplied. A scope never silently overrides a preview or test harness.
    final inherited =
        AppFontFace(id: 'inherit', family: appBundledFonts.first.family);
    return AppFontPolicy(
        language: uiLanguage.value,
        mixedScripts: false,
        zh: inherited,
        en: inherited,
        ja: inherited,
        ko: inherited);
  }

  @override
  bool updateShouldNotify(AppFontScope oldWidget) => policy != oldWidget.policy;
}

class AppFontRun {
  const AppFontRun(this.text, this.language);
  final String text;
  final UiLanguage language;
}

final _runCache = <(String, UiLanguage), List<AppFontRun>>{};
final _paragraphBreak = RegExp(r'\r\n|[\n\u2028\u2029]');

List<AppFontRun> _rememberRuns(
    (String, UiLanguage) key, List<AppFontRun> runs) {
  final immutable = List<AppFontRun>.unmodifiable(runs);
  // Share the same bounded cache for complete multiline projections and rows.
  // Long documents are not retained in the shared cache.
  if (key.$1.length <= 8192) {
    _runCache[key] = immutable;
    while (_runCache.length > 256) {
      _runCache.remove(_runCache.keys.first);
    }
  }
  return immutable;
}

/// Han is shared by several languages. Kana/Hangul provide context; an explicit
/// content language (or UI language) resolves otherwise ambiguous Han text.
List<AppFontRun> appFontRuns(String text, UiLanguage language) {
  final key = (text, language);
  final cached = _runCache.remove(key);
  if (cached != null) {
    _runCache[key] = cached;
    return cached;
  }
  final breaks = _paragraphBreak.allMatches(text).iterator;
  if (breaks.moveNext()) {
    final result = <AppFontRun>[];
    var start = 0;
    do {
      final separator = breaks.current;
      result.addAll(
          appFontRuns(text.substring(start, separator.start), language));
      // CRLF is one grapheme. Keep the author's complete separator and UTF-16
      // offsets instead of creating style boundaries between CR and LF.
      result.add(AppFontRun(text.substring(separator.start, separator.end),
          result.isEmpty ? language : result.last.language));
      start = separator.end;
    } while (breaks.moveNext());
    result.addAll(appFontRuns(text.substring(start), language));
    return _rememberRuns(key, result);
  }
  bool kana(int c) => c >= 0x3040 && c <= 0x30ff || c >= 0xff66 && c <= 0xff9d;
  bool hangul(int c) =>
      c >= 0xac00 && c <= 0xd7af ||
      c >= 0x1100 && c <= 0x11ff ||
      c >= 0x3130 && c <= 0x318f ||
      c >= 0xa960 && c <= 0xa97f ||
      c >= 0xd7b0 && c <= 0xd7ff;
  bool han(int c) =>
      c >= 0x3400 && c <= 0x9fff ||
      c >= 0xf900 && c <= 0xfaff ||
      c >= 0x20000 && c <= 0x323af;
  bool latin(int c) =>
      c >= 0x41 && c <= 0x5a ||
      c >= 0x61 && c <= 0x7a ||
      c >= 0xc0 && c <= 0x24f ||
      c >= 0x1e00 && c <= 0x1eff;
  final runes = text.runes;
  final hanLanguage = runes.any(kana)
      ? UiLanguage.ja
      : runes.any(hangul)
          ? UiLanguage.ko
          : language == UiLanguage.en
              ? UiLanguage.zh
              : language;
  final result = <AppFontRun>[];
  var current = language;
  final buffer = StringBuffer();
  for (final cluster in text.characters) {
    final codes = cluster.runes;
    final next = codes.any(kana)
        ? UiLanguage.ja
        : codes.any(hangul)
            ? UiLanguage.ko
            : codes.any(han)
                ? hanLanguage
                : codes.any(latin)
                    ? UiLanguage.en
                    : current;
    if (next != current && buffer.isNotEmpty) {
      result.add(AppFontRun(buffer.toString(), current));
      buffer.clear();
    }
    current = next;
    buffer.write(cluster);
  }
  if (buffer.isNotEmpty) result.add(AppFontRun(buffer.toString(), current));
  return _rememberRuns(key, result);
}

TextSpan appFontSpan(String text,
    {required TextStyle style,
    required AppFontPolicy policy,
    UiLanguage? language}) {
  final context = language ?? policy.language;
  if (policy.uiFace.id == 'inherit') return TextSpan(text: text, style: style);
  final fallback = policy.fallback;
  if (!policy.mixedScripts) {
    return TextSpan(
        text: text,
        style: style.copyWith(
            fontFamily: policy.faceFor(context).family,
            fontFamilyFallback: fallback),
        locale: context.locale);
  }
  return TextSpan(style: style, children: [
    for (final run in appFontRuns(text, context))
      TextSpan(
          text: run.text,
          style: TextStyle(
              fontFamily: policy.faceFor(run.language).family,
              fontFamilyFallback: fallback),
          locale: run.language.locale)
  ]);
}

/// Use for content whose scripts may differ from the surrounding UI locale.
class AppFontText extends StatelessWidget {
  const AppFontText(this.data,
      {super.key,
      this.style,
      this.textAlign,
      this.textDirection,
      this.softWrap,
      this.overflow,
      this.textScaler,
      this.maxLines,
      this.semanticsLabel,
      this.strutStyle,
      this.textWidthBasis,
      this.textHeightBehavior,
      this.language});
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final StrutStyle? strutStyle;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final UiLanguage? language;
  @override
  Widget build(BuildContext context) {
    if (AppFontScope.maybeOf(context) == null) {
      return Text(data,
          style: style,
          textAlign: textAlign,
          textDirection: textDirection,
          softWrap: softWrap,
          overflow: overflow,
          textScaler: textScaler,
          maxLines: maxLines,
          semanticsLabel: semanticsLabel,
          strutStyle: strutStyle,
          textWidthBasis: textWidthBasis,
          textHeightBehavior: textHeightBehavior);
    }
    return Text.rich(
        appFontSpan(data,
            style: DefaultTextStyle.of(context).style.merge(style),
            policy: AppFontScope.of(context),
            language: language),
        textAlign: textAlign,
        textDirection: textDirection,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
        strutStyle: strutStyle,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior);
  }
}

class AppFontSelectableText extends StatelessWidget {
  const AppFontSelectableText(this.data, {super.key, this.style});
  final String data;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => AppFontScope.maybeOf(context) == null
      ? SelectableText(data, style: style)
      : SelectableText.rich(appFontSpan(data,
          style: DefaultTextStyle.of(context).style.merge(style),
          policy: AppFontScope.of(context)));
}

/// Direct Text leaf for existing keyed list/header consumers. It retains their
/// selection, semantics and widget identity while observing the shared scope.
Text appFontText(BuildContext context, String data,
    {Key? key,
    TextStyle? style,
    TextAlign? textAlign,
    TextDirection? textDirection,
    bool? softWrap,
    TextOverflow? overflow,
    TextScaler? textScaler,
    int? maxLines,
    String? semanticsLabel,
    StrutStyle? strutStyle,
    TextWidthBasis? textWidthBasis,
    TextHeightBehavior? textHeightBehavior}) {
  final policy = AppFontScope.maybeOf(context);
  if (policy == null) {
    return Text(data,
        key: key,
        style: style,
        textAlign: textAlign,
        textDirection: textDirection,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
        strutStyle: strutStyle,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior);
  }
  return Text.rich(
      appFontSpan(data,
          style: DefaultTextStyle.of(context).style.merge(style),
          policy: policy),
      key: key,
      textAlign: textAlign,
      textDirection: textDirection,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      strutStyle: strutStyle,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior);
}
