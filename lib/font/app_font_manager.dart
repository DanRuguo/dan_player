import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:path/path.dart' as p;
import '../app_settings.dart';
import 'font_preferences.dart';

class AppFontManager {
  AppFontManager(
      {Future<void> Function(AppFontPolicy)? load,
      Future<bool> Function(String)? fileExists,
      String? assetDirectory})
      : _load = load ?? ensureAppFontsLoaded,
        _exists = fileExists ?? ((path) => File(path).exists()),
        _assetDirectory = assetDirectory ??
            p.join(p.dirname(Platform.resolvedExecutable), 'data',
                'flutter_assets');
  static final instance = AppFontManager();
  final Future<void> Function(AppFontPolicy) _load;
  final Future<bool> Function(String) _exists;
  final String _assetDirectory;
  final policy = ValueNotifier<AppFontPolicy>(AppFontPolicy.defaults());
  final missingCustomFonts = ValueNotifier<List<AppFontChoice>>(const []);
  int _generation = 0;
  bool _listening = false;
  bool _disposed = false;
  bool _committing = false;
  Future<void> initialize() async {
    if (!_listening) {
      uiLanguage.addListener(_languageChanged);
      _listening = true;
    }
    await apply(AppSettings.instance.fontPreferences);
  }

  void _languageChanged() {
    final ready = policy.value;
    policy.value = ready.withLanguage(uiLanguage.value);
  }

  Future<AppFontPolicy> prepare(
      AppFontPreferences preferences, UiLanguage language,
      {bool strict = false}) async {
    Future<AppFontFace> resolve(AppFontChoice choice, UiLanguage slot) async {
      final fallback = preferences.perLanguage
          ? const AppFontPreferences().choiceFor(slot).face
          : const AppFontPreferences().shared.face;
      var face = choice.face;
      if (!choice.isBundled && !await _exists(choice.path!)) {
        if (strict) {
          throw StateError('Custom font is unavailable: ${choice.family}');
        }
        face = fallback;
      } else if (!choice.isBundled) {
        try {
          await _load(AppFontPolicy(
              language: slot,
              mixedScripts: false,
              zh: face,
              en: face,
              ja: face,
              ko: face));
        } catch (_) {
          if (strict) rethrow;
          face = fallback;
        }
      }
      return face.asset == null
          ? face
          : face.withPath(p.join(_assetDirectory, face.asset!));
    }

    final choices = [
      for (final slot in UiLanguage.values)
        preferences.perLanguage
            ? preferences.choiceFor(slot)
            : preferences.shared
    ];
    final faces = await Future.wait([
      for (var i = 0; i < 4; i++) resolve(choices[i], UiLanguage.values[i])
    ]);
    final result = AppFontPolicy(
        language: language,
        mixedScripts: preferences.perLanguage && preferences.mixedScripts,
        zh: faces[0],
        en: faces[1],
        ja: faces[2],
        ko: faces[3],
        baseFallback: appBundledFonts[0]
            .withPath(p.join(_assetDirectory, appBundledFonts[0].asset!)));
    await _load(result);
    return result;
  }

  void _publish(AppFontPreferences preferences, AppFontPolicy ready) {
    final missing = <AppFontChoice>{};
    for (final slot in UiLanguage.values) {
      final choice = preferences.perLanguage
          ? preferences.choiceFor(slot)
          : preferences.shared;
      if (!choice.isBundled && choice.face != ready.faceFor(slot)) {
        missing.add(choice);
      }
    }
    missingCustomFonts.value = List.unmodifiable(missing);
    policy.value = ready;
  }

  Future<void> apply(AppFontPreferences preferences) async {
    final generation = ++_generation;
    final ready = await prepare(preferences, uiLanguage.value);
    if (_disposed || generation != _generation) return;
    _publish(preferences, ready.withLanguage(uiLanguage.value));
  }

  /// Loading and durable persistence finish before a new choice is published.
  Future<void> commit(AppFontPreferences preferences,
      {Future<void> Function()? persist}) async {
    if (_committing) throw StateError('A font change is already being saved');
    _committing = true;
    try {
      final generation = ++_generation;
      var ready = await prepare(preferences, uiLanguage.value, strict: true);
      if (_disposed || generation != _generation) {
        throw StateError('Font change superseded');
      }
      final settings = AppSettings.instance;
      final previous = settings.fontPreferences;
      settings.fontPreferences = preferences;
      try {
        await (persist?.call() ??
            settings.saveSettings(
                captureWindowSize: false,
                throwOnError: true,
                requireCommit: true));
      } catch (_) {
        settings.fontPreferences = previous;
        rethrow;
      }
      if (!_disposed && generation == _generation) {
        if (ready.language != uiLanguage.value) {
          ready = ready.withLanguage(uiLanguage.value);
        }
        if (!_disposed && generation == _generation) {
          _publish(preferences, ready);
        }
      }
    } finally {
      _committing = false;
    }
  }

  void dispose() {
    _disposed = true;
    ++_generation;
    if (_listening) uiLanguage.removeListener(_languageChanged);
    policy.dispose();
    missingCustomFonts.dispose();
  }
}
