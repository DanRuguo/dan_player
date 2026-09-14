const catalogAudioTrim = <String, List<String>>{
  '请先安装或修复裁剪组件': [
    'Install or repair the trimming component first.',
    '先にトリミングコンポーネントをインストールまたは修復してください。',
    '먼저 자르기 구성 요소를 설치하거나 복구하세요.'
  ],
  '安装裁剪组件': ['Set up trimming', 'トリミングの準備', '자르기 설정'],
  '裁剪需要 FFmpeg、FFprobe 和 FFplay。未找到可用的完整工具。可从 GitHub 下载约 70 MB 的组件，将使用 Windows 系统代理。':
      [
    'Trimming requires FFmpeg, FFprobe and FFplay. A complete working toolset was not found. Download the approximately 70 MB component from GitHub using the Windows system proxy.',
    'FFmpeg、FFprobe、FFplay が必要です。利用可能なツール一式が見つかりません。Windows のシステムプロキシを使用して GitHub から約 70 MB をダウンロードできます。',
    'FFmpeg, FFprobe, FFplay가 필요합니다. 사용 가능한 도구 모음을 찾지 못했습니다. Windows 시스템 프록시를 사용하여 GitHub에서 약 70 MB를 다운로드할 수 있습니다.'
  ],
  '也可以从官网下载 Windows 完整编译包，将 bin 目录中的程序及 DLL 放到以下目录，然后点击“我已安装好”。': [
    'Alternatively, get a complete Windows build from the official download page. Copy the programs and DLLs from its bin folder to the folder below, then select “I have installed it”.',
    '公式ダウンロードページから Windows 用の完全なビルドを入手し、bin 内のプログラムと DLL を下のフォルダーにコピーして「インストール済み」を押してください。',
    '공식 다운로드 페이지에서 Windows 전체 빌드를 받아 bin 폴더의 프로그램과 DLL을 아래 폴더에 복사한 뒤 “설치 완료”를 누르세요.'
  ],
  '正在检查并安装组件…': ['Checking and installing…', '確認・インストール中…', '확인 및 설치 중…'],
  '组件仍不可用。请检查网络、工具是否完整及目录权限，或手动安装后重试。': [
    'The component is still unavailable. Check the network, tool files and folder permissions, or install manually and retry.',
    'まだ利用できません。ネットワーク、ツール一式、フォルダー権限を確認するか、手動でインストールして再試行してください。',
    '구성 요소를 사용할 수 없습니다. 네트워크, 도구 파일, 폴더 권한을 확인하거나 수동 설치 후 다시 시도하세요.'
  ],
  '我已安装好': ['I have installed it', 'インストール済み', '설치 완료'],
  '从 GitHub 下载': ['Download from GitHub', 'GitHub からダウンロード', 'GitHub에서 다운로드'],
  '此文件包含不支持的混合容器或标签布局，暂不能安全裁剪。原文件未修改。': [
    'This file uses an unsupported mixed container or tag layout and cannot be trimmed safely. The original is unchanged.',
    'このファイルは未対応の混在コンテナまたはタグ構造のため、安全にトリミングできません。元のファイルは変更されていません。',
    '지원하지 않는 혼합 컨테이너 또는 태그 구조이므로 안전하게 자를 수 없습니다. 원본 파일은 변경되지 않았습니다.'
  ],
  '部分歌词格式无法自动对齐，已保留原文，请手动校准': [
    'Some lyric formats cannot be aligned automatically. The original text was kept; calibrate it manually.',
    '一部の歌詞形式は自動調整できません。原文を保持しました。手動でタイミングを調整してください。',
    '일부 가사 형식은 자동으로 맞출 수 없습니다. 원문을 유지했으니 직접 시간을 보정하세요.'
  ],
  '歌词回滚未完成，已保留现有文件。恢复文件位于：': [
    'Lyrics could not be rolled back. Existing files were kept. Recovery file:',
    '歌詞を元に戻せませんでした。既存のファイルは保持しています。復元用ファイル：',
    '가사를 되돌리지 못했습니다. 기존 파일은 유지했습니다. 복원 파일 위치:'
  ],
  '原歌词恢复副本已保留：': [
    'Original lyrics recovery copy kept:',
    '元の歌詞の復元用コピーを保持しました：',
    '원본 가사 복원용 사본을 유지했습니다:'
  ],
  '歌词临时文件未能清理，请检查：': [
    'Temporary lyric files could not be removed. Check:',
    '歌詞の一時ファイルを削除できませんでした。確認してください：',
    '가사 임시 파일을 삭제하지 못했습니다. 확인할 위치:'
  ],
  '无法读取或调整独立歌词，请检查歌词文件。': [
    'Cannot read or adjust the separate lyrics file. Check that file.',
    '外部歌詞ファイルの読み込みや調整ができません。ファイルを確認してください。',
    '별도 가사 파일을 읽거나 조정할 수 없습니다. 가사 파일을 확인하세요.'
  ],
  '独立歌词文件过大，暂不能安全裁剪。': [
    'The separate lyrics file is too large to trim safely.',
    '外部歌詞ファイルが大きすぎるため、安全にトリミングできません。',
    '별도 가사 파일이 너무 커서 안전하게 자를 수 없습니다.'
  ],
  '目标歌词文件已存在，请换一个文件名保存副本。': [
    'The destination lyrics file already exists. Choose another name for the copy.',
    '保存先に歌詞ファイルが存在します。コピーには別の名前を指定してください。',
    '저장 위치에 가사 파일이 이미 있습니다. 사본에 다른 파일 이름을 사용하세요.'
  ],
  '独立歌词已发生变化，请重新打开裁剪窗口。': [
    'The separate lyrics file changed. Reopen the trim dialog.',
    '外部歌詞ファイルが変更されました。トリミング画面を開き直してください。',
    '별도 가사 파일이 변경되었습니다. 자르기 창을 다시 여세요.'
  ],
  '独立歌词校验失败，歌曲尚未被修改。': [
    'Lyrics verification failed. The song has not been changed.',
    '歌詞の検証に失敗しました。曲はまだ変更されていません。',
    '가사 검증에 실패했습니다. 곡은 아직 변경되지 않았습니다.'
  ],
  '当前平台暂不支持安全保存独立歌词。': [
    'Safe saving of separate lyrics is not supported on this platform yet.',
    'このプラットフォームでは外部歌詞の安全な保存にまだ対応していません。',
    '이 플랫폼에서는 별도 가사의 안전한 저장을 아직 지원하지 않습니다.'
  ],
  '不支持通过符号链接或目录联接修改独立歌词。': [
    'Editing separate lyrics through symbolic links or directory junctions is not supported.',
    'シンボリックリンクやジャンクションを通した外部歌詞の変更には対応していません。',
    '심볼릭 링크나 디렉터리 연결을 통한 별도 가사 편집은 지원하지 않습니다.'
  ],
  '独立歌词被占用或无法读取，请稍后重试。': [
    'The separate lyrics file is in use or unreadable. Try again shortly.',
    '外部歌詞ファイルが使用中か、読み取れません。しばらくしてから再試行してください。',
    '별도 가사 파일이 사용 중이거나 읽을 수 없습니다. 잠시 후 다시 시도하세요.'
  ],
  '无法安全保存独立歌词，请检查目标是否已存在或被占用。': [
    'Cannot save the separate lyrics safely. Check whether the destination exists or is in use.',
    '外部歌詞を安全に保存できません。保存先が既に存在するか、使用中でないか確認してください。',
    '별도 가사를 안전하게 저장할 수 없습니다. 대상이 이미 존재하거나 사용 중인지 확인하세요.'
  ],
  '歌曲已保存，但独立歌词文件未能复制；已有歌词文件未被覆盖': [
    'The song was saved, but its separate lyrics file could not be copied. Existing lyrics were not overwritten.',
    '曲は保存されましたが、外部歌詞ファイルをコピーできませんでした。既存の歌詞は上書きしていません。',
    '곡은 저장했지만 별도 가사 파일을 복사하지 못했습니다. 기존 가사는 덮어쓰지 않았습니다.',
  ],
  '正在保存…': ['Saving…', '保存中…', '저장 중…'],
  '无法完整保留原标签或封面。可关闭继承原歌曲信息，并另存副本。': [
    'Some original tags or artwork cannot be preserved. Turn off original information and save a copy.',
    '元のタグやカバーを完全には保持できません。曲情報の引き継ぎをオフにしてコピーを保存できます。',
    '원본 태그나 커버를 완전히 유지할 수 없습니다. 원본 정보 유지를 끄고 사본으로 저장하세요.',
  ],
  '原歌曲在裁剪期间发生变化，请关闭窗口后重新打开。': [
    'The original song changed during trimming. Close and reopen this dialog.',
    'トリミング中に元の曲が変更されました。この画面を閉じて開き直してください。',
    '자르는 동안 원본 곡이 변경되었습니다. 이 창을 닫고 다시 여세요.',
  ],
  '无法保存，请检查文件是否被占用以及文件夹写入权限。': [
    'Cannot save. Check whether the file is in use and whether the folder is writable.',
    '保存できません。ファイルが使用中でないか、フォルダーに書き込み権限があるか確認してください。',
    '저장할 수 없습니다. 파일이 사용 중인지, 폴더에 쓰기 권한이 있는지 확인하세요.',
  ],
  '片段已保存': ['Segment saved', '区間を保存しました', '구간을 저장했습니다'],
  '文件已保存，但曲库暂未更新，请重新扫描文件夹。': [
    'File saved, but the library has not updated. Scan the folder again.',
    'ファイルを保存しましたが、ライブラリは未更新です。フォルダーを再スキャンしてください。',
    '파일은 저장했지만 라이브러리는 갱신되지 않았습니다. 폴더를 다시 스캔하세요.'
  ],
  '已取消裁剪': ['Trimming cancelled', 'トリミングを中止しました', '자르기를 취소했습니다'],
  '裁剪组件不完整，请使用完整的便携包': [
    'Trimming tools are missing. Use the complete portable package.',
    'トリミング用ツールが不足しています。完全なポータブル版を使用してください。',
    '자르기 도구가 없습니다. 완전한 포터블 패키지를 사용하세요.'
  ],
  '音频处理超时，原文件未被修改': [
    'Audio processing timed out. The original file was not changed.',
    '音声処理がタイムアウトしました。元のファイルは変更されていません。',
    '오디오 처리 시간이 초과되었습니다. 원본 파일은 변경되지 않았습니다.'
  ],
  '文件被占用或没有写入权限，原文件未被修改': [
    'The file is in use or cannot be written. The original was not changed.',
    'ファイルが使用中か、書き込み権限がありません。元のファイルは変更されていません。',
    '파일이 사용 중이거나 쓰기 권한이 없습니다. 원본은 변경되지 않았습니다.'
  ],
  '无法处理此音频文件，请检查文件是否完整': [
    'Cannot process this audio. Check that the file is complete.',
    '音声を処理できません。ファイルが破損していないか確認してください。',
    '오디오를 처리할 수 없습니다. 파일이 완전한지 확인하세요.'
  ],
  '暂不支持裁剪包含多个音轨的文件': [
    'Trimming files with multiple audio tracks is not supported yet.',
    '複数の音声トラックを含むファイルにはまだ対応していません。',
    '여러 오디오 트랙이 포함된 파일 자르기는 아직 지원하지 않습니다.'
  ],
  '无法读取有效的歌曲时长': [
    'Cannot read a valid song duration.',
    '有効な曲の長さを読み取れません。',
    '올바른 곡 길이를 읽을 수 없습니다.'
  ],
  '此音频格式暂不支持安全裁剪': [
    'Safe trimming is not supported for this audio format yet.',
    'この音声形式の安全なトリミングにはまだ対応していません。',
    '이 오디오 형식의 안전한 자르기는 아직 지원하지 않습니다.'
  ],
  '暂不支持裁剪包含视频或额外数据流的文件': [
    'Trimming files with video or additional data streams is not supported yet.',
    '映像や追加データストリームを含むファイルにはまだ対応していません。',
    '동영상이나 추가 데이터 스트림이 있는 파일 자르기는 아직 지원하지 않습니다.'
  ],
  '精确裁剪会重新编码音频；原有的有损格式可能发生细微音质变化': [
    'Precise trimming re-encodes audio. Lossy formats may have slight quality changes.',
    '正確なトリミングでは再エンコードします。非可逆形式では音質がわずかに変わる場合があります。',
    '정확히 자르기 위해 오디오를 다시 인코딩합니다. 손실 형식은 음질이 조금 달라질 수 있습니다.'
  ],
  '仅支持裁剪独立的本地歌曲文件': [
    'Only individual local song files can be trimmed.',
    '独立したローカルの曲ファイルのみトリミングできます。',
    '독립된 로컬 곡 파일만 자를 수 있습니다.'
  ],
  '请选择有效的裁剪范围，至少保留 0.05 秒': [
    'Choose a valid range of at least 0.05 seconds.',
    '0.05秒以上の有効な区間を選択してください。',
    '0.05초 이상의 올바른 구간을 선택하세요.'
  ],
  '请选择有效的保存位置和文件名': [
    'Choose a valid destination and file name.',
    '有効な保存先とファイル名を指定してください。',
    '올바른 저장 위치와 파일 이름을 선택하세요.'
  ],
  '此文件只能另存副本': [
    'This file can only be saved as a copy.',
    'このファイルはコピーとしてのみ保存できます。',
    '이 파일은 사본으로만 저장할 수 있습니다.'
  ],
  '曲库操作正在进行，请稍后再裁剪': [
    'A library operation is in progress. Try trimming again shortly.',
    'ライブラリの処理中です。しばらくしてからトリミングしてください。',
    '라이브러리 작업이 진행 중입니다. 잠시 후 다시 자르세요.'
  ],
  '覆盖只能保存到原文件，副本必须使用其他文件名': [
    'Replacement must use the original path; copies need a different file name.',
    '上書きは元のファイルにのみ行えます。コピーには別のファイル名を使用してください。',
    '덮어쓰기는 원본 경로에만 가능합니다. 사본은 다른 파일 이름을 사용하세요.'
  ],
  '此文件名已存在，请换一个名称保存副本': [
    'This file name already exists. Choose another name for the copy.',
    '同名のファイルが存在します。コピーには別の名前を指定してください。',
    '같은 파일 이름이 이미 있습니다. 사본에 다른 이름을 지정하세요.'
  ],
  '保存文件夹不存在，请重新选择': [
    'The destination folder does not exist. Choose it again.',
    '保存先フォルダーが存在しません。再選択してください。',
    '저장 폴더가 없습니다. 다시 선택하세요.'
  ],
  '裁剪结果校验失败，原文件未被修改': [
    'Trimmed audio did not pass verification. The original file was not changed.',
    'トリミング結果の検証に失敗しました。元のファイルは変更されていません。',
    '잘라낸 오디오 검증에 실패했습니다. 원본 파일은 변경되지 않았습니다.'
  ],
  '歌曲已保存，但曲库刷新未完成，请刷新曲库；不要重复覆盖': [
    'The song was saved, but the library did not finish updating. Refresh the library; do not replace the file again.',
    '曲は保存されましたが、ライブラリの更新が未完了です。再度上書きせず、ライブラリを更新してください。',
    '곡은 저장했지만 라이브러리 갱신이 완료되지 않았습니다. 다시 덮어쓰지 말고 라이브러리를 새로 고치세요.'
  ],
  '歌曲已保存，原文件的恢复副本仍保留在原文件夹': [
    'The song was saved. A recovery copy of the original remains in its folder.',
    '曲を保存しました。元のファイルの復元用コピーは元のフォルダーに残っています。',
    '곡을 저장했습니다. 원본 복원용 사본은 원래 폴더에 남아 있습니다.'
  ],
  '歌曲裁剪': ['Trim song', '曲のトリミング', '곡 자르기'],
  ' - 裁剪': [' - Trimmed', ' - トリミング', ' - 편집본'],
  '选择片段': ['Choose a segment', '区間を選択', '구간 선택'],
  '原始时长': ['Original duration', '元の長さ', '원본 길이'],
  '开始时间': ['Start time', '開始時間', '시작 시간'],
  '结束时间': ['End time', '終了時間', '종료 시간'],
  '选区时长': ['Selection duration', '選択区間の長さ', '선택 구간 길이'],
  '可输入秒数或 分:秒，最多保留三位小数。': [
    'Enter seconds or minutes:seconds, with up to three decimal places.',
    '秒数または 分:秒 で入力します。小数点以下は3桁まで指定できます。',
    '초 또는 분:초 형식으로 입력하세요. 소수점 이하 세 자리까지 가능합니다.',
  ],
  '请输入有效的起止时间：开始早于结束，且不超过歌曲时长。': [
    'The start must be before the end, within the song duration.',
    '開始は終了より前にし、曲の長さを超えないようにしてください。',
    '시작은 종료보다 빨라야 하며 곡 길이를 초과할 수 없습니다.',
  ],
  '试听选区': ['Preview selection', '選択区間を試聴', '미리 듣기'],
  '停止试听': ['Stop preview', '試聴を停止', '미리 듣기 중지'],
  '试听会暂时暂停主播放；结束后恢复，若已自行操作主播放则不再恢复。': [
    'Preview pauses main playback and resumes it afterward, unless you change playback yourself.',
    '試聴中は通常の再生を一時停止し、終了後に再開します。再生を手動で操作した場合は再開しません。',
    '미리 듣는 동안 주 재생을 일시 정지하고 종료 후 재개합니다. 직접 재생을 조작했다면 재개하지 않습니다.',
  ],
  '试听失败，请检查音频输出设备是否被独占，或稍后重试。': [
    'Preview failed. Check whether another player has exclusive access to the audio device, or try again.',
    '試聴できませんでした。音声出力デバイスが排他使用されていないか確認するか、再試行してください。',
    '미리 듣기에 실패했습니다. 오디오 장치가 독점 사용 중인지 확인하거나 다시 시도하세요.',
  ],
  '保存方式': ['Save options', '保存方法', '저장 방식'],
  '覆盖原文件': ['Replace original file', '元のファイルを上書き', '원본 파일 덮어쓰기'],
  '默认创建副本，原歌曲保持不变。': [
    'A new copy is saved by default. The original song stays unchanged.',
    '通常はコピーを保存し、元の曲は変更しません。',
    '기본적으로 사본을 저장하며 원본 곡은 변경되지 않습니다.',
  ],
  '我确认覆盖原文件。被裁掉的内容无法撤销恢复。': [
    'I confirm replacement. Removed audio cannot be restored by Undo.',
    '元のファイルを上書きします。削除された音声は元に戻せません。',
    '원본 덮어쓰기를 확인합니다. 잘라낸 부분은 실행 취소로 복원할 수 없습니다.',
  ],
  '保存文件夹': ['Destination folder', '保存先フォルダー', '저장 폴더'],
  '选择保存文件夹': ['Choose destination folder', '保存先フォルダーを選択', '저장 폴더 선택'],
  '原文件夹': ['Original folder', '元のフォルダー', '원래 폴더'],
  '其他位置': ['Other location', '別の場所', '다른 위치'],
  '请输入有效的文件名，不要包含路径或特殊保留字符。': [
    'Enter a valid file name without paths or reserved characters.',
    'パスや使用できない文字を含まない有効なファイル名を入力してください。',
    '경로나 예약 문자를 포함하지 않은 올바른 파일 이름을 입력하세요.',
  ],
  '请保留文件名末尾的音频扩展名。': [
    'Keep the audio extension at the end of the file name.',
    'ファイル名の末尾に音声ファイルの拡張子を残してください。',
    '파일 이름 끝의 오디오 확장자를 유지하세요.',
  ],
  '按原始格式精确裁剪。有损音频会重新编码，无损音频保持无损。': [
    'Trim precisely in the original format. Lossy audio is re-encoded; lossless audio stays lossless.',
    '元の形式で正確にトリミングします。非可逆音声は再エンコードされ、可逆音声は可逆形式を保ちます。',
    '원본 형식으로 정확히 자릅니다. 손실 음원은 다시 인코딩하며 무손실 음원은 무손실로 유지합니다.',
  ],
  '继承原歌曲信息': ['Keep original song information', '元の曲情報を引き継ぐ', '원본 곡 정보 유지'],
  '保留封面等附加信息，并自动对齐歌词时间；纯文本歌词原样保留。': [
    'Keep artwork and additional tags, and align timed lyrics to the segment. Plain lyrics stay unchanged.',
    'カバーなどの追加情報を保持し、歌詞の時刻を区間に合わせます。時刻のない歌詞はそのまま保持します。',
    '커버와 추가 태그를 유지하며 가사 시간을 구간에 맞춥니다. 일반 텍스트 가사는 그대로 유지합니다.',
  ],
  '仅写入下方标题、艺术家和专辑；覆盖原文件时仍会对齐独立歌词时间。': [
    'Write only the title, artist and album below. Replacing the original still aligns its separate lyrics file.',
    '下のタイトル・アーティスト・アルバムのみ書き込みます。元の曲を上書きする場合、外部歌詞の時刻は調整します。',
    '아래 제목, 아티스트, 앨범만 기록합니다. 원본을 덮어쓸 때는 별도 가사 파일의 시간을 조정합니다.',
  ],
  '时长根据裁剪结果自动更新。': [
    'Duration is updated automatically from the trimmed audio.',
    '長さはトリミング結果に合わせて自動更新されます。',
    '길이는 잘라낸 오디오를 기준으로 자동 갱신됩니다.',
  ],
  '保存片段': ['Save segment', '区間を保存', '구간 저장'],
  '取消裁剪': ['Cancel trimming', 'トリミングを中止', '자르기 취소'],
  '正在裁剪并检查音频…': [
    'Trimming and verifying audio…',
    'トリミングして音声を確認中…',
    '오디오를 자르고 확인하는 중…'
  ],
  '未完成裁剪。': [
    'Trimming did not complete.',
    'トリミングが完了しませんでした。',
    '자르기가 완료되지 않았습니다.'
  ],
  '无法读取音频，请确认本地文件可用。': [
    'Cannot read the audio. Check that the local file is available.',
    '音声を読み取れません。ローカルファイルが利用可能か確認してください。',
    '오디오를 읽을 수 없습니다. 로컬 파일을 사용할 수 있는지 확인하세요.',
  ],
};
