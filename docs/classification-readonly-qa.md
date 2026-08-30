# 分类/统计只读验证摘要（2026-08-30）

本文保留验证方法和通用结论，不公开私人曲库规模、曲目名称、艺术家、路径、分布或文件字节统计。

## 方法与边界

- 对用户明确授权目录执行完整只读检查，不用抽样代替完整检查。
- 当前 Rust/FRB 接口没有公开的独立 `getTags`。为避免会写索引的构建/刷新接口，探针只读解析 ID3、Vorbis、APEv2 标签，并在需要时查询 Windows `System.Music.Artist` / `System.Music.Composer`。描述符经子进程内存传递，不生成含曲目路径、标签正文或歌词正文的缓存文件。
- 显式加载已有 Release 的原生库，通过真实 `getLyricFromPath` 读取内嵌歌词。应用实际的 `MusicClassificationScanner`、`MusicCategories` 和 `LibraryStatisticsScanner` 完成分类及核对，不另写一套算法替代应用实现。
- 探针以 `implements Audio` 的只读描述符避开设置单例；不初始化、读取或保存用户 AppSettings、AudioLibrary，也不调用索引构建、标签写入、歌词下载、播放或 SMTC。分类分隔符仅在探针内显式给定。
- 这些是源文件快照验证，不等同于读取用户已存索引。旧索引与 Windows 文字解码回退可能带来描述符差异，因此界面必须保留证据来源。

## 结论与证据边界

分类页与统计页的语言结果及证据来源计数一致。语言来源区分“标签 / 歌词 / 元数据推断 / 未知”；文字推断不等于识别了实际演唱语言。

作曲分类依次使用作曲标签、明确歌词作曲署名、参与创作艺术家回退及未知。艺术家回退只是浏览口径，不会写回 `Audio.composer` 或源标签。独立标签读取与应用描述符的计数不可混用，因为应用还可能包含既有字段回退和 Windows 补缺。

追加的只读元数据检查促成了以下通用修复：

- 标题来自完整文件名时，仅在分类中去掉真实扩展名，避免 `.mp3` 被当作拉丁语言线索；不修改文件名或 `Audio.title`。
- 纯汉字主标题不再因拉丁艺名或专辑中的 `OST` 被否决中文文字推断。假名、韩文及明确的非拉丁文字仍优先；主标题自身汉字与拉丁文字混合时保留未知。
- 拉丁变音字母按拉丁文字处理，并保留元数据推断标记。证据不足时不把混合标题默认归入“其他语言”。
- Windows 只读属性可在标签描述符缺失时补充信息；属性同样为空时不强填艺术家或作曲家。

## 缓存与完整性

- 后续统计扫描复用了同源歌词缓存，没有新增原生歌词读取。
- 本轮只读检查未修改原音乐、歌词、用户设置或曲库索引。
- 缓存仅驻留内存，最多 1024 项 / 4 MiB；逐次复核音频与外置歌词大小及修改时间。异常不缓存，空结果 30 秒后重试。
- 本机单次耗时不作为性能保证；公开文档不保留可识别私人曲库的性能及容量明细。

## 验证记录

- 当轮 4 份核心及持久化专项共 71 项通过：`music_categories_test.dart`、`library_statistics_test.dart`、`music_classification_evidence_test.dart`、`classification_metadata_persistence_test.dart`。包含艺术家回退不写回磁盘标签、文件扩展名、日/韩优先和混合标题反例。
- 缓存额外专项 3 项通过，覆盖 mtime 失效、同大小歌词变更、并发去重、异常重试、空结果有效期及容量上限。
- `scripts/native_tests/classification_readonly_probe.dart` 的只读端到端专项通过，严格核对分类与统计的一致性。其私人输入明细不随源码发布。
- 当轮定向 Dart 分析无问题；该独立验证阶段未运行全量测试或构建发布包。

探针位于默认 `test/` 之外，仅在显式提供 `DAN_PLAYER_CLASSIFICATION_ROOT` 与 `DAN_PLAYER_CLASSIFICATION_DLL` 时运行。常规测试及公开界面渲染不会自动访问真实音乐目录。

## 私有描述符输出

`python scripts/audit_classification_metadata.py <music-directory> --descriptors` 是供隔离本机探针消费的私有模式。其标准输出含音频绝对路径及标题、艺术家、专辑等标签，虽然没有歌词正文，也不能作为公开日志。不得提交、上传或随发行包附带该输出及捕获它的日志。正常端到端探针仅在子进程内存中传递描述符；启用 `DAN_PLAYER_CLASSIFICATION_METADATA_AUDIT` 后的曲目示例同样必须留在私有验证环境。

普通汇总模式的已捕获异常仅记录异常类型及数字 errno，不回显原始异常消息或源路径。`scripts/test_audit_classification_metadata.py` 使用合成异常验证此边界，不访问真实曲库。
