# 界面示例

[返回项目说明](../../README.md)

本目录展示实际播放器组件，使用虚构曲目、自绘演示封面与隔离数据。全部图片均由当前 Material 3 Expressive 版本的 Flutter 控件离屏渲染，用于展示布局、四语言自适应排版、主题和功能，不代表实时音频或 Windows 原生桌面合成效果测试。点击链接查看原图。

项目页首的 [浅色图标](player-icon-light.png) 与 [深色图标](player-icon-dark.png) 直接取自 `app_icon.ico`、`app_icon_dark.ico` 中的 256px PNG 图层，与播放器使用的图标一致。

## 主要页面（明暗主题 × 宽窄窗口）

| 页面 | 浅色宽窗 | 浅色窄窗 | 深色宽窗 | 深色窄窗 |
| --- | --- | --- | --- | --- |
| 音乐 | [查看](library-light-wide.png) | [查看](library-light-narrow.png) | [查看](library-dark-wide.png) | [查看](library-dark-narrow.png) |
| 歌单 | [查看](playlists-light-wide.png) | [查看](playlists-light-narrow.png) | [查看](playlists-dark-wide.png) | [查看](playlists-dark-narrow.png) |
| 设置 | [查看](settings-light-wide.png) | [查看](settings-light-narrow.png) | [查看](settings-dark-wide.png) | [查看](settings-dark-narrow.png) |

## 曲库、歌词、音效与桌面功能

| 功能 | 示例 |
| --- | --- |
| 分类磁贴与艺术家视图 | [浅色拼贴磁贴](feature-category-tiles-light.png) · [深色拼贴磁贴](feature-category-tiles-dark.png) · [艺术家分类](feature-categories-light.png) |
| 多碟专辑详情与文件夹 | [多碟分段头与关联艺术家](feature-album-detail-dark.png) · [文件夹树管理](feature-folders-light.png) |
| 搜索与歌单选曲 | [深色搜索页](feature-search-dark.png) · [更改歌单所选歌曲](feature-change-selected-songs-light.png) |
| 双语注音歌词与均衡器 | [日语假名 + 英语 IPA 沉浸歌词](feature-now-playing-lyrics-dark.png) · [十段均衡器与新增预设](feature-equalizer-dark.png) |
| 歌词注音与桌面歌词设置 | [歌词注音与音标整合设置](feature-lyric-annotations-light.png) · [桌面歌词外观](feature-lyric-appearance-dark.png) · [迷你播放器歌词](feature-mini-lyrics-dark.png) |
| 歌词编辑器 | [快捷点按文本](lyric-tap-text-zh.png) · [窄窗逐字打点](lyric-tap-words-narrow-zh.png) · [传统代码编辑](lyric-code-editor-zh.png) · [逐字预览](lyric-editor-preview-zh.png) |
| 播放条与实时频谱 | [悬浮磨砂播控栏](feature-player-bar-dark.png) · [圆头与像素频谱](feature-spectrum-dark.png) |
| 音乐统计与收听排行 | [统计英雄卡片与 24 小时分布](feature-statistics-light.png) · [奖牌排行与收听习惯](statistics-rankings-light.png) |
| 资源监控与存储分类 | [侧栏与设置共用资源监控](process-resource-locations.png) · [缓存与临时文件分类占用](cache-storage-statistics.png) |
| 主题选择与桌面集成 | [主题色轮选择器](feature-theme-picker-light.png) · [桌面托盘与快捷键设置](feature-desktop-settings-light.png) |
| 特色操作指南 | [曲库与分类常用操作](manual-common-library.png) · [播放队列与进度互动演示](manual-playback-demo.png) |

## 四语言界面与弹窗示例

| 功能 | 简体中文 | English | 日本語 | 한국어 |
| --- | --- | --- | --- | --- |
| 搜索快捷筛选与历史胶囊 | [查看](search-history-zh.png) | [查看](search-history-en.png) | [查看](search-history-ja.png) | [查看](search-history-ko.png) |
| 报告问题与 15 天时效日志 | [查看](feature-report-issue-zh.png) | [查看](feature-report-issue-en.png) | [查看](feature-report-issue-ja.png) | [查看](feature-report-issue-ko.png) |
| 歌词页半透明待播预览 | [查看](feature-upcoming-zh.png) | [查看](feature-upcoming-en.png) | [查看](feature-upcoming-ja.png) | [查看](feature-upcoming-ko.png) |
| 圆头与像素频谱互动指南 | [查看](feature-spectrum-guide-zh.png) | [查看](feature-spectrum-guide-en.png) | [查看](feature-spectrum-guide-ja.png) | [查看](feature-spectrum-guide-ko.png) |
| 首次使用互动引导 | [查看](feature-onboarding-zh.png) | [查看](feature-onboarding-en.png) | [查看](feature-onboarding-ja.png) | [查看](feature-onboarding-ko.png) |
| 备份文件选择性恢复 | [查看](feature-restore-zh.png) | [查看](feature-restore-en.png) | [查看](feature-restore-ja.png) | [查看](feature-restore-ko.png) |

## 展示说明

所有窗口级示例均加载播放器内置四语字体（思源黑体 SC／JP、Google Sans、Pretendard）与 Material Symbols 图标字体，展示 Material 3 Expressive 圆角卡片、自适应胶囊分段控件与悬浮磨砂播控栏。

双语注音歌词示例同时开启离线日语假名与内置离线英语 IPA 音标（`/…/` 斜线样式），展示同句混排下的双轨上标排版与连续边缘过渡。多碟专辑详情展示 `Disc 1 / Disc 2` 碟片副标题胶囊头与关联艺术家卡片。

报告问题弹窗使用独立测试日志，展示本地毫秒时间戳、15 天自动清理提示、按会话或警告／错误筛选，以及个人路径脱敏。搜索历史、待播预览、频谱指南、首次引导与选择性恢复均分别提供中、英、日、韩四语渲染，用于对照多语言自适应布局。

只保留当前功能需要的展示图片；更新或移除图片时，同步维护本索引和四语项目 README 的引用。本机调试日志、逐轮验证中间图和历史安装器截图不放入本目录。
