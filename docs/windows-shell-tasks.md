# Windows 快捷任务与卸载入口

26.0.4 开始，任务栏与新安装创建的开始菜单快捷方式共用 `DanRuguo.DanPlayer` AppUserModelID。右键任务包含显示主窗口、播放/暂停、上一首、下一首、迷你播放器。任务标题跟随应用语言；图标是项目原创的 24 网格圆角几何，源脚本为 `scripts/generate_shell_task_icons.py`，五个多尺寸 ICO 已纳入资源，普通构建无需 Python。

任务通过固定的 `--shell-action=<action>` 参数激活。播放器按可执行文件位置和 `DAN_PLAYER_DATA_DIR` 使用独立的进程互斥量。再次启动同一实例只转发白名单动作，不再创建 Flutter 引擎或音频输出。正在启动时最多保留 16 个任务，现有进程的转发等待只发生在短暂的新进程中。冷启动的播放任务在曲库与会话恢复后执行；没有歌曲时提示选择歌曲。

设置 → 更新与关于 → 应用管理提供卸载入口。程序只识别当前用户的 Dan Player 安装注册表项，并核对 InstallLocation 与本次运行目录、卸载文件固定名称、`.dan-player-install` 目录、Inno `.dat` 与安装清单；目录及文件不能是重解析点，文件句柄在启动交接前阻止替换。不执行注册表附加参数或命令解释器，也不递归删除目录。用户确认后，卸载器等待本次播放器进程保存状态并退出，再显示卸载向导；15 秒内没有退出则停止卸载。Inno 仅依据安装日志移除程序文件，用户音乐、歌单及设置保留。

便携副本不调用其他安装实例的卸载器，仅提供打开本次程序目录的按钮。安装登记存在但卸载文件损坏时，界面指向 Windows“已安装的应用”。验证失败不会先退出播放器。

设置了 `DAN_PLAYER_DATA_DIR` 的 QA 进程使用隔离 AppUserModelID，不写系统 Jump List，也不允许卸载真实安装。Explorer 不会继承这项环境变量，因此 QA 注册任务可能错误打开用户资料；该行为被明确禁止。可在相同 QA 环境下启动相同 EXE 两次，验证单实例动作转发。

必要验证：`flutter test --no-pub test/windows_shell_test.dart`；CMake 目标 `windows_shell_policy_test`；Windows 主程序和 Inno 安装器正常编译。不运行用户机器上的真实卸载流程。相关标准：[Microsoft Jump List 任务](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-icustomdestinationlist-addusertasks)、[Inno 卸载文件目录](https://jrsoftware.org/ishelp/topic_setup_uninstallfilesdir.htm)。
