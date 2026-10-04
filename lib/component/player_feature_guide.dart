import 'dart:math' as math;

import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/page/search_page/search_page.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PlayerFeatureGuideSettings extends StatelessWidget {
  const PlayerFeatureGuideSettings({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsSurface(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsHeader(
            title: ui('特色操作指南'),
            icon: Icons.menu_book_outlined,
            subtitle: ui('队列、书签、歌词、文件夹与统计的常用操作；设置和已有说明可直接打开。')),
        const SizedBox(height: 12),
        Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton.icon(
                key: const ValueKey('open-player-feature-guide'),
                onPressed: () => showPlayerFeatureGuide(context),
                icon: const Icon(Icons.menu_book_outlined),
                label: Text(ui('打开操作指南')))),
      ],
    ));
  }
}

Future<void> showPlayerFeatureGuide(BuildContext context) =>
    showAppDialog<void>(
        context: context, builder: (_) => const PlayerFeatureGuideDialog());

/// Links use the existing setting IDs and existing help dialogs. Opening this
/// guide does not initialize playback, inspect files or alter preferences.
class PlayerFeatureGuideDialog extends StatelessWidget {
  const PlayerFeatureGuideDialog({super.key, this.onNavigate});
  final ValueChanged<String>? onNavigate;

  void _setting(BuildContext context, String section, String setting) {
    final location = Uri(path: '/settings', queryParameters: {
      'section': section,
      'setting': setting,
    }).toString();
    _navigate(context, location);
  }

