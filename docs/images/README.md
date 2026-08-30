# 安全的界面示例

本目录共 18 张 PNG：`library-*`、`settings-*`、`playlists-*` 基础布局图 12 张，以及 `feature-*` 特色图 6 张。它们均由真实 Flutter 页面和控件离屏绘制，使用完全虚构的内存数据，不是用户桌面截图，也不包含真实曲库、歌单、歌词、文件路径或第三方专辑封面。图文介绍见 [功能导览](../feature-tour.md)。

- 曲目、演奏组、作曲组、专辑及歌单均明确标为“演示 / 虚构”。封面仅由测试代码生成抽象几何图形。
- 页面使用生产 `AudiosPage`、`SettingsPage`、`PlaylistBrowser`、`CategoriesPage`、`SearchResultPage`、`CompactPlayerView` 和 `ThemePickerDialog`；窗口框架使用生产标题栏、导航、内容面板及 `Entry` 主题。未重新手画播放器界面。
- 示例不启动原生音频、联网请求、自动更新或实时桌面材质。外框显示生产实色回退；主界面标题栏使用真实无歌词状态，迷你播放器展示新写的“演示歌词”和译文的固定暂停帧。图片不作为实时播放、置顶操作或 Windows 材质验收证据。
- 基础页面提供浅色 / 深色、1366×900 宽屏 / 600×900 窄屏。特色图按实际组件内容选择窗口尺寸；PNG 由 Flutter 自身输出，不经后期修图。
- 搜索结果来自内存中显式提供的虚构曲目，联网结果为空，没有请求任何歌源。分类曲目有完整虚构标签，测试断言未请求歌词文件。主题对话框仅打开并取消，不保存用户设置。
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
| 多维分类 | `CategoriesPage`，虚构作曲标签分组与圆形封面 | [浅色分类](feature-categories-light.png) |
| 迷你歌词 | `CompactPlayerView`，虚构歌曲、原创演示歌词与译文的暂停帧 | [深色迷你播放器](feature-mini-lyrics-dark.png) |
| 桌面集成 | `SettingsPage` 桌面组，展示托盘、歌曲预览与真实模糊半径设置 | [桌面设置](feature-desktop-settings-light.png) |
| 歌词个性化 | `SettingsPage` 外观组，字号、文字／背景不透明度、描边与色板 | [歌词外观](feature-lyric-appearance-dark.png) |
| 手动主题 | 从生产 `ThemeSelector` 打开的 `ThemePickerDialog` | [主题选择器](feature-theme-picker-light.png) |
| 统一搜索 | `SearchResultPage`，虚构本地结果与明确为空的联网结果 | [搜索结果](feature-search-dark.png) |

桌面设置图中的“系统托盘尚未就绪”是离屏环境未启动系统托盘的真实状态，不通过伪造原生就绪状态隐藏该提示。

对应测试：`test/public_ui_showcase_test.dart`。生成前应等待页面修改完成并串行占用 Flutter 测试锁。公开旧截图只从当前发布树移除，历史提交和旧版本不在本轮改写范围内。
