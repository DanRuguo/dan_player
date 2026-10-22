const catalogLyricPlaybackTools = <String, List<String>>{
  '调整模糊': ['Adjust blur', 'ぼかしの調整', '흐림 조정'],
  '启用歌词模糊': ['Enable lyric blur', '歌詞のぼかしを有効にする', '가사 흐림 사용'],
  '上方模糊范围': ['Top blur range', '上部のぼかし範囲', '위쪽 흐림 범위'],
  '下方模糊范围': ['Bottom blur range', '下部のぼかし範囲', '아래쪽 흐림 범위'],
  '清晰区域': ['Clear area', '鮮明な領域', '선명한 영역'],
  '上方模糊区域': ['Top blurred area', '上部のぼかし領域', '위쪽 흐림 영역'],
  '下方模糊区域': ['Bottom blurred area', '下部のぼかし領域', '아래쪽 흐림 영역'],
  '模糊区域预览': ['Blur area preview', 'ぼかし領域のプレビュー', '흐림 영역 미리 보기'],
  '拖动滑块调整上方和下方的模糊范围。': [
    'Drag the sliders to adjust the top and bottom blur ranges.',
    'スライダーを動かして上下のぼかし範囲を調整します。',
    '슬라이더를 끌어 위쪽과 아래쪽의 흐림 범위를 조정하세요.'
  ],
  '歌词字间距保存失败；本次会话仍然生效。': [
    'Could not save lyric letter spacing; it remains active for this session.',
    '歌詞の文字間隔を保存できませんでした。このセッションには適用されています。',
    '가사 글자 간격을 저장하지 못했습니다. 현재 세션에는 계속 적용됩니다.'
  ],
  '歌词字间距': ['Lyric letter spacing', '歌詞の文字間隔', '가사 글자 간격'],
  '音乐伴每一天': ['Music every day', '音楽のある毎日', '음악과 함께'],
  '增加主歌词、桌面歌词和任务栏歌词的自然字距；0 保持原样。': [
    'Add spacing to player, desktop and taskbar lyrics; 0 preserves natural spacing.',
    'プレーヤー・デスクトップ・タスクバーの歌詞に文字間隔を追加します。0 は元の間隔です。',
    '플레이어·바탕 화면·작업 표시줄 가사의 글자 간격을 늘립니다. 0은 원래 간격을 유지합니다.'
  ],
  '恢复默认字间距': ['Reset letter spacing', '文字間隔を既定に戻す', '기본 글자 간격으로 복원'],
  '自动生成日语假名': [
    'Generate Japanese readings automatically',
    '日本語の読み仮名を自動生成',
    '일본어 읽기 자동 생성'
  ],
  '优先显示已缓存的假名；未缓存时，自动联网开启则优先联网并在失败时回退离线，关闭则使用离线字典。保留已有注音和原歌词。': [
    'Show cached readings first. Without a cache, automatic networking prefers online generation with offline fallback; otherwise use the offline dictionary. Keep existing readings and original lyrics.',
    '保存済みの読み仮名を優先表示します。未保存の場合、自動通信が有効ならオンライン生成を優先し、失敗時はオフラインに切り替えます。無効時はオフライン辞書を使用します。既存の読みと元の歌詞は保持します。',
    '캐시된 읽기를 먼저 표시합니다. 캐시가 없고 자동 네트워크가 켜져 있으면 온라인 생성 후 실패 시 오프라인으로 전환합니다. 꺼져 있으면 오프라인 사전을 사용합니다. 기존 읽기와 원본 가사는 유지합니다.'
  ],
  '自动联网已关闭，可在阅读工具勾选显示日语假名；联网生成与字典安装请使用下方设置。': [
    'Automatic networking is off. Enable Show Japanese readings in the reading tools; use the settings below for online generation and dictionary installation.',
    '自動通信は無効です。読書ツールで「日本語の読み仮名を表示」を有効にできます。オンライン生成と辞書のインストールには下の設定を使用してください。',
    '자동 네트워크가 꺼져 있습니다. 읽기 도구에서 일본어 읽기 표시를 켤 수 있습니다. 온라인 생성과 사전 설치는 아래 설정을 사용하세요.'
  ],
  '生成方式': ['Generation method', '生成方法', '생성 방식'],
  '日语假名生成方式': ['Japanese reading method', '読み仮名の生成方法', '일본어 읽기 생성 방식'],
  '无法打开网页，请复制链接后重试。': [
    'Could not open the page. Copy the link and retry.',
    'ページを開けませんでした。リンクをコピーして再試行してください。',
    '페이지를 열지 못했습니다. 링크를 복사하여 다시 시도하세요.'
  ],
  '联网生成': ['Generate online', 'オンライン生成', '온라인 생성'],
  '离线生成': ['Generate offline', 'オフライン生成', '오프라인 생성'],
  '生成': ['Generate', '生成', '생성'],
  '日语假名字典组件': ['Japanese reading dictionary', '読み仮名辞書', '일본어 읽기 사전'],
  '按需下载假名字典和许可文件；离线分析不会上传歌词。': [
    'Download the reading dictionary and licenses when needed. Offline analysis does not upload lyrics.',
    '必要な時に読み仮名辞書とライセンスをダウンロードします。オフライン解析では歌詞を送信しません。',
    '필요할 때 읽기 사전과 라이선스를 다운로드합니다. 오프라인 분석은 가사를 업로드하지 않습니다.'
  ],
  '手动安装：从播放器发布页下载字典组件，解压到此目录，保留许可文件。': [
    'Manual installation: download the dictionary from the player release page and extract it into this folder, keeping the licenses.',
    '手動インストール：プレーヤーのリリースページから辞書をダウンロードし、このフォルダーに展開してください。ライセンスも保持してください。',
    '수동 설치: 플레이어 릴리스 페이지에서 사전을 다운로드하여 이 폴더에 압축을 풀고 라이선스 파일을 유지하세요.'
  ],
  '字典组件仍不可用。请检查下载、文件完整性和目录权限，或手动安装后重试。': [
    'The dictionary is still unavailable. Check the download, file integrity and folder permissions, or install it manually and retry.',
    '辞書を利用できません。ダウンロード・ファイルの整合性・フォルダーの権限を確認するか、手動でインストールして再試行してください。',
    '사전을 아직 사용할 수 없습니다. 다운로드, 파일 무결성과 폴더 권한을 확인하거나 수동으로 설치한 후 다시 시도하세요.'
  ],
  '字典组件已就绪；点击“开始生成”。': [
    'The dictionary is ready. Click Start generating.',
    '辞書の準備ができました。「生成を開始」を押してください。',
    '사전이 준비되었습니다. 생성 시작을 누르세요.'
  ],
  '联网假名注音': ['Online Japanese readings', 'オンライン読み仮名', '온라인 일본어 읽기'],
  '需要您自己的 Yahoo! JAPAN Client ID；自动联网开启时优先使用，失败时回退离线。': [
    'Requires your own Yahoo! JAPAN Client ID. Prefer online when automatic networking is on; fall back offline on failure.',
    'ご自身の Yahoo! JAPAN Client ID が必要です。自動通信が有効ならオンラインを優先し、失敗時はオフラインに切り替えます。',
    '본인의 Yahoo! JAPAN Client ID가 필요합니다. 자동 네트워크가 켜져 있으면 온라인을 우선하며 실패하면 오프라인으로 전환합니다.'
  ],
  '配置联网注音': ['Configure online readings', 'オンラインの読みを設定', '온라인 읽기 설정'],
  '需要您自己的 Yahoo! JAPAN Client ID': [
    'Requires your own Yahoo! JAPAN Client ID',
    'ご自身の Yahoo! JAPAN Client ID が必要です',
    '본인의 Yahoo! JAPAN Client ID가 필요합니다'
  ],
  '自动联网开启时优先使用，失败时回退离线。': [
    'Preferred when automatic networking is on; fall back offline if it fails.',
    '自動通信が有効なら優先し、失敗時はオフラインに切り替えます。',
    '자동 네트워크가 켜져 있으면 우선 사용하고 실패하면 오프라인으로 전환합니다.'
  ],
  'Yahoo! JAPAN Client ID': [
    'Yahoo! JAPAN Client ID',
    'Yahoo! JAPAN Client ID',
    'Yahoo! JAPAN Client ID'
  ],
  '仅保存在本机，用于您主动或允许的日语假名请求。': [
    'Saved locally, for Japanese reading requests you initiate or permit.',
    'この端末に保存し、手動または許可された読み仮名のリクエストに使用します。',
    '이 기기에 저장되며 직접 시작하거나 허용한 일본어 읽기 요청에 사용됩니다.'
  ],
  '申请 Client ID': ['Get a Client ID', 'Client ID を取得', 'Client ID 발급'],
  '显示 Client ID': ['Show Client ID', 'Client ID を表示', 'Client ID 표시'],
  '隐藏 Client ID': ['Hide Client ID', 'Client ID を隠す', 'Client ID 숨기기'],
  'Client ID 只能包含不带空格的 ASCII 字符，最多 2048 个字符。': [
    'Client ID must contain ASCII characters without spaces, up to 2048 characters.',
    'Client ID は空白なしの ASCII 文字で、最大 2048 文字です。',
    'Client ID는 공백 없는 ASCII 문자여야 하며 최대 2048자입니다.'
  ],
  '联网注音设置保存失败': [
    'Could not save online reading settings',
    'オンラインの読み設定を保存できませんでした',
    '온라인 읽기 설정을 저장하지 못했습니다'
  ],
  '当前输入已保留，请重试。': [
    'Your input is retained. Please retry.',
    '入力は保持しています。再試行してください。',
    '입력을 유지했습니다. 다시 시도하세요.'
  ],
  '仅处理播放器已缓存的日语歌词，不修改原歌词和已有注音；注音遵循“自动联网”设置，失败时回退离线。': [
    'Process only Japanese lyrics already cached by the player. Keep originals and existing readings; follow automatic networking settings and fall back offline on failure.',
    'プレーヤーに保存済みの日本語歌詞だけを処理し、元の歌詞と既存の読みを保持します。自動通信の設定に従い、失敗時はオフラインに切り替えます。',
    '플레이어에 캐시된 일본어 가사만 처리하고 원본과 기존 읽기를 유지합니다. 자동 네트워크 설정을 따르며 실패하면 오프라인으로 전환합니다.'
  ],
  '批量生成日语假名': [
    'Generate Japanese readings in bulk',
    '読み仮名を一括生成',
    '일본어 읽기 일괄 생성'
  ],
  '仅为播放器已缓存的日语歌词补充缺少的读音；保留原歌词和已有注音，不联网，也不读取音乐文件标签。': [
    'Add readings to Japanese lyrics already cached by the player. Keep original lyrics and existing readings; no network or audio-tag reads.',
    'プレーヤーに保存済みの日本語歌詞に読みを補います。元の歌詞と既存の読みを保持し、通信や音楽ファイルのタグ読み取りは行いません。',
    '플레이어에 캐시된 일본어 가사에 읽기를 추가합니다. 원본 가사와 기존 읽기를 유지하며 네트워크와 음악 파일 태그를 읽지 않습니다.'
  ],
  '打开批量生成': ['Open bulk generation', '一括生成を開く', '일괄 생성 열기'],
  '开始生成': ['Start generating', '生成を開始', '생성 시작'],
  '已处理 {0}/{1} · 生成 {2} · 跳过 {3} · 失败 {4}': [
    'Processed {0}/{1} · Generated {2} · Skipped {3} · Failed {4}',
    '処理 {0}/{1} · 生成 {2} · スキップ {3} · 失敗 {4}',
    '처리 {0}/{1} · 생성 {2} · 건너뜀 {3} · 실패 {4}'
  ],
  '开始后扫描已缓存歌词；可随时取消。': [
    'Scan saved lyric caches after starting. Cancel at any time.',
    '開始後に保存済みの歌詞を調べます。いつでもキャンセルできます。',
    '시작하면 저장된 가사 캐시를 확인합니다. 언제든 취소할 수 있습니다.'
  ],
  '正在读取已缓存歌词…': ['Reading cached lyrics…', '保存済みの歌詞を読み取り中…', '캐시된 가사 읽는 중…'],
  '正在批量生成日语假名…': [
    'Generating Japanese readings in bulk…',
    '読み仮名を一括生成中…',
    '일본어 읽기 일괄 생성 중…'
  ],
  '正在取消假名生成…': [
    'Cancelling reading generation…',
    '読み仮名の生成を中止中…',
    '읽기 생성 취소 중…'
  ],
  '已取消，已生成的假名缓存会保留。': [
    'Cancelled. Completed reading caches are retained.',
    '中止しました。生成済みの読みのキャッシュは保持します。',
    '취소했습니다. 생성된 읽기 캐시는 유지됩니다.'
  ],
  '批量生成日语假名完成': [
    'Bulk Japanese reading generation finished',
    '読み仮名の一括生成が完了しました',
    '일본어 읽기 일괄 생성 완료'
  ],
  '读取缓存失败，请重试。': [
    'Could not read caches. Please retry.',
    'キャッシュを読み取れませんでした。再試行してください。',
    '캐시를 읽지 못했습니다. 다시 시도하세요.'
  ],
  '需要日语假名字典组件': [
    'Japanese reading dictionary required',
    '読み仮名辞書が必要です',
    '일본어 읽기 사전 필요'
  ],
  '正在下载日语假名字典…': [
    'Downloading Japanese reading dictionary…',
    '読み仮名辞書をダウンロード中…',
    '일본어 읽기 사전 다운로드 중…'
  ],
  '正在校验并安装字典…': [
    'Verifying and installing dictionary…',
    '辞書を検証・インストール中…',
    '사전 확인 및 설치 중…'
  ],
  '离线补充缺少的日语读音；保留已有注音，不联网，也不修改原歌词。': [
    'Fill missing Japanese readings offline. Keep existing readings and original lyrics; no network requests.',
    '不足する日本語の読みをオフラインで補います。既存の読みと元の歌詞を保持し、通信は行いません。',
    '누락된 일본어 읽기를 오프라인으로 보충합니다. 기존 읽기와 원본 가사를 유지하며 네트워크를 사용하지 않습니다.'
  ],
  '生成当前歌词日语假名': [
    'Generate Japanese readings for these lyrics',
    '現在の歌詞の読み仮名を生成',
    '현재 가사의 일본어 읽기 생성'
  ],
  '正在生成日语假名': ['Generating Japanese readings', '読み仮名を生成中', '일본어 읽기 생성 중'],
  '显示日语假名': ['Show Japanese readings', '読み仮名を表示', '일본어 읽기 표시'],
  '生成日语假名': ['Generate Japanese readings', '日本語の読み仮名を生成', '일본어 가나 생성'],
  '请在设置中安装日语假名字典组件': [
    'Install the Japanese reading dictionary in settings',
    '設定で読み仮名辞書をインストールしてください',
    '설정에서 일본어 읽기 사전을 설치하세요'
  ],
  '正在排序歌曲…': ['Sorting songs…', '曲を並べ替え中…', '노래 정렬 중…'],
  '当前无法生成日语假名，请稍后重试': [
    'Japanese readings are currently unavailable. Please retry later.',
    '現在、読み仮名を生成できません。しばらくしてから再試行してください。',
    '현재 일본어 읽기를 생성할 수 없습니다. 나중에 다시 시도하세요.'
  ],
  '已补充日语假名': ['Japanese readings added', '読み仮名を補いました', '일본어 읽기를 추가했습니다'],
  '已有读音，或没有可补充的日语歌词': [
    'Readings already exist, or no Japanese lyrics need them',
    '既存の読みがあるか、補う日本語の歌詞がありません',
    '읽기가 이미 있거나 보충할 일본어 가사가 없습니다'
  ],
  '当前系统无法离线生成日语假名': [
    'Offline Japanese readings are unavailable on this system',
    'このシステムでは読み仮名をオフライン生成できません',
    '이 시스템에서는 오프라인 일본어 읽기를 생성할 수 없습니다'
  ],
  '歌词过长，无法一次生成日语假名': [
    'These lyrics are too long to generate readings in one operation',
    '歌詞が長すぎるため、一度に読み仮名を生成できません',
    '가사가 너무 길어 한 번에 일본어 읽기를 생성할 수 없습니다'
  ],
  '歌曲过渡': ['Track transitions', '曲の切り替え', '곡 전환'],
  '跳过头尾静音': [
    'Skip leading and trailing silence',
    '曲の前後の無音をスキップ',
    '곡 앞뒤 무음 건너뛰기'
  ],
  '下次加载本地歌曲生效；仅分析头尾，保留声音边缘，不改原文件或总时长。': [
    'Applies to the next local track load. Analyses only the edges, preserves sound boundaries, and keeps the file and total duration unchanged.',
    '次のローカル曲の読み込みから適用します。曲の前後だけを解析し、音の端を残します。元ファイルと総時間は変更しません。',
    '다음 로컬 곡을 불러올 때 적용됩니다. 곡의 앞뒤만 분석하고 소리의 경계를 보존하며, 원본 파일과 전체 길이는 변경하지 않습니다.'
  ],
  '静音阈值': ['Silence threshold', '無音のしきい値', '무음 기준값'],
  '每端最多分析': ['Maximum scan per edge', '前後それぞれの解析上限', '각 끝의 최대 분석 시간'],
  '手动定位、A–B 练习或切换输出后，本曲恢复完整范围。在线音频、CUE、短曲、无法精确定位的格式和无法确认的静音边界保持原样；分析超时会回退。启用时自动过渡采用常规切换。':
      [
    'Seeking, A–B practice or changing the output restores the full track. Online audio, CUE segments, short tracks, formats without precise seeking and uncertain boundaries stay unchanged; analysis timeouts fall back. Automatic transitions use Standard while enabled.',
    '手動シーク・A–B 練習・出力の切り替え後は、この曲の再生範囲を元に戻します。オンライン音源・CUE 分割曲・短い曲・正確にシークできない形式・不確かな境界は変更せず、解析タイムアウト時も通常再生します。有効時の自動切り替えは通常方式です。',
    '수동 탐색, A–B 연습 또는 출력 변경 후 현재 곡의 전체 범위를 복원합니다. 온라인 음원, CUE 분할 곡, 짧은 곡, 정확한 탐색이 불가능한 형식과 불확실한 경계는 그대로 유지하며 분석 시간 초과 시 일반 재생합니다. 활성화하면 자동 전환은 일반 방식을 사용합니다.'
  ],
  '无法将音频接入输出（BASS 错误码 {0}）': [
    'Could not connect audio to the output (BASS error {0})',
    '音声を出力に接続できませんでした（BASS エラー {0}）',
    '오디오를 출력에 연결하지 못했습니다(BASS 오류 {0})'
  ],
  '常规切换': ['Standard', '通常', '일반 전환'],
  '连续输出': ['Continuous output', '連続出力', '연속 출력'],
  '交叉淡入淡出': ['Crossfade', 'クロスフェード', '크로스페이드'],
  '同专辑保持连续输出': ['Keep album tracks continuous', '同じアルバムは連続再生', '같은 앨범은 연속 재생'],
  '自动播放同一专辑时保留曲目衔接，跨专辑仍淡入淡出。专辑名或艺术家信息不完整时沿用淡入淡出。': [
    'Preserve transitions within an album during automatic playback, while crossfading between albums. Crossfade still applies when the album title or artist is missing.',
    '自動再生で同じアルバムの曲のつながりを保ち、別のアルバムへはクロスフェードします。アルバム名またはアーティストが不明な場合もクロスフェードします。',
    '자동 재생 시 같은 앨범 안에서는 곡 사이의 연결을 유지하고, 다른 앨범으로 넘어갈 때는 크로스페이드합니다. 앨범명이나 아티스트 정보가 없으면 크로스페이드를 유지합니다.'
  ],
  '下次加载歌曲生效。连续输出预先准备当前队列的下一首本地歌曲；手动切歌、定位、A–B 循环和停止目标沿用原行为。': [
    'Applies when a track is next loaded. Continuous output prepares the next local track in the queue. Manual changes, seeking, A–B loops and stop targets retain their behavior.',
    '次の曲の読み込みから適用します。連続出力はキュー内の次のローカル曲を準備します。手動切り替え・シーク・A–B リピート・停止指定は従来どおりです。',
    '다음 곡을 불러올 때 적용됩니다. 연속 출력은 대기열의 다음 로컬 곡을 준비합니다. 수동 전환·탐색·A–B 반복·정지 목표는 기존 동작을 유지합니다.'
  ],
  '淡入淡出时长：{0} 秒': [
    'Crossfade duration: {0} s',
    'フェード時間：{0} 秒',
    '크로스페이드 길이: {0}초'
  ],
  '仅共享输出混合两曲；独占输出使用连续接续。短曲自动缩短过渡，在线音频、CUE 分轨或未能预备的歌曲使用常规切换。': [
    'Mixes tracks in shared output only; exclusive output uses continuous sequencing. Short tracks reduce the fade. Online audio, CUE segments and unprepared tracks use standard transitions.',
    '共有出力のみで曲をミックスし、排他出力では連続再生します。短い曲はフェードを短縮します。オンライン音源・CUE 分割曲・準備できなかった曲は通常切り替えです。',
    '공유 출력에서만 두 곡을 혼합하며 독점 출력에서는 연속 재생합니다. 짧은 곡은 전환 시간을 줄입니다. 온라인 음원·CUE 분할 곡·준비하지 못한 곡은 일반 전환을 사용합니다.'
  ],
  '设置保存失败，请重试': [
    'Could not save settings. Please retry.',
    '設定を保存できませんでした。再試行してください。',
    '설정을 저장하지 못했습니다. 다시 시도하세요.'
  ],
  '阅读工具可调整歌词字间距并勾选显示日语假名，主歌词与桌面歌词共用。优先显示有效缓存；未缓存时，自动联网开启则优先联网并在失败时回退离线，否则使用离线字典。联网配置、字典安装与批量生成位于设置。':
      [
    'Adjust lyric letter spacing and toggle Japanese readings in the reading tools, shared by player and desktop. Show valid cached readings first. Without a cache, automatic networking prefers online generation with offline fallback; otherwise use the offline dictionary. Network configuration, dictionary installation and batch generation are in settings.',
    '読書ツールで文字間隔と読み仮名の表示を変更でき、プレーヤーとデスクトップで共有します。有効な保存済みの読みを優先表示します。未保存で自動通信が有効ならオンライン生成を優先し、失敗時はオフラインに切り替えます。無効時はオフライン辞書を使用します。通信の設定・辞書のインストール・一括生成は設定にあります。',
    '읽기 도구에서 가사 글자 간격과 일본어 읽기 표시를 변경하며 플레이어와 바탕 화면이 공유합니다. 유효한 캐시를 먼저 표시합니다. 캐시가 없고 자동 네트워크가 켜져 있으면 온라인 생성 후 실패 시 오프라인으로 전환하며, 꺼져 있으면 오프라인 사전을 사용합니다. 네트워크 설정·사전 설치·일괄 생성은 설정에 있습니다.'
  ],
  '联网注音需要您自己的 Yahoo! JAPAN Client ID；离线词典缺失时可手动安装组件，也可在设置中批量处理已缓存歌词。生成假名按汉字位置显示并存入独立缓存，保留原歌词和已有注音；自动读音仅供参考。':
      [
    'Online readings require your own Yahoo! JAPAN Client ID. Install the offline dictionary in settings, where cached lyrics can also be processed in bulk. Readings align with Han characters and use a separate cache, preserving originals and existing annotations. Generated readings are a reference.',
    'オンラインの読みにはご自身の Yahoo! JAPAN Client ID が必要です。辞書がなければコンポーネントをインストールできます。設定では保存済みの歌詞を一括処理できます。読みを漢字の位置に表示し、独立したキャッシュに保存します。元の歌詞と既存の読みは保持し、自動の読みは参考用です。',
    '온라인 읽기에는 본인의 Yahoo! JAPAN Client ID가 필요합니다. 사전이 없으면 구성 요소를 설치하세요. 설정에서 캐시된 가사를 일괄 처리할 수 있습니다. 읽기는 한자 위치에 표시하고 별도 캐시에 저장하며 원본 가사와 기존 주석을 유지합니다. 자동 읽기는 참고용입니다.'
  ],
  '在“曲库与播放 → 歌曲过渡”选择常规切换、连续输出或交叉淡入淡出，下次加载歌曲生效。连续输出预备已有的下一首本地歌曲；淡入淡出仅在共享输出混合两曲。暂停、定位、循环与停止目标优先，未能预备时沿用常规切换。':
      [
    'Choose Standard, Continuous output or Crossfade under Library & playback → Track transitions; it applies at the next track load. Continuous output prepares the known next local track. Crossfade mixes tracks in shared output. Pause, seeking, loops and stop targets take priority; unprepared tracks use standard transitions.',
    '「ライブラリと再生 → 曲の切り替え」で通常・連続出力・クロスフェードを選択し、次の曲の読み込みから適用します。連続出力は既知の次のローカル曲を準備し、クロスフェードは共有出力でミックスします。一時停止・シーク・リピート・停止指定を優先し、準備できない曲は通常切り替えです。',
    '라이브러리와 재생 → 곡 전환에서 일반 전환·연속 출력·크로스페이드를 선택하면 다음 곡을 불러올 때 적용됩니다. 연속 출력은 정해진 다음 로컬 곡을 준비하며 크로스페이드는 공유 출력에서 혼합합니다. 일시 정지·탐색·반복·정지 목표를 우선하며 준비하지 못한 곡은 일반 전환을 사용합니다.'
  ],
};
