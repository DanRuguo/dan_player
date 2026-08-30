// Explicit UI translations, source-key order 250–499.
// Placeholders and user/media arguments are preserved verbatim.
const Map<String, List<String>> uiCatalogB = {
  "选择关联歌曲": ["Select a linked song", "関連付ける曲を選択", "연결할 곡 선택"],
  "当前歌词不是带平台 ID 的 QQ音乐或网易云来源": [
    "The current lyrics are not from QQ Music or NetEase Cloud Music with a platform song ID",
    "現在の歌詞は、曲 ID を持つ QQ Music または NetEase Cloud Music のものではありません",
    "현재 가사는 플랫폼 곡 ID가 있는 QQ Music 또는 NetEase Cloud Music 출처가 아닙니다"
  ],
  "评论来源会随以后选择的联网歌词变化": [
    "The comment source will follow future online lyric selections",
    "今後選択するオンライン歌詞に合わせてコメントの取得元が変わります",
    "이후 선택하는 온라인 가사에 따라 댓글 출처가 바뀝니다"
  ],
  "跟随联网歌词": ["Follow online lyrics", "オンライン歌詞に合わせる", "온라인 가사에 맞추기"],
  "解除关联": ["Unlink", "関連付けを解除", "연결 해제"],
  "正在加载评论…": ["Loading comments…", "コメントを読み込み中…", "댓글 불러오는 중…"],
  "重试": ["Retry", "再試行", "다시 시도"],
  "平台暂未返回这首歌曲的评论。": [
    "The platform has not returned any comments for this song.",
    "この曲のコメントはまだ取得できません。",
    "플랫폼에서 이 곡의 댓글을 반환하지 않았습니다."
  ],
  "平台返回了重复页面，已停止继续请求。": [
    "The platform returned a duplicate page. Further requests have stopped.",
    "重複したページが返されたため、追加の取得を停止しました。",
    "플랫폼에서 중복 페이지를 반환하여 추가 요청을 중단했습니다."
  ],
  "已达到本次每个分类最多 10 页（200 条）的读取上限。": [
    "The limit of 10 pages (200 comments) per category for this session has been reached.",
    "今回の取得上限（カテゴリごとに10ページ・200件）に達しました。",
    "이번 세션의 카테고리별 조회 한도인 10페이지(200개)에 도달했습니다."
  ],
  "已显示平台返回的全部评论。": [
    "All comments returned by the platform are shown.",
    "取得できたコメントをすべて表示しています。",
    "플랫폼에서 반환한 모든 댓글을 표시했습니다."
  ],
  "加载更多": ["Load more", "さらに読み込む", "더 불러오기"],
  "{0} 赞": ["{0} likes", "{0} 件のいいね", "좋아요 {0}개"],
  "引用 / 回复 · {0}\n{1}": [
    "Quote / reply · {0}\n{1}",
    "引用 / 返信 · {0}\n{1}",
    "인용 / 답글 · {0}\n{1}"
  ],
  "搜索失败，请检查网络后重试。": [
    "Search failed. Check your connection and try again.",
    "検索に失敗しました。ネットワーク接続を確認して再試行してください。",
    "검색하지 못했습니다. 네트워크를 확인한 후 다시 시도하세요."
  ],
  "该候选缺少可核实的平台歌曲 ID。": [
    "This candidate has no verifiable platform song ID.",
    "この候補には確認可能なプラットフォームの曲 ID がありません。",
    "이 후보에는 확인 가능한 플랫폼 곡 ID가 없습니다."
  ],
  "评论预览暂时不可用；仍可按平台 ID 关联。": [
    "Comment preview is unavailable. You can still link by platform song ID.",
    "コメントのプレビューを取得できません。曲 ID での関連付けは可能です。",
    "댓글 미리보기를 사용할 수 없습니다. 플랫폼 곡 ID로 연결할 수는 있습니다."
  ],
  "为本地歌曲关联评论": [
    "Link comments to a local song",
    "ローカル曲にコメントを関連付ける",
    "로컬 곡에 댓글 연결"
  ],
  "只保存所选平台与歌曲 ID，不登录平台，也不会修改歌词或本地音频标签。": [
    "Only the selected platform and song ID are saved. No sign-in is required, and lyrics and local audio tags are not changed.",
    "選択したプラットフォームと曲 ID のみ保存します。ログインは不要で、歌詞やローカル音声のタグは変更しません。",
    "선택한 플랫폼과 곡 ID만 저장합니다. 로그인하지 않으며 가사나 로컬 오디오 태그를 수정하지 않습니다."
  ],
  "歌曲名 / 作曲家或演唱者": [
    "Song title / composer or performer",
    "曲名 / 作曲者・歌手",
    "곡명 / 작곡가 또는 가수"
  ],
  "搜索候选": ["Search candidates", "候補を検索", "후보 검색"],
  "没有可关联的候选，请修改关键词后重试。": [
    "No candidates can be linked. Change your keywords and try again.",
    "関連付け可能な候補がありません。キーワードを変えて再試行してください。",
    "연결 가능한 후보가 없습니다. 검색어를 바꾸고 다시 시도하세요."
  ],
  "{0}\n专辑：{1} · 作曲：{2} · {3}": [
    "{0}\nAlbum: {1} · Composer: {2} · {3}",
    "{0}\nアルバム：{1} · 作曲：{2} · {3}",
    "{0}\n앨범: {1} · 작곡: {2} · {3}"
  ],
  "正在读取一条评论示例…": [
    "Loading a sample comment…",
    "コメントのサンプルを読み込み中…",
    "댓글 예시 불러오는 중…"
  ],
  "平台当前没有返回评论示例。": [
    "The platform has not returned a sample comment.",
    "コメントのサンプルを取得できませんでした。",
    "플랫폼에서 댓글 예시를 반환하지 않았습니다."
  ],
  "评论示例 · {0}\n{1}": [
    "Sample comment · {0}\n{1}",
    "コメントのサンプル · {0}\n{1}",
    "댓글 예시 · {0}\n{1}"
  ],
  "关联所选歌曲": ["Link selected song", "選択した曲を関連付ける", "선택한 곡 연결"],
  "打开导航栏": ["Open navigation", "ナビゲーションを開く", "탐색 메뉴 열기"],
  "返回": ["Back", "戻る", "뒤로"],
  "切换全屏失败：{0}": [
    "Could not toggle fullscreen: {0}",
    "全画面表示の切り替えに失敗しました：{0}",
    "전체 화면 전환 실패: {0}"
  ],
  "切换窗口大小失败：{0}": [
    "Could not change window size: {0}",
    "ウィンドウサイズの変更に失敗しました：{0}",
    "창 크기 변경 실패: {0}"
  ],
  "迷你播放器（{0}）": ["Mini player ({0})", "ミニプレーヤー（{0}）", "미니 플레이어({0})"],
  "退出全屏": ["Exit fullscreen", "全画面表示を終了", "전체 화면 종료"],
  "全屏": ["Fullscreen", "全画面表示", "전체 화면"],
  "窗口大小已锁定": ["Window size is locked", "ウィンドウサイズはロックされています", "창 크기가 잠겨 있습니다"],
  "全屏模式下不可用": [
    "Unavailable in fullscreen",
    "全画面表示では使用できません",
    "전체 화면에서는 사용할 수 없습니다"
  ],
  "还原": ["Restore", "元のサイズに戻す", "이전 크기로"],
  "最大化": ["Maximize", "最大化", "최대화"],
  "退出": ["Exit", "終了", "종료"],
  "音乐列表样式": ["Music list style", "曲リストの表示形式", "음악 목록 스타일"],
  "经典列表": ["Classic list", "従来のリスト", "기본 목록"],
  "资源管理器分栏": ["Explorer-style columns", "エクスプローラー形式の列表示", "탐색기형 열 보기"],
  "分栏显示歌名、作曲家与专辑；窗口较窄时自动使用经典列表。": [
    "Show title, composer and album in columns. Narrow windows automatically use the classic list.",
    "曲名・作曲者・アルバムを列で表示します。ウィンドウが狭い場合は従来のリストに切り替わります。",
    "곡명, 작곡가, 앨범을 열로 표시합니다. 창이 좁으면 기본 목록으로 자동 전환됩니다."
  ],
  "紧凑歌单": ["Compact playlists", "コンパクトなプレイリスト", "간결한 재생목록"],
  "收紧歌单标题与卡片间距，保留所有播放、菜单和排序操作。": [
    "Reduce spacing around playlist headers and cards while keeping playback, menus and sorting available.",
    "再生・メニュー・並べ替え機能を保ったまま、プレイリストの見出しやカードの間隔を詰めます。",
    "재생, 메뉴, 정렬 기능을 유지하면서 재생목록 제목과 카드 간격을 줄입니다."
  ],
  "{0} 首作品": ["{0} works", "{0} 作品", "작품 {0}개"],
  "{0} 首乐曲": ["{0} tracks", "{0} 曲", "{0}곡"],
  "来源": ["Source", "取得元", "출처"],
  "本地文件": ["Local file", "ローカルファイル", "로컬 파일"],
  "音轨": ["Track number", "トラック番号", "트랙 번호"],
  "码率": ["Bitrate", "ビットレート", "비트레이트"],
  "采样率": ["Sample rate", "サンプルレート", "샘플링 레이트"],
  "播放统计": ["Playback statistics", "再生統計", "재생 통계"],
  "{0} 次 · {1}": ["{0} plays · {1}", "{0} 回 · {1}", "{0}회 · {1}"],
  "联网标识": ["Online ID", "オンライン ID", "온라인 ID"],
  "文件位置": ["File location", "ファイルの場所", "파일 위치"],
  "打开失败": ["Could not open", "開けませんでした", "열지 못했습니다"],
  "在文件资源管理器中显示": ["Show in File Explorer", "エクスプローラーで表示", "파일 탐색기에서 표시"],
  "文件时间": ["File timestamps", "ファイルの日時", "파일 시간"],
  "创建：{0}\n修改：{1}": [
    "Created: {0}\nModified: {1}",
    "作成：{0}\n更新：{1}",
    "만든 날짜: {0}\n수정한 날짜: {1}"
  ],
  "本地音乐": ["Local music", "ローカル音楽", "로컬 음악"],
  "编辑信息": ["Edit information", "情報を編集", "정보 편집"],
  "移出总乐库": ["Remove from library", "ライブラリから削除", "라이브러리에서 제거"],
  "保存到本地": ["Save locally", "ローカルに保存", "로컬에 저장"],
  "当前来源不可下载": [
    "This source does not support downloads",
    "この取得元はダウンロードに対応していません",
    "현재 출처에서는 다운로드할 수 없습니다"
  ],
  "实时频谱": ["Live spectrum", "リアルタイムスペクトラム", "실시간 스펙트럼"],
  "播放这首歌以显示实时频谱": [
    "Play this song to show its live spectrum",
    "この曲を再生するとスペクトラムを表示します",
    "이 곡을 재생하면 실시간 스펙트럼을 표시합니다"
  ],
  "音乐页必须提供旧自定义排序，保留索引 5。": [
    "The music page must supply the legacy custom sort at index 5.",
    "曲ページでは従来のカスタム並べ替えをインデックス 5 に保持する必要があります。",
    "음악 페이지는 기존 사용자 지정 정렬을 제공하고 인덱스 5를 유지해야 합니다."
  ],
  "正在只读检查本地歌词中的作曲信息；无作曲署名时会回退到参与创作的艺术家。": [
    "Checking local lyrics for composer credits without modifying files. If no composer is credited, contributing artists are used.",
    "ファイルを変更せず、ローカル歌詞の作曲情報を確認しています。作曲者の記載がない場合は参加アーティストを使用します。",
    "파일을 수정하지 않고 로컬 가사의 작곡 정보를 확인하고 있습니다. 작곡가 표기가 없으면 참여 아티스트를 사용합니다."
  ],
  "部分本地分类标签尚未读取，可刷新乐库尝试补全；作曲信息与参与创作的艺术家均缺失的歌曲保留在“未知作曲家”中。": [
    "Some local classification tags have not been read. Refresh the library to try filling them in. Songs with neither composer nor contributing artist information remain under “Unknown composer”.",
    "一部のローカル分類タグをまだ読み取れていません。ライブラリを更新すると補完できる場合があります。作曲者と参加アーティストの両方が不明な曲は「不明な作曲者」に残ります。",
    "일부 로컬 분류 태그를 아직 읽지 못했습니다. 라이브러리를 새로 고쳐 보완할 수 있습니다. 작곡가와 참여 아티스트 정보가 모두 없는 곡은 ‘알 수 없는 작곡가’에 남습니다."
  ],
  "未找到作曲信息或参与创作的艺术家；歌曲保留在“未知作曲家”中。": [
    "No composer or contributing artist information was found. These songs remain under “Unknown composer”.",
    "作曲者や参加アーティストの情報が見つかりません。これらの曲は「不明な作曲者」に残ります。",
    "작곡가 또는 참여 아티스트 정보를 찾지 못했습니다. 해당 곡은 ‘알 수 없는 작곡가’에 남습니다."
  ],
  "正在只读检查本地歌词；语言优先使用标签，其次参考歌词及标题、作曲/参与创作艺术家等元数据推断。": [
    "Checking local lyrics without modifying files. Language tags take priority; otherwise, lyrics, titles and composer/contributing artist metadata are used for inference.",
    "ファイルを変更せずローカル歌詞を確認しています。言語タグを優先し、次に歌詞、曲名、作曲者・参加アーティストなどのメタデータから推定します。",
    "파일을 수정하지 않고 로컬 가사를 확인하고 있습니다. 언어 태그를 우선 사용하고, 그다음 가사, 제목, 작곡가/참여 아티스트 등의 메타데이터로 추정합니다."
  ],
  "语言优先使用标签，其次参考歌词及标题、作曲/参与创作艺术家等元数据推断；推断不等于音频识别，无法确认的歌曲归入“未识别”。": [
    "Language tags take priority; otherwise, lyrics, titles and composer/contributing artist metadata are used for inference. This is not audio recognition. Uncertain songs are grouped as “Unidentified”.",
    "言語タグを優先し、次に歌詞、曲名、作曲者・参加アーティストなどのメタデータから推定します。音声認識ではありません。判断できない曲は「未識別」に分類します。",
    "언어 태그를 우선 사용하고, 그다음 가사, 제목, 작곡가/참여 아티스트 등의 메타데이터로 추정합니다. 이는 오디오 인식이 아니며, 확인할 수 없는 곡은 ‘미확인’으로 분류합니다."
  ],
  "作曲家采用宽口径：优先使用作曲标签、歌词署名，缺失时回退到参与创作的艺术家；回退结果会单独标注。": [
    "Composer grouping uses a broad definition: composer tags and lyric credits take priority; contributing artists are used as a fallback and labeled separately.",
    "作曲者は広い定義で分類します。作曲タグや歌詞のクレジットを優先し、不明な場合は参加アーティストで補完して、区別して表示します。",
    "작곡가는 넓은 기준으로 분류합니다. 작곡 태그와 가사 크레딧을 우선 사용하고, 없으면 참여 아티스트로 대체하며 별도로 표시합니다."
  ],
  "仅按本地文件扩展名分类；联网歌曲或无扩展名文件归入“未知格式”。": [
    "Grouped only by local file extension. Online songs and files without an extension are listed as “Unknown format”.",
    "ローカルファイルの拡張子のみで分類します。オンラインの曲や拡張子のないファイルは「不明な形式」に分類します。",
    "로컬 파일 확장자로만 분류합니다. 온라인 곡이나 확장자가 없는 파일은 ‘알 수 없는 형식’으로 분류합니다."
  ],
  "{0} 首歌曲 · {1} {2}": [
    "{0} songs · {1} {2}",
    "{0} 曲 · {1} {2}",
    "{0}곡 · {1} {2}"
  ],
  "搜索专辑或专辑艺术家": [
    "Search albums or album artists",
    "アルバムまたはアルバムアーティストを検索",
    "앨범 또는 앨범 아티스트 검색"
  ],
  "搜索{0}": ["Search {0}", "{0}を検索", "{0} 검색"],
  "清除分类搜索": ["Clear category search", "分類検索をクリア", "분류 검색 지우기"],
  "总乐库还没有歌曲。添加本地音乐或将联网歌曲加入总乐库后即可分类浏览。": [
    "Your library is empty. Add local music or online songs to browse by category.",
    "ライブラリに曲がありません。ローカル音楽やオンラインの曲を追加すると、分類別に閲覧できます。",
    "라이브러리에 곡이 없습니다. 로컬 음악이나 온라인 곡을 라이브러리에 추가하면 분류별로 찾아볼 수 있습니다."
  ],
  "未找到匹配的分类": ["No matching categories", "一致する分類がありません", "일치하는 분류가 없습니다"],
  "{0} 首 · {1}": ["{0} songs · {1}", "{0} 曲 · {1}", "{0}곡 · {1}"],
  "正在只读检查本地歌词中的分类信息…": [
    "Checking local lyrics for classification without modifying files…",
    "ファイルを変更せず、ローカル歌詞の分類情報を確認中…",
    "파일을 수정하지 않고 로컬 가사의 분류 정보 확인 중…"
  ],
  "此分类已不存在或标签已更新，请返回分类页重新选择。": [
    "This category no longer exists or its tags have changed. Return to categories and select again.",
    "この分類は存在しないか、タグが更新されています。分類ページに戻って選択し直してください。",
    "이 분류가 없어졌거나 태그가 갱신되었습니다. 분류 페이지로 돌아가 다시 선택하세요."
  ],
  "全选": ["Select all", "すべて選択", "모두 선택"],
  "加入歌单 ({0})": ["Add to playlist ({0})", "プレイリストに追加（{0}）", "재생목록에 추가({0})"],
  "分类依据：{0}": ["Classification basis: {0}", "分類の根拠：{0}", "분류 근거: {0}"],
  "分类仅用于浏览，不移动文件或更改标签。": [
    "Categories are for browsing only. No files are moved and no tags are changed.",
    "分類は閲覧用です。ファイルの移動やタグの変更は行いません。",
    "분류는 탐색용으로만 사용하며 파일을 이동하거나 태그를 변경하지 않습니다."
  ],
  "在此分类中搜索歌曲": ["Search songs in this category", "この分類内の曲を検索", "이 분류에서 곡 검색"],
  "此分类中未找到匹配的歌曲": [
    "No matching songs in this category",
    "この分類に一致する曲がありません",
    "이 분류에 일치하는 곡이 없습니다"
  ],
  "{0} 个文件夹": ["{0} folders", "{0} フォルダー", "폴더 {0}개"],
  "路径": ["Path", "パス", "경로"],
  "修改日期": ["Date modified", "更新日時", "수정한 날짜"],
  "未命名文件夹": ["Unnamed folder", "名前のないフォルダー", "이름 없는 폴더"],
  "未知日期": ["Unknown date", "不明な日付", "알 수 없는 날짜"],
  "{0} 首歌曲 · 修改于 {1}": [
    "{0} songs · Modified {1}",
    "{0} 曲 · 更新：{1}",
    "{0}곡 · 수정: {1}"
  ],
  "{0} 首乐曲 · {1}": ["{0} tracks · {1}", "{0} 曲 · {1}", "{0}곡 · {1}"],
  "播放列表": ["Play queue", "再生キュー", "재생 대기열"],
  "加入总乐库失败，请重试": [
    "Could not add to library. Please try again.",
    "ライブラリに追加できませんでした。再試行してください。",
    "라이브러리에 추가하지 못했습니다. 다시 시도하세요."
  ],
  "本地歌曲详情": ["Local song details", "ローカル曲の詳細", "로컬 곡 정보"],
  "平坦": ["Flat", "フラット", "플랫"],
  "流行": ["Pop", "ポップ", "팝"],
  "摇滚": ["Rock", "ロック", "록"],
  "古典": ["Classical", "クラシック", "클래식"],
  "爵士": ["Jazz", "ジャズ", "재즈"],
  "人声": ["Vocals", "ボーカル", "보컬"],
  "低音增强": ["Bass boost", "低音ブースト", "저음 강화"],
  "高音增强": ["Treble boost", "高音ブースト", "고음 강화"],
  "当前输出模式不支持均衡器": [
    "The current output mode does not support the equalizer",
    "現在の出力モードはイコライザーに対応していません",
    "현재 출력 모드에서는 이퀄라이저를 지원하지 않습니다"
  ],
  "均衡器": ["Equalizer", "イコライザー", "이퀄라이저"],
  "预设": ["Presets", "プリセット", "프리셋"],
  "重置为平坦": ["Reset to flat", "フラットに戻す", "플랫으로 초기화"],
  "调节范围 ±15 dB，换歌后继续保持。": [
    "Adjust within ±15 dB. Settings are retained when songs change.",
    "調整範囲は ±15 dB です。曲が変わっても設定を維持します。",
    "±15 dB 범위에서 조절하며 곡이 바뀌어도 설정을 유지합니다."
  ],
  "完成": ["Done", "完了", "완료"],
  "指定默认歌词": ["Choose default lyrics", "既定の歌詞を選択", "기본 가사 지정"],
  "在线": ["Online", "オンライン", "온라인"],
  "本地": ["Local", "ローカル", "로컬"],
  "搜索歌词候选失败，请检查网络后重试。": [
    "Could not search for lyrics. Check your connection and try again.",
    "歌詞候補を検索できませんでした。ネットワーク接続を確認して再試行してください。",
    "가사 후보를 검색하지 못했습니다. 네트워크를 확인한 후 다시 시도하세요."
  ],
  "歌曲已切换；已保存原歌曲的歌词来源，但没有应用到当前歌曲。": [
    "The song has changed. The previous song's lyric source was saved, but was not applied to the current song.",
    "曲が切り替わりました。元の曲の歌詞取得元は保存しましたが、現在の曲には適用していません。",
    "곡이 바뀌었습니다. 이전 곡의 가사 출처는 저장했지만 현재 곡에는 적용하지 않았습니다."
  ],
  "保存本地歌词来源失败，旧设置已保留，请重试。": [
    "Could not save the local lyric source. Previous settings were retained. Please try again.",
    "ローカル歌詞の取得元を保存できませんでした。以前の設定を保持しています。再試行してください。",
    "로컬 가사 출처를 저장하지 못했습니다. 기존 설정을 유지했습니다. 다시 시도하세요."
  ],
  "歌曲已切换，旧歌曲的候选没有应用。": [
    "The song has changed. The previous song's candidate was not applied.",
    "曲が切り替わったため、元の曲の候補は適用していません。",
    "곡이 바뀌어 이전 곡의 후보를 적용하지 않았습니다."
  ],
  "{0}未返回可用歌词，可选择其他候选或重试。": [
    "{0} returned no usable lyrics. Choose another candidate or try again.",
    "{0}から利用可能な歌詞を取得できませんでした。別の候補を選ぶか、再試行してください。",
    "{0}에서 사용 가능한 가사를 반환하지 않았습니다. 다른 후보를 선택하거나 다시 시도하세요."
  ],
  "获取或保存歌词失败，旧设置已保留，请重试。": [
    "Could not fetch or save lyrics. Previous settings were retained. Please try again.",
    "歌詞の取得または保存に失敗しました。以前の設定を保持しています。再試行してください。",
    "가사를 가져오거나 저장하지 못했습니다. 기존 설정을 유지했습니다. 다시 시도하세요."
  ],
  "默认歌词": ["Default lyrics", "既定の歌詞", "기본 가사"],
  "关闭": ["Close", "閉じる", "닫기"],
  "当前播放歌曲已经改变。为避免歌词串歌，请关闭后从新歌曲重新选择。": [
    "The playing song has changed. Close this dialog and select lyrics from the new song to avoid mismatched lyrics.",
    "再生中の曲が変わりました。歌詞の取り違えを防ぐため、閉じてから新しい曲で選択し直してください。",
    "재생 중인 곡이 바뀌었습니다. 가사가 다른 곡에 적용되지 않도록 이 창을 닫고 새 곡에서 다시 선택하세요."
  ],
  "自动匹配会先尝试自定义歌词接口；接口结果没有平台歌曲 ID，因此不会出现在下面的内置平台候选中。": [
    "Automatic matching tries custom lyric APIs first. Their results have no platform song IDs, so they do not appear among the built-in platform candidates below.",
    "自動検索ではカスタム歌詞 API を先に試します。その結果にはプラットフォームの曲 ID がないため、下の標準プラットフォーム候補には表示されません。",
    "자동 검색은 사용자 지정 가사 API를 먼저 시도합니다. 해당 결과에는 플랫폼 곡 ID가 없으므로 아래 기본 플랫폼 후보 목록에는 표시되지 않습니다."
  ],
  "使用本地歌词": ["Use local lyrics", "ローカル歌詞を使用", "로컬 가사 사용"],
  "读取内嵌歌词或同目录同名 LRC 文件": [
    "Read embedded lyrics or a same-name LRC file in the song's folder",
    "埋め込み歌詞、または同じフォルダーにある同名の LRC ファイルを読み込みます",
    "내장 가사 또는 같은 폴더의 이름이 같은 LRC 파일을 읽습니다"
  ],
  "候选状态不可用，请重试。": [
    "Candidate status is unavailable. Please try again.",
    "候補の状態を取得できません。再試行してください。",
    "후보 상태를 확인할 수 없습니다. 다시 시도하세요."
  ],
  "当前没有可用的联网歌词来源，请检查歌词与歌源设置。": [
    "No online lyric sources are available. Check the lyrics and music source settings.",
    "利用可能なオンライン歌詞の取得元がありません。歌詞と音楽ソースの設定を確認してください。",
    "사용 가능한 온라인 가사 출처가 없습니다. 가사 및 음악 소스 설정을 확인하세요."
  ],
  "没有找到相关歌词候选，可检查歌曲标签后重试。": [
    "No matching lyrics were found. Check the song tags and try again.",
    "一致する歌詞候補がありません。曲のタグを確認して再試行してください。",
    "관련 가사 후보를 찾지 못했습니다. 곡 태그를 확인한 후 다시 시도하세요."
  ],
  "可用来源没有返回候选。": [
    "Available sources returned no candidates.",
    "利用可能な取得元から候補が返されませんでした。",
    "사용 가능한 출처에서 후보를 반환하지 않았습니다."
  ],
  "网": ["N", "N", "N"],
  "酷": ["K", "K", "K"],
  "来源：{0} · 匹配 {1}%": [
    "Source: {0} · Match {1}%",
    "取得元：{0} · 一致率 {1}%",
    "출처: {0} · 일치율 {1}%"
  ],
  "当前使用": ["Currently used", "現在使用中", "현재 사용 중"],
  "联网歌词为只读": [
    "Online lyrics are read-only",
    "オンライン歌詞は読み取り専用です",
    "온라인 가사는 읽기 전용입니다"
  ],
  "编辑本地歌词": ["Edit local lyrics", "ローカル歌詞を編集", "로컬 가사 편집"],
  "切换歌词对齐方向": ["Change lyric alignment", "歌詞の配置を変更", "가사 정렬 변경"],
  "增大歌词字体": ["Increase lyric font size", "歌詞の文字を大きく", "가사 글꼴 크기 늘리기"],
  "减小歌词字体": ["Decrease lyric font size", "歌詞の文字を小さく", "가사 글꼴 크기 줄이기"],
  "间奏": ["Instrumental", "間奏", "간주"],
  "正在加载歌词": ["Loading lyrics", "歌詞を読み込み中", "가사 불러오는 중"],
  "歌词加载失败，请切换来源或重试": [
    "Could not load lyrics. Change the source or try again.",
    "歌詞を読み込めませんでした。取得元を変えるか再試行してください。",
    "가사를 불러오지 못했습니다. 출처를 바꾸거나 다시 시도하세요."
  ],
  "无歌词": ["No lyrics", "歌詞なし", "가사 없음"],
  "无法跳转到该歌词：{0}": [
    "Could not seek to this lyric: {0}",
    "この歌詞の位置に移動できませんでした：{0}",
    "이 가사 위치로 이동하지 못했습니다: {0}"
  ],
  "歌词": ["Lyrics", "歌詞", "가사"],
  "歌曲评论 · 需要先关联平台歌曲": [
    "Song comments · Link a platform song first",
    "曲のコメント · 先にプラットフォームの曲を関連付けてください",
    "곡 댓글 · 먼저 플랫폼 곡을 연결하세요"
  ],
  "{0} 分钟后": ["In {0} minutes", "{0} 分後", "{0}분 후"],
  "播完当前歌曲后停止": ["Stop after the current song", "現在の曲が終わったら停止", "현재 곡이 끝나면 정지"],
  "取消倒计时（{0}）": ["Cancel timer ({0})", "タイマーを解除（{0}）", "타이머 취소({0})"],
  "睡眠定时": ["Sleep timer", "スリープタイマー", "취침 타이머"],
  "睡眠定时 {0}": ["Sleep timer {0}", "スリープタイマー {0}", "취침 타이머 {0}"],
  "开启桌面歌词": ["Enable desktop lyrics", "デスクトップ歌詞を表示", "데스크톱 가사 켜기"],
  "正在启动桌面歌词": ["Starting desktop lyrics", "デスクトップ歌詞を起動中", "데스크톱 가사 시작 중"],
  "桌面歌词已锁定；点击解锁": [
    "Desktop lyrics are locked; click to unlock",
    "デスクトップ歌詞はロック中です。クリックして解除",
    "데스크톱 가사가 잠겨 있습니다. 클릭하여 잠금 해제"
  ],
  "关闭桌面歌词": ["Disable desktop lyrics", "デスクトップ歌詞を閉じる", "데스크톱 가사 끄기"],
  "桌面歌词异常，正在恢复": [
    "Recovering desktop lyrics after an error",
    "デスクトップ歌詞の異常から復旧中",
    "데스크톱 가사 오류 복구 중"
  ],
  "桌面歌词启动失败；点击重试": [
    "Could not start desktop lyrics; click to retry",
    "デスクトップ歌詞を起動できませんでした。クリックして再試行",
    "데스크톱 가사를 시작하지 못했습니다. 클릭하여 다시 시도"
  ],
  "音量": ["Volume", "音量", "음량"],
  "播放模式；现在：{0}": ["Playback mode; current: {0}", "再生モード：{0}", "재생 모드, 현재: {0}"],
  "随机；现在：{0}": ["Shuffle; current: {0}", "シャッフル：{0}", "무작위 재생, 현재: {0}"],
  "上一曲": ["Previous track", "前の曲", "이전 곡"],
  "下一曲": ["Next track", "次の曲", "다음 곡"],
  "搜索本地曲库和联网音乐": [
    "Search local library and online music",
    "ローカルライブラリとオンライン音楽を検索",
    "로컬 라이브러리 및 온라인 음악 검색"
  ],
  "所有": ["All", "すべて", "전체"],
  "总乐库": ["Library", "ライブラリ", "라이브러리"],
  "联网": ["Online", "オンライン", "온라인"],
  "总乐库中没有匹配歌曲": [
    "No matching songs in your library",
    "ライブラリに一致する曲がありません",
    "라이브러리에 일치하는 곡이 없습니다"
  ],
  "在总乐库中定位": ["Locate in library", "ライブラリ内で表示", "라이브러리에서 찾기"],
  "没有匹配艺术家": ["No matching artists", "一致するアーティストがありません", "일치하는 아티스트가 없습니다"],
  "没有匹配专辑": ["No matching albums", "一致するアルバムがありません", "일치하는 앨범이 없습니다"],
  "联网音乐": ["Online music", "オンライン音楽", "온라인 음악"],
  "搜索已启用的联网歌源；播放能力由平台授权与接口可用性决定，当前不提供下载。": [
    "Search enabled online music sources. Playback depends on platform authorization and API availability. Downloads are currently unavailable.",
    "有効なオンライン音楽ソースを検索します。再生できるかどうかはプラットフォームの許可と API の可用性に依存します。現在、ダウンロードは利用できません。",
    "활성화된 온라인 음악 소스를 검색합니다. 재생 가능 여부는 플랫폼의 허가와 API 가용성에 따라 달라지며, 현재 다운로드는 제공하지 않습니다."
  ],
  "联网服务没有找到匹配歌曲": [
    "No matching songs were found online",
    "オンラインで一致する曲が見つかりませんでした",
    "온라인 서비스에서 일치하는 곡을 찾지 못했습니다"
  ],
  "联网搜索失败：{0}": [
    "Online search failed: {0}",
    "オンライン検索に失敗しました：{0}",
    "온라인 검색 실패: {0}"
  ],
  "自定义艺术家分隔符": [
    "Custom artist separators",
    "カスタムのアーティスト区切り文字",
    "사용자 지정 아티스트 구분자"
  ],
  "管理艺术家分隔符": ["Manage artist separators", "アーティストの区切り文字を管理", "아티스트 구분자 관리"],
  "新增": ["Add", "追加", "추가"],
  "确定": ["OK", "確定", "확인"],
  "选择自定义背景图片": [
    "Choose a custom background image",
    "カスタム背景画像を選択",
    "사용자 지정 배경 이미지 선택"
  ],
  "静态图片（PNG / JPEG / WebP / BMP）": [
    "Static images (PNG / JPEG / WebP / BMP)",
    "静止画像（PNG / JPEG / WebP / BMP）",
    "정적 이미지(PNG / JPEG / WebP / BMP)"
  ],
  "已为{0}保存背景副本，原图片未修改。": [
    "Saved a background copy for {0}. The original image is unchanged.",
    "{0}用の背景コピーを保存しました。元の画像は変更していません。",
    "{0}용 배경 사본을 저장했습니다. 원본 이미지는 수정하지 않았습니다."
  ],
  "无法读取或保存图片，请检查文件与目录权限。原背景未改变。": [
    "Could not read or save the image. Check file and folder permissions. The previous background is unchanged.",
    "画像の読み込みまたは保存に失敗しました。ファイルとフォルダーの権限を確認してください。以前の背景は変更していません。",
    "이미지를 읽거나 저장하지 못했습니다. 파일과 폴더 권한을 확인하세요. 기존 배경은 변경하지 않았습니다."
  ],
  "已清理 {0} 个未使用的背景副本；当前选择和原图片均保留。": [
    "Removed {0} unused background copies. The current selection and original images were kept.",
    "未使用の背景コピーを {0} 件削除しました。現在の選択と元の画像は保持しています。",
    "사용하지 않는 배경 사본 {0}개를 삭제했습니다. 현재 선택 항목과 원본 이미지는 유지했습니다."
  ],
  "清理背景副本失败，请检查已保存配置和目录权限。": [
    "Could not clean up background copies. Check saved settings and folder permissions.",
    "背景コピーを削除できませんでした。保存済みの設定とフォルダーの権限を確認してください。",
    "배경 사본을 정리하지 못했습니다. 저장된 설정과 폴더 권한을 확인하세요."
  ],
  "保存背景设置失败；当前选择仍对本次会话生效。": [
    "Could not save background settings. The current selection still applies to this session.",
    "背景設定を保存できませんでした。現在の選択は今回のセッションでは有効です。",
    "배경 설정을 저장하지 못했습니다. 현재 선택은 이번 세션에서 계속 적용됩니다."
  ],
  "背景与毛玻璃": ["Background and blur", "背景とすりガラス効果", "배경 및 블러"],
  "三个界面独立设置。主窗口的标题栏、侧栏和边缘共用背景；主内容面板保持清晰。": [
    "Set each of the three interfaces independently. The main window's title bar, sidebar and edges share a background; the main content stays clear.",
    "3つの画面を個別に設定します。メインウィンドウのタイトルバー・サイドバー・外周は背景を共有し、メインコンテンツは鮮明に保ちます。",
    "세 화면을 각각 설정합니다. 메인 창의 제목 표시줄, 사이드바, 가장자리는 배경을 공유하며 주요 콘텐츠는 선명하게 유지합니다."
  ],
  "使用实色背景，不显示桌面或专辑图片；再次开启会保留原来的参数。": [
    "Use a solid background without the desktop or album image. Your previous settings are retained when you enable it again.",
    "デスクトップやアルバム画像を表示せず、単色の背景を使用します。再び有効にすると以前の設定が適用されます。",
    "바탕 화면이나 앨범 이미지를 표시하지 않고 단색 배경을 사용합니다. 다시 켜면 기존 설정을 유지합니다."
  ],
  "随窗口后方的真实桌面变化，不随歌曲换封面。模糊半径由 Windows 管理。": [
    "Follow the real desktop behind the window, not the song artwork. Windows controls the blur radius.",
    "曲のジャケットではなく、ウィンドウ背後の実際のデスクトップを反映します。ぼかし半径は Windows が管理します。",
    "곡의 앨범 아트가 아닌 창 뒤의 실제 바탕 화면에 따라 바뀝니다. 블러 반경은 Windows에서 관리합니다."
  ],
  "随当前歌曲的专辑封面变化。仅模糊背景，歌曲封面、文字和按钮保持清晰。": [
    "Follow the current song's album artwork. Only the background is blurred; artwork, text and buttons stay clear.",
    "現在の曲のアルバムジャケットに合わせて変化します。背景だけをぼかし、ジャケット・文字・ボタンは鮮明に保ちます。",
    "현재 곡의 앨범 아트에 따라 바뀝니다. 배경만 흐리게 처리하며 앨범 아트, 텍스트, 버튼은 선명하게 유지합니다."
  ],
  "使用已导入的图片副本，不随歌曲切换；移动或删除原图片不影响此背景。": [
    "Use an imported image copy that does not change with the song. Moving or deleting the original image does not affect this background.",
    "読み込んだ画像のコピーを使用し、曲が変わっても変化しません。元の画像を移動・削除しても背景には影響しません。",
    "가져온 이미지 사본을 사용하며 곡이 바뀌어도 유지됩니다. 원본 이미지를 이동하거나 삭제해도 배경에 영향을 주지 않습니다."
  ],
  "背景透明度": ["Background opacity", "背景の不透明度", "배경 불투명도"],
  "数值越大，背景越明显；文字和按钮本身不会变透明。": [
    "Higher values make the background more visible. Text and buttons do not become transparent.",
    "値を大きくすると背景がよりはっきり表示されます。文字やボタン自体は透明になりません。",
    "값이 클수록 배경이 더 뚜렷해집니다. 텍스트와 버튼 자체는 투명해지지 않습니다."
  ],
  "背景透明度 {0}%": ["Background opacity {0}%", "背景の不透明度 {0}%", "배경 불투명도 {0}%"],
  "图片模糊强度": ["Image blur strength", "画像のぼかし強度", "이미지 블러 강도"],
  "封面模糊强度": ["Artwork blur strength", "ジャケットのぼかし強度", "앨범 아트 블러 강도"],
  "数值越大越柔和；调整不会降低前景专辑封面的清晰度。": [
    "Higher values create a softer background without reducing foreground artwork clarity.",
    "値を大きくすると背景が柔らかくなります。手前のアルバムジャケットの鮮明さは変わりません。",
    "값이 클수록 배경이 부드러워지며 전경의 앨범 아트 선명도는 떨어지지 않습니다."
  ],
  "封面模糊强度 {0}": [
    "Artwork blur strength {0}",
    "ジャケットのぼかし強度 {0}",
    "앨범 아트 블러 강도 {0}"
  ],
  "轻缓动态背景": ["Gentle background motion", "ゆるやかな背景アニメーション", "부드러운 배경 움직임"],
  "让背景图片缓慢漂移。暂停、窗口隐藏或减少动态效果时停止；不会移动文字与按钮。": [
    "Let the background drift slowly. It stops when playback is paused, the window is hidden or reduced motion is enabled. Text and buttons do not move.",
    "背景画像をゆっくり動かします。一時停止中、ウィンドウ非表示時、動きを減らす設定の有効時には停止します。文字やボタンは動きません。",
    "배경 이미지가 천천히 움직입니다. 재생 일시 정지, 창 숨김 또는 동작 줄이기 설정 시 멈추며 텍스트와 버튼은 움직이지 않습니다."
  ],
  "仅适用于专辑封面或自定义图片，不改变真实窗后背景。": [
    "Applies only to album artwork or custom images, not the real background behind the window.",
    "アルバムジャケットとカスタム画像にのみ適用します。実際のウィンドウ背後の背景は変更しません。",
    "앨범 아트나 사용자 지정 이미지에만 적용되며 창 뒤의 실제 배경은 바꾸지 않습니다."
  ],
  "{0}。高对比度或系统不支持时自动使用实色。": [
    "{0}. A solid background is used in high contrast mode or on unsupported systems.",
    "{0}。ハイコントラスト時やシステムが非対応の場合は自動的に単色背景を使用します。",
    "{0}. 고대비 모드이거나 시스템에서 지원하지 않으면 단색 배경을 자동으로 사용합니다."
  ],
  "背景来源与“专辑封面动态配色”分别控制。高对比度模式会关闭模糊。": [
    "Background source and dynamic artwork colors are separate settings. High contrast mode disables blur.",
    "背景の取得元と「ジャケットに合わせた配色」は別々の設定です。ハイコントラストではぼかしを無効にします。",
    "배경 출처와 ‘앨범 아트 동적 색상’은 별도로 설정합니다. 고대비 모드에서는 블러를 끕니다."
  ],
  "还原{0}默认背景": [
    "Restore the default background for {0}",
    "{0}の既定の背景に戻す",
    "{0} 기본 배경 복원"
  ],
  "已导入的背景": ["Imported background", "読み込み済みの背景", "가져온 배경"],
  "更换自定义图片": ["Change custom image", "カスタム画像を変更", "사용자 지정 이미지 변경"],
  "选择自定义图片": ["Choose custom image", "カスタム画像を選択", "사용자 지정 이미지 선택"],
  "移除图片选择": ["Remove image selection", "画像の選択を解除", "이미지 선택 해제"],
  "清理未使用副本": ["Clean up unused copies", "未使用のコピーを削除", "사용하지 않는 사본 정리"],
  "支持静态 PNG、JPEG、WebP、BMP，最多 20 MiB / 4000 万像素。背景副本最长边 2048 像素，不修改原图或前景封面。": [
    "Supports static PNG, JPEG, WebP and BMP images up to 20 MiB / 40 megapixels. Background copies have a maximum edge of 2048 pixels. Original images and foreground artwork are not modified.",
    "静止画像の PNG・JPEG・WebP・BMP に対応（最大 20 MiB / 4000万画素）。背景コピーの長辺は最大 2048 ピクセルです。元の画像や手前のジャケットは変更しません。",
    "정적 PNG, JPEG, WebP, BMP 이미지를 최대 20 MiB / 4,000만 픽셀까지 지원합니다. 배경 사본의 긴 변은 최대 2048픽셀이며 원본 이미지와 전경 앨범 아트는 수정하지 않습니다."
  ],
  "背景副本不可用，请重新选择图片。": [
    "The background copy is unavailable. Select the image again.",
    "背景コピーを使用できません。画像を選択し直してください。",
    "배경 사본을 사용할 수 없습니다. 이미지를 다시 선택하세요."
  ],
  "正在读取背景副本…": ["Loading background copy…", "背景コピーを読み込み中…", "배경 사본 불러오는 중…"],
  "当前已是最新稳定版": [
    "You have the latest stable version",
    "最新の安定版です",
    "현재 최신 안정 버전입니다"
  ],
  "发现稳定版 {0}": [
    "Stable version {0} is available",
    "安定版 {0} が見つかりました",
    "안정 버전 {0}이 있습니다"
  ],
  "查看": ["View", "表示", "보기"],
  "检查更新失败，请稍后重试": [
    "Could not check for updates. Please try again later.",
    "更新を確認できませんでした。後でもう一度お試しください。",
    "업데이트를 확인하지 못했습니다. 나중에 다시 시도하세요."
  ],
  "已阻止不安全的外部链接": [
    "An unsafe external link was blocked",
    "安全でない外部リンクをブロックしました",
    "안전하지 않은 외부 링크를 차단했습니다"
  ],
  "无法打开链接": ["Could not open link", "リンクを開けませんでした", "링크를 열지 못했습니다"],
  "自动检查稳定版更新（每天最多一次）": [
    "Automatically check for stable updates (at most once a day)",
    "安定版の更新を自動確認（1日1回まで）",
    "안정 버전 업데이트 자동 확인(하루 최대 한 번)"
  ],
  "立即检查": ["Check now", "今すぐ確認", "지금 확인"],
  "当前版本：{0}": ["Current version: {0}", "現在のバージョン：{0}", "현재 버전: {0}"],
  "上次检查：{0}": ["Last checked: {0}", "前回の確認：{0}", "마지막 확인: {0}"],
  "更新包下载失败，请稍后重试": [
    "Could not download the update. Please try again later.",
    "更新パッケージをダウンロードできませんでした。後でもう一度お試しください。",
    "업데이트 패키지를 다운로드하지 못했습니다. 나중에 다시 시도하세요."
  ],
  "无法打开资源管理器": [
    "Could not open File Explorer",
    "エクスプローラーを開けませんでした",
    "파일 탐색기를 열지 못했습니다"
  ],
  "稳定版 {0}{1}": ["Stable version {0}{1}", "安定版 {0}{1}", "안정 버전 {0}{1}"],
  "此版本没有提供更新说明。": [
    "No release notes were provided for this version.",
    "このバージョンには更新内容の説明がありません。",
    "이 버전에는 릴리스 노트가 제공되지 않았습니다."
  ],
  "正在准备下载…": ["Preparing download…", "ダウンロードを準備中…", "다운로드 준비 중…"],
  "已下载 {0}{1}": ["Downloaded {0}{1}", "ダウンロード済み {0}{1}", "다운로드됨 {0}{1}"],
  "下载完成，SHA-256 校验通过。请从资源管理器启动安装包。": [
    "Download complete. SHA-256 verification passed. Launch the installer from File Explorer.",
    "ダウンロードが完了し、SHA-256 検証に成功しました。エクスプローラーからインストーラーを起動してください。",
    "다운로드가 완료되었으며 SHA-256 검증을 통과했습니다. 파일 탐색기에서 설치 프로그램을 실행하세요."
  ],
  "下载完成；发布者未提供校验文件。为安全起见不会自动执行，请在资源管理器中确认后安装。": [
    "Download complete. The publisher did not provide a checksum file. For safety, it will not run automatically. Verify it in File Explorer before installing.",
    "ダウンロードが完了しました。公開元がチェックサムファイルを提供していないため、安全のため自動実行しません。エクスプローラーで確認してからインストールしてください。",
    "다운로드가 완료되었습니다. 게시자가 체크섬 파일을 제공하지 않았으므로 안전을 위해 자동 실행하지 않습니다. 파일 탐색기에서 확인한 후 설치하세요."
  ],
  "忽略此版本": ["Skip this version", "このバージョンをスキップ", "이 버전 건너뛰기"],
  "显示安装包": ["Show installer", "インストーラーを表示", "설치 파일 표시"],
  "打开发布页": ["Open release page", "リリースページを開く", "릴리스 페이지 열기"],
  "下载更新": ["Download update", "更新をダウンロード", "업데이트 다운로드"],
  "在 GitHub 查看": ["View on GitHub", "GitHub で見る", "GitHub에서 보기"],
  "取消下载": ["Cancel download", "ダウンロードを中止", "다운로드 취소"],
  "稍后": ["Later", "後で", "나중에"],
  "报告问题": ["Report an issue", "問題を報告", "문제 신고"],
  "创建问题": ["Create issue", "Issue を作成", "이슈 만들기"],
  "## 描述": ["## Description", "## 説明", "## 설명"],
  "## 日志": ["## Logs", "## ログ", "## 로그"],
  "已打开 GitHub 问题页面": [
    "Opened the GitHub issue page",
    "GitHub の Issue ページを開きました",
    "GitHub 이슈 페이지를 열었습니다"
  ],
  "描述": ["Description", "説明", "설명"],
  "日志": ["Logs", "ログ", "로그"],
  "你可以随意修改日志内容。": [
    "You can edit the log contents freely.",
    "ログの内容は自由に編集できます。",
    "로그 내용을 자유롭게 수정할 수 있습니다."
  ],
  "保存桌面设置失败；当前选择仍对本次会话生效。": [
    "Could not save desktop settings. The current selection still applies to this session.",
    "デスクトップ設定を保存できませんでした。現在の選択は今回のセッションでは有効です。",
    "데스크톱 설정을 저장하지 못했습니다. 현재 선택은 이번 세션에서 계속 적용됩니다."
  ],
  "关闭窗口后在后台继续播放": [
    "Keep playing in the background after closing the window",
    "ウィンドウを閉じてもバックグラウンドで再生を続ける",
    "창을 닫아도 백그라운드에서 계속 재생"
  ],
};
