const Map<String, List<String>> catalogFolderTools = {
  '播放器缓存与数据': ['Player cache and data', 'キャッシュとプレーヤーデータ', '플레이어 캐시 및 데이터'],
  '封面、歌词、歌单、统计与设置': [
    'Artwork, lyrics, playlists, statistics and settings',
    '画像、歌詞、プレイリスト、統計と設定',
    '커버, 가사, 재생목록, 통계 및 설정'
  ],
  '在文件资源管理器浏览': ['Browse in File Explorer', 'エクスプローラーで開く', '파일 탐색기에서 보기'],
  '移动音乐文件夹': ['Move music folder', '音楽フォルダーを移動', '음악 폴더 이동'],
  '移动缓存文件夹': ['Move cache folder', 'キャッシュフォルダーを移動', '캐시 폴더 이동'],
  '查看占用统计': ['View storage usage', '使用容量の統計を表示', '저장 공간 통계 보기'],
  '无法打开此文件夹': ['Unable to open this folder', 'このフォルダーを開けません', '이 폴더를 열 수 없습니다'],
  '选择移入的文件夹（可新建文件夹）': [
    'Choose the destination parent folder (you can create a folder)',
    '移動先の親フォルダーを選択（新規作成可）',
    '이동할 상위 폴더 선택 (새 폴더 생성 가능)'
  ],
  '从 {0}\n移至 {1}': ['From {0}\nTo {1}', '移動元 {0}\n移動先 {1}', '원본 {0}\n대상 {1}'],
  '缓存与播放器资料一起移动，保留歌单、歌词、统计和设置。确认后退出，下次打开时先完成剪切和路径同步。': [
    'Move cache and player data together, keeping playlists, lyrics, statistics and settings. Confirm to quit; the next launch completes the cut and path updates first.',
    'キャッシュとデータを一緒に移動し、プレイリスト、歌詞、統計と設定を保持します。確認すると終了し、次回起動時に移動とパスの更新を先に完了します。',
    '캐시와 플레이어 데이터를 함께 이동하며 재생목록, 가사, 통계와 설정을 보존합니다. 확인하면 종료하고 다음 실행 시 이동 및 경로 갱신을 먼저 완료합니다.'
  ],
  '整个文件夹及其子文件夹将剪切到新位置，歌单、歌词、书签和统计保持关联。确认后退出，下次打开时先完成移动和路径同步。': [
    'Cut the folder and its subfolders to the new location, keeping playlist, lyric, bookmark and statistics links. Confirm to quit; the next launch completes the move and path updates first.',
    'フォルダーとその中身を新しい場所に移動し、プレイリスト、歌詞、ブックマークと統計の関連を保持します。確認すると終了し、次回起動時に移動とパス更新を先に完了します。',
    '폴더와 하위 폴더를 새 위치로 이동하고 재생목록, 가사, 북마크, 통계 연결을 유지합니다. 확인하면 종료하고 다음 실행 시 이동 및 경로 갱신을 먼저 완료합니다.'
  ],
  '不会覆盖已有文件夹；跨盘移动先校验文件，再删除原文件。': [
    'Existing folders are never overwritten. Cross-drive moves verify delivery before removing the original files.',
    '既存フォルダーは上書きしません。別ドライブへの移動はファイルを検証してから元のファイルを削除します。',
    '기존 폴더를 덮어쓰지 않습니다. 드라이브 간 이동은 파일 검증 후 원본을 삭제합니다.'
  ],
  '确认移动并退出': ['Confirm move and quit', '移動を確認して終了', '이동 확인 및 종료'],
  '移动已安排，请退出并重新打开播放器完成移动': [
    'Move scheduled. Quit and reopen the player to complete it.',
    '移動を予約しました。終了して再起動すると完了します。',
    '이동이 예약되었습니다. 플레이어를 종료 후 다시 실행하세요.'
  ],
  '无法移动：请检查目录权限，目标不得已存在、包含原目录或位于原目录内，且不能有其他待完成的迁移。': [
    'Unable to move. Check permissions; the destination must not exist, contain the source or be inside it. Complete any pending migration first.',
    '移動できません。権限を確認してください。移動先は既存、移動元の親または子フォルダーにできません。未完了の移行を先に完了してください。',
    '이동할 수 없습니다. 권한을 확인하세요. 대상은 기존 폴더, 원본의 상위 또는 하위 폴더일 수 없습니다. 대기 중인 이전을 먼저 완료하세요.'
  ],
  '缓存与播放器数据占用': [
    'Cache and player data storage',
    'キャッシュとプレーヤーデータの容量',
    '캐시 및 플레이어 데이터 사용량'
  ],
  '{0} 个文件': ['{0} files', '{0} ファイル', '파일 {0}개'],
  '封面缓存': ['Artwork cache', '画像キャッシュ', '커버 캐시'],
  '联网歌词缓存': ['Online lyric cache', 'オンライン歌詞キャッシュ', '온라인 가사 캐시'],
  '评论缓存': ['Comment cache', 'コメントキャッシュ', '댓글 캐시'],
  '其他缓存': ['Other cache', 'その他のキャッシュ', '기타 캐시'],
  '自选图片与封面': ['Custom images and artwork', '選択した画像とカバー', '사용자 이미지 및 커버'],
  '曲库与用户资料': ['Library and user data', 'ライブラリとユーザーデータ', '라이브러리 및 사용자 데이터'],
  '迁移与恢复快照': [
    'Migration and recovery snapshots',
    '移行と復元のスナップショット',
    '이전 및 복구 스냅샷'
  ],
  '更新与临时文件': ['Updates and temporary files', '更新と一時ファイル', '업데이트 및 임시 파일'],
  '其他数据': ['Other data', 'その他のデータ', '기타 데이터'],
  '统计未包含：不可读 {0} 项、链接 {1} 项{2}': [
    'Excluded: {0} unreadable entries, {1} links{2}',
    '未集計：読み取り不可 {0} 件、リンク {1} 件{2}',
    '제외: 읽기 불가 {0}개, 링크 {1}개{2}'
  ],
  '；已达到扫描上限': ['; scan limit reached', '（走査上限に到達）', '; 검색 제한 도달'],
  '无法读取此目录的占用信息': [
    'Unable to read storage usage for this folder',
    'このフォルダーの容量を読み取れません',
    '이 폴더의 사용량을 읽을 수 없습니다'
  ],
  '正在读取占用信息…': ['Reading storage usage…', '使用容量を読み取り中…', '사용량 읽는 중…'],
  '实际文件字节；用户资料、自选图片与可重建缓存分别统计。链接不跟随，仅打开此页或手动刷新时读取。': [
    'Actual file bytes, with user data, custom images and rebuildable caches reported separately. Links are not followed. Read only on page entry or manual refresh.',
    '実際のファイル容量を集計し、ユーザーデータ、選択画像と再生成可能なキャッシュを分けて表示します。リンクは辿らず、ページ表示または手動更新時のみ読み取ります。',
    '실제 파일 크기이며 사용자 데이터, 사용자 이미지, 재생성 가능한 캐시를 구분합니다. 링크를 따라가지 않으며 페이지 진입 또는 수동 새로고침 시에만 읽습니다.'
  ],
  '{0} 首 · 已核实 {1} · 缺失 {2} · 不可读 {3}': [
    '{0} tracks · Verified {1} · Missing {2} · Unreadable {3}',
    '{0} 曲 · 確認済 {1} · 不明 {2} · 読取不可 {3}',
    '{0}곡 · 확인 {1} · 누락 {2} · 읽기 불가 {3}'
  ],
  '文件夹移动尚未完成': [
    'Folder move is incomplete',
    'フォルダーの移動は未完了です',
    '폴더 이동이 완료되지 않았습니다'
  ],
  '播放器尚未载入资料。已保留移动记录和仍未剪切的原文件，请连接相关磁盘、检查权限后重试；不会覆盖其他文件夹。': [
    'Player data has not loaded. The move journal and originals not yet cut are retained. Connect the disks and check permissions, then retry. Other folders are never overwritten.',
    'データはまだ読み込まれていません。移動記録と未削除の元ファイルは保持されています。ディスクと権限を確認して再試行してください。他のフォルダーは上書きしません。',
    '데이터를 아직 불러오지 않았습니다. 이동 기록과 아직 삭제하지 않은 원본을 보존했습니다. 디스크와 권한을 확인 후 재시도하세요. 다른 폴더를 덮어쓰지 않습니다.'
  ],
  '重试并继续': ['Retry and continue', '再試行して続行', '재시도 및 계속'],
  '曲库迁移尚未完成': ['Library migration is incomplete', 'ライブラリ移行は未完了です', '라이브러리 이전이 완료되지 않았습니다'],
  '播放器尚未载入曲库。迁移现场和同批快照已保留；请连接相关目录后重试。只有明确确认的文件夹移动会剪切文件，其他重定位操作只更新关联。': [
    'The library has not loaded. The migration journal and batch snapshots are retained. Connect the folders and retry. Only explicitly confirmed folder moves cut files; other relocation updates references.',
    'ライブラリはまだ読み込まれていません。移行記録とスナップショットは保持されています。関連フォルダーを接続して再試行してください。明示的に確認したフォルダー移動のみファイルを移動し、その他の再関連付けは参照だけを更新します。',
    '라이브러리를 아직 불러오지 않았습니다. 이전 기록과 스냅샷을 보존했습니다. 관련 폴더를 연결 후 재시도하세요. 명시적으로 확인한 폴더 이동만 파일을 이동하며 다른 경로 재설정은 연결만 갱신합니다.'],
  '恢复迁移前的资料？': ['Restore pre-migration data?', '移行前のデータを復元しますか？', '이전 전 데이터를 복원할까요?'],
  '将成组恢复这一批次的全部资料；尚未开始的迁移则直接取消。': [
    'Restore the entire batch together, or cancel a migration that has not started.',
    'このバッチの全データをまとめて復元します。未開始の移行はキャンセルします。',
    '해당 배치의 모든 데이터를 함께 복원하며 아직 시작하지 않은 이전은 취소합니다.'],
  '恢复原资料': ['Restore original data', '元のデータを復元', '원본 데이터 복원'],
};
