# 界面示例

[返回项目说明](../../README.md)

本目录展示实际播放器组件，使用虚构曲目和隔离数据。图片由 Flutter 控件离屏渲染，用于展示布局、主题和功能，不代表实时音频或 Windows 桌面材质测试。点击链接查看原图。

项目页首的 [浅色图标](player-icon-light.png) 与 [深色图标](player-icon-dark.png) 直接取自 `app_icon.ico`、`app_icon_dark.ico` 中的 256px PNG 图层，与播放器使用的图标一致。

## 主要页面

| 页面 | 浅色宽窗 | 浅色窄窗 | 深色宽窗 | 深色窄窗 |
| --- | --- | --- | --- | --- |
| 音乐 | [查看](library-light-wide.png) | [查看](library-light-narrow.png) | [查看](library-dark-wide.png) | [查看](library-dark-narrow.png) |
| 歌单 | [查看](playlists-light-wide.png) | [查看](playlists-light-narrow.png) | [查看](playlists-dark-wide.png) | [查看](playlists-dark-narrow.png) |
| 设置 | [查看](settings-light-wide.png) | [查看](settings-light-narrow.png) | [查看](settings-dark-wide.png) | [查看](settings-dark-narrow.png) |

## 功能预览

| 功能 | 示例 |
| --- | --- |
| 曲库分类与文件夹 | [分类](feature-categories-light.png) · [文件夹](feature-folders-light.png) |
| 搜索与歌单编辑 | [搜索](feature-search-dark.png) · [更改所选歌曲](feature-change-selected-songs-light.png) |
| 搜索历史胶囊 | [中文／删除状态](search-history-zh.png) · [English](search-history-en.png) · [日本語](search-history-ja.png) · [한국어](search-history-ko.png) |
| 音乐统计 | [统计总览](feature-statistics-light.png) · [三栏排行](statistics-rankings-light.png) |
| 主题与桌面设置 | [主题选择](feature-theme-picker-light.png) · [桌面设置](feature-desktop-settings-light.png) |
| 歌词 | [歌词外观](feature-lyric-appearance-dark.png) · [迷你歌词](feature-mini-lyrics-dark.png) |
| 歌词编辑 | [快捷点按文本](lyric-tap-text-zh.png) · [窄窗逐字打点](lyric-tap-words-narrow-zh.png) · [传统代码编辑](lyric-code-editor-zh.png) · [逐字预览](lyric-editor-preview-zh.png) |
| 播放条与频谱 | [播放条](feature-player-bar-dark.png) · [固定虚构频谱帧](feature-spectrum-dark.png) |

## 更新预览

本轮搜索历史图片由 [search_history_render_test.dart](../../test/search_history_render_test.dart) 生成，使用 `--dart-define=DAN_SEARCH_RENDER=<输出目录>`。加载播放器字体与 Material Symbols 图标字体，展示搜索页内容区域、居中换行、超长文本省略和示例历史；中文图展示强调色删除状态，英文／日文使用浅色主题，中文／韩文使用深色主题。这些图片不包含原生窗口边框或底部播放条，不作为整窗或原生性能测试证据。

歌词编辑的四张图由 [tap_lyric_editor_test.dart](../../test/tap_lyric_editor_test.dart) 与 [lyric_editor_formats_render_test.dart](../../test/lyric_editor_formats_render_test.dart) 的中文定向渲染生成，分别使用 `DAN_TAP_RENDER`、`DAN_EDITOR_RENDER` 编译期开关。使用虚构曲目和真实产品字体；宽窗、窄窗、正文、逐字与预览均是 Flutter 离屏控件图，不代表真实声卡试听。

在仓库运行 [render_public_ui.ps1](../../scripts/render_public_ui.ps1) 生成主要页面和功能预览，对应测试为 [public_ui_showcase_test.dart](../../test/public_ui_showcase_test.dart)。三栏排行由 [statistics_visualization_test.dart](../../test/statistics_visualization_test.dart) 渲染检查，使用 `DAN_STATISTICS_RENDER` 指定输出目录后，将需要展示的截图更新到本目录。

只保留当前功能需要的展示图片；更新或移除图片时，同步维护本索引和项目 README 的引用。本机调试日志、逐轮渲染结果和历史安装器截图不放入本目录。
