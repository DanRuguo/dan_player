import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_typography.dart';
import 'desktop_lyric_theme_transition.dart';
import 'message.dart';
import 'app_input_theme.dart';
import 'app_scrollbar.dart';
import 'appearance_palette_bridge.dart';
import 'component/desktop_lyric_appearance_options.dart';
import 'component/desktop_lyric_taskbar_options.dart';
import 'ui_language.dart';

/// The native owned window already has its final bounds. This app never loads
/// lyrics, subscribes to stdin or initializes window_manager / user settings.
class DesktopLyricAppearanceApp extends StatelessWidget {
  const DesktopLyricAppearanceApp({super.key, required this.client});
  final DesktopLyricPaletteClient client;
  @override
  Widget build(BuildContext context) => UiLanguageScope(
        child: ListenableBuilder(
            listenable: client,
            builder: (context, _) => DesktopLyricThemeTransition(
                  // Reused native panels must start each presentation at the
                  // newest palette, including forced frames while still hidden.
                  key: ValueKey(client.presentationId),
                  colors: client.theme.value,
                  enabled: client.active,
                  builder: (context, colors, _) => _themedApp(context, colors),
                )),
      );

  Widget _themedApp(BuildContext context, ThemeChangedMessage colors) {
    final brightness =
        client.isDarkMode.value ? Brightness.dark : Brightness.light;
    final base = DesktopLyricTypography.theme(brightness);
    final scheme = base.colorScheme.copyWith(
        primary: Color(colors.primary),
        surface: Color(colors.surfaceContainer),
        surfaceContainer: Color(colors.surfaceContainer),
        onSurface: Color(colors.onSurface));
    final textTheme = base.textTheme.apply(
        fontFamily: client.fontFamily,
        fontFamilyFallback: client.fontFamilyFallback);
    return MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      debugShowCheckedModeBanner: false,
      // The explicit colour clock above already supplies each
      // intermediate theme; do not interpolate a second time.
      themeAnimationDuration: Duration.zero,
      theme: base.copyWith(
          colorScheme: scheme,
          inputDecorationTheme: appInputTheme(scheme),
          textTheme: textTheme,
          // The base theme's resolver closes over its blue seed;
          // changing only colorScheme does not update that closure.
          iconButtonTheme: IconButtonThemeData(
              style: base.iconButtonTheme.style!.copyWith(
                  overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.transparent;
            }
            if (states.contains(WidgetState.pressed)) {
              return scheme.primary.withValues(alpha: .12);
            }
            if (states.contains(WidgetState.hovered)) {
              return scheme.primary.withValues(alpha: .08);
            }
            if (states.contains(WidgetState.focused)) {
              return scheme.primary.withValues(alpha: .10);
            }
            return null;
          }))),
          // Tooltip consumes a complete style, not the surrounding
          // TextTheme. Pair its foreground with an explicit surface.
          tooltipTheme: base.tooltipTheme.copyWith(
              textStyle: textTheme.bodySmall!.copyWith(
                  color: scheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
              decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: scheme.onSurface.withValues(alpha: .12))))),
      locale: uiLanguage.value.locale,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: UiLanguage.values.map((e) => e.locale),
      builder: (context, child) => TickerMode(
          enabled: client.active,
          child: ExcludeFocus(
              excluding: !client.active,
              child: UiLanguageTransition(
                  key: ValueKey(client.presentationId),
                  child: child ?? const SizedBox.shrink()))),
      home: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                unawaited(client.close()),
          },
          child: Focus(
              autofocus: true,
              child: DesktopLyricAppearancePanel(controller: client))),
    );
  }
}

/// The same options/model as main-player settings, in an opaque own surface.
class DesktopLyricAppearancePanel extends StatelessWidget {
  const DesktopLyricAppearancePanel({super.key, required this.controller});
  final DesktopLyricPaletteClient controller;
  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final colors = Theme.of(context).colorScheme;
    final primary = colors.primary;
    final foreground = colors.onSurface;
    return ClipRRect(
      key: const ValueKey('desktop-appearance-rounded-surface'),
      borderRadius: BorderRadius.circular(16),
      child: Scaffold(
        key: const ValueKey('desktop-appearance-dialog'),
        backgroundColor: colors.surfaceContainer,
        body: SafeArea(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Symbols.palette, color: primary)),
                Expanded(
                    child: Text(ui('歌词外观'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: foreground))),
                IconButton(
                    key: const ValueKey('desktop-appearance-close'),
                    tooltip: ui('关闭歌词外观'),
                    onPressed: controller.close,
                    style: IconButton.styleFrom(
                            fixedSize: const Size(44, 44),
                            visualDensity: VisualDensity.standard,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap)
                        .copyWith(
                            // IconButton.color otherwise derives an onSurface ink
                            // at widget priority, above the current theme resolver.
                            overlayColor: Theme.of(context)
                                .iconButtonTheme
                                .style
                                ?.overlayColor),
                    color: foreground,
                    icon: const Icon(Symbols.close)),
              ])),
          Expanded(
              child: SingleChildScrollView(
            key: const ValueKey('desktop-appearance-scroll'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ValueListenableBuilder(
                  valueListenable: controller.layoutError,
                  builder: (context, error, _) => error == null
                      ? const SizedBox.shrink()
                      : Semantics(
                          liveRegion: true,
                          child: Text(error,
                              key: const ValueKey(
                                  'desktop-appearance-layout-error'),
                              style: TextStyle(color: foreground)))),
              ValueListenableBuilder(
                  valueListenable: controller.appearance,
                  builder: (context, appearance, _) => Column(children: [
                        DesktopLyricTaskbarOptions(
                            appearance: appearance,
                            onChanged: controller.appearance.update,
                            primaryColor: primary,
                            foregroundColor: foreground),
                        const SizedBox(height: 14),
                        DesktopLyricAppearanceOptions(
                            appearance: appearance,
                            onChanged: controller.appearance.update,
                            primaryColor: primary,
                            foregroundColor: foreground),
                      ])),
              ValueListenableBuilder(
                  valueListenable: controller.saveError,
                  builder: (context, error, _) => error == null
                      ? const SizedBox.shrink()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              Text(error,
                                  key: const ValueKey(
                                      'desktop-appearance-save-error'),
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error)),
                              TextButton(
                                  onPressed: controller.retrySave,
                                  style: TextButton.styleFrom(
                                      foregroundColor: primary),
                                  child: Text(ui('重试保存'))),
                            ])),
            ]),
          )),
        ])),
      ),
    );
  }
}
