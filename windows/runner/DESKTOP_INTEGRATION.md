# Windows 后台播放与 Shell 控制

这是 Dan Player 自有的 Win32 实现，不依赖第三方托盘插件或其浮动 Git 分支。
没有复制参考播放器的实现；接口依据微软公开文档。版本仍为 26.0.3。

## 用户行为

- 默认关闭窗口会正常退出；设置中的“关闭窗口时后台播放”默认关闭。
- 启用后，主窗口、迷你窗口关闭按钮及 Alt+F4 都走 `requestAppClose()`。
  隐藏前必须再次得到原生托盘注册成功的明确回复；失败、超时、异常或无效回复均正常退出，
  不会只凭缓存的“曾经可用”状态把播放窗口藏起来。
- 托盘菜单提供显示主窗口、迷你播放器、上一首、播放/暂停、下一首、桌面歌词、退出。
  默认使用 Dan Player 自有的非阻塞圆角 Material 风格弹层：命令图标统一取自 Windows 10/11 自带的 Segoe MDL2 Assets（窗口、还原、媒体、字幕和电源语义），按 DPI 排版且颜色跟随应用明暗与主题色，支持悬停、键盘方向键、Enter/Space 和 Esc。创建自绘窗口失败或系统处于高对比度时自动回退原生 `HMENU`，不会因此失去退出或播放控制。
  单击或键盘激活托盘图标恢复当前窗口模式。Windows 可能将图标放在通知区域折叠区。
- 菜单“退出”始终真正退出，不再应用后台播放偏好。重复关闭不会取消正在进行的清理。
- 任务栏悬停预览保留上一首、播放/暂停、下一首三个原生按钮；可独立关闭。
  可选自定义歌曲卡片通过公开 DWM 缩略图接口显示，悬停后的 Peek 使用完整大卡片；关闭时恢复系统窗口预览。
  这不是任务栏空白区域常驻歌词，也不创建另一个播放进程。
- 音频服务尚未就绪、无歌曲或正在缓冲时，相应播放按钮禁用。显示窗口和退出始终可用。

## Dart 接入与生命周期

`DesktopIntegration.instance.initialize(onExit: shutdownAndExit)` 在主窗口及原生背景配置后、
`show/focus` 前等待完成；初始化失败会被记录，不阻止应用启动。
`AppSettings.experience` 是现有体验偏好的唯一持久化入口。

构造桌面集成、设置页面和可见性宿主不会访问 `PlayService.instance` 或创建 BASS。
播放适配器只订阅显式 `PlayService.playbackReady`，就绪后复用现有单个播放服务。
不会为托盘重复创建队列、媒体流或音频时钟。

`DesktopVisibilityHost` 保留路由和输入内容，用 `TickerMode`、`ExcludeFocus`、`IgnorePointer`
停用隐藏/最小化窗口的界面活动。`isHidden` 是被动的 `ValueListenable<bool>`，
定时器/流驱动的动态背景等另外订阅它；不是所有异步工作都会自动受 `TickerMode` 控制。
原生 `WM_SHOWWINDOW`、`WM_SIZE`、`WM_ACTIVATE` 仍继续传给 Flutter 和其他插件，
不伪造暂停的应用生命周期、不暂停音频。

真正退出先同步标记集成不可用并发布隐藏状态，再解绑播放观察器和原生回调、移除 Shell 资源；
之后才保存设置/队列及关闭已有播放服务，最后解除 `setPreventClose` 并关闭窗口。
`DesktopIntegration` 实现 `Listenable` 而非继承 `ChangeNotifier`，所以异步 `dispose()`
不覆盖同步父类方法。内部通知器保留至进程结束，允许仍挂载的消费者安全移除监听器。

## 原生协议

频道：`dan_player/desktop_integration`。

