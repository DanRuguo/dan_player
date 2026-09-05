const Map<String, List<String>> catalogSmartPlaylistDialog = {
  '智能歌单': ['Smart playlists', 'スマートプレイリスト', '스마트 재생목록'],
  '智能歌单预览': ['Smart playlist preview', 'スマートプレイリストのプレビュー', '스마트 재생목록 미리보기'],
  '新建智能歌单': ['New smart playlist', 'スマートプレイリストを作成', '새 스마트 재생목록'],
  '智能歌单名称': ['Smart playlist name', 'スマートプレイリスト名', '스마트 재생목록 이름'],
  '只筛选本地曲库，须满足全部条件；曲库变化会更新预览，已播放的队列保持原顺序。': [
    'Matches local library tracks that meet every condition. Library changes refresh this preview; the playback queue keeps its current order.',
    'ローカルライブラリで全条件を満たす曲が対象です。ライブラリの変更でプレビューは更新されますが、再生キューの順序は変わりません。',
    '로컬 라이브러리에서 모든 조건을 만족하는 곡을 표시합니다. 라이브러리 변경 시 미리보기는 갱신되지만 재생 대기열 순서는 유지됩니다.'
  ],
  '筛选规则': ['Filter rules', '絞り込み条件', '필터 규칙'],
  '关键词（标题、歌手、专辑）': [
    'Keywords (title, artist, album)',
    'キーワード（曲名・アーティスト・アルバム）',
    '검색어 (제목, 아티스트, 앨범)'
  ],
  '歌手包含': ['Artist contains', 'アーティスト名に含む文字', '아티스트 포함'],
  '专辑包含': ['Album contains', 'アルバム名に含む文字', '앨범 포함'],
  '例如 flac, mp3；留空不限': [
    'e.g. flac, mp3; blank means any',
    '例：flac, mp3（空欄はすべて）',
    '예: flac, mp3 (비워두면 모두)'
  ],
  '结果排序': ['Result order', '結果の並び順', '결과 정렬'],
  '最短时长（秒）': ['Minimum duration (seconds)', '最短時間（秒）', '최소 길이 (초)'],
  '最长时长（秒）': ['Maximum duration (seconds)', '最長時間（秒）', '최대 길이 (초)'],
  '最近加入优先': ['Recently added first', '追加日時の新しい順', '최근 추가순'],
  '时长从短到长': ['Duration: shortest first', '再生時間の短い順', '길이 짧은순'],
  '匹配 {0} 首本地歌曲': [
    '{0} matching local tracks',
    '一致するローカル曲：{0} 曲',
    '일치하는 로컬 곡 {0}개'
  ],
  '加入或新建普通歌单…': [
    'Add to or create a regular playlist…',
    '通常のプレイリストに追加・新規作成…',
    '일반 재생목록에 추가 또는 새로 만들기…'
  ],
  '保存规则': ['Save rules', '条件を保存', '규칙 저장'],
  '查看结果或编辑规则': ['View results or edit rules', '結果を表示・条件を編集', '결과 보기 또는 규칙 편집'],
  '还没有智能歌单，创建规则即可自动归集歌曲。': [
    'No smart playlists yet. Create rules to collect matching tracks automatically.',
    'スマートプレイリストはまだありません。条件を作成すると、一致する曲が自動で集まります。',
    '아직 스마트 재생목록이 없습니다. 규칙을 만들어 일치하는 곡을 자동으로 모으세요.'
  ],
  '删除智能歌单规则': [
    'Delete smart playlist rules',
    'スマートプレイリストの条件を削除',
    '스마트 재생목록 규칙 삭제'
  ],
  '删除“{0}”的规则？音乐文件和普通歌单会保留。': [
    'Delete the rules for “{0}”? Music files and regular playlists will be kept.',
    '「{0}」の条件を削除しますか？音楽ファイルと通常のプレイリストは残ります。',
    '“{0}” 규칙을 삭제할까요? 음악 파일과 일반 재생목록은 유지됩니다.'
  ],
  '删除规则失败，请重试。': [
    'Could not delete the rules. Please retry.',
    '条件を削除できませんでした。再試行してください。',
    '규칙을 삭제하지 못했습니다. 다시 시도하세요.'
  ],
  '无法读取智能歌单，请检查数据目录后重试。': [
    'Could not read smart playlists. Check the data folder and retry.',
    'スマートプレイリストを読み込めませんでした。データフォルダーを確認して再試行してください。',
    '스마트 재생목록을 읽지 못했습니다. 데이터 폴더를 확인하고 다시 시도하세요.'
  ],
  '无法更新结果预览，请重试。': [
    'Could not refresh the preview. Please retry.',
    'プレビューを更新できませんでした。再試行してください。',
    '미리보기를 갱신하지 못했습니다. 다시 시도하세요.'
  ],
  '智能歌单尚未保存，编辑内容已保留，请重试。': [
    'The smart playlist has not been saved. Your edits are retained; please retry.',
    'スマートプレイリストはまだ保存されていません。編集内容は保持されています。再試行してください。',
    '스마트 재생목록이 아직 저장되지 않았습니다. 편집 내용은 유지되니 다시 시도하세요.'
  ],
  '请输入 1–120 个字符的智能歌单名称。': [
    'Enter a smart playlist name with 1–120 characters.',
    'スマートプレイリスト名を1～120文字で入力してください。',
    '스마트 재생목록 이름을 1~120자로 입력하세요.'
  ],
  '每条筛选条件最多 160 个字符。': [
    'Each filter condition supports up to 160 characters.',
    '各絞り込み条件は160文字までです。',
    '각 필터 조건은 최대 160자입니다.'
  ],
  '时长须为 0–86400 秒，最短时长不能超过最长时长。': [
    'Duration must be 0–86400 seconds, with the minimum no greater than the maximum.',
    '時間は0～86400秒で、最短時間は最長時間以下にしてください。',
    '길이는 0~86400초이며 최소 길이가 최대 길이를 초과할 수 없습니다.'
  ],
  '最多可保存 100 个智能歌单。': [
    'You can save up to 100 smart playlists.',
    'スマートプレイリストは100件まで保存できます。',
    '스마트 재생목록은 최대 100개까지 저장할 수 있습니다.'
  ],
};
