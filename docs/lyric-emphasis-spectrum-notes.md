# 26.0.3 歌词强调与进度区频谱

核对日期：2026-08-27。延续 `lyric-motion-notes.md` 的稳定行身份和真实时间轴；这一轮增强主句层级、调整自动滚动节奏，并将全宽音柱移到播放进度条上方。版本、歌词数据、偏移设置和音频引擎不变。

## 呈现与性能

- 主句按用户字号的 1.12 倍、`w800` 字重固定排版。邻句只在绘制阶段缩放到 0.88，主句相对邻句约大 13.6%；透明度从原来的 0.60 改为 0.46，第二、第三及更远行分别为 0.30、0.22、0.16。各行保留相同的粗字形排版，避免激活时更换字重造成折行或高度抖动。
- 行交接仍从当前绘制值连续过渡，时长 460ms；触控及语义区域移到缩放层外，远行和空白间奏也保有完整 48px 点击区域。高对比模式不淡化上下文。
- 自动跟随使用独立的单调快起慢停曲线 `Cubic(0.16, 1, 0.30, 1)`，正常 620ms、跨句跳转 320ms。不是移植 Apple 的私有曲线或弹簧引擎，也没有越过目标后弹回。新目标中断旧滚动；初始非零位置及减少动画仍立即定位，四秒手动滚动保护不变。
- 大/小播放布局使用同一个 `SpectrumProgressSection`：32px / 24px 的音柱紧接进度条上方，不覆盖滑块或拦截触控。删除了播放按钮下面原有的 54px / 36px 音柱区域；保留时间、播放、音量、模式、桌面歌词等原控件。
- `FullWidthSpectrum` 仍连接 BASS 的真实 48 频段流。`FullWidthSpectrumView` 将到达的 FFT 帧交给 `CustomPainter(repaint: Listenable)`，不再用 `StreamBuilder` 每个采样重建组件。相同样本（包括暂停后的全零帧）不触发重绘；画笔、横向条柱几何和渐变着色器按尺寸缓存。
- 隐藏的 `TickerMode`、被其他路由覆盖、应用非活动及减少动画状态不订阅频谱；恢复时读实际当前快照。应用暂停在生命周期回调内立即释放订阅，不等待已经停止的 Flutter 帧。旧源订阅有代次隔离。非法数值归零，极窄尺寸也不会越界绘制。

无独立频谱动画定时器、无随机音柱、无空数据补造波形。逐字高亮仍只使用来源的实际词时间；只有逐行时间的 LRC 不模拟逐字进度。没有引入图片模糊、额外网页视图或整页缩放。

## 联网核对的主源

以下均采用固定提交链接，借鉴交互与渲染分层思路，没有复制实现代码、字体、素材或新增其依赖。

