# M3U8 歌单导入与导出

歌单页右上角菜单提供“导入 M3U8 歌单”；打开已有歌单后可从同一菜单导出。多选菜单也可以导出当前选中的本地歌曲。

导入支持 UTF-8 编码的 `.m3u`、`.m3u8`（含 BOM）。先读取并预览数量和名称，确认后创建新歌单。相对路径以歌单文件所在目录为准，支持绝对盘符路径、`file:` URI 和 Windows UNC 共享路径。曲目顺序、重复项及 EXTINF 标题/时长会保留；已有曲库元数据优先。音乐文件不会被复制、删除或重新扫描，暂不可用的文件仍保留引用。

导出写入标准 UTF-8 M3U8，可选择相对路径；音乐与歌单一起移动时相对路径更方便。不同盘符或无法计算相对位置时保留绝对路径。保存选择器确认的目标路径不会被程序擅自改名，文件名须以 `.m3u8` 结尾；先完整编码到临时文件，再替换目标，失败时清理本次临时文件。

每份歌单最多 2 MiB、20,000 条本地曲目。解析与编码在独立 isolate 中完成，引用转换分批让出界面线程；不为确认文件存在而遍历网络共享。网络 URL、联网歌曲标识、不支持的格式与嵌套歌单会显示跳过数量。包含 `#EXT-X-` 的 HLS 清单整体拒绝导入，避免把音频分片变成曲目；非 UTF-8 旧 M3U 请先另存为 UTF-8 M3U8。

借鉴 [MusicPlayer2 的 Playlist.cpp](https://github.com/zhongyang219/MusicPlayer2/blob/e4967271d03f1b9dea121ed9a4bb81f2b15c1b84/MusicPlayer2/Playlist.cpp) 的路径/EXTINF 互通、[fooyin 的 HLS 识别](https://github.com/fooyin/fooyin/blob/2f38420d94c543c9fc9de859b5f2ac1c44ae51ba/src/core/playlist/parsers/m3uparser.cpp) 和 [Strawberry 的递归边界设计](https://github.com/strawberrymusicplayer/strawberry/blob/33c46534bf2af3b8e0bcb941257e657ebd0c972f/src/playlistparsers/m3uparser.cpp)，使用现有 Dart 模型独立实现。本版不展开嵌套歌单。