| 调用 | 参数/结果 |
| --- | --- |
| `configure` | `{taskbarControls: bool, dark?: bool, accent?: COLORREF, fontFamily?: string, fontPath?: string, labels?: map, trayMenuBlurRadius?: double}` → 状态；半径有限且在 0..24 逻辑像素内，否则拒绝 |
| `updatePlayback` | `ready/hasTrack/hasQueue/playing/buffering/desktopLyrics` 布尔值和 `title` |
| `setThumbnail` | `{width: int, height: int, pixels: Uint8List}`；Flutter 预乘 alpha 的 `rawRgba`，每轴 1..512，字节数精确等于 `width*height*4` 且不超过 1 MiB；成功 null 表示接收有效源，非法参数/分配失败显式错误，DWM 展示能力另由状态报告 |
| `clearThumbnail` | 无参数；释放像素并恢复两个 DWM iconic 属性，成功 null，失败显式错误，可重复清理 |
| `prepareHide` | 重新注册/验证托盘 → 状态 |
| `getState` | 当前状态 |
| `showMenu` | 显示本窗口的托盘菜单 |
| `dispose` | 幂等释放托盘、缩略图按钮、预览像素/DWM iconic 属性、COM 和 HICON |

状态含单调 `revision`、`trayAvailable`、`taskbarAvailable`、`thumbnailAvailable`、`windowVisible`、`minimized`
及可选 `reason`；Dart 拒绝晚到的旧 revision。原生事件为 `stateChanged` 和 `action`。
播放状态只在实际变化后合并发送，不传位置、歌词或每帧消息。歌曲卡片独立发送、独立降级；
`thumbnailAvailable` 只表示当前自定义卡片已成功启用，不参与托盘隐藏安全判断，
`taskbarControls` 开关也不隐式清除自定义预览。

## 自定义预览的资源与恢复策略

### 托盘菜单可调高斯模糊（与歌曲卡片独立）

- 菜单绘制使用单个有界内存缓冲区，先完成背景、文字与图标，再一次性提交到可见窗口。
  鼠标跨行只标记旧/新选择行重绘；标题和未变化行不随鼠标移动重新擦除。
  缓冲区在打开前分配、关闭释放，悬停不分配 GDI 位图；最多 4,194,304 像素，
  分配失败或超出预算则直接使用系统 HMENU。此缓冲区与模糊采样完全独立。
  `desktop_integration_paint_test` 使用合成内存像素验证 500 次悬停式刷新、原子提交、
  标题区域不变、100 次开关/DPI尺寸循环与资源释放，不作为所有显卡下 DWM 外观保证。

- `PlayerExperience.trayMenuBlurRadius` 是增量偏好，默认 0（纯色），旧设置不会启用捕获。
  滑条调整的是公开 GDI+ `BlurParams.radius` 高斯卷积核半径，不是 sigma、透明度或系统材质强度；
  物理半径为逻辑半径乘 DPI/96，没有降采样。拖动只在结束时保存一次，保存失败在设置中可见。
- 只有打开自有托盘菜单时，在创建/显示弹层 HWND 前，以最终工作区内的菜单矩形执行一次 `BitBlt`。
  不采菜单以外的边缘补偿区域、不建全屏中间图、不存盘、不传给 Dart、不联网、不建立捕获循环。
  这是打开瞬间的静态背景，之后背景变化要到下次打开才更新；悬停、播放和主题重绘均不重新采样。
- 使用公开 `Gdiplus::Blur` 原位高斯处理，只留下过滤后的 DIB；固定 80% 当前主题底色染色保障可读性，
  该染色不随半径滑条变化。关闭、失败、设置变化和退出都会擦除并释放 DIB/临时像素与效果订阅。
  捕获范围超过 1,048,576 像素（保留 DIB 最大 4 MiB）或单边超过 4096 时直接纯色，**不先捕获再缩小**。
  GDI+ 处理另有临时内存，因此 4 MiB 不是总内存上限。极小工作区放不下完整菜单时回退系统 HMENU。
- Win10/11 共用公开 GDI+ 路径；不使用未公开的 `SetWindowCompositionAttribute`，也不把 Win11
  backdrop 类型当成可调模糊半径。高对比度用系统 HMENU；透明效果关闭、节能或查询/捕获/分配失败用纯色。
  `UISettings.AdvancedEffectsEnabled` 和节能通知仅在有模糊菜单时订阅，关闭即解绑。COM 初始化匹配释放，
  延迟激活/退出用 generation 和局部资源所有权隔离；终止后不得开始捕获或恢复旧订阅。
