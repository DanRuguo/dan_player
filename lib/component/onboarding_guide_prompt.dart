import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/player_feature_guide.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

Future<void> showOnboardingGuidePrompt(BuildContext context) async {
  final welcomeRoute = ModalRoute.of(context);
  final open = await showAppDialog<bool>(
      context: context, builder: (_) => const OnboardingGuidePrompt());
  if (open != true || !context.mounted || welcomeRoute?.isCurrent == false) {
    return;
  }
  await showPlayerFeatureGuide(context);
}

/// Reuses the existing guide; it has no separate completion setting or service.
class OnboardingGuidePrompt extends StatelessWidget {
  const OnboardingGuidePrompt({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AlertDialog(
        key: const ValueKey('onboarding-guide-prompt'),
        scrollable: true,
        title: AppDialogTitle(ui('特色操作指南')),
        content: SizedBox(
            width: 480,
            child: Text(ui('你可以在“设置 → 备份与恢复 → 特色操作指南”了解播放器的特色功能、快捷键和高级搜索。'))),
        actions: [
          AppDialogActions(children: [
            TextButton(
                key: const ValueKey('onboarding-guide-later'),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(ui('稍后阅读'))),
            FilledButton.icon(
                key: const ValueKey('onboarding-guide-open'),
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.menu_book_outlined),
                label: Text(ui('打开操作指南'))),
          ]),
        ]);
  }
}
