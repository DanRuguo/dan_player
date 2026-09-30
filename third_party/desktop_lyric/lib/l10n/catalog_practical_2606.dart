// Practical playback, reading and listening-history controls.
const catalogPractical2606 = <String, List<String>>{
  '隐藏子歌单歌曲数量': [
    'Hide subplaylist track counts',
    '子プレイリストの曲数を非表示',
    '하위 재생목록 곡 수 숨기기'
  ],
  '显示子歌单歌曲数量': [
    'Show subplaylist track counts',
    '子プレイリストの曲数を表示',
    '하위 재생목록 곡 수 표시'
  ],
  '{0} 个直接项目 · {1} 首歌曲': [
    '{0} direct items · {1} tracks',
    '{0}個の直接項目 · {1}曲',
    '직접 항목 {0}개 · {1}곡'
  ],
  '{0} · {1} 首歌曲': ['{0} · {1} tracks', '{0} · {1}曲', '{0} · {1}곡'],
  '树状': ['Tree', 'ツリー', '트리'],
  '点击歌单或箭头展开、折叠；单击歌曲播放。同一歌单的歌曲按窗口宽度紧凑排列。\n\n右键、长按或 Shift + F10 打开项目菜单；自定义排序下按住卡片拖动，可调整顺序或移入歌单。\n\n方向键浏览层级，Home / End 跳到首尾；搜索保留所属歌单，清除搜索恢复展开状态。':
      [
    'Click a playlist or arrow to expand or collapse it; click a track to play. Tracks in the same playlist form a compact layout that adapts to the window.\n\nRight-click, long-press or press Shift + F10 for actions. In custom order, hold and drag a card to reorder it or move it into a playlist.\n\nUse arrow keys to browse and Home / End to jump. Search retains parent playlists; clearing it restores expansion.',
    'プレイリストや矢印をクリックして展開・折りたたみ、曲をクリックして再生します。同じプレイリストの曲はウィンドウ幅に合わせて並びます。\n\n右クリック・長押し・Shift + F10 でメニューを開きます。カスタム順ではカードを押したままドラッグして並べ替えや移動ができます。\n\n方向キーで移動し、Home / End で先頭・末尾へ移動します。検索では親の階層を保持し、解除すると展開状態を戻します。',
    '재생목록이나 화살표를 클릭하여 펼치거나 접고, 곡을 클릭하여 재생합니다. 같은 재생목록의 곡은 창 너비에 맞춰 배치됩니다.\n\n우클릭, 길게 누르기 또는 Shift + F10으로 메뉴를 엽니다. 사용자 지정 순서에서는 카드를 누른 채 끌어 순서를 바꾸거나 재생목록으로 이동할 수 있습니다.\n\n방향키로 탐색하고 Home / End로 처음과 끝으로 이동합니다. 검색은 상위 재생목록을 유지하며, 검색을 지우면 펼침 상태를 복원합니다.'
  ],
  '展开全部': ['Expand all', 'すべて展開', '모두 펼치기'],
  '折叠全部': ['Collapse all', 'すべて折りたたむ', '모두 접기'],
  '{0} 项 · {1} 首': ['{0} items · {1} tracks', '{0}項目 · {1}曲', '{0}개 항목 · {1}곡'],
  '树状歌单': ['Playlist tree', 'ツリー表示', '트리형 재생목록'],
  '搜索树状歌单': ['Search playlist tree', 'プレイリストや曲を検索', '재생목록 트리 검색'],
  '展开全部歌单': ['Expand all playlists', 'すべて展開', '모든 재생목록 펼치기'],
  '折叠全部歌单': ['Collapse all playlists', 'すべて折りたたむ', '모든 재생목록 접기'],
  '展开歌单': ['Expand playlist', 'プレイリストを展開', '재생목록 펼치기'],
  '折叠歌单': ['Collapse playlist', 'プレイリストを折りたたむ', '재생목록 접기'],
  '定位正在播放': ['Reveal playing track', '再生中の曲を表示', '재생 중인 곡 찾기'],
  '没有匹配的歌单或歌曲': [
    'No matching playlists or tracks',
    '一致するプレイリストや曲がありません',
    '일치하는 재생목록이나 곡이 없습니다'
  ],
  '当前歌曲不在此歌单树中': [
    'The playing track is not in this playlist tree',
    '再生中の曲はこのツリーにありません',
    '재생 중인 곡이 이 트리에 없습니다'
  ],
  '分钟': ['Minutes', '分', '분'],
  '{0} 小时': ['{0} hours', '{0}時間', '{0}시간'],
  '取消倒计时': ['Cancel timer', 'タイマーを取り消す', '타이머 취소'],
  '有收听记录的小时数，不等同于收听时长。': [
    'Hours with listening activity, not the total listening duration.',
    '再生記録のある時間枠の数です。再生時間の合計とは異なります。',
    '청취 기록이 있는 시간대 수이며 총 청취 시간과는 다릅니다.'
  ],
  '显示歌词译文': ['Show translations', '歌詞の翻訳を表示', '가사 번역 표시'],
  '显示歌词注音': ['Show pronunciation', '歌詞の読みを表示', '가사 발음 표시'],
  '显示歌词时间': ['Show lyric timestamps', '歌詞の時刻を表示', '가사 시간 표시'],
  '手动阅读歌词': ['Read lyrics manually', '歌詞を手動で読む', '가사 수동 읽기'],
  '回到当前歌词': ['Return to current line', '現在の歌詞に戻る', '현재 가사로 돌아가기'],
  '恢复歌词字号': ['Reset lyric text size', '歌詞の文字サイズを戻す', '가사 글자 크기 초기화'],
  '精确歌词字号': ['Set exact lyric text size', '歌詞の文字サイズを数値で指定', '정확한 가사 글자 크기 설정'],
  '字号设为 {0}': ['Set text size to {0}', '文字サイズを{0}に設定', '글자 크기를 {0}(으)로 설정'],
  '复制完整显示歌词': ['Copy all visible lyric text', '表示中の歌詞全文をコピー', '표시 중인 가사 전체 복사'],
  '歌词阅读工具': ['Lyric reading tools', '歌詞の読み方', '가사 읽기 도구'],
  '复制这一句歌词': ['Copy this lyric line', 'この歌詞をコピー', '이 가사 줄 복사'],
  '复制歌词与时间': ['Copy lyric with timestamp', '時刻付きで歌詞をコピー', '시간과 가사 복사'],
  '没有可复制的歌词': ['No lyrics to copy', 'コピーできる歌詞がありません', '복사할 가사가 없습니다'],
  '已复制歌词': ['Lyrics copied', '歌詞をコピーしました', '가사를 복사했습니다'],
  '复制歌词失败：{0}': [
    'Could not copy lyrics: {0}',
    '歌詞をコピーできません：{0}',
    '가사를 복사하지 못했습니다: {0}'
  ],
  '显示剩余时间': ['Show remaining time', '残り時間を表示', '남은 시간 표시'],
  '显示总时长': ['Show total duration', '総時間を表示', '전체 길이 표시'],
  '剩余 {0}': ['{0} remaining', '残り {0}', '{0} 남음'],
  '撤销进度跳转': ['Undo seek', '再生位置の移動を取り消す', '재생 위치 이동 취소'],
  '复制播放时间': ['Copy playback position', '再生時刻をコピー', '재생 시간 복사'],
  '已复制播放时间': ['Playback position copied', '再生時刻をコピーしました', '재생 시간을 복사했습니다'],
  '复制播放时间失败：{0}': [
    'Could not copy playback position: {0}',
    '再生時刻をコピーできません：{0}',
    '재생 시간을 복사하지 못했습니다: {0}'
  ],
  '进度快捷键：←/→ 5 秒，Shift+←/→ 1 秒，Home/End 首尾，0–9 百分比': [
    'Seek: ←/→ 5s; Shift+←/→ 1s; Home/End start/end; 0–9 percentage',
    '移動：←/→ 5秒、Shift+←/→ 1秒、Home/End 先頭/末尾、0–9 割合',
    '이동: ←/→ 5초, Shift+←/→ 1초, Home/End 처음/끝, 0–9 비율'
  ],
  '向前 {0}': ['Forward {0}', '{0} 先へ', '{0} 앞으로'],
  '向后 {0}': ['Back {0}', '{0} 前へ', '{0} 뒤로'],
  '播放书签：{0}': ['Playback bookmark: {0}', '再生ブックマーク：{0}', '재생 북마크: {0}'],
  'A-B 循环：{0} – {1}': [
    'A-B repeat: {0} – {1}',
    'A-B リピート：{0} – {1}',
    'A-B 반복: {0} – {1}'
  ],
  '自定义睡眠定时': ['Custom sleep timer', 'スリープ時間を指定', '사용자 지정 수면 타이머'],
  '倒计时结束后播完本曲': [
    'Finish this song when the timer ends',
    '時間になったら曲の最後で停止',
    '타이머 종료 시 현재 곡을 마저 재생'
  ],
  '延长 5 分钟': ['Add 5 minutes', '5分延長', '5분 연장'],
  '缩短 5 分钟': ['Subtract 5 minutes', '5分短縮', '5분 단축'],
  '继续倒计时': ['Resume timer', 'タイマーを再開', '타이머 계속'],
  '暂停倒计时': ['Pause timer', 'タイマーを一時停止', '타이머 일시 정지'],
  '倒计时已暂停 {0}': ['Timer paused · {0}', 'タイマー停止中 · {0}', '타이머 일시 정지 · {0}'],
  '睡眠定时已到，将播完当前歌曲后停止': [
    'Sleep timer ended; stopping after this song',
    'スリープ時間になりました。この曲の最後で停止します',
    '수면 타이머가 끝났습니다. 현재 곡이 끝나면 정지합니다'
  ],
  '睡眠定时已到，播放已暂停': [
    'Sleep timer ended; playback paused',
    'スリープ時間になり、再生を一時停止しました',
    '수면 타이머가 끝나 재생을 일시 정지했습니다'
  ],
  '请输入 {0} 到 {1} 之间的整数': [
    'Enter a whole number from {0} to {1}',
    '{0}〜{1}の整数を入力してください',
    '{0}에서 {1} 사이의 정수를 입력하세요'
  ],
  '精确音量': ['Set exact volume', '音量を数値で指定', '정확한 음량 설정'],
  '音量百分比': ['Volume percentage', '音量（%）', '음량 비율'],
  '恢复音量': ['Restore volume', '音量を戻す', '음량 복원'],
  '音量设为 {0}%': ['Set volume to {0}%', '音量を{0}%に設定', '음량을 {0}%로 설정'],
  '一年按日历周年计算，包含实际的2月29日；有收听记录的周计为活跃周。': [
    'A year follows the calendar anniversary and includes February 29 when present. A week with listening counts as active.',
    '1年は暦の同日を基準にし、該当する2月29日も含みます。再生記録のある週を活動週とします。',
    '1년은 달력의 같은 날짜를 기준으로 하며 해당 기간의 2월 29일을 포함합니다. 청취 기록이 있는 주를 활동 주로 셉니다.'
  ],
  '最近24小时的真实记录；恢复播放不重复计次。': [
    'Actual records from the last 24 hours; resuming does not add a play.',
    '直近24時間の実際の記録です。一時停止からの再開は回数に加算しません。',
    '최근 24시간의 실제 기록입니다. 일시 정지 후 재개는 재생 횟수를 늘리지 않습니다.'
  ],
  '旧记录只有每日合计，不能还原最近24小时；新的播放将开始精确记录。': [
    'Older daily totals cannot reconstruct the last 24 hours. New playback will be recorded precisely.',
    '以前の記録は日別合計のみで、直近24時間を復元できません。今後の再生から正確に記録します。',
    '이전 기록은 일별 합계뿐이므로 최근 24시간을 복원할 수 없습니다. 새 재생부터 정확히 기록합니다.'
  ],
  '精确记录始于 {0}，此前的小时数据未知；≥ 表示已记录的部分。': [
    'Precise recording began at {0}. Earlier hourly data is unknown; ≥ marks the recorded portion.',
    '正確な記録は{0}からです。それ以前の時間別データは不明で、≥は記録済みの部分を示します。',
    '정확한 기록은 {0}부터입니다. 이전 시간별 자료는 알 수 없으며 ≥는 기록된 부분을 뜻합니다.'
  ],
  '日均收听': ['Daily average', '1日平均', '일 평균'],
  '连续活跃': ['Current streak', '連続日数', '연속 활동'],
  '最长连续': ['Longest streak', '最長連続', '최장 연속'],
  '最常听的星期': ['Favorite weekday', 'よく聴く曜日', '선호 요일'],
  '周末收听占比': ['Weekend share', '週末の割合', '주말 비중'],
  '最投入的一天 · {0} · {1}': [
    'Best day · {0} · {1}',
    '最多の日 · {0} · {1}',
    '가장 많이 들은 날 · {0} · {1}'
  ],
  '洞察按所选范围的已保存时长计算；今天尚未收听时，连续天数截至昨天。': [
    'Insights use saved listening time in this range. If you have not listened today, the current streak ends yesterday.',
    '選択範囲の保存済み再生時間で計算します。今日はまだ聴いていない場合、連続日数は昨日までです。',
    '선택한 범위의 저장된 청취 시간으로 계산합니다. 오늘 아직 듣지 않았다면 연속 일수는 어제까지입니다.'
  ],
  '按已明确归属的历史记录汇总；同名专辑按艺术家区分。': [
    'Totals use identified history; albums with the same name are separated by artist.',
    '帰属を確認できる履歴を集計します。同名アルバムはアーティスト別に区別します。',
    '출처가 확인된 기록을 합산합니다. 이름이 같은 앨범은 아티스트별로 구분합니다.'
  ],
  '最近24小时': ['Last 24 hours', '直近24時間', '최근 24시간'],
  '历史时段分布': ['Lifetime hours', '全期間の時間帯', '전체 시간대 분포'],
  '全部历史记录': ['All-time records', '全期間の記録', '전체 기록'],
  '每根柱表示最近24小时内一个小时的收听时长；日期和时刻随展示快照固定。': [
    'Each bar shows an hour of listening in the last 24 hours. Dates and times stay fixed for this view.',
    '各棒は直近24時間のうち1時間の再生時間です。表示中は日付と時刻が固定されます。',
    '각 막대는 최근 24시간 중 1시간의 청취량을 나타냅니다. 이 화면의 날짜와 시각은 고정됩니다.'
  ],
  '{0} 周': ['{0} weeks', '{0}週', '{0}주'],
};
