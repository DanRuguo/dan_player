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
| 使用说明书 | [音乐与分类常用操作](manual-common-library.png) · [队列与进度互动演示](manual-playback-demo.png) |
| 资源与空间 | [侧栏与设置共用资源监控](process-resource-locations.png) · [统计页缓存分类占用](cache-storage-statistics.png) |
| 主题与桌面设置 | [主题选择](feature-theme-picker-light.png) · [桌面设置](feature-desktop-settings-light.png) |
| 歌词 | [歌词外观](feature-lyric-appearance-dark.png) · [迷你歌词](feature-mini-lyrics-dark.png) |
| 歌词编辑 | [快捷点按文本](lyric-tap-text-zh.png) · [窄窗逐字打点](lyric-tap-words-narrow-zh.png) · [传统代码编辑](lyric-code-editor-zh.png) · [逐字预览](lyric-editor-preview-zh.png) |
| 播放条与频谱 | [播放条](feature-player-bar-dark.png) · [固定虚构频谱帧](feature-spectrum-dark.png) |
| 歌词页待播预览 | [中文](feature-upcoming-zh.png) · [English](feature-upcoming-en.png) · [日本語](feature-upcoming-ja.png) · [한국어](feature-upcoming-ko.png) |
| 频谱样式互动指南 | [中文](feature-spectrum-guide-zh.png) · [English](feature-spectrum-guide-en.png) · [日本語](feature-spectrum-guide-ja.png) · [한국어](feature-spectrum-guide-ko.png) |

## 展示说明

说明书图片展示播放器的真实组件与字体，资源数值、目录和曲目采用虚构示例。界面动效在说明书中可由用户主动试用，静态图仅展示某一状态，不作为播放、GPU 或动画性能验证。

搜索历史图片加载播放器字体与 Material Symbols 图标字体，展示内容区域、居中换行、超长文本省略和示例历史；中文图展示强调色删除状态，英文／日文使用浅色主题，中文／韩文使用深色主题。这些图片不包含原生窗口边框或底部播放条。

歌词编辑的四张图使用虚构曲目和真实产品字体，展示宽窗、窄窗、正文、逐字与预览状态，不代表真实声卡试听。

四语待播图片使用当前的 `CurrentPlaylistView`、`QueueUpcomingPreview` 与 `BackgroundLayer`，加载播放器深色主题和实际字体，展示四项双列、半透明卡片及完整队列。歌名、作者、专辑和渐变封面均为虚构示例；这是歌词页的队列视图，播放条弹出的列表不显示待播预览。

四语频谱指南图片并排展示实际 `PlayerGuideDemo` 中的圆头音柱与像素音柱，使用生产频谱绘制组件和固定演示数据。图片截取互动演示的一帧，不播放音频、不读取听歌记录，也不代表性能测量。

更新主要页面、功能预览或三栏排行图片时，使用播放器当前界面与固定示例数据，将需要展示的截图更新到本目录。

只保留当前功能需要的展示图片；更新或移除图片时，同步维护本索引和项目 README 的引用。本机调试日志、逐轮渲染结果和历史安装器截图不放入本目录。
