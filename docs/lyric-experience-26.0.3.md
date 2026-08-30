# 歌词弹性滚动、桌面竖排与倍速时钟

此改动保持版本 26.0.3。仅借鉴公开实现的交互设计，未复制 ZeroBit 的源代码、图片或字体；没有增加任务栏歌词。

## 参考与边界

- ZeroBit 主项目固定提交 [`1076cbfcc4637a31a37f9dfa381e46f6256fa134`](https://github.com/Empty-57/ZeroBit-Player/tree/1076cbfcc4637a31a37f9dfa381e46f6256fa134)，[GPL-3.0 许可证](https://github.com/Empty-57/ZeroBit-Player/blob/1076cbfcc4637a31a37f9dfa381e46f6256fa134/LICENSE)。其 [BASS 包装](https://github.com/Empty-57/ZeroBit-Player/blob/1076cbfcc4637a31a37f9dfa381e46f6256fa134/rust/src/api/bass.rs) 是倍速与媒体时间链路的参考，而非本次移植代码。
- 独立桌面歌词仓库固定提交 [`3c8d0087b957b9f76b56b830abd6690e37802355`](https://github.com/Empty-57/zerobit_player_desktop_lyrics/tree/3c8d0087b957b9f76b56b830abd6690e37802355)，其 [GPL-3.0 许可证](https://github.com/Empty-57/zerobit_player_desktop_lyrics/blob/3c8d0087b957b9f76b56b830abd6690e37802355/LICENSE) 已单独核对，不根据主库推定。主库没有固定该独立库的对应发行提交。
- [文本显示组件](https://github.com/Empty-57/zerobit_player_desktop_lyrics/blob/3c8d0087b957b9f76b56b830abd6690e37802355/lib/tools/lrcTool/lyrics_text_display_widget.dart) 提供竖向排列的交互启发；本项目按 Unicode 字素簇重新实现，不能用拆 UTF-16 字符的方式拆散组合 emoji。
- [桌面歌词窗口组件](https://github.com/Empty-57/zerobit_player_desktop_lyrics/blob/3c8d0087b957b9f76b56b830abd6690e37802355/lib/desktop_lyrics_widget.dart) 和 [桌面控制器](https://github.com/Empty-57/zerobit_player_desktop_lyrics/blob/3c8d0087b957b9f76b56b830abd6690e37802355/lib/getx_ctrl/desktop_lyrics_ctrl.dart) 提供横竖方向、窗口约束和控制项布局的启发。
- 工作区限制使用 Windows 的 [MonitorFromRect](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-monitorfromrect) 与 [GetMonitorInfoW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getmonitorinfow)，不访问 Explorer 内部层级，也不依赖 Win11 专属合成效果。

## 实际行为

主歌词：

- 设置中的“歌词弹性滚动”默认开启。正常逐句推进使用 720ms 阻尼曲线，回弹距离最多 8 个逻辑像素，终点精确归位。
- 字体尺寸、行高、行 State 与点击区域不随弹簧改变；只有滚动位置弹性变化。关闭选项保留原有由快到慢的单调滚动。
- 跨句跳转仍使用较短的单调曲线，新的跳转会取消旧滚动。初次加载使用播放器的真实位置。
- 保留手动滚动后 4 秒保护、触摸持续按住时不抢滚动、点击歌词跳转、原始偏移与真逐字时间。
- 减少动画或停用 Ticker 的区域立即显示最终状态；文字缩放到 200% 不改写用户字号。

桌面歌词：

- “桌面歌词竖排”可在设置或歌词窗口方向按钮中切换。设置立即同步到已打开的窗口，也放入初始化参数；不会因修改设置或打开空歌词窗而初始化 BASS。
- 原文自上而下显示，译文独立成列，不将整个横排句子旋转 90°。CJK、Hangul、kana 与 emoji 保持按完整 Unicode 字素簇逐格直立排版；CJK 标点仍各自占格，不与相邻文字拼成横排词组。
- 以空格分隔的外文单词会直立横排在同一格中，撇号词、连字符词、缩写和数字也保持为一个整体。200px 窄列配合 200% 文字缩放时，过长的双语单词在各自列内缩小适配，不向相邻列或窗口外溢出。
- 有真实逐词时间时，外文单词在本格内沿水平方向高亮，CJK 等逐字素内容仍从上到下推进；只有行时间的歌词不伪造逐词时间，译文没有词时间时保持整列显示。
- 横排保持 TextPainter 完整段落 shaping；竖排使用缓存的字素布局。时钟只重绘高亮和更新已有滚动位置，不按每个时钟 tick 重新测量文字。
- 长句随真实媒体时间滚动，暂停冻结，暂停时 seek 也立即前后重定位。减少动画时关闭连续字词扫色和插值 tick 的滚动，仍响应真实时间线校正。
- 工具栏 9 个操作在窄窗换行，主要触控区至少 44×44。字体、配色、上一首/播放/下一首、横竖方向、锁定和关闭仍可用。
- 锁定使用本歌词进程自己的 HWND，不再用前台窗口句柄，避免焦点变化后锁错其他应用。

窗口几何：

- 横排默认 800×160、最小 320×128；竖排默认 248×560、最小 200×320，实际最小值还会根据控制项和文字缩放增加。
- 横排、竖排各保留当前进程内自己的位置和尺寸；不是跨重启的持久化窗口位置。
- 切换方向先解除旧方向的最小约束，再设置新边界与新约束。所有切换串行，快速往返以最新请求为准。
- 根据目标显示器工作区限制位置和尺寸，支持负坐标、不同 DPI、显示器被移除和小工作区。调色板临时扩大不会覆盖常规横竖尺寸。
- 调整失败尝试还原旧边界/约束，允许同一请求重试，不把失败后的中间状态记作已完成。

倍速 IPC：

- `PlaybackTimelineMessage` 和 `InitArgsMessage` 增加可选 `playbackRate`；旧 JSON 缺失时为 1.0。有效范围 0.5–2.0，非法或非有限值安全处理。
- 媒体位置锚点仍为源音乐时间。桌面端估计位置为“收到的媒体时间 + 单调墙钟经过时间 × 当前倍率”，不把歌词时间戳或 seek 目标除以倍率。
- 主程序常规 400ms 校正时间线，helper 在播放时以 33ms 更新显示；暂停取消本地 tick。改倍率重新以实际位置锚定，避免时间跳变。
- 旧歌曲 sequence 的歌词/时间线不会覆盖新歌曲；原有横排 JSON 字段继续兼容。

生命周期：

- 主程序服务 `dispose()` 幂等，解除设置/就绪监听、停止同步和恢复计时器，关闭进程；普通关闭歌词窗口仍保留监听，以便重新打开。
- 启动请求在关闭后才完成时，迟到的进程立即被杀掉，不再重新挂载或自动恢复。
- helper 的 stdin EOF 表示所属主进程已关闭通信管道：停止时钟并幂等关闭自己的窗口。窗口尚未 show 时也检查 EOF，避免主程序提前退出后出现孤立窗口。暂停与方向消息不会触发此关闭。

## 验证与已知边界

专项测试覆盖主页面实际行的状态身份/布局、弹性终点与最大回弹、切歌/seek 取消、4 秒保护、减少动画，以及设置失败重试。桌面测试覆盖 7 档倍率、旧 JSON、暂停 seek、旧消息、emoji 字素边界、真实竖向高亮、200% 窄窗、横竖窗口恢复/DPI/失败回滚、关闭与 EOF。

复跑入口在工作区 `tool/qa-lyric-experience/run_tests.ps1`，使用 `-Suite main`、`desktop` 或 `preview`，必须与其他 Flutter 作业串行。全部测试使用隔离时钟、模拟窗口适配器和临时进程对象，不读取用户歌曲或设置，不启动安装播放器。

实际组件预览保存在 `tool/qa-lyric-experience/20260827-212037-336-preview/`：`vertical-light-100.png` 和 `vertical-dark-200.png`，均为 320×640 逻辑尺寸、2×栅格，包含中英日文、组合重音、家庭 emoji 与独立译文；2/2 渲染测试正常退出。字体为项目真实字体和只读系统 emoji fallback，不是 Ahem。`manifest.json` 记录字体及图像 SHA-256。

这些图片仅证明 Flutter 组件排版，不是 Win10/Win11 实机截图，也不证明原生窗口阴影、置顶、屏幕穿透或实际多显示器交互已经人工验证。回滚的最终成功仍取决于系统窗口 API。竖排布局会把空格分隔的外文单词作为一个直立横排单元，但不实现完整的东亚竖排标点替换规范；CJK 标点仍按独立字素格显示。恶意/错误来源把一个 emoji 拆成多个定时词时，只画一次该字素，由包含它起点的词时间负责，避免重复或破碎 emoji。
