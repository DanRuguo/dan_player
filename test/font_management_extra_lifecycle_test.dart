import 'dart:async';

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/font_preview_loader.dart';
import 'package:dan_player/font/app_font_manager.dart';
import 'package:dan_player/page/settings_page/font_management_dialog.dart';
import 'package:dan_player/page/settings_page/font_selector_dialog.dart';
import 'package:dan_player/src/rust/api/installed_font.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _first = InstalledFont(path: 'qa-first.ttf', fullName: 'First preview');
const _next = InstalledFont(path: 'qa-next.ttf', fullName: 'Next preview');

Widget _host(Widget Function(BuildContext) dialog) => MaterialApp(
    theme: ThemeData(
        fontFamily: danEmbeddedFontFamily,
        fontFamilyFallback: danFontFamilyFallback),
    home: Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () =>
                    showDialog<void>(context: context, builder: dialog),
                child: const Text('Open')))));

void main() {
  setUpAll(() => ensureAppFontsLoaded(AppFontPolicy.defaults()));

  testWidgets('enumeration during management exit cannot open another dialog',
      (tester) async {
    final fonts = Completer<List<InstalledFont>?>();
    final manager = AppFontManager(load: (_) async {});
    addTearDown(manager.dispose);
    var enumerations = 0;
    await tester.pumpWidget(_host((_) => FontManagementDialog(
        manager: manager,
        getFonts: () {
          enumerations++;
          return fonts.future;
        })));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('font-slot-ko')));
    await tester.tap(find.byKey(const ValueKey('font-slot-ko')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ui('选择已安装字体')));
    await tester.pumpAndSettle();
    expect(enumerations, 1);
    await tester.tap(find.text(ui('取消')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(FontManagementDialog), findsOneWidget,
        reason: 'The original route is still mounted in its real exit');
    fonts.complete([_first]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(FontSelectorDialog), findsNothing,
        reason: 'Cancelled enumeration must not acquire a new route');
    await tester.pumpAndSettle();
    expect(find.byType(FontManagementDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker exit releases pending preview before font registration',
      (tester) async {
    final size = Completer<int>();
    final checked = Completer<void>();
    final loaded = <InstalledFont>[];
    final loader = FontPreviewLoader(
        maximumAutomaticFonts: 1,
        maximumAutomaticBytes: 64,
        sizeOf: (font) {
          if (font == _first) {
            checked.complete();
            return size.future;
          }
          return Future.value(64);
        },
        load: (font) async => loaded.add(font));
    await tester.pumpWidget(_host((_) => FontSelectorDialog(
        installedFont: const [_first],
        currentFont: _first.fullName,
        loader: loader)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(checked.isCompleted, isTrue);
    await tester.tap(find.text(ui('取消')));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(FontSelectorDialog), findsOneWidget,
        reason: 'Preview leases must retire before disposal after exit');
    size.complete(64);
    await tester.pump();
    expect(loaded, isEmpty,
        reason: 'The closing route must not register an invisible font');
    await tester.pumpAndSettle();
    final next = loader.acquire(_next);
    await tester.pump();
    expect(await next.family, _next.fullName,
        reason: 'Cancelled previews preserve the automatic budget');
    expect(loaded, [_next]);
    next.release();
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden picker defers pending previews and resumes when visible',
      (tester) async {
    final size = Completer<int>();
    var checks = 0;
    final loaded = <InstalledFont>[];
    final loader = FontPreviewLoader(
        sizeOf: (_) => ++checks == 1 ? size.future : Future.value(64),
        load: (font) async => loaded.add(font));
    var visible = true;
    late StateSetter display;
    await tester
        .pumpWidget(_host((_) => StatefulBuilder(builder: (context, setState) {
              display = setState;
              return TickerMode(
                  enabled: visible,
                  child: FontSelectorDialog(
                      installedFont: const [_first],
                      currentFont: _first.fullName,
                      loader: loader));
            })));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(checks, 1);
    display(() => visible = false);
    await tester.pump();
    size.complete(64);
    await tester.pump();
    expect(loaded, isEmpty,
        reason: 'A hidden window has no demand for an uncached preview');
    display(() => visible = true);
    await tester.pumpAndSettle();
    expect(loaded, [_first]);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('font-selector-preview')))
            .style!
            .fontFamily,
        _first.fullName);
    await tester.tap(find.text(ui('取消')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
