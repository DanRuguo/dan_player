const Map<String, List<String>> catalogPlaylistExchange = {
  '此文件是 HLS 流媒体清单，不能作为本地歌单导入。': [
    'This file is an HLS stream manifest and cannot be imported as a local playlist.',
    'このファイルは HLS ストリーム一覧のため、ローカルプレイリストとして読み込めません。',
    '이 파일은 HLS 스트림 목록이므로 로컬 재생목록으로 가져올 수 없습니다.'
  ],
  '歌单包含无法导出的本地文件引用，请移除不支持的项目后重试。': [
    'The playlist contains invalid local file references. Remove unsupported items and try again.',
    '書き出せないローカルファイル参照があります。未対応の項目を削除して再試行してください。',
    '내보낼 수 없는 로컬 파일 참조가 있습니다. 지원되지 않는 항목을 제거한 후 다시 시도해 주세요.'
  ],
  '无法打开文件选择器，请稍后重试。': [
    'Cannot open the file picker. Try again later.',
    'ファイル選択を開けません。後でもう一度お試しください。',
    '파일 선택기를 열 수 없습니다. 나중에 다시 시도해 주세요.'
  ],
  '导出文件名请使用 .m3u8 后缀。': [
    'Use the .m3u8 extension for the exported playlist.',
    '書き出すファイル名には .m3u8 拡張子を使用してください。',
    '내보낼 파일 이름에 .m3u8 확장자를 사용해 주세요.'
  ],
  '跳过 {0} 项联网歌曲或不支持的文件引用。': [
    'Skip {0} online tracks or unsupported file references.',
    'オンライン曲または未対応のファイル参照 {0} 件をスキップします。',
    '온라인 곡 또는 지원되지 않는 파일 참조 {0}개를 건너뜁니다.'
  ],
  '导入 M3U8 歌单': ['Import M3U8 playlist', 'M3U8 プレイリストを読み込む', 'M3U8 재생목록 가져오기'],
  '导出 M3U8 歌单': ['Export M3U8 playlist', 'M3U8 プレイリストを書き出す', 'M3U8 재생목록 내보내기'],
  '歌单文件超过 2 MiB，无法导入。': [
    'Playlist exceeds the 2 MiB limit.',
    'プレイリストが 2 MiB の上限を超えています。',
    '재생목록이 2 MiB 제한을 초과합니다.'
  ],
  '歌单超过 20000 条，请拆分后导入。': [
    'Split playlists containing more than 20,000 entries.',
    '20,000 件を超えるプレイリストは分割してください。',
    '20,000개 항목을 초과하는 재생목록은 나누어 주세요.'
  ],
  '请将歌单另存为 UTF-8 编码的 M3U8 文件。': [
    'Save the playlist as a UTF-8 M3U8 file.',
    'UTF-8 の M3U8 ファイルとして保存してください。',
    '재생목록을 UTF-8 M3U8 파일로 저장해 주세요.'
  ],
  '无法读取歌单文件，请检查文件位置与访问权限。': [
    'Cannot read the playlist. Check its location and access permissions.',
    'プレイリストを読み込めません。場所とアクセス権限を確認してください。',
    '재생목록을 읽을 수 없습니다. 위치와 접근 권한을 확인해 주세요.'
  ],
  '将导入 {0} 个本地歌曲引用，保留顺序与重复项。': [
    'Import {0} local track references, preserving order and repeats.',
    '順序と重複を保って {0} 件のローカル曲を読み込みます。',
    '순서와 중복을 유지하여 로컬 곡 참조 {0}개를 가져옵니다.'
  ],
  '跳过 {0} 项网络地址或不支持的格式。': [
    'Skip {0} network addresses or unsupported formats.',
    '{0} 件のネットワークアドレスまたは未対応形式をスキップします。',
    '네트워크 주소 또는 지원되지 않는 형식 {0}개를 건너뜁니다.'
  ],
  '歌单只记录文件位置，不复制音乐；文件移动后需更新对应引用。': [
    'Playlists reference files without copying music. Update references after moving files.',
    '音楽をコピーせず、ファイルの場所を記録します。移動後は参照を更新してください。',
    '음악을 복사하지 않고 파일 위치를 기록합니다. 파일 이동 후 참조를 업데이트해 주세요.'
  ],
  '没有可导入的本地歌曲。': [
    'No local tracks to import.',
    '読み込み可能なローカル曲がありません。',
    '가져올 로컬 곡이 없습니다.'
  ],
  '所选歌曲中没有可导出的本地文件。': [
    'No local files in the selected tracks can be exported.',
    '選択した曲に書き出し可能なローカルファイルがありません。',
    '선택한 곡에 내보낼 로컬 파일이 없습니다.'
  ],
  'M3U8 歌单已导出（{0} 首）。': [
    'M3U8 playlist exported ({0} tracks).',
    'M3U8 プレイリストを書き出しました（{0} 曲）。',
    'M3U8 재생목록을 내보냈습니다({0}곡).'
  ],
  '导出失败，请检查目标目录与写入权限。': [
    'Export failed. Check the destination and write permissions.',
    '書き出しに失敗しました。保存先と書き込み権限を確認してください。',
    '내보내기에 실패했습니다. 대상 폴더와 쓰기 권한을 확인해 주세요.'
  ],
  '导出 {0} 个本地歌曲引用，保留顺序与重复项。': [
    'Export {0} local track references, preserving order and repeats.',
    '順序と重複を保って {0} 件のローカル曲を書き出します。',
    '순서와 중복을 유지하여 로컬 곡 참조 {0}개를 내보냅니다.'
  ],
  '跳过 {0} 首联网歌曲，其播放地址不适合保存到本地歌单。': [
    'Skip {0} online tracks whose playback addresses are unsuitable for local playlists.',
    'ローカルプレイリストに保存できないオンライン曲 {0} 件をスキップします。',
    '재생 주소를 로컬 재생목록에 저장하기에 적합하지 않은 온라인 곡 {0}개를 건너뜁니다.'
  ],
  '使用相对路径': ['Use relative paths', '相対パスを使用', '상대 경로 사용'],
  '与音乐文件一起移动文件夹时，更容易保持歌单可用。': [
    'Keep playlists usable when moving the folder together with its music.',
    '音楽と一緒にフォルダーを移動しても参照を維持しやすくなります。',
    '음악과 폴더를 함께 옮길 때 재생목록을 계속 사용할 수 있습니다.'
  ],
  '选择保存位置': ['Choose save location', '保存先を選択', '저장 위치 선택'],
};
