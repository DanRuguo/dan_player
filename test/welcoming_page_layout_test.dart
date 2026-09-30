import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/welcoming_page.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
  });

  testWidgets(
      'library setup centers its content and remains usable when narrow',
      (tester) async {
    final original = AppSettings.instance.onboardingCompleted;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel, (_) async => 'build/test-data/welcome-layout');
    AppSettings.instance.onboardingCompleted = true;
    addTearDown(() async {
      AppSettings.instance.onboardingCompleted = original;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final boundary = GlobalKey();
    Future<void> render(String name) async {
      const output = String.fromEnvironment('DAN_WELCOME_RENDER');
      if (output.isEmpty) return;
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
        try {
          final bytes =
              (await image.toByteData(format: drawing.ImageByteFormat.png))!
                  .buffer
                  .asUint8List();
          await Directory(output).create(recursive: true);
          await File(path.join(output, '$name.png')).writeAsBytes(bytes);
        } finally {
          image.dispose();
        }
      });
    }

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 768);
    await tester.pumpWidget(UiLanguageScope(
        child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                theme: ThemeData(fontFamily: danEmbeddedFontFamily),
                home: const WelcomingPage()))));
    await tester.pump(const Duration(milliseconds: 500));
    final card = find.byKey(const ValueKey('welcome-library-card'));
    expect(card, findsOneWidget);
    expect(tester.getCenter(card).dy, closeTo(408, 1));
    expect(tester.getSize(card).width, lessThanOrEqualTo(560));
    expect(find.text(ui('添加文件夹')), findsOneWidget);
    expect(find.text(ui('从备份恢复')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await render('welcome-wide');

    tester.view.physicalSize = const Size(320, 560);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getSize(card).width, lessThanOrEqualTo(288));
    await tester.ensureVisible(find.text(ui('从备份恢复')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await render('welcome-narrow');
  });
}
