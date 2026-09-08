import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/page/now_playing_page/component/equalizer_dialog.dart';
import 'package:dan_player/page/settings_page/check_update.dart';
import 'package:dan_player/page/settings_page/other_settings.dart';
import 'package:dan_player/page/settings_page/theme_picker_dialog.dart';
import 'package:dan_player/page/settings_page/theme_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/src/rust/api/installed_font.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:dan_player/update/update_service.dart';
import 'package:dan_player/utils.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github/github.dart' show Release;
import 'package:provider/provider.dart';

class _EqualizerPlayback extends Fake implements PlaybackService {
  @override
  int eqEditRevision = 0;
  @override
  final eqEnabled = ValueNotifier(false);
  final _gains = List<double>.filled(10, 0);
  bool acceptsEnable = true;

  @override
  List<double> get eqGains => List.of(_gains);

  @override
  bool setEqEnabled(bool enabled) {
    if (!acceptsEnable) return false;
    eqEnabled.value = enabled;
    return true;
  }

  @override
  void setEqBandGain(int band, double gain) => _gains[band] = gain;

  @override
  void applyEqGains(List<double> gains) => _gains.setAll(0, gains);
}

void main() {
  late BuildContext pageContext;
  final bubble = find.byKey(const ValueKey('app-notice-bubble'));

  Future<void> mount(WidgetTester tester, double scale,
      {Widget? content}) async {
    tester.view.physicalSize = const Size(507, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: ThemeProvider.instance,
      child: MaterialApp(
        // Match the Windows player. Android selection handles can otherwise
        // float over dialog actions after a text field is scrolled offscreen.
        theme: ThemeData(platform: TargetPlatform.windows),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: AppPresentationHost(child: child!),
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(8, 48, 8, 8),
            child: AppContentRegion(
              child: Builder(builder: (context) {
                pageContext = context;
                return SizedBox.expand(
                  child: content == null
                      ? null
                      : Align(alignment: Alignment.topCenter, child: content),
                );
              }),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    addTearDown(() async => tester.pumpWidget(const SizedBox()));
  }

  void expectActionAboveNotice(WidgetTester tester, String label) {
    final action = find.text(label);
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.getRect(action).bottom, lessThan(tester.getRect(bubble).top));
    expect(tester.takeException(), isNull);
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('theme picker keeps confirm and cancel above notice at $scale',
        (tester) async {
      await mount(tester, scale);
      var result = showAppDialog<Color>(
        context: pageContext,
        builder: (_) => const ThemePickerDialog(),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
          isTrue);
      final wheel =
          tester.widget<ColorWheelPicker>(find.byType(ColorWheelPicker));
      wheel.onChanged(const Color(0xFF993366));
      await tester.pump();
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('theme-hex-input')))
              .controller!
              .text,
          '#993366');
      await tester.enterText(
          find.byKey(const ValueKey('theme-hex-input')), '#336699');
      await tester.pumpAndSettle();
      showAppNotice('颜色将在确认后应用，取消会保留原主题。');
      await tester.pumpAndSettle();
      expectActionAboveNotice(tester, '确定');
      expectActionAboveNotice(tester, '取消');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(await result, const Color(0xFF336699));

      result = showAppDialog<Color>(
        context: pageContext,
        builder: (_) => const ThemePickerDialog(),
      );
      await tester.pumpAndSettle();
      expectActionAboveNotice(tester, '取消');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('equalizer keeps controls and completion usable at $scale',
        (tester) async {
      expect(PlayService.isInitialized, isFalse);
      final playback = _EqualizerPlayback();
      addTearDown(playback.eqEnabled.dispose);
      await mount(tester, scale);
      final result = showAppDialog<void>(
        context: pageContext,
        builder: (_) => EqualizerDialog(playbackService: playback),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
          isTrue);
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(playback.eqEnabled.value, isTrue);

      final preset = find.byType(DropdownMenu<String>);
      await tester.ensureVisible(preset);
      await tester.pumpAndSettle();
      await tester.tap(preset);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('流行').last);
      await tester.tap(find.text('流行').last);
      await tester.pumpAndSettle();
      expect(playback.eqGains.first, -1.6);
      tester.widget<Slider>(find.byType(Slider).first).onChanged!(3);
      await tester.pumpAndSettle();
      expect(playback.eqGains.first, 3);
      expect(find.text('自定义'), findsOneWidget);

      showAppNotice('均衡器设置已应用，换歌后继续保持。');
      await tester.pumpAndSettle();
      expectActionAboveNotice(tester, '完成');
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await result;
      expect(find.byType(EqualizerDialog), findsNothing);
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unsupported EQ reports failure without hiding completion',
      (tester) async {
    final playback = _EqualizerPlayback()..acceptsEnable = false;
    addTearDown(playback.eqEnabled.dispose);
    await mount(tester, 2);
    showAppDialog<void>(
      context: pageContext,
      builder: (_) => EqualizerDialog(playbackService: playback),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(playback.eqEnabled.value, isFalse);
    expect(find.text('当前输出模式不支持均衡器'), findsOneWidget);
    expectActionAboveNotice(tester, '完成');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.byType(EqualizerDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('lyric API validation and cancel survive notice at $scale',
        (tester) async {
      final settings = AppSettings.instance;
      final previous = settings.lyricApiUrl;
      settings.lyricApiUrl = null;
      addTearDown(() => settings.lyricApiUrl = previous);
      await mount(tester, scale, content: const LyricApiEditor());
      await tester.tap(find.text('设置接口'));
      await tester.pumpAndSettle();
      final editor = find.byWidgetPredicate((widget) =>
          widget is TextField && widget.decoration?.labelText == '接口地址');
      await tester.enterText(editor, 'not-an-http-url');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 http 或 https 接口地址'), findsOneWidget);
      showAppNotice('请核对接口地址后再保存。', duration: const Duration(seconds: 30));
      await tester.pumpAndSettle();
      // Host notifications rebuild the dialog frame but must not erase the
      // active form's validation state or its pending text edit.
      expect(find.text('请输入 http 或 https 接口地址'), findsOneWidget);
      expect(
          tester.widget<TextField>(editor).controller!.text, 'not-an-http-url');
      expectActionAboveNotice(tester, '保存');
      expectActionAboveNotice(tester, '取消');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(settings.lyricApiUrl, isNull,
          reason: 'Validation/cancel must not persist a partial API edit');
      expect(tester.takeException(), isNull);
    });

    testWidgets('font list and cancel remain reachable with notice at $scale',
        (tester) async {
      final theme = ThemeProvider.instance;
      final previous = theme.fontFamily;
      theme.changeFontFamily('很长的当前字体名称用于验证标题可以滚动而不是挤占取消按钮' * 3);
      addTearDown(() => theme.changeFontFamily(previous));
      final fonts = [
        InstalledFont(path: 'not-opened-long.ttf', fullName: '很长的已安装字体名称' * 6),
        const InstalledFont(path: 'not-opened-selected.ttf', fullName: '测试字体乙'),
      ];
      await mount(tester, scale);
      var result = showAppDialog<InstalledFont>(
        context: pageContext,
        builder: (_) => FontSelectorDialog(installedFont: fonts),
      );
      await tester.pumpAndSettle();
      showAppNotice('选择字体不会修改字体文件。', duration: const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expectActionAboveNotice(tester, '取消');
      await tester.scrollUntilVisible(
        find.text('测试字体乙'),
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('font-selector-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('测试字体乙'));
      await tester.pumpAndSettle();
      expect(await result, fonts[1]);
      result = showAppDialog<InstalledFont>(
        context: pageContext,
        builder: (_) => FontSelectorDialog(installedFont: fonts),
      );
      await tester.pumpAndSettle();
      expectActionAboveNotice(tester, '取消');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'update details and actions stay bounded above notice at $scale',
        (tester) async {
      await mount(tester, scale);
      final update = AvailableUpdate(
        release: Release(
          tagName: 'v26.0.4',
          name: 'Dan Player 很长的更新版本说明标题',
          body: List.filled(35, '### 更新内容\n\n新增功能和修复说明。').join('\n\n'),
          publishedAt: DateTime(2026, 8, 30),
          htmlUrl:
              'https://github.com/DanRuguo/dan_player/releases/tag/v26.0.4',
        ),
        version: const AppVersion(26, 0, 4),
      );
      final result = showAppDialog<void>(
        context: pageContext,
        builder: (_) => NewestUpdateView(update: update),
      );
      await tester.pumpAndSettle();
      showAppNotice('请先阅读更新说明，再选择下载或稍后处理。',
          duration: const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expectActionAboveNotice(tester, '稍后');
      final details = tester
          .widget<SingleChildScrollView>(
              find.byKey(const ValueKey('update-details-scroll')))
          .controller!;
      expect(details.position.maxScrollExtent, greaterThan(100));
      details.jumpTo(details.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('打开发布页'));
      await tester.pumpAndSettle();
      expect(find.text('打开发布页').hitTestable(), findsOneWidget);
      expect(find.text('忽略此版本'), findsOneWidget);
      expectActionAboveNotice(tester, '稍后');
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      await result;
      expect(find.byType(NewestUpdateView), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
