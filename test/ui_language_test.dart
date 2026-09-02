import 'dart:convert';
import 'dart:io';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/component/compact_lyric_view.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/player_shortcut_preferences.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:dan_player/page/settings_page/interface_settings.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:desktop_lyric/l10n/ui_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_desktop_integration.dart';

Widget _app(Widget child,
        {double scale = 1, Brightness brightness = Brightness.light}) =>
    UiLanguageScope(
        child: ValueListenableBuilder<UiLanguage>(
            valueListenable: uiLanguage,
            builder: (context, language, _) => MaterialApp(
                locale: language.locale,
                supportedLocales: UiLanguage.values.map((e) => e.locale),
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: ThemeData(
                    colorScheme: ColorScheme.fromSeed(
                        seedColor: Colors.teal, brightness: brightness)),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: UiLanguageTransition(child: child!)),
                home: Scaffold(body: child))));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    uiLanguage.value = UiLanguage.zh;
  });
  test('four languages, backward-compatible defaults and exact templates', () {
    expect(UiLanguage.values.map((e) => e.code), ['zh', 'en', 'ja', 'ko']);
    for (final value in [null, '', 0, 'fr', {}, true]) {
      expect(UiLanguage.parse(value), UiLanguage.zh);
    }
    for (final entry in uiCatalog.entries) {
      expect(entry.value, hasLength(3), reason: entry.key);
      final placeholders = RegExp(r'\{\d+\}')
          .allMatches(entry.key)
          .map((m) => m[0])
          .toList()
        ..sort();
      for (final target in entry.value) {
        expect(target.trim(), isNotEmpty, reason: entry.key);
        expect(
            RegExp(r'\{\d+\}').allMatches(target).map((m) => m[0]).toList()
              ..sort(),
            placeholders,
            reason: '${entry.key} -> $target');
      }
    }
    expect(
        translateUi('未收录的歌曲 😀 e\u0301', UiLanguage.en), '未收录的歌曲 😀 e\u0301');
    expect(
        translateUi('{0} / {1}', UiLanguage.en, ['{1}', '私の歌']), '{1} / 私の歌');
    expect(translateUi('显示主窗口', UiLanguage.en), 'Show main window');
  });

  test('every explicit UI template has translations', () {
    final missing = <String>{};
    final pattern = RegExp(
        r'''\b(?:ui|showTextOnSnackBar)\(\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')''');
    for (final root in [
      'lib',
      'third_party/desktop_lyric/lib',
    ]) {
      for (final file in Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) =>
              f.path.endsWith('.dart') &&
              !f.path.contains(
                  '${Platform.pathSeparator}l10n${Platform.pathSeparator}') &&
              !f.path.endsWith('.g.dart'))) {
        for (final match in pattern.allMatches(file.readAsStringSync())) {
          final literal = match[1]!;
          final source = literal.startsWith('"')
              ? jsonDecode(literal) as String
              : literal
                  .substring(1, literal.length - 1)
                  .replaceAll(r"\'", "'")
                  .replaceAll(r'\n', '\n');
          if (!uiCatalog.containsKey(source)) {
            missing.add('${file.path}: $source');
          }
        }
      }
    }
    expect(missing, isEmpty);
  });

  test('unified detail and album browser labels translate in every language',
      () {
    const keys = {
      '清除搜索',
      '未找到匹配的歌曲',
      '浏览全部专辑 · {0}',
    };
    for (final key in keys) {
      expect(uiCatalog[key], hasLength(3), reason: key);
      for (final language in UiLanguage.values.skip(1)) {
        expect(translateUi(key, language, [23]), isNot(key),
            reason: '$key/$language');
      }
    }
  });

  test('enum-backed visible labels have translations', () {
    final keys = <String>{
      for (final field in AudioSortField.values) ...[
        field.label,
        field.group,
        if (field.note != null) field.note!,
      ],
      audioSortMissingValueNote,
      for (final kind in MusicCategoryKind.values) ...[
        kind.label,
        kind.countLabel,
        kind.unknownLabel,
      ],
      for (final scene in BackgroundScene.values) scene.label,
      for (final source in BackgroundSource.values) source.label,
      for (final shortcut in playerShortcutDefinitions) shortcut.description,
      for (final status in const [
        WindowBackdropStatus(available: true, effect: 'blur'),
        WindowBackdropStatus(reason: 'disabled'),
        WindowBackdropStatus(reason: 'transparency_disabled'),
        WindowBackdropStatus(reason: 'high_contrast'),
        WindowBackdropStatus(reason: 'energy_saver'),
        WindowBackdropStatus(reason: 'initializing'),
        WindowBackdropStatus(reason: 'unavailable'),
      ])
        status.description,
      '桌面歌词',
      '快捷键',
      '备份本地缓存？',
      '备份会保存曲库索引、歌单、歌词来源、播放统计、设置和缓存资源，不会复制音乐文件。\n\n在另一台电脑恢复前，请先准备包含尽量相同歌曲的文件夹，并先让 Dan Player 导入该文件夹；文件夹名称和位置可以不同。',
      '恢复本地缓存？',
      '请先在这台电脑准备包含尽量相同歌曲的文件夹，并让 Dan Player 完成导入。恢复时会按扫描根内的相对位置、文件名和大小匹配歌曲；无法可靠匹配的信息会跳过并在完成后统计，不会保留旧电脑上失效的绝对路径。',
      '替换当前缓存？',
      '替换已有缓存？',
      '目标位置已识别为 Dan Player 缓存：\n{0}\n\n恢复会在下次启动前进行原子替换；若替换失败，原缓存会保留。是否继续？',
      '退出播放器',
      '正在处理…',
      '备份到文件',
      '恢复已准备完成，但未能自动退出；请手动退出并重新打开播放器',
      '恢复已准备完成；请退出并重新打开播放器',
      '无法连接播放器，外观尚未保存。',
      '外观保存失败，当前会话仍然生效。',
      '歌词窗口布局调整失败，请重新切换显示模式。',
      '歌词窗口布局调整失败，已保留原窗口；请重新切换显示模式重试。',
    };
    for (final key in keys) {
      expect(uiCatalog[key], hasLength(3), reason: key);
      for (final language in UiLanguage.values.skip(1)) {
        expect(translateUi(key, language), isNot(key), reason: key);
      }
    }
  });

  test('managed background failures shown in settings are translated', () {
    final source = File('lib/background_image_store.dart').readAsStringSync();
    final pattern = RegExp(
        r'''BackgroundImageException\(\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')''');
    final keys = <String>{
      for (final match in pattern.allMatches(source))
        match[1]!.startsWith('"')
            ? jsonDecode(match[1]!) as String
            : match[1]!
                .substring(1, match[1]!.length - 1)
                .replaceAll(r"\'", "'")
                .replaceAll(r'\n', '\n'),
    };
    expect(keys, isNotEmpty);
    for (final key in keys) {
      expect(uiCatalog[key], hasLength(3), reason: key);
      for (final language in UiLanguage.values.skip(1)) {
        expect(translateUi(key, language), isNot(key), reason: key);
      }
    }
  });

  testWidgets('composed sort footer translates each catalogued line',
      (tester) async {
    const first = '缺失或不适用的信息始终排在最后；相同值保留原有次序。';
    const second = '使用本地文件的修改时间；联网曲目没有此信息。';
    uiLanguage.value = UiLanguage.en;
    await tester.pumpWidget(_app(AppSortButton<int>(
      value: 0,
      direction: SortDirection.ascending,
      options: const [
        AppSortOption(value: 0, label: '修改时间', icon: Icons.edit_calendar),
      ],
      onChanged: (_) {},
      onDirectionChanged: (_) {},
      helpText: '$first\n$second',
    )));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(find.text('${ui(first)}\n${ui(second)}'), findsOneWidget);
    expect(find.text('$first\n$second'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact lyric application states follow interface language',
      (tester) async {
    uiLanguage.value = UiLanguage.ja;
    await tester.pumpWidget(_app(const CompactLyricView(trackIdentity: null)));
    await tester.pumpAndSettle();
    expect(find.text(ui('选择歌曲，开始聆听')), findsOneWidget);
    expect(find.text(ui('这里会显示当前歌词')), findsOneWidget);
    expect(find.text('选择歌曲，开始聆听'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'language changes preserve editor, focus, scroll and widget state',
      (tester) async {
    final field = TextEditingController(text: '結想は花となる · Hello 😀 {1}');
    final focus = FocusNode();
    final scroll = ScrollController();
    await tester.pumpWidget(
        _app(_PersistentEditor(field: field, focus: focus, scroll: scroll)));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(_PersistentEditor));
    focus.requestFocus();
    scroll.jumpTo(160);
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(_PersistentEditor)), same(state));
      expect(field.text, '結想は花となる · Hello 😀 {1}');
      expect(focus.hasFocus, isTrue);
      expect(scroll.offset, 160);
      expect(find.text(translateUi('编辑歌曲信息', language)), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    field.dispose();
    focus.dispose();
    scroll.dispose();
  });

  for (final language in UiLanguage.values) {
    for (final width in [320.0, 507.0, 1000.0]) {
      testWidgets('interface settings fit ${language.code} / $width at 200%',
          (tester) async {
        uiLanguage.value = language;
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(_app(
            SingleChildScrollView(
                child: InterfaceSettings(persist: () async {})),
            scale: 2));
        await tester.pumpAndSettle();
        expect(find.text(translateUi('界面语言', language)), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'language controls save without native window capture and report errors',
      (tester) async {
    var saves = 0;
    // The production group supplies the scroll viewport; this isolated save
    // fixture must retain that contract as the settings gain descriptive rows.
    await tester.pumpWidget(
        _app(SingleChildScrollView(child: InterfaceSettings(persist: () async {
      saves++;
      throw StateError('test');
    }))));
    await tester.tap(find.byKey(const ValueKey('ui-language-en')));
    await tester.pumpAndSettle();
    expect(uiLanguage.value, UiLanguage.en);
    expect(saves, 1);
    final error = find.text(translateUi('保存界面设置失败；本次会话仍然有效。', UiLanguage.en));
    await tester.ensureVisible(error);
    await tester.pumpAndSettle();
    expect(error, findsOneWidget);
    expect(AppSettings.instance.uiLayout.value.toMap(), isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  test('helper init and live messages change language without media changes',
      () {
    final helper = DesktopLyricController.detached();
    helper.applyInitialState(const InitArgsMessage(
        false, '曲名', 'artist', 'album', false, 0, 0, 0,
        language: 'ja'));
    expect(uiLanguage.value, UiLanguage.ja);
    final before = helper.nowPlaying.value;
    for (final language in UiLanguage.values) {
      helper.handleMessage(UiLanguageMessage(language.code).buildMessageJson());
      expect(uiLanguage.value, language);
      expect(helper.nowPlaying.value, same(before));
    }
    helper.dispose();
  });

  for (final language in UiLanguage.values) {
    testWidgets('notice severity remains an error in ${language.code}',
        (tester) async {
      uiLanguage.value = language;
      late BuildContext noticeContext;
      await tester.pumpWidget(_app(Builder(builder: (context) {
        noticeContext = context;
        return const SizedBox.shrink();
      })));
      showTextOnSnackBar('更新歌曲信息失败：{0}',
          arguments: ['曲名 😀 {1}'], context: noticeContext);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text(translateUi('更新歌曲信息失败：{0}', language, ['曲名 😀 {1}'])),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test(
      'native menu labels follow language without resending playback or window actions',
      () async {
    final rig = DesktopTestRig();
    await rig.initialize();
    await flushDesktopEvents();
    final updates =
        rig.native.calls.where((c) => c.$1 == 'updatePlayback').length;
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      await flushDesktopEvents();
      final labels = rig.native.calls
          .lastWhere((c) => c.$1 == 'configure')
          .$2!['labels'] as Map;
      expect(labels['showMain'], translateUi('显示主窗口', language));
      expect(labels['showMini'], translateUi('迷你播放器', language));
      expect(labels['previous'], translateUi('上一首', language));
      expect(labels['play'], translateUi('播放', language));
      expect(labels['pause'], translateUi('暂停', language));
      expect(labels['next'], translateUi('下一首', language));
      expect(labels['lyrics'], translateUi('桌面歌词', language));
      expect(labels['exit'], translateUi('退出 Dan Player', language));
      expect(rig.native.calls.where((c) => c.$1 == 'updatePlayback').length,
          updates);
      expect(rig.playback.actions, isEmpty);
      expect(rig.window.showModes, isEmpty);
    }
    await rig.dispose();
  });
}

class _PersistentEditor extends StatefulWidget {
  const _PersistentEditor(
      {required this.field, required this.focus, required this.scroll});
  final TextEditingController field;
  final FocusNode focus;
  final ScrollController scroll;
  @override
  State<_PersistentEditor> createState() => _PersistentEditorState();
}

class _PersistentEditorState extends State<_PersistentEditor> {
  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Column(children: [
      AppDialogTitle(ui('编辑歌曲信息')),
      TextField(controller: widget.field, focusNode: widget.focus),
      SettingsTile(
          description: ui('界面语言'),
          action: Text(ui('设置')),
          icon: Icons.translate),
      Expanded(
          child: ListView(
              controller: widget.scroll,
              children: List.generate(
                  60, (i) => SizedBox(height: 40, child: Text('$i')))))
    ]);
  }
}
