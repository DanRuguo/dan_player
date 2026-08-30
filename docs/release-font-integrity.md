# Windows Release 图标完整性

## 2026-08-27 缺失图标的原因

本次检查确认是 **Release 增量构建复用了旧的裁剪字体**，而不是图标源不存在、`uses-material-design` 未开启，或已证实的可变字体渲染缺陷。

安装的 Flutter 3.47.1 中，`BundleWindowsAssets.inputs` 未列入 `app.dill`，但图标裁剪器需要读取它来决定保留哪些 `IconData` 字形。仅修改 Dart 界面时，AOT 可以重新编译，而 Release 资产目标仍认为旧字体有效；Debug 对应目标则声明了 `app.dill` 输入。[Flutter 3.47.1 的 Windows 构建目标](https://github.com/flutter/flutter/blob/3.47.1/packages/flutter_tools/lib/src/build_system/targets/windows.dart)、[Flutter IconData 文档](https://api.flutter.dev/flutter/widgets/IconData-class.html)

旧产物的只读审计证据：

- 字体与 Release 资产 stamp 的更新时间约为 11:15，`app.dill` / `app.so` 已在 14:23–14:24 更新。
- 最终目录中的 MaterialIcons 仅 2,112 字节。实际编译内核要求 54 个图标，其中 38 个缺失；Material Symbols Outlined 要求 124 个，其中 8 个缺失。
- 例如 MaterialIcons 的 `create_new_folder_outlined`（U+EF8C）、`refresh_rounded`（U+F00E9），以及 Symbols 的 `keyboard`（U+E312）、`picture_in_picture_alt`（U+E911）不在旧字体 cmap 中，原始字体则包含它们。
- `app_icon.ico`、`RCE_logo_transparent.png`、`RCE_logo_white.png` 的包内资产与源文件 SHA-256 一致；不能把所有“空白图标”归因于 Logo 文件缺失。

以上数量是修复前那一次编译的诊断，不是永久写死的图标清单；之后新增图标会自动进入实际编译需求。

## 构建与验证

正常使用项目的构建脚本。已有依赖准备好、需要先构建再进行签名和 QA 时：

```powershell
.\scripts\build_windows_release.ps1 -NoRestore -SkipSigning -SkipPackaging
```

脚本会在主程序和桌面歌词程序的每次 Release 构建前，仅失效经过路径检查的三种生成印记：`release_bundle_windows-x64_assets.stamp`、`aot_elf_release.stamp`、`windows_aot_bundle.stamp`。不删除完整缓存、已有内核/AOT、字体源、旧 dist 或用户资料。AOT 随下一次 Release 构建重新生成，避免增量构建重写内核后仍保留较旧的 AOT 时间，无法建立同轮产物证据；不放宽字体门禁，调试构建不受影响。继续使用 Flutter 的图标裁剪，不增加 `--no-tree-shake-icons`。失效动作可单独用 `-WhatIf` 查看：

```powershell
.\scripts\invalidate_windows_icon_assets.ps1 -WhatIf
```

构建后会自动运行门禁。也可以单独只读检查已生成的主程序，或者向一个**尚不存在**的文件写入审计报告：

```powershell
.\scripts\verify_windows_release_fonts.ps1
.\scripts\verify_windows_release_fonts.ps1 -ReportPath ..\tool\qa-release\font-audit-new.json
```

以上命令从仓库根目录运行；示例报告位于仓库外的 `..\tool` 工具目录，不随源码或发布包提供。

对于桌面歌词项目，将 `-ProjectRoot` 指向 `third_party\desktop_lyric`。对于已经复制的 staging 目录，用 `-ReleaseDirectory` 指定其包含 `data` 的根目录。可用 `-FlutterRoot` 明确指定本次编译所用的 Flutter SDK。门禁不运行 Flutter 构建、不启动播放器、不安装字体，也不访问用户音乐资料。

## 门禁保证的范围

1. 读取**最终 Release 目录**的 `data/app.so`，按 SHA-256 找到同一次 AOT 对应的缓存内核；没有匹配内核就拒绝用无关源码猜测需求。
2. 使用 Flutter 自带 `const_finder` 获取该内核实际保留的常量 `IconData`。动态构造无法证明安全时直接失败；不要求保留整个 SDK 的所有图标或歌词中的全部 Unicode。
3. 根据最终 `FontManifest.json` 定位字体，解析真实 TTF/OTF 的 Unicode cmap（格式 4、12、13），检查字形不是 `.notdef`，也没有超出 `maxp` 范围。可变字体与补充平面码点同样检查；不把较旧 cmap 的字形合并进首选 cmap 来掩盖问题。[OpenType cmap 规范](https://learn.microsoft.com/en-us/typography/opentype/spec/cmap)
4. 项目直接引用的字体必须注册。仅明确识别 Flutter 的平台兜底常量（未使用的 Cupertino 字体、系统字体哨兵及 Inspector 图标）；其他未注册的编译字体一律失败。
5. 主程序的五份品牌/图标资产（应用图标、明暗 RCE、明暗 DanRuguo）还会与源文件逐字节哈希比较，保证新增开屏图片同样进入源文件、Release 目录与最终 ZIP 的一致性门禁。

`assemble_windows_release.ps1` 在创建新的 dist 目录前先验证输入，并对复制后的两套 payload 再验证，生成各自的 `FONT-INTEGRITY.json`。组包后重新读取 ZIP 内的 AOT、字体、FontManifest、Logo 和报告，验证其 SHA-256 与实际审计数据一致。最终包和普通源码/完整字体预览不能互相替代。

审计报告记录：AOT / 内核 / FontManifest 哈希，每个字体的字节数、哈希、所需码点、缺失码点，以及 Logo 哈希。它证明编译需求和最终打包字节一致，**不替代真实字体墨迹渲染检查，也不等同于启动 Windows 播放器的 GUI 验收**。CI 同样执行构建前失效和构建/组包后的门禁。

## 回归测试

```powershell
flutter test --no-pub test/release_font_integrity_test.dart --concurrency=1
```

测试包括 BMP / 补充平面 / 可变字体、格式 4 的字形数组、首选 cmap 选择、损坏字体边界、`.notdef`、动态 IconData、缺失/未注册字体、旧裁剪字体失败，以及 `-WhatIf` 和仅删除指定生成 stamp 的隔离文件夹验证。文件夹夹具在 workspace 的 `tool/qa-release` 下生成，不读取或清理用户音乐目录。