- [AMLL 的滚动弹簧策略](https://github.com/amll-dev/applemusic-like-lyrics/blob/9a1bd986c62af005bd9874fff670294a8ac1c145/packages/core/src/lyric-player/base/spring.ts)区分正常播放与 seek；[滚动输入引擎](https://github.com/amll-dev/applemusic-like-lyrics/blob/9a1bd986c62af005bd9874fff670294a8ac1c145/packages/core/src/lyric-player/base/scroll.ts)区分用户交互与自动跟随，并清理惯性/等待状态；[歌词样式](https://github.com/amll-dev/applemusic-like-lyrics/blob/9a1bd986c62af005bd9874fff670294a8ac1c145/packages/core/src/styles/lyric-player.module.css)把变换、透明度和排版职责分离。本项目使用 Flutter 的可中断滚动和自己的无过冲曲线。AMLL 许可见 [AGPL-3.0 LICENSE](https://github.com/amll-dev/applemusic-like-lyrics/blob/9a1bd986c62af005bd9874fff670294a8ac1c145/LICENSE)。
- 用户补充的 [FluentPlayer / FullPlay.vue](https://github.com/zhouchentao666/FluentPlayer/blob/facc34373d0f4f7c0e13b87a326291aee79af529/src/components/Play/FullPlay.vue)实际接入 `@applemusic-like-lyrics/vue`，把当前播放时间、暂停状态、歌词字号和对齐位置传给歌词视图；原文、译文与背景歌词有不同视觉层级。它启发的是保留用户字号及真实播放状态，再通过层级突出主句，不是按墙钟另造歌词动画。该提交未提供独立 LICENSE 文件，其 [README 许可段](https://github.com/zhouchentao666/FluentPlayer/blob/facc34373d0f4f7c0e13b87a326291aee79af529/README.md#L178-L184)仅指向原项目 CeruMusic 的协议，并含学习交流/非商业声明，因此不据此认定其代码或字体已获得可直接移植的许可。
- [LyciaMusic / AudioVisualizer.vue](https://github.com/Billy636/LyciaMusic/blob/e5a8e3327be33406074b81c6ee038f1c69e1512e/src/components/player/AudioVisualizer.vue)区分真实样本获取、画布绘制及后台低功耗状态。借鉴的是仅在需要显示时消费实际 FFT，而不是复制其定时器、渐变公式或插值算法；本项目沿用原 BASS 端已有的攻击/释放平滑。Lycia 代码许可见 [LICENSE](https://github.com/Billy636/LyciaMusic/blob/e5a8e3327be33406074b81c6ee038f1c69e1512e/LICENSE)，其他材料另见 [NOTICE](https://github.com/Billy636/LyciaMusic/blob/e5a8e3327be33406074b81c6ee038f1c69e1512e/NOTICE)。
- [Flutter 官方 CustomPainter 文档](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html)说明 `repaint` 可直接通知重绘，跳过 widget build 和布局阶段。本轮频谱据此改用渲染层通知，并保留 `RepaintBoundary`。

## 代码边界

生产变更仅涉及：

- `lib/page/now_playing_page/component/lyric_motion.dart`
- `lib/page/now_playing_page/component/lyric_view_tile.dart`
- `lib/page/now_playing_page/component/vertical_lyric_view.dart`
- `lib/page/now_playing_page/large_page.dart`
- `lib/page/now_playing_page/small_page.dart`
- `lib/component/full_width_spectrum.dart`

标题栏/迷你/桌面歌词、共享 `AppMotion`、设置及 BASS 引擎没有在本轮改动。标题栏继续使用原来的淡入曲线，不受新的竖向滚动曲线影响。歌曲详情页沿用兼容的 `FullWidthSpectrum(height: ...)` 接口，因而也获得频谱渲染及订阅生命周期改进。

## 验证

专项使用真实 Flutter 组件、受控时间流和显式 FFT 样本。测试不联网获取音乐，不启动原生播放器，不读写用户乐库。覆盖更强主句层级、连续状态/布局、四段减速、触控中断、边缘点击、实际逐字时间/offset/暂停、迟到数据、减少动画、200% 长文与三种对齐，以及 FFT 重绘隔离、生命周期、缓存、极窄绘制和进度条触控/键盘。

首轮日志保留在 `tool/qa-lyric-emphasis-spectrum-20260827-191836-760/lyric-spectrum-test-01.log`：59/68 通过，随后修复应用暂停必须立即取消订阅的真实缺口。滚动测量需先建立 post-frame ticker 的零时刻；字形边界测试需排除未绘制的行末空白选择区域。窄进度时间戳的布局由主流程在其所属 `page.dart` 单独修复。

第二轮 `lyric-spectrum-test-02.log` 为 **67/68 通过**：频谱 18/18、标题栏歌词 16/16、竖向歌词 33/34。真实大字字形边界、滚动四段减速/终点均通过；唯一未过的断言是在恰好 620ms 取 `isScrollingNotifier`，Flutter 的 `_InterpolationSimulation.isDone` 使用严格大于时长判断。测试已补上一个 16ms 收尾帧，同时仍检查精确 620ms 的终点和下一帧位置不变，交主流程最终统一批次执行；未修改曲线或放宽位置/减速断言。

定向静态分析无 error/warning，保留既有大写全局名的 info。六个生产文件已冻结。最终统一批次结果见 `26.0.3-validation.md`。headless 验证不等同于 Windows 10/11 实机帧率或 GPU 验收；没有宣称整个播放器的 FPS 提升幅度，也没有将原有全量歌词行布局改成虚拟列表。
