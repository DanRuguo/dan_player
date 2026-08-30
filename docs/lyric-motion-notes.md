# 26.0.3 歌词过渡实现说明

核对日期：2026-08-27。版本保持 26.0.3。本次只调整主播放页和标题栏的歌词呈现，不改变歌词来源、偏移规则、音频播放或用户数据。

## 生硬切换的根因

- 原竖向列表将同一个 `GlobalKey` 从旧当前行移动到新当前行；两行自己的动画状态不能稳定保留，看似使用隐式动画，实际仍出现突变。
- 逐字歌词在普通行和当前行之间切换 `Text` 与 `RichText/WidgetSpan`，字形布局、折行和高度会变化；刚打开的逐字行也可能从零进度开始，未使用播放器的当前时间。
- 间奏原先只在激活期间占用高度，改变了滚动目标；自动跟随和手动滚动又可能相互打断。
- 标题栏原先使用延时后按整句时长执行的横向滚动；暂停或跳转时，这段独立动画仍可继续，旧来源的异步回调也可能晚到。

## 独立实现

每条歌词保留自己的行身份及布局。`LyricLineMotion` 在当前绘制值上重新设定透明度、缩放和颜色过渡目标；460ms 的单调曲线没有缩放过冲。当前行按最终字号布局，邻近行只做绘制缩放，不通过更改字号制造折行变化。

逐字歌词的普通/激活状态使用同一段 `TextPainter` 字形布局，按原有词时间覆盖绘制高亮；播放采样只重绘当前逐字行或间奏，不在每个 33ms 采样点重建整份歌词。翻译保持在同一行内。只有逐行时间的 LRC 使用整行颜色过渡，不推算不存在的逐字时间。

滚动由当前列表自己的 `ScrollController` 执行：正常跟随 520ms，跨句跳转 320ms；新目标取消旧活动并从实际位置接续，不滚动祖先页面。初始非零位置、布局变化和减少动画设置直接定位。滚轮、触摸和触控板操作保护四秒，手指尚未结束拖动时不会超时抢回；成功点击歌词跳转才解除保护，失败显示错误并保留实际播放位置。

标题栏使用 220ms 短交叉淡入。长句横移目标只由实际播放时间决定，普通相邻采样之间最多进行 64ms 的有限平滑，不按墙钟外推整句；暂停后平稳停住，向后或大跨度跳转立即跟随实际时间。标题栏原有 48px 行高、上下 8px 间距及局部最大 150% 文字缩放规则不变。

歌词源的 Future、播放订阅和排队滚动均有独立身份或代次检查，旧歌词晚到、快速切歌及销毁不能恢复旧行。沿用已解析的时间轴和播放器实际位置，不重复施加 offset，不额外请求在线歌词。

减少动画同时遵循 `MediaQuery`、平台 `disableAnimations/reduceMotion` 和 `TickerMode`，包括运行中开启设置；行切换立即落到最终状态，逐字扫色及间奏呼吸停止。高对比模式不淡化上下文歌词；行的完整原文/翻译保留语义信息，触控区域不少于 44 逻辑像素。

## 参考来源与归属

以下固定提交已在线核对，并与工作区只读参考仓库的提交一致。仅借鉴交互设计，不复制、改写移植或打包这些仓库的实现代码、视觉资产或依赖。

