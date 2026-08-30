// Shared UI metadata labels and the language selector. Media tags remain raw.
const Map<String, List<String>> uiCatalogD = {
  '页面视图': ['Page view', '表示形式', '페이지 보기'],
  '列表': ['List', 'リスト', '목록'],
  '网格': ['Grid', 'グリッド', '격자'],
  '界面语言': ['Interface language', '表示言語', '인터페이스 언어'],
  '窗口尺寸锁定设置暂未应用，可在“设置 > 外观与背景”中重试。': [
    'Window size locking is not applied yet. Retry in Settings > Appearance & background.',
    'ウィンドウサイズの固定を適用できませんでした。設定 > 外観と背景で再試行できます。',
    '창 크기 잠금이 적용되지 않았습니다. 설정 > 모양 및 배경에서 다시 시도해 주세요.'
  ],
  '操作失败：{0}': ['Action failed: {0}', '操作に失敗しました：{0}', '작업 실패: {0}'],
  '关闭快捷键说明': ['Close shortcut help', 'ショートカットの説明を閉じる', '단축키 도움말 닫기'],
  '在播放器窗口激活时生效。输入文字时不拦截按键；按钮、滑块等控件优先处理自己的按键。': [
    'Active only while the player is focused. Typing is not intercepted, and buttons and sliders handle their own keys first.',
    'プレイヤーがアクティブなときのみ有効です。文字入力は妨げず、ボタンやスライダーのキー操作が優先されます。',
    '플레이어 창이 활성화되어 있을 때만 작동합니다. 텍스트 입력을 방해하지 않으며 버튼과 슬라이더의 키 조작이 우선합니다.'
  ],
  '音量快捷键仅改变本播放器音量，不修改 Windows 系统音量。': [
    'Volume shortcuts affect this player only, not Windows volume.',
    '音量キーはこのプレイヤーのみに適用され、Windows の音量は変更しません。',
    '음량 단축키는 이 플레이어에만 적용되며 Windows 음량은 변경하지 않습니다.'
  ],
  '仅切换界面文字，不修改歌曲、歌词或文件。': [
    'Changes interface text only; songs, lyrics and files stay unchanged.',
    '表示言語のみ変更します。楽曲、歌詞、ファイルは変更しません。',
    '화면의 언어만 변경하며 곡, 가사, 파일은 변경하지 않습니다.'
  ],
  '保存界面设置失败；本次会话仍然有效。': [
    'Could not save interface settings. They still apply to this session.',
    '表示設定を保存できませんでした。このセッションでは有効です。',
    '화면 설정을 저장하지 못했습니다. 이번 세션에는 적용됩니다.'
  ],
  '显示主窗口': ['Show main window', 'メインウィンドウを表示', '메인 창 표시'],
  '退出 Dan Player': ['Quit Dan Player', 'Dan Player を終了', 'Dan Player 종료'],
  '分类': ['Categories', 'カテゴリ', '분류'],
  '音乐': ['Music', 'ミュージック', '음악'],
  '统计': ['Statistics', '統計', '통계'],
  '升序': ['Ascending', '昇順', '오름차순'],
  '降序': ['Descending', '降順', '내림차순'],
  '乐库顺序': ['Library order', 'ライブラリ順', '라이브러리 순서'],
  '原始顺序': ['Original order', '元の順序', '기존 순서'],
  '名称': ['Name', '名前', '이름'],
  '歌曲信息': ['Track information', '楽曲情報', '곡 정보'],
  '时间': ['Time', '日時', '시간'],
  '文件与来源': ['File and source', 'ファイルと音源', '파일 및 소스'],
  '位艺术家': ['artists', 'アーティスト', '아티스트'],
  '张专辑': ['albums', 'アルバム', '앨범'],
  '位作曲家': ['composers', '作曲者', '작곡가'],
  '种语言': ['languages', '言語', '언어'],
  '种格式': ['formats', '形式', '형식'],
  '种来源': ['sources', '音源', '소스'],
  '未知来源': ['Unknown source', '不明な音源', '알 수 없는 소스'],
  '未知格式': ['Unknown format', '不明な形式', '알 수 없는 형식'],
  '未知艺术家': ['Unknown artist', '不明なアーティスト', '알 수 없는 아티스트'],
  '未知专辑': ['Unknown album', '不明なアルバム', '알 수 없는 앨범'],
  '未知作曲家': ['Unknown composer', '不明な作曲者', '알 수 없는 작곡가'],
  '中文': ['Chinese', '中国語', '중국어'],
  '英文': ['English', '英語', '영어'],
  '日文': ['Japanese', '日本語', '일본어'],
  '韩文': ['Korean', '韓国語', '한국어'],
  '其他语言': ['Other languages', 'その他の言語', '기타 언어'],
  '未识别': ['Unidentified', '未判定', '미확인'],
  '本地': ['Local', 'ローカル', '로컬'],
  '联网': ['Online', 'オンライン', '온라인'],
  '本地 {0}': ['Local {0}', 'ローカル {0}', '로컬 {0}'],
  '联网 {0}': ['Online {0}', 'オンライン {0}', '온라인 {0}'],
  '明确标签': ['Explicit tag', '明示タグ', '명시적 태그'],
  '标签': ['Tag', 'タグ', '태그'],
  '艺术家回退': ['Contributing artist', '参加アーティスト', '참여 아티스트'],
  '推断': ['Inferred', '推定', '추정'],
  '未知': ['Unknown', '不明', '알 수 없음'],
  '歌词': ['Lyrics', '歌詞', '가사'],
  '歌词推断': ['Inferred from lyrics', '歌詞から推定', '가사에서 추정'],
  '元数据推断': ['Inferred from metadata', 'メタデータから推定', '메타데이터에서 추정'],
  '参与创作艺术家': ['Contributing artist', '参加アーティスト', '참여 아티스트'],
  'QQ音乐': ['QQ Music', 'QQ Music', 'QQ Music'],
  '网易云音乐': [
    'NetEase Cloud Music',
    'NetEase Cloud Music',
    'NetEase Cloud Music'
  ],
  'QQ音乐匿名接口当前未提供可靠的下载权限': [
    'The anonymous QQ Music API does not currently provide reliable download authorization',
    'QQ Music の匿名 API では現在、確実なダウンロード権限が提供されていません',
    'QQ Music 익명 API는 현재 신뢰할 수 있는 다운로드 권한을 제공하지 않습니다'
  ],
  '网易云音乐匿名接口当前未提供可靠的下载权限': [
    'The anonymous NetEase API does not currently provide reliable download authorization',
    'NetEase の匿名 API では現在、確実なダウンロード権限が提供されていません',
    'NetEase 익명 API는 현재 신뢰할 수 있는 다운로드 권한을 제공하지 않습니다'
  ],
  '未启用联网歌源，请在设置开启': [
    'No online source is enabled. Enable one in Settings.',
    'オンライン音源が無効です。設定で有効にしてください。',
    '온라인 소스가 꺼져 있습니다. 설정에서 켜 주세요.'
  ],
  '播放 / 暂停': ['Play / pause', '再生 / 一時停止', '재생 / 일시 정지'],
  '快退 5 秒': ['Back 5 seconds', '5 秒戻る', '5초 뒤로'],
  '快进 5 秒': ['Forward 5 seconds', '5 秒進む', '5초 앞으로'],
  '播放器音量降低 5%': ['Decrease volume by 5%', '音量を 5% 下げる', '음량 5% 줄이기'],
  '播放器音量提高 5%': ['Increase volume by 5%', '音量を 5% 上げる', '음량 5% 높이기'],
  '切换迷你播放器': ['Toggle mini player', 'ミニプレイヤーを切り替え', '미니 플레이어 전환'],
  '进入 / 退出全屏': ['Enter / leave fullscreen', '全画面を切り替え', '전체 화면 전환'],
  '关闭弹窗 / 退出迷你或全屏 / 返回': [
    'Close dialog / leave mini or fullscreen / go back',
    'ダイアログを閉じる / ミニ・全画面を終了 / 戻る',
    '대화상자 닫기 / 미니·전체 화면 종료 / 뒤로'
  ],
  '查看快捷键': ['View shortcuts', 'ショートカットを表示', '단축키 보기'],
  '空格': ['Space', 'スペース', '스페이스'],
  '本地使用文件创建时间；联网使用加入乐库时间。': [
    'Local files use creation time; online tracks use the time added to the library.',
    'ローカルはファイルの作成日時、オンラインは追加日時を使用します。',
    '로컬은 파일 생성 시간, 온라인은 라이브러리 추가 시간을 사용합니다.'
  ],
  '使用本地文件的修改时间；联网曲目没有此信息。': [
    'Uses local file modification time; unavailable for online tracks.',
    'ローカルの更新日時を使用します。オンライン楽曲にはありません。',
    '로컬 파일의 수정 시간을 사용합니다. 온라인 곡에는 이 정보가 없습니다.'
  ],
  '使用最近索引的本地字节数，不重新扫描；联网不算本地占用。': [
    'Uses the last indexed file size without rescanning; online tracks do not count as local storage.',
    '再走査せず直近の索引サイズを使用します。オンライン楽曲は容量に含みません。',
    '재검색 없이 최근 색인의 파일 크기를 사용합니다. 온라인 곡은 로컬 용량에 포함하지 않습니다.'
  ],
  '使用本地文件扩展名；未提供格式的联网曲目排在最后。': [
    'Uses file extensions; online tracks without a format appear last.',
    '拡張子を使用します。形式不明のオンライン楽曲は最後になります。',
    '파일 확장자를 사용합니다. 형식이 없는 온라인 곡은 마지막에 표시됩니다.'
  ],
  '只使用已有语言标签，不根据名称猜测语言。': [
    'Uses existing language tags only, without guessing from names.',
    '既存の言語タグのみ使用し、名前からは推測しません。',
    '기존 언어 태그만 사용하며 이름으로 추측하지 않습니다.'
  ],
  '保留原有乐库顺序。': [
    'Keeps the original library order.',
    '元のライブラリ順を保持します。',
    '기존 라이브러리 순서를 유지합니다.'
  ],
  '缺失或不适用的信息始终排在最后；相同值保留原有次序。': [
    'Missing or inapplicable values always appear last. Equal values retain their original order.',
    '情報がない項目は常に最後に表示します。同じ値は元の順序を保持します。',
    '없거나 해당하지 않는 정보는 항상 마지막에 표시됩니다. 같은 값은 기존 순서를 유지합니다.'
  ],
};
