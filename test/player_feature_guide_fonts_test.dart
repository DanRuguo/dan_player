import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/player_feature_guide.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _instructions = [
  '字体可统一设置，或分别设置中文、英文、日文、韩文；主界面、桌面歌词与任务栏歌词同步应用。',
  '英文、假名与韩文分别使用所选字体；共用汉字结合上下文和界面语言判断，缺字自动回退。',
];

void main() {
  setUpAll(() => ensureAppFontsLoaded(AppFontPolicy.defaults()));
  for (final language in UiLanguage.values) {
    testWidgets(
        '${language.code} font guide fits narrow large text and opens the existing setting',
        (tester) async {
      final previous = uiLanguage.value;
      addTearDown(() => uiLanguage.value = previous);
      uiLanguage.value = language;
      tester.view.physicalSize = const Size(520, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigated = <String>[];
      final policy = AppFontPolicy.defaults(language: language);
      await tester.pumpWidget(MaterialApp(
          theme: applyAppControlTheme(ThemeData(
              useMaterial3: true,
              fontFamily: policy.uiFamily,
              fontFamilyFallback: policy.fallback)),
          builder: (context, child) => UiLanguageScope(
              child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      disableAnimations: true,
                      textScaler: const TextScaler.linear(1.6)),
                  child: child!)),
          home: Scaffold(
              body: PlayerFeatureGuideDialog(onNavigate: navigated.add))));
      final section = find.byKey(const ValueKey('guide-section-fonts'));
      final header =
          find.descendant(of: section, matching: find.byType(ListTile)).first;
      await tester.ensureVisible(header);
      await tester.pumpAndSettle();
      await tester.tap(header);
      await tester.pumpAndSettle();
      for (final instruction in _instructions) {
        final translated = translateUi(instruction, language);
        if (language != UiLanguage.zh) expect(translated, isNot(instruction));
        final text = find.text(translated);
        expect(text, findsOneWidget);
        await tester.ensureVisible(text);
        await tester.pumpAndSettle();
        final rect = tester.getRect(text);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(520));
        expect(tester.takeException(), isNull);
      }
      final link = find.byKey(const ValueKey('guide-font-settings'));
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(navigated, ['/settings?section=appearance&setting=font']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
