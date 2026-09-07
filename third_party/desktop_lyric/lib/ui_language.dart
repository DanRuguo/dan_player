import 'package:flutter/material.dart';
import 'package:desktop_lyric/app_motion.dart';
import 'l10n/ui_catalog.dart';

/// UI language only: never translates track tags, filenames, lyrics or IDs.
enum UiLanguage {
  zh('zh', '中文'),
  en('en', 'English'),
  ja('ja', '日本語'),
  ko('ko', '한국어');

  const UiLanguage(this.code, this.nativeName);
  final String code;
  final String nativeName;
  Locale get locale => Locale(code);
  static UiLanguage parse(Object? value) =>
      values.firstWhere((item) => item.code == value, orElse: () => zh);
}

/// Shared in-process source; the player persists it and forwards changes to
/// its helper. Unknown/old settings stay Chinese for backwards compatibility.
final uiLanguage = ValueNotifier(UiLanguage.zh);

class UiLanguageScope extends InheritedNotifier<ValueNotifier<UiLanguage>> {
  UiLanguageScope({super.key, required super.child})
      : super(notifier: uiLanguage);
  static UiLanguage watch(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<UiLanguageScope>();
    return uiLanguage.value;
  }
}

/// Explicit source-key lookup with positional arguments, never pattern matches
/// arbitrary user text. Argument contents retain their original script.
String ui(String source, [List<Object?> arguments = const []]) =>
    translateUi(source, uiLanguage.value, arguments);

final _argumentPattern = RegExp(r'\{(\d+)\}');

String translateUi(String source, UiLanguage language,
    [List<Object?> arguments = const []]) {
  final row = uiCatalog[source];
  final index = switch (language) {
    UiLanguage.zh => -1,
    UiLanguage.en => 0,
    UiLanguage.ja => 1,
    UiLanguage.ko => 2,
  };
  final template = index < 0 || row == null ? source : row[index];
  // One pass means user-supplied '{1}' cannot expand into another argument.
  return arguments.isEmpty
      ? template
      : template.replaceAllMapped(_argumentPattern, (match) {
          final i = int.parse(match[1]!);
          return i < arguments.length ? '${arguments[i] ?? ''}' : match[0]!;
        });
}

/// Fade the existing tree, not an AnimatedSwitcher clone. Route state, text
/// controllers, focus, playback and scroll positions survive a language switch.
class UiLanguageTransition extends StatefulWidget {
  const UiLanguageTransition({super.key, required this.child});
  final Widget child;
  @override
  State<UiLanguageTransition> createState() => _UiLanguageTransitionState();
}

class _UiLanguageTransitionState extends State<UiLanguageTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade =
      AnimationController(vsync: this, duration: AppMotion.standard, value: 1);
  @override
  void initState() {
    super.initState();
    uiLanguage.addListener(_changed);
  }

  void _changed() {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    if ((MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        features.disableAnimations ||
        features.reduceMotion ||
        !TickerMode.valuesOf(context).enabled) {
      _fade.value = 1;
      return;
    }
    _fade.forward(from: _fade.isAnimating ? _fade.value : .65);
  }

  @override
  void dispose() {
    uiLanguage.removeListener(_changed);
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _fade, child: widget.child);
}
