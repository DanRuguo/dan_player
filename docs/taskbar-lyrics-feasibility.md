# 任务栏歌词复核与兼容性结论

## 2026-08-30 追加：任务栏上方单行模式

按用户后续要求，已实装桌面歌词的“任务栏上方单行歌词”模式。它是当前屏幕工作区底部的普通置顶窗口，不是真正嵌入任务栏；因此下文关于不做 Explorer 嵌入的结论仍成立。主设置与外观面板共用同一开关和高度、间距、最小字号、译文设置，长句自动缩小/省略，全部按钮留在窗口内。自动隐藏的四边 appbar 采用公开API只读避让；侧边/顶部任务栏仍按屏幕工作区底部显示。细节见同包 `INTERACTION-FIXES.md`，本轮不冒称完成Win10/11实机组合验收。

## 之前的参考库复核（历史记录）

复核日期：2026-08-30。结论：**本轮不实现真正嵌入任务栏的歌词**。它并非技术上绝对做不到，但目前没有已验证、可稳定覆盖原生 Windows 10/11 的方案。用户随后明确授权参考桌面悬浮歌词和任务栏悬停卡片，这两项与真嵌入分开处理。

## ZeroBit Player 实际提供什么

检查了 GitHub 当日主分支固定快照，而非只凭 README 判断：

