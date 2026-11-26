<div align="center">

<p>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/player-icon-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/images/player-icon-light.png">
    <img src="docs/images/player-icon-light.png" alt="Dan Player 播放器图标" width="128">
  </picture>
</p>

<h1>Dan Player</h1>

<p><strong>为你的本地音乐收藏而设计。</strong></p>

<p>面向 Windows x64 的本地优先音乐播放器，采用 Material 3 Expressive 桌面设计，<br>
兼顾曲库整理、双语注音歌词、高保真音频控制与轻量低耗的桌面体验。</p>

<p align="center">
  <a href="https://github.com/DanRuguo/dan_player/releases/latest"><img src="https://img.shields.io/github/v/release/DanRuguo/dan_player?style=flat&amp;labelColor=374151&amp;label=stable&amp;logo=github&amp;logoColor=white&amp;color=2563EB" alt="最新稳定版"></a>
  <a href="https://github.com/DanRuguo/dan_player/releases"><img src="https://img.shields.io/github/v/release/DanRuguo/dan_player?style=flat&amp;labelColor=374151&amp;include_prereleases&amp;filter=v%2A-snapshot.%2A&amp;sort=semver&amp;label=preview&amp;color=D97706" alt="最新 snapshot 预览版"></a>
  <a href="https://github.com/DanRuguo/dan_player/releases"><img src="https://img.shields.io/github/downloads/DanRuguo/dan_player/total?style=flat&amp;labelColor=374151&amp;label=downloads&amp;color=059669" alt="GitHub Release 附件下载量"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/DanRuguo/dan_player?style=flat&amp;labelColor=374151&amp;label=license&amp;color=64748B" alt="项目许可证"></a>
</p>

<p align="center">
  <a href="#download"><img src="https://img.shields.io/badge/platform-Windows%20x64-0078D4?style=flat&amp;labelColor=374151" alt="平台：Windows x64"></a>
  <a href="#development"><img src="https://img.shields.io/badge/Flutter-UI-02569B?style=flat&amp;labelColor=374151&amp;logo=flutter&amp;logoColor=white" alt="Flutter：界面"></a>
  <a href="#development"><img src="https://img.shields.io/badge/Rust-Bridge-B45309?style=flat&amp;labelColor=374151&amp;logo=rust&amp;logoColor=white" alt="Rust：原生桥接"></a>
  <a href="https://www.un4seen.com/bass.html"><img src="https://img.shields.io/badge/BASS-Audio-6750A4?style=flat&amp;labelColor=374151" alt="BASS：音频播放"></a>
</p>

<p>
  <a href="https://github.com/DanRuguo/dan_player/releases/latest"><strong>下载稳定版</strong></a> ·
  <a href="https://github.com/DanRuguo/dan_player/releases">预览版与历史版本</a> ·
  <a href="https://github.com/DanRuguo/dan_player/releases">更新记录</a> ·
  <a href="https://github.com/DanRuguo/dan_player/issues/new/choose">问题反馈</a>
</p>

<p>
  <strong>简体中文</strong> ·
  <a href="README.en.md">English</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a>
</p>

</div>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/library-dark-wide.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/images/library-light-wide.png">
    <img src="docs/images/library-light-wide.png" alt="Dan Player 音乐主页：Material 3 Expressive 桌面布局与悬浮播控栏，使用虚构演示数据" width="1200">
  </picture>
</p>

<p align="center">
  <a href="#download">下载与安装</a> ·
  <a href="#features">特色</a> ·
  <a href="#screenshots">界面一览</a> ·
  <a href="#quick-start">开始使用</a> ·
  <a href="#development">开发与构建</a>
</p>

<a id="安装与使用"></a>
<a id="download"></a>

## 下载与安装

