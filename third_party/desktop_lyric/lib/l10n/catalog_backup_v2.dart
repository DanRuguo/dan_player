const Map<String, List<String>> catalogBackupV2 = {
  '加密备份的压缩后大小须小于 64 GiB；更大的曲库可按文件夹分批备份。': [
    'The compressed encrypted backup must be under 64 GiB. Split larger libraries into folder batches.',
    '暗号化バックアップの圧縮後のサイズは 64 GiB 未満にしてください。大きなライブラリはフォルダーごとに分けて保存できます。',
    '암호화 백업은 압축 후 64 GiB 미만이어야 합니다. 큰 라이브러리는 폴더별로 나누어 백업하세요.'
  ],
  '加密备份的压缩后大小必须小于 64 GiB，请减少所选文件夹并分批备份。': [
    'The compressed encrypted backup must be under 64 GiB. Select fewer folders and create separate backups.',
    '暗号化バックアップの圧縮後のサイズは 64 GiB 未満にしてください。選択フォルダーを減らして分割して保存してください。',
    '암호화 백업은 압축 후 64 GiB 미만이어야 합니다. 선택한 폴더 수를 줄여 나누어 백업하세요.'
  ],
  '播放器备份与恢复': ['Player backup and restore', 'プレーヤーのバックアップと復元', '플레이어 백업 및 복원'],
  '音乐、曲库、歌单、统计与设置，自由组合为一个压缩备份；支持密码加密和按需恢复。': [
    'Choose music, library data, playlists, statistics and settings for one compressed backup, with optional password encryption and selective restore.',
    '音楽、ライブラリ、プレイリスト、統計、設定を選び、1つの圧縮ファイルに保存します。パスワード暗号化と選択復元に対応しています。',
    '음악, 라이브러리, 재생목록, 통계, 설정을 선택하여 하나의 압축 파일로 보관합니다. 비밀번호 암호화와 선택 복원을 지원합니다.'
  ],
  '创建播放器备份': ['Create a player backup', 'バックアップを作成', '플레이어 백업 만들기'],
  '选择恢复内容': ['Choose what to restore', '復元する内容を選択', '복원할 내용 선택'],
  '只恢复勾选的内容，其余当前数据保留。歌曲存入目标位置的新文件夹，不覆盖原音乐。': [
    'Restore selected contents and keep other current data. Music goes into a new folder at the destination; original music stays intact.',
    '選んだ内容のみ復元し、その他の現在のデータは保持します。音楽は復元先の新しいフォルダーに保存され、元の音楽を上書きしません。',
    '선택한 내용만 복원하고 다른 현재 데이터는 유지합니다. 음악은 대상 위치의 새 폴더에 저장하며 원본을 덮어쓰지 않습니다.'
  ],
  '音乐与播放器数据可分别选择，压缩保存为一个 .bak 文件。': [
    'Select music and player data separately, then compress them into one .bak file.',
    '音楽とプレーヤーのデータを個別に選択し、1つの .bak ファイルに圧縮して保存します。',
    '음악과 플레이어 데이터를 따로 선택하여 하나의 .bak 파일로 압축합니다.'
  ],
  '快速选择': ['Quick selection', 'まとめて選択', '빠른 선택'],
  '全部内容': ['Everything', 'すべての内容', '전체 내용'],
  '全部歌曲': ['All music', 'すべての音楽', '전체 음악'],
  '全部缓存': ['All player data', 'すべてのデータ', '전체 플레이어 데이터'],
  '曲库索引与播放状态': [
    'Library index and playback state',
    'ライブラリ索引と再生状態',
    '라이브러리 색인 및 재생 상태'
  ],
  '歌单与个人整理': [
    'Playlists and personal organization',
    'プレイリストと個人整理',
    '재생목록 및 개인 정리'
  ],
  '播放器设置': ['Player settings', 'プレーヤー設定', '플레이어 설정'],
  '封面、歌词与其他缓存': [
    'Artwork, lyrics and other cache',
    'ジャケット・歌詞・その他のキャッシュ',
    '표지, 가사 및 기타 캐시'
  ],
  '此备份不含播放器缓存': [
    'This backup contains no player data',
    'このバックアップにはプレーヤーのデータがありません',
    '이 백업에는 플레이어 데이터가 없습니다'
  ],
  '本地音乐文件夹': ['Local music folders', 'ローカル音楽フォルダー', '로컬 음악 폴더'],
  '{0} 个文件夹 · {1} 个源文件 · {2}': [
    '{0} folders · {1} source files · {2}',
    '{0} フォルダー · {1} ファイル · {2}',
    '폴더 {0}개 · 원본 파일 {1}개 · {2}'
  ],
  '{0} 个源文件 · {1}': [
    '{0} source files · {1}',
    '{0} ファイル · {1}',
    '원본 파일 {0}개 · {1}'
  ],
  '此备份不含音乐文件': [
    'This backup contains no music files',
    'このバックアップには音楽ファイルがありません',
    '이 백업에는 음악 파일이 없습니다'
  ],
  '曲库中没有可读取的本地音乐文件': [
    'No readable local music files in the library',
    'ライブラリに読み取り可能なローカル音楽がありません',
    '라이브러리에 읽을 수 있는 로컬 음악 파일이 없습니다'
  ],
  '全选歌曲': ['Select all music', '音楽をすべて選択', '모든 음악 선택'],
  '清除歌曲选择': ['Clear music selection', '音楽の選択を解除', '음악 선택 해제'],
  '已选 {0} 项缓存 · {1} 个音乐文件夹 · {2}': [
    'Selected: {0} data groups · {1} music folders · {2}',
    '選択中：データ {0} 項目 · 音楽 {1} フォルダー · {2}',
    '선택됨: 데이터 {0}개 · 음악 폴더 {1}개 · {2}'
  ],
  '所选数据引用的封面和字体会一并保留。音乐文件已压缩的部分通常无法明显缩小；需要足够的临时磁盘空间。': [
    'Referenced artwork and fonts are included. Already compressed music may shrink very little; sufficient temporary disk space is required.',
    '選んだデータが参照する画像やフォントも保存します。圧縮済みの音楽はサイズがあまり小さくならない場合があります。一時ファイル用の空き容量が必要です。',
    '선택한 데이터가 참조하는 표지와 글꼴도 포함합니다. 이미 압축된 음악은 크기가 거의 줄지 않을 수 있으며 충분한 임시 디스크 공간이 필요합니다.'
  ],
  '密码加密': ['Password encryption', 'パスワード暗号化', '비밀번호 암호화'],
  '密码区分大小写，支持中文、空格和符号；不保存密码，遗失后无法恢复。': [
    'Passwords are case-sensitive and support Unicode, spaces and symbols. The password is not saved and cannot be recovered if lost.',
    'パスワードは大文字・小文字を区別し、日本語、空白、記号も使用できます。保存されないため、忘れると復元できません。',
    '비밀번호는 대소문자를 구분하며 한글, 공백, 기호를 지원합니다. 비밀번호는 저장되지 않으며 잊어버리면 복구할 수 없습니다.'
  ],
  '备份密码': ['Backup password', 'バックアップのパスワード', '백업 비밀번호'],
  '再次输入密码': ['Confirm password', 'パスワードを再入力', '비밀번호 확인'],
  '请输入备份密码': ['Enter a backup password', 'パスワードを入力してください', '백업 비밀번호를 입력하세요'],
  '两次输入的密码不一致': ['Passwords do not match', 'パスワードが一致しません', '비밀번호가 일치하지 않습니다'],
  '隐藏密码': ['Hide password', 'パスワードを非表示', '비밀번호 숨기기'],
  '显示密码': ['Show password', 'パスワードを表示', '비밀번호 표시'],
  '恢复在下次启动时生效。只恢复歌曲时会保留当前曲库索引，可随后扫描恢复的音乐文件夹。': [
    'Restoration takes effect at the next launch. Restoring music only keeps the current index; you can scan the restored music folder afterwards.',
    '復元は次回起動時に反映されます。音楽のみを復元する場合は現在の索引を保持します。後から復元したフォルダーをスキャンできます。',
    '복원은 다음 실행 시 적용됩니다. 음악만 복원하면 현재 색인은 유지되며 이후 복원한 음악 폴더를 스캔할 수 있습니다.'
  ],
  '恢复所选内容': ['Restore selection', '選択内容を復元', '선택한 내용 복원'],
  '备份所选内容': ['Back up selection', '選択内容を保存', '선택한 내용 백업'],
  '保存播放器备份': ['Save player backup', 'バックアップを保存', '플레이어 백업 저장'],
  '选择播放器备份': ['Choose a player backup', 'バックアップを選択', '플레이어 백업 선택'],
  '选择恢复内容的存放位置': ['Choose a restore destination', '復元先を選択', '복원 위치 선택'],
  '已保存 {0} 个文件，包含 {1} 个音乐源文件。': [
    'Saved {0} files, including {1} music source files.',
    '{0} ファイルを保存しました（音楽の元ファイル {1} 個を含む）。',
    '음악 원본 {1}개를 포함하여 파일 {0}개를 저장했습니다.'
  ],
  '无法读取曲库，请等待扫描完成后重试': [
    'Cannot read the library. Wait for scanning to finish and retry.',
    'ライブラリを読み取れません。スキャンが完了してから再試行してください。',
    '라이브러리를 읽을 수 없습니다. 스캔이 끝난 후 다시 시도하세요.'
  ],
  '操作已取消，原有文件保持不变': [
    'Cancelled. Existing files remain unchanged.',
    'キャンセルしました。元のファイルは変更されていません。',
    '취소되었습니다. 기존 파일은 변경되지 않았습니다.'
  ],
  '无法读取备份，请检查密码或文件完整性': [
    'Cannot read the backup. Check the password or file integrity.',
    'バックアップを読み取れません。パスワードとファイルの破損をご確認ください。',
    '백업을 읽을 수 없습니다. 비밀번호나 파일 무결성을 확인하세요.'
  ],
  '恢复已准备完成': ['Restore is ready', '復元の準備が完了しました', '복원 준비 완료'],
  '下次启动时将切换到：\n{0}\n\n已还原 {1} 个音乐源文件；已匹配 {2} 首歌曲引用，{3} 首暂不可用。未勾选的数据保持原状。': [
    'At the next launch, data will switch to:\n{0}\n\nRestored {1} music source files. Matched {2} song references; {3} remain unavailable. Unselected data stays intact.',
    '次回起動時の保存先：\n{0}\n\n音楽の元ファイル {1} 個を復元し、{2} 曲の参照を照合しました。{3} 曲は現在利用できません。未選択のデータは保持されます。',
    '다음 실행 시 데이터 위치가 변경됩니다:\n{0}\n\n음악 원본 {1}개를 복원했습니다. 곡 참조 {2}개를 연결했으며 {3}개는 현재 사용할 수 없습니다. 선택하지 않은 데이터는 유지됩니다.'
  ],
  '解锁备份': ['Unlock backup', 'バックアップのロック解除', '백업 잠금 해제'],
  '请原样输入密码，保留空格、大小写和符号。': [
    'Enter the exact password, including spaces, letter case and symbols.',
    '空白・大文字小文字・記号を含め、正確なパスワードを入力してください。',
    '공백, 대소문자, 기호를 포함하여 비밀번호를 정확히 입력하세요.'
  ],
  '解锁': ['Unlock', 'ロック解除', '잠금 해제'],
  '正在加密备份…': ['Encrypting backup…', 'バックアップを暗号化中…', '백업 암호화 중…'],
  '正在解锁并验证备份…': [
    'Unlocking and verifying backup…',
    'バックアップをロック解除・検証中…',
    '백업 잠금 해제 및 확인 중…'
  ],
  '正在压缩文件…': ['Compressing files…', 'ファイルを圧縮中…', '파일 압축 중…'],
  '正在验证和恢复文件…': [
    'Verifying and restoring files…',
    'ファイルを検証・復元中…',
    '파일 확인 및 복원 중…'
  ],
  '正在准备备份文件…': ['Preparing backup files…', 'バックアップを準備中…', '백업 파일 준비 중…'],
  '正在取消…': ['Cancelling…', 'キャンセル中…', '취소 중…'],
  '取消操作': ['Cancel operation', '処理をキャンセル', '작업 취소'],
};
