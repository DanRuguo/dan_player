const Map<String, List<String>> catalogPlaylistFolder = {
  '输出格式': ['Output format', '出力形式', '출력 형식'],
  '原样复制': ['Copy originals', '元の形式でコピー', '원본 복사'],
  '转换质量': ['Conversion quality', '変換品質', '변환 품질'],
  '体积优先 · {0} kbps': [
    'Smaller files · {0} kbps',
    'サイズ優先 · {0} kbps',
    '작은 파일 · {0} kbps'
  ],
  '均衡 · {0} kbps': ['Balanced · {0} kbps', 'バランス · {0} kbps', '균형 · {0} kbps'],
  '高音质 · {0} kbps': [
    'High quality · {0} kbps',
    '高音質 · {0} kbps',
    '높은 음질 · {0} kbps'
  ],
  '将 {0} 首歌曲转换为 {1} 个 {2} 文件，其中 {3} 首为 CUE 分轨。': [
    'Convert {0} tracks into {1} {2} files, including {3} CUE tracks.',
    '{0} 曲を {1} 個の {2} ファイルに変換します。そのうち {3} 曲は CUE 分割曲です。',
    '{0}곡을 {2} 파일 {1}개로 변환합니다. 이 중 {3}곡은 CUE 분할 곡입니다.'
  ],
  '已选择 {0} 首 CUE 分轨；选择转换格式可导出为独立音频文件。': [
    '{0} CUE tracks selected. Choose a conversion format to export them as separate audio files.',
    'CUE 分割曲が {0} 曲選択されています。変換形式を選ぶと個別の音声ファイルに書き出せます。',
    'CUE 분할 곡 {0}개가 선택되었습니다. 변환 형식을 선택하면 개별 오디오 파일로 내보낼 수 있습니다.'
  ],
  '跳过 {0} 项联网歌曲或不支持的文件。': [
    'Skip {0} online tracks or unsupported files.',
    'オンライン曲または未対応ファイル {0} 件をスキップします。',
    '온라인 곡 또는 지원되지 않는 파일 {0}개를 건너뜁니다.'
  ],
  '保留标题、艺术家、专辑等基本文字标签；不保留内嵌歌词、封面或侧车文件。': [
    'Keeps basic text tags such as title, artist and album. Embedded lyrics, artwork and separate companion files are not kept.',
    'タイトル、アーティスト、アルバムなどの基本テキストタグを保持します。埋め込み歌詞・カバー画像や別ファイルは保持しません。',
    '제목, 아티스트, 앨범 등 기본 텍스트 태그를 유지합니다. 내장 가사, 표지 및 별도 부가 파일은 유지하지 않습니다.'
  ],
  '原样复制完整音频文件，不改变编码和嵌入标签；不复制单独的歌词或封面文件。': [
    'Copies complete audio files with their encoding and embedded tags unchanged. Separate lyric and cover files are not copied.',
    '音声ファイル全体をコピーし、エンコードと埋め込みタグを保持します。別ファイルの歌詞やカバー画像はコピーしません。',
    '인코딩과 내장 태그를 유지하여 오디오 파일 전체를 복사합니다. 별도의 가사 및 표지 파일은 복사하지 않습니다.'
  ],
  'MP3 输出为 44.1 kHz，单声道保留，其余转为双声道，便于车载和便携设备播放。': [
    'MP3 uses 44.1 kHz, keeping mono or converting other channel layouts to stereo for car and portable players.',
    'MP3 は 44.1 kHz で出力します。モノラルを保持し、それ以外はステレオに変換するため、車載・携帯プレイヤーで再生しやすくなります。',
    'MP3는 44.1 kHz로 출력하며 모노는 유지하고 나머지는 스테레오로 변환하여 차량 및 휴대용 기기에서 재생하기 좋습니다.'
  ],
  'Opus 输出为 48 kHz，单声道保留，其余转为双声道。请确认目标设备支持 Opus。': [
    'Opus uses 48 kHz, keeping mono or converting other channel layouts to stereo. Check that the target device supports Opus.',
    'Opus は 48 kHz で出力し、モノラルを保持、それ以外はステレオに変換します。再生先の機器が Opus に対応していることをご確認ください。',
    'Opus는 48 kHz로 출력하며 모노는 유지하고 나머지는 스테레오로 변환합니다. 대상 기기가 Opus를 지원하는지 확인하세요.'
  ],
  'FLAC 保留采样率和声道，不会提升有损音源的音质。': [
    'FLAC keeps the sample rate and channels. It does not improve the quality of lossy sources.',
    'FLAC はサンプルレートとチャンネル数を保持します。非可逆圧縮音源の音質が向上するわけではありません。',
    'FLAC는 샘플레이트와 채널을 유지합니다. 손실 압축 음원의 음질을 높이지는 않습니다.'
  ],
  '正在检查转换组件…': ['Checking conversion tools…', '変換ツールを確認中…', '변환 도구 확인 중…'],
  '安装音频转换组件': [
    'Install audio conversion tools',
    '音声変換ツールをインストール',
    '오디오 변환 도구 설치'
  ],
  '转换复用 FFmpeg 组件。可以手动安装，或从 GitHub 下载约 70 MB 的组件；原样复制无需安装。': [
    'Conversion uses the existing FFmpeg tools. Install them manually or download about 70 MB from GitHub. Copying originals needs no installation.',
    '変換には共通の FFmpeg ツールを使用します。手動でインストールするか、GitHub から約 70 MB をダウンロードできます。元の形式でのコピーには不要です。',
    '변환에는 공용 FFmpeg 도구를 사용합니다. 직접 설치하거나 GitHub에서 약 70 MB를 다운로드할 수 있습니다. 원본 복사에는 설치가 필요하지 않습니다.'
  ],
  '已转换 {0}/{1} 个文件': [
    'Converted {0}/{1} files',
    '{0}/{1} 個のファイルを変換済み',
    '파일 {0}/{1}개 변환됨'
  ],
  '音频转换需要 FFmpeg 组件，请先安装或修复。': [
    'Audio conversion requires the FFmpeg tools. Install or repair them first.',
    '音声変換には FFmpeg ツールが必要です。先にインストールまたは修復してください。',
    '오디오 변환에는 FFmpeg 도구가 필요합니다. 먼저 설치하거나 복구해 주세요.'
  ],
  '音频转换失败，请检查源文件是否完整或选择其他格式。': [
    'Audio conversion failed. Check the source file or choose another format.',
    '音声の変換に失敗しました。元のファイルを確認するか、別の形式を選んでください。',
    '오디오 변환에 실패했습니다. 원본 파일을 확인하거나 다른 형식을 선택해 주세요.'
  ],
  '导出音频校验失败，未生成目标文件夹。': [
    'Exported audio could not be verified. No destination folder was created.',
    '書き出した音声を検証できませんでした。出力先フォルダーは作成されていません。',
    '내보낸 오디오를 검증하지 못했습니다. 대상 폴더를 생성하지 않았습니다.'
  ],
  '音频转换超时，未生成目标文件夹。': [
    'Audio conversion timed out. No destination folder was created.',
    '音声変換がタイムアウトしました。出力先フォルダーは作成されていません。',
    '오디오 변환 시간이 초과되었습니다. 대상 폴더를 생성하지 않았습니다.'
  ],
  '音频转换仅支持单音轨文件，不支持视频或额外数据流。': [
    'Conversion supports one audio stream only, without video or extra data streams.',
    '変換できるのは単一の音声ストリームのみです。動画や追加のデータストリームには対応していません。',
    '변환은 오디오 스트림 하나만 지원하며 동영상이나 추가 데이터 스트림은 지원하지 않습니다.'
  ],
  '无法读取有效的歌曲时长或音频参数。': [
    'Could not read a valid duration or audio parameters.',
    '有効な再生時間または音声パラメーターを読み取れません。',
    '유효한 재생 시간 또는 오디오 정보를 읽을 수 없습니다.'
  ],
  'CUE 分轨范围无效或超出源音频时长。': [
    'The CUE track range is invalid or exceeds the source duration.',
    'CUE 分割曲の範囲が無効か、元の音声の長さを超えています。',
    'CUE 분할 구간이 잘못되었거나 원본 오디오 길이를 초과합니다.'
  ],
  '导出音乐文件夹': ['Export music folder', '音楽フォルダーを書き出す', '음악 폴더 내보내기'],
  '导出队列音乐文件夹': [
    'Export queue as music folder',
    'キューを音楽フォルダーに書き出す',
    '대기열을 음악 폴더로 내보내기'
  ],
  '导出搜索结果音乐文件夹': [
    'Export search results as music folder',
    '検索結果を音楽フォルダーに書き出す',
    '검색 결과를 음악 폴더로 내보내기'
  ],
  '将 {0} 首歌曲导出到新文件夹，复制 {1} 个音频文件。': [
    'Export {0} tracks into a new folder, copying {1} audio files.',
    '新しいフォルダーに {0} 曲を書き出し、{1} 個の音声ファイルをコピーします。',
    '새 폴더에 {0}곡을 내보내고 오디오 파일 {1}개를 복사합니다.'
  ],
  '保留歌曲顺序和重复项，生成相对路径 M3U8；原文件不变。': [
    'Keep track order and repeats, with a relative-path M3U8 playlist. Original files stay unchanged.',
    '曲順と重複を保った相対パスの M3U8 を作成します。元のファイルは変更しません。',
    '곡 순서와 중복을 유지한 상대 경로 M3U8을 생성합니다. 원본 파일은 변경되지 않습니다.'
  ],
  '跳过 {0} 项联网歌曲、CUE 分轨或不支持的文件。': [
    'Skip {0} online tracks, CUE tracks or unsupported files.',
    'オンライン曲、CUE 分割曲、未対応ファイル {0} 件をスキップします。',
    '온라인 곡, CUE 분할 곡 또는 지원되지 않는 파일 {0}개를 건너뜁니다.'
  ],
  '不转换音频，也不复制歌词或封面侧车文件。': [
    'Audio is not converted. Separate lyric and cover files are not copied.',
    '音声の変換や、別ファイルの歌詞・カバー画像のコピーは行いません。',
    '오디오를 변환하거나 별도의 가사 및 표지 파일을 복사하지 않습니다.'
  ],
  '正在导出音乐文件夹': ['Exporting music folder', '音楽フォルダーを書き出し中', '음악 폴더 내보내는 중'],
  '正在准备音频文件…': ['Preparing audio files…', '音声ファイルを準備中…', '오디오 파일 준비 중…'],
  '已复制 {0}/{1} 个文件': [
    'Copied {0}/{1} files',
    '{0}/{1} 個のファイルをコピー済み',
    '파일 {0}/{1}개 복사됨'
  ],
  '音乐文件夹已导出（{0} 首，{1} 个文件）。': [
    'Music folder exported ({0} tracks, {1} files).',
    '音楽フォルダーを書き出しました（{0} 曲、{1} ファイル）。',
    '음악 폴더를 내보냈습니다({0}곡, 파일 {1}개).'
  ],
  '导出文件夹超过 20000 项，请拆分后导出。': [
    'The export exceeds 20,000 entries. Split it into smaller exports.',
    '書き出す項目が 20,000 件を超えています。分割して書き出してください。',
    '내보낼 항목이 20,000개를 초과합니다. 나누어 내보내 주세요.'
  ],
  '复制期间源文件发生变化，请重新导出。': [
    'A source file changed during copying. Please export again.',
    'コピー中に元のファイルが変更されました。もう一度書き出してください。',
    '복사 중 원본 파일이 변경되었습니다. 다시 내보내 주세요.'
  ],
  '导出歌单超过 2 MiB，请减少歌曲或缩短名称后重试。': [
    'The exported playlist exceeds 2 MiB. Reduce the track count or shorten names and try again.',
    '書き出すプレイリストが 2 MiB を超えています。曲数を減らすか名前を短くして再試行してください。',
    '내보낼 재생목록이 2 MiB를 초과합니다. 곡 수를 줄이거나 이름을 짧게 한 후 다시 시도해 주세요.'
  ],
};