| 渠道 | 适用场景 | 下载入口 |
| --- | --- | --- |
| **最新稳定版** | 日常收听与稳妥升级，版本以发布页为准 | [稳定版安装器、便携 ZIP 与校验文件](https://github.com/DanRuguo/dan_player/releases/latest) |
| **预览版（Snapshot）** | 抢先体验最新界面重构、歌词注音与音频功能 | [预览版与独立可选组件](https://github.com/DanRuguo/dan_player/releases) |

**安装版**采用 Material 3 Expressive 向导，支持原位升级并保留已安装的扩展组件；**便携版**请完整解压整个 ZIP 后运行 `Dan Player.exe`，不要单独复制可执行文件。桌面歌词由同一程序按需启动独立进程。

完整便携包已内置无损减重的**音频专用版 FFmpeg 7.1.1** 与**三份离线日语假名词库**（主词典、词汇补充、汉字读音补充）及对应许可，解压后即可用于转码、试听裁剪与离线假名注音。精简安装器不包含这两项体积较大的组件；需要时可在播放器设置中一键下载，自动核验固定字节数与 SHA-256、安装至 `tool` 目录并复检（当前预览版组件托管于 [v26.1.2-snapshot.8 发布页](https://github.com/DanRuguo/dan_player/releases/tag/v26.1.2-snapshot.8)）。**离线英语国际音标（IPA）词库体积不足 1 MB，已在安装版和便携版中直接内置，无需额外下载。**

> **下载与签名说明**：自有程序使用 RCEIT.Inc 自签名证书，Windows 仍可能显示信任提示；安装器不会自动安装受信任根证书。旧签名版本请手动下载新安装器升级。预览版不替换稳定版 Latest；升级前建议通过播放器的“备份与恢复”保存个人资料。

<a id="下载校验"></a>
<a id="download-verification"></a>

<details>
<summary><strong>核对下载文件的 SHA-256</strong></summary>

从同一 Release 下载程序及对应校验文件：便携 ZIP 对照 `SHA256SUMS`，安装器对照同名 `.exe.sha256`。计算文件的 SHA-256，同时与 GitHub 资产摘要核对。将下面的占位文件名替换为实际下载文件名：

```powershell
Get-FileHash -LiteralPath '.\DanPlayer-版本号-Setup-x64.exe' -Algorithm SHA256
```

摘要一致表示文件内容与发布资产相符，不等同于 Windows 对签名证书的信任。请始终核对下载来源，不要通过关闭系统安全功能来处理来源不明的文件。

</details>

<a id="features"></a>

## 特色

- **曲库浏览与语法检索：** 按艺术家、专辑、码率、时长、语言、格式、来源与文件夹浏览；支持多碟专辑分段头与碟片副标题、Opus／容器有效码率识别、CUE 分轨、元数据批量编辑与曲库健康检查。搜索页提供多词、拼音首字母与容错匹配、五项高级语法快捷胶囊，以及可一键清空的历史记录。
- **歌单多视图与队列批处理：** 嵌套子歌单、智能歌单规则、拖动排序，保留列表／方形网格／圆形封面／树状四视图及跨视图封面飞行追踪。播放队列支持多选、Shift 连选、搜索结果勾选、批量移至下一首或队尾、移除、保存导出，以及完整的撤销与重做；支持导入 M3U／M3U8／PLS／XSPF 本地引用。
- **批量音频转换与导出：** 在“导出音乐文件夹”中选择原样复制或转换至 MP3／Opus／FLAC，支持音质预设、CUE 自动分轨、进度与取消，并输出保留顺序与重复项的相对路径 M3U8（转换需 FFmpeg，原文件保持不变）。
- **高保真播放与片段控制：** 十段均衡器（内置流行、摇滚、古典、爵士、人声、低音增强及电子、原声、通勤等预设，支持导入导出）、ReplayGain 响度均衡、独立升降调、保音高变速、WASAPI 独占输出、逐曲续播、A–B 片段循环与全库书签；可选交叉淡化、同专辑免交叉及跳过曲首／曲尾静音。
- **双语注音歌词与创作工作台：** 支持逐字强调、双语译文毫秒容差对齐、离线日语假名与**内置离线英语 IPA 音标**（纯音标／`/…/`／`[…]` 三种样式，支持同句中英日混排并存与纯离线批量生成）；兼容 LRC／QRC／KRC／TTML（含 `itunes:timing`）与内嵌同步／纯文本歌词回退。配备两遍可分离着色器连续边缘模糊，以及快捷点按与传统文本两种歌词编辑器。
- **封面光影与平滑过渡：** 支持内嵌、同目录多命名封面与动态 GIF；播放大封面具备柔和轮廓辉光、局部水滴折射与点击波纹；分类切换采用 GPU 离屏纹理交叉叠化避免暗场闪烁，专辑详情与艺术家详情实现像素级对齐、双向封面变形飞行及关联卡片一键速播。
- **频谱、动效与低耗策略：** 进度条与封面四周支持圆头音柱和平滑像素频谱；提供十类独立动画开关、系统减少动画联动、窗口隐藏停钟、自适应／固定刷新率及一键省电预设，并可选开启原生 XAudio2 轻触控反馈音效。
- **Material 3 Expressive 桌面集成：** 中／英／日／韩四语自适应排版、明暗主题与封面动态取色、迷你播放器、抗锯齿圆角系统托盘播控菜单（带封面与三键控制），以及互斥显示的桌面歌词／任务栏内嵌歌词（冷启动未播歌时自动隐藏空白 Windows SMTC 浮层）。
- **收听统计、空间分析与问题诊断：** 统计页提供收听时长与活跃时段 KPI 概览、24 小时分布、90 天星期收听习惯及奖牌排行榜；支持不改动音频文件的个人评分与标签、侧栏／歌词页／设置共用的按需 CPU／GPU／内存监控、应用数据分类占用，以及带 **15 天自动清理与毫秒时间戳日志**、支持个人路径脱敏的弹出式“报告问题”工具。
- **加密备份与选择性恢复：** 按需勾选本地音乐文件夹、曲库索引、歌单、统计、设置与缓存保存为 `.bak`，支持密码加密、选择性恢复、共享音频去重与随时取消。

歌词与评论默认优先读取本地内容和已保存缓存；自动联网可在设置中按需开启（临时网络超时按曲目指数退避，手动刷新立即重试）。联网音乐与自定义歌源接入方式见 [自定义歌源 API](docs/custom-music-source-api.md)。

日语假名与英语音标均保存在独立派生缓存中，不修改原歌词文件。联网日语注音需自行配置本机保存的 Yahoo! JAPAN Client ID；离线词典对专有名词与多音词仍有局限，可在歌词工作台中审阅修订。

<a id="screenshots"></a>

## 界面一览

### 分类磁贴、多碟专辑详情与嵌套歌单

<picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/feature-category-tiles-dark.png"><img src="docs/images/feature-category-tiles-light.png" alt="分类页拼贴封面磁贴与自适应胶囊工具栏，使用虚构演示数据" width="1200"></picture>

| 嵌套歌单与四视图切换 | 多碟专辑详情与关联艺术家速播 |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/playlists-dark-wide.png"><img src="docs/images/playlists-light-wide.png" alt="歌单页面：圆形封面视图、子歌单与自适应胶囊栏" width="600"></picture> | ![多碟专辑详情页：Disc 分段胶囊头、总时长与关联艺术家卡片](docs/images/feature-album-detail-dark.png) |

### 沉浸双语注音歌词、均衡器与频谱待播

| 日语假名 + 英语 IPA 沉浸歌词页 | 十段均衡器与电子／原声／通勤预设 |
| --- | --- |
| ![正在播放歌词页：封面辉光、日语假名与英语国际音标同句并存](docs/images/feature-now-playing-lyrics-dark.png) | ![十段均衡器弹窗：频段增益胶囊与多场景预设](docs/images/feature-equalizer-dark.png) |

| 四首半透明待播卡片 | 圆头音柱与像素频谱互动指南 |
| --- | --- |
| ![中文待播预览：四首半透明卡片与双列布局](docs/images/feature-upcoming-zh.png) | ![中文特色指南：圆头音柱与像素频谱演示](docs/images/feature-spectrum-guide-zh.png) |

### 统一注音设置、迷你播放器与两种歌词编辑器

| 歌词注音与音标整合设置 | 迷你播放器与双语歌词 |
| --- | --- |
| ![设置页：日语假名与内置英语 IPA 音标样式及批量生成卡片](docs/images/feature-lyric-annotations-light.png) | ![迷你播放器：专辑封面、双语注音歌词与胶囊控制](docs/images/feature-mini-lyrics-dark.png) |

| 快捷点按：准备正文、翻译与注音 | 快捷点按：窄窗逐字打点 |
| --- | --- |
| ![快捷点按编辑器的多轨文本输入](docs/images/lyric-tap-text-zh.png) | ![窄窗中的快捷点按逐字打点](docs/images/lyric-tap-words-narrow-zh.png) |

| 传统码字：QRC 歌词代码 | 传统码字：逐字预览 |
| --- | --- |
| ![传统歌词编辑器的 QRC 代码编辑](docs/images/lyric-code-editor-zh.png) | ![传统歌词编辑器的逐字同步预览](docs/images/lyric-editor-preview-zh.png) |

### 快捷语法搜索、文件夹树与听歌统计

| 搜索快捷胶囊与历史清空 | 文件夹树与目录曲目 |
| --- | --- |
| ![搜索页：高级语法快捷胶囊、最近搜索清空与居中历史标签](docs/images/search-history-zh.png) | ![文件夹页面：目录层级树与曲目列表](docs/images/feature-folders-light.png) |

| 音乐统计总览与 24 小时分布 | 奖牌排行与收听习惯 |
| --- | --- |
| ![音乐统计页：英雄横幅、四宫格 KPI 与 24 小时分布图](docs/images/feature-statistics-light.png) | ![统计页：播放排行奖牌徽标与收听分布](docs/images/statistics-rankings-light.png) |

### 外观设置、15 天日志诊断、资源监控与备份迁移

| 外观与分组设置 | 报告问题弹窗与 15 天时效日志 |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-dark-wide.png"><img src="docs/images/settings-light-wide.png" alt="设置页面：分组胶囊与自适应分段控件" width="600"></picture> | ![报告问题弹窗：问题分类、路径脱敏与 15 天毫秒时间戳日志筛选](docs/images/feature-report-issue-zh.png) |

| 侧栏与设置共用按需资源监控 | 应用缓存与临时文件占用 |
| --- | --- |
| ![侧栏折线与设置页共用的进程 CPU、GPU、内存监控](docs/images/process-resource-locations.png) | ![缓存、用户资料与临时文件分类空间占用](docs/images/cache-storage-statistics.png) |

| 特色操作指南：常用说明 | 特色操作指南：互动进度与队列 |
| --- | --- |
| ![音乐、分类与歌单的操作说明](docs/images/manual-common-library.png) | ![进度定位互动演示与队列整理说明](docs/images/manual-playback-demo.png) |

| 首次引导：四语切换与播放体验 | 加密备份选择性恢复 |
| --- | --- |
| ![首次使用互动引导界面](docs/images/feature-onboarding-zh.png) | ![选择要恢复的播放器资料与音乐文件夹](docs/images/feature-restore-zh.png) |

<sub>以上图片均由播放器当前 Flutter 控件与隔离演示数据离屏渲染，用于展示界面布局与功能，不代表实时声卡采样或 Windows 原生桌面材质测试。完整的宽窄窗口、明暗主题与中／英／日／韩四语言图集见 <a href="docs/images/README.md">界面图库（64 张）</a>。</sub>

<a id="quick-start"></a>

## 开始使用

**添加音乐。** 导入音乐文件或文件夹后，在音乐、分类、歌单和文件夹页浏览；支持嵌套子歌单与拖动排序组织收藏。

**整理个人偏好。** 进入“分类 → 个人整理 → 歌曲”，查看评过分或添加过个人标签的歌曲，并按日期、评分、标签筛选。个人评分和标签保存在播放器资料中，**不会写入音乐文件**；“编辑信息”和“批量编辑标签”则会修改音频文件元数据，保存前请核对变更预览。

**记住喜欢的片段。** 在正在播放页面的“更多 → 播放书签”中保存当前位置或 A–B 片段，再到“分类 → 个人整理 → 全库书签”集中查找。全库书签中的播放按钮从保存的起点起播；恢复片段循环时，在对应歌曲的“播放书签”中选择该 A–B 书签。

**备份自己的资料。** 设置中的“备份与恢复”可按需保存播放器资料和本地音乐，并支持密码加密及选择性恢复。程序升级与资料备份是不同操作，安装目录中的程序文件不能替代曲库、歌单与设置备份（单个加密备份须小于约 64 GiB）。

<details>
<summary><strong>常用快捷键</strong></summary>

| 按键 | 操作 |
| --- | --- |
| `Space` | 播放／暂停 |
| `Ctrl + Left` / `Ctrl + Right` | 上一首／下一首 |
| `Left` / `Right` | 后退／前进 5 秒 |
| `Ctrl + M` | 切换迷你播放器 |
| `F11` | 切换全屏 |
| `F1` | 查看快捷键 |

</details>

<a id="documentation"></a>

## 文档与反馈

[界面图库](docs/images/README.md) · [自定义歌源 API](docs/custom-music-source-api.md) · [go-music-api 配置示例](docs/examples/go-music-api-jamendo.json) · [全部发行版本](https://github.com/DanRuguo/dan_player/releases)

配置示例中的服务地址需要替换为自己部署的地址。遇到问题时，可先查看 [已有 Issues](https://github.com/DanRuguo/dan_player/issues)，或在播放器“设置 → 更新与关于 → 报告问题”中筛选最近 15 天的带时间戳运行日志（默认隐藏个人目录路径），一键生成环境摘要并打开 [GitHub 反馈草稿](https://github.com/DanRuguo/dan_player/issues/new/choose)。请不要上传私人音乐文件、凭据或完整个人目录。

<a id="源码与构建"></a>
<a id="development"></a>

## 开发与构建

基于 **Flutter、Rust 与 BASS**。需要 Flutter、Rust 和 Visual Studio 桌面 C++ 工作负载；Dart 约束见 [pubspec.yaml](pubspec.yaml)，依赖版本以 [pubspec.lock](pubspec.lock) 与 [rust/Cargo.lock](rust/Cargo.lock) 为准。Windows 持续集成入口见 [Windows CI](.github/workflows/windows_ci.yml)。

<details>
<summary><strong>源码结构、调试与定向检查</strong></summary>

| 目录 | 用途 |
| --- | --- |
| [lib/](lib/) | 主界面、曲库、歌词注音、运行日志、播放服务与数据模型 |
| [third_party/desktop_lyric/](third_party/desktop_lyric/) | 共用的桌面歌词组件、四语词条、内置字体资源与 Windows 宿主 |
| [rust/](rust/)、[rust_builder/](rust_builder/) | 标签与封面解析、词库构建工具、Flutter/Rust 桥接与 Cargokit 支持 |
| [windows/](windows/)、[installer/](installer/) | Windows 托盘／触控音效集成与 Material 3 Expressive 原生安装器 |
| [scripts/](scripts/) | 依赖准备、组件组装、构建、签名与产物校验 |
| [assets/](assets/)、[shaders/](shaders/)、[docs/](docs/) | 内置英语音标词库、渐变模糊与光效着色器、接口说明与公开图库 |

在仓库根目录执行，使用独立资料目录，避免调试影响日常曲库与设置：

```powershell
$env:DAN_PLAYER_DATA_DIR = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path '../tool/qa-local/readme-debug'))
flutter pub get
flutter run -d windows
```

运行前需准备 BASS 运行库，见 `scripts/prepare_bass_runtime.ps1` 与 `scripts/prepare_bass_fx_runtime.ps1`。本机 SDK、缓存和签名路径不放入源码仓库。

按当前改动准备隔离夹具，选择实际存在的入口做定向 Dart/Widget、Rust 或 Windows 验证；不恢复已退役的历史测试集合。Dart 使用 `flutter test --no-pub <测试入口>`，Rust 使用 `cargo test --manifest-path rust/Cargo.toml --locked <测试筛选>`。UI 应用真实组件核对直接受影响的语言、窗宽和文字缩放；原生采帧使用独立验收窗口。

</details>

<details>
<summary><strong>Windows 构建与发行</strong></summary>

现有发布脚本使用工作区布局：源码在 `dan_player/`，同级 `tool/` 放置工具链和缓存，`dist/` 接收产物。`build_windows_release.ps1` 准备依赖、核对可复用来源与产物、编译 Windows 程序、检查字体及运行库，并按参数签名或组装。

```powershell
# 使用上述工作区布局，在源码仓库运行；无签名证书时：
.\scripts\build_windows_release.ps1 -SkipSigning
```

`-SkipPackaging` 跳过便携包组装；`-NoRestore` 使用已恢复的依赖。安装器使用 `scripts/build_windows_installer.ps1`，便携包和安装器分别由 `verify_local_release.ps1`、`verify_windows_installer.ps1` 核验。需要随便携包附带可选组件时，按 `scripts/ffmpeg_runtime_manifest.json` 与 `scripts/support/bundled_japanese_readings.json` 准备固定运行库后使用 `scripts/assemble_windows_release.ps1 -IncludeOptionalComponents`。

</details>

仅维护必要的长期文档。本机开发笔记、历史 QA、临时日志、工具缓存、个人资料和签名私钥不进入源码仓库；公开界面资源集中在 `docs/images/`，随资源变更同步维护引用。

<a id="license"></a>

## 许可证与致谢

本项目按 [LICENSE](LICENSE) 分发；第三方组件保留各自许可，BASS 的使用与分发须遵守其官方许可。

主程序与桌面歌词共用一份字体资源，支持统一选择、四语言分别选择，以及混合文字按语种使用字体。内置 [思源黑体 SC／JP](licenses/SOURCE-HAN-SANS/PROVENANCE.md)、[Google Sans](licenses/GOOGLE-SANS/PROVENANCE.md) 和 [Pretendard](licenses/PRETENDARD/PROVENANCE.md)，均按 SIL Open Font License 1.1 分发；原版许可与来源随便携包和安装器提供。`DanPingFangSC` 内部兼容别名对应思源黑体 SC，不包含苹果字体。

Dan Player 基于 [Ferry-200/coriander_player](https://github.com/Ferry-200/coriander_player) 修改，感谢原作者提供的播放器基础、曲库结构和歌词体验。同时感谢 [desktop_lyric](https://github.com/Ferry-200/desktop_lyric)、[music_api_dart](https://github.com/Ferry-200/music_api_dart)、[BASS](https://www.un4seen.com/bass.html)、[Lofty](https://crates.io/crates/lofty)、[flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge) 及 [Flutter](https://flutter.dev/) 与 Material Design。

内置英语音标词库的许可与来源见 [CMUDict](licenses/CMUDICT/PROVENANCE.md)；离线假名字典的许可与来源见 [IPADIC](licenses/IPADIC/PROVENANCE.md) / [EDRDG](licenses/EDRDG/PROVENANCE.md) 和 [Lindera](licenses/LINDERA/LICENSE)。联网注音：[Web Services by Yahoo! JAPAN](https://developer.yahoo.co.jp/sitemap/)。

<sub>徽章由 <a href="https://shields.io/">Shields.io</a> 提供。下载量统计 Release 附件的下载次数，不等于用户数或安装量；技术徽章仅说明使用的技术，不声明最低支持版本。</sub>
