import 'dart:convert';
import 'dart:io';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/settings_tile.dart';
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
    final pattern =
        RegExp(r'''\bui\(\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')''');
    for (final root in [
      'lib/component',
      'lib/page',
      'third_party/desktop_lyric/lib/component'
    ]) {
      for (final file in Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
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
