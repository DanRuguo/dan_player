import 'dart:math' as math;

import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/component/player_guide_demo.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/page/search_page/search_page.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
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
            subtitle: ui('从导入音乐到歌词制作、进阶播放与资料维护的播放器说明书；按章节阅读，也可直接打开相关工具。')),
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
class PlayerFeatureGuideDialog extends StatefulWidget {
  const PlayerFeatureGuideDialog(
      {super.key, this.onNavigate, this.demoIsHidden});
  final ValueChanged<String>? onNavigate;
  final ValueListenable<bool>? demoIsHidden;

  @override
  State<PlayerFeatureGuideDialog> createState() =>
      _PlayerFeatureGuideDialogState();
}

const _guideChapters = [
  ('start', '导入与起步'),
  ('playback', '播放与队列'),
  ('organize', '整理音乐'),
  ('lyric-tools', '歌词工具与制作'),
  ('audio-tools', '声音与音频文件'),
  ('windows', '外观与窗口'),
  ('maintenance', '统计与维护'),
  ('input-tools', '搜索与快捷键'),
];

class _PlayerFeatureGuideDialogState extends State<PlayerFeatureGuideDialog> {
  final _chapterKeys = {
    for (final chapter in _guideChapters) chapter.$1: GlobalKey(),
  };
  final _demoExpanded = {'queue': false, 'lyrics': false};

  void _setting(BuildContext context, String section, String setting) {
    final location = Uri(path: '/settings', queryParameters: {
      'section': section,
      'setting': setting,
    }).toString();
    _navigate(context, location);
  }

