/// Snapshot 2 additions found by the full visible-string localization audit.
/// Order: English, Japanese, Korean.
const Map<String, List<String>> catalogSnapshot2Localization = {
  '语言': ['Language', '言語', '언어'],
  '文件格式': ['File format', 'ファイル形式', '파일 형식'],
  '添加时间': ['Date added', '追加日時', '추가 시간'],
  '修改时间': ['Date modified', '更新日時', '수정 시간'],
  '专辑艺术家': ['Album artist', 'アルバムアーティスト', '앨범 아티스트'],
  '文件大小': ['File size', 'ファイルサイズ', '파일 크기'],
  '语言标签': ['Language tag', '言語タグ', '언어 태그'],
  '来源': ['Source', '音源', '소스'],
  '桌面歌词': ['Desktop lyrics', 'デスクトップ歌詞', '바탕 화면 가사'],
  '快捷键': ['Keyboard shortcuts', 'キーボードショートカット', '키보드 단축키'],
  '备份与恢复': ['Backup & restore', 'バックアップと復元', '백업 및 복원'],
  '本地缓存备份与恢复': [
    'Local cache backup & restore',
    'ローカルキャッシュのバックアップと復元',
    '로컬 캐시 백업 및 복원'
  ],
  '将曲库索引、歌单、统计、设置和缓存资源保存为单个 .bak 文件；不复制音乐文件。': [
    'Save the library index, playlists, statistics, settings and cached resources as one .bak file; music files are not copied.',
    'ライブラリ索引、プレイリスト、統計、設定、キャッシュ素材を 1 つの .bak ファイルに保存します。音楽ファイルはコピーしません。',
    '보관함 색인, 재생목록, 통계, 설정과 캐시 리소스를 하나의 .bak 파일로 저장합니다. 음악 파일은 복사하지 않습니다.'
  ],
  '继续': ['Continue', '続行', '계속'],
  '保存本地缓存备份': ['Save local cache backup', 'ローカルキャッシュのバックアップを保存', '로컬 캐시 백업 저장'],
  'Dan Player 备份': ['Dan Player backup', 'Dan Player バックアップ', 'Dan Player 백업'],
  '备份已保存': ['Backup saved', 'バックアップを保存しました', '백업을 저장했습니다'],
  '已写入 {0} 个缓存文件，并记录 {1} 首歌曲的可迁移引用。备份不含音乐文件；恢复前仍需先导入尽量相同的歌曲文件夹。': [
    'Saved {0} cache files and portable references for {1} tracks. Music files are not included; import a folder containing as many of the same tracks as possible before restoring.',
    '{0} 個のキャッシュファイルと {1} 曲分の移行可能な参照を保存しました。音楽ファイルは含まれません。復元前に、できるだけ同じ曲を含むフォルダーを先に取り込んでください。',
    '캐시 파일 {0}개와 곡 {1}개의 이동 가능한 참조를 저장했습니다. 음악 파일은 포함되지 않으므로 복원 전에 가능한 한 같은 곡이 든 폴더를 먼저 가져오세요.'
  ],
  '备份失败，未替换原有备份文件；请稍后重试': [
    'Backup failed and the existing backup was not replaced. Please retry later.',
    'バックアップに失敗しました。既存のバックアップは置き換えていません。後でもう一度お試しください。',
    '백업에 실패해 기존 백업 파일은 교체하지 않았습니다. 잠시 후 다시 시도하세요.'
  ],
  '选择本地缓存备份': [
    'Choose a local cache backup',
    'ローカルキャッシュのバックアップを選択',
    '로컬 캐시 백업 선택'
  ],
  '选择恢复后的缓存存放位置': [
    'Choose where to store the restored cache',
    '復元したキャッシュの保存場所を選択',
    '복원한 캐시를 저장할 위치 선택'
  ],
  '缓存恢复已准备完成': [
    'Cache restore is ready',
    'キャッシュの復元準備が完了しました',
    '캐시 복원 준비가 완료되었습니다'
  ],
  '缓存将在下次启动时安全切换到：\n{0}\n\n已匹配 {1} 首歌曲；{2} 首无法可靠匹配的歌曲信息已跳过。其他可恢复的设置、歌单和统计已保留。':
      [
    'The cache will safely switch to this location on the next launch:\n{0}\n\nMatched {1} tracks; information for {2} tracks that could not be matched reliably was skipped. Other recoverable settings, playlists and statistics were retained.',
    '次回起動時にキャッシュを次の場所へ安全に切り替えます：\n{0}\n\n{1} 曲を照合しました。確実に照合できなかった {2} 曲の情報はスキップしました。その他の復元可能な設定、プレイリスト、統計は保持されています。',
    '다음 실행 때 캐시를 아래 위치로 안전하게 전환합니다:\n{0}\n\n곡 {1}개를 일치시켰으며 확실하게 일치하지 않은 곡 {2}개의 정보는 건너뛰었습니다. 복원 가능한 다른 설정, 재생목록과 통계는 유지했습니다.'
  ],
  '稍后重启': ['Restart later', '後で再起動', '나중에 다시 시작'],
  '恢复失败，当前缓存与缓存位置均未改变': [
    'Restore failed; the current cache and its location were not changed.',
    '復元に失敗しました。現在のキャッシュと保存場所は変更されていません。',
    '복원에 실패했으며 현재 캐시와 캐시 위치는 변경되지 않았습니다.'
  ],
  '恢复已准备完成，但未能自动退出；请手动退出并重新打开播放器': [
    'Restore is ready, but the player could not quit automatically. Quit it manually and reopen it.',
    '復元の準備は完了しましたが、自動で終了できませんでした。手動で終了してからプレーヤーを開き直してください。',
    '복원 준비가 완료되었지만 자동으로 종료하지 못했습니다. 직접 종료한 뒤 플레이어를 다시 여세요.'
  ],
  '恢复已准备完成；请退出并重新打开播放器': [
    'Restore is ready. Quit and reopen the player.',
    '復元の準備が完了しました。プレーヤーを終了して開き直してください。',
    '복원 준비가 완료되었습니다. 플레이어를 종료한 뒤 다시 여세요.'
  ],
  '从备份恢复': ['Restore from backup', 'バックアップから復元', '백업에서 복원'],
  '备份本地缓存？': ['Back up local cache?', 'ローカルキャッシュをバックアップしますか？', '로컬 캐시를 백업할까요?'],
  '备份会保存曲库索引、歌单、歌词来源、播放统计、设置和缓存资源，不会复制音乐文件。\n\n在另一台电脑恢复前，请先准备包含尽量相同歌曲的文件夹，并先让 Dan Player 导入该文件夹；文件夹名称和位置可以不同。':
      [
    'The backup saves the library index, playlists, lyric sources, playback statistics, settings and cached resources; it does not copy music files.\n\nBefore restoring on another computer, prepare a folder containing as many of the same tracks as possible and import it into Dan Player first. The folder name and location may differ.',
    'バックアップにはライブラリ索引、プレイリスト、歌詞ソース、再生統計、設定、キャッシュ素材が保存されます。音楽ファイルはコピーしません。\n\n別のコンピューターで復元する前に、できるだけ同じ曲を含むフォルダーを用意し、先に Dan Player へ取り込んでください。フォルダー名と場所は異なっていてもかまいません。',
    '백업에는 보관함 색인, 재생목록, 가사 소스, 재생 통계, 설정과 캐시 리소스가 저장되며 음악 파일은 복사하지 않습니다.\n\n다른 컴퓨터에서 복원하기 전에 가능한 한 같은 곡이 든 폴더를 준비해 Dan Player로 먼저 가져오세요. 폴더 이름과 위치는 달라도 됩니다.'
  ],
  '恢复本地缓存？': ['Restore local cache?', 'ローカルキャッシュを復元しますか？', '로컬 캐시를 복원할까요?'],
  '请先在这台电脑准备包含尽量相同歌曲的文件夹，并让 Dan Player 完成导入。恢复时会按扫描根内的相对位置、文件名和大小匹配歌曲；无法可靠匹配的信息会跳过并在完成后统计，不会保留旧电脑上失效的绝对路径。':
      [
    'First prepare a folder on this computer containing as many of the same tracks as possible and let Dan Player finish importing it. During restore, tracks are matched by relative location within the scan root, file name and size. Unreliable matches are skipped and counted at the end; invalid absolute paths from the old computer are not retained.',
    'まずこのコンピューターに、できるだけ同じ曲を含むフォルダーを用意し、Dan Player で取り込みを完了してください。復元時は、スキャン元内の相対位置、ファイル名、サイズで曲を照合します。確実に照合できない情報はスキップして完了後に集計し、古いコンピューターの無効な絶対パスは保持しません。',
    '먼저 이 컴퓨터에 가능한 한 같은 곡이 든 폴더를 준비하고 Dan Player에서 가져오기를 완료하세요. 복원할 때 스캔 루트 안의 상대 위치, 파일 이름과 크기로 곡을 일치시킵니다. 확실하게 일치하지 않는 정보는 건너뛰고 완료 후 집계하며 이전 컴퓨터의 유효하지 않은 절대 경로는 유지하지 않습니다.'
  ],
  '替换当前缓存？': [
    'Replace the current cache?',
    '現在のキャッシュを置き換えますか？',
    '현재 캐시를 교체할까요?'
  ],
  '替换已有缓存？': [
    'Replace the existing cache?',
    '既存のキャッシュを置き換えますか？',
    '기존 캐시를 교체할까요?'
  ],
  '目标位置已识别为 Dan Player 缓存：\n{0}\n\n恢复会在下次启动前进行原子替换；若替换失败，原缓存会保留。是否继续？': [
    'The destination contains a Dan Player cache:\n{0}\n\nIt will be atomically replaced before the next launch. If replacement fails, the original cache will be kept. Continue?',
    '保存先に Dan Player のキャッシュがあります：\n{0}\n\n次回起動前にアトミックに置き換えます。置き換えに失敗した場合は元のキャッシュを保持します。続行しますか？',
    '대상 위치에서 Dan Player 캐시를 확인했습니다:\n{0}\n\n다음 실행 전에 원자적으로 교체하며, 교체에 실패하면 기존 캐시를 유지합니다. 계속할까요?'
  ],
  '正在处理…': ['Working…', '処理中…', '처리 중…'],
  '备份到文件': ['Back up to file', 'ファイルにバックアップ', '파일로 백업'],
  '背景副本目录不可用，请检查目录权限。': [
    'The managed background folder is unavailable. Check its permissions.',
    '背景コピー用フォルダーを利用できません。権限を確認してください。',
    '관리 배경 폴더를 사용할 수 없습니다. 폴더 권한을 확인하세요.'
  ],
  '背景副本目录不能指向其它位置。': [
    'The managed background folder cannot point to another location.',
    '背景コピー用フォルダーから別の場所を参照することはできません。',
    '관리 배경 폴더는 다른 위치를 가리킬 수 없습니다.'
  ],
  '请选择一张本地图片。': ['Choose a local image.', 'ローカル画像を選択してください。', '로컬 이미지를 선택하세요.'],
  '图片不存在、为空或无法读取。': [
    'The image is missing, empty or unreadable.',
    '画像が存在しないか、空または読み取り不能です。',
    '이미지가 없거나 비어 있거나 읽을 수 없습니다.'
  ],
  '图片不能超过 20 MiB，请选择较小的图片。': [
    'Images must be 20 MiB or smaller. Choose a smaller image.',
    '画像は 20 MiB 以下にしてください。より小さい画像を選択してください。',
    '이미지는 20 MiB 이하여야 합니다. 더 작은 이미지를 선택하세요.'
  ],
  '图片不能超过 20 MiB。': [
    'Images must be 20 MiB or smaller.',
    '画像は 20 MiB 以下にしてください。',
    '이미지는 20 MiB 이하여야 합니다.'
  ],
  '仅支持静态 PNG、JPEG、WebP 和 BMP 图片。': [
    'Only static PNG, JPEG, WebP and BMP images are supported.',
    '静止画の PNG、JPEG、WebP、BMP のみ対応しています。',
    '정적 PNG, JPEG, WebP, BMP 이미지만 지원합니다.'
  ],
  '暂不支持动图；可为静态图片开启轻缓动态效果。': [
    'Animated images are not supported; gentle motion can be enabled for a static image.',
    'アニメーション画像には対応していません。静止画にはゆるやかな動きを設定できます。',
    '움직이는 이미지는 지원하지 않습니다. 정적 이미지에는 부드러운 움직임을 켤 수 있습니다.'
  ],
  '图片像素数过大（最多 4000 万像素）。': [
    'The image has too many pixels (maximum 40 million).',
    '画像の画素数が大きすぎます（最大 4,000 万画素）。',
    '이미지 픽셀 수가 너무 많습니다(최대 4천만 픽셀).'
  ],
  '无法生成受控的背景副本，请换一张图片。': [
    'Could not create a managed background copy. Choose another image.',
    '管理された背景コピーを作成できませんでした。別の画像を選択してください。',
    '관리 배경 사본을 만들지 못했습니다. 다른 이미지를 선택하세요.'
  ],
  '图片已损坏或无法解码，原背景未改变。': [
    'The image is damaged or cannot be decoded. The background was not changed.',
    '画像が破損しているかデコードできません。背景は変更されていません。',
    '이미지가 손상되었거나 디코딩할 수 없습니다. 배경은 변경되지 않았습니다.'
  ],
  '同名背景副本损坏，请先清理未使用副本。': [
    'A managed copy with the same name is damaged. Clean unused copies first.',
    '同名の背景コピーが破損しています。先に未使用のコピーを整理してください。',
    '같은 이름의 배경 사본이 손상되었습니다. 먼저 사용하지 않는 사본을 정리하세요.'
  ],
  '背景副本空间已满，请先点击“清理未使用副本”再导入。': [
    'Managed background storage is full. Select “Clean unused copies” before importing.',
    '背景コピーの保存領域がいっぱいです。「未使用のコピーを整理」を実行してから取り込んでください。',
    '관리 배경 저장 공간이 가득 찼습니다. 가져오기 전에 “사용하지 않는 사본 정리”를 선택하세요.'
  ],
  '背景副本发生冲突，请重新选择图片。': [
    'The managed background copy conflicted with another file. Choose the image again.',
    '背景コピーが別のファイルと競合しました。画像を選択し直してください。',
    '관리 배경 사본이 다른 파일과 충돌했습니다. 이미지를 다시 선택하세요.'
  ],
  '已保存配置不可读，暂不清理背景副本。': [
    'Saved settings are unreadable, so managed background copies were not cleaned.',
    '保存済み設定を読み取れないため、背景コピーを整理しませんでした。',
    '저장된 설정을 읽을 수 없어 관리 배경 사본을 정리하지 않았습니다.'
  ],
  '已保存配置无效，暂不清理背景副本。': [
    'Saved settings are invalid, so managed background copies were not cleaned.',
    '保存済み設定が無効なため、背景コピーを整理しませんでした。',
    '저장된 설정이 유효하지 않아 관리 배경 사본을 정리하지 않았습니다.'
  ],
  '已保存图片引用不可读，暂不清理背景副本。': [
    'Saved image references are unreadable, so managed background copies were not cleaned.',
    '保存済み画像の参照を読み取れないため、背景コピーを整理しませんでした。',
    '저장된 이미지 참조를 읽을 수 없어 관리 배경 사본을 정리하지 않았습니다.'
  ],
  '歌曲预览暂不可用，已回退为系统缩略图。': [
    'Track preview is unavailable; using the system thumbnail instead.',
    '曲のプレビューを利用できないため、システムのサムネイルを使用します。',
    '곡 미리보기를 사용할 수 없어 시스템 미리보기로 전환했습니다.'
  ],
  '桌面集成初始化失败，请重试。': [
    'Desktop integration could not start. Please retry.',
    'デスクトップ連携を開始できませんでした。再試行してください。',
    '데스크톱 통합을 시작하지 못했습니다. 다시 시도하세요.'
  ],
  '桌面集成暂不可用，请重试。': [
    'Desktop integration is temporarily unavailable. Please retry.',
    'デスクトップ連携を一時的に利用できません。再試行してください。',
    '데스크톱 통합을 일시적으로 사용할 수 없습니다. 다시 시도하세요.'
  ],
  '系统托盘暂不可用；关闭窗口将正常退出。': [
    'The system tray is unavailable; closing the window will quit normally.',
    'システムトレイを利用できません。ウィンドウを閉じると通常どおり終了します。',
    '시스템 트레이를 사용할 수 없어 창을 닫으면 정상 종료됩니다.'
  ],
  '恢复播放器窗口失败，请重试。': [
    'Could not restore the player window. Please retry.',
    'プレーヤーウィンドウを復元できませんでした。再試行してください。',
    '플레이어 창을 복원하지 못했습니다. 다시 시도하세요.'
  ],
  '更新桌面播放控制失败，请重试。': [
    'Could not update desktop playback controls. Please retry.',
    'デスクトップの再生操作を更新できませんでした。再試行してください。',
    '데스크톱 재생 컨트롤을 업데이트하지 못했습니다. 다시 시도하세요.'
  ],
  '桌面操作失败，请重试。': [
    'The desktop action failed. Please retry.',
    'デスクトップ操作に失敗しました。再試行してください。',
    '데스크톱 작업에 실패했습니다. 다시 시도하세요.'
  ],

  // Background selectors were enum labels and therefore escaped literal-call
  // catalog coverage even though their surrounding descriptions were localised.
  '不模糊': ['Solid', '単色', '단색'],
  '窗后背景': ['Behind-window background', 'ウィンドウ背面', '창 뒤 배경'],
  '专辑封面': ['Album artwork', 'アルバムアート', '앨범 아트'],
  '自定义图片': ['Custom image', 'カスタム画像', '사용자 지정 이미지'],
  '主窗口': ['Main window', 'メインウィンドウ', '메인 창'],
  '歌词播放页': ['Now playing', '再生中', '지금 재생 중'],
  'Windows 实时窗后毛玻璃可用': [
    'Windows live behind-window blur is available',
    'Windows のリアルタイム背景ぼかしを利用できます',
    'Windows 실시간 창 뒤 흐림 효과를 사용할 수 있습니다'
  ],
  '未选择窗后背景，原生毛玻璃已停用': [
    'Behind-window background is not selected; native blur is off',
    'ウィンドウ背面が選択されていないため、ネイティブぼかしは無効です',
    '창 뒤 배경을 선택하지 않아 네이티브 흐림 효과가 꺼져 있습니다'
  ],
  '系统透明效果已关闭，主界面使用实色背景': [
    'System transparency is off; the main window uses a solid background',
    'システムの透明効果が無効なため、メイン画面は単色背景を使用します',
    '시스템 투명 효과가 꺼져 있어 메인 화면은 단색 배경을 사용합니다'
  ],
  '高对比度模式，主界面使用系统背景色': [
    'High contrast is active; the main window uses the system background',
    'ハイコントラストのため、メイン画面はシステム背景色を使用します',
    '고대비 모드에서는 메인 화면이 시스템 배경색을 사용합니다'
  ],
  '节电模式，主界面暂时使用实色背景': [
    'Battery saver is active; the main window temporarily uses a solid background',
    '省電モードのため、メイン画面は一時的に単色背景を使用します',
    '절전 모드에서는 메인 화면이 일시적으로 단색 배경을 사용합니다'
  ],
  '正在初始化 Windows 窗后毛玻璃': [
    'Initialising Windows behind-window blur',
    'Windows の背景ぼかしを初期化しています',
    'Windows 창 뒤 흐림 효과를 초기화하는 중입니다'
  ],
  '窗后毛玻璃暂不可用，主界面使用实色背景': [
    'Behind-window blur is unavailable; the main window uses a solid background',
    '背景ぼかしを利用できないため、メイン画面は単色背景を使用します',
    '창 뒤 흐림 효과를 사용할 수 없어 메인 화면은 단색 배경을 사용합니다'
  ],
  '无法连接播放器，外观尚未保存。': [
    'Could not connect to the player; appearance has not been saved.',
    'プレーヤーに接続できず、外観は保存されていません。',
    '플레이어에 연결하지 못해 모양이 저장되지 않았습니다.'
  ],
  '外观保存失败，当前会话仍然生效。': [
    'Could not save the appearance; it still applies for this session.',
    '外観を保存できませんでした。このセッションでは有効です。',
    '모양을 저장하지 못했지만 이번 세션에는 적용됩니다.'
  ],
  '歌词窗口布局调整失败，请重新切换显示模式。': [
    'Could not adjust the lyrics-window layout. Switch the display mode again.',
    '歌詞ウィンドウの配置を調整できませんでした。表示モードを切り替え直してください。',
    '가사 창 레이아웃을 조정하지 못했습니다. 표시 모드를 다시 전환하세요.'
  ],
  '歌词窗口布局调整失败，已保留原窗口；请重新切换显示模式重试。': [
    'Could not adjust the lyrics-window layout; the original window was kept. Switch the display mode again to retry.',
    '歌詞ウィンドウの配置を調整できなかったため、元のウィンドウを維持しました。表示モードを切り替え直してください。',
    '가사 창 레이아웃을 조정하지 못해 기존 창을 유지했습니다. 표시 모드를 다시 전환해 보세요.'
  ],
  '进入迷你播放器': ['Enter mini player', 'ミニプレーヤーに切り替え', '미니 플레이어로 전환'],
  '还原完整播放器': ['Restore full player', 'フルプレーヤーに戻す', '전체 플레이어로 복원'],
  '切换窗口置顶': ['Toggle always on top', '常に手前に表示を切り替え', '항상 위 전환'],
  '{0}失败，已保留原窗口状态，请重试。': [
    '{0} failed. The previous window state was kept; please retry.',
    '{0}に失敗しました。元のウィンドウ状態を維持しました。再試行してください。',
    '{0}에 실패했습니다. 이전 창 상태를 유지했으니 다시 시도하세요.'
  ],
  '{0}失败，部分窗口状态未能恢复，请重试还原窗口。': [
    '{0} failed and some window state could not be restored. Try restoring the window again.',
    '{0}に失敗し、一部のウィンドウ状態を復元できませんでした。ウィンドウの復元を再試行してください。',
    '{0}에 실패했고 일부 창 상태를 복원하지 못했습니다. 창 복원을 다시 시도하세요.'
  ],

  // Compact lyric status text is application UI; actual lyrics and tags still
  // pass through unchanged because unknown catalog keys are never translated.
  '选择歌曲，开始聆听': [
    'Choose a track to start listening',
    '曲を選んで再生を始めましょう',
    '곡을 선택해 감상을 시작하세요'
  ],
  '这里会显示当前歌词': [
    'Current lyrics will appear here',
    '現在の歌詞がここに表示されます',
    '현재 가사가 여기에 표시됩니다'
  ],
  '正在加载歌词…': ['Loading lyrics…', '歌詞を読み込み中…', '가사 불러오는 중…'],
  '与完整播放器同步': ['Synced with the full player', 'フルプレーヤーと同期', '전체 플레이어와 동기화'],
  '暂无歌词': ['No lyrics available', '歌詞はありません', '사용 가능한 가사 없음'],
  '可在完整播放器选择歌词': [
    'Choose lyrics in the full player',
    'フルプレーヤーで歌詞を選択できます',
    '전체 플레이어에서 가사를 선택할 수 있습니다'
  ],
  '歌词加载失败': ['Could not load lyrics', '歌詞を読み込めませんでした', '가사를 불러오지 못했습니다'],
  '请在完整播放器重试或切换来源': [
    'Retry or change the source in the full player',
    'フルプレーヤーで再試行するか音源を変更してください',
    '전체 플레이어에서 다시 시도하거나 소스를 변경하세요'
  ],
  '纯音乐，请欣赏': [
    'Instrumental — enjoy the music',
    'インストゥルメンタルをお楽しみください',
    '연주곡을 감상하세요'
  ],
  '无时间轴歌词 · 完整内容请在歌词详情页查看': [
    'Unsynced lyrics · Open lyric details for the full text',
    '同期なし歌詞 · 全文は歌詞詳細で確認できます',
    '시간 정보 없는 가사 · 전체 내용은 가사 상세에서 확인하세요'
  ],
  '歌词即将开始': ['Lyrics will start shortly', 'まもなく歌詞が始まります', '곧 가사가 시작됩니다'],
  '间奏 · 聆听音乐': [
    'Interlude · Enjoy the music',
    '間奏 · 音楽をお楽しみください',
    '간주 · 음악을 감상하세요'
  ],
  '下一句 · {0}': ['Next · {0}', '次の歌詞 · {0}', '다음 가사 · {0}'],
  '译文': ['Translation', '訳文', '번역'],
  '下一句': ['Next line', '次の歌詞', '다음 가사'],
  '首句': ['First line', '最初の歌詞', '첫 가사'],

  '桌面歌词方向保存失败；当前会话仍生效，请在设置中重试。': [
    'Could not save the desktop-lyrics direction. It still applies for this session; retry in Settings.',
    'デスクトップ歌詞の方向を保存できませんでした。このセッションでは有効です。設定で再試行してください。',
    '바탕 화면 가사 방향을 저장하지 못했습니다. 이번 세션에는 적용되며 설정에서 다시 시도하세요.'
  ],
  '桌面歌词外观保存失败；当前会话仍生效，可在歌词外观中重试保存。': [
    'Could not save the desktop-lyrics appearance. It still applies for this session; retry in Lyric appearance.',
    'デスクトップ歌詞の外観を保存できませんでした。このセッションでは有効です。歌詞の外観で再試行できます。',
    '바탕 화면 가사 모양을 저장하지 못했습니다. 이번 세션에는 적용되며 가사 모양에서 다시 시도할 수 있습니다.'
  ],
  '桌面歌词启动失败：{0}': [
    'Could not start desktop lyrics: {0}',
    'デスクトップ歌詞を起動できませんでした：{0}',
    '바탕 화면 가사를 시작하지 못했습니다: {0}'
  ],
  '调整播放速度失败：{0}': [
    'Could not change playback speed: {0}',
    '再生速度を変更できませんでした：{0}',
    '재생 속도를 변경하지 못했습니다: {0}'
  ],
  '请等待当前音乐加载完成后再切换输出模式': [
    'Wait for the current track to finish loading before changing output mode',
    '現在の曲の読み込みが完了してから出力モードを変更してください',
    '현재 곡 로딩이 끝난 뒤 출력 모드를 변경하세요'
  ],
  '音频输出已切换，但设置保存失败：{0}': [
    'Audio output changed, but the setting could not be saved: {0}',
    'オーディオ出力は変更されましたが、設定を保存できませんでした：{0}',
    '오디오 출력은 변경되었지만 설정을 저장하지 못했습니다: {0}'
  ],
  '切换音频输出失败：{0}': [
    'Could not change audio output: {0}',
    'オーディオ出力を変更できませんでした：{0}',
    '오디오 출력을 변경하지 못했습니다: {0}'
  ],
  '已恢复歌曲，但原播放位置暂不可用': [
    'The track was restored, but its previous position is temporarily unavailable',
    '曲は復元されましたが、元の再生位置は一時的に利用できません',
    '곡은 복원했지만 이전 재생 위치를 일시적으로 사용할 수 없습니다'
  ],
  '输出模式已切换，但暂时无法恢复原播放位置': [
    'Output mode changed, but the previous position could not be restored',
    '出力モードは変更されましたが、元の再生位置を復元できませんでした',
    '출력 모드는 변경했지만 이전 재생 위치를 복원하지 못했습니다'
  ],
  '输出模式切换失败，已恢复原模式：{0}': [
    'Could not change output mode; the previous mode was restored: {0}',
    '出力モードを変更できなかったため、元のモードに戻しました：{0}',
    '출력 모드 변경에 실패해 이전 모드로 복원했습니다: {0}'
  ],
  '音频设备不可用，原模式也未能恢复；请检查设备后重试': [
    'The audio device is unavailable and the previous mode could not be restored. Check the device and retry.',
    'オーディオデバイスを利用できず、元のモードにも戻せませんでした。デバイスを確認して再試行してください。',
    '오디오 장치를 사용할 수 없고 이전 모드도 복원하지 못했습니다. 장치를 확인한 뒤 다시 시도하세요.'
  ],
  '切换音频输出失败，原模式保持不变：{0}': [
    'Could not change audio output; the previous mode is unchanged: {0}',
    'オーディオ出力を変更できませんでした。元のモードは変更されていません：{0}',
    '오디오 출력을 변경하지 못했습니다. 이전 모드는 그대로 유지됩니다: {0}'
  ],
};
