# 按来源歌曲 ID 读取公开评论

## 结果和边界

26.0.3 的 QQ音乐、网易云音乐热门和最新评论均已通过公共歌曲样本进行匿名实测，四条读取链路均验证到第二页，第二页各有 20 个新的评论 ID。这里使用平台域名上的网页端接口，不宣称它们是有稳定性保证的开放 API；不同歌曲、地区、网络或平台政策变化仍可能使请求失败。26.0.4 另外支持用户自行配置的只读评论端点；自定义服务由用户管理，不属于下述公共平台样本验证。

只在用户主动打开评论窗口后读取第一页。热门与最新各自按需加载并保留滚动位置；“加载更多”由用户明确触发，不自动轮询。显示来源、只读说明、真实空数据状态、可重试错误；后续页失败保留已显示内容。重复页面会停止继续请求。

限制如下：

- 界面每页请求 20 条，每个标签最多 10 页。QQ／网易单次请求总期限 12 秒、响应上限 1 MiB；自定义评论请求沿用自定义歌源的 6 秒总时限、256 KiB 响应上限，并最多解析 100 条记录。
- QQ 使用有效 `onlineNumericId`，网易使用有效数字 `onlineId`。自定义来源使用 `custom:<配置 ID>` 和安全不透明歌曲 ID：配置 ID 最长 96 个字符，首字符必须为字母或数字，其余字符只允许字母、数字、点、下划线和短横线；歌曲 ID 为 1–256 个字符，首字符同样必须为字母或数字，其余字符还可使用波浪号。URL、路径、空白或查询字符串不能作为评论身份。
- 联网歌曲直接使用可靠来源 ID；本地歌曲可明确选择“跟随联网歌词”或“独立指定”。“跟随联网歌词”仍只接受带可靠 ID 的 QQ／网易歌词；“独立指定”可保存符合上述身份规则的自定义候选，实际读取仍要求对应配置当前具备评论能力。没有 ID、未知来源和未关联状态分别提示。
- 本地评论关联保存在独立的 `song_comment_associations.json` 中，只含规范化本地路径、模式、平台和平台歌曲 ID，以及用于复核的候选显示快照。它不写音频标签、不改歌词选择，也不把本地备注当成在线评论。应用内改名会迁移该关联。
- 独立指定会先按歌曲信息搜索，再由用户确认候选；候选明确区分演唱者与作曲信息，并仅在用户点选后按需加载一条评论示例。没有作曲信息或评论时如实显示“平台未提供／暂无评论”，不会猜测字段。
- 不登录、不读取或发送 Cookie/Authorization，不执行音源脚本；不请求音频、头像、评论图片、位置或用户主页，不写评论、不点赞。
- 只渲染可选择的纯文本和响应中已有的最多 3 条引用/回复。链接、HTML、脚本或图片字段均不会被执行或自动加载。
- 评论仅保存在窗口内存中，不写入用户曲库或本地评论缓存。取消只关闭本次请求自己的 HTTP 客户端，不触碰搜索、歌词或播放的共享请求。
- 关闭、切换标签、替换平台 ID 时取消旧请求并增加代次，迟到响应不能覆盖新内容；同一帧两次关闭回调也不能关闭下层页面。
- 自定义评论要求对应配置仍存在、已启用、声明评论能力并配置评论端点；带有尚未接入的凭据引用时不会发送请求。停用或删除配置会立即阻止新的评论读取，但不会删除收藏、歌单或本地评论关联；重新导入同一稳定配置 ID 后，符合身份规则的记录可重新绑定。完整缓存备份会保存这些配置引用和关联，不保存评论正文，也不包含密钥。

QQ 最新接口在实测中会同时返回 `commenttotal=0`、真实评论和 `morecomment=1`。此时总数按“未知”处理，分页遵从真实 `morecomment`，不显示虚构的零条总数。回复活动时间不冒充根评论的发表时间；远端异常时间值在单位换算前校验，避免整数回绕产生假日期。

## UI 接口

生产实现的主要文件：

- `lib/online/song_comments.dart`：身份/可用性、匿名读取、解析、限时限页、取消。
- `lib/online/song_comment_association.dart`：跟随歌词/独立指定关系、原子保存、备份恢复与改名迁移。
- `lib/component/song_comment_match_dialog.dart`：候选搜索、来源/字段展示、按需评论预览和迟到请求失效。
- `lib/component/song_comments_dialog.dart`：可直接测试的真实窗口及用户点击入口。

```dart
SongCommentsService.canRead(audio); // static bool
SongCommentsService.unavailableReason(audio); // static String?，null 表示可读取
await showSongCommentsDialog(context, audio);
```

测试可注入 `SongCommentsService(transport: ...)`，入口也接受 `service:`。窗口打开时捕获平台歌曲 ID，不跟随之后的播放切歌去请求另一首歌。`SongCommentsDialog` 被宿主显式替换歌曲参数时会重新绑定并丢弃旧结果。候选搜索、候选评论预览和评论分页各有独立代次/取消边界；关闭窗口、换候选或换歌曲后，迟到结果不会覆盖当前内容。

正文使用 `ListView.builder` 虚拟化；长评论/引用不设行数省略。标题栏和标签固定，来源说明与内容在同一可滚动区域内，因此短窗和 200% 字号仍能到达页尾操作。Windows compact/shrinkWrap 主题下，标签、重试、加载更多明确使用 standard visual density，触控目标至少 44 个逻辑像素。