  void _navigate(BuildContext context, String location) {
    final navigate = onNavigate;
    if (navigate != null) {
      navigate(location);
      return;
    }
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(location);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AppDialogContent(
          width: 760,
          maxHeight: math.max(0, screen.height - 80),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogTitle(ui('特色操作指南')),
              const SizedBox(height: 12),
              Flexible(
                child: AppContentScrollbar(
                  builder: (context, controller) => SingleChildScrollView(
                    key: const ValueKey('player-feature-guide-scroll'),
                    controller: controller,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _section(
                            context,
                            'playlists',
                            '歌单与队列整理',
                            Icons.account_tree_outlined,
                            [
                              _paragraph(context, '歌单视图与导航'),
                              _text(
                                  '列表、圆形、矩形与树形共用同一份歌单。点击列表或封面进入歌单；树形点击展开，项目菜单可进入详情。视图与层级各自记住显示方式，封面追踪可在动画设置中关闭。'),
                              _paragraph(context, '自定义顺序与拖动'),
                              _text(
                                  '自定义排序：拖动歌曲或子歌单右侧的三个点，其他行会连续让位；点按三个点、右键或长按行可打开菜单。\n\n拖到子歌单的封面/名称区域并稍作停留，高亮后松开即可移入；也可通过菜单“移动到…”选择目标。\n\n名称等排序仅改变显示和播放次序，不覆盖自定义顺序；切回“自定义”即可继续拖动。\n\n顺序播放会按各层次序进入子歌单，播完再返回父歌单。Alt + ↑ / ↓ 可在自定义模式调序，Shift + F10 打开菜单。'),
                              _paragraph(context, '树形浏览'),
                              _text(
                                  '点击歌单或箭头展开、折叠；单击歌曲播放。同一歌单的歌曲按窗口宽度紧凑排列。\n\n右键、长按或 Shift + F10 打开项目菜单；自定义排序下按住卡片拖动，可调整顺序或移入歌单。\n\n方向键浏览层级，Home / End 跳到首尾；搜索保留所属歌单，清除搜索恢复展开状态。'),
                              _paragraph(context, '当前队列与筛选结果'),
                              _text(
                                  '歌曲菜单可插入下一首或加入队尾；队列中的移动、移除和排序不会改动原歌单。队列搜索结果可另存歌单或导出，保存的是点按时可见的顺序，重复引用也会保留。'),
                            ],
                            expanded: true),
                        _section(context, 'smart', '智能歌单与个人资料',
                            Icons.auto_awesome_outlined, [
                          _text(
                              '智能歌单按本地筛选规则生成歌曲；可以固定排序，也可以随机抽取并“换一批”。保存智能规则后，下次打开会重新求值；加入普通歌单则保留当前批次。每批不重复抽同一歌曲，不同批次可能重合。'),
                          const SizedBox(height: 8),
                          _text('评分、标签与个人备注属于播放器资料，可用于筛选和整理；它们不会改写音乐文件的原始标签。'),
                        ]),
                        _section(context, 'lyrics', '歌词阅读、练习与分享',
                            Icons.lyrics_outlined, [
                          _text(
                              '歌词菜单提供阅读、查找、选段练习与歌词卡片。阅读工具可调整字号和显示内容；查找结果可定位原句，练习选段使用 A-B 循环。歌词卡片可选择句子并导出 PNG，原歌曲和歌词不会被改写。'),
                          const SizedBox(height: 8),
                          _text(
                              '本地歌词和已缓存歌词优先；自动联网需要在设置中开启。手动搜索或选择歌词独立于自动联网开关，歌词校准与编辑可从歌词页现有菜单进入。'),
                          _link(context, 'guide-lyric-settings', '打开歌词体验设置',
                              () => _setting(context, 'lyrics', 'experience')),
                        ]),
                        _section(context, 'files', '导出与音频检查',
                            Icons.drive_file_move_outlined, [
                          _text(
                              'M3U8 导出保存歌曲路径引用；“导出音乐文件夹”会复制本地音频并生成相对路径歌单，适合搬到另一台设备。在线歌曲与 CUE 分轨会明确跳过；同一源文件只复制一次，歌单仍保留顺序和重复引用。原文件不移动、不转码。'),
                          const SizedBox(height: 8),
                          _text(
                              '歌词页“更多”中的本曲设置、响度与峰值分析、音频文件校验用于查看与调整当前歌曲。分析和校验只读取源文件；响度分析给出参考增益，不会自动改写音频。'),
                        ]),
                        _section(context, 'search', '高级搜索',
                            Icons.manage_search_outlined, [
                          _text(
                              '字段、数值范围、OR 和排除条件可组合筛选本地音乐。完整语法、单位、未知资料的处理及示例沿用“本地筛选用法”，不额外联网。'),
                          const SizedBox(height: 8),
                          SelectableText(
                              '(format:flac | rating:>=4) -filename:live',
                              key: const ValueKey('guide-search-example'),
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.primary)),
                          _link(context, 'guide-local-search-help', '打开本地筛选用法',
                              () => showLocalSearchHelp(context)),
                        ]),
                        _section(context, 'shortcuts', '快捷键',
                            Icons.keyboard_outlined, [
                          _text(
                              '查看当前快捷键可读取你实际保存的组合；默认 Space 播放或暂停，Ctrl + ← / → 切歌，← / → 定位 5 秒，Ctrl + M 切换迷你播放器，F11 全屏。输入文字时不会抢走输入按键，控件优先处理自己的键盘操作。'),
                          _link(context, 'guide-current-shortcuts', '查看当前快捷键',
                              () => HotkeysHelper.showShortcuts(context)),
                          _link(context, 'guide-shortcut-settings', '自定义快捷键',
                              () => _setting(context, 'desktop', 'shortcuts')),
                        ]),
                        _section(context, 'appearance', '主题、桌面与任务栏',
                            Icons.palette_outlined, [
                          _text(
                              '主题、桌面歌词、任务栏歌词和性能选项已有各自说明；下面直接定位到对应设置。桌面歌词与任务栏歌词互斥，任务栏空区不足时会隐藏显示。'),
                          _link(context, 'guide-theme-settings', '打开主题设置',
                              () => _setting(context, 'appearance', 'theme')),
                          _link(
                              context,
                              'guide-desktop-settings',
                              '打开桌面与任务栏设置',
                              () =>
                                  _setting(context, 'desktop', 'integration')),
                          _link(context, 'guide-animation-settings', '打开动画设置',
                              () => _setting(context, 'effects', 'animation')),
                        ]),
                        _section(context, 'queue', '播放队列与停止目标',
                            Icons.queue_music_outlined, [
                          _text(
                              '歌词页打开播放队列，歌曲菜单可插入下一首或加入队尾；队列中的调整不会改动原歌单。正在播放的歌曲保留在队列中。'),
                          const SizedBox(height: 8),
                          _text(
                              '“更多 → 睡眠定时”可设置倒计时、播完本曲、按当前播放数量或播完队列后停止。倒计时与队列停止目标可叠加、独立取消；队列状态会提示目标是否仍有效。'),
                          const SizedBox(height: 8),
                          _text('按数量包含本曲，确认时固定目标条目；重排后仍止于该条，删除目标会取消该停止目标。'),
                          _link(context, 'guide-session-settings', '打开会话恢复设置',
                              () => _setting(context, 'library', 'session')),
                        ]),
                        _section(context, 'bookmarks', '书签与播放记忆',
                            Icons.bookmarks_outlined, [
                          _text(
                              '播放本地歌曲时，在“歌词页 → 更多 → 播放书签”保存时间点或当前 A-B 区间。点时间书签定位，点区间书签恢复循环；可重命名或删除。'),
                          const SizedBox(height: 8),
                          _text(
                              '按曲记忆用于再次点选本地音频时续播，可仅用于长音频。自动下一首与循环仍从头开始；清除自动记忆不会删除手动书签。'),
                          _link(context, 'guide-resume-settings', '打开播放记忆设置',
                              () => _setting(context, 'library', 'resume')),
                        ]),
                        _section(context, 'lyric-display', '桌面与任务栏歌词',
                            Icons.desktop_windows_outlined, [
                          _text(
                              '在设置中开启桌面歌词或任务栏歌词，两种模式自动互斥，共用当前歌词。桌面歌词的外观面板可调整样式，也可切换到任务栏。'),
                          const SizedBox(height: 8),
                          _text(
                              '任务栏设置可选位置、切换空区、单/双行、配色与独立描边。歌词文字保持点击穿透；播放/暂停与可选下一首只有按钮区域接收点击。安全空间不足时自动隐藏。'),
                          _link(
                              context,
                              'guide-desktop-lyric-settings',
                              '打开桌面歌词设置',
                              () => _setting(
                                  context, 'desktop', 'desktop-lyrics')),
                          _link(
                              context,
                              'guide-taskbar-lyric-settings',
                              '打开任务栏歌词设置',
                              () =>
                                  _setting(context, 'desktop', 'integration')),
                        ]),
                        _section(context, 'storage', '文件夹与缓存管理',
                            Icons.folder_copy_outlined, [
                          _text(
                              '文件夹页右键、长按或点更多，可备注、浏览、移动文件夹或查看占用。备注只改变显示名，真实名称与路径不变；缓存项有独立图标和标记。'),
                          const SizedBox(height: 8),
                          _text(
                              '移动确认后退出，下次启动先剪切并同步资料路径。同盘可直接移动，跨盘先校验再删除原文件，不覆盖已有目标。备份与恢复可按组件选择，缓存分类占用在统计页查看。'),
                          _link(context, 'guide-folder-page', '打开文件夹页',
                              () => _navigate(context, app_paths.FOLDERS_PAGE)),
                          _link(context, 'guide-backup-settings', '打开备份与恢复',
                              () => _setting(context, 'backup', 'backup')),
                        ]),
                        _section(context, 'statistics', '统计与资源监控',
                            Icons.insights_outlined, [
                          _text(
                              '统计页查看听歌趋势、排行、音乐与缓存占用。缓存类别用易读名称显示，悬停查看真实路径；文件夹菜单可直达对应占用统计。'),
                          const SizedBox(height: 8),
                          _text(
                              '资源监控只采样播放器自身 CPU、GPU 与内存，可选数字、折线或条形和刷新间隔。离开监控区域或隐藏窗口即停止采样；不可用数据会明确标示。'),
                          _link(
                              context,
                              'guide-cache-statistics',
                              '打开缓存占用统计',
                              () => _navigate(
                                  context,
                                  Uri(
                                          path: app_paths.STATISTICS_PAGE,
                                          queryParameters: {'section': 'cache'})
                                      .toString())),
                          _link(
                              context,
                              'guide-resource-settings',
                              '打开资源监控设置',
                              () => _setting(
                                  context, 'backup', 'process-resources')),
                        ]),
                        _section(
                            context, 'sound', '速度、音高与音量', Icons.tune_outlined, [
                          _text(
                              '播放设置中，变速保持音高，升降调独立改变音高而不改变速度与歌词时间；1× 和原调可复位。本曲播放设置可保存该歌曲的偏好。'),
                          const SizedBox(height: 8),
                          _text(
                              '歌词页“更多 → 均衡器”调整频段；ReplayGain 在设置中读取已有响度标签，可按曲目或专辑均衡。已有响度分析与文件校验说明见“导出与音频检查”。'),
                          _link(
                              context,
                              'guide-speed-pitch-settings',
                              '打开速度与升降调设置',
                              () => _setting(context, 'library', 'playback')),
                          _link(
                              context,
                              'guide-replaygain-settings',
                              '打开音量均衡设置',
                              () => _setting(context, 'library', 'gain')),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AppDialogActions(children: [
                TextButton(
                    key: const ValueKey('close-player-feature-guide'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(ui('关闭'))),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String id, String title, IconData icon,
          List<Widget> children,
          {bool expanded = false}) =>
      ExpansionTile(
        key: ValueKey('guide-section-$id'),
        initiallyExpanded: expanded,
        shape: AppShape.surface,
        collapsedShape: AppShape.surface,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(ui(title)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expansionAnimationStyle:
            appToolbarReduceMotion(context, kind: MotionKind.layout)
                ? AnimationStyle.noAnimation
                : const AnimationStyle(duration: AppMotion.standard),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );

  Widget _text(String key) => Text(ui(key));
  Widget _paragraph(BuildContext context, String key) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(ui(key), style: Theme.of(context).textTheme.titleSmall));
  Widget _link(BuildContext context, String key, String label,
          VoidCallback action) =>
      Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                  key: ValueKey(key),
                  onPressed: action,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(ui(label)))));
}
