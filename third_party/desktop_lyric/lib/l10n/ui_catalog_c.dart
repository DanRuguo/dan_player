// Source keys 500–740, deduplicated in build/ui-strings.json appearance order.
// Values: English, Japanese, Korean. Numeric placeholders are preserved.
const Map<String, List<String>> uiCatalogC = {
  "隐藏到系统托盘；可从托盘恢复主窗、迷你播放器或真正退出。托盘不可用时正常退出。": [
    "Hide to the system tray; restore the main window or mini player, or fully quit, from the tray. Quit normally if the tray is unavailable.",
    "システムトレイに隠します。トレイからメインウィンドウやミニプレーヤーを表示したり、完全に終了したりできます。トレイが利用できない場合は通常どおり終了します。",
    "시스템 트레이로 숨깁니다. 트레이에서 기본 창이나 미니 플레이어를 복원하거나 완전히 종료할 수 있습니다. 트레이를 사용할 수 없으면 정상 종료합니다."
  ],
  "任务栏缩略图播放控制": [
    "Taskbar thumbnail playback controls",
    "タスクバーのサムネイル再生コントロール",
    "작업 표시줄 미리 보기 재생 제어"
  ],
  "悬停任务栏图标时显示上一首、播放/暂停和下一首。不在任务栏显示歌词。": [
    "Hover over the taskbar icon for Previous, Play/Pause, and Next. Lyrics are not shown on the taskbar.",
    "タスクバーのアイコンにカーソルを合わせると、前の曲・再生/一時停止・次の曲を表示します。タスクバーには歌詞を表示しません。",
    "작업 표시줄 아이콘에 마우스를 올리면 이전 곡, 재생/일시 정지, 다음 곡이 표시됩니다. 작업 표시줄에는 가사가 표시되지 않습니다."
  ],
  "任务栏歌曲预览": ["Taskbar song preview", "タスクバーの楽曲プレビュー", "작업 표시줄 곡 미리 보기"],
  "小预览显示歌曲卡片；桌面 Peek 按窗口大小放大显示，保持比例。关闭后恢复系统窗口预览。": [
    "Show a song card in the thumbnail. Desktop Peek enlarges it to fit the window without distortion. Turn off to restore system window previews.",
    "サムネイルに楽曲カードを表示します。デスクトップの Peek では縦横比を保ってウィンドウに合わせて拡大します。オフにするとシステムのウィンドウプレビューに戻ります。",
    "축소판에 곡 카드를 표시합니다. 데스크톱 Peek에서는 비율을 유지하며 창 크기에 맞게 확대합니다. 끄면 시스템 창 미리 보기로 돌아갑니다."
  ],
  "系统托盘已就绪；隐藏或最小化时停止非必要界面动画，音乐继续播放。": [
    "System tray ready. Nonessential animations stop while hidden or minimized; music keeps playing.",
    "システムトレイの準備ができました。非表示・最小化中は不要な画面アニメーションを停止し、音楽の再生は続きます。",
    "시스템 트레이가 준비되었습니다. 숨기거나 최소화하면 불필요한 화면 애니메이션은 중지되고 음악은 계속 재생됩니다."
  ],
  "系统托盘尚未就绪；不会将播放器隐藏到无法恢复的状态。": [
    "System tray is not ready. The player will not be hidden without a way to restore it.",
    "システムトレイはまだ利用できません。復元できない状態でプレーヤーを非表示にはしません。",
    "시스템 트레이가 아직 준비되지 않았습니다. 복원할 수 없는 상태로 플레이어를 숨기지 않습니다."
  ],
  "桌面歌词设置保存失败；本次会话仍然生效。": [
    "Could not save desktop lyrics settings; they remain active for this session.",
    "デスクトップ歌詞の設定を保存できませんでした。このセッションでは引き続き有効です。",
    "바탕 화면 가사 설정을 저장하지 못했습니다. 현재 세션에는 계속 적용됩니다."
  ],
  "桌面歌词显示": ["Desktop lyrics display", "デスクトップ歌詞の表示", "바탕 화면 가사 표시"],
  "对已打开的桌面歌词即时生效；未打开时记住选择，不会自动启动歌词窗口。单行模式停靠当前屏幕工作区底部，不嵌入任务栏；侧边任务栏时仍在屏幕底部显示。": [
    "Changes apply immediately to open desktop lyrics. Otherwise, your choice is remembered without opening a window. Single-line mode docks to the bottom of the current screen's work area, not inside the taskbar; it stays at the screen bottom even with a side taskbar.",
    "デスクトップ歌詞が開いていればすぐに反映します。閉じている場合は選択を記憶し、歌詞ウィンドウは開きません。1行モードは現在の画面の作業領域の下端に配置され、タスクバーには埋め込みません。タスクバーが側面にあっても画面の下端に表示します。",
    "열려 있는 바탕 화면 가사에 즉시 적용됩니다. 닫혀 있으면 창을 자동으로 열지 않고 선택을 기억합니다. 한 줄 모드는 현재 화면 작업 영역의 아래쪽에 배치되며 작업 표시줄 내부에 들어가지 않습니다. 작업 표시줄이 옆에 있어도 화면 아래쪽에 표시됩니다."
  ],
  "设置分类": ["Settings categories", "設定カテゴリー", "설정 분류"],
  "歌词体验": ["Lyrics experience", "歌詞の表示体験", "가사 표시 환경"],
  "歌词弹性滚动": ["Elastic lyric scrolling", "歌詞の弾性スクロール", "가사 탄성 스크롤"],
  "逐句跟随时轻微回弹；跳转保持平稳。系统减少动画时不启用。": [
    "A gentle bounce when following each line; seeking stays smooth. Disabled when the system reduces motion.",
    "行を追うときに軽く弾む動きを加え、シーク時は滑らかに移動します。システムで動きを減らす設定が有効な場合は使用しません。",
    "가사 줄을 따라갈 때 가볍게 반동을 주고 위치 이동은 부드럽게 유지합니다. 시스템의 동작 줄이기가 켜져 있으면 사용하지 않습니다."
  ],
  "桌面歌词竖排": ["Vertical desktop lyrics", "デスクトップ歌詞の縦書き", "바탕 화면 가사 세로쓰기"],
  "文字从上到下排列，译文分列；仅改变桌面歌词，不会自动打开歌词窗口。": [
    "Arrange text top to bottom with translations in separate columns. Only affects desktop lyrics and does not open the lyrics window.",
    "文字を上から下へ並べ、訳文を別の列に表示します。デスクトップ歌詞だけに適用し、歌詞ウィンドウは自動で開きません。",
    "글자를 위에서 아래로 배치하고 번역은 별도 열에 표시합니다. 바탕 화면 가사에만 적용되며 가사 창을 자동으로 열지 않습니다."
  ],
  "歌词设置保存失败；当前选择仍在本次会话生效。": [
    "Could not save lyrics settings; your choices remain active for this session.",
    "歌詞の設定を保存できませんでした。現在の選択はこのセッションで引き続き有効です。",
    "가사 설정을 저장하지 못했습니다. 현재 선택은 이 세션에 계속 적용됩니다."
  ],
  "保存歌源设置失败；当前选择仍对本次会话生效。": [
    "Could not save music source settings; your choices remain active for this session.",
    "音楽ソースの設定を保存できませんでした。現在の選択はこのセッションで引き続き有効です。",
    "음악 소스 설정을 저장하지 못했습니다. 현재 선택은 이 세션에 계속 적용됩니다."
  ],
  "联网歌源": ["Online music sources", "オンライン音楽ソース", "온라인 음악 소스"],
  "只影响新的联网搜索。关闭后，不会删除收藏、歌单或队列，也不会中断已有歌曲的播放。": [
    "Only affects new online searches. Turning off does not delete favorites, playlists, or the queue, and does not interrupt playback.",
    "新しいオンライン検索だけに適用します。オフにしても、お気に入り・プレイリスト・再生キューは削除せず、再生中の曲も中断しません。",
    "새 온라인 검색에만 적용됩니다. 끄더라도 즐겨찾기, 재생 목록, 대기열을 삭제하거나 현재 재생을 중단하지 않습니다."
  ],
  "已启用 {0} 个歌源；新搜索会同时查询已启用的来源。": [
    "{0} sources enabled; new searches query all enabled sources together.",
    "{0} 個のソースが有効です。新しい検索では有効なソースを同時に検索します。",
    "소스 {0}개가 활성화되었습니다. 새 검색은 활성화된 모든 소스를 함께 검색합니다."
  ],
  "已启用 {0} 个内置歌源；新搜索会同时查询已启用的来源。": [
    "{0} built-in sources enabled; new searches query all enabled sources together.",
    "{0} 個の内蔵音源が有効です。新しい検索では有効なソースを同時に検索します。",
    "내장 음원 {0}개가 활성화되었습니다. 새 검색은 활성화된 모든 소스를 함께 검색합니다."
  ],
  "参与新搜索": ["Include in new searches", "新しい検索に含める", "새 검색에 포함"],
  "不参与新搜索；已有歌曲仍可播放": [
    "Exclude from new searches; existing songs still play",
    "新しい検索には含めません。既存の曲は再生できます",
    "새 검색에서 제외하며 기존 곡은 계속 재생 가능"
  ],
  "歌曲搜索；公开可用音源播放；歌词和封面（来源提供时）。": [
    "Song search, publicly available audio playback, and lyrics and covers when provided by the source.",
    "楽曲検索、公開音源の再生、ソースが提供する歌詞とカバーに対応します。",
    "곡 검색, 공개 음원 재생, 소스에서 제공하는 가사와 커버를 지원합니다."
  ],
  "下载未开放：{0}。": [
    "Downloads unavailable: {0}.",
    "ダウンロードは利用できません：{0}。",
    "다운로드를 사용할 수 없습니다: {0}."
  ],
  "只读公开评论：需有效平台歌曲 ID，接口可用性由平台决定。": [
    "Read-only public comments require a valid platform song ID. Availability depends on the platform.",
    "公開コメントは閲覧専用です。有効なプラットフォームの楽曲 ID が必要で、利用可否はプラットフォームに依存します。",
    "공개 댓글은 읽기 전용이며 유효한 플랫폼 곡 ID가 필요합니다. 사용 가능 여부는 플랫폼에 따라 다릅니다."
  ],
  "恢复上次播放会话": [
    "Restore the last playback session",
    "前回の再生セッションを復元",
    "마지막 재생 세션 복원"
  ],
  "首选歌词来源": ["Preferred lyrics source", "優先する歌詞ソース", "선호하는 가사 소스"],
  "当前没有已保存的歌词API可备份": [
    "No saved lyrics APIs to back up",
    "バックアップできる保存済み歌詞 API はありません",
    "백업할 저장된 가사 API가 없습니다"
  ],
  "备份歌词API": ["Back up lyrics APIs", "歌詞 API をバックアップ", "가사 API 백업"],
  "Dan Player API 备份": [
    "Dan Player API backup",
    "Dan Player API バックアップ",
    "Dan Player API 백업"
  ],
  "歌词API": ["Lyrics API", "歌詞 API", "가사 API"],
  "歌词API备份已保存": [
    "Lyrics API backup saved",
    "歌詞 API のバックアップを保存しました",
    "가사 API 백업을 저장했습니다"
  ],
  "备份歌词API失败": [
    "Could not back up lyrics APIs",
    "歌詞 API をバックアップできませんでした",
    "가사 API를 백업하지 못했습니다"
  ],
  "加载歌词API备份": [
    "Load a lyrics API backup",
    "歌詞 API のバックアップを読み込む",
    "가사 API 백업 불러오기"
  ],
  "文本文件": ["Text files", "テキストファイル", "텍스트 파일"],
  "备份文件中没有可用的歌词API": [
    "No usable lyrics APIs in the backup file",
    "バックアップファイルに利用できる歌詞 API がありません",
    "백업 파일에 사용 가능한 가사 API가 없습니다"
  ],
  "加载歌词API备份失败": [
    "Could not load the lyrics API backup",
    "歌詞 API のバックアップを読み込めませんでした",
    "가사 API 백업을 불러오지 못했습니다"
  ],
  "删除歌词API": ["Delete lyrics API", "歌詞 API を削除", "가사 API 삭제"],
  "确认要删除该API吗？此操作不可恢复！": [
    "Delete this API? This cannot be undone.",
    "この API を削除しますか？この操作は取り消せません。",
    "이 API를 삭제할까요? 이 작업은 되돌릴 수 없습니다."
  ],
  "确认删除": ["Confirm deletion", "削除を確認", "삭제 확인"],
  "备份当前API": ["Back up the current API", "現在の API をバックアップ", "현재 API 백업"],
  "加载备份": ["Load backup", "バックアップを読み込む", "백업 불러오기"],
  "已读取API备份，请点击保存应用": [
    "API backup loaded. Select Save to apply it.",
    "API のバックアップを読み込みました。「保存」で適用してください。",
    "API 백업을 불러왔습니다. 저장을 눌러 적용하세요."
  ],
  "接口地址": ["Endpoint URL", "API の URL", "API 주소"],
  "请求方式：GET；参数：title、artist、album、duration、fileName、displayTitle。返回 JSON 支持 {type:\"lrc\", lyric:\"...\", translation:\"...\"}，type 可为 lrc/qrc/krc。":
      [
    "Method: GET; parameters: title, artist, album, duration, fileName, displayTitle. JSON responses support {type:\"lrc\", lyric:\"...\", translation:\"...\"}; type may be lrc/qrc/krc.",
    "リクエスト方式：GET。パラメーター：title、artist、album、duration、fileName、displayTitle。JSON 応答は {type:\"lrc\", lyric:\"...\", translation:\"...\"} に対応し、type は lrc/qrc/krc を指定できます。",
    "요청 방식: GET. 매개변수: title, artist, album, duration, fileName, displayTitle. JSON 응답은 {type:\"lrc\", lyric:\"...\", translation:\"...\"} 형식을 지원하며 type은 lrc/qrc/krc를 사용할 수 있습니다."
  ],
  "恢复默认": ["Restore defaults", "初期設定に戻す", "기본값 복원"],
  "请输入 http 或 https 接口地址": [
    "Enter an http or https endpoint URL",
    "http または https の API URL を入力してください",
    "http 또는 https API 주소를 입력하세요"
  ],
  "已恢复默认歌词API": [
    "Default lyrics API restored",
    "既定の歌詞 API に戻しました",
    "기본 가사 API로 복원했습니다"
  ],
  "歌词API已更新": ["Lyrics API updated", "歌詞 API を更新しました", "가사 API를 업데이트했습니다"],
  "设置接口": ["Set endpoint", "API を設定", "API 설정"],
  "已自定义": ["Customized", "カスタマイズ済み", "사용자 지정됨"],
  "当前接口": ["Current endpoint", "現在の API", "현재 API"],
  "删除当前歌词API": [
    "Delete the current lyrics API",
    "現在の歌詞 API を削除",
    "현재 가사 API 삭제"
  ],
  "使用内置 QQ / 酷狗 / 网易歌词源": [
    "Use built-in QQ / Kugou / NetEase lyrics sources",
    "内蔵の QQ・酷狗・網易の歌詞ソースを使用",
    "내장 QQ / 쿠거우 / 넷이즈 가사 소스 사용"
  ],
  "当前使用内置歌词源": [
    "Using built-in lyrics sources",
    "内蔵の歌詞ソースを使用中",
    "내장 가사 소스 사용 중"
  ],
  "正在测试歌词API连通性": [
    "Testing lyrics API connectivity",
    "歌詞 API の接続をテスト中",
    "가사 API 연결 테스트 중"
  ],
  "测试失败：未获得结果": [
    "Test failed: no results received",
    "テストに失敗しました：結果が得られませんでした",
    "테스트 실패: 결과를 받지 못했습니다"
  ],
  "文件夹管理": ["Folder management", "フォルダー管理", "폴더 관리"],
  "刷新音乐库": ["Refresh music library", "音楽ライブラリを更新", "음악 라이브러리 새로 고침"],
  "完整刷新": ["Full refresh", "全体を更新", "전체 새로 고침"],
  "当前没有可刷新的音乐文件夹": [
    "No music folders to refresh",
    "更新できる音楽フォルダーがありません",
    "새로 고칠 음악 폴더가 없습니다"
  ],
  "音乐库已刷新": ["Music library refreshed", "音楽ライブラリを更新しました", "음악 라이브러리를 새로 고쳤습니다"],
  "刷新音乐库失败：{0}": [
    "Could not refresh music library: {0}",
    "音楽ライブラリを更新できませんでした：{0}",
    "음악 라이브러리를 새로 고치지 못했습니다: {0}"
  ],
  "管理文件夹": ["Manage folders", "フォルダーを管理", "폴더 관리"],
  "更新音乐文件夹失败：{0}": [
    "Could not update music folders: {0}",
    "音楽フォルダーを更新できませんでした：{0}",
    "음악 폴더를 업데이트하지 못했습니다: {0}"
  ],
  "选择文件夹": ["Choose folder", "フォルダーを選択", "폴더 선택"],
  "曲库与播放": ["Library & playback", "ライブラリと再生", "라이브러리 및 재생"],
  "联网与歌词": ["Online & lyrics", "オンラインと歌詞", "온라인 및 가사"],
  "外观与背景": ["Appearance & background", "外観と背景", "모양 및 배경"],
  "桌面与快捷键": ["Desktop & shortcuts", "デスクトップとショートカット", "바탕 화면 및 단축키"],
  "更新与关于": ["Updates & about", "更新とアプリについて", "업데이트 및 정보"],
  "当前会话已应用，但设置保存失败：{0}": [
    "Applied for this session, but could not save settings: {0}",
    "このセッションには適用しましたが、設定を保存できませんでした：{0}",
    "현재 세션에 적용했지만 설정을 저장하지 못했습니다: {0}"
  ],
  "播放速度": ["Playback speed", "再生速度", "재생 속도"],
  "保音高变速；歌词跟随歌曲进度，听歌时长仍按实际时间统计。": [
    "Change speed without changing pitch. Lyrics follow playback; listening time uses actual elapsed time.",
    "音程を維持して速度を変更します。歌詞は再生位置に追従し、再生時間の統計は実際の経過時間で計測します。",
    "음높이를 유지하면서 속도를 바꿉니다. 가사는 재생 위치를 따르고 청취 시간은 실제 경과 시간으로 집계합니다."
  ],
  "当前安装缺少倍速组件，仍可正常以 1× 播放。": [
    "The speed component is missing from this installation. Normal 1× playback is still available.",
    "このインストールには速度変更コンポーネントがありません。通常の 1× 再生は利用できます。",
    "현재 설치에 배속 구성 요소가 없습니다. 일반 1× 재생은 계속 사용할 수 있습니다."
  ],
  "WASAPI 独占输出": ["WASAPI exclusive output", "WASAPI 排他出力", "WASAPI 독점 출력"],
  "正在切换输出模式…": ["Switching output mode…", "出力モードを切り替え中…", "출력 모드 전환 중…"],
  "启用后设备可能无法同时播放其他应用的声音；独占不等于一定无重采样。切换失败会尝试恢复原模式。": [
    "Other apps may be unable to play audio through this device while enabled. Exclusive mode does not guarantee no resampling. If switching fails, the original mode will be restored when possible.",
    "有効にすると、このデバイスで他のアプリの音声を同時に再生できない場合があります。排他モードでもリサンプリングが必ずなくなるわけではありません。切り替えに失敗した場合は元のモードへの復元を試みます。",
    "켜면 이 장치에서 다른 앱의 소리를 동시에 재생하지 못할 수 있습니다. 독점 모드가 리샘플링 없음을 보장하지는 않습니다. 전환에 실패하면 원래 모드로 복원을 시도합니다."
  ],
  "尚未播放歌曲，以上设置将在开始播放时应用。": [
    "No song has played yet. These settings will apply when playback starts.",
    "まだ曲を再生していません。これらの設定は再生開始時に適用します。",
    "아직 재생한 곡이 없습니다. 재생을 시작하면 위 설정이 적용됩니다."
  ],
  "播放速度（保音高）": [
    "Playback speed (preserve pitch)",
    "再生速度（音程を維持）",
    "재생 속도(음높이 유지)"
  ],
  "速度已应用，但设置保存失败：{0}": [
    "Speed applied, but could not save settings: {0}",
    "速度を適用しましたが、設定を保存できませんでした：{0}",
    "속도는 적용했지만 설정을 저장하지 못했습니다: {0}"
  ],
  "快捷键保存失败，已恢复原设置：{0}": [
    "Could not save shortcuts; previous settings restored: {0}",
    "ショートカットを保存できなかったため、元の設定に戻しました：{0}",
    "단축키를 저장하지 못해 이전 설정으로 복원했습니다: {0}"
  ],
  "快捷键保存失败，已恢复原设置": [
    "Could not save shortcuts; previous settings restored",
    "ショートカットを保存できなかったため、元の設定に戻しました",
    "단축키를 저장하지 못해 이전 설정으로 복원했습니다"
  ],
  "应用内快捷键": ["In-app shortcuts", "アプリ内ショートカット", "앱 내 단축키"],
  "仅在播放器窗口内生效；输入文字、编辑标签或录制按键时不会触发播放操作。": [
    "Only active inside the player window. Playback actions do not trigger while typing, editing tags, or recording a shortcut.",
    "プレーヤーウィンドウ内だけで有効です。文字入力、タグ編集、ショートカットの記録中は再生操作を実行しません。",
    "플레이어 창 안에서만 작동합니다. 글자 입력, 태그 편집, 단축키 기록 중에는 재생 동작이 실행되지 않습니다."
  ],
  "修改“{0}”": ["Change “{0}”", "「{0}」を変更", "“{0}” 변경"],
  "请按下新的组合键": [
    "Press the new key combination",
    "新しいキーの組み合わせを押してください",
    "새 키 조합을 누르세요"
  ],
  "与“{0}”冲突": ["Conflicts with “{0}”", "「{0}」と競合しています", "“{0}”와 충돌합니다"],
  "保存侧栏布局失败；当前选择仍对本次会话生效。": [
    "Could not save sidebar layout; your choice remains active for this session.",
    "サイドバーのレイアウトを保存できませんでした。現在の選択はこのセッションで引き続き有効です。",
    "사이드바 배치를 저장하지 못했습니다. 현재 선택은 이 세션에 계속 적용됩니다."
  ],
  "应用窗口约束失败：{0}": [
    "Could not apply window constraints: {0}",
    "ウィンドウの制約を適用できませんでした：{0}",
    "창 크기 제한을 적용하지 못했습니다: {0}"
  ],
  "侧栏宽度": ["Sidebar width", "サイドバーの幅", "사이드바 너비"],
  "图标模式 · {0} px": ["Icon mode · {0} px", "アイコン表示 · {0} px", "아이콘 모드 · {0} px"],
  "展开模式 · {0} px": [
    "Expanded mode · {0} px",
    "展開表示 · {0} px",
    "펼침 모드 · {0} px"
  ],
  "恢复默认侧栏宽度": [
    "Restore default sidebar width",
    "サイドバーの幅を既定値に戻す",
    "기본 사이드바 너비 복원"
  ],
  "锁定侧栏宽度": ["Lock sidebar width", "サイドバーの幅を固定", "사이드바 너비 잠금"],
  "锁定后关闭主窗口中的拖动调整；窗口缩小时仍会临时收窄，避免遮住主内容。": [
    "Disable drag resizing in the main window. The sidebar still narrows temporarily in a smaller window to keep the main content visible.",
    "メインウィンドウでのドラッグによる幅の変更を無効にします。ウィンドウが小さい場合は、メインコンテンツを隠さないよう一時的に幅を狭めます。",
    "기본 창에서 드래그로 너비를 바꾸지 못하게 합니다. 창이 작아지면 주요 내용이 가려지지 않도록 일시적으로 좁아집니다."
  ],
  "锁定窗口大小": ["Lock window size", "ウィンドウサイズを固定", "창 크기 잠금"],
  "阻止鼠标改变完整播放器的宽度和高度；迷你播放器切换仍可正常恢复。": [
    "Prevent mouse resizing of the full player. Switching to and from the mini player still restores correctly.",
    "通常プレーヤーの幅と高さをマウスで変更できなくします。ミニプレーヤーへの切り替えと復元は引き続き利用できます。",
    "마우스로 전체 플레이어의 너비와 높이를 바꾸지 못하게 합니다. 미니 플레이어로 전환하거나 복원하는 기능은 유지됩니다."
  ],
  "锁定窗口纵横比": ["Lock window aspect ratio", "ウィンドウの縦横比を固定", "창 가로세로 비율 잠금"],
  "拖动窗口时保持 {0} : 1。": [
    "Keep a {0} : 1 ratio while resizing the window.",
    "ウィンドウのサイズ変更時に {0} : 1 の比率を維持します。",
    "창 크기를 조절할 때 {0} : 1 비율을 유지합니다."
  ],
  "开启时以当前完整播放器的宽高比为准。": [
    "Use the current full player aspect ratio when enabled.",
    "有効にした時点の通常プレーヤーの縦横比を使用します。",
    "켤 때의 전체 플레이어 가로세로 비율을 사용합니다."
  ],
  "固定窗口大小开启时不能同时锁定纵横比；请先关闭固定大小。": [
    "Aspect ratio lock is unavailable while window size is locked. Turn off window size lock first.",
    "ウィンドウサイズの固定中は縦横比を固定できません。先にウィンドウサイズの固定を解除してください。",
    "창 크기가 잠겨 있으면 가로세로 비율을 함께 잠글 수 없습니다. 먼저 창 크기 잠금을 해제하세요."
  ],
  "窗口约束暂未应用，请重试。": [
    "Window constraints have not been applied. Try again.",
    "ウィンドウの制約はまだ適用されていません。再試行してください。",
    "창 크기 제한이 아직 적용되지 않았습니다. 다시 시도하세요."
  ],
  "主题选择器": ["Theme picker", "テーマ選択", "테마 선택기"],
  "修改主题": ["Change theme", "テーマを変更", "테마 변경"],
  "主题模式": ["Theme mode", "テーマモード", "테마 모드"],
  "专辑封面动态配色": [
    "Dynamic colors from album art",
    "アルバムカバーから動的に配色",
    "앨범 커버 기반 동적 색상"
  ],
  "自定义字体": ["Custom font", "フォントのカスタマイズ", "사용자 지정 글꼴"],
  "无法获取字体": ["Could not retrieve fonts", "フォントを取得できませんでした", "글꼴을 가져오지 못했습니다"],
  "选择字体": ["Choose font", "フォントを選択", "글꼴 선택"],
  "当前字体：{0}": ["Current font: {0}", "現在のフォント：{0}", "현재 글꼴: {0}"],
  "暂时无法完成统计，请重试。已有结果会保留。": [
    "Could not complete statistics. Try again; existing results are preserved.",
    "統計を完了できませんでした。再試行してください。既存の結果は保持します。",
    "통계를 완료하지 못했습니다. 다시 시도하세요. 기존 결과는 유지됩니다."
  ],
  "音乐统计": ["Music statistics", "音楽の統計", "음악 통계"],
  "重新核实文件大小与语言": [
    "Recheck file sizes and languages",
    "ファイルサイズと言語を再確認",
    "파일 크기 및 언어 다시 확인"
  ],
  "听歌习惯、曲库构成与本地文件占用。": [
    "Listening habits, library composition, and local file storage.",
    "音楽を聴く習慣、ライブラリの構成、ローカルファイルの使用容量。",
    "청취 습관, 라이브러리 구성 및 로컬 파일 용량."
  ],
  "曲库概览": ["Library overview", "ライブラリ概要", "라이브러리 개요"],
  "正在核实曲库 {0} / {1}…": [
    "Checking library {0} / {1}…",
    "ライブラリを確認中 {0} / {1}…",
    "라이브러리 확인 중 {0} / {1}…"
  ],
  "统计于 {0} · 按源文件字节数统计，不含缓存或磁盘分配开销。{1}": [
    "Calculated at {0} · Based on source file bytes, excluding caches and disk allocation overhead.{1}",
    "集計時刻 {0} · 元ファイルのバイト数に基づき、キャッシュとディスク割り当ての追加領域は含みません。{1}",
    "집계 시각 {0} · 원본 파일의 바이트 수 기준이며 캐시와 디스크 할당 오버헤드는 제외합니다.{1}"
  ],
  "占用空间最多": ["Largest storage use", "使用容量が最大", "용량 사용량 최다"],
  "播放最多": ["Most played", "再生回数が最多", "재생 횟수 최다"],
  "{0} 次": ["{0} times", "{0} 回", "{0}회"],
  "收听最久": ["Longest listening time", "再生時間が最長", "청취 시간 최장"],
  "{0} 小时 {1} 分{2}": ["{0} hr {1} min{2}", "{0} 時間 {1} 分{2}", "{0}시간 {1}분{2}"],
  "{0} 分 {1} 秒": ["{0} min {1} sec", "{0} 分 {1} 秒", "{0}분 {1}초"],
  "{0} 分钟": ["{0} minutes", "{0} 分", "{0}분"],
  "不足 1 秒": ["Less than 1 second", "1 秒未満", "1초 미만"],
  "{0} 秒": ["{0} seconds", "{0} 秒", "{0}초"],
  "播放后显示高峰时段": [
    "Peak hours appear after playback",
    "再生するとピーク時間帯を表示します",
    "재생 후 가장 활발한 시간대를 표시합니다"
  ],
  "{0} · 按本机时间": [
    "{0} · Local device time",
    "{0} · この端末の時刻",
    "{0} · 이 기기의 현지 시간"
  ],
  "{0} 个并列时段 · 每段 {1}": [
    "{0} tied periods · {1} each",
    "同率の時間帯が {0} 件 · 各 {1}",
    "공동 시간대 {0}개 · 각 {1}"
  ],
  "听歌时长": ["Listening time", "再生時間", "청취 시간"],
  "仅累计实际播放采样时间": [
    "Counts only sampled time during actual playback",
    "実際の再生中に観測した時間だけを集計",
    "실제 재생 중 측정된 시간만 집계"
  ],
  "播放次数": ["Play count", "再生回数", "재생 횟수"],
  "{0} 首有记录 · 恢复播放不重复计次": [
    "{0} songs recorded · Resuming playback does not count again",
    "{0} 曲を記録 · 再生再開では重複して数えません",
    "{0}곡 기록됨 · 재생 재개는 중복 집계하지 않음"
  ],
  "最活跃时段": ["Most active period", "最も活発な時間帯", "가장 활발한 시간대"],
  "听歌行为": ["Listening activity", "再生の傾向", "청취 활동"],
  "包含所有已保存记录。历史小时分布没有日期维度，不作为近7天或近30天数据展示。": [
    "Includes all saved records. Historical hourly distribution has no dates, so it is not shown as last-7-day or last-30-day data.",
    "保存済みの全記録を含みます。過去の時間帯別データには日付がないため、直近 7 日間や 30 日間のデータとしては表示しません。",
    "저장된 모든 기록을 포함합니다. 과거 시간대별 분포에는 날짜 정보가 없어 최근 7일 또는 30일 데이터로 표시하지 않습니다."
  ],
  "全部记录": ["All records", "すべての記録", "전체 기록"],
  "本地与联网歌曲一并统计，发现你一天中的听歌习惯。": [
    "Local and online songs are counted together to reveal your daily listening habits.",
    "ローカル曲とオンライン曲をまとめて集計し、1 日の再生傾向を確認できます。",
    "로컬 곡과 온라인 곡을 함께 집계하여 하루의 청취 습관을 보여줍니다."
  ],
  "完整 {0} 次": ["Completed {0} times", "最後まで再生 {0} 回", "끝까지 재생 {0}회"],
  "提前跳过 {0} 次": ["Skipped early {0} times", "途中でスキップ {0} 回", "중간에 건너뛰기 {0}회"],
  "24 小时收听分布": ["24-hour listening distribution", "24 時間の再生分布", "24시간 청취 분포"],
  "每根柱表示该时段累计收听时长，强调色柱为最高时段。": [
    "Each bar shows total listening time in that hour. The accent-colored bar marks the highest period.",
    "各棒はその時間帯の累計再生時間を示します。アクセント色の棒が最も長い時間帯です。",
    "각 막대는 해당 시간대의 누적 청취 시간을 나타냅니다. 강조색 막대는 가장 높은 시간대입니다."
  ],
  "暂停、缓冲和拖动播放进度不补算时长。休眠或采样间隔超过 2 秒时，仅计最近 2 秒，未观测的间隔不补记。": [
    "Pauses, buffering, and seeking add no listening time. After sleep or a sampling gap over 2 seconds, only the latest 2 seconds count; unobserved gaps are not backfilled.",
    "一時停止、バッファリング、シークの時間は加算しません。スリープ後や観測間隔が 2 秒を超えた場合は直近の 2 秒だけを計上し、観測できなかった時間は補いません。",
    "일시 정지, 버퍼링, 재생 위치 이동 시간은 더하지 않습니다. 절전 상태이거나 측정 간격이 2초를 넘으면 최근 2초만 집계하며 관측하지 못한 시간은 소급하여 기록하지 않습니다."
  ],
  "还没有收听记录。开始播放后，这里会显示真实的时段分布。": [
    "No listening records yet. Start playback to see your actual hourly distribution.",
    "再生記録はまだありません。再生を始めると、実際の時間帯別分布が表示されます。",
    "아직 청취 기록이 없습니다. 재생을 시작하면 실제 시간대별 분포가 표시됩니다."
  ],
  "收听时长": ["Time listened", "聴いた時間", "들은 시간"],
  "顶格 {0}": ["Scale maximum: {0}", "目盛りの上限：{0}", "눈금 최댓값: {0}"],
  "{0}，收听 {1}{2}": [
    "{0}, listened for {1}{2}",
    "{0}、再生時間 {1}{2}",
    "{0}, 청취 시간 {1}{2}"
  ],
  "横向滑动查看全部 24 个时段": [
    "Scroll horizontally to view all 24 hours",
    "横にスクロールして 24 時間すべてを表示",
    "가로로 스크롤하여 전체 24시간 보기"
  ],
  "前一个时段": ["Previous period", "前の時間帯", "이전 시간대"],
  "选择一个时段": ["Select a period", "時間帯を選択", "시간대 선택"],
  "点击、长按或悬停柱状条查看时长": [
    "Click, long-press, or hover over a bar to view its duration",
    "棒をクリック・長押し・ホバーすると時間を確認できます",
    "막대를 클릭하거나 길게 누르거나 마우스를 올려 시간을 확인하세요"
  ],
  "后一个时段": ["Next period", "次の時間帯", "다음 시간대"],
  "正在统计": ["Calculating", "集計中", "집계 중"],
  "本地 {0} · 联网 {1}": [
    "Local {0} · Online {1}",
    "ローカル {0} · オンライン {1}",
    "로컬 {0} · 온라인 {1}"
  ],
  "本地源文件占用": ["Local source file storage", "ローカル元ファイルの使用容量", "로컬 원본 파일 용량"],
  "正在读取真实字节数": ["Reading actual byte sizes", "実際のバイト数を読み取り中", "실제 바이트 수 읽는 중"],
  "{0} 首已核实 · 不含联网曲目": [
    "{0} songs checked · Excludes online tracks",
    "{0} 曲を確認済み · オンライン曲は除外",
    "{0}곡 확인됨 · 온라인 곡 제외"
  ],
  "文件读取情况": ["File read status", "ファイルの読み取り状況", "파일 읽기 상태"],
  "{0} 首未计入空间": [
    "{0} songs excluded from storage totals",
    "{0} 曲を容量の集計から除外",
    "{0}곡을 용량 집계에서 제외"
  ],
  "只读检查，不修改源文件": [
    "Read-only check; source files are not changed",
    "読み取り専用の確認で、元ファイルは変更しません",
    "읽기 전용 검사이며 원본 파일을 수정하지 않음"
  ],
  "缺失 {0} · 无权限/不可读 {1}": [
    "Missing {0} · No access/unreadable {1}",
    "見つからない {0} · 権限なし/読み取り不可 {1}",
    "누락 {0} · 권한 없음/읽기 불가 {1}"
  ],
  "本地文件夹": ["Local folders", "ローカルフォルダー", "로컬 폴더"],
  "按完整路径区分直接父目录，不含联网曲目": [
    "Group by immediate parent directory using full paths; excludes online tracks",
    "フルパスで直属の親フォルダーを区別し、オンライン曲は除外",
    "전체 경로로 바로 위 폴더를 구분하며 온라인 곡은 제외"
  ],
  "歌曲语言": ["Song languages", "楽曲の言語", "곡 언어"],
  "正在读取曲目信息…": ["Reading track information…", "楽曲情報を読み取り中…", "곡 정보 읽는 중…"],
  "标签 {0} 首 · 歌词 {1} 首 · 推断 {2} 首 · 未识别 {3} 首": [
    "Tags {0} · Lyrics {1} · Inferred {2} · Unidentified {3} songs",
    "タグ {0} 曲 · 歌詞 {1} 曲 · 推定 {2} 曲 · 不明 {3} 曲",
    "태그 {0}곡 · 가사 {1}곡 · 추론 {2}곡 · 미확인 {3}곡"
  ],
  "{0} 首": ["{0} songs", "{0} 曲", "{0}곡"],
  "缺乏可靠语言信息": [
    "Insufficient reliable language information",
    "信頼できる言語情報が不足しています",
    "신뢰할 수 있는 언어 정보 부족"
  ],
  "标签 {0} · 歌词 {1} · 推断 {2}": [
    "Tags {0} · Lyrics {1} · Inferred {2}",
    "タグ {0} · 歌詞 {1} · 推定 {2}",
    "태그 {0} · 가사 {1} · 추론 {2}"
  ],
  "尚未添加歌曲": ["No songs added yet", "まだ曲が追加されていません", "아직 추가한 곡이 없습니다"],
  "首曲目": ["tracks", "曲", "곡"],
  "与分类页共用判定：语言标签优先，其次为本地内嵌或同名 .lrc 歌词的原文线索，最后依据歌名、作曲或参与创作艺术家和专辑名作文字推断。按常见 LRC 约定保留同时间戳首行，不混入后续译文；没有足够证据时保留未识别。歌词与文字推断均不代表已识别实际演唱语言。":
      [
    "Uses the same rules as Categories: language tags first, then original-text clues in embedded lyrics or a same-name local .lrc file, then textual inference from the title, composing or contributing artists, and album name. Under common LRC conventions, only the first line at each timestamp is kept, excluding subsequent translations. Without enough evidence, the language remains unidentified. Lyrics and text inference do not confirm the language actually sung.",
    "カテゴリー画面と同じ判定を使います。言語タグを優先し、次に埋め込み歌詞または同名のローカル .lrc の原文の手掛かりを参照し、最後に曲名、作曲・制作に参加したアーティスト、アルバム名から文字に基づいて推定します。一般的な LRC の慣例に従い、同じタイムスタンプでは最初の行だけを残し、後続の訳文は混ぜません。十分な根拠がなければ不明のままにします。歌詞や文字からの推定は、実際に歌われている言語の確認を意味しません。",
    "분류 화면과 같은 기준을 사용합니다. 언어 태그를 우선하고, 다음으로 내장 가사나 같은 이름의 로컬 .lrc 파일에 있는 원문 단서를 확인한 뒤 곡명, 작곡·창작 참여 아티스트, 앨범명을 바탕으로 문자 정보를 추론합니다. 일반적인 LRC 관례에 따라 같은 타임스탬프의 첫 줄만 유지하고 뒤의 번역문은 섞지 않습니다. 근거가 부족하면 미확인으로 남깁니다. 가사와 문자 기반 추론은 실제로 노래한 언어가 확인되었음을 의미하지 않습니다."
  ],
  "其他格式": ["Other formats", "その他の形式", "기타 형식"],
  "本地空间 · 文件格式": [
    "Local storage · File formats",
    "ローカル容量 · ファイル形式",
    "로컬 용량 · 파일 형식"
  ],
  "扇区按实际字节数划分；格式按文件扩展名分组。": [
    "Slices are sized by actual bytes; formats are grouped by file extension.",
    "扇形の大きさは実際のバイト数を示し、形式はファイル拡張子で分類します。",
    "부채꼴 크기는 실제 바이트 수를 기준으로 하며 형식은 파일 확장자로 분류합니다."
  ],
  "{0} 个源文件": ["{0} source files", "元ファイル {0} 件", "원본 파일 {0}개"],
  "暂无可核实文件": [
    "No files available to verify",
    "確認できるファイルがありません",
    "확인할 수 있는 파일이 없습니다"
  ],
  "已核实占用": ["Verified storage use", "確認済みの使用容量", "확인된 사용 용량"],
  "正在只读检查本地源文件。": [
    "Checking local source files in read-only mode.",
    "ローカルの元ファイルを読み取り専用で確認中です。",
    "로컬 원본 파일을 읽기 전용으로 검사 중입니다."
  ],
  "已读取 {0} 首；缺失 {1} 首，无权限/不可读 {2} 首。联网 {3} 首不计入本地占用。文件在外部变化后可点右上角刷新。": [
    "Read {0} songs; {1} missing, {2} inaccessible/unreadable. {3} online songs are excluded from local storage. Refresh at the top right after external file changes.",
    "{0} 曲を読み取り済み。見つからない曲は {1} 曲、権限なし/読み取り不可は {2} 曲です。オンラインの {3} 曲はローカル容量に含みません。外部でファイルを変更した場合は右上から更新してください。",
    "{0}곡을 읽었습니다. 누락 {1}곡, 권한 없음/읽기 불가 {2}곡입니다. 온라인 {3}곡은 로컬 용량에서 제외됩니다. 외부에서 파일을 변경한 뒤에는 오른쪽 위에서 새로 고침하세요."
  ],
  "本地分布 · 文件夹": [
    "Local distribution · Folders",
    "ローカルの内訳 · フォルダー",
    "로컬 분포 · 폴더"
  ],
  "正在只读检查本地源文件…": [
    "Checking local source files in read-only mode…",
    "ローカルの元ファイルを読み取り専用で確認中…",
    "로컬 원본 파일을 읽기 전용으로 검사 중…"
  ],
  "{0} 个直接父目录 · 本地 {1} 首": [
    "{0} immediate parent folders · {1} local songs",
    "直属の親フォルダー {0} 件 · ローカル {1} 曲",
    "바로 위 폴더 {0}개 · 로컬 {1}곡"
  ],
  "占用空间": ["Storage use", "使用容量", "사용 용량"],
  "其他文件夹（{0} 个）": ["Other folders ({0})", "その他のフォルダー（{0} 件）", "기타 폴더({0}개)"],
  "{0} · 已核实 {1} 首{2}{3}": [
    "{0} · {1} verified songs{2}{3}",
    "{0} · {1} 曲を確認済み{2}{3}",
    "{0} · {1}곡 확인됨{2}{3}"
  ],
  "尚无本地文件夹": ["No local folders yet", "ローカルフォルダーはまだありません", "아직 로컬 폴더가 없습니다"],
  "首本地曲目": ["local tracks", "ローカル曲", "로컬 곡"],
  "暂无可核实字节": [
    "No byte sizes available to verify",
    "確認できるバイト数がありません",
    "확인할 수 있는 바이트 수가 없습니다"
  ],
  "本地已核实占用": ["Verified local storage use", "確認済みのローカル使用容量", "확인된 로컬 사용 용량"],
  "按曲库登记路径的直接父目录分组，不递归合并子目录；完整路径不同的同名文件夹分开统计。按当前指标显示前 7 个，其余合并为“其他文件夹”。": [
    "Group by the immediate parent directory of each library path, without recursively merging subfolders. Same-named folders with different full paths are counted separately. Show the top 7 for the current metric; combine the rest as Other folders.",
    "ライブラリに登録されたパスの直属の親フォルダーで分類し、子フォルダーを再帰的にまとめません。名前が同じでもフルパスが異なるフォルダーは別々に集計します。現在の指標の上位 7 件を表示し、残りは「その他のフォルダー」にまとめます。",
    "라이브러리에 등록된 경로의 바로 위 폴더로 묶으며 하위 폴더를 재귀적으로 합치지 않습니다. 이름이 같아도 전체 경로가 다른 폴더는 따로 집계합니다. 현재 지표의 상위 7개를 표시하고 나머지는 ‘기타 폴더’로 합칩니다."
  ],
  "数量包含缺失/不可读曲目；空间只计成功读取的真实字节，不含联网歌曲和缓存。{0}切换指标不重新扫描；外部文件变化后请手动刷新。": [
    "Counts include missing/unreadable tracks. Storage includes only successfully read bytes, excluding online songs and caches.{0}Changing metrics does not rescan files; refresh manually after external changes.",
    "曲数には見つからない曲や読み取り不可の曲も含みます。容量は正常に読み取れた実際のバイト数だけを集計し、オンライン曲とキャッシュは含みません。{0}指標を切り替えても再スキャンしません。外部で変更した場合は手動で更新してください。",
    "곡 수에는 누락되거나 읽을 수 없는 곡도 포함됩니다. 용량에는 읽기에 성공한 실제 바이트만 포함되며 온라인 곡과 캐시는 제외됩니다.{0}지표를 바꿔도 다시 검사하지 않습니다. 외부 변경 후에는 수동으로 새로 고침하세요."
  ],
  "没有可用于分布统计的本地文件": [
    "No local files available for distribution statistics",
    "内訳を集計できるローカルファイルがありません",
    "분포를 집계할 로컬 파일이 없습니다"
  ],
  "播放歌曲后会在这里生成排行": [
    "Play songs to generate rankings here",
    "曲を再生すると、ここにランキングが表示されます",
    "곡을 재생하면 여기에 순위가 표시됩니다"
  ],
  "随机播放": ["Shuffle", "シャッフル再生", "셔플 재생"],
  "自定义顺序仅在主动拖动或移动条目时保存。": [
    "Custom order is saved only when you deliberately drag or move items.",
    "カスタム順序は、項目をドラッグまたは移動したときだけ保存します。",
    "사용자 지정 순서는 항목을 직접 드래그하거나 이동할 때만 저장됩니다."
  ],
  "升序": ["Ascending", "昇順", "오름차순"],
  "降序": ["Descending", "降順", "내림차순"],
  "切换页面视图；现在：{0}": [
    "Switch page view; current: {0}",
    "ページの表示を切り替え · 現在：{0}",
    "페이지 보기 전환 · 현재: {0}"
  ],
  "取消全选": ["Deselect all", "すべての選択を解除", "전체 선택 해제"],
  "退出多选视图": ["Exit multi-select view", "複数選択を終了", "다중 선택 보기 종료"],
  "音乐索引无法读取": [
    "Could not read the music index",
    "音楽インデックスを読み込めません",
    "음악 색인을 읽을 수 없습니다"
  ],
  "重新选择音乐文件夹": ["Choose music folders again", "音楽フォルダーを選び直す", "음악 폴더 다시 선택"],
  "正在检查音乐索引": ["Checking the music index", "音楽インデックスを確認中", "음악 색인 확인 중"],
  "你的音乐放在哪些文件夹呢？": [
    "Which folders contain your music?",
    "音楽はどのフォルダーにありますか？",
    "음악이 어느 폴더에 있나요?"
  ],
  "软件会扫描这些文件夹（包括所有子文件夹）下的音乐并建立索引。": [
    "The app scans music in these folders, including all subfolders, and builds an index.",
    "選択したフォルダーとすべての子フォルダーの音楽をスキャンして、インデックスを作成します。",
    "앱이 선택한 폴더와 모든 하위 폴더의 음악을 검색하여 색인을 만듭니다."
  ],
  "添加文件夹": ["Add folder", "フォルダーを追加", "폴더 추가"],
  "扫描": ["Scan", "スキャン", "검색"],
  "增大字号": ["Increase font size", "文字を大きくする", "글자 크기 늘리기"],
  "减小字号": ["Decrease font size", "文字を小さくする", "글자 크기 줄이기"],
  "切换为横排歌词": ["Switch to horizontal lyrics", "歌詞を横書きに切り替え", "가사를 가로쓰기로 전환"],
  "切换为竖排歌词": ["Switch to vertical lyrics", "歌詞を縦書きに切り替え", "가사를 세로쓰기로 전환"],
  "锁定歌词；可在播放器中解锁": [
    "Lock lyrics; unlock in the player",
    "歌詞をロック · プレーヤーで解除できます",
    "가사 잠금 · 플레이어에서 해제 가능"
  ],
  "无法锁定歌词：{0}": [
    "Could not lock lyrics: {0}",
    "歌詞をロックできませんでした：{0}",
    "가사를 잠그지 못했습니다: {0}"
  ],
  "调整歌词外观窗口失败：{0}": [
    "Could not resize the appearance window: {0}",
    "歌詞の外観ウィンドウを調整できませんでした：{0}",
    "가사 모양 창의 크기를 조절하지 못했습니다: {0}"
  ],
  "恢复歌词窗口失败：{0}": [
    "Could not restore the lyrics window: {0}",
    "歌詞ウィンドウを復元できませんでした：{0}",
    "가사 창을 복원하지 못했습니다: {0}"
  ],
  "歌词外观": ["Lyrics appearance", "歌詞の外観", "가사 모양"],
  "歌词外观\n{0}": ["Lyrics appearance\n{0}", "歌詞の外観\n{0}", "가사 모양\n{0}"],
  "关闭歌词外观": ["Close lyrics appearance", "歌詞の外観設定を閉じる", "가사 모양 설정 닫기"],
  "原文字号": ["Original text size", "原文の文字サイズ", "원문 글자 크기"],
  "译文字号": ["Translation text size", "訳文の文字サイズ", "번역 글자 크기"],
  "文字不透明度": ["Text opacity", "文字の不透明度", "글자 불투명도"],
  "背景不透明度": ["Background opacity", "背景の不透明度", "배경 불투명도"],
  "文字描边": ["Text outline", "文字の縁取り", "글자 외곽선"],
  "在复杂背景上增加字形对比": [
    "Improve glyph contrast on complex backgrounds",
    "複雑な背景で文字を見やすくします",
    "복잡한 배경에서 글자 대비 향상"
  ],
  "正在跟随播放器主题": ["Following player theme", "プレーヤーのテーマに連動中", "플레이어 테마 사용 중"],
  "跟随播放器主题": ["Follow player theme", "プレーヤーのテーマに合わせる", "플레이어 테마 따르기"],
  "文字颜色": ["Text color", "文字色", "글자 색상"],
  "文字颜色 {0}": ["Text color {0}", "文字色 {0}", "글자 색상 {0}"],
  "任务栏上方单行歌词": [
    "Single-line lyrics above taskbar",
    "タスクバーの上に歌詞を1行で表示",
    "작업 표시줄 위 한 줄 가사"
  ],
  "任务栏上方间距": ["Gap above taskbar", "タスクバー上の間隔", "작업 표시줄 위 간격"],
  "单行高度": ["Single-line height", "1行表示の高さ", "한 줄 높이"],
  "最小字号": ["Minimum font size", "最小文字サイズ", "최소 글자 크기"],
  "优先显示译文": ["Prefer translation", "訳文を優先して表示", "번역 우선 표시"],
  "无译文时显示原文": [
    "Show original text when no translation is available",
    "訳文がない場合は原文を表示",
    "번역이 없으면 원문 표시"
  ],
  "调整单行歌词高度失败：{0}": [
    "Could not adjust single-line lyrics height: {0}",
    "1行歌詞の高さを調整できませんでした：{0}",
    "한 줄 가사 높이를 조절하지 못했습니다: {0}"
  ],
  "调整歌词窗口失败：{0}": [
    "Could not resize the lyrics window: {0}",
    "歌詞ウィンドウを調整できませんでした：{0}",
    "가사 창 크기를 조절하지 못했습니다: {0}"
  ],
  "恢复悬浮歌词": ["Restore floating lyrics", "フローティング歌詞に戻す", "떠 있는 가사로 복원"],
  "选择一条候选歌词填入编辑器；填入后仍需手动保存。": [
    "Choose a lyric candidate to fill the editor. You will still need to save it manually.",
    "候補の歌詞を選んでエディターに取り込みます。取り込み後も手動で保存する必要があります。",
    "가사 후보를 선택해 편집기에 불러오세요. 불러온 뒤에도 직접 저장해야 합니다."
  ],
  "该候选没有返回可用歌词，可选择其他候选或重试。": [
    "This candidate did not return usable lyrics. Choose another candidate or try again.",
    "この候補から利用可能な歌詞を取得できませんでした。別の候補を選ぶか、再試行してください。",
    "이 후보에서 사용할 수 있는 가사를 가져오지 못했습니다. 다른 후보를 선택하거나 다시 시도하세요."
  ],
  "获取歌词失败，可选择其他候选或重试。": [
    "Could not load the lyrics. Choose another candidate or try again.",
    "歌詞を取得できませんでした。別の候補を選ぶか、再試行してください。",
    "가사를 불러오지 못했습니다. 다른 후보를 선택하거나 다시 시도하세요."
  ],
  "请选择一个目标歌单": [
    "Choose a destination playlist",
    "追加先のプレイリストを選択してください",
    "대상 재생목록을 선택하세요"
  ],
  "已选择目标歌单": ["Selected destination", "選択中のプレイリスト", "선택한 대상 재생목록"],
  "{0} 个歌单": ["{0} playlists", "プレイリスト {0} 件", "재생목록 {0}개"],
};