- `tests/desktop_integration_blur_test.cpp` 是一个 headless 可执行程序，使用合成条纹和内存 DC，
  覆盖高斯空间扩散、DPI、精确矩形/预算、20 次仅重绘和 32 次开关/失败循环及 GDI 句柄稳定性。
  `tests/desktop_integration_blur_benchmark.cpp` 仅测合成棋盘像素（一次预热、五次计时），不读取桌面。
  这些测试不代表真实 Win10/11 菜单外观或实际屏幕捕获耗时已经验证。

### 任务栏歌曲卡片

- 原生只缓存一张不超过 1 MiB 的 raw RGBA 卡片，无 PNG 解码、文件、联网或屏幕截图。
  相同尺寸/字节内容不重复使 DWM 缓存失效；替换、首次启用及 Shell/DWM 重建时才请求失效。
- `WM_DWMSENDICONICTHUMBNAIL` 严格按 **HIWORD=最大宽、LOWORD=最大高** 解码，
  保留源宽高比、只缩小不放大，双线性采样并转换成 top-down 32bpp BGRA DIB。
  图像与请求尺寸均先验证，零尺寸请求不分配，不会按系统大尺寸创建巨型位图。
- `WM_DWMSENDICONICLIVEPREVIEWBITMAP` 与缩略图分开布局：普通窗口按 `GetClientRect`
  输出完整客户区大小，同一源卡片等比例放大、居中留边、不裁文字。1280×800 客户区对应
  1280×640 卡片，1920×1080 对应 1920×960；不是复用 480×240 小位图，也不是播放器截图。
  每轴最多 4096、总像素最多 4,194,304（临时 DIB 16 MiB），超大窗口按相同比例缩小画布。
  Peek 用固定点双线性插值，只复用两行与横向采样表（最多额外 176 KiB 临时工作区），
  小缩略图保持原有下采样/舍入语义。放大改善显示尺寸但不凭空增加源字体细节。
  每次临时 `HBITMAP` 在 DWM 复制后立即释放，
  仅长期保留同一份 <=1 MiB 原始卡片，不缓存第二张大图，不读取屏幕。
- 最小化时不使用当前的零尺寸/图标尺寸客户区：在正常、最大化及调整大小时保存最后一个
  **非最小化**的有效客户区，`SIZE_MINIMIZED` 和 `IsIconic` 均禁止覆盖它。
  如果控制器首次接入时窗口已经最小化，则仅取 `WINDOWPLACEMENT.rcNormalPosition` 的宽高，
  减去当前自定义非客户区计算留下的实际 frame/client 差值；标准窗口的 iconic client 为空时，
  使用 `AdjustWindowRectExForDpi` 的边框指标回退。不混用 workspace/screen 原点，不发送人工
  `WM_NCCALCSIZE`，不显示、移动、还原窗口或修改窗口样式。该初始回退是正常还原尺寸估计，
  不缓存为真实观测值，也不承诺等于“还原到最大化/全屏”的最终尺寸；DIB 仍受上述 16 MiB 上限。
- `TaskbarCreated`、`TaskbarButtonCreated`、`WM_DWMCOMPOSITIONCHANGED` 重新应用
  `DWMWA_FORCE_ICONIC_REPRESENTATION` / `DWMWA_HAS_ICONIC_BITMAP` 并恢复缓存卡片；
  这些重建消息继续传播给 Flutter、窗口背景及其他插件，不影响三按钮策略。
- 新卡片原位替换，切歌不先清空 DWM 属性。无效输入或源分配失败返回错误且不破坏上一份有效源；
  DWM 属性/失效/提交暂时失败则发布 `thumbnailAvailable: false`、尽力恢复系统表示，但保留最新有效源。
  每代源最多 3 次 100/500/1500ms 延迟恢复，成功取消计时器但不补回已消耗预算，避免无限失效循环。
  每次计时器使用独立的带标记 ID，忽略 `KillTimer` 后仍可能排队的旧消息，不提前触发新代重试。
  新内容或 Shell/DWM 重建可重置预算；关闭立即丢弃源、取消图像重试，仅属性还原失败时执行有界清理重试。
  退出取消全部计时器并还原属性；所有 DWM 调用检查 generation，旧调用不得清空新源或复活已关闭卡片。
  仅涉及本进程现有 HWND；不改窗口风格或 backdrop。
