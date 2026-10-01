const Map<String, List<String>> catalogOfflineTools = {
  '练习这一句': ['Practice this line', 'この行を練習', '이 구절 연습'],
  '这句歌词没有至少 1 秒的有效时间范围': [
    'This lyric line has no valid time range of at least 1 second',
    'この歌詞行には1秒以上の有効な時間範囲がありません',
    '이 가사 구절에 1초 이상의 유효한 시간 범위가 없습니다'
  ],
  '已将这一句设为 A-B 练习范围': [
    'This line is now the A-B practice range',
    'この行をA-B練習範囲に設定しました',
    '이 구절을 A-B 연습 구간으로 설정했습니다'
  ],
  '导出队列为 M3U8': ['Export queue as M3U8', 'キューをM3U8に書き出す', '대기열을 M3U8로 내보내기'],
  '导出搜索结果为 M3U8': [
    'Export search results as M3U8',
    '検索結果をM3U8に書き出す',
    '검색 결과를 M3U8로 내보내기'
  ],
  '导出队列或搜索结果': [
    'Export queue or search results',
    'キューまたは検索結果を書き出す',
    '대기열 또는 검색 결과 내보내기'
  ],
  '导出歌词卡片': ['Export lyric card', '歌詞カードを書き出す', '가사 카드 내보내기'],
  '选择最多 4 句歌词；卡片保留所选文字与换行。': [
    'Choose up to 4 lyric lines. The card preserves their text and line breaks.',
    '歌詞を最大4行選んでください。選んだ文字と改行をカードに保ちます。',
    '가사를 최대 4줄 선택하세요. 카드에 선택한 글자와 줄바꿈이 유지됩니다.'
  ],
  '没有可导出的歌词': ['No lyrics to export', '書き出せる歌詞がありません', '내보낼 가사가 없습니다'],
  '显示歌曲信息': ['Show track details', '曲の情報を表示', '곡 정보 표시'],
  '请至少选择一句歌词': [
    'Select at least one lyric line',
    '歌詞を1行以上選んでください',
    '가사를 한 줄 이상 선택하세요'
  ],
  '所选内容过长，无法完整放入卡片。请减少句数或隐藏歌曲信息。': [
    'The selected content is too long to fit in full. Select fewer lines or hide track details.',
    '選んだ内容が長すぎて全て入りません。行数を減らすか曲の情報を非表示にしてください。',
    '선택한 내용이 너무 길어 모두 담을 수 없습니다. 줄 수를 줄이거나 곡 정보를 숨기세요.'
  ],
  '无法保存歌词卡片，请检查位置与访问权限后重试。': [
    'Could not save the lyric card. Check the location and access permissions, then try again.',
    '歌詞カードを保存できません。保存先とアクセス権を確認して再試行してください。',
    '가사 카드를 저장할 수 없습니다. 저장 위치와 접근 권한을 확인한 후 다시 시도하세요.'
  ],
  '歌词卡片已保存': ['Lyric card saved', '歌詞カードを保存しました', '가사 카드가 저장되었습니다'],
  '保存 PNG': ['Save PNG', 'PNGを保存', 'PNG 저장'],
  'TTML 已导入为{0}，原文件未修改。': [
    'TTML imported as {0}. The original file was kept.',
    'TTMLを{0}として読み込みました。元のファイルは変更されません。',
    'TTML을 {0}(으)로 가져왔습니다. 원본 파일은 유지되었습니다.'
  ],
  'TTML 结构无效': ['Invalid TTML structure', 'TTML構造が無効です', 'TTML 구조가 올바르지 않습니다'],
  'TTML 不支持 DTD 或外部实体': [
    'DTDs and external entities are unsupported in TTML',
    'TTMLのDTDと外部実体には対応していません',
    'TTML의 DTD와 외부 엔터티는 지원되지 않습니다'
  ],
  'TTML 节点过多或嵌套过深': [
    'TTML has too many nodes or excessive nesting',
    'TTMLのノード数または入れ子の深さが上限を超えています',
    'TTML 노드 수 또는 중첩 깊이가 한도를 초과했습니다'
  ],
  'TTML 包含无效字符实体': [
    'TTML contains an invalid character entity',
    'TTMLに無効な文字実体が含まれています',
    'TTML에 잘못된 문자 엔터티가 있습니다'
  ],
  'TTML 时间格式或时制不受支持': [
    'Unsupported TTML timing format or time base',
    'TTMLの時刻形式または時間基準に対応していません',
    'TTML 시간 형식 또는 시간 기준은 지원되지 않습니다'
  ],
  'TTML 歌词行需要结束时间': [
    'TTML lyric lines require an end time',
    'TTMLの歌詞行には終了時刻が必要です',
    'TTML 가사 줄에는 종료 시간이 필요합니다'
  ],
  '歌词时间超出范围': [
    'Lyric time is out of range',
    '歌詞の時刻が範囲外です',
    '가사 시간이 허용 범위를 벗어났습니다'
  ],
  'TTML 辅助轨未匹配原文': [
    'A TTML auxiliary track has no matching original line',
    'TTMLの補助トラックに対応する原文がありません',
    'TTML 보조 트랙에 일치하는 원문 줄이 없습니다'
  ],
  'TTML 正文包含不支持的元素': [
    'TTML content contains an unsupported element',
    'TTMLの本文に未対応の要素が含まれています',
    'TTML 본문에 지원되지 않는 요소가 있습니다'
  ],
  '按当前播放数量停止': [
    'Stop after selected track count',
    '指定した再生曲数で停止',
    '지정한 재생 곡 수 후 정지'
  ],
  '按当前队列设置停止目标': [
    'Set queue stop target',
    '現在のキューから停止目標を設定',
    '현재 대기열에서 정지 목표 설정'
  ],
  '首数（包含当前歌曲）': [
    'Track count (including the current track)',
    '曲数（再生中の曲を含む）',
    '곡 수 (현재 곡 포함)'
  ],
  '确认后固定目标歌曲；重排或插入歌曲后仍在该曲结束时停止。': [
    'Confirmation fixes the target track. Reordering or inserting tracks keeps the stop at the end of that track.',
    '確定すると対象の曲を固定します。並べ替えや曲の追加をしても、その曲の終了時に停止します。',
    '확인하면 목표 곡이 고정됩니다. 곡을 재정렬하거나 추가해도 해당 곡이 끝날 때 정지합니다.'
  ],
  '当前队列或歌曲已改变，请重新设置停止目标': [
    'The queue or current track changed. Set the stop target again.',
    'キューまたは再生中の曲が変わりました。停止目標を設定し直してください。',
    '대기열 또는 현재 곡이 변경되었습니다. 정지 목표를 다시 설정하세요.'
  ],
  '制作歌词卡片': ['Create a lyric card', '歌詞カードを作成', '가사 카드 만들기'],
  '没有可制作卡片的歌词': [
    'No lyrics are available for a card',
    'カードにできる歌詞がありません',
    '카드로 만들 가사가 없습니다'
  ],
  '歌曲或歌词已改变，请重新制作卡片': [
    'The track or lyrics changed. Create the card again.',
    '曲または歌詞が変わりました。カードを作成し直してください。',
    '곡 또는 가사가 변경되었습니다. 카드를 다시 만드세요.'
  ],
  '制作歌词卡片失败：{0}': [
    'Could not create the lyric card: {0}',
    '歌詞カードを作成できませんでした：{0}',
    '가사 카드를 만들지 못했습니다: {0}'
  ],
  '支持本地 TTML 行与逐字歌词；译文和注音按文件中的明确角色读取。': [
    'Supports local line and word-synced TTML lyrics. Translation and romanization follow explicit roles in the file.',
    'ローカルの行・単語同期TTML歌詞に対応します。訳文と読みはファイル内の明示された役割に従って読み込みます。',
    '로컬 줄 및 단어 단위 TTML 가사를 지원합니다. 번역과 발음은 파일에 명시된 역할에 따라 읽습니다.'
  ],
};
