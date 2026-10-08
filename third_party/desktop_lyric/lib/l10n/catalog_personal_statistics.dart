const catalogPersonalStatistics = <String, List<String>>{
  '已合并 {0} 条重复记录。': [
    '{0} duplicate records merged.',
    '重複する {0} 件の記録を統合しました。',
    '중복 기록 {0}개를 병합했습니다.'
  ],
  '使用次数：{0}': ['Usage count: {0}', '使用回数：{0}', '사용 횟수: {0}'],
  '右键点击或长按查看使用次数': [
    'Right-click or hold to view usage count',
    '右クリックまたは長押しで使用回数を表示',
    '오른쪽 클릭하거나 길게 눌러 사용 횟수 보기'
  ],
  '添加标签时可点击常用标签气泡填入名称；右键或长按只显示使用次数。': [
    'When adding a tag, click a frequently used tag bubble to fill its name. Right-click or hold to view its usage count.',
    'タグの追加時によく使うタグの吹き出しをクリックすると、名前を入力できます。右クリックまたは長押しでは使用回数のみ表示します。',
    '태그를 추가할 때 자주 사용하는 태그 말풍선을 누르면 이름이 입력됩니다. 오른쪽 클릭하거나 길게 누르면 사용 횟수만 표시됩니다.'
  ],
  '“个人标注”可切换评级或标签：评级只统计有效星级；标签按逐歌使用次数统计，显示前五名，其余合并为“其他标签”。需要最新数据时使用页头刷新。': [
    'Personal annotations switches between ratings and tags. Ratings include valid stars only. Tags count assignments per track, with the top five shown and the rest grouped as Other tags. Use the page refresh for current data.',
    '「個人の注釈」で評価とタグを切り替えます。評価は有効な星数のみ、タグは曲ごとの付与数で集計し、上位 5 個以外は「その他のタグ」にまとめます。最新データにはページ上部の更新を使ってください。',
    '개인 주석에서 평점과 태그를 전환합니다. 평점은 유효한 별점만 집계합니다. 태그는 곡별 부여 횟수로 집계하며 상위 5개 외에는 기타 태그로 합칩니다. 최신 데이터는 페이지 위쪽에서 새로 고침하세요.'
  ],
  '个人标注': ['Personal annotations', '個人の注釈', '개인 주석'],
  '标注分组': ['Annotation group', '注釈の分類', '주석 분류'],
  '评级': ['Ratings', '評価', '평점'],
  '个人标注统计尚未就绪': [
    'Personal annotation statistics are not ready yet',
    '個人の注釈の統計はまだ準備できていません',
    '개인 주석 통계가 아직 준비되지 않았습니다'
  ],
  '暂时无法读取个人标注，请刷新重试。': [
    'Could not read personal annotations. Refresh to retry.',
    '個人の注釈を読み取れませんでした。更新して再試行してください。',
    '개인 주석을 읽지 못했습니다. 새로 고침하여 다시 시도하세요.'
  ],
  '已评级歌曲': ['Rated tracks', '評価済みの曲', '평점을 매긴 곡'],
  '个评级': ['Ratings', '件の評価', '평점 수'],
  '1 个评级': ['1 rating', '1 件の評価', '평점 1개'],
  '{0} 个评级': ['{0} ratings', '{0} 件の評価', '평점 {0}개'],
  '{0} 星': ['{0}-star', '星 {0}', '별 {0}개'],
  '1 首': ['1 song', '1 曲', '1곡'],
  '1 次标注': ['1 assignment', '1 件の付与', '부여 1회'],
  '按已评级歌曲计算比例；未评级歌曲不参与。': [
    'Shares are calculated from rated tracks; unrated tracks are excluded.',
    '評価済みの曲を基準に割合を計算します。未評価の曲は含みません。',
    '평점을 매긴 곡을 기준으로 비율을 계산합니다. 평점이 없는 곡은 제외합니다.'
  ],
  '暂无评级': ['No ratings yet', '評価はまだありません', '아직 평점이 없습니다'],
  '标签附着次数': ['Tag assignments', 'タグの付与数', '태그 부여 횟수'],
  '个标签': ['Tags', '個のタグ', '태그 수'],
  '1 次标签标注': ['1 tag assignment', '1 件のタグ付与', '태그 부여 1회'],
  '{0} 次标签标注': ['{0} tag assignments', '{0} 件のタグ付与', '태그 부여 {0}회'],
  '{0} 次标注': ['{0} assignments', '{0} 件の付与', '부여 {0}회'],
  '其他标签': ['Other tags', 'その他のタグ', '기타 태그'],
  '其他 {0} 个标签': ['{0} other tags', 'その他の {0} 個のタグ', '기타 태그 {0}개'],
  '按逐歌标签附着次数计算；一首歌可有多个标签，次数不等于歌曲总数。': [
    'Shares use tag assignments per track. A track can have several tags, so assignments are not the track total.',
    '曲ごとのタグ付与数を基準に計算します。1 曲に複数のタグを付けられるため、付与数は曲数と一致しません。',
    '곡별 태그 부여 횟수를 기준으로 계산합니다. 한 곡에 여러 태그가 있을 수 있어 부여 횟수는 곡 수와 다릅니다.'
  ],
  '显示前 5 个标签，其余合并为“其他标签”。': [
    'The top 5 tags are shown; the rest are combined as Other tags.',
    '上位 5 個のタグを表示し、残りは「その他のタグ」にまとめます。',
    '상위 5개 태그를 표시하며 나머지는 기타 태그로 합칩니다.'
  ],
  '暂无标签': ['No tags yet', 'タグはまだありません', '아직 태그가 없습니다'],
  '共 {0} 首歌曲 · {1} 个标注': [
    '{0} tracks · {1} annotations',
    '全 {0} 曲 · {1} 件の注釈',
    '총 {0}곡 · 주석 {1}개'
  ],
};
