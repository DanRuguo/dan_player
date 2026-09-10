import 'dart:async';
import 'dart:io';
import 'package:desktop_lyric/appearance_palette_app.dart';
import 'package:desktop_lyric/appearance_palette_bridge.dart';
import 'package:desktop_lyric/app_presentation.dart';
import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/app_scrollbar.dart';

import 'package:desktop_lyric/app_typography.dart';
import 'package:desktop_lyric/component/desktop_lyric_body.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_theme_transition.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/desktop_lyric_window_binding.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:desktop_lyric/ui_language.dart';

Future<void> main(List<String> args) => runDesktopLyric(args);

/// Used by the standalone development runner and Dan Player's lyric mode.
Future<void> runDesktopLyric(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  DesktopLyricController.initWithArgs(args);
  final controller = DesktopLyricController.instance;
  final layout = DesktopLyricWindowLayout.instance;
  final initiallyVertical = controller.vertical.value;
  final binding = DesktopLyricWindowBinding(controller, layout);

  WindowOptions windowOptions = WindowOptions(
    size: DesktopLyricGeometry.defaultSize(initiallyVertical),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (controller.inputClosed) return;
    await windowManager.setAsFrameless();
    try {
      await layout.initialize(
          vertical: initiallyVertical, appearance: controller.appearance.value);
    } catch (error, stack) {
      stderr.writeln('Desktop lyric initial geometry: $error\n$stack');
    }
    if (controller.inputClosed) return;
    // Account for settings that arrived during native initialization, then
    // follow actual display events without a background resize timer.
    binding.attach();
    if (controller.inputClosed) return;
    await windowManager.show();
  });

  runApp(DesktopLyricApp(binding: binding));
}

@pragma('vm:entry-point')
Future<void> desktopLyricAppearanceMain(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final client = DesktopLyricPaletteClient();
  await client.initialize(
      initialSnapshot:
          DesktopLyricPaletteClient.decodeStartupSnapshot(arguments));
  runApp(DesktopLyricAppearanceApp(client: client));
}

class DesktopLyricApp extends StatefulWidget {
  const DesktopLyricApp({super.key, this.binding});
  final DesktopLyricWindowBinding? binding;

  @override
  State<DesktopLyricApp> createState() => _DesktopLyricAppState();
}

class _DesktopLyricAppState extends State<DesktopLyricApp> {
  Timer? _paletteWarmup;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _paletteWarmup = Timer(const Duration(milliseconds: 900), () {
        if (mounted) unawaited(_palette.prewarm());
      });
    });
  }

  late final DesktopLyricPaletteHost _palette =
      DesktopLyricPaletteHost.instance;
  @override
  void dispose() {
    _paletteWarmup?.cancel();
    _palette.dispose();
    widget.binding?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UiLanguageScope(
        child: ValueListenableBuilder<UiLanguage>(
            valueListenable: uiLanguage,
            builder: (context, language, _) => ValueListenableBuilder(
                  valueListenable: DesktopLyricController.instance.isDarkMode,
                  builder: (context, isDarkMode, _) =>
                      ValueListenableProvider.value(
                    value: DesktopLyricController.instance.theme,
                    child: MaterialApp(
                      scrollBehavior: const AppScrollBehavior(),
                      debugShowCheckedModeBanner: false,
                      themeAnimationDuration: AppMotion.standard,
                      themeAnimationCurve: AppMotion.standardCurve,
                      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
                      theme: DesktopLyricTypography.theme(Brightness.light),
                      darkTheme: DesktopLyricTypography.theme(Brightness.dark),
                      localizationsDelegates:
                          GlobalMaterialLocalizations.delegates,
                      supportedLocales: supportedLocales,
                      locale: language.locale,
                      builder: (context, child) =>
                          ValueListenableBuilder<ThemeChangedMessage>(
                        valueListenable: DesktopLyricController.instance.theme,
                        child: AppPresentationHost(
                            child: UiLanguageTransition(
                                child: child ?? const SizedBox.shrink())),
                        builder: (context, colors, child) =>
                            DesktopLyricThemeTransition(
                          colors: colors,
                          child: child,
                          builder: (context, current, child) =>
                              Provider<ThemeChangedMessage>.value(
                                  value: current, child: child!),
                        ),
                      ),
                      home: DesktopLyricPaletteScope(
                          host: _palette, child: const DesktopLyricBody()),
                    ),
                  ),
                )));
  }

  final supportedLocales = const [
    Locale('zh'),
    Locale('en'),
    Locale('ja'),
    Locale('ko')
  ];
}