- 主播放器：[`e47d34fb5c946a6cf10041377b15eb6f089f5d28`](https://github.com/Empty-57/ZeroBit-Player/tree/e47d34fb5c946a6cf10041377b15eb6f089f5d28)（2026-08-27）。
- README 链接的独立歌词组件：[`a36c53f4dc6f6cd257072797630cd31e41113c91`](https://github.com/Empty-57/zerobit_player_desktop_lyrics/tree/a36c53f4dc6f6cd257072797630cd31e41113c91)（2026-08-27）。

| 检查位置 | 证据与含义 |
| --- | --- |
| [主播放器 `lib/windows_taskbar_thumbnail.dart:4–60`](https://github.com/Empty-57/ZeroBit-Player/blob/e47d34fb5c946a6cf10041377b15eb6f089f5d28/lib/windows_taskbar_thumbnail.dart#L4-L60) | 有任务栏功能：上一首、播放/暂停、下一首，以及自定义缩略图；不能据此说项目「完全没有任务栏功能」。 |
| [主播放器 `windows/runner/taskbar_manager.cpp:169–209`](https://github.com/Empty-57/ZeroBit-Player/blob/e47d34fb5c946a6cf10041377b15eb6f089f5d28/windows/runner/taskbar_manager.cpp#L169-L209)、[325–353](https://github.com/Empty-57/ZeroBit-Player/blob/e47d34fb5c946a6cf10041377b15eb6f089f5d28/windows/runner/taskbar_manager.cpp#L325-L353) | 使用 `ThumbBarAddButtons` / `ThumbBarUpdateButtons` 与 `DwmSetIconicThumbnail`。属于悬停预览/缩略图，不是在任务栏空白区域持续绘制歌词。 |
| [歌词组件 `lib/main.dart:41–65`](https://github.com/Empty-57/zerobit_player_desktop_lyrics/blob/a36c53f4dc6f6cd257072797630cd31e41113c91/lib/main.dart#L41-L65) | 创建透明、无边框、`skipTaskbar: true`、`alwaysOnTop: true` 的独立窗口；`skipTaskbar` 是隐藏它自己的任务栏按钮，不是嵌入任务栏。 |
| [歌词组件 `lib/desktop_lyrics_client.dart:104–108`](https://github.com/Empty-57/zerobit_player_desktop_lyrics/blob/a36c53f4dc6f6cd257072797630cd31e41113c91/lib/desktop_lyrics_client.dart#L104-L108)、[主项目说明:1–17](https://github.com/Empty-57/ZeroBit-Player/blob/e47d34fb5c946a6cf10041377b15eb6f089f5d28/docs/guide/desktop-lyric.md#L1-L17) | 周期性请求置顶，文档也明确描述独立小窗口。 |

此外检查了上述快照的自有 `lib`、`windows/runner` 和主项目 `rust/src` 文本源码（133 个 Dart/C++/头文件/YAML/Rust 文件），检索任务栏歌词、`Shell_TrayWnd`、`Shell_SecondaryTrayWnd`、`ReBarWindow32`、`IDeskBand`、`FindWindow`、`SetParent` 等入口。唯一 `SetParent` 是 [Flutter 内容挂到自己的 runner 窗口](https://github.com/Empty-57/ZeroBit-Player/blob/e47d34fb5c946a6cf10041377b15eb6f089f5d28/windows/runner/win32_window.cpp#L241-L249)，不是挂到 Explorer。**这些已检查快照未发现真正任务栏歌词实现**；这不是对其他分支、未公开代码或未来版本的绝对断言，也未运行上游发行包做黑盒验证。

## 值得参考的增量，而非重复已有功能

- 拖动、悬停工具条、锁定穿透已在双方实现。上游入口为
  [`main.dart:85–91`](https://github.com/Empty-57/zerobit_player_desktop_lyrics/blob/a36c53f4dc6f6cd257072797630cd31e41113c91/lib/main.dart#L85-L91)、
  [`tool_bar.dart:60–139`](https://github.com/Empty-57/zerobit_player_desktop_lyrics/blob/a36c53f4dc6f6cd257072797630cd31e41113c91/lib/tool_bar.dart#L60-L139)、
  [`desktop_lyrics_client.dart:189–191`](https://github.com/Empty-57/zerobit_player_desktop_lyrics/blob/a36c53f4dc6f6cd257072797630cd31e41113c91/lib/desktop_lyrics_client.dart#L189-L191)。
  Dan Player 已有真实窗口句柄的穿透控制、长按显控件和按监视器工作区收回越界窗口，无需用上游替换。
- 上游的字体、字重、文字透明度、已唱/未唱独立色、描边开关/色属于可借鉴的可读性选项，见
  [`desktop_lyrics_ctrl.dart:20–45`](https://github.com/Empty-57/zerobit_player_desktop_lyrics/blob/a36c53f4dc6f6cd257072797630cd31e41113c91/lib/controller/desktop_lyrics_ctrl.dart#L20-L45)。
  但其所谓描边实际为单个偏移阴影，并非轮廓笔画，见
  [`lyrics_text_display_widget.dart:29–41`](https://github.com/Empty-57/zerobit_player_desktop_lyrics/blob/a36c53f4dc6f6cd257072797630cd31e41113c91/lib/tools/lrcTool/lyrics_text_display_widget.dart#L29-L41)；应复用本地逐字/字素渲染，不能照搬拆 UTF-16 字符的竖排实现。
- 上游保存/恢复坐标并按字体/方向变更最小尺寸，但所检查的
  [`desktop_lyrics_client.dart:213–237`](https://github.com/Empty-57/zerobit_player_desktop_lyrics/blob/a36c53f4dc6f6cd257072797630cd31e41113c91/lib/desktop_lyrics_client.dart#L213-L237) 与
  [`desktop_lyrics_ctrl.dart:67–94`](https://github.com/Empty-57/zerobit_player_desktop_lyrics/blob/a36c53f4dc6f6cd257072797630cd31e41113c91/lib/controller/desktop_lyrics_ctrl.dart#L67-L94)
  未显示多屏工作区约束；不能把其定位代码当作混合 DPI/拔屏安全保证。本地已有 `MonitorFromRect(MONITOR_DEFAULTTONEAREST)` 及工作区限位，保留。
- 三个原生按钮本地已有；上游也仅固定三个，未见按尺寸增减的自适应按钮。新增价值是自定义预览位图。
  上游 [`taskbar_manager.cpp:325–353`](https://github.com/Empty-57/ZeroBit-Player/blob/e47d34fb5c946a6cf10041377b15eb6f089f5d28/windows/runner/taskbar_manager.cpp#L325-L353)
  虽按源比例缩放，但 329–330 行将宽/高字序反置；微软规定
  [HIWORD 为宽、LOWORD 为高](https://learn.microsoft.com/en-us/windows/win32/dwm/wm-dwmsendiconicthumbnail)，超出请求的位图会被拒绝。
  本地按官方机制独立实现，使用受限 raw RGBA，不复制该错误或 PNG 解码路径；协议及资源生命周期见 `windows/runner/DESKTOP_INTEGRATION.md`。

## 自研路径与边界

| 路径 | 能实现的效果 | Windows 10/11 兼容性判断 |
| --- | --- | --- |
| 独立透明置顶窗口 | 桌面悬浮歌词；可以视觉上靠近任务栏 | 可使用受支持窗口 API，但不会参与任务栏布局，覆盖到任务栏也不等于嵌入。仍需处理全屏、点击穿透、显示桌面和自动隐藏。 |
| `ITaskbarList3` / DWM 缩略图 | 播放按钮、自定义悬停预览 | 有正式接口，但不提供任务栏空白区的常驻任意文本；见微软 [Taskbar Extensions](https://learn.microsoft.com/en-us/windows/win32/shell/taskbar-extensions#thumbnail-toolbars)。 |
| 传统 COM DeskBand | 由 Shell 容纳的任务栏工具栏 | 传统任务栏有正式 [Desk Bands](https://learn.microsoft.com/en-us/windows/win32/shell/band-objects#desk-bands) 机制；不能直接当作原生 Win11 通用接口。微软 [Win11 功能变更](https://www.microsoft.com/en-us/windows/windows-11-specifications#table4) 明确移除了应用自定义任务栏区域的能力。 |
| 查找 Explorer 子窗口后 reparent、修改内部布局或注入 hook | 特定系统版本上可能实现真嵌入/近似嵌入 | 可以研究，但依赖非公开 Shell 窗口结构和布局；不能由 `SetParent` 存在就推出任务栏支持。Win11 居中图标、溢出区、触控任务栏及后续更新都需单独适配；不把 ExplorerPatcher/替换任务栏作为用户隐含前提。 |
| AppBar | 在屏幕边缘保留一条歌词区域 | 是独立的桌面工具栏，不是任务栏内部。微软要求位置协商、处理 `ABN_POSCHANGED` / 全屏与自动隐藏状态，见 [Application Desktop Toolbars](https://learn.microsoft.com/en-us/windows/win32/shell/application-desktop-toolbars)。 |

以下是基于上述机制的工程风险判断，不是已完成的兼容性测试：

- **Explorer 生命周期**：任务栏重建后旧 HWND/布局失效，需要重新发现、撤销旧挂接并恢复。微软的 [`TaskbarCreated`](https://learn.microsoft.com/en-us/windows/win32/shell/taskbar#taskbar-creation-notification) 文档说明重建通知，Win10 主屏 DPI 变化也可能发送；该通知不承诺恢复第三方未公开嵌入布局。
- **DPI / 多屏**：必须按每屏逻辑/物理坐标处理不同缩放、主屏切换、热插拔与远程桌面，不能写死任务栏高度或只查主屏。微软 [`SetParent`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setparent#remarks) 明确指出跨 DPI awareness 的父子窗口关系可能导致错误或进程 DPI 模式重置；[`WM_DPICHANGED`](https://learn.microsoft.com/en-us/windows/win32/hidpi/wm-dpichanged) 要求响应 DPI/建议窗口矩形变化。
- **布局与输入**：需避让开始、搜索、应用按钮、托盘、溢出和自动隐藏热区，确保歌词不抢焦点、不吞系统点击。Win10 可移动/改变高度的任务栏与 Win11 原生底部、居中/左对齐及触控形态不是一个固定布局；见微软 [Taskbar customization](https://support.microsoft.com/en-US/Windows/Experience/Personalization/customize-the-taskbar-in-windows)。
- **故障隔离**：若未来探索原型，应使用独立、可随时关闭的 native helper，发现目标不匹配/重建失败就回退为桌面歌词；不得注入主播放器引擎到 Explorer，也不承诺一直覆盖全屏应用。使用 hook/COM 扩展还需验证进程位数、权限与卸载清理，避免拖垮 Explorer。

重新立项的最低门槛是明确「原生 Win10/Win11、无需改系统」的支持矩阵，并实际验证各支持版本的混合 DPI 双屏、重启 Explorer、自动隐藏、全屏、睡眠恢复、切换主屏与系统更新后行为。当前没有这组验证证据，按「不可靠则暂不做」执行，不新增伪装成已支持的开关。
