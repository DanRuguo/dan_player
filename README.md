# Dan Player

Windows x64 音乐播放器，基于 Flutter、Rust 与 BASS，支持本地曲库、联网音乐、桌面歌词和四语言界面。

[稳定版 26.0.4](https://github.com/DanRuguo/dan_player/releases/tag/v26.0.4) · [候选版 26.0.5-snapshot.3](https://github.com/DanRuguo/dan_player/releases/tag/v26.0.5-snapshot.3) · [更新记录](https://github.com/DanRuguo/dan_player/releases) · [反馈](https://github.com/DanRuguo/dan_player/issues)

![音乐主页](docs/images/library-light-wide.png)

## 功能

- 本地与联网播放，CUE 分轨、均衡器、响度均衡、逐曲续播和 A–B 循环。
- 艺术家、专辑、格式、文件夹分类；嵌套歌单、智能歌单、M3U8 导入导出。
- 个人评分、标签、播放书签、曲库健康检查与回收站。
- 歌词匹配、编辑、校准，桌面歌词与迷你播放器。
- 随封面变色的明暗主题，中文、英语、日语、韩语界面。
- 听歌时段、曲库构成、文件占用和歌曲排行可视化。

| 歌单 | 设置 |
| --- | --- |
| ![歌单](docs/images/playlists-dark-wide.png) | ![设置](docs/images/settings-light-wide.png) |

预览使用实际界面组件与虚构数据。

![音乐统计排行](docs/images/statistics-rankings-light.png)

## 安装与使用

Release 提供安装器、便携 ZIP 和校验文件。安装器支持原位升级，成功后清理临时回滚资料；便携包完整解压后运行 `Dan Player.exe`。桌面歌词由同一程序启动独立进程。

自有程序使用 RCEIT.Inc 自签名证书，Windows 可能显示信任提示；安装器不会自动安装信任证书。旧签名版本升级请手动下载新安装器。

`Space` 播放／暂停，`Ctrl + Left/Right` 切歌，`Left/Right` 跳转 5 秒，`Ctrl + M` 切换迷你播放器，`F11` 全屏，`F1` 查看快捷键。

自定义歌源见 [接口说明](docs/custom-music-source-api.md) 和 [配置示例](docs/examples/)。

## 源码与构建

| 目录 | 用途 |
| --- | --- |
| `lib/` | 界面、曲库和播放服务 |
| `rust/`、`rust_builder/` | 标签处理与 Flutter/Rust 桥接 |
| `windows/`、`installer/` | Windows 集成与安装器 |
| `third_party/` | 随附组件及其许可证 |
| `test/`、`test_driver/` | 自动化测试 |
| `scripts/` | 构建、校验与发布脚本 |
| `docs/` | 接口说明、示例和界面图片 |

需要 Flutter、Rust 和 Visual Studio 桌面 C++ 工作负载。依赖版本以锁文件为准。

```powershell
flutter pub get
flutter test
.\scripts\build_windows_release.ps1
```

构建脚本验证运行库后组装发布包；`-SkipSigning` 生成未签名产物。测试时将 `DAN_PLAYER_DATA_DIR` 设置为独立绝对路径，隔离曲库和设置。签名私钥、个人资料和本机开发记录不进入仓库。

## 许可证

本项目按 [LICENSE](LICENSE) 分发。第三方组件保留各自许可；BASS 的使用与分发须遵守其官方许可。

## 致谢

Dan Player 基于开源项目 [Ferry-200/coriander_player](https://github.com/Ferry-200/coriander_player) 修改，感谢原作者提供的播放器基础、曲库结构和歌词体验。

同时感谢以下项目和组件：

- [Ferry-200/desktop_lyric](https://github.com/Ferry-200/desktop_lyric)：桌面歌词组件基础。
- [music_api_dart](https://github.com/Ferry-200/music_api_dart)：在线音乐信息和歌词匹配。
- [BASS](https://www.un4seen.com/bass.html)：音频播放能力。
- [Lofty](https://crates.io/crates/lofty)：音频标签读取与写入。
- [flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge)：Flutter 与 Rust 交互。
- [Flutter](https://flutter.dev/) 和 Material Design：桌面 UI 基础。
