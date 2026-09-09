# 自定义歌源 API 接入

[返回项目说明](../README.md) · [go-music-api 配置示例](examples/go-music-api-jamendo.json)

Dan Player 的自定义歌源使用显式能力声明。搜索只返回歌曲候选；播放或下载地址在用户选择歌曲后才解析。接口均为 `GET`，响应须为 UTF-8。下面的通用 v1 契约允许对象包在 `data` 字段中；网易云增强 API 等专用协议由对应适配器解析，不能只换地址当作通用 v1。

## Dan Player 通用 v1

配置可让多个能力共用一个服务地址，也可为每项能力指定相对或绝对 HTTP(S) 端点。标题、艺术家、专辑和时长是搜索候选的基本字段；声明 `metadata` 后接收扩展字段，声明 `cover` 后读取封面。元数据与封面端点留空时使用搜索结果；显式 `metadata` 端点按歌曲 `id` 等信息返回歌曲对象（可放在 `track` 内），显式 `cover` 端点接受 `id` 并直接返回图片。补充元数据不会改变已选歌曲的稳定 ID。

### 搜索

请求参数：`q`、`limit`。响应：

```json
{
  "tracks": [
    {
      "id": "opaque-track-id",
      "title": "Track title",
      "artist": "Artist",
      "album": "Album",
      "duration": 180,
      "coverUrl": "https://example.test/cover.jpg",
      "streamAvailable": true,
      "downloadAllowed": false
    }
  ]
}
```

`id` 与 `title` 必填；`duration` 使用秒。`playable` 可替代 `streamAvailable`，`artworkUrl` 或 `cover` 可替代 `coverUrl`。`streamAvailable: false` 会直接阻止播放；缺少该字段表示未知，实际播放时仍会尝试解析。搜索响应中的媒体 URL 会被忽略。

### 歌词

请求包含 `title`、`artist`、`album`、`duration`、`fileName`、`displayTitle`；来源自己的联网歌曲还会包含 `id`。服务可直接返回纯文本歌词，或返回：

```json
{
  "type": "lrc",
  "lyric": "[00:01.00]Main line",
  "translation": "[00:01.00]Translated line"
}
```

`lrc` 或 `content` 可替代 `lyric`；`format` 可替代 `type`。请求不会发送本地绝对路径。

### 评论

首次请求参数：`id`、`page`（从 0 开始）、`limit`，不指定排序，读取来源默认评论列表。来源如果支持热门或最新，可在响应中明确声明 `supportedSorts`；用户点击相应分类后才追加 `sort=hot` 或 `sort=latest`。只声明 `comments` 能力不代表同时支持这两种排序，未声明时不会显示对应分类。响应示例：

```json
{
  "comments": [
    {
      "id": "comment-id",
      "author": "Listener",
      "content": "Comment text",
      "publishedAt": "2026-09-02T12:00:00Z",
      "likeCount": 7
    }
  ],
  "hasMore": false,
  "total": 1,
  "supportedSorts": ["hot", "latest"]
}
```

评论为只读；播放器不会发送评论、点赞或账号 Cookie。若歌曲需要用于评论，`id` 必须是 1–256 个字符的安全不透明标识：首字符为字母或数字，其余字符仅限字母、数字、点、下划线、波浪号和短横线；不能使用 URL、路径、空白或查询字符串。其他搜索结果可使用更长的不透明 ID，但不能据此读取评论。

### 播放与下载解析

请求参数：`id`、`purpose`，其中 `purpose` 为 `stream` 或 `download`。响应：

```json
{
  "url": "https://media.example.test/song.mp3",
  "expiresAt": "2026-09-02T13:00:00Z",
  "downloadAllowed": true,
  "mimeType": "audio/mpeg",
  "supportsRange": true
}
```

配置声明下载能力后即可尝试解析；不要求搜索行和解析响应额外返回 `downloadAllowed: true`。明确返回不可下载或需要登录时会停止。播放与下载 URL 必须是没有用户信息和片段的 HTTP(S) 地址。

## 配置文件

设置页导出的文件只包含配置，可合并导入。下面是分离端点的最小示例：

```json
{
  "format": "dan-player-custom-music-sources",
  "version": 1,
  "profiles": [
    {
      "id": "my-source",
      "name": "My source",
      "baseUrl": "https://music.example.test/",
      "enabled": true,
      "protocol": "dan-source-v1",
      "protocolVersion": 1,
      "capabilities": ["search", "metadata", "cover", "lyrics", "stream"],
      "endpoints": {
        "search": "v1/search",
        "lyrics": "v1/lyrics",
        "stream": "v1/resolve"
      }
    }
  ]
}
```

配置 ID 最长 96 个字符，首字符必须是字母或数字，其余字符只允许字母、数字、点、下划线与短横线。它会以 `custom:<配置 ID>` 的形式写入收藏、歌单和评论关联，因此编辑配置时保持稳定；重新导入同一 ID 可以重新绑定这些记录，普通新建会生成新 ID。最多保存 32 个配置；导入会逐项跳过无效记录，ID 冲突时由用户选择更新、仅添加新项或取消。

