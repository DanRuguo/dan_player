/// 26.0.5 snapshot 2: library recovery, lyric revisions and playback diagnostics.
/// Order: English, Japanese, Korean. Placeholders contain unmodified user data.
const catalogSnapshot22605 = <String, List<String>>{
  '添加音乐所在的文件夹，确认后刷新曲库。': [
    'Add the folders containing your music, then confirm to refresh the library.',
    '音楽のあるフォルダーを追加し、確定するとライブラリを更新します。',
    '음악이 있는 폴더를 추가한 뒤 확인하면 보관함을 새로 고칩니다.'
  ],
  '移除仅取消收录，不会删除音乐文件。': [
    'Removing a folder excludes it from the library without deleting music files.',
    '削除するとライブラリへの登録だけを解除します。音楽ファイルは削除しません。',
    '폴더를 제거하면 보관함 등록만 해제되며 음악 파일은 삭제하지 않습니다.'
  ],
  '还没有音乐文件夹': ['No music folders yet', '音楽フォルダーはまだありません', '아직 음악 폴더가 없습니다'],
  '添加文件夹，开始整理你的音乐。': [
    'Add a folder to start organizing your music.',
    'フォルダーを追加して音楽の整理を始めましょう。',
    '폴더를 추가하고 음악 정리를 시작하세요.'
  ],
  '复制路径': ['Copy path', 'パスをコピー', '경로 복사'],
  '已复制路径': ['Path copied', 'パスをコピーしました', '경로를 복사했습니다'],
  '复制失败，请选择路径文字后重试。': [
    'Could not copy the path. Select the path text and try again.',
    'コピーできませんでした。パスの文字列を選択してもう一度お試しください。',
    '경로를 복사하지 못했습니다. 경로 텍스트를 선택한 뒤 다시 시도하세요.'
  ],
  '移除文件夹': ['Remove folder', 'フォルダーの登録を解除', '폴더 제거'],
  '歌词修订已保存并锁定': [
    'Lyric revision saved and locked',
    '歌詞の修正版を保存してロックしました',
    '가사 수정본을 저장하고 잠갔습니다'
  ],
  '导出同名 LRC？': [
    'Export an LRC with the same name?',
    '同名の LRC を書き出しますか？',
    '같은 이름의 LRC를 내보낼까요?'
  ],
  '将写入下列文件；已有内容会被替换并保留 .bak 备份。应用内修订另行保存。\n{0}': [
    'The file below will be written. Existing contents will be replaced and kept as a .bak backup. The in-app revision is saved separately.\n{0}',
    '次のファイルに書き込みます。既存の内容は置き換え、.bak バックアップとして保持します。アプリ内の修正版は別途保存します。\n{0}',
    '아래 파일에 저장합니다. 기존 내용은 교체되며 .bak 백업으로 보관됩니다. 앱 내 수정본은 별도로 저장됩니다.\n{0}'
  ],
  '确认导出': ['Confirm export', '書き出しを確定', '내보내기 확인'],
  '导出歌词失败：{0}': [
    'Could not export lyrics: {0}',
    '歌詞を書き出せませんでした：{0}',
    '가사를 내보내지 못했습니다: {0}'
  ],
  '保存应用内修订并锁定，保留原始歌词；+500 ms 表示晚显示 500 ms。': [
    'Save and lock the in-app revision while keeping the original lyrics. +500 ms displays lyrics 500 ms later.',
    '元の歌詞を保持したまま、アプリ内の修正版を保存してロックします。+500 ms は歌詞を 500 ms 遅く表示します。',
    '원본 가사를 유지하고 앱 내 수정본을 저장하여 잠급니다. +500 ms는 가사를 500 ms 늦게 표시합니다.'
  ],
  '导出 LRC…': ['Export LRC…', 'LRC を書き出す…', 'LRC 내보내기…'],
  '请输入 -600000 至 600000 的整数毫秒值。': [
    'Enter a whole number of milliseconds from -600000 to 600000.',
    '-600000 ～ 600000 の整数をミリ秒単位で入力してください。',
    '-600000에서 600000 사이의 정수를 밀리초 단위로 입력하세요.'
  ],
  '时间校准': ['Timing', 'タイミング調整', '타이밍 조정'],
  '正值延后歌词，负值提前歌词。': [
    'Positive values delay lyrics; negative values show them earlier.',
    '正の値は歌詞を遅く、負の値は早く表示します。',
    '양수는 가사를 늦게, 음수는 일찍 표시합니다.'
  ],
  '提前 500 ms': ['500 ms earlier', '500 ms 早く', '500 ms 일찍'],
  '延后 500 ms': ['500 ms later', '500 ms 遅く', '500 ms 늦게'],
  '+500 ms 表示歌词晚显示 500 ms': [
    '+500 ms displays lyrics 500 ms later',
    '+500 ms は歌詞を 500 ms 遅く表示します',
    '+500 ms는 가사를 500 ms 늦게 표시합니다'
  ],
  '重置偏移': ['Reset offset', 'オフセットをリセット', '오프셋 초기화'],
  '保存偏移': ['Save offset', 'オフセットを保存', '오프셋 저장'],
  '同步主窗口、迷你播放器与桌面歌词，不改写原文件。': [
    'Syncs across the main window, mini player and desktop lyrics without changing the original file.',
    'メイン画面、ミニプレーヤー、デスクトップ歌詞で共有します。元のファイルは変更しません。',
    '메인 창, 미니 플레이어와 바탕 화면 가사에 함께 적용하며 원본 파일은 변경하지 않습니다.'
  ],
  '匹配与保护': ['Matching & protection', '照合と保護', '검색 및 보호'],
  '确认并锁定当前歌词': [
    'Confirm and lock these lyrics',
    '現在の歌詞を確定してロック',
    '현재 가사 확인 및 잠금'
  ],
  '保存当前版本；网络内容变化不会覆盖人工成果。': [
    'Keep this version so online changes cannot overwrite your work.',
    '現在の版を保存し、オンラインの内容が変わっても手動で整えた歌詞を上書きしません。',
    '현재 버전을 저장하여 온라인 내용이 바뀌어도 직접 수정한 가사를 덮어쓰지 않습니다.'
  ],
  '无歌词，不再自动查找': [
    'No lyrics; stop automatic lookup',
    '歌詞なし・自動検索を停止',
    '가사 없음 · 자동 검색 중지'
  ],
  '适用于纯音乐；关闭后仍可恢复之前的歌词。': [
    'Useful for instrumental tracks. Turn this off to restore the previous lyrics.',
    'インストゥルメンタル曲向けです。オフにすると以前の歌詞を復元できます。',
    '연주곡에 적합합니다. 이 옵션을 끄면 이전 가사를 복원할 수 있습니다.'
  ],
  '歌词内容与版本': ['Lyrics & versions', '歌詞とバージョン', '가사 및 버전'],
  '编辑修订': ['Edit revision', '修正版を編集', '수정본 편집'],
  '切换歌词来源': ['Change lyric source', '歌詞ソースを変更', '가사 소스 변경'],
  '恢复原始歌词': ['Restore original lyrics', '元の歌詞を復元', '원본 가사 복원'],
  '恢复之前的版本': ['Restore a previous version', '以前のバージョンを復元', '이전 버전 복원'],
  '版本 {0} · {1}': ['Version {0} · {1}', 'バージョン {0} · {1}', '버전 {0} · {1}'],
  '歌词校准与锁定': ['Lyric timing & lock', '歌詞の調整とロック', '가사 조정 및 잠금'],
  '无歌词 · 不再自动查找': [
    'No lyrics · Automatic lookup off',
    '歌詞なし · 自動検索オフ',
    '가사 없음 · 자동 검색 꺼짐'
  ],
  '人工修订 · 已锁定': ['Edited · Locked', '修正版 · ロック済み', '수정됨 · 잠김'],
  '已确认 · 已锁定': ['Confirmed · Locked', '確定済み · ロック済み', '확인됨 · 잠김'],
  '手动选定': ['Manually selected', '手動で選択済み', '직접 선택됨'],
  '自动匹配': ['Automatic matching', '自動照合', '자동 검색'],
  '人工修订': ['Edited revision', '手動修正版', '직접 수정한 버전'],
  '原始副本': ['Original copy', '元のコピー', '원본 사본'],
  '导出播放诊断': ['Export playback diagnostics', '再生診断を書き出す', '재생 진단 내보내기'],
  '诊断文件': ['Diagnostic files', '診断ファイル', '진단 파일'],
  '已导出脱敏播放诊断': [
    'Redacted playback diagnostics exported',
    '個人情報を除いた再生診断を書き出しました',
    '개인정보를 제거한 재생 진단을 내보냈습니다'
  ],
  '导出诊断失败，请检查保存位置': [
    'Could not export diagnostics. Check the save location.',
    '診断を書き出せませんでした。保存先を確認してください。',
    '진단을 내보내지 못했습니다. 저장 위치를 확인하세요.'
  ],
  '播放详情': ['Playback details', '再生の詳細', '재생 상세 정보'],
  '输出、音频处理与诊断': [
    'Output, audio processing & diagnostics',
    '出力・音声処理・診断',
    '출력, 오디오 처리 및 진단'
  ],
  '尚未打开音频，可查看最近错误与输出状态': [
    'No audio is open. Recent errors and output status are available.',
    '音声はまだ開かれていません。最近のエラーと出力状態を確認できます。',
    '아직 오디오를 열지 않았습니다. 최근 오류와 출력 상태를 확인할 수 있습니다.'
  ],
  '以下参数对应正在播放的歌曲': [
    'These values describe the track currently playing',
    '以下は現在再生中の曲の情報です',
    '아래 값은 현재 재생 중인 곡의 정보입니다'
  ],
  '未知 / 未接通检测': [
    'Unknown / Not yet detected',
    '不明 / 未検出',
    '알 수 없음 / 아직 감지되지 않음'
  ],
  '精度未知': ['Unknown precision', '精度不明', '정밀도 알 수 없음'],
  '源精度': ['Source precision', '元の精度', '원본 정밀도'],
  '单曲': ['Track', 'トラック', '트랙'],
  '未应用': ['Not applied', '未適用', '적용되지 않음'],
  'WASAPI 独占 · 格式由设备协商': [
    'WASAPI exclusive · Format negotiated with the device',
    'WASAPI 排他 · 形式はデバイスとネゴシエート',
    'WASAPI 독점 · 장치와 협의한 형식'
  ],
  '系统共享 · 格式由 Windows 决定': [
    'System shared · Format set by Windows',
    'システム共有 · 形式は Windows が決定',
    '시스템 공유 · Windows가 정한 형식'
  ],
  'WASAPI 独占已初始化': [
    'WASAPI exclusive initialized',
    'WASAPI 排他を初期化済み',
    'WASAPI 독점 초기화 완료'
  ],
  '独占解码链路；设备尚未确认': [
    'Exclusive decoding path; device not yet confirmed',
    '排他デコード経路 · デバイスは未確認',
    '독점 디코딩 경로 · 장치 미확인'
  ],
  'BASS 系统共享输出': [
    'BASS system shared output',
    'BASS システム共有出力',
    'BASS 시스템 공유 출력'
  ],
  '未应用、静音或无法检测': [
    'Not applied, muted or undetectable',
    '未適用・ミュート・検出不可',
    '적용되지 않음, 음소거 또는 감지 불가'
  ],
  '{0} 个频段': ['{0} bands', '{0} バンド', '{0}개 밴드'],
  '部分设置未应用': ['Some settings were not applied', '一部の設定が未適用', '일부 설정이 적용되지 않음'],
  '会话 / 状态': ['Session / State', 'セッション / 状態', '세션 / 상태'],
  '音源 / 解码输出': ['Source / Decoded output', '音源 / デコード出力', '소스 / 디코딩 출력'],
  '请求输出': ['Requested output', '要求した出力', '요청한 출력'],
  '已接通链路': ['Active output path', '接続済みの出力経路', '연결된 출력 경로'],
  '设备编号': ['Device number', 'デバイス番号', '장치 번호'],
  '设备实际格式': ['Actual device format', 'デバイスの実際の形式', '실제 장치 형식'],
  '混音 / 处理格式': ['Mixing / Processing format', 'ミキシング / 処理形式', '믹싱 / 처리 형식'],
  'ReplayGain 请求 / 生效': [
    'ReplayGain requested / Applied',
    'ReplayGain 要求 / 適用',
    'ReplayGain 요청 / 적용'
  ],
  '实际响度增益': ['Effective loudness gain', '実際のラウドネスゲイン', '실제 음량 게인'],
  '实际 DSP 音量倍数': [
    'Effective DSP volume multiplier',
    '実際の DSP 音量倍率',
    '실제 DSP 음량 배율'
  ],
  'EQ 请求 / 生效': ['EQ requested / Applied', 'EQ 要求 / 適用', 'EQ 요청 / 적용'],
  '最近结束原因': ['Last end reason', '前回の終了理由', '최근 종료 사유'],
  '最近错误 / 原生代码': [
    'Last error / Native code',
    '最近のエラー / ネイティブコード',
    '최근 오류 / 네이티브 코드'
  ],
  '独占不代表 Bit-perfect 已验证。结束位置来自后端媒体边界，未检测硬件缓冲排空。': [
    'Exclusive mode does not verify bit-perfect playback. End positions come from backend media boundaries; hardware buffer drain is not detected.',
    '排他モードはビットパーフェクトの検証を意味しません。終了位置はバックエンドのメディア境界に基づき、ハードウェアバッファの排出は検出していません。',
    '독점 모드가 비트 퍼펙트 재생의 검증을 뜻하지는 않습니다. 종료 위치는 백엔드 미디어 경계를 기준으로 하며 하드웨어 버퍼 소진은 감지하지 않습니다.'
  ],
  '独占不代表 Bit-perfect 已验证。结束位置来自后端媒体边界，未检测硬件缓冲排空。削波保护只约束已有 ReplayGain 标签，后续 EQ 和变速仍可能改变样本；未提供 R128 或全链路削波测量。':
      [
    'Exclusive mode does not verify bit-perfect playback. End positions come from backend media boundaries; hardware buffer drain is not detected. Clipping protection only uses existing ReplayGain tags; subsequent EQ and speed changes can still alter samples. R128 and end-to-end clipping measurements are not provided.',
    '排他モードはビットパーフェクトの検証を意味しません。終了位置はバックエンドのメディア境界に基づき、ハードウェアバッファの排出は検出していません。クリッピング防止は既存の ReplayGain タグだけに基づき、その後の EQ や速度変更でサンプルが変わる可能性があります。R128 や全経路のクリッピング測定は提供していません。',
    '독점 모드가 비트 퍼펙트 재생의 검증을 뜻하지는 않습니다. 종료 위치는 백엔드 미디어 경계를 기준으로 하며 하드웨어 버퍼 소진은 감지하지 않습니다. 클리핑 방지는 기존 ReplayGain 태그만 사용하며 이후 EQ와 속도 변경으로 샘플이 달라질 수 있습니다. R128 및 전체 경로의 클리핑 측정은 제공하지 않습니다.'
  ],
  '导出仅包含版本、状态、错误分类和输出参数，不包含歌曲名称、私人路径、凭据或音乐文件。': [
    'Exports contain only the version, state, error category and output parameters, without track names, private paths, credentials or music files.',
    '書き出す内容はバージョン、状態、エラー分類、出力パラメーターのみです。曲名、個人のパス、認証情報、音楽ファイルは含みません。',
    '내보내기에는 버전, 상태, 오류 분류 및 출력 매개변수만 포함되며 곡 이름, 개인 경로, 인증 정보나 음악 파일은 포함되지 않습니다.'
  ],
  '刷新详情': ['Refresh details', '詳細を更新', '상세 정보 새로 고침'],
  '导出脱敏诊断': [
    'Export redacted diagnostics',
    '個人情報を除いて診断を書き出す',
    '개인정보를 제거한 진단 내보내기'
  ],
  '自定义顺序保存失败，原有顺序已恢复。': [
    'Could not save the custom order. The previous order was restored.',
    'カスタム順序を保存できませんでした。元の順序に戻しました。',
    '사용자 지정 순서를 저장하지 못해 이전 순서로 복원했습니다.'
  ],
  '自定义顺序已从备份恢复，损坏文件已保留。': [
    'Custom order restored from backup; the damaged file was kept.',
    'カスタム順序をバックアップから復元しました。破損ファイルは保持しています。',
    '백업에서 사용자 지정 순서를 복원했으며 손상된 파일은 보관했습니다.'
  ],
  '自定义顺序读取失败；原文件和备份已保留，恢复前不会覆盖。': [
    'Could not read the custom order. The original file and backup were kept and will not be overwritten before recovery.',
    'カスタム順序を読み込めませんでした。元のファイルとバックアップは保持し、復元するまで上書きしません。',
    '사용자 지정 순서를 읽지 못했습니다. 원본과 백업을 보관했으며 복구 전에는 덮어쓰지 않습니다.'
  ],
  '未找到可用的本地歌词，已保留之前保存的版本。': [
    'No usable local lyrics were found. The previously saved version was kept.',
    '利用可能なローカル歌詞が見つかりませんでした。以前に保存した版を保持しています。',
    '사용 가능한 로컬 가사를 찾지 못해 이전에 저장한 버전을 유지했습니다.'
  ],
  '曲库健康与搬迁': ['Library health & relocation', 'ライブラリの状態と移転', '보관함 상태 및 이전'],
  '查看来源状态，或重新关联已经搬好的音乐目录。': [
    'Check source availability or relink a music folder you have already moved.',
    '音源の状態を確認したり、移動済みの音楽フォルダーを再関連付けしたりします。',
    '소스 상태를 확인하거나 이미 옮긴 음악 폴더를 다시 연결합니다.'
  ],
  '检查曲库': ['Check library', 'ライブラリを確認', '보관함 확인'],
  '重定位目录': ['Relink folder', 'フォルダーを再関連付け', '폴더 다시 연결'],
  '恢复迁移前的资料？': [
    'Restore data from before relocation?',
    '移転前のデータを復元しますか？',
    '이전 전의 데이터를 복원할까요?'
  ],
  '这会成组恢复最近一次目录迁移前的索引、歌单、统计和歌词等资料，撤销迁移后的相关更改。迁移后新增的资料文件会移入该批次的 displaced 目录保留。音乐文件不会移动。保存恢复任务后将退出，下次启动生效。':
      [
    'Restore the index, playlists, statistics, lyrics and related data together from before the most recent folder relocation, undoing subsequent changes to that data. Data files added after relocation will be kept in that batch’s displaced folder. Music files will not move. The player will quit after scheduling recovery; changes take effect on the next launch.',
    '直近のフォルダー移転前の索引、プレイリスト、統計、歌詞などをまとめて復元し、移転後の関連変更を取り消します。移転後に追加したデータファイルは、その処理の displaced フォルダーへ移して保持します。音楽ファイルは移動しません。復元タスクの保存後に終了し、次回起動時に適用します。',
    '최근 폴더 이전 전의 색인, 재생목록, 통계, 가사 등 관련 데이터를 함께 복원하고 이후의 관련 변경을 되돌립니다. 이전 후 추가된 데이터 파일은 해당 작업의 displaced 폴더에 보관됩니다. 음악 파일은 이동하지 않습니다. 복구 작업을 예약한 뒤 종료하며 다음 실행 때 적용됩니다.'
  ],
  '恢复并退出': ['Restore and quit', '復元して終了', '복원 후 종료'],
  '恢复迁移快照': ['Restore relocation snapshot', '移転前のスナップショットを復元', '이전 스냅샷 복원'],
  '曲库健康': ['Library health', 'ライブラリの状態', '보관함 상태'],
  '已检查 {0} 首；关闭窗口会停止后续检查。': [
    'Checked {0} tracks. Closing this window stops further checks.',
    '{0} 曲を確認しました。この画面を閉じると以降の確認を停止します。',
    '{0}곡을 확인했습니다. 창을 닫으면 나머지 확인을 중지합니다.'
  ],
  '最近成功扫描': ['Last successful scan', '前回のスキャン成功', '최근 성공한 스캔'],
  '尚无记录': ['No record yet', '記録はまだありません', '아직 기록 없음'],
  '确认缺失 {0} · 访问受限 {1} · 未能确认 {2}': [
    'Confirmed missing {0} · Access denied {1} · Unverified {2}',
    '欠落確認 {0} · アクセス制限 {1} · 未確認 {2}',
    '누락 확인 {0} · 접근 제한 {1} · 미확인 {2}'
  ],
  '元数据待补 {0} · 近期未读取到封面 {1}': [
    'Metadata incomplete {0} · Recent cover read failures {1}',
    'メタデータ未補完 {0} · 最近のカバー読み込み失敗 {1}',
    '메타데이터 보완 필요 {0} · 최근 표지 읽기 실패 {1}'
  ],
  '离线来源保留原记录；封面仅统计近期实际读取失败，不代表全库封面检查。': [
    'Records for offline sources are retained. Cover counts reflect recent read failures, not a full-library cover scan.',
    'オフライン音源の記録は保持します。カバーは最近の実際の読み込み失敗のみを集計し、ライブラリ全体の確認結果ではありません。',
    '오프라인 소스의 기존 기록은 유지합니다. 표지 수치는 최근 실제 읽기 실패만 집계하며 전체 보관함의 표지 검사 결과는 아닙니다.'
  ],
  '重定位音乐目录': ['Relink music folder', '音楽フォルダーを再関連付け', '음악 폴더 다시 연결'],
  '将旧目录按相对路径关联到新目录。音乐应已搬好；本操作不搬动文件。确认后退出，下次启动成组备份并应用，同时保留歌单顺序、统计与歌词成果。': [
    'Relink the old folder to the new one using relative paths. Move your music first; this operation does not move files. After confirmation the player quits, then backs up and applies the changes together on the next launch, preserving playlist order, statistics and saved lyrics.',
    '相対パスを使って旧フォルダーを新しい場所へ関連付けます。音楽は事前に移動してください。この操作ではファイルを移動しません。確定後に終了し、次回起動時にまとめてバックアップして適用します。プレイリストの順序、統計、保存した歌詞は保持します。',
    '상대 경로로 이전 폴더를 새 폴더에 연결합니다. 음악은 미리 옮겨 두어야 하며 이 작업으로 파일을 이동하지는 않습니다. 확인 후 종료하고 다음 실행 때 변경 사항을 함께 백업하여 적용합니다. 재생목록 순서, 통계와 저장한 가사는 유지됩니다.'
  ],
  '旧目录（可填写离线路径）': [
    'Old folder (offline paths allowed)',
    '旧フォルダー（オフラインのパスも可）',
    '이전 폴더(오프라인 경로 입력 가능)'
  ],
  '新目录': ['New folder', '新しいフォルダー', '새 폴더'],
  '选择搬迁后的音乐目录': [
    'Choose the relocated music folder',
    '移動先の音楽フォルダーを選択',
    '이동한 음악 폴더 선택'
  ],
  '映射 {0} 首 · 新位置缺失 {1} 首 · 冲突 {2} 项': [
    'Mapped {0} tracks · Missing at new location {1} · Conflicts {2}',
    '対応付け {0} 曲 · 新しい場所で欠落 {1} 曲 · 競合 {2} 件',
    '연결된 곡 {0} · 새 위치에서 누락 {1} · 충돌 {2}'
  ],
  '预览映射': ['Preview mapping', '対応付けをプレビュー', '연결 미리 보기'],
  '确认并退出': ['Confirm and quit', '確定して終了', '확인 후 종료'],
  '可访问': ['Available', 'アクセス可能', '접근 가능'],
  '来源离线': ['Source offline', '音源がオフライン', '소스 오프라인'],
  '访问受限': ['Access denied', 'アクセス制限', '접근 제한'],
  '目录缺失': ['Folder missing', 'フォルダーが見つかりません', '폴더 누락'],
  '状态待确认': ['Status unverified', '状態未確認', '상태 미확인'],
  '有 {0} 项旧版统计未明确归属；已保留总数，新的播放分别记录。': [
    '{0} legacy statistics entries have no definite track match. Totals were retained; new plays are recorded separately.',
    '旧版の統計 {0} 件は対応する曲を特定できません。合計は保持し、今後の再生は個別に記録します。',
    '이전 버전의 통계 {0}개가 어느 곡에 속하는지 확정되지 않았습니다. 합계는 유지하고 새 재생은 따로 기록합니다.'
  ],
  '旧版未明确归属 · {0} 个候选': [
    'Unmatched legacy record · {0} candidates',
    '旧版の未特定記録 · 候補 {0} 件',
    '이전 기록의 곡 미확정 · 후보 {0}개'
  ],
  '部分音乐来源暂不可访问，已打开上次曲库。可在设置中查看来源状态或重定位目录。': [
    'Some music sources are temporarily unavailable, so the previous library was opened. Check source status or relink folders in Settings.',
    '一部の音源に一時的にアクセスできないため、前回のライブラリを開きました。設定で音源の状態を確認したり、フォルダーを再関連付けしたりできます。',
    '일부 음악 소스에 일시적으로 접근할 수 없어 이전 보관함을 열었습니다. 설정에서 소스 상태를 확인하거나 폴더를 다시 연결할 수 있습니다.'
  ],
};
