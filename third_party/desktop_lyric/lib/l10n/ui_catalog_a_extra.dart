// Display-boundary keys discovered after the initial UI literal extraction.
// Domain IDs, track metadata, lyrics and comment content remain unchanged.
const Map<String, List<String>> uiCatalogAExtra = {
  ' · 平台统计 {0} 条': [
    ' · Platform total: {0}',
    ' · 配信元の総数：{0} 件',
    ' · 플랫폼 집계: {0}개',
  ],
  '热门': ['Popular', '人気', '인기'],
  '最新': ['Latest', '新着', '최신'],
  '独立指定': ['Selected independently', '個別に指定', '별도로 지정'],
  'QQ音乐': ['QQ Music', 'QQ Music', 'QQ Music'],
  '网易云音乐': [
    'NetEase Cloud Music',
    'NetEase Cloud Music',
    'NetEase Cloud Music'
  ],
  '酷狗音乐': ['Kugou Music', 'Kugou Music', 'Kugou Music'],
  '所有': ['All', 'すべて', '모두'],
  '总乐库': ['Library', 'ライブラリ', '전체 보관함'],
  '联网': ['Online', 'オンライン', '온라인'],
  '平坦': ['Flat', 'フラット', '플랫'],
  '流行': ['Pop', 'ポップ', '팝'],
  '摇滚': ['Rock', 'ロック', '록'],
  '古典': ['Classical', 'クラシック', '클래식'],
  '爵士': ['Jazz', 'ジャズ', '재즈'],
  '人声': ['Vocals', 'ボーカル', '보컬'],
  '低音增强': ['Bass boost', '低音強調', '저음 강화'],
  '高音增强': ['Treble boost', '高音強調', '고음 강화'],
  '顺序播放': ['In order', '順番に再生', '순서대로 재생'],
  '列表循环': ['Repeat playlist', 'リストをリピート', '목록 반복'],
  '单曲循环': ['Repeat track', '1曲リピート', '한 곡 반복'],
  '启用': ['Enabled', '有効', '사용'],
  '禁用': ['Disabled', '無効', '사용 안 함'],
  '平台未提供': ['Not provided by platform', '配信元からの提供なし', '플랫폼에서 제공하지 않음'],
  '当前选择了“跟随联网歌词”，但歌词来源没有可用于评论的 QQ音乐或网易云歌曲 ID。可以重新选择联网歌词，或独立指定歌曲。': [
    'Follow online lyrics is selected, but the lyric source has no QQ Music or NetEase track ID usable for comments. Choose online lyrics again or select a track independently.',
    '「オンライン歌詞に追従」が選択されていますが、歌詞の提供元にコメント用のQQ MusicまたはNetEaseの楽曲IDがありません。オンライン歌詞を選び直すか、曲を個別に指定してください。',
    '“온라인 가사 따라가기”가 선택되어 있지만 가사 출처에 댓글용 QQ Music 또는 NetEase 곡 ID가 없습니다. 온라인 가사를 다시 선택하거나 곡을 별도로 지정하세요.',
  ],
  '本地歌曲尚未关联评论来源。可以跟随当前联网歌词，或从搜索候选中独立指定一首平台歌曲。': [
    'This local track has no linked comment source. Follow the current online lyrics or select a platform track from the search results.',
    'このローカル曲にはコメントの提供元が関連付けられていません。現在のオンライン歌詞に追従するか、検索候補から配信元の曲を個別に指定できます。',
    '이 로컬 곡에는 댓글 출처가 연결되지 않았습니다. 현재 온라인 가사를 따르거나 검색 후보에서 플랫폼 곡을 별도로 지정하세요.',
  ],
  '这首 QQ音乐歌曲缺少平台数字 ID，暂时不能读取评论。请从联网搜索结果重新打开。': [
    'This QQ Music track has no numeric platform ID, so comments cannot be loaded. Reopen it from online search results.',
    'このQQ Musicの曲には配信元の数値IDがないため、コメントを読み込めません。オンライン検索結果から開き直してください。',
    '이 QQ Music 곡에는 플랫폼 숫자 ID가 없어 댓글을 읽을 수 없습니다. 온라인 검색 결과에서 다시 여세요.',
  ],
  '这首网易云音乐歌曲缺少有效的平台歌曲 ID，暂时不能读取评论。': [
    'This NetEase Cloud Music track has no valid platform track ID, so comments cannot be loaded.',
    'このNetEase Cloud Musicの曲には有効な楽曲IDがないため、コメントを読み込めません。',
    '이 NetEase Cloud Music 곡에는 유효한 플랫폼 곡 ID가 없어 댓글을 읽을 수 없습니다.',
  ],
  '当前仅支持 QQ音乐和网易云音乐的公开只读评论。': [
    'Only public, read-only comments from QQ Music and NetEase Cloud Music are currently supported.',
    '現在、QQ MusicとNetEase Cloud Musicの公開コメントの読み取りのみに対応しています。',
    '현재 QQ Music과 NetEase Cloud Music의 공개 댓글 읽기만 지원합니다.',
  ],
  '每个分类最多读取 200 条评论，已停止继续请求。': [
    'The limit of 200 comments per category has been reached. Further requests have stopped.',
    'カテゴリーごとの上限200件に達したため、追加のコメント取得を停止しました。',
    '분류별 최대 200개 댓글에 도달하여 추가 요청을 중단했습니다.',
  ],
  '评论请求超时，请检查网络后重试。': [
    'The comment request timed out. Check your connection and try again.',
    'コメントの取得がタイムアウトしました。ネットワークを確認して再試行してください。',
    '댓글 요청 시간이 초과되었습니다. 네트워크를 확인한 후 다시 시도하세요.',
  ],
  '平台返回的评论格式异常或内容过大，暂时无法读取，请稍后重试。': [
    'The platform returned invalid or oversized comment data. Please try again later.',
    '配信元のコメントデータの形式が不正か、サイズが大きすぎるため読み込めません。しばらくしてから再試行してください。',
    '플랫폼의 댓글 데이터 형식이 잘못되었거나 크기가 너무 큽니다. 잠시 후 다시 시도하세요.',
  ],
  '评论加载失败，请检查网络连接后重试。': [
    'Could not load comments. Check your network connection and try again.',
    'コメントを読み込めませんでした。ネットワーク接続を確認して再試行してください。',
    '댓글을 불러오지 못했습니다. 네트워크 연결을 확인한 후 다시 시도하세요.',
  ],
  '平台暂不允许匿名读取评论或请求过于频繁，请稍后重试。': [
    'The platform is not allowing anonymous comment access, or requests are too frequent. Please try again later.',
    '配信元が匿名でのコメント取得を許可していないか、リクエストが多すぎます。しばらくしてから再試行してください。',
    '플랫폼에서 익명 댓글 읽기를 허용하지 않거나 요청이 너무 잦습니다. 잠시 후 다시 시도하세요.',
  ],
  '平台暂时不提供这首歌曲的匿名评论，请稍后重试；不会尝试登录或绕过限制。': [
    'The platform is not currently providing anonymous comments for this track. Try again later; no login or restriction bypass will be attempted.',
    '配信元は現在、この曲のコメントを匿名では提供していません。しばらくしてから再試行してください。ログインや制限の回避は行いません。',
    '플랫폼에서 현재 이 곡의 익명 댓글을 제공하지 않습니다. 잠시 후 다시 시도하세요. 로그인이나 제한 우회는 시도하지 않습니다.',
  ],
  '评论来源暂不允许匿名读取或请求过于频繁，请稍后重试。': [
    'The comment source currently disallows anonymous access or is receiving requests too frequently. Try again later.',
    'コメントの取得元が匿名での読み取りを許可していないか、リクエストが多すぎます。しばらくしてから再試行してください。',
    '댓글 출처에서 익명 조회를 허용하지 않거나 요청이 너무 잦습니다. 잠시 후 다시 시도하세요.',
  ],
  '评论服务暂时不可用，请稍后重试。': [
    'The comment service is temporarily unavailable. Try again later.',
    'コメントサービスは一時的に利用できません。しばらくしてから再試行してください。',
    '댓글 서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도하세요.',
  ],
  '本地歌曲尚未关联评论来源。可以跟随当前联网歌词，或从搜索候选中独立指定一首来源歌曲。': [
    'This local track has no linked comment source. Follow the current online lyrics or select a source track independently from the search results.',
    'このローカル曲にはコメントの取得元が関連付けられていません。現在のオンライン歌詞に追従するか、検索候補から取得元の曲を個別に指定できます。',
    '이 로컬 곡에는 연결된 댓글 출처가 없습니다. 현재 온라인 가사를 따르거나 검색 후보에서 출처 곡을 별도로 지정하세요.',
  ],
  '这首自定义来源歌曲缺少可安全保存的来源歌曲 ID，暂时不能关联评论。': [
    'This custom-source track has no source track ID that can be stored safely, so comments cannot be linked yet.',
    'このカスタム音源の曲には安全に保存できる取得元の曲 ID がないため、現在はコメントを関連付けられません。',
    '이 사용자 지정 음원 곡에는 안전하게 저장할 수 있는 출처 곡 ID가 없어 아직 댓글을 연결할 수 없습니다.',
  ],
  '当前支持 QQ音乐、网易云音乐及已配置评论能力的自定义歌源。': [
    'QQ Music, NetEase Cloud Music, and custom sources configured for comments are currently supported.',
    '現在、QQ Music、NetEase Cloud Music、およびコメント機能を設定したカスタム音源に対応しています。',
    '현재 QQ Music, NetEase Cloud Music 및 댓글 기능을 설정한 사용자 지정 음원을 지원합니다.',
  ],
  '评论来源返回的格式异常或内容过大，暂时无法读取，请稍后重试。': [
    'The comment source returned invalid or oversized data. It cannot be read right now; try again later.',
    'コメントの取得元が不正な形式または大きすぎるデータを返したため、現在は読み込めません。しばらくしてから再試行してください。',
    '댓글 출처에서 잘못된 형식 또는 너무 큰 데이터를 반환해 현재 읽을 수 없습니다. 잠시 후 다시 시도하세요.',
  ],
  '对应的自定义歌源已移除、停用或未配置评论能力。': [
    'The corresponding custom source was removed, disabled, or is not configured for comments.',
    '対応するカスタム音源が削除、無効化されたか、コメント機能が設定されていません。',
    '해당 사용자 지정 음원이 삭제되었거나 비활성화되었거나 댓글 기능이 설정되지 않았습니다.',
  ],
  '对应的自定义歌源在请求期间已修改或停用。': [
    'The corresponding custom source was changed or disabled during the request.',
    'リクエスト中に対応するカスタム音源が変更または無効化されました。',
    '요청 중에 해당 사용자 지정 음원이 변경되었거나 비활성화되었습니다.',
  ],
  '对应的自定义歌源当前不可用。': [
    'The corresponding custom source is currently unavailable.',
    '対応するカスタム音源は現在利用できません。',
    '해당 사용자 지정 음원을 현재 사용할 수 없습니다.',
  ],
  '歌源返回的评论格式异常或内容过大。': [
    'The source returned invalid or oversized comment data.',
    '音源が不正な形式または大きすぎるコメントデータを返しました。',
    '음원에서 잘못된 형식 또는 너무 큰 댓글 데이터를 반환했습니다.',
  ],
  '歌源拒绝了评论请求，请检查接口配置。': [
    'The source rejected the comment request. Check the endpoint configuration.',
    '音源がコメントのリクエストを拒否しました。エンドポイント設定を確認してください。',
    '음원에서 댓글 요청을 거부했습니다. 엔드포인트 설정을 확인하세요.',
  ],
};
