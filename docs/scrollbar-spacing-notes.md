# 主内容滚动条间距

## 本轮实现

使用共享 `AppContentScrollbar` 保留 Flutter Material `Scrollbar`，没有用图标
替代滚动条，也没有更改行末菜单或拖拽柄的行为。

- 列表/网格的尾侧预留 24 逻辑像素独立区域；左右书写方向使用对应尾侧。
- 拇指常态 6、悬停/拖动 8 像素，距外侧 4 像素，因此内容与最宽拇指之间仍有
  12 像素空隙。内容视口整体缩进，行末点击区域不会伸进这块区域。
- 拇指使用当前主题的 `onSurfaceVariant` / `primary`，保留 Material 的
  交互、绘制及无溢出时隐藏逻辑。
- 关闭这个子树的自动滚动条，避免 Windows 同时插入第二条；保留原有滚轮、
  触摸与触控板策略。控制器支持调用方复用，内部控制器按需创建并自行释放。

接入：总乐库等 `UniPage` 列表/网格/排序列表，艺术家/专辑 `UniDetailPage`，
歌单网格与 `PlaylistReorderSurface`，分类总览和歌曲详情，搜索结果和当前播放队列。
弹窗、侧边栏和桌面歌词未在本轮统一修改；现有专用横向分类栏也保持原样。

## 非图形验证

仅运行 widget 测试和静态检查，未打开应用、GUI 或进行视觉验收，也未访问真实
用户曲库/设置。以下 7 份测试共 **121/121 通过**：

- `test/app_content_scrollbar_test.dart`（新增 7 项）
- `test/music_grid_test.dart`
- `test/playlist_reorder_surface_test.dart`
- `test/playlist_browser_test.dart`
- `test/category_grid_test.dart`
- `test/categories_page_test.dart`
- `test/page_entrance_test.dart`

覆盖单条 Material 滚动条、LTR/RTL 几何间距、实际拇指拖动不触发菜单、控制器
替换/外部所有权、触摸策略，以及原有歌单拖拽、边缘自动滚动、列表/网格切换、
定位、懒加载、分类和 200% 字号回归。9 个实现文件与新增测试 scoped analyze
无问题。

## 顺带只读审查：具体改善点

以下为代码观察，未据此声称已测得卡顿。第 1 项随后获授权单独做了有界优化，
其余保持只读记录：

1. `UniPage.result`、`UniDetailPage.result`、`PlaylistBrowser.build` 原先每次
   建立完整 grid key→index 映射，即使当前为列表模式。已单独改为只在网格分支
   建立，列表分支返回常量空映射；没有改变排序、队列或网格的 identity 规则。
   `test/list_mode_index_map_test.dart` 使用 2048 项读取计数集合，约束列表仅
   读取可视/缓存行，网格继续读取全量索引；已有网格重排/定位用例继续回归。
2. `PlaylistBrowser.build` 先 `_rows(current)`，再 `_orderedOccurrences(current)`；
   后者的第一次递归再次 `_rows(current)`。非自定义排序时，当前层会重复构造和
   排序。若将来优化，可把已经排序的当前层传入队列遍历，同时保留对子层的排序、
   循环检测、entry ID 和重复歌曲引用语义，不宜直接合并为按歌曲去重的列表。
3. 搜索结果的本地部分用 `SliverList.builder`，但 `_onlineSliver` 的已完成结果
   在 `Column` 中展开所有 `AudioTile`。联网结果多时不会按可视区域懒构建；
   可在独立任务中改为异步 sliver 列表，并回归加载/错误/混合搜索布局。

另一个可用性观察：`SongCommentMatchDialog` 的评论预览位于全部候选结果之后，
候选很多时需要继续向下滚动才能看见。这是现有布局事实，本轮未修改。
