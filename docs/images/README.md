# 安全的界面示例

播放器的 23 张示例已于 2026-09-08 按 26.0.5-snapshot.3 重新渲染；5 张安装器示例展示沿用的安装界面。

本目录共 28 张 PNG：`library-*`、`settings-*`、`playlists-*` 基础布局图 12 张，`feature-*` 特色图 11 张，以及 `installer-*` 安装器图 5 张。播放器图片由真实 Flutter 页面和控件离屏绘制，安装器图片由 Inno 安装器自身控件在隔离 QA 桌面绘制；全部使用虚构数据或载荷，不包含真实曲库、歌单、歌词、用户文件路径或第三方专辑封面。图文介绍见 [功能导览](../feature-tour.md)。

- 曲目、演奏组、专辑及歌单均明确标为“演示 / 虚构”。封面仅由测试代码生成抽象几何图形。
- 页面使用生产 `AudiosPage`、`SettingsPage`、`PlaylistBrowser`、`FoldersPage`、`StatisticsPage`、`CategoriesPage`、`SearchResultPage`、`CompactPlayerView`、`PlaylistSongPicker` 和 `ThemePickerDialog`；播放细节使用生产 `NowPlayingBarRow`、`SevenToneSpectrum` 与 `FrequencySpectrumPainter`。窗口框架使用生产标题栏、导航、内容面板及 `Entry` 主题，未重新手画播放器界面。
- 示例不启动原生音频、联网请求、自动更新或实时桌面材质。外框显示生产实色回退；主界面标题栏使用真实无歌词状态，迷你播放器展示新写的“演示歌词”和译文的固定暂停帧。图片不作为实时播放、置顶操作或 Windows 材质验收证据。
- 基础页面提供浅色 / 深色、1366×900 宽屏 / 600×900 窄屏。特色图按实际组件内容选择窗口尺寸；PNG 由 Flutter 自身输出，不经后期修图。
- 搜索结果来自内存中显式提供的虚构曲目，联网结果为空，没有请求任何歌源。分类曲目有完整虚构标签，测试断言未请求歌词文件。主题对话框仅打开并取消，不保存用户设置。
- 文件夹使用不存在的 `Z:\公开演示` 虚构路径；统计页的大小与播放记录均由内存注入，不检查磁盘文件。七音柱与 48 频带图使用固定虚构频谱帧，不启动播放器或伪装实时采样。
- 安装器图使用 QA 沙箱路径和虚构载荷；仅捕获安装器自身窗口，不读取或截取用户桌面。明暗主题、Logo、按钮边界与字体均由生产安装器代码绘制。
- 加载仓库内字体及生产回退列表中的 Windows `Malgun Gothic`，以显示韩语语言选项；只读取系统已有字体，不安装、复制或分发系统字体。导出时缺少该字体会失败，避免发布空白标签；各个可见图标还逐项校验字形存在。

在仓库根目录执行 `powershell -File scripts/render_public_ui.ps1` 生成全部示例；使用 `-VerifyOnly` 只运行布局与隐私边界测试，不写图片。常规 `flutter test` 不导出 PNG。

## 全部示例

| 页面 | 浅色宽屏 | 深色宽屏 | 浅色窄屏 | 深色窄屏 |
| --- | --- | --- | --- | --- |
| 音乐 | [查看](library-light-wide.png) | [查看](library-dark-wide.png) | [查看](library-light-narrow.png) | [查看](library-dark-narrow.png) |
| 歌单 | [查看](playlists-light-wide.png) | [查看](playlists-dark-wide.png) | [查看](playlists-light-narrow.png) | [查看](playlists-dark-narrow.png) |
| 设置 | [查看](settings-light-wide.png) | [查看](settings-dark-wide.png) | [查看](settings-light-narrow.png) | [查看](settings-dark-narrow.png) |

## 特色图库

| 功能 | 生产组件与说明 | 图片 |
| --- | --- | --- |
| 多维分类 | `CategoriesPage`，虚构码率区间与圆形封面 | [浅色分类](feature-categories-light.png) |
| 迷你歌词 | `CompactPlayerView`，虚构歌曲、原创演示歌词与译文的暂停帧 | [深色迷你播放器](feature-mini-lyrics-dark.png) |
| 桌面集成 | `SettingsPage` 桌面组，展示托盘、歌曲预览与真实模糊半径设置 | [桌面设置](feature-desktop-settings-light.png) |
| 歌词个性化 | `SettingsPage` 外观组，字号、文字／背景不透明度、描边与色板 | [歌词外观](feature-lyric-appearance-dark.png) |
| 手动主题 | 从生产 `ThemeSelector` 打开的 `ThemePickerDialog` | [主题选择器](feature-theme-picker-light.png) |
| 统一搜索 | `SearchResultPage`，虚构本地结果与明确为空的联网结果 | [搜索结果](feature-search-dark.png) |
| 文件夹浏览 | `FoldersPage`，不存在的虚构路径、歌曲数量与修改日期 | [文件夹页](feature-folders-light.png) |
| 播放统计 | `StatisticsPage`，内存播放记录及固定虚构文件大小 | [统计页](feature-statistics-light.png) |
| 播放条细节 | `NowPlayingBarRow`、拖动进度、切歌与队列控件，并注入固定七音柱 | [深色播放条](feature-player-bar-dark.png) |
| 更改所选歌曲 | 从真实歌单页面打开的 `PlaylistSongPicker` 生产弹窗 | [选曲弹窗](feature-change-selected-songs-light.png) |
| 音乐频谱 | `FrequencySpectrumPainter` 的 48 频带音柱与 `SevenToneSpectrum`，固定虚构帧 | [深色频谱](feature-spectrum-dark.png) |

## 安装器图库

| 阶段 | 说明 | 图片 |
| --- | --- | --- |
| RCE 开场 | 浅色主题的透明 RCE 标识 | [RCE 浅色](installer-brand-rce-light.png) |
| DanRuguo 开场 | 深色主题的透明 DanRuguo 标识 | [DanRuguo 深色](installer-brand-danruguo-dark.png) |
| 选择位置 | 路径编辑、快捷方式与对齐后的原生按钮 | [目录页](installer-directory-light.png) |
| 安装中 | 深色背景、主题 Logo 与安装进度 | [进度页](installer-installing-dark.png) |
| 安装完成 | 内容列中的启动、删除安装器和完成按钮 | [完成页](installer-finished-light.png) |

桌面设置图中的“系统托盘尚未就绪”是离屏环境未启动系统托盘的真实状态，不通过伪造原生就绪状态隐藏该提示。

对应测试：`test/public_ui_showcase_test.dart`。生成前应等待页面修改完成并串行占用 Flutter 测试锁。公开旧截图只从当前发布树移除，历史提交和旧版本不在本轮改写范围内。
