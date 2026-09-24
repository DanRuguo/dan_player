import 'package:desktop_lyric/ui_language.dart';

class SettingsSearchEntry {
  const SettingsSearchEntry(this.section, this.id, this.title, this.terms);
  final String section, id, title;
  final List<String> terms;
  String get sectionTitle => settingsSectionTitles[section]!;
  String get location => Uri(
      path: '/settings',
      queryParameters: {'section': section, 'setting': id}).toString();
  Iterable<String> get labels => [title, sectionTitle, ...terms];
}

const settingsSectionTitles = <String, String>{
  "library": "曲库与播放",
  "lyrics": "联网与歌词",
  "appearance": "界面与主题",
  "effects": "背景与动效",
  "desktop": "桌面与快捷键",
  "backup": "备份与恢复",
  "about": "更新与关于",
};

const settingsSearchEntries = <SettingsSearchEntry>[
  SettingsSearchEntry("library", "folders", "文件夹管理", ["本地音乐文件夹"]),
  SettingsSearchEntry("library", "refresh", "刷新音乐库", ["增量刷新", "完整刷新"]),
  SettingsSearchEntry("library", "session", "恢复上次播放会话", []),
  SettingsSearchEntry("library", "playback", "播放速度", ["WASAPI 独占输出"]),
  SettingsSearchEntry(
      "library", "resume", "按曲记忆播放位置", ["仅长音频", "长音频最短时长", "清除自动记忆位置"]),
  SettingsSearchEntry("library", "gain", "ReplayGain 音量均衡", ["依据标签峰值限制增益"]),
  SettingsSearchEntry("library", "sleep", "播放时防止自动休眠", []),
  SettingsSearchEntry("library", "watch", "自动更新音乐库", []),
  SettingsSearchEntry("library", "artists", "自定义艺术家分隔符", []),
  SettingsSearchEntry("library", "health", "曲库健康与搬迁", ["重定位音乐目录"]),
  SettingsSearchEntry("lyrics", "automatic", "自动联网", ["歌曲评论"]),
  SettingsSearchEntry("lyrics", "source", "首选歌词来源", ["本地", "联网"]),
  SettingsSearchEntry("lyrics", "batch", "批量缓存歌词", ["选择已导入的文件夹", "开始缓存"]),
  SettingsSearchEntry("lyrics", "experience", "歌词体验", ["歌词弹性滚动", "桌面歌词竖排"]),
  SettingsSearchEntry(
      "lyrics", "platforms", "平台直连与公开 API", ["QQ音乐", "网易云音乐", "LRCLIB"]),
  SettingsSearchEntry(
      "lyrics", "custom", "第三方源", ["添加歌源", "歌词API", "导入", "导出"]),
  SettingsSearchEntry("appearance", "language", "界面语言", []),
  SettingsSearchEntry("appearance", "theme", "主题模式", ["修改主题", "专辑封面动态配色"]),
  SettingsSearchEntry("appearance", "font", "自定义字体", []),
  SettingsSearchEntry("appearance", "layout", "界面布局",
      ["音乐列表样式", "紧凑歌单", "开屏底部内容", "加载进度", "经典列表", "资源管理器分栏"]),
  SettingsSearchEntry("appearance", "sidebar", "侧栏宽度", []),
  SettingsSearchEntry("effects", "background", "背景与毛玻璃", ["轻缓动态背景", "低频律动背景"]),
  SettingsSearchEntry("effects", "rendering", "界面刷新率",
      ["频谱显示", "歌词页实时频谱", "播放条七音频谱", "界面面板毛玻璃", "不可见时暂停视觉更新"]),
  SettingsSearchEntry("effects", "animation", "动画管理", [
    "开屏动画",
    "下一首动画",
    "封面追踪",
    "页面浮现",
    "页面切换",
    "布局与文字动画",
    "歌词动画",
    "交互反馈动画",
    "主题与封面渐变",
    "播放时图标旋转"
  ]),
  SettingsSearchEntry("desktop", "desktop-lyrics", "桌面歌词显示", []),
  SettingsSearchEntry("desktop", "integration", "桌面与快捷键",
      ["托盘菜单高斯模糊", "任务栏缩略图播放控制", "任务栏歌曲预览", "任务栏播放进度", "关闭窗口后在后台继续播放"]),
  SettingsSearchEntry("desktop", "shortcuts", "应用内快捷键", []),
  SettingsSearchEntry(
      "backup", "backup", "播放器备份与恢复", ["创建播放器备份", "从备份恢复", "密码加密"]),
  SettingsSearchEntry("backup", "performance", "性能快捷设置", []),
  SettingsSearchEntry(
      "about", "updates", "检查更新", ["自动检查更新（每天最多一次）", "接收预览版更新"]),
  SettingsSearchEntry("about", "network-proxy", "网络代理",
      ["系统代理", "自定义 HTTP 代理", "测试 GitHub 连接"]),
  SettingsSearchEntry("about", "uninstall", "应用管理", ["卸载 Dan Player"]),
  SettingsSearchEntry("about", "issues", "报告问题", []),
  SettingsSearchEntry("about", "about", "关于", []),
];

// Translations are indexed without changing the active UI language. No widgets,
// provider calls or settings side effects are needed to search this catalog.
final _settingsText = {
  for (final entry in settingsSearchEntries)
    entry.id: [
      for (final label in entry.labels)
        for (final language in UiLanguage.values)
          translateUi(label, language).toLowerCase()
    ].join('\n'),
};

List<SettingsSearchEntry> searchSettings(String query) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();
  if (terms.isEmpty) return [];
  final matches = settingsSearchEntries
      .where((entry) => terms.every(_settingsText[entry.id]!.contains))
      .toList();
  int rank(SettingsSearchEntry entry) => UiLanguage.values.any((language) =>
          translateUi(entry.title, language).toLowerCase() ==
          query.trim().toLowerCase())
      ? 0
      : 1;
  matches.sort((a, b) => rank(a).compareTo(rank(b)));
  return matches;
}