- **LyciaMusic，`e5a8e3327be33406074b81c6ee038f1c69e1512e`**：[LightLyricPlayer.vue 的距离分层、几何定位及交互保护](https://github.com/Billy636/LyciaMusic/blob/e5a8e3327be33406074b81c6ee038f1c69e1512e/src/components/player/LightLyricPlayer.vue#L225-L288)，以及[按歌词内容稳定关联行、主文与译文同层](https://github.com/Billy636/LyciaMusic/blob/e5a8e3327be33406074b81c6ee038f1c69e1512e/src/components/player/LightLyricPlayer.vue#L389-L465)。启发是把歌词行身份、布局和绘制动画分开，并给用户滚动留出保护时间。本项目没有使用其弹性过冲或无逐字数据时的整行进度填充。
- **ECHO，`45ea979d18da08234307b13c215f56abe3c00556`**：[LyricsView.tsx 的取消滚动、几何定位和快速重新居中](https://github.com/moekotori/echo/blob/45ea979d18da08234307b13c215f56abe3c00556/src/renderer/components/lyrics/LyricsView.tsx#L529-L589)，以及[lyrics.css 的独立透明度、变换与距离层级](https://github.com/moekotori/echo/blob/45ea979d18da08234307b13c215f56abe3c00556/src/renderer/styles/lyrics.css#L2567-L2665)。启发是让新目标取代旧动画、依据实际布局定位，并将当前句和周围歌词分层呈现。本项目使用 Flutter 原生控制器和自己的单调过渡实现，不引入网页渲染器。

Lycia 的代码及资产授权分别以其 [README 许可声明](https://github.com/Billy636/LyciaMusic/blob/e5a8e3327be33406074b81c6ee038f1c69e1512e/README.md#L202-L205)、[LICENSE](https://github.com/Billy636/LyciaMusic/blob/e5a8e3327be33406074b81c6ee038f1c69e1512e/LICENSE) 和 [NOTICE](https://github.com/Billy636/LyciaMusic/blob/e5a8e3327be33406074b81c6ee038f1c69e1512e/NOTICE) 为准；ECHO 授权见其 [LICENSE](https://github.com/moekotori/echo/blob/45ea979d18da08234307b13c215f56abe3c00556/LICENSE)。本次设计参考不改变这些上游声明，也不代表取得其图片资产的再分发许可。

## 文件与验证

生产改动限定四个文件：

- `lib/page/now_playing_page/component/lyric_motion.dart`：专用过渡参数、可中断行动画和无障碍策略。
- `lib/page/now_playing_page/component/lyric_view_tile.dart`：稳定行结构、逐字原位绘制和真实时间驱动间奏。
- `lib/page/now_playing_page/component/vertical_lyric_view.dart`：可独立测试的真实列表、局部滚动和源生命周期。
- `lib/component/horizontal_lyric_view.dart`：实际时间驱动标题歌词、有限横移和源隔离。

新增实际 widget 专项测试 **43/43 通过**，退出码 0：`test/vertical_lyric_view_test.dart` 27 项，`test/horizontal_lyric_view_test.dart` 16 项。覆盖行 State 身份、连续帧透明度/尺度、滚动无过冲、首次非零进度、快速 seek、暂停、手动保护、旧 Future/Stream 失效、200% 长文译文、运行中减少动画、高对比语义和正负 offset 只应用一次。测试使用真实显示组件及受控时间流，不启动原生音频或联网请求。

```powershell
& '..\tool\flutter\bin\flutter.bat' test --no-pub --concurrency=1 --reporter expanded test/vertical_lyric_view_test.dart test/horizontal_lyric_view_test.dart
```

工具与日志位于仓库外工具目录，以上命令从仓库根目录运行。完整成功日志：`..\tool\qa-lyric-motion-20260827-172559-966\combined-test-02.log`，不随源码或发布包提供。首次运行的日志 `vertical-test-01.log` 也保留；其中三个测试未在异步 stream 送达后先建立动画零时刻帧，一个测试未及时释放语义句柄。修正测试生命周期后重跑通过，未放宽动画或布局断言。

四个生产文件与两个专项测试已格式化；定向分析无 error/warning，仅保留既有 `ALWAYS_SHOW_LYRIC_VIEW_CONTROLS` 命名 info。歌词周边集成回归另由主流程执行，130/130 通过；最终完整回归及发行包结果以 `26.0.3-validation.md` 为准。

## 验证边界

本轮不修改迷你/桌面歌词、歌词服务、共享 `AppMotion`、标题栏或 Windows 原生拖动层，也未操作真实用户歌曲。headless widget 测试不等同于 Windows 10/11 实机帧率或 GPU 验收。保留原有全量行布局方式，未宣称超长歌词虚拟化；逐字精度仍取决于来源提供的词时间。
