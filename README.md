<div align="center">

<p>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/images/RCE_logo_white.png">
    <source media="(prefers-color-scheme: light)" srcset="assets/images/RCE_logo_transparent.png">
    <img src="assets/images/RCE_logo_transparent.png" alt="RCE 品牌标志" width="128">
  </picture>
</p>

<h1>Dan Player</h1>

<p><strong>为你的本地音乐收藏而设计。</strong></p>

<p>面向 Windows x64 的音乐播放器，兼顾曲库整理、歌词体验与桌面交互。<br>
以本地收听为核心，也支持联网音乐与自定义歌源。</p>

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
  <a href="https://github.com/DanRuguo/dan_player/releases">历史版本</a> ·
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
    <img src="docs/images/library-light-wide.png" alt="Dan Player 音乐主页：本地曲库与播放控制，使用虚构演示数据" width="1200">
  </picture>
</p>

<p align="center">
  <a href="#download">下载与安装</a> ·
  <a href="#features">功能</a> ·
  <a href="#screenshots">界面一览</a> ·
  <a href="#quick-start">开始使用</a> ·
  <a href="#development">开发与构建</a>
</p>

<a id="安装与使用"></a>

<a id="download"></a>

## 下载与安装

| 版本 | 适用场景 | 下载 |
| --- | --- | --- |
| **26.0.5 · 稳定版** | 日常收听，优先选择正式发行版本 | [安装器、便携 ZIP 与校验文件](https://github.com/DanRuguo/dan_player/releases/tag/v26.0.5) |

**安装版**运行安装器，支持原位升级；**便携版**完整解压 ZIP 后运行 `Dan Player.exe`，不要只复制一个 EXE。26.0.5 的桌面歌词由同一程序启动独立进程。

> **下载与签名说明**：自有程序使用 RCEIT.Inc 自签名证书，Windows 仍可能显示信任提示；安装器不会自动安装信任证书。旧签名版本请手动下载新安装器升级。预览版不替换稳定版 Latest；升级前建议通过播放器的“备份与恢复”保存个人资料。

<a id="下载校验"></a>
<a id="download-verification"></a>

<details>
<summary><strong>核对下载文件的 SHA-256</strong></summary>

从同一 Release 下载程序及 `SHA256SUMS` 校验文件，计算安装器或 ZIP 的 SHA-256，与校验文件及 GitHub 资产摘要核对。将下面的占位文件名替换为实际下载文件名：

```powershell
Get-FileHash -LiteralPath '.\DanPlayer-版本号-Setup-x64.exe' -Algorithm SHA256
```

摘要一致表示文件内容与发布资产相符，不等同于 Windows 对签名证书的信任。请始终核对下载来源，不要通过关闭系统安全功能来处理来源不明的文件。

</details>

<a id="features"></a>

## 功能

从找到一首歌，到整理整套收藏，常用操作都围绕同一份曲库展开。

| 方向 | 主要能力 |
| --- | --- |
| **曲库与检索** | 按艺术家、专辑、格式和文件夹浏览；搜索歌曲，批量整理元数据，检查曲库健康。 |
| **歌单与队列** | 嵌套歌单、拖动排序、智能条件与 M3U8 导入导出；队列保存、撤销，以及歌单回收。 |
| **歌词与阅读** | 歌词匹配、编辑、修订、锁定和时间校准；全文检索、桌面歌词与迷你播放器。 |
| **播放与定位** | CUE 分轨、均衡器与响度均衡、逐曲续播、A–B 循环；保存时间点或片段，并在全库书签中集中管理。 |
| **个人音乐资料** | 个人评分、标签与筛选；查看听歌时段、歌曲排行、曲库构成和文件占用。 |
| **Windows 桌面体验** | 随封面变化的配色、明暗主题、四语言界面；快捷键、迷你窗口、任务栏预览与播放诊断。 |

以上功能已包含在 26.0.5 正式版中；具体更新请查看对应 [Release 更新说明](https://github.com/DanRuguo/dan_player/releases)。

联网音乐与自定义歌源可作为本地曲库的补充。自定义服务按实际声明的能力提供检索、歌词等功能，接入方式见 [自定义歌源 API](docs/custom-music-source-api.md)。

### 26.0.5 新增体验

- **分类磁贴：** 矩形封面支持 1×1、2×1、1×2、2×2，自定义拖动排序和可选自动填隙；文字直接显示在封面内，按图像明暗自动选择文字颜色。
- **备份与恢复：** 将本地音乐按文件夹、曲库索引、歌单、统计、设置与缓存资源按需保存到一个 `.bak` 文件，可选密码加密；恢复时可重新选择文件夹和资料项目，也可一键全选。请妥善保存密码；单个加密备份须小于约 64 GiB，更大的收藏可分文件夹备份。
- **性能与引导：** 一键省电或高性能，关闭后恢复之前的相关设置；支持刷新率与频谱档位设置，首次使用提供功能引导，开屏等待更短。

同时改进歌单视图、音量面板、菜单交互、原生模糊切换及窗口尺寸恢复。磁贴布局与文字采样按需计算并缓存，磁贴动画结束后停止该动画的刷新；实际功耗取决于设备和设置。

<a id="screenshots"></a>

## 界面一览

### 整理收藏，也保留自己的使用习惯

| 歌单与收藏 | 外观与设置 |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/playlists-dark-wide.png"><img src="docs/images/playlists-light-wide.png" alt="歌单页面，展示收藏与列表组织" width="600"></picture> | <picture><source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-dark-wide.png"><img src="docs/images/settings-light-wide.png" alt="设置页面，展示主题与分组设置" width="600"></picture> |

### 找到想听的歌曲，专注眼前的歌词

| 歌曲搜索 | 迷你播放器与歌词 |
| --- | --- |
| ![歌曲搜索界面，使用虚构曲目](docs/images/feature-search-dark.png) | ![迷你播放器与歌词，使用虚构演示内容](docs/images/feature-mini-lyrics-dark.png) |

### 从收听记录重新认识自己的曲库

![音乐统计与歌曲排行，使用虚构演示数据](docs/images/statistics-rankings-light.png)

<sub>图片均复用仓库内的生产控件渲染资源，使用虚构曲目与隔离资料；用于展示界面，不代表实时音频或原生桌面效果测试。更多明暗主题、宽窄窗口和功能示例见 <a href="docs/images/README.md">界面图库</a>。</sub>

<a id="quick-start"></a>

## 开始使用

**添加音乐。** 导入音乐文件或文件夹后，在音乐、分类和歌单页浏览；使用嵌套歌单与拖动排序组织收藏。

**整理个人偏好。** 26.0.5 可进入“分类 → 个人整理 → 歌曲”，查看评过分或添加过个人标签的歌曲，并按日期、评分、标签筛选。个人评分和标签保存在播放器资料中，**不会写入音乐文件**；“编辑信息”和“批量编辑标签”则会修改文件元数据，保存前请核对变更预览。

**记住喜欢的片段。** 在正在播放页面的“更多 → 播放书签”中保存当前位置或 A–B 片段，再到“分类 → 个人整理 → 全库书签”集中查找。全库书签中的播放按钮从保存的起点播放；恢复片段循环时，在对应歌曲的“播放书签”中选择该 A–B 书签。

**备份自己的资料。** 设置中的“备份与恢复”可按需保存播放器资料和本地音乐，并支持加密及选择性恢复。程序升级与资料备份是不同操作，安装目录中的程序文件不能替代曲库、歌单与设置备份。

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

配置示例中的服务地址需要替换为自己部署的地址。遇到问题时，请先查看 [已有 Issues](https://github.com/DanRuguo/dan_player/issues)，再通过 [反馈模板](https://github.com/DanRuguo/dan_player/issues/new/choose) 提交播放器版本、复现步骤，以及相关界面语言、窗口大小或显示缩放。播放问题可附脱敏诊断；请不要上传私人音乐文件、凭据或完整个人目录。

<a id="源码与构建"></a>
<a id="development"></a>

## 开发与构建

基于 **Flutter、Rust 与 BASS**。需要 Flutter、Rust 和 Visual Studio 桌面 C++ 工作负载；Dart 约束见 [pubspec.yaml](pubspec.yaml)，依赖版本以 [pubspec.lock](pubspec.lock) 与 [rust/Cargo.lock](rust/Cargo.lock) 为准。Windows 持续集成入口见 [Windows CI](.github/workflows/windows_ci.yml)。

<details>
<summary><strong>源码结构、调试与定向检查</strong></summary>

| 目录 | 用途 |
| --- | --- |
| `lib/` | 界面、曲库和播放服务 |
| `rust/`、`rust_builder/` | 标签处理与 Flutter/Rust 桥接 |
| `windows/`、`installer/` | Windows 集成与安装器 |
| `third_party/` | 随附组件及其许可证 |
| `test/`、`test_driver/` | 自动化测试 |
| `scripts/` | 构建、校验与发布脚本 |
| `docs/` | 接口说明、示例和界面图片 |

在仓库根目录执行，使用独立资料目录，避免调试影响日常曲库与设置：

```powershell
$env:DAN_PLAYER_DATA_DIR = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path '../tool/qa-data/readme-debug'))
flutter pub get
flutter run -d windows
```

运行前需准备 BASS 运行库，相关脚本为 `scripts/prepare_bass_runtime.ps1` 与 `scripts/prepare_bass_fx_runtime.ps1`。本机 SDK、运行库缓存和签名配置路径只记录在源码仓库外的 `DEVELOPMENT.md`。

按模块集中验证，只运行与改动有关的检查；不要每增加一个功能就完整回归、构建和签名。例如统计与详情布局改动可运行：

```powershell
flutter test test/statistics_visualization_test.dart test/detail_diagnostics_layout_test.dart --no-pub
```

集成收尾使用 `scripts/verify_interaction_regressions.ps1`。UI 改动须使用真实 Flutter 控件渲染核对；公开图片通过 `scripts/render_public_ui.ps1` 与隔离虚构资料生成，覆盖语言、窗口宽度和文字缩放。控件渲染不替代真实音频设备与 Windows 桌面集成检查。

</details>

<details>
<summary><strong>Windows 构建与发行</strong></summary>

现有发布脚本使用工作区布局：源码在 `dan_player/`，同级 `tool/` 放置工具链和缓存，`dist/` 接收产物。`build_windows_release.ps1` 检查依赖、运行发布门禁、构建 Windows 程序并校验字体与运行库。

```powershell
# 使用上述工作区布局，在源码仓库运行；无签名证书时：
.\scripts\build_windows_release.ps1 -SkipSigning
```

`-SkipPackaging` 跳过便携包组装；`-NoRestore` 使用已恢复的依赖。正式签名需要单独配置证书。安装器使用 `scripts/build_windows_installer.ps1`，便携包和安装器分别由 `verify_local_release.ps1`、`verify_windows_installer.ps1` 核验。

同一代码状态复用已通过的检查与构建产物，失败只重试必要阶段；签名后核对源码提交、测试收据、产物 SHA-256 与签名，再执行必要的 GitHub 发布流程。预览版保持 prerelease，不替换稳定版 Latest，不以省略校验来精简流程。

</details>

仅维护必要的长期文档。本机开发笔记、历史 QA、临时日志、工具缓存、个人资料和签名私钥不进入源码仓库；公开界面资源集中在 `docs/images/`，随资源变更同步维护引用。

<a id="license"></a>

## 许可证与致谢

本项目按 [LICENSE](LICENSE) 分发；第三方组件保留各自许可，BASS 的使用与分发须遵守其官方许可。

Dan Player 基于 [Ferry-200/coriander_player](https://github.com/Ferry-200/coriander_player) 修改，感谢原作者提供的播放器基础、曲库结构和歌词体验。同时感谢 [desktop_lyric](https://github.com/Ferry-200/desktop_lyric)、[music_api_dart](https://github.com/Ferry-200/music_api_dart)、[BASS](https://www.un4seen.com/bass.html)、[Lofty](https://crates.io/crates/lofty)、[flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge) 及 [Flutter](https://flutter.dev/) 与 Material Design。

<sub>徽章由 <a href="https://shields.io/">Shields.io</a> 提供。下载量统计 Release 附件的下载次数，不等于用户数或安装量；技术徽章仅说明使用的技术，不声明最低支持版本。</sub>
