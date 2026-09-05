const Map<String, List<String>> catalogQueueTools = {
  '将队列保存为歌单': ['Save queue as playlist', 'キューをプレイリストに保存', '대기열을 재생목록으로 저장'],
  '播放队列 {0}': ['Play queue {0}', '再生キュー {0}', '재생 대기열 {0}'],
  '已保存 {0} 首歌曲到“{1}”': [
    'Saved {0} tracks to “{1}”',
    '「{1}」に {0} 曲を保存しました',
    '“{1}”에 {0}곡 저장됨'
  ],
  '歌单已创建，但保存失败；请在歌单页重试保存': [
    'Playlist created but could not be saved. Retry saving on the playlists page.',
    'プレイリストを作成しましたが保存できませんでした。プレイリスト画面で再試行してください。',
    '재생목록을 만들었으나 저장하지 못했습니다. 재생목록 페이지에서 다시 저장하세요.'
  ],
  '无法保存队列为歌单：{0}': [
    'Could not save queue as playlist: {0}',
    'キューをプレイリストに保存できません：{0}',
    '대기열을 재생목록으로 저장할 수 없습니다: {0}'
  ],
  '定位当前歌曲': ['Locate current track', '再生中の曲へ移動', '현재 곡으로 이동'],
  '仅保留当前歌曲': ['Keep only the current track', '再生中の曲だけ残す', '현재 곡만 유지'],
  '移到下一首': ['Move to play next', '次に再生する位置へ移動', '다음 재생 위치로 이동'],
  '从播放队列移除': ['Remove from play queue', '再生キューから削除', '재생 대기열에서 제거'],
  '正在播放的歌曲保留在队列中': [
    'The current track stays in the queue',
    '再生中の曲はキューに残ります',
    '현재 재생 중인 곡은 대기열에 유지됩니다'
  ],
  'A-B 片段循环': ['A-B repeat', 'A-B リピート', 'A-B 구간 반복'],
  '播放到需要的位置，分别标记 A 和 B；两点至少间隔 1 秒。': [
    'Mark A and B at the desired playback positions, at least one second apart.',
    '再生中に A と B を指定します。間隔は 1 秒以上にしてください。',
    '원하는 재생 위치에서 A와 B를 지정하세요. 두 지점은 1초 이상 떨어져야 합니다.'
  ],
  '请先加载一首本地歌曲，再设置片段循环。': [
    'Load a local track before setting A-B repeat.',
    'ローカルの曲を読み込んでから A-B リピートを設定してください。',
    '로컬 곡을 불러온 후 구간 반복을 설정하세요.'
  ],
  '当前位置：{0}': ['Current position: {0}', '現在位置：{0}', '현재 위치: {0}'],
  '标记 A：{0}': ['Mark A: {0}', 'A を指定：{0}', 'A 지정: {0}'],
  '标记 B：{0}': ['Mark B: {0}', 'B を指定：{0}', 'B 지정: {0}'],
  'B 点必须在 A 点至少 1 秒之后': [
    'B must be at least one second after A',
    'B は A より 1 秒以上後に指定してください',
    'B는 A보다 최소 1초 뒤여야 합니다'
  ],
  '循环播放此片段': ['Repeat this segment', 'この区間を繰り返す', '이 구간 반복'],
  '切换歌曲会清除标记；手动跳到区间外会关闭循环。': [
    'Changing tracks clears the marks. Seeking outside the segment turns repeat off.',
    '曲の切り替えでマークを消去します。区間外へのシークでリピートを解除します。',
    '곡을 바꾸면 지점이 지워집니다. 구간 밖으로 이동하면 반복이 꺼집니다.'
  ],
  '清除标记': ['Clear marks', 'マークを消去', '지점 지우기'],
  '片段循环跳转失败，已关闭循环': [
    'Could not seek within the segment; repeat is now off',
    '区間内にシークできなかったためリピートを解除しました',
    '구간 이동에 실패하여 반복을 껐습니다'
  ],
};
