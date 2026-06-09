import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/src/rust/api/utils.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:go_router/go_router.dart';
import 'package:dan_player/app_paths.dart' as app_paths;

class CreateIssueTile extends StatelessWidget {
  const CreateIssueTile({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      description: "报告问题",
      icon: Symbols.help,
      action: FilledButton.icon(
        onPressed: () => context.push(app_paths.SETTINGS_ISSUE_PAGE),
        label: const Text("创建问题"),
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
    submitBtnController.update(WidgetState.disabled, true);
    final issueBodyBuilder = StringBuffer();
    issueBodyBuilder
      ..writeln("## 描述")
      ..writeln(descEditingController.text)
      ..writeln("## 日志")
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
      showTextOnSnackBar("已打开 GitHub 问题页面");
    } catch (err, trace) {
      showTextOnSnackBar(err.toString());
      LOGGER.e(err, stackTrace: trace);
    }

    submitBtnController.update(WidgetState.disabled, false);
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Focus(
                    onFocusChange: HotkeysHelper.onFocusChanges,
                    child: TextField(
                      controller: titleEditingController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: "标题",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: FilledButton(
                    statesController: submitBtnController,
                    onPressed: createIssue,
                    child: const Text("报告问题"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Focus(
                onFocusChange: HotkeysHelper.onFocusChanges,
                child: TextField(
                  controller: descEditingController,
                  textAlignVertical: const TextAlignVertical(y: -1),
                  expands: true,
                  maxLines: null,
                  decoration: const InputDecoration(
                    hintText: "描述",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Focus(
                onFocusChange: HotkeysHelper.onFocusChanges,
                child: TextField(
                  controller: logEditingController,
                  textAlignVertical: const TextAlignVertical(y: -1),
                  expands: true,
                  maxLines: null,
                  decoration: const InputDecoration(
                    hintText: "日志",
                    helperText: "你可以随意修改日志内容。",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const Padding(padding: EdgeInsets.only(bottom: 96.0))
          ],
        ),
      ),
    );
  }
}
