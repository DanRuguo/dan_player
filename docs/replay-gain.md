# ReplayGain 音量均衡

26.0.5-snapshot.1 在设置的播放选项中增加 ReplayGain。默认关闭；曲目模式使用曲目增益，专辑模式优先使用专辑增益，缺少时回退曲目。它读取文件已经存在的增益标签，不分析整首音频，不扫描整库，也不写入标签。没有可用增益标签的歌曲保持用户设置的音量。

“依据标签峰值限制增益”会结合用户音量限制当前增益。没有峰值标签时，此选项保留负增益但禁止额外放大；关闭该选项才会应用没有峰值标签的正增益。这不是最终输出限幅器，后续均衡器、其他 DSP 及不准确的峰值标签仍可能造成削波。

## 接入与边界

- 当前本地文件在已有的 BASS 后台开流步骤读取元数据，不新增同步文件扫描。BASS 返回的 Vorbis/FLAC、APE、MP4 注释按标准 `REPLAYGAIN_TRACK_GAIN`、`REPLAYGAIN_TRACK_PEAK`、`REPLAYGAIN_ALBUM_GAIN`、`REPLAYGAIN_ALBUM_PEAK` 解析。
- ID3v2.3/v2.4 读取 TXXX，支持 Latin-1、UTF-8、UTF-16 BOM、UTF-16BE。大封面及无关日期帧不会阻止读取增益。使用带实际长度的 `TAG_BINARY`；标签块上限 64 MiB、文字帧 8 KiB，注释列表上限 1 MiB/512 项。不支持的压缩、加密、unsynchronization 标签保留原音量。
- 接受有限数值，增益范围 −60 至 +30 dB、峰值范围大于 0 且不超过 64。未知、异常或超出范围的值忽略。没有启用 R128、Sound Check 等不同参考响度协议的自动换算。
- URL 流暂不应用 ReplayGain；CUE 分轨只继承所在本地音频文件的标签，没有新增 CUE 文件的逐曲 ReplayGain 扩展解析。
- 原始解码流的增益保持默认值，最终播放流只施加一次“用户音量 × ReplayGain”。倍速、独占 mixer、输出模式重开、设置在开流期间变化和静音共用这个路径。关闭恢复用户音量，不把曲目增益写回音量滑块或系统音量。
- 偏好持久化在应用设置的 `ReplayGain` 对象，启动创建播放器时应用。UI 先确认原生应用成功再保存；失败保留旧偏好。

BASS 官方文档明确了 [标签指针与 TAG_BINARY 的长度/生命周期](https://www.un4seen.com/doc/bass/BASS_ChannelGetTags.html)、[FLAC 使用 Vorbis 注释接口](https://www.un4seen.com/doc/bassflac/BASS_FLAC_StreamCreateFile.html)，以及 [VOLDSP 对解码输出有效并允许大于 1 的增益](https://www.un4seen.com/doc/bass/BASS_ATTRIB_VOLDSP.html)。因此无需新增 Rust/FRB 接口或更换解码组件。

## 本机定向验证（2026-09-06）

- 27 个 Dart 定向测试通过：20 个增益/偏好/ID3 测试，另有 7 个已有后台开流、取消、独占初始化回归。
- 原生探针使用独立生成的 4 秒、440 Hz 正弦音频，涵盖 FLAC、Ogg Vorbis、MP3 ID3v2.3/v2.4；每种格式分别验证普通解码、1.5 倍速、倍速接独占所用 mixer，共 12 条实际解码路径。−6.020599913 dB 的实测 RMS 比值均为 0.5，没有重复施加。
- 实际 BassPlayer 核对专辑峰值限制、倍速、静音、输出切换失败后的回滚、开流期间改设置/音量、过期请求、无标签重置、关闭、释放后重载。首次实设备独占申请被占用设备拒绝；原模式和静音成功恢复。该轮已实测独占 mixer 的数据路径，**未宣称通过硬件独占输出验收**。
- 新模型、标签读取器及两个测试文件分析无问题。BassPlayer/PlaybackService 定向分析仅剩既有命名提示，没有新错误或警告。AppSettings 和设置面板由主任务做持久化/布局测试。

仓库原生探针：`scripts/native_tests/replay_gain_test.dart`。工作区隔离夹具及生成器：`tool/qa-local/snapshot5-replaygain/`；记录：`.migration/logs/2605-snapshot1/replaygain-*.log`。测试期间没有读取或修改用户音乐、播放列表或设置。
