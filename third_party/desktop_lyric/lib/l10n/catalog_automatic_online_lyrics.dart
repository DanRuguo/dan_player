const Map<String, List<String>> catalogAutomaticOnlineLyrics = {
  '自动联网': ['Automatic network access', '自動オンライン接続', '자동 네트워크 연결'],
  '缺少本地和缓存歌词时自动搜词；打开已关联的歌曲评论时自动更新一次。': [
    'Search when no local or cached lyrics exist. Refresh linked comments once when opened.',
    'ローカル・キャッシュに歌詞がない場合は自動検索し、関連付けたコメントを開いたときに一度更新します。',
    '로컬 및 캐시 가사가 없으면 자동 검색하며, 연결된 댓글을 열 때 한 번 새로고침합니다.',
  ],
  '联网无匹配歌词 (╥﹏╥)': [
    'No matching lyrics online (╥﹏╥)',
    '一致する歌詞がオンラインにありません (╥﹏╥)',
    '온라인에 일치하는 가사가 없습니다 (╥﹏╥)'
  ],
  '提高来源优先级': ['Move source up', 'ソースの優先度を上げる', '소스 우선순위 높이기'],
  '降低来源优先级': ['Move source down', 'ソースの優先度を下げる', '소스 우선순위 낮추기'],
  '优先使用匹配度高的歌词；同分优先逐字歌词和内置来源，第三方源按设置顺序尝试。': [
    'Prefer closer matches, then word timing and built-in sources for ties. Custom sources follow their settings order.',
    '一致度を優先し、同点では単語同期歌詞と内蔵ソースを優先します。外部ソースは設定順に試します。',
    '일치도를 우선하며 동점이면 단어별 가사와 내장 소스를 우선합니다. 외부 소스는 설정 순서로 시도합니다.'
  ],
  '候选按匹配度和来源排序；自动选词时，同分优先逐字歌词。': [
    'Candidates are sorted by match and source. Automatic selection favors word timing for ties.',
    '候補は一致度とソース順に表示します。自動選択では、同点なら単語同期歌詞を優先します。',
    '후보는 일치도와 소스 순으로 정렬합니다. 자동 선택에서는 동점일 때 단어별 가사를 우선합니다.',
  ],
  "批量缓存歌词": ["Batch cache lyrics", "歌詞を一括キャッシュ", "가사 일괄 캐시"],
  "选择已导入的文件夹": ["Choose an imported folder", "取り込み済みフォルダーを選択", "가져온 폴더 선택"],
  "请先将音乐文件夹导入乐库。": [
    "Import a music folder into your library first.",
    "先に音楽フォルダーをライブラリに取り込んでください。",
    "먼저 음악 폴더를 라이브러리로 가져오세요."
  ],
  "开始缓存": ["Start caching", "キャッシュ開始", "캐시 시작"],
  "选择文件夹后开始，只缓存缺失的歌词。": [
    "Choose a folder to cache missing lyrics.",
    "フォルダーを選択し、不足する歌詞をキャッシュします。",
    "폴더를 선택해 누락된 가사를 캐시하세요."
  ],
  "仅处理所选已导入文件夹及子文件夹中的入库歌曲；跳过已有歌词，只缓存匹配成功的结果，不修改音乐文件。": [
    "Process library songs in the selected imported folder and its subfolders. Skip saved lyrics and cache successful matches without modifying music files.",
    "選択した取り込み済みフォルダーとサブフォルダー内の登録曲のみを処理します。既存の歌詞はスキップし、一致した歌詞をキャッシュします。音楽ファイルは変更しません。",
    "선택한 가져온 폴더와 하위 폴더의 라이브러리 곡만 처리합니다. 기존 가사는 건너뛰고 일치한 결과만 캐시하며 음악 파일은 수정하지 않습니다."
  ],
  "正在取消，等待当前请求结束…": [
    "Cancelling; waiting for the current request…",
    "キャンセル中。現在のリクエストの終了を待っています…",
    "취소 중, 현재 요청이 끝나기를 기다리는 중…"
  ],
  "正在读取已导入的歌曲…": ["Reading imported songs…", "取り込み済みの曲を読み込み中…", "가져온 곡을 읽는 중…"],
  "正在匹配并缓存歌词…": [
    "Matching and caching lyrics…",
    "歌詞を検索してキャッシュ中…",
    "가사 검색 및 캐시 중…"
  ],
  "已取消，已缓存的歌词会保留。": [
    "Cancelled. Cached lyrics are retained.",
    "キャンセルしました。キャッシュ済みの歌詞は保持されます。",
    "취소했습니다. 이미 캐시한 가사는 유지됩니다."
  ],
  "批量缓存完成": ["Batch caching complete", "一括キャッシュ完了", "일괄 캐시 완료"],
  "读取失败，请重新选择已导入的文件夹。": [
    "Could not read songs. Select an imported folder again.",
    "曲を読み込めませんでした。取り込み済みフォルダーを選択し直してください。",
    "곡을 읽지 못했습니다. 가져온 폴더를 다시 선택하세요."
  ],
  "已处理 {0}/{1} · 缓存 {2} · 跳过 {3} · 无匹配 {4} · 纯音乐 {5} · 失败 {6}": [
    "Processed {0}/{1} · Cached {2} · Skipped {3} · Unmatched {4} · Instrumental {5} · Failed {6}",
    "処理 {0}/{1} · 保存 {2} · スキップ {3} · 一致なし {4} · インスト {5} · 失敗 {6}",
    "처리 {0}/{1} · 캐시 {2} · 건너뜀 {3} · 불일치 {4} · 연주곡 {5} · 실패 {6}"
  ],
  '来源：{0} · 匹配度未知，仅供手动选择': [
    'Source: {0} · Match unknown; manual selection only',
    'ソース：{0} · 一致度不明、手動選択のみ',
    '소스: {0} · 일치도 알 수 없음, 수동 선택 전용'
  ],
  '正在搜索其他歌词来源…': [
    'Searching other lyric sources…',
    'ほかの歌詞ソースを検索中…',
    '다른 가사 소스 검색 중…',
  ],
  '正在识别歌词格式': [
    'Identifying lyric format',
    '歌詞形式を確認中',
    '가사 형식 확인 중',
  ],
  '歌词格式未知': [
    'Lyric format unknown',
    '歌詞形式は不明',
    '가사 형식 알 수 없음',
  ],
  '无法预览歌词，点选可重试。': [
    'Preview unavailable; select to retry.',
    'プレビューできません。選択すると再試行します。',
    '미리 볼 수 없습니다. 선택하여 다시 시도하세요.',
  ],
  '已停止搜索其他来源，当前候选仍可选择。': [
    'Searching other sources stopped. You can still choose a listed candidate.',
    'ほかのソースの検索を停止しました。表示中の候補は選択できます。',
    '다른 소스 검색을 중지했습니다. 표시된 후보는 계속 선택할 수 있습니다.',
  ],
  '继续搜索': [
    'Continue searching',
    '検索を続ける',
    '검색 계속',
  ],
};
