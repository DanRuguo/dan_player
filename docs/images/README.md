# 界面示例

[返回项目说明](../../README.md)

本目录展示实际播放器组件，使用虚构曲目和隔离数据。图片由 Flutter 控件离屏渲染，用于展示布局、主题和功能，不代表实时音频或 Windows 桌面材质测试。点击链接查看原图。

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
| 音乐统计 | [统计总览](feature-statistics-light.png) · [三栏排行](statistics-rankings-light.png) |
| 主题与桌面设置 | [主题选择](feature-theme-picker-light.png) · [桌面设置](feature-desktop-settings-light.png) |
| 歌词 | [歌词外观](feature-lyric-appearance-dark.png) · [迷你歌词](feature-mini-lyrics-dark.png) |
| 播放条与频谱 | [播放条](feature-player-bar-dark.png) · [固定虚构频谱帧](feature-spectrum-dark.png) |

## 更新预览

在仓库运行 [render_public_ui.ps1](../../scripts/render_public_ui.ps1) 生成主要页面和功能预览，对应测试为 [public_ui_showcase_test.dart](../../test/public_ui_showcase_test.dart)。三栏排行由 [statistics_visualization_test.dart](../../test/statistics_visualization_test.dart) 渲染检查，使用 `DAN_STATISTICS_RENDER` 指定输出目录后，将需要展示的截图更新到本目录。

只保留当前功能需要的展示图片；更新或移除图片时，同步维护本索引和项目 README 的引用。本机调试日志、逐轮渲染结果和历史安装器截图不放入本目录。