- [`DWMWA_FORCE_ICONIC_REPRESENTATION`](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute)
  同时影响缩略图与 Peek，本功能按用户选择保留强制歌曲卡片；
  不把卡片 Peek 描述为系统原生整窗预览。关闭歌曲卡片才恢复正常 DWM 窗口表示。

## Win10/Win11 边界

- 托盘使用本 HWND + ID，多个独立实例不会用固定全局 GUID 互相覆盖。
- 监听 `TaskbarCreated` 重建 Explorer 丢失的托盘资源；重建失败且窗口隐藏时恢复窗口。
- `TaskbarButtonCreated` 到达后才调用 `ITaskbarList3`；三个按钮只添加一次，之后更新或隐藏。
  只接受已知按钮 ID 且 `HIWORD(WPARAM) == THBN_CLICKED` 的任务栏命令。
- 托盘版本 4 回调与兼容回调分别解码，支持键盘激活；自绘菜单按当前显示器 DPI 定位并限制在工作区内，兼容负坐标显示器与极小远程桌面工作区；高对比度使用原生菜单回退。
  缩略图按钮图标按当前 DPI 生成，设置/主题变化时更新，不依赖 Flutter 私有字体。
- 三个任务栏按钮使用 `configure.accent`（播放器当前动态封面/主题色），
  单独变更 accent 也重建图标并更新已添加的按钮。按 Windows `SystemUsesLightTheme`
  选择明暗参考底，保留原色或向黑/白最小调色至参考对比度至少 4.5:1，
  给非文字图标常用的 3:1 下限留余量；不会简单替换成固定黑白图标。
  Windows 实际半透明任务栏/第三方主题并非采样所得，因此这不是所有桌面背景下的对比度保证。
  高对比模式精确遵循 `COLOR_BTNTEXT`，不应用自定义 accent。
- 托盘菜单的启用图标、勾选以及浅色调背景/文字跟随同一动态 accent，
  悬停底色也单独校验文字/图标对比；禁用灰与退出命令语义不变。
  已打开菜单收到主题变更会重绘，切到系统高对比模式则收起自绘菜单，下次使用原生 `HMENU`。
- Shell/COM 错误按 API 返回值降级；不会请求管理员权限、修改系统设置或任务栏策略。
- 原生菜单和 COM 消息循环可能重入销毁：终止标志先发布，接口保留局部引用，弹出菜单前先回复方法调用。自绘菜单本身不启动阻塞消息循环，并在失去激活、外部点击、Explorer 重启或退出时释放窗口/GDI 资源，避免退出后恢复托盘或访问已释放的通道。
- 不改变窗口风格、DWM 边距、非客户区计算、缩放命中测试或 Win10 白边修复。
- 不拦截 `WM_QUERYENDSESSION`；确认结束会话后请求清理，但操作系统强制结束时不能保证异步保存完成。

## 验证与性能口径