SelectableText 自身拥有内部滚动区域，不能让它们的零偏移覆盖评论列表的位置。每个标签使用专属控制器：detach 时记录列表位置，创建下一次 ScrollPosition 时直接以该位置布局，不依赖绘制后一帧再跳回。

## 联网核对与参考来源

参考 FluentPlayer 的热门/最新分离、主动打开后才加载、每个标签保留进度、明确加载状态等交互思路，使用本项目 Flutter 组件独立实现，未移植其 Vue/Rust 代码、样式、图片或依赖。固定参考提交为 `facc34373d0f4f7c0e13b87a326291aee79af529`：[CommentsOverlay.vue](https://github.com/zhouchentao666/FluentPlayer/blob/facc34373d0f4f7c0e13b87a326291aee79af529/src/components/Play/CommentsOverlay.vue)。

| 来源 | 已核对的只读契约 | 固定源码 |
| --- | --- | --- |
| QQ 最新 | `c.y.qq.com` 的 `fcg_global_comment_h5.fcg`，`cmd=8`、数字 `topid`、零基 `pagenum` | [项目已锁定的 song.dart](https://github.com/Ferry-200/music_api_dart/blob/c6f3e0abd9c6295b3678ce10d30bc09debda9abe/lib/src/api/qq/module/song.dart) |
| QQ 热门 | `u.y.qq.com` 的 `music.globalComment.CommentRead/GetHotCommentList`，`PageNum` 分页 | [FluentPlayer tx/comment.rs](https://github.com/zhouchentao666/FluentPlayer/blob/facc34373d0f4f7c0e13b87a326291aee79af529/src-tauri/src/music_sdk/sources/tx/comment.rs) |
| 网易最新/热门 | `music.163.com/weapi/v1/resource/comments` / `hotcomments`，`R_SO_4_ID`，`offset` 分页 | [已锁定的 comment.dart](https://github.com/Ferry-200/music_api_dart/blob/c6f3e0abd9c6295b3678ce10d30bc09debda9abe/lib/src/api/netease/module/comment.dart) |

当前 pinned `music_api` 的 QQ `songComment` 是顶层函数，不是 `QQ.songComment` 静态方法；网易是 `Netease.api('/comment/music', ...)`，不是假定的 `Netease.request`。该依赖共享 HTTP 单例且网易封装会自行设置 Cookie，因此本功能使用独立的无 Cookie HTTP 客户端，只复用已经锁定的 `weApi` 请求格式序列化函数，不复制加密源码，也不新增依赖或处理受保护媒体。

许可记录：FluentPlayer 此固定树未提供独立 LICENSE，README 声明遵循其上游 CeruMusic 原许可证；不能仅据仓库标签认定授权范围。[README 许可说明](https://github.com/zhouchentao666/FluentPlayer/blob/facc34373d0f4f7c0e13b87a326291aee79af529/README.md)。现有 pinned music_api 的 LICENSE 仍是占位内容，本轮不把它描述为已确认的开源许可，也未复制它的源码；这是原有依赖的授权核验事项。[已锁定的 LICENSE](https://github.com/Ferry-200/music_api_dart/blob/c6f3e0abd9c6295b3678ce10d30bc09debda9abe/LICENSE)。

## 公共样本验证记录

2026-08-27 UTC 11:30–11:49（北京时间 19:30–19:49），公共 QQ mid `000QhBeg2M2Uyf` 精确解析为数字 ID `498054208`；网易使用公共 ID `186016`。没有搜索或读取用户真实曲库，也没有请求音频。

| 路径 | 首/次页结果 | 第二页去重后的新 ID |
| --- | --- | --- |
| QQ 最新 | code 0，各 20 条 | 20 |
| QQ 热门 | code 0、req.code 0，各 20 条 | 20 |
| 网易最新 | code 200，各 20 条 | 20 |
| 网易热门 | code 200，各 20 条 | 20 |

工具与结构化日志均在仓库外工具目录（从仓库根目录起算）`..\tool`，不随源码或发布包提供：

- `song_comments_probe.dart`、`song-comments-probe-20260827-02.log`、`-03.log`：响应结构、数量、状态；QQ 最新两页差集。
- `song_comments_pagination_probe.dart`、`song-comments-pagination-probe-20260827.log`：另三路各两页，最多 6 个只读请求；均 20 个新 ID。
- 日志不保存评论正文、用户名、用户 ID、头像或 Cookie。探测是手动有界验证，不是产品后台任务。

## 自动化验证

`test/song_comments_test.dart` 27 项 + `test/song_comments_dialog_test.dart` 18 项，合计 **45/45 通过，exit 0**。覆盖身份匹配、固定 HTTPS 只读请求、零认证头、真实字段解析、长文本、格式/拒绝/离线/超时、响应大小、限页去重、独立取消、迟到结果、标签双向滚动恢复、关闭幂等、Windows 紧凑主题触控，以及 320×280 / 200% 字号的浅色、深色、高对比度和减少动画布局。

日志：`tool/qa-song-comments-20260827-194507-279/comments-test-02.log`；定向分析 `comments-analyze.log` 为 **No issues found**。首轮 `comments-test-01.log` 的 40/43 记录保留：发现并修复真实标签滚动位置问题，另两项是测试 finder 返回 EditableText 后误转 SelectableText 的 fixture 类型错误，未削弱实际长文本/布局断言。

未运行或控制 GUI、未访问安装版应用数据、未进行真实音频播放。平台未来可用性仍由明确的失败/重试界面兜底；测试通过不等同于对外部接口永久可用的承诺。
