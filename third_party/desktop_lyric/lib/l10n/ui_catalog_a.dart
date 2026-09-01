// Application UI strings 0–249, in first-appearance order.
// Values are English, Japanese and Korean. Media/user text is never translated.
const Map<String, List<String>> uiCatalogA = {
  '提示': ['Info', 'お知らせ', '알림'],
  '成功': ['Success', '完了', '완료'],
  '注意': ['Warning', '注意', '주의'],
  '错误': ['Error', 'エラー', '오류'],
  '关闭通知': ['Dismiss notification', '通知を閉じる', '알림 닫기'],
  '滚动或滑动查看更多排序项': [
    'Scroll or swipe for more sort options',
    'スクロールまたはスワイプで他の並べ替え項目を表示',
    '스크롤하거나 밀어서 정렬 항목 더 보기',
  ],
  '排序方式，可滚动查看更多字段': [
    'Sort order; scroll for more fields',
    '並べ替え順。スクロールで他の項目を表示',
    '정렬 기준, 스크롤하여 항목 더 보기',
  ],
  '排序方式': ['Sort by', '並べ替え', '정렬 기준'],
  '排序': ['Sort', '並べ替え', '정렬'],
  '排序：{0}': ['Sort: {0}', '並べ替え：{0}', '정렬: {0}'],
  '新建歌单 播放全部 自定义 移除所选 Ag（0123）': [
    'New playlist Play all Custom Remove selected Ag (0123)',
    '新規プレイリスト すべて再生 カスタム 選択項目を削除 Ag（0123）',
    '새 재생목록 모두 재생 사용자 지정 선택 항목 제거 Ag (0123)',
  ],
  '歌名': ['Song title', '曲名', '곡명'],
  '作曲家': ['Composer', '作曲者', '작곡가'],
  '专辑': ['Album', 'アルバム', '앨범'],
  '时长': ['Duration', '再生時間', '재생 시간'],
  '联网歌曲信息由来源提供，不能修改其标签': [
    'Online track information comes from its source; its tags cannot be edited',
    'オンライン楽曲の情報は配信元が提供しているため、タグは編集できません',
    '온라인 곡 정보는 제공처에서 가져오므로 태그를 수정할 수 없습니다',
  ],
  '已填入候选信息，尚未写入文件。请核对后点击“保存”。': [
    'Candidate information is filled in but not written to the file. Review it, then select Save.',
    '候補情報を入力しました。ファイルにはまだ書き込まれていません。確認して「保存」を選んでください。',
    '후보 정보를 입력했으며 아직 파일에는 기록하지 않았습니다. 확인 후 “저장”을 선택하세요.',
  ],
  '准备歌曲信息失败：{0}': [
    'Could not prepare track information: {0}',
    '楽曲情報を準備できませんでした：{0}',
    '곡 정보를 준비하지 못했습니다: {0}',
  ],
  '选择专辑图片': ['Choose album image', 'アルバム画像を選択', '앨범 이미지 선택'],
  '图片文件': ['Image files', '画像ファイル', '이미지 파일'],
  '所有文件': ['All files', 'すべてのファイル', '모든 파일'],
  '选择封面失败：{0}': [
    'Could not select cover art: {0}',
    'カバー画像を選択できませんでした：{0}',
    '커버 이미지를 선택하지 못했습니다: {0}',
  ],
  '文件名和标题不能为空': [
    'File name and title cannot be empty',
    'ファイル名とタイトルは空にできません',
    '파일 이름과 제목은 비워 둘 수 없습니다',
  ],
  '已更新歌曲信息': ['Track information updated', '楽曲情報を更新しました', '곡 정보를 업데이트했습니다'],
  '更新歌曲信息失败：{0}': [
    'Could not update track information: {0}',
    '楽曲情報を更新できませんでした：{0}',
    '곡 정보를 업데이트하지 못했습니다: {0}',
  ],
  '编辑歌曲信息': ['Edit track information', '楽曲情報を編集', '곡 정보 편집'],
  '联网查找信息与封面': [
    'Find information and cover online',
    '情報とカバー画像をオンライン検索',
    '온라인에서 정보 및 커버 찾기'
  ],
  '文件名': ['File name', 'ファイル名', '파일 이름'],
  '标题名': ['Title', 'タイトル', '제목'],
  '艺术家名': ['Artist name', 'アーティスト名', '아티스트 이름'],
  '专辑名': ['Album name', 'アルバム名', '앨범 이름'],
  '不更改专辑图片': ['Keep current album image', 'アルバム画像を変更しない', '현재 앨범 이미지 유지'],
  '上传图片': ['Upload image', '画像をアップロード', '이미지 업로드'],
  '取消': ['Cancel', 'キャンセル', '취소'],
  '正在写入': ['Writing…', '書き込み中…', '기록 중…'],
  '保存': ['Save', '保存', '저장'],
  '已从总乐库移除': ['Removed from library', 'ライブラリから削除しました', '전체 보관함에서 제거했습니다'],
  '已加入总乐库': ['Added to library', 'ライブラリに追加しました', '전체 보관함에 추가했습니다'],
  '更新总乐库失败：{0}': [
    'Could not update library: {0}',
    'ライブラリを更新できませんでした：{0}',
    '전체 보관함을 업데이트하지 못했습니다: {0}',
  ],
  '当前来源不支持下载': [
    'This source does not support downloads',
    'この配信元はダウンロードに対応していません',
    '현재 제공처는 다운로드를 지원하지 않습니다',
  ],
  '下载联网音乐': ['Download online track', 'オンライン楽曲をダウンロード', '온라인 곡 다운로드'],
  '音频文件': ['Audio files', '音声ファイル', '오디오 파일'],
  '正在下载 {0}…': ['Downloading {0}…', '{0} をダウンロード中…', '{0} 다운로드 중…'],
  '下载完成：{0}': ['Download complete: {0}', 'ダウンロード完了：{0}', '다운로드 완료: {0}'],
  '下载失败：{0}': ['Download failed: {0}', 'ダウンロードに失敗しました：{0}', '다운로드 실패: {0}'],
  '下一首播放': ['Play next', '次に再生', '다음에 재생'],
  '加入歌单…': ['Add to playlist…', 'プレイリストに追加…', '재생목록에 추가…'],
  '多选': ['Select multiple', '複数選択', '여러 항목 선택'],
  '来源：{0}': ['Source: {0}', '提供元：{0}', '출처: {0}'],
  '从总乐库移除': ['Remove from library', 'ライブラリから削除', '전체 보관함에서 제거'],
  '加入总乐库': ['Add to library', 'ライブラリに追加', '전체 보관함에 추가'],
  '下载': ['Download', 'ダウンロード', '다운로드'],
  '下载不可用：{0}': [
    'Download unavailable: {0}',
    'ダウンロードできません：{0}',
    '다운로드할 수 없음: {0}'
  ],
  '联网歌曲详情': ['Online track details', 'オンライン楽曲の詳細', '온라인 곡 상세 정보'],
  '艺术家': ['Artist', 'アーティスト', '아티스트'],
  '编辑歌词': ['Edit lyrics', '歌詞を編集', '가사 편집'],
  '详细信息': ['Details', '詳細情報', '상세 정보'],
  '联网音乐 · {0}': ['Online music · {0}', 'オンライン楽曲 · {0}', '온라인 음악 · {0}'],
  '正在获取播放地址': ['Getting playback URL', '再生URLを取得中', '재생 주소 가져오는 중'],
  '歌曲操作': ['Track actions', '楽曲の操作', '곡 작업'],
  '未知作曲家': ['Unknown composer', '作曲者不明', '알 수 없는 작곡가'],
  '{0} · 联网音乐 · {1}': [
    '{0} · Online music · {1}',
    '{0} · オンライン楽曲 · {1}',
    '{0} · 온라인 음악 · {1}'
  ],
  '刷新失败：{0}': ['Refresh failed: {0}', '更新に失敗しました：{0}', '새로 고침 실패: {0}'],
  '正在准备扫描': ['Preparing to scan', 'スキャンを準備中', '검색 준비 중'],
  '当前歌词：{0}': ['Current lyric: {0}', '現在の歌詞：{0}', '현재 가사: {0}'],
  '窗口操作失败，请重试': [
    'Window action failed. Please try again.',
    'ウィンドウ操作に失敗しました。再試行してください。',
    '창 작업에 실패했습니다. 다시 시도하세요.'
  ],
  '尚未选择歌曲': ['No track selected', '楽曲が選択されていません', '선택한 곡 없음'],
  '迷你播放器': ['Mini player', 'ミニプレーヤー', '미니 플레이어'],
  '还原完整播放器（{0}）': [
    'Restore full player ({0})',
    '通常のプレーヤーに戻る（{0}）',
    '전체 플레이어로 복원 ({0})'
  ],
  '取消置顶': ['Turn off always on top', '最前面表示を解除', '항상 위에 표시 해제'],
  '窗口置顶': ['Always on top', '最前面に表示', '항상 위에 표시'],
  '最小化': ['Minimize', '最小化', '최소화'],
  '退出播放器': ['Quit player', 'プレーヤーを終了', '플레이어 종료'],
  '上一首': ['Previous track', '前の曲', '이전 곡'],
  '正在缓冲': ['Buffering', 'バッファリング中', '버퍼링 중'],
  '暂停': ['Pause', '一時停止', '일시 정지'],
  '播放': ['Play', '再生', '재생'],
  '下一首': ['Next track', '次の曲', '다음 곡'],
  '播放进度': ['Playback progress', '再生位置', '재생 진행률'],
  '当前歌曲实时频谱': [
    'Live spectrum of current track',
    '現在の曲のリアルタイムスペクトラム',
    '현재 곡의 실시간 스펙트럼'
  ],
  '音频频谱，动态效果已暂停': [
    'Audio spectrum, animation paused',
    '音声スペクトラム、アニメーションは停止中',
    '오디오 스펙트럼, 애니메이션 일시 정지됨'
  ],
  '歌词暂不可用': ['Lyrics unavailable', '歌詞を表示できません', '가사를 표시할 수 없습니다'],
  '{0} · 无时间轴歌词': [
    '{0} · Untimed lyrics',
    '{0} · タイムスタンプなしの歌詞',
    '{0} · 시간 정보 없는 가사'
  ],
  '间奏 · 聆听音乐': [
    'Interlude · Enjoy the music',
    '間奏 · 音楽をお楽しみください',
    '간주 · 음악을 감상하세요'
  ],
  '联网音乐的歌词为只读，不能修改': [
    'Online track lyrics are read-only and cannot be edited',
    'オンライン楽曲の歌詞は読み取り専用のため、編集できません',
    '온라인 곡의 가사는 읽기 전용이므로 수정할 수 없습니다',
  ],
  '读取歌词失败：{0}': [
    'Could not read lyrics: {0}',
    '歌詞を読み込めませんでした：{0}',
    '가사를 읽지 못했습니다: {0}'
  ],
  '歌词不能为空': ['Lyrics cannot be empty', '歌詞は空にできません', '가사는 비워 둘 수 없습니다'],
  '没有识别到有效的 LRC 时间戳': [
    'No valid LRC timestamps found',
    '有効なLRCタイムスタンプが見つかりません',
    '유효한 LRC 타임스탬프가 없습니다'
  ],
  '歌词已保存到 {0}': ['Lyrics saved to {0}', '歌詞を {0} に保存しました', '가사를 {0}에 저장했습니다'],
  '保存歌词失败：{0}': [
    'Could not save lyrics: {0}',
    '歌詞を保存できませんでした：{0}',
    '가사를 저장하지 못했습니다: {0}'
  ],
  '放弃歌词修改？': ['Discard lyric changes?', '歌詞の変更を破棄しますか？', '가사 변경 사항을 버릴까요?'],
  '尚未保存的内容将丢失。': [
    'Unsaved changes will be lost.',
    '未保存の内容は失われます。',
    '저장하지 않은 내용이 사라집니다.'
  ],
  '继续编辑': ['Keep editing', '編集を続ける', '계속 편집'],
  '放弃修改': ['Discard changes', '変更を破棄', '변경 사항 버리기'],
  '编辑歌词 · {0}': ['Edit lyrics · {0}', '歌詞を編集 · {0}', '가사 편집 · {0}'],
  '保存为同名 .lrc 文件（UTF-8）': [
    'Save as a matching .lrc file (UTF-8)',
    '同じ名前の .lrc ファイル（UTF-8）として保存',
    '같은 이름의 .lrc 파일로 저장 (UTF-8)'
  ],
  '插入当前播放时间': ['Insert current playback time', '現在の再生時刻を挿入', '현재 재생 시간 삽입'],
  '[00:00.00]歌词内容': [
    '[00:00.00]Lyrics here',
    '[00:00.00]歌詞を入力',
    '[00:00.00]가사 내용'
  ],
  '保存歌词': ['Save lyrics', '歌詞を保存', '가사 저장'],
  'Ag国': ['AgW', 'Ag国', 'Ag국'],
  '未知': ['Unknown', '不明', '알 수 없음'],
  '未知艺术家': ['Unknown artist', 'アーティスト不明', '알 수 없는 아티스트'],
  '未知专辑': ['Unknown album', 'アルバム不明', '알 수 없는 앨범'],
  '搜索失败，请检查网络后重试': [
    'Search failed. Check your connection and try again.',
    '検索に失敗しました。ネットワークを確認して再試行してください。',
    '검색에 실패했습니다. 네트워크를 확인한 후 다시 시도하세요.'
  ],
  '封面获取失败：{0}。可取消勾选“封面”后继续填入文字信息。': [
    'Could not fetch cover art: {0}. Uncheck Cover to fill in text information only.',
    'カバー画像を取得できませんでした：{0}。「カバー画像」のチェックを外すと、文字情報のみ入力できます。',
    '커버 이미지를 가져오지 못했습니다: {0}. “커버” 선택을 해제하면 텍스트 정보만 입력할 수 있습니다.',
  ],
  '联网查找歌曲信息与封面': [
    'Find track information and cover online',
    '楽曲情報とカバー画像をオンライン検索',
    '온라인에서 곡 정보 및 커버 찾기'
  ],
  '歌曲名 / 艺术家': ['Song title / Artist', '曲名 / アーティスト', '곡명 / 아티스트'],
  '搜索': ['Search', '検索', '검색'],
  '标题': ['Title', 'タイトル', '제목'],
  '封面': ['Cover', 'カバー画像', '커버'],
  '填入候选封面': ['Use candidate cover', '候補のカバー画像を入力', '후보 커버 입력'],
  '候选未提供封面': [
    'No cover provided for this candidate',
    'この候補にはカバー画像がありません',
    '후보에 커버 이미지가 없습니다'
  ],
  '选中候选结果后仅填入编辑器；点击“保存”才会写入本地文件。': [
    'Selecting a candidate only fills in the editor. The local file is updated only when you select Save.',
    '候補を選んでもエディターへの入力のみで、「保存」を選ぶまでローカルファイルには書き込まれません。',
    '후보를 선택하면 편집기에만 입력됩니다. “저장”을 선택해야 로컬 파일에 기록됩니다.',
  ],
  '没有找到候选结果，可修改关键词后重试': [
    'No candidates found. Try different search terms.',
    '候補が見つかりません。キーワードを変えて再試行してください。',
    '후보가 없습니다. 검색어를 바꿔 다시 시도하세요.'
  ],
  '获取封面…': ['Fetching cover…', 'カバー画像を取得中…', '커버 가져오는 중…'],
  '填入编辑器': ['Fill in editor', 'エディターに入力', '편집기에 입력'],
  '歌单读取尚未完成，请先修复数据文件并重新读取；原文件没有改动。': [
    'Playlist loading is incomplete. Repair the data file and reload it; the original file has not been changed.',
    'プレイリストの読み込みが完了していません。データファイルを修復して再読み込みしてください。元のファイルは変更していません。',
    '재생목록을 완전히 읽지 못했습니다. 데이터 파일을 복구한 후 다시 읽어 주세요. 원본 파일은 변경하지 않았습니다.',
  ],
  '无法更改歌单：{0}': [
    'Could not change playlist: {0}',
    'プレイリストを変更できませんでした：{0}',
    '재생목록을 변경하지 못했습니다: {0}'
  ],
  '更改已保留在当前会话，但保存失败；可在页面上重试。': [
    'Changes are kept for this session, but saving failed. You can retry on this page.',
    '変更は現在のセッションに保持されていますが、保存に失敗しました。このページで再試行できます。',
    '변경 사항은 현재 세션에 유지되지만 저장하지 못했습니다. 이 페이지에서 다시 시도할 수 있습니다.',
  ],
  '保存仍未成功：{0}': [
    'Saving still failed: {0}',
    '再度保存に失敗しました：{0}',
    '다시 저장하지 못했습니다: {0}'
  ],
  '新建歌单': ['New playlist', '新規プレイリスト', '새 재생목록'],
  '新建子歌单': ['New nested playlist', '新規サブプレイリスト', '새 하위 재생목록'],
  '重命名歌单': ['Rename playlist', 'プレイリスト名を変更', '재생목록 이름 바꾸기'],
  '无法选择歌单封面：{0}': [
    'Could not select playlist cover: {0}',
    'プレイリストのカバー画像を選択できませんでした：{0}',
    '재생목록 커버를 선택하지 못했습니다: {0}'
  ],
  '这个歌单还没有可播放的歌曲。': [
    'This playlist has no playable tracks yet.',
    'このプレイリストにはまだ再生できる曲がありません。',
    '이 재생목록에는 아직 재생할 수 있는 곡이 없습니다.'
  ],
  '移除歌曲引用？': ['Remove track reference?', '楽曲の参照を削除しますか？', '곡 참조를 제거할까요?'],
  '删除歌单？': ['Delete playlist?', 'プレイリストを削除しますか？', '재생목록을 삭제할까요?'],
  '仅从当前歌单移除“{0}”。不会删除磁盘音乐或总乐库中的歌曲。': [
    'Remove “{0}” only from this playlist. Music files and tracks in the library will not be deleted.',
    '「{0}」を現在のプレイリストからのみ削除します。ディスク上の音楽ファイルやライブラリの曲は削除されません。',
    '현재 재생목록에서만 “{0}”을(를) 제거합니다. 디스크의 음악 파일이나 전체 보관함의 곡은 삭제하지 않습니다.',
  ],
  '删除“{0}”及其 {1} 个子歌单、{2} 个歌曲引用？\n\n不会删除磁盘音乐或总乐库中的歌曲。': [
    'Delete “{0}”, its {1} nested playlists and {2} track references?\n\nMusic files and tracks in the library will not be deleted.',
    '「{0}」と、その中のサブプレイリスト {1} 個、楽曲の参照 {2} 件を削除しますか？\n\nディスク上の音楽ファイルやライブラリの曲は削除されません。',
    '“{0}” 및 하위 재생목록 {1}개와 곡 참조 {2}개를 삭제할까요?\n\n디스크의 음악 파일이나 전체 보관함의 곡은 삭제하지 않습니다.',
  ],
  '移除': ['Remove', '削除', '제거'],
  '删除歌单': ['Delete playlist', 'プレイリストを削除', '재생목록 삭제'],
  '移除所选项目？': ['Remove selected items?', '選択した項目を削除しますか？', '선택한 항목을 제거할까요?'],
  '移除所选 {0} 个项目，其中包含 {1} 个歌单及其全部子歌单、{2} 个歌曲引用。\n\n不会删除磁盘音乐或总乐库中的歌曲。': [
    'Remove {0} selected items, including {1} playlists with all their nested playlists and {2} track references.\n\nMusic files and tracks in the library will not be deleted.',
    '選択した {0} 項目を削除します。対象には、プレイリスト {1} 個とそのすべてのサブプレイリスト、楽曲の参照 {2} 件が含まれます。\n\nディスク上の音楽ファイルやライブラリの曲は削除されません。',
    '선택한 항목 {0}개를 제거합니다. 여기에는 재생목록 {1}개와 모든 하위 재생목록, 곡 참조 {2}개가 포함됩니다.\n\n디스크의 음악 파일이나 전체 보관함의 곡은 삭제하지 않습니다.',
  ],
  '移除所选': ['Remove selected', '選択項目を削除', '선택 항목 제거'],
  '将“{0}”移动到': ['Move “{0}” to', '「{0}」の移動先', '“{0}” 이동 위치'],
  '歌单关系包含循环或超过最大层数': [
    'Playlist hierarchy contains a cycle or exceeds the maximum depth',
    'プレイリストの階層に循環があるか、最大階層数を超えています',
    '재생목록 계층에 순환 참조가 있거나 최대 깊이를 초과했습니다'
  ],
  '打开歌单': ['Open playlist', 'プレイリストを開く', '재생목록 열기'],
  '播放歌单（含子歌单）': [
    'Play playlist (including nested)',
    'プレイリストを再生（サブプレイリストを含む）',
    '재생목록 재생 (하위 목록 포함)'
  ],
  '重命名': ['Rename', '名前を変更', '이름 바꾸기'],
  '更改所选歌曲': ['Change selected tracks', '選択した曲を変更', '선택한 곡 변경'],
  '更改歌单封面': ['Change playlist cover', 'プレイリストのカバー画像を変更', '재생목록 커버 변경'],
  '恢复默认封面': ['Restore default cover', '既定のカバー画像に戻す', '기본 커버로 복원'],
  '上移（Alt + ↑）': ['Move up (Alt + ↑)', '上へ移動（Alt + ↑）', '위로 이동 (Alt + ↑)'],
  '下移（Alt + ↓）': ['Move down (Alt + ↓)', '下へ移動（Alt + ↓）', '아래로 이동 (Alt + ↓)'],
  '移动到…': ['Move to…', '移動先を選択…', '다음으로 이동…'],
  '移到上一级': ['Move up one level', '1つ上の階層へ移動', '상위 단계로 이동'],
  '从当前歌单移除': ['Remove from this playlist', '現在のプレイリストから削除', '현재 재생목록에서 제거'],
  '删除歌单…': ['Delete playlist…', 'プレイリストを削除…', '재생목록 삭제…'],
  '松开移入': ['Release to move inside', '離すと中に移動', '놓아서 안으로 이동'],
  '不能移入': ['Cannot move inside', '中に移動できません', '안으로 이동할 수 없음'],
  '拖动排序 · 点按打开菜单': [
    'Drag to reorder · Click for menu',
    'ドラッグで並べ替え · クリックでメニュー',
    '끌어서 순서 변경 · 클릭하여 메뉴 열기'
  ],
  '歌单项目操作（切到自定义可拖动）': [
    'Playlist item actions (switch to Custom to drag)',
    'プレイリスト項目の操作（カスタム順でドラッグ可能）',
    '재생목록 항목 작업 (사용자 지정 정렬에서 끌기 가능)'
  ],
  '{0} · {1} 首歌曲（含子歌单）': [
    '{0} · {1} tracks (including nested playlists)',
    '{0} · {1} 曲（サブプレイリストを含む）',
    '{0} · {1}곡 (하위 재생목록 포함)'
  ],
  '{0} 个直接项目 · {1} 首歌曲（含子歌单）': [
    '{0} direct items · {1} tracks (including nested playlists)',
    '直下の項目 {0} 件 · {1} 曲（サブプレイリストを含む）',
    '바로 아래 항목 {0}개 · {1}곡 (하위 재생목록 포함)'
  ],
  '播放此歌单（含子歌单）': [
    'Play this playlist (including nested)',
    'このプレイリストを再生（サブプレイリストを含む）',
    '이 재생목록 재생 (하위 목록 포함)'
  ],
  '选择{0}': ['Select {0}', '{0} を選択', '{0} 선택'],
  '全部歌单': ['All playlists', 'すべてのプレイリスト', '모든 재생목록'],
  '歌单操作': ['Playlist actions', 'プレイリストの操作', '재생목록 작업'],
  '自定义排序：拖动歌曲或子歌单右侧的三个点，其他行会连续让位；点按三个点、右键或长按行可打开菜单。\n\n拖到子歌单的封面/名称区域并稍作停留，高亮后松开即可移入；也可通过菜单“移动到…”选择目标。\n\n名称等排序仅改变显示和播放次序，不覆盖自定义顺序；切回“自定义”即可继续拖动。\n\n顺序播放会按各层次序进入子歌单，播完再返回父歌单。Alt + ↑ / ↓ 可在自定义模式调序，Shift + F10 打开菜单。':
      [
    'Custom order: drag the three dots beside a track or nested playlist. Other rows move aside smoothly. Click the dots, right-click, or long-press a row to open its menu.\n\nHover over a nested playlist’s cover or name until it highlights, then release to move the item inside. You can also choose a destination with Move to… in the menu.\n\nSorting by name or other fields changes only the display and playback order, not your custom order. Switch back to Custom to drag again.\n\nSequential playback enters nested playlists in their order and returns to the parent when finished. In Custom mode, Alt + ↑ / ↓ reorders items; Shift + F10 opens the menu.',
    'カスタム順：曲やサブプレイリストの右にある3点をドラッグすると、他の行が滑らかに移動して場所を空けます。3点のクリック、右クリック、または行の長押しでメニューを開けます。\n\nサブプレイリストのカバー画像や名前の上で少し待ち、ハイライトされてから離すと、その中に移動できます。メニューの「移動先を選択…」から移動先を選ぶこともできます。\n\n名前などでの並べ替えは表示順と再生順のみを変更し、カスタム順は上書きしません。「カスタム」に戻すと再びドラッグできます。\n\n順番に再生すると、各階層の順序に沿ってサブプレイリストに入り、再生後に親プレイリストへ戻ります。カスタム順では Alt + ↑ / ↓ で順序を変更し、Shift + F10 でメニューを開けます。',
    '사용자 지정 정렬: 곡이나 하위 재생목록 오른쪽의 점 3개를 끌면 다른 행이 부드럽게 자리를 비웁니다. 점을 클릭하거나 행을 오른쪽 클릭 또는 길게 눌러 메뉴를 열 수 있습니다.\n\n하위 재생목록의 커버나 이름 위에서 잠시 기다린 후 강조 표시되면 놓아 안으로 이동하세요. 메뉴의 “다음으로 이동…”에서 위치를 선택할 수도 있습니다.\n\n이름 등 다른 기준으로 정렬하면 표시 및 재생 순서만 바뀌며 사용자 지정 순서는 유지됩니다. 다시 끌려면 “사용자 지정”으로 전환하세요.\n\n순서대로 재생할 때는 각 계층의 순서에 따라 하위 재생목록에 들어갔다가 재생을 마치면 상위 목록으로 돌아옵니다. 사용자 지정 모드에서 Alt + ↑ / ↓로 순서를 바꾸고 Shift + F10으로 메뉴를 여세요.',
  ],
  '知道了': ['Got it', '了解', '확인'],
  '歌单已重新读取': ['Playlists reloaded', 'プレイリストを再読み込みしました', '재생목록을 다시 읽었습니다'],
  '重试保存': ['Retry saving', '保存を再試行', '저장 다시 시도'],
  '重新读取': ['Reload', '再読み込み', '다시 읽기'],
  '歌单更改尚未保存；当前会话仍保留更改。\n{0}': [
    'Playlist changes are not saved; they are retained for this session.\n{0}',
    'プレイリストの変更は未保存です。現在のセッションでは保持されています。\n{0}',
    '재생목록 변경 사항을 저장하지 못했지만 현재 세션에는 유지됩니다.\n{0}',
  ],
  '{0} 个顶层歌单 · {1} 首歌曲引用': [
    '{0} top-level playlists · {1} track references',
    '最上位のプレイリスト {0} 個 · 楽曲の参照 {1} 件',
    '최상위 재생목록 {0}개 · 곡 참조 {1}개'
  ],
  '歌单': ['Playlists', 'プレイリスト', '재생목록'],
  '这里还没有项目。可以新建子歌单、添加歌曲或拖入歌单。': [
    'No items yet. Create a nested playlist, add tracks, or drag in a playlist.',
    'まだ項目がありません。サブプレイリストの作成、曲の追加、プレイリストのドラッグで追加できます。',
    '아직 항목이 없습니다. 하위 재생목록을 만들거나 곡을 추가하거나 재생목록을 끌어오세요.'
  ],
  '不可用的项目': ['Unavailable item', '利用できない項目', '사용할 수 없는 항목'],
  '{0}的歌单封面': ['Playlist cover for {0}', '{0} のプレイリストカバー', '{0}의 재생목록 커버'],
  '选择歌单封面': ['Choose playlist cover', 'プレイリストのカバー画像を選択', '재생목록 커버 선택'],
  '请输入歌单名称': ['Enter a playlist name', 'プレイリスト名を入力してください', '재생목록 이름을 입력하세요'],
  '无法打开图片选择器，请稍后重试': [
    'Could not open the image picker. Please try again later.',
    '画像選択画面を開けませんでした。しばらくしてから再試行してください。',
    '이미지 선택기를 열지 못했습니다. 잠시 후 다시 시도하세요.'
  ],
  '歌单名称': ['Playlist name', 'プレイリスト名', '재생목록 이름'],
  '选择封面': ['Choose cover', 'カバー画像を選択', '커버 선택'],
  '更换封面': ['Change cover', 'カバー画像を変更', '커버 변경'],
  '移除自定义封面': ['Remove custom cover', 'カスタムカバー画像を削除', '사용자 지정 커버 제거'],
  '选择歌曲（{0} 首）': ['Select tracks ({0})', '曲を選択（{0} 曲）', '곡 선택 ({0}곡)'],
  '封面和歌曲可稍后添加；歌单中也可以继续创建子歌单。': [
    'You can add a cover and tracks later, and create nested playlists inside this playlist.',
    'カバー画像や曲は後から追加できます。プレイリスト内にサブプレイリストを作成することもできます。',
    '커버와 곡은 나중에 추가할 수 있으며 재생목록 안에 하위 재생목록도 만들 수 있습니다.'
  ],
  '创建': ['Create', '作成', '만들기'],
  '选择目标歌单': ['Choose destination playlist', '移動先のプレイリストを選択', '대상 재생목록 선택'],
  '移动': ['Move', '移動', '이동'],
  '在“{0}”下新建子歌单': [
    'Create nested playlist in “{0}”',
    '「{0}」内にサブプレイリストを作成',
    '“{0}” 안에 하위 재생목록 만들기'
  ],
  '新歌单尚未保存：{0}': [
    'New playlist has not been saved: {0}',
    '新しいプレイリストは未保存です：{0}',
    '새 재생목록을 아직 저장하지 못했습니다: {0}'
  ],
  '无法创建歌单：{0}': [
    'Could not create playlist: {0}',
    'プレイリストを作成できませんでした：{0}',
    '재생목록을 만들지 못했습니다: {0}'
  ],
  '全部歌单（顶层）': ['All playlists (top level)', 'すべてのプレイリスト（最上位）', '모든 재생목록 (최상위)'],
  '歌单数据读取失败，已保护原文件。请到歌单页面修复后重新读取。': [
    'Could not read playlist data. The original file is protected. Repair it and reload from the Playlists page.',
    'プレイリストのデータを読み込めませんでした。元のファイルは保護されています。プレイリストページで修復後、再読み込みしてください。',
    '재생목록 데이터를 읽지 못했습니다. 원본 파일은 보호되었습니다. 재생목록 페이지에서 복구한 후 다시 읽어 주세요.'
  ],
  '还没有歌单，请先新建一个。': [
    'No playlists yet. Create one first.',
    'プレイリストがありません。まず新しく作成してください。',
    '아직 재생목록이 없습니다. 먼저 만들어 주세요.'
  ],
  '歌单数据尚未完整读取，无法添加歌曲；请到歌单页面重新读取。': [
    'Tracks cannot be added until playlist data is fully loaded. Reload it from the Playlists page.',
    'プレイリストのデータ読み込みが未完了のため、曲を追加できません。プレイリストページで再読み込みしてください。',
    '재생목록 데이터를 완전히 읽지 못해 곡을 추가할 수 없습니다. 재생목록 페이지에서 다시 읽어 주세요.'
  ],
  '加入歌单': ['Add to playlist', 'プレイリストに追加', '재생목록에 추가'],
  '将 {0} 首歌曲加入歌单': [
    'Add {0} tracks to a playlist',
    '{0} 曲をプレイリストに追加',
    '{0}곡을 재생목록에 추가'
  ],
  '添加': ['Add', '追加', '추가'],
  '所选歌曲已在“{0}”中': [
    'Selected tracks are already in “{0}”',
    '選択した曲はすでに「{0}」にあります',
    '선택한 곡은 이미 “{0}”에 있습니다'
  ],
  '已将 {0} 首歌曲加入“{1}”': [
    'Added {0} tracks to “{1}”',
    '{0} 曲を「{1}」に追加しました',
    '{0}곡을 “{1}”에 추가했습니다'
  ],
  '更改已保留在当前会话，但保存失败：{0}': [
    'Changes are kept for this session, but saving failed: {0}',
    '変更は現在のセッションに保持されていますが、保存に失敗しました：{0}',
    '변경 사항은 현재 세션에 유지되지만 저장하지 못했습니다: {0}'
  ],
  '加入歌单失败：{0}': [
    'Could not add to playlist: {0}',
    'プレイリストに追加できませんでした：{0}',
    '재생목록에 추가하지 못했습니다: {0}'
  ],
  '稍作停留移入': ['Hover briefly to move inside', '少し待つと中に移動できます', '잠시 머물러 안으로 이동'],
  '从总乐库添加歌曲': ['Add tracks from library', 'ライブラリから曲を追加', '전체 보관함에서 곡 추가'],
  '搜索标题、歌手或专辑': [
    'Search title, artist or album',
    'タイトル・アーティスト・アルバムを検索',
    '제목, 아티스트 또는 앨범 검색'
  ],
  '仅编辑本层歌曲；子歌单及仍选歌曲的混排位置会保留。': [
    'Edit only tracks at this level. Nested playlists and tracks that remain selected keep their interleaved positions.',
    'この階層の曲のみを編集します。サブプレイリストと選択を維持した曲の混在順序は保たれます。',
    '현재 단계의 곡만 편집합니다. 하위 재생목록과 계속 선택된 곡의 혼합 배치 위치는 유지됩니다.'
  ],
  '总乐库为空；先添加本地音乐或收藏联网搜索结果。': [
    'The library is empty. Add local music or save online search results first.',
    'ライブラリが空です。ローカル音楽を追加するか、オンライン検索結果を保存してください。',
    '전체 보관함이 비어 있습니다. 먼저 로컬 음악을 추가하거나 온라인 검색 결과를 보관함에 저장하세요.'
  ],
  '没有匹配歌曲': ['No matching tracks', '一致する曲がありません', '일치하는 곡 없음'],
  '已在当前歌单中': ['Already in this playlist', '現在のプレイリストに追加済み', '이미 현재 재생목록에 있음'],
  '总乐库暂未收录，保留歌曲引用': [
    'Not currently in the library; track reference retained',
    '現在ライブラリにはありませんが、楽曲の参照は保持します',
    '현재 전체 보관함에 없지만 곡 참조는 유지됩니다'
  ],
  '保存选择（{0} 首）': [
    'Save selection ({0} tracks)',
    '選択を保存（{0} 曲）',
    '선택 저장 ({0}곡)'
  ],
  '添加 {0} 首': ['Add {0} tracks', '{0} 曲を追加', '{0}곡 추가'],
  '自定义': ['Custom', 'カスタム', '사용자 지정'],
  '歌曲数量': ['Track count', '曲数', '곡 수'],
  '名称升序': ['Name, ascending', '名前の昇順', '이름 오름차순'],
  '名称降序': ['Name, descending', '名前の降順', '이름 내림차순'],
  '最新添加': ['Recently added', '追加が新しい順', '최근 추가순'],
  '最近修改': ['Recently modified', '更新が新しい順', '최근 수정순'],
  '最早添加': ['Oldest added', '追加が古い順', '오래된 추가순'],
  '最早修改': ['Oldest modified', '更新が古い順', '오래된 수정순'],
  '歌曲数量升序': ['Track count, ascending', '曲数の昇順', '곡 수 오름차순'],
  '播放全部': ['Play all', 'すべて再生', '모두 재생'],
  '专辑 · {0}': ['Album · {0}', 'アルバム · {0}', '앨범 · {0}'],
  '操作说明': ['How to use', '操作ガイド', '사용 방법'],
  '添加歌曲或子歌单': [
    'Add tracks or nested playlists',
    '曲やサブプレイリストを追加',
    '곡 또는 하위 재생목록 추가'
  ],
  '添加歌曲': ['Add tracks', '曲を追加', '곡 추가'],
  '原始顺序': ['Original order', '元の順序', '원래 순서'],
  '歌单信息': ['Playlist information', 'プレイリスト情報', '재생목록 정보'],
  '自定义顺序支持歌曲与子歌单混排。其他排序不覆盖自定义顺序。': [
    'Custom order lets you mix tracks and nested playlists. Other sort orders do not overwrite it.',
    'カスタム順では曲とサブプレイリストを混在させて並べられます。他の並べ替えでカスタム順が上書きされることはありません。',
    '사용자 지정 순서에서는 곡과 하위 재생목록을 섞어 배치할 수 있습니다. 다른 정렬은 사용자 지정 순서를 덮어쓰지 않습니다.'
  ],
  '子歌单没有歌曲专属字段，保留原次序并排在最后。': [
    'Nested playlists have no track-specific fields, so they keep their order and appear last.',
    'サブプレイリストには曲固有の項目がないため、元の順序を保って末尾に表示されます。',
    '하위 재생목록에는 곡 전용 필드가 없으므로 기존 순서를 유지하며 마지막에 표시됩니다.'
  ],
  '切换列表视图': ['Switch to list view', 'リスト表示に切り替え', '목록 보기로 전환'],
  '切换网格视图': ['Switch to grid view', 'グリッド表示に切り替え', '그리드 보기로 전환'],
  '更多': ['More', 'その他', '더 보기'],
  '移除所选（{0}）': ['Remove selected ({0})', '選択項目を削除（{0}）', '선택 항목 제거 ({0})'],
  '全选当前层': ['Select all at this level', 'この階層をすべて選択', '현재 단계 모두 선택'],
  '退出多选': ['Exit multi-select', '複数選択を終了', '다중 선택 종료'],
  'Do Re Mi Fa Sol La Si 实时频谱': [
    'Do Re Mi Fa Sol La Si live spectrum',
    'ド レ ミ ファ ソ ラ シのリアルタイムスペクトラム',
    '도 레 미 파 솔 라 시 실시간 스펙트럼'
  ],
  '歌曲实时七音频谱': [
    'Live seven-note spectrum',
    '楽曲の7音リアルタイムスペクトラム',
    '곡의 실시간 7음계 스펙트럼'
  ],
  '音乐': ['Music', '音楽', '음악'],
  '分类': ['Categories', 'カテゴリー', '분류'],
  '文件夹': ['Folders', 'フォルダー', '폴더'],
  '统计': ['Statistics', '統計', '통계'],
  '设置': ['Settings', '設定', '설정'],
  '侧栏宽度保存失败；本次会话仍保留当前宽度': [
    'Could not save sidebar width; the current width is kept for this session',
    'サイドバーの幅を保存できませんでした。現在のセッションではこの幅を維持します',
    '사이드바 너비를 저장하지 못했습니다. 현재 세션에서는 이 너비가 유지됩니다'
  ],
  '侧栏宽度已锁定': [
    'Sidebar width is locked',
    'サイドバーの幅は固定されています',
    '사이드바 너비가 잠겨 있습니다'
  ],
  '拖动调整侧栏宽度': ['Drag to resize sidebar', 'ドラッグでサイドバーの幅を調整', '끌어서 사이드바 너비 조절'],
  '评论关联保存失败：{0}': [
    'Could not save comment link: {0}',
    'コメントの関連付けを保存できませんでした：{0}',
    '댓글 연결을 저장하지 못했습니다: {0}'
  ],
  '评论加载失败，请检查网络后重试。': [
    'Could not load comments. Check your connection and try again.',
    'コメントを読み込めませんでした。ネットワークを確認して再試行してください。',
    '댓글을 불러오지 못했습니다. 네트워크를 확인한 후 다시 시도하세요.'
  ],
  '歌曲评论': ['Track comments', '楽曲のコメント', '곡 댓글'],
  '关闭评论': ['Close comments', 'コメントを閉じる', '댓글 닫기'],
  '只按你确认的平台歌曲 ID 关联，不会仅凭同名歌曲自动猜测。': [
    'Comments are linked only by the platform track ID you confirm, never guessed from matching titles.',
    '確認した配信元の楽曲IDのみで関連付けます。同名の曲から自動で推測することはありません。',
    '확인한 플랫폼 곡 ID로만 연결하며 같은 제목만으로 자동 추측하지 않습니다.'
  ],
  '来源：{0} · 只读 · 按平台歌曲 ID 精确匹配': [
    'Source: {0} · Read-only · Exact platform track ID match',
    '提供元：{0} · 読み取り専用 · 配信元の楽曲IDで完全一致',
    '출처: {0} · 읽기 전용 · 플랫폼 곡 ID로 정확히 일치'
  ],
  '评论由平台用户发表；不加载头像、图片或音频。': [
    'Comments are posted by platform users. Avatars, images and audio are not loaded.',
    'コメントは配信元のユーザーが投稿したものです。アバター・画像・音声は読み込みません。',
    '댓글은 플랫폼 사용자가 작성합니다. 프로필 사진, 이미지, 오디오는 불러오지 않습니다.'
  ],
  '已显示 {0} 条{1}': [
    'Showing {0} comments{1}',
    '{0} 件のコメントを表示中{1}',
    '댓글 {0}개 표시 중{1}'
  ],
  '评论来源：尚未关联': ['Comment source: not linked', 'コメント提供元：未設定', '댓글 출처: 연결되지 않음'],
  '评论来源：{0}{1}': ['Comment source: {0}{1}', 'コメント提供元：{0}{1}', '댓글 출처: {0}{1}'],
};