  void _navigate(BuildContext context, String location) {
    final navigate = widget.onNavigate;
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
                        _text(
                            '这是一份按操作顺序组织的播放器说明书。点目录跳到章节，展开条目查看步骤；末尾的工具入口直接定位现有页面，阅读指南不会开始播放或改动资料。'),
                        const SizedBox(height: 8),
                        _contents(context),
                        _chapter(context, 1,
                            '先添加音乐目录并完成扫描，再从音乐页开始播放；以下操作不会改变原音乐文件。'),
                        _section(
                            context,
                            'getting-started',
                            '首次导入与开始听歌',
                            Icons.library_music_outlined,
                            [
                              _text(
                                  '在“设置 → 曲库与播放 → 文件夹管理”打开管理窗口，点“添加文件夹”选择音乐目录，可重复添加；点“确定”后等待扫描完成。这里只把歌曲加入曲库，不移动原文件；移除收录目录也不删除音乐。到音乐页点选歌曲开始播放，点播放条的曲目信息进入歌词页。'),
                              _flow(context, 'first-play',
                                  ['添加文件夹', '扫描曲库', '选择歌曲', '打开歌词页']),
                              _text(
                                  '新增或修改音乐后优先使用“增量刷新”，需要重新读取全部资料时使用“完整刷新”。扫描取消或失败会保留原曲库；外置盘暂时离线时先检查访问状态，不要删除原歌单。也可开启“自动更新音乐库”，让已添加目录的变化合并后增量刷新。'),
                              _paragraph(context, '音乐页：浏览、排序与点歌'),
                              _text(
                                  '音乐页集中显示曲库歌曲。用页头排序按钮选择字段和升降序，按歌曲行开始播放；播放器以当前显示顺序建立队列。进入多选后，点行改为勾选。自定义排序可拖动整理，其他排序不会改写文件；页头“搜索”进入独立搜索页。'),
                              _paragraph(context, '分类页：从专辑与艺术家开始'),
                              _text(
                                  '分类页可按专辑、艺术家、码率、时长、语言、格式或来源浏览，“个人整理”集中查看评分与标签。搜索框筛选当前分类组；点封面进入详情，再搜索或排序歌曲，点歌按详情里可见的结果播放。切换分类类型会清空分类搜索，浏览分类不会改动音乐标签。'),
                              _link(
                                  context,
                                  'guide-basic-music-page',
                                  '打开音乐页',
                                  () => _navigate(
                                      context, app_paths.AUDIOS_PAGE)),
                              _link(
                                  context,
                                  'guide-basic-category-page',
                                  '打开分类页',
                                  () => _navigate(
                                      context, app_paths.CATEGORIES_PAGE)),
                              _link(
                                  context,
                                  'guide-first-import-settings',
                                  '打开文件夹管理',
                                  () =>
                                      _setting(context, 'library', 'folders')),
                              _link(
                                  context,
                                  'guide-first-refresh-settings',
                                  '打开音乐库刷新设置',
                                  () =>
                                      _setting(context, 'library', 'refresh')),
                              _link(
                                  context,
                                  'guide-first-watch-settings',
                                  '打开自动更新音乐库',
                                  () => _setting(context, 'library', 'watch')),
                            ],
                            expanded: true),
                        _chapter(context, 2,
                            '从播放条进入歌词页或队列；先了解播放顺序，再按需要设置书签、续播和停止条件。'),
                        _section(context, 'queue', '播放队列与停止目标',
                            Icons.queue_music_outlined, [
                          _paragraph(context, '播放条、随机与循环'),
                          _text(
                              '播放条可上一首、播放／暂停、下一首和打开播放列表；点曲目信息进入歌词页。随机只切换队列播放顺序，不立刻换歌；循环按钮依次切换关闭、列表循环、单曲循环。歌词页可拖进度条定位，或用“更多 → 精确定位”输入时间；播放列表顶栏的“A-B 片段循环”标记区间，也可用歌词选段练习。'),
                          _paragraph(context, '定位进度与返回播放'),
                          _text(
                              '进度条用于定位当前歌曲，不重建播放队列。需要准确时间时用“精确定位”；定位到 A-B 区间外会退出片段循环。暂停只停止播放，仍可阅读歌词和整理队列；准备好后再次点播放。下面可试着拖动或点按进度，按钮只演示前后定位。'),
                          _demo('queue', PlayerGuideDemoKind.progress),
                          _paragraph(context, '编辑当前队列'),
                          _text(
                              '歌词页打开播放队列，歌曲菜单可插入下一首或加入队尾；队列中的调整不会改动原歌单。正在播放的歌曲保留在队列中。'),
                          const SizedBox(height: 8),
                          _text(
                              '播放列表“整理队列”可去重、清理当前曲目前后或重排待播项，并保留当前播放。队列获得焦点时 Ctrl + Z 撤销，Ctrl + Y 或 Ctrl + Shift + Z 重做；替换播放来源或切换随机会结束这段整理历史。移除停止目标后再撤销整理，不会恢复停止目标。'),
                          _paragraph(context, '倒计时与停止目标'),
                          const SizedBox(height: 8),
                          _text(
                              '“更多 → 睡眠定时”可设置倒计时、播完本曲、按当前播放数量或播完队列后停止。倒计时与队列停止目标可叠加、独立取消；队列状态会提示目标是否仍有效。'),
                          const SizedBox(height: 8),
                          _text('按数量包含本曲，确认时固定目标条目；重排后仍止于该条，删除目标会取消该停止目标。'),
                          const SizedBox(height: 8),
                          _text(
                              '倒计时可延长、缩短、暂停或继续，也可选择到时播完本曲再停。按数量、播完本曲与队尾目标一次只保留一种；新设目标前先关闭 A-B 和单曲循环。已有目标被循环阻挡时，队列会提示原因，关闭循环即可继续前进。倒计时真正触发停止后，队列目标也会清除。'),
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
                          const SizedBox(height: 8),
                          _text(
                              '“恢复上次播放会话”保存队列与位置，重新启动时先恢复为暂停状态，准备好后再播放。它与按曲记忆分开：会话恢复上次队列，按曲记忆用于再次手动点选同一首本地歌曲。'),
                          _link(context, 'guide-resume-settings', '打开播放记忆设置',
                              () => _setting(context, 'library', 'resume')),
                        ]),
                        _chapter(context, 3,
                            '用歌单、智能规则和批量工具整理曲库；区分播放器里的引用、个人资料与真正的音乐文件。'),
                        _section(
                            context,
                            'playlists',
                            '歌单与队列整理',
                            Icons.account_tree_outlined,
                            [
                              _paragraph(context, '新建与加入歌曲'),
                              _text(
                                  '在歌单页点“新建歌单”，填写名称，可选封面并选择歌曲，再点“创建”；也可先建空歌单，进入后添加歌曲或子歌单。歌曲菜单的“加入歌单…”将引用加入所选歌单，不复制或移动音频。之后再选列表、圆形、矩形或树形浏览。'),
                              _paragraph(context, '普通歌单的日常管理'),
                              _text(
                                  '歌单项目的右键、长按或更多菜单用于进入详情、编辑名称与封面、加入歌曲和管理子歌单。进入歌单后点歌曲播放，或用多选整理一批项目。移除歌单里的歌曲只移除引用，原音乐文件仍保留；删除歌单后可从歌单回收站检查与恢复。'),
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
                              '从歌单页“更多 → 智能歌单”进入，可新建规则或选最近播放、常听歌曲、还没听过等预设。填写筛选规则，查看结果与“匹配详情”，再“保存规则”；想固定这一批歌曲，用“加入或新建普通歌单…”。'),
                          const SizedBox(height: 8),
                          _text(
                              '智能歌单按本地筛选规则生成歌曲；可以固定排序，也可以随机抽取并“换一批”。保存智能规则后，下次打开会重新求值；加入普通歌单则保留当前批次。每批不重复抽同一歌曲，不同批次可能重合。'),
                          const SizedBox(height: 8),
                          _text('评分、标签与个人备注属于播放器资料，可用于筛选和整理；它们不会改写音乐文件的原始标签。'),
                        ]),
                        _section(context, 'batch-edit', '多选与批量整理',
                            Icons.checklist_outlined, [
                          _text(
                              '从歌曲菜单进入“多选”，再勾选歌曲；顶部可全选、反选或退出。播放所选、下一批播放、加入队尾与导出都按当前可见顺序处理；被筛选隐藏的已选项不会参与本次操作。'),
                          _flow(context, 'batch', ['选择歌曲', '预览修改', '应用预览']),
                          _text(
                              '多选“更多”集中提供个人评分与标签、批量编辑标签、重新读取封面和复制信息。个人评分、标签和备注只存在播放器资料中；批量编辑歌曲标签会写入音频文件，先预览再确认，未启用的字段保持原值。'),
                          _link(context, 'guide-batch-music-page', '打开音乐页',
                              () => _navigate(context, app_paths.AUDIOS_PAGE)),
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
                        _chapter(context, 4,
                            '先选择与校准歌词，再阅读或练习；需要制作歌词时，在传统码字和快捷点按之间选择合适方法。'),
                        _section(context, 'lyrics', '歌词阅读、练习与分享',
                            Icons.lyrics_outlined, [
                          _text(
                              '播放歌曲后进入歌词页，打开“歌词阅读工具”调整字号、时间和辅助内容。Ctrl + F 查找原文、翻译或注音，用上／下一匹配和“定位阅读”浏览目标句，不改变播放位置。歌词行右键或长按可复制当前句。'),
                          _paragraph(context, '跟随播放与手动阅读'),
                          _text(
                              '正常播放会跟随当前歌词；单击有时间轴的歌词行可跳到该句，纯文本没有逐句定位。想只阅读而不跳歌，在阅读工具开启“手动阅读歌词”，再用“回到当前歌词”恢复跟随。A± 可拖动调字号；译文、注音与时间各自开关。逐词强调需要带逐字时间的歌词，普通 LRC 主要按句强调。'),
                          _demo('lyrics', PlayerGuideDemoKind.lyrics),
                          const SizedBox(height: 8),
                          _text(
                              '歌词菜单提供阅读、查找、选段练习与歌词卡片。阅读工具可调整字号和显示内容；查找结果可定位原句，练习选段使用 A-B 循环。歌词卡片可选择句子并导出 PNG，原歌曲和歌词不会被改写。'),
                          const SizedBox(height: 8),
                          _text(
                              '已确认或已选用的人工歌词优先；其他歌曲按“首选歌词来源”读取本地与已缓存内容，均缺失后才由自动联网决定是否搜索。手动搜索或选择不受自动开关限制，校准与编辑可从歌词页现有入口进入。'),
                          _link(context, 'guide-lyric-settings', '打开歌词体验设置',
                              () => _setting(context, 'lyrics', 'experience')),
                        ]),
                        _section(context, 'sources-comments', '歌词来源与评论关联',
                            Icons.forum_outlined, [
                          _text(
                              '已确认或已选用的人工歌词优先；没有人工选择时按“首选歌词来源”读取本地与缓存内容。两者均缺失且开启自动联网时才搜索，已有歌词或关闭开关时不会自动搜词。手动搜索独立于这个开关；编辑副本保存后，仍需手动选用才成为播放歌词。'),
                          const SizedBox(height: 8),
                          _text(
                              '歌词页评论按钮打开只读评论。可“选择关联歌曲”确认平台歌曲，或“跟随联网歌词”使用当前歌词携带的 QQ音乐／网易云歌曲 ID；不会仅凭同名猜测。切换关联后，刷新读取新确认的来源；也可解除关联。'),
                          _link(
                              context,
                              'guide-automatic-online-settings',
                              '打开自动联网设置',
                              () => _setting(context, 'lyrics', 'automatic')),
                          _link(
                              context,
                              'guide-lyric-source-settings',
                              '打开歌词来源设置',
                              () => _setting(context, 'lyrics', 'source')),
                        ]),
                        _section(context, 'offline-lyrics', '本地歌词与离线准备',
                            Icons.download_for_offline_outlined, [
                          _text(
                              '已有 LRC 或 TXT 文件时，在歌曲多选的“更多 → 批量关联本地歌词”选择目录。按音乐文件同基名匹配，先检查候选，再确认关联；同名多份需要手动选择。保存为应用内副本，不移动原歌词文件。'),
                          const SizedBox(height: 8),
                          _text(
                              '已锁定、已编辑或已标记无歌词的歌曲会保留现有选择。没有本地歌词时，可在“批量缓存歌词”选择已导入的音乐文件夹准备离线歌词；取消只停止后续处理，已经缓存的结果仍保留。'),
                          _link(
                              context,
                              'guide-offline-lyric-settings',
                              '打开批量缓存歌词',
                              () => _setting(context, 'lyrics', 'batch')),
                        ]),
                        _section(context, 'manual-lyric-edit', '传统码字：完整编辑流程',
                            Icons.edit_note_outlined, [
                          _flow(context, 'manual-edit',
                              ['传统码字', '编辑与试听', '保存编辑副本', '使用编辑的本地歌词']),
                          _paragraph(context, '1. 打开编辑器并选择格式'),
                          _text(
                              '先播放本地歌曲，在歌词页点“编辑本地歌词”图标，或在歌曲菜单点“编辑歌词”，选择“传统码字”。LRC 适合逐句，增强 LRC、QRC、KRC、YRC 可保留逐字时间；纯文本没有时间轴，播放器无损副本用于完整保留时间、翻译和注音。降低格式能力时先读转换提示，可“保留完整内容”或“返回选择格式”。'),
                          _paragraph(context, '2. 载入内容并分开编辑'),
                          _text(
                              '编辑器优先载入已保存的编辑副本，再读取当前歌词或本地、缓存内容。可“导入歌词”“填入联网歌词”或“载入示例”；这些动作只填入编辑器，替换未保存内容需要确认。正文、翻译、注音分别编辑，辅助轨使用与正文句首一致的 LRC 时间戳。纯文本和无损副本不显示独立辅助栏；TTML 导入会转换成可编辑格式，原文件不改写。'),
                          _code(context, 'manual-lrc', '[00:01.000]Hello world',
                              'LRC 示例：方括号内为分、秒和毫秒，后面是本句正文。'),
                          _paragraph(context, '3. 用试听位置设置句与字的时间'),
                          _text(
                              '使用试听播放／暂停、进度条和前后 100 毫秒定位。在要修改的行放置光标，点“设置当前行时间”。逐字格式先设行时间，再选中同一行中不含时间标记的文字，点“设置所选文字时间”填写起止时间。正文句首改动时会同步相同时间的翻译与注音。输入框内空格仍用于输入；焦点移到试听控件后，空格播放／暂停，左右键定位 100 毫秒。'),
                          _paragraph(context, '4. 预览、保存与明确选用'),
                          _text(
                              '有时间轴的歌词切到“预览”，用“播放编辑预览”或逐句试听检查内容与时间；显示最多 100 行、每行 80 个时间片段，保存仍包含全部内容。纯文本只检查正文。点“保存编辑副本”校验并保存到播放器，随后在“歌词校准与锁定 → 歌词内容与版本”点“使用编辑的本地歌词”；这一步才用于播放并锁定，单独保存不会替换当前播放歌词。'),
                          _paragraph(context, '5. 导出、回退与保护'),
                          _text(
                              '需要外部文件时另用“导出歌词”，核对将写入的文件清单；翻译和注音导出为独立 LRC，已有内容保留备份。已有原始歌词时，可在校准窗口“恢复原始歌词”；有历史记录时可“恢复之前的版本”。取消未保存修改会询问是否放弃；联网歌曲只读。试听不加入播放队列或听歌统计，关闭时仅在主播放意图未改变的情况下恢复之前状态；编辑不会改写音频。'),
                          _link(
                              context,
                              'guide-manual-edit-page',
                              '打开歌词页',
                              () => _navigate(
                                  context, app_paths.NOW_PLAYING_PAGE)),
                        ]),
                        _section(context, 'tap-lyric-edit', '快捷点按：完整制词流程',
                            Icons.keyboard_alt_outlined, [
                          _flow(context, 'tap-edit',
                              ['准备歌词文本', '逐句打点', '逐字打点（可选）', '保存并选用']),
                          _paragraph(context, '1. 准备正文、翻译与注音'),
                          _text(
                              '从本地歌曲的编辑入口选择“快捷点按”。按一行一句输入纯文本，可“联网填入纯文本”或“加载上次进度”。每行按正文、翻译、注音三栏输入，缺翻译时中间留空；正文含分隔符时调整“分隔符空格数”，与画面示例一致。直接“保存纯文本歌词”只保存正文；要保留辅助内容请继续逐句制作。'),
                          _code(context, 'tap-columns', ui('正文|翻译|注音\n正文||注音'),
                              '点按文本示例：竖线分隔三栏，换行进入下一句。'),
                          _paragraph(context, '2. 逐句开始、结束与试听确认'),
                          _text(
                              '点“继续编写逐句歌词”，按提示准备试听组件。空格播放／暂停；句首按 Enter 或“开始本句”，句尾再按 Enter 或“结束本句”。结束后试听当前句，准确就“满意，继续”，不准确就“不满意，重录本句”。可用 0.25×、0.5×、0.75× 或 1× 试听，记录始终是歌曲时间。暂停不确认打点；最后一句已有开始时，自然播完才会补上句尾。'),
                          _paragraph(context, '3. 可选：继续逐字打点'),
                          _text(
                              '逐句全部确认后可在逐句级选择格式保存，也可“继续编写逐字歌词”。播放当前句，按 Enter 或点强调的字记录该字的结束，依次完成后再试听、确认或重录本句。中日韩按字处理，西文通常按词处理；空格和标点保留。仅剩最后一个字时，试听自然到达边界可补齐；还有多个字未完成时不会自动确认，需重录。'),
                          _paragraph(context, '4. 保存进度、退出与重新修改'),
                          _text(
                              '“保存当前进度”会暂停试听并保存文本、打点和当前位置，下次通过“加载上次进度”继续。“返回修改文本”保留文本但清除本次打点，操作前先保存进度。退出时可继续编辑、不保存退出或保存进度并退出；不保存不会覆盖上次手动保存的进度。歌曲版本或时长与进度不符时需重新编辑。'),
                          _paragraph(context, '5. 选择格式、保存副本并投入播放'),
                          _text(
                              '点“选择格式并保存歌词”后，会进入格式选择与传统编辑器确认，并非直接导出文件。检查正文，有时间轴时再看预览，点“保存编辑副本”，再到“歌词校准与锁定”使用编辑的本地歌词。LRC 不能完整保留句尾与逐字时间，可选逐字格式或播放器无损副本；外部歌词用“导出歌词”。回退与锁定沿用传统码字的版本入口。'),
                          _link(
                              context,
                              'guide-tap-edit-page',
                              '打开歌词页',
                              () => _navigate(
                                  context, app_paths.NOW_PLAYING_PAGE)),
                        ]),
                        _chapter(
                            context, 5, '调整速度、音高和响度，或检查、导出音频；单曲偏好与全局默认分别管理。'),
                        _section(
                            context, 'sound', '速度、音高与音量', Icons.tune_outlined, [
                          _paragraph(context, '音量、静音与精确输入'),
                          _text(
                              '歌词页点喇叭打开音量面板，拖滑条或选择百分比预设；点数值可输入精确音量。面板里的喇叭用于静音／恢复最近的非零音量，打开面板本身不会静音。调整播放器音量不会改写音乐文件。'),
                          _paragraph(context, '速度、升降调与均衡器'),
                          _text(
                              '歌词页 1× 按钮打开“播放速度与升降调”，选速度或在子菜单选半音；设置的“曲库与播放 → 播放速度”管理全局默认。更多里的“本曲播放设置”可记住单曲偏好，手动调整全局参数仍立即生效。均衡器可开启、选预设或调整频段；输出不支持时会提示。'),
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
                        _section(context, 'files', '导出与音频检查',
                            Icons.drive_file_move_outlined, [
                          _text(
                              'M3U8 导出保存歌曲路径引用；“导出音乐文件夹”会复制本地音频并生成相对路径歌单，适合搬到另一台设备。在线歌曲与 CUE 分轨会明确跳过；同一源文件只复制一次，歌单仍保留顺序和重复引用。原文件不移动、不转码。'),
                          const SizedBox(height: 8),
                          _text(
                              '歌词页“更多”中的本曲设置、响度与峰值分析、音频文件校验用于查看与调整当前歌曲。分析和校验只读取源文件；响度分析给出参考增益，不会自动改写音频。'),
                        ]),
                        _chapter(context, 6,
                            '主题、窗口和歌词显示沿用同一套外观设置；减少动画、隐藏停钟等选项用于按设备能力调整体验。'),
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
                        _section(context, 'lyric-display', '桌面与任务栏歌词',
                            Icons.desktop_windows_outlined, [
                          _text(
                              '在设置中开启桌面歌词或任务栏歌词，两种模式自动互斥，共用当前歌词。桌面歌词的外观面板可调整样式，也可切换到任务栏。'),
                          const SizedBox(height: 8),
                          _text(
                              '任务栏设置可选位置、切换空区、单/双行、配色与独立描边。歌词文字保持点击穿透；播放/暂停与可选下一首只有按钮区域接收点击。安全空间不足时自动隐藏。'),
                          const SizedBox(height: 8),
                          _text(
                              '任务栏图标增减会改变安全空区，歌词会随可用宽度调整；空间不够时隐藏不代表歌曲暂停。可切换空区或调整对齐，也可切回桌面歌词。隐藏播放器窗口时资源监控停止；关闭窗口是否后台播放，由“退出后操作”设置决定。'),
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
                        _chapter(context, 7,
                            '先查看听歌与文件占用，再按需开启资源监控；备份、恢复和已搬目录的重定位用于维护与换机。'),
                        _section(context, 'statistics', '统计与资源监控',
                            Icons.insights_outlined, [
                          _text(
                              '统计页查看听歌趋势、排行、音乐与缓存占用。缓存类别用易读名称显示，悬停查看真实路径；文件夹菜单可直达对应占用统计。'),
                          const SizedBox(height: 8),
                          _text(
                              '资源监控先由总开关启用，再选择是否在侧栏底部和歌词页左上角显示；这两处默认关闭。各位置共用数字、折线或条形与 1／5／10 秒刷新设置。展开侧栏在图标旁显示数值或图表；紧凑侧栏只显示图标，悬停查看占比。歌词页使用迷你图标与细图，悬停查看名称与占比。'),
                          const SizedBox(height: 8),
                          _text(
                              '只采样播放器自身 CPU、GPU 与内存；RAM 百分比为播放器工作集占物理内存的比例。只有启用的显示区域可见时才采样，全部不可见或隐藏窗口即停止；不可用数据明确标示。'),
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
                        _section(context, 'backup-workflow', '备份、恢复与换机',
                            Icons.backup_outlined, [
                          _paragraph(context, '创建备份与选择内容'),
                          _text(
                              '在“设置 → 备份与恢复 → 播放器备份与恢复”点“备份到文件”，选择组件与音乐文件夹，再点“备份所选内容”保存 .bak。默认选择播放器资料组件，音乐文件夹默认未选；完整换机时选择“全部”或明确勾选要带走的音乐。仅备份索引不会复制音频文件。'),
                          _text(
                              '歌词编辑副本与点按进度属于“曲库索引与播放状态”；书签、歌单和智能规则属于“歌单与个人整理”。需要保留制词成果时不要只选缓存。可选密码加密，记住原样密码；密码不保存在播放器，遗失后无法恢复加密备份。'),
                          _flow(context, 'backup',
                              ['备份到文件', '从备份恢复', '选择恢复内容', '退出并重启']),
                          _paragraph(context, '恢复、位置与生效时间'),
                          _text(
                              '点“从备份恢复”选择备份，必要时输入密码解锁；核对恢复项，点“恢复所选内容”并选择存放位置。覆盖已识别的播放器缓存需要确认。显示“恢复已准备完成”后选择稍后重启或退出播放器，下次启动才生效；未选资料保留原状。恢复失败不会切换当前缓存位置。'),
                          _text(
                              '只恢复索引而原音乐路径不存在时，还需恢复音乐、重新导入或重定位目录。只恢复音乐文件时保留当前索引，之后扫描收录。跨设备迁移先确保备份包含所需资料与音乐；文件夹剪切和已经搬好目录的重定位沿用对应章节。'),
                          _link(
                              context,
                              'guide-manual-backup-settings',
                              '打开备份与恢复',
                              () => _setting(context, 'backup', 'backup')),
                        ]),
                        _section(
                            context, 'relink', '音乐目录重定位', Icons.link_outlined, [
                          _text(
                              '如果音乐已通过资源管理器搬到新位置，在“曲库健康与搬迁 → 重定位目录”填入旧目录与新目录。它同步曲库、歌单和相关资料的路径，音乐文件本身不会再次移动；尚未搬动文件时用文件夹页的“移动音乐文件夹”。'),
                          _flow(context, 'relink', ['预览映射', '确认并退出', '重新启动']),
                          _text(
                              '预览中确认匹配、缺失与冲突后再应用；重启时完成资料同步。外置盘离线时先检查曲库状态，离线记录会保留，不必重新建立歌单。已有检查与迁移详情可直接打开。'),
                          _link(
                              context,
                              'guide-library-health-settings',
                              '打开曲库健康与搬迁',
                              () => _setting(context, 'library', 'health')),
                        ]),
                        _chapter(context, 8,
                            '用搜索缩小范围，再借助快捷键提高操作效率；完整语法和实际保存的快捷键可直接打开查看。'),
                        _section(context, 'search', '高级搜索',
                            Icons.manage_search_outlined, [
                          _paragraph(context, '先查找，再按条件缩小范围'),
                          _text(
                              '从侧栏或音乐页打开搜索，输入歌名、歌手或专辑后提交，再从结果进入歌曲、艺术家或专辑。普通搜索也可查询已配置的在线歌源；加入 format:flac 这类筛选条件后，只查询本地曲库。先用普通文字找到目标，结果过多时再补格式、评分或排除条件；完整语法与示例用下面的帮助查看。'),
                          _link(context, 'guide-basic-search-page', '打开搜索页',
                              () => _navigate(context, app_paths.SEARCH_PAGE)),
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
        onExpansionChanged: _demoExpanded.containsKey(id)
            ? (value) => setState(() => _demoExpanded[id] = value)
            : null,
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

  Widget _demo(String section, PlayerGuideDemoKind kind) => TickerMode(
      enabled: _demoExpanded[section] ?? false,
      child: PlayerGuideDemo(
          key: ValueKey('guide-demo-${kind.name}'),
          kind: kind,
          isHidden: widget.demoIsHidden));

  Widget _text(String key) => Text(ui(key));
  Widget _chapter(BuildContext context, int number, String introduction) {
    final chapter = _guideChapters[number - 1];
    return KeyedSubtree(
        key: _chapterKeys[chapter.$1],
        child: Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 8),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                      key: ValueKey('guide-chapter-${chapter.$1}'),
                      header: true,
                      child: Text('$number · ${ui(chapter.$2)}',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.primary))),
                  const SizedBox(height: 6),
                  _text(introduction),
                ])));
  }

  Widget _contents(BuildContext context) => Wrap(
          key: const ValueKey('guide-manual-contents'),
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var index = 0; index < _guideChapters.length; index++)
              TextButton(
                  key: ValueKey('guide-jump-${_guideChapters[index].$1}'),
                  onPressed: () {
                    final destination =
                        _chapterKeys[_guideChapters[index].$1]!.currentContext;
                    if (destination == null) return;
                    Scrollable.ensureVisible(destination,
                        alignment: 0,
                        duration: AppMotion.duration(
                            context, MotionKind.layout, AppMotion.standard),
                        curve: AppMotion.standardCurve);
                  },
                  child:
                      Text('${index + 1} · ${ui(_guideChapters[index].$2)}')),
          ]);

  Widget _code(
      BuildContext context, String id, String example, String caption) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: DecoratedBox(
            decoration: ShapeDecoration(
                color: colors.surfaceContainerLow, shape: AppShape.control),
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SelectableText(example,
                          key: ValueKey('guide-code-$id'),
                          style: TextStyle(
                              color: colors.primary,
                              fontFamily: 'Consolas',
                              fontFamilyFallback: danFontFamilyFallback)),
                      const SizedBox(height: 6),
                      Text(ui(caption),
                          style: Theme.of(context).textTheme.bodySmall),
                    ]))));
  }

  Widget _flow(BuildContext context, String id, List<String> steps) {
    final colors = Theme.of(context).colorScheme;
    final labels = steps.map((step) => ui(step)).toList();
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Semantics(
            label: ui('操作顺序：{0}', [labels.join(' → ')]),
            excludeSemantics: true,
            child: Wrap(
                key: ValueKey('guide-flow-$id'),
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var index = 0; index < labels.length; index++) ...[
                    if (index > 0)
                      Icon(Icons.arrow_forward_rounded,
                          size: 16, color: colors.primary),
                    DecoratedBox(
                        decoration: ShapeDecoration(
                            color: colors.secondaryContainer,
                            shape: AppShape.control),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            child: Text('${index + 1} · ${labels[index]}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                        color: colors.onSecondaryContainer)))),
                  ],
                ])));
  }

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
