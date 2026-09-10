import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/src/rust/api/utils.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:go_router/go_router.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:desktop_lyric/ui_language.dart';

class CreateIssueTile extends StatelessWidget {
  const CreateIssueTile({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsTile(
      description: ui("报告问题"),
      icon: Symbols.help,
      action: FilledButton.icon(
        onPressed: () => context.push(app_paths.SETTINGS_ISSUE_PAGE),
        label: Text(ui("创建问题")),
        icon: const Icon(Symbols.help),
      ),
    );
  }
}

class SettingsIssuePage extends StatefulWidget {
  const SettingsIssuePage({super.key});

  @override
  State<SettingsIssuePage> createState() => _SettingsIssuePageState();
}

class _SettingsIssuePageState extends State<SettingsIssuePage> {
  final titleEditingController = TextEditingController();
  final descEditingController = TextEditingController();
  final logEditingController = TextEditingController();
  final submitBtnController = WidgetStatesController();

  Future<void> createIssue() async {
    if (!mounted || submitBtnController.value.contains(WidgetState.disabled)) {
      return;
    }
    submitBtnController.update(WidgetState.disabled, true);
    final issueBodyBuilder = StringBuffer();
    issueBodyBuilder
      ..writeln(ui("## 描述"))
      ..writeln(descEditingController.text)
      ..writeln(ui("## 日志"))
      ..writeln("```")
      ..writeln(logEditingController.text)
      ..writeln("```");

    try {
      final issueUri = Uri.https(
        "github.com",
        "/${AppSettings.githubOwner}/${AppSettings.githubRepository}/issues/new",
        {
          "title": titleEditingController.text,
          "body": issueBodyBuilder.toString(),
        },
      );
      await launchInBrowser(uri: issueUri.toString());
      if (mounted) showTextOnSnackBar("已打开 GitHub 问题页面");
    } catch (err, trace) {
      if (mounted) showTextOnSnackBar(err.toString());
      LOGGER.e(err, stackTrace: trace);
    }

    if (mounted) submitBtnController.update(WidgetState.disabled, false);
  }

  @override
  void initState() {
    super.initState();
    final logStrBuf = StringBuffer();
    for (final event in LOGGER_MEMORY.buffer) {
      for (var line in event.lines) {
        logStrBuf.writeln(line);
      }
    }
    logEditingController.text = logStrBuf.toString();
  }

  @override
  void dispose() {
    titleEditingController.dispose();
    descEditingController.dispose();
    logEditingController.dispose();
    submitBtnController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AppEntrance(
          identity: 'issue-form',
          child: LayoutBuilder(builder: (context, constraints) {
            final stacked = constraints.maxWidth < 600 ||
                MediaQuery.textScalerOf(context).scale(14) > 20;
            final title = Focus(
              onFocusChange: HotkeysHelper.onFocusChanges,
              child: TextField(
                controller: titleEditingController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: ui("标题"),
                  border: AppShape.inputBorder,
                ),
              ),
            );
            final submit = FilledButton.icon(
              statesController: submitBtnController,
              onPressed: createIssue,
              icon: const Icon(Symbols.bug_report),
              label: Text(ui("报告问题")),
            );
            final fieldHeight =
                ((constraints.maxHeight - (stacked ? 256 : 176)) / 2)
                    .clamp(168.0, double.infinity);
            Widget editor(TextEditingController controller, String hint,
                    {String? helper}) =>
                SizedBox(
                  height: fieldHeight,
                  child: Focus(
                    onFocusChange: HotkeysHelper.onFocusChanges,
                    child: TextField(
                      controller: controller,
                      textAlignVertical: TextAlignVertical.top,
                      expands: true,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: ui(hint),
                        helperText: helper == null ? null : ui(helper),
                        helperMaxLines: 3,
                        border: AppShape.inputBorder,
                      ),
                    ),
                  ),
                );
            return SingleChildScrollView(
              key: const ValueKey('issue-form-scroll'),
              padding: const EdgeInsets.only(bottom: 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (stacked) ...[
                    title,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: submit),
                  ] else
                    Row(children: [
                      Expanded(child: title),
                      const SizedBox(width: 12),
                      submit,
                    ]),
                  const SizedBox(height: 12),
                  editor(descEditingController, '描述'),
                  const SizedBox(height: 12),
                  editor(logEditingController, '日志', helper: '你可以随意修改日志内容。'),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}