公开请求头会过滤 Cookie、Authorization、token、secret、password 等敏感名称；播放器不会把安全凭据正文写入配置，只保存未来安全凭据条目的引用，在系统安全凭据存储接入前会拒绝发送认证请求。不要把密钥直接写进地址或公开请求头，因为这些配置会随导出和完整缓存备份保存。完整缓存备份另会包含联网收藏、歌单和评论关联，但不复制音乐文件；HTTP 端点不会作为本地绝对路径改写。

停用或删除配置不会删除这些本地收藏、歌单或关联，也不会清除已经保存的歌曲信息和封面 URL；新的搜索、歌词、评论、播放和下载请求会停止。已保存的封面 URL 也受当前配置门禁：只有同一配置仍存在、启用且声明封面能力时才会联网读取，停用或删除后不会访问旧封面服务器；重新导入同一稳定 ID 后可恢复。

## 兼容预设与边界

- `legacy-lyrics`：LRC API 的歌词协议；名称仅用于配置兼容，界面显示为普通第三方 API。内置 LRC API 可改名、改地址、停用或删除。
- `kugou-v1`：独立实现的酷狗协议适配，参考 ZeroBit 的歌词、封面取用方式及 ECHO 的音源解析方式。搜索、歌词、歌曲信息、播放和下载分别使用可编辑的端点；评论没有默认端点，不宣称支持。
- `netease-api-v1`：连接自行部署的网易云 Node.js API / 增强版。设置中“添加内置预设 → 网易云增强 API”可添加完整可编辑配置，默认关闭，地址 `http://127.0.0.1:3000/` 需要对应的真实服务。
- `go-music-api-v1`：连接用户自行部署的 [`go-music-api` 固定提交](https://github.com/guohuiyuan/go-music-api/tree/bacdfbe6cf6a5ba7331463d2039e3aac915c627f) 兼容服务，默认使用完整路径 `/api/v1/music/search`、`/api/v1/music/lyric`、`/api/v1/music/cover` 与 `/api/v1/music/stream`；最后一个端点同时用于播放和下载代理。Dan Player 不提供或代理该服务器。
- 通用 v1 配置声明下载能力即可尝试实际解析，不再强制接口重复提供 `downloadAllowed: true`。搜索或解析返回 `downloadAllowed: false`、`canDownload: false`、要求登录或拒绝访问时仍会停止。`go-music-api-v1` 使用自托管流代理；它不需要额外的解析授权 JSON。
- `go-music-api-v1` 的歌词需要该来源搜索结果中保存的不透明歌曲身份，不能仅凭任意本地歌曲的标题和艺术家查询。
- 单次请求有 6 秒总时限，并限制响应大小、搜索条数和并发数；不跟随接口重定向。
- 能力声明不保证接口长期可用，也不构成登录、付费、DRM 或版权授权。接入者应只返回自己有权提供的内容。

## 能力测试

用户输入歌曲名称（必填）、艺术家和专辑（选填）后，分别检测搜索、歌曲信息、封面、歌词、评论、播放和下载。播放与下载只解析地址并取少量响应，不启动播放、不保存歌曲。没有匹配样本、接口不支持、超时、需登录与成功分别显示；一次无结果不会自动删除已声明的能力。用户确认后才可将检测成功的能力应用到第三方配置。

自动预置仅在初次安装或一次性迁移时执行；用户也可通过“添加内置预设”主动选择。明确清空列表及已保存后删除的预设不会在重启时复活。旧 `LyricApiUrl` 的名称、地址和开关会保留，只有原来的默认名称改为 LRC API。

网易云增强 API 预设不会在升级时自动启用或启动服务器；已有用户可通过“添加内置预设”选择。该协议使用 `keywords` 搜索、`ids` 读取已选歌曲详情、`id` 获取歌词和音频。最新评论使用 `comment/music` 的 `offset`，热门评论使用同目录 `comment/hot` 的 `type=0` / `offset`（默认最多 10 页）；不混用 `comment/new` 的游标协议。若服务有路径前缀，基地址和相对端点会保留该前缀。搜索结果不包含已解析音频，播放时访问 `song/url`，下载时独立访问 `song/download/url`；没有有效 URL、身份不符、服务拒绝或 `freeTrialInfo` 试听片段均不会当作完整音频。账户登录、点赞、发评论等写入能力不在该适配范围。

整体信息架构仅参考 [ZeroBit Player 固定提交的歌词 API 选择界面](https://github.com/Empty-57/ZeroBit-Player/blob/e47d34fb5c946a6cf10041377b15eb6f089f5d28/lib/pages/setting_page.dart)（[GPL-3.0](https://github.com/Empty-57/ZeroBit-Player/blob/e47d34fb5c946a6cf10041377b15eb6f089f5d28/LICENSE)）与 [ECHO 固定提交的 provider 文档](https://github.com/Moekotori/ECHO/blob/45ea979d18da08234307b13c215f56abe3c00556/docs/ECHO_NEXT_PLUGINS.md)（[LGPL-3.0-only](https://github.com/Moekotori/ECHO/blob/45ea979d18da08234307b13c215f56abe3c00556/LICENSE)）；`go-music-api` 固定兼容目标采用 [AGPL-3.0](https://github.com/guohuiyuan/go-music-api/blob/bacdfbe6cf6a5ba7331463d2039e3aac915c627f/LICENSE)。协议和实现均为 Dan Player 独立代码，没有复制或捆绑这些项目的代码、服务、远程脚本、平台账号或登录凭据。