隔离 Flutter 测试位于 `test/desktop_integration_test.dart`、
`test/desktop_integration_settings_test.dart`，使用 fake 窗口/原生/播放适配器，
覆盖冷启动、隐藏失败、Shell 恢复、旧事件、重复关闭、销毁、按钮能力、设置和小窗大字。
`tests/desktop_integration_policy_test.cpp` 是不创建 HWND/Shell/音频的纯策略断言。
其中颜色网格断言覆盖明暗系统任务栏、极浅/极深封面色、主题切换、相同配置去重与系统高对比优先级。
`tests/taskbar_thumbnail_policy_test.cpp` 覆盖像素限制、int64 越界、非方形请求宽高顺序、
缩略图禁止放大、Peek 客户区适配/等比放大/预算、BGRA/预乘 alpha、相同内容去重与有限重试预算。
`tests/taskbar_peek_bitmap_test.cpp` 在 1280×800、1920×1080、2560×1440、竖窗和 4K 客户区上
生成合成卡片临时 DIB，检查整卡边缘、大小、16 MiB 上限、每轮 GDI 句柄释放及无第二份长期缓存。
`tests/taskbar_peek_geometry_test.cpp` 使用 36 个始终隐藏的 HWND，分别提供真实普通窗口与
初始最小化窗口的几何输入，验证标准边框、自定义标题栏及全客户区边框、正常/tool-window 样式，
以及对应 96/144/192 fixture 比例的边框输入（不是切换真实系统 DPI）。在本机 1280×800 初始
frame 下，三种 iconic client 分别为 0×0、183×26、199×34，解析结果恢复为 1262×753、
1264×792、1280×800；标准指标使用本机实际窗口 DPI。缓存顺序用两个独立隐藏 HWND 重放，
不调用 `ShowWindow` 或恢复命令，因此这是几何/缓存策略回归，不是真实单 HWND 最小化/还原
转场，也不是任务栏 Peek 呈现的 GUI 验收。所有查询另核对几何、样式、可见性及前台窗口不变。
`tool/native-desktop-integration/run_checks.ps1` 另以 `/W4 /WX` 编译实际原生翻译单元，
日志写入唯一目录，不运行播放器。

这些检查不代表 Win10/Win11 真机托盘、Explorer 重启、后台连续音频或缩略图外观已验证。
尚需实机检查不同 DPI/主题/通知区域、隐藏与最小化恢复、系统退出及 Shell 重启。
性能验证应对比同一曲目/窗口尺寸的前台与隐藏 CPU/GPU、帧次数、工作集，
并检查重复隐藏/显示、切歌后句柄/内存是否持续增长；不把配置或代码路径当成已测加速比例。

## 依据

- [Shell_NotifyIconW](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shell_notifyiconw)
- [ITaskbarList3::ThumbBarAddButtons](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-itaskbarlist3-thumbbaraddbuttons)
- [TaskbarCreated 与任务栏](https://learn.microsoft.com/en-us/windows/win32/shell/taskbar)
- [通知区域](https://learn.microsoft.com/en-us/windows/win32/shell/notification-area)
- [TrackPopupMenu](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-trackpopupmenu)
- [WM_DWMSENDICONICTHUMBNAIL：宽高顺序](https://learn.microsoft.com/en-us/windows/win32/dwm/wm-dwmsendiconicthumbnail)
- [DwmSetIconicThumbnail：32bpp、尺寸限制及所有权](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/nf-dwmapi-dwmseticonicthumbnail)
- [DwmSetIconicLivePreviewBitmap：客户区上限与副本生命周期](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/nf-dwmapi-dwmseticoniclivepreviewbitmap)
- [GetClientRect：当前客户区尺寸](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getclientrect)
- [WM_SIZE：SIZE_MINIMIZED](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-size)
- [WINDOWPLACEMENT：还原位置和 workspace 坐标](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-windowplacement)
- [WM_NCCALCSIZE：自定义客户区计算](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-nccalcsize)
- [AdjustWindowRectExForDpi：按 DPI 计算边框](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-adjustwindowrectexfordpi)
- [WM_DWMCOMPOSITIONCHANGED](https://learn.microsoft.com/en-us/windows/win32/dwm/wm-dwmcompositionchanged)
- [Windows 高对比度参数](https://learn.microsoft.com/en-us/windows/win32/winauto/high-contrast-parameter)
- [W3C 非文字控件对比度说明](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html)
- [GDI+ Blur：高斯模糊](https://learn.microsoft.com/en-us/windows/win32/api/gdipluseffects/nl-gdipluseffects-blur)
- [BlurParams：卷积核半径与边界](https://learn.microsoft.com/en-us/windows/win32/api/gdipluseffects/ns-gdipluseffects-blurparams)
- [BitBlt：矩形块传输](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-bitblt)
- [高级视觉效果设置与纯色回退](https://learn.microsoft.com/en-us/windows/apps/develop/composition/composition-tailoring)
- [节能状态与通知](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-system_power_status)
