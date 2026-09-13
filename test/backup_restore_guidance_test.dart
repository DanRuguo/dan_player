import 'package:dan_player/data/backup_selection.dart';
import 'package:dan_player/page/settings_page/backup_selection_dialog.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final language in UiLanguage.values) {
    testWidgets(
        'first restore explains absent music and resources ${language.code}',
        (tester) async {
      final old = uiLanguage.value;
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = old);
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(UiLanguageScope(
          child: MaterialApp(
              home: Scaffold(
        body: BackupSelectionDialog(
            restoring: true,
            firstUse: true,
            contents: const BackupContents(
                components: {BackupComponent.library}, musicFolders: [])),
      ))));
      await tester.pumpAndSettle();
      expect(find.text(ui('首次迁移建议选择包含音乐和播放器资料的完整备份，并恢复全部内容；也可以按需选择。')),
          findsOneWidget);
      expect(
          find.text(
              ui('未恢复全部音乐：索引不会包含音频本身。原路径不可用的歌曲无法播放，之后可导入音乐或修复路径；已有封面缓存仍可显示。')),
          findsOneWidget);
      expect(find.text(ui('未选择完整缓存资源：随其他资料附带的封面仍可恢复；缺少的封面和歌词需要重新读取或获取。')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('backup-component-resources')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('full selection removes missing music and cache notices',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BackupSelectionDialog(
      restoring: true,
      firstUse: true,
      contents: const BackupContents(components: {
        ...BackupComponent.values
      }, musicFolders: [
        BackupMusicFolder(id: 'one', name: 'Music', songCount: 1, bytes: 100),
      ]),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ui('全部内容')));
    await tester.pumpAndSettle();
    expect(
        find.text(
            ui('未恢复全部音乐：索引不会包含音频本身。原路径不可用的歌曲无法播放，之后可导入音乐或修复路径；已有封面缓存仍可显示。')),
        findsNothing);
    expect(find.text(ui('未选择完整缓存资源：随其他资料附带的封面仍可恢复；缺少的封面和歌词需要重新读取或获取。')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
}
