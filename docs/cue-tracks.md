# CUE 分轨

26.0.4 支持从歌单工具栏导入外部 `.cue`，预览后创建正常歌单。每条分轨具有独立标题、艺术家、曲目编号、播放进度、队列标识和书签；不生成拆分音频、不把虚拟曲目混入扫描索引。支持同一 CUE 中的多个本地音频文件、UTF-8、带 BOM 的 UTF-16，以及 Windows GB18030/GBK/GB2312。输入上限 1 MiB，音频曲目编号 01–99。路径按 CUE 所在目录解析，不猜测同名但扩展名不同的文件。

分轨从 `INDEX 01` 开始，到同文件下一曲的 `INDEX 01` 结束，最后一首到音频结尾。CD 帧保持每秒 75 帧的原始精度；`INDEX 00` 中已存在的音频归前一首，`PREGAP`/`POSTGAP` 不额外生成静音。数据光盘、重复 FILE 段、缺失或倒序时间、缺失源文件会明确报错；内嵌 CUE 标签暂不读取。

音频解码使用 BASS 原生 `BASS_POS_END`，先设整轨解码边界，再接保音高倍速和 BASSmix。进度和跳转对用户始终是分轨内的相对位置；独占输出切换及失败回滚保留片段范围。片段结束由原生流结束触发，界面刷新计时器不负责截断音频。MP3 在打开工作线程中启用预扫描以提高定位精度，长文件首次打开可能稍慢。

歌单和播放会话保存 CUE 源路径与开始/结束帧；即使移除了导入时创建的歌单，当前队列也有独立描述用于下次恢复。移动源文件后不会猜测替代文件；重新导入会按新位置建立引用。源文件缺失或与 CUE 时间不匹配时播放会提示错误。分轨的元数据和歌词编辑、直接删除源文件菜单不提供；可以移除歌单条目、关联在线歌词。复制本地路径得到真实整轨位置；M3U8 导出会跳过分轨，避免把整张专辑误导出成多首完整音频。

正在播放或打开某首 CUE 分轨时，应用会拒绝删除对应整轨音频。切换其他歌曲后删除整轨，会清理其普通曲目和所有 CUE 分轨的队列/歌单引用。切换歌曲会清空队列撤销历史，删除清理不会被撤销重新带回。

## 参考与本机验证

实现独立编写。行为参考 [fooyin 的 CUE 解析器](https://github.com/fooyin/fooyin/blob/2f38420d94c543c9fc9de859b5f2ac1c44ae51ba/src/core/playlist/parsers/cueparser.cpp) 的独立偏移/时长和跨文件处理；原生边界依据 [BASS_ChannelSetPosition](https://www.un4seen.com/doc/bass/BASS_ChannelSetPosition.html) 与 [BASS_StreamCreateFile](https://www.un4seen.com/doc/bass/BASS_StreamCreateFile.html) 官方文档。未复制第三方实现。

- `cue_sheet_test.dart`：真实隔离文件、中文编码、帧精度与多文件、非法输入、歌单及独立会话恢复、标签禁止写入、原文件删除后的关联清理、M3U 跳过。
- `cue_import_dialog_test.dart`：导入前不创建歌单、错误不可确认、取消、分轨菜单无整轨写改删、360×560 窗口与 1.8 倍文字下明暗主题无溢出。
- `cue_native_segment_test.dart`：指定本机官方 BASS/BASS_FX DLL 后，调用实际生产 `prepareBassSegment`，合成 PCM 中间 1 秒分轨在 1×/1.5×准确输出 1 秒/2⁄3 秒；从中点跳转后准确输出剩余 1⁄2 秒/1⁄3 秒，无下一片段样本泄漏。未配置 DLL 的 CI 会明确跳过这个可选原生用例。
- 独立原生探针还覆盖普通解码和 BASS_FX+BASSmix 的 1×/1.5×及跳转后边界；结果位于本机 `.migration/logs/release-final/cue-native-probe.json`。这是离线解码验证，并非所有 WASAPI 硬件、所有压缩格式或无缝连续播放保证；相邻分轨沿用现有换曲机制，不宣称零间隙。
- 常规回归覆盖会话文件、删除操作、元数据事务及后台 BASS 打开。检查记录位于 `.migration/logs/release-final/cue-*.log`，合成文件和应用测试数据位于 `tool/qa-local/cue-*`，不会修改用户音乐。
