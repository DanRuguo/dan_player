const Map<String, List<String>> catalogCueRelease = {
  '导入 CUE 分轨': ['Import CUE tracks', 'CUE 分割トラックを読み込む', 'CUE 분할 트랙 가져오기'],
  '将导入 {0} 首 CUE 分轨，每首有独立的播放进度。': [
    'Import {0} CUE tracks, each with its own playback progress.',
    '{0} 曲の CUE トラックを読み込みます。各曲に独立した再生位置があります。',
    '각각 독립된 재생 위치를 가진 CUE 트랙 {0}개를 가져옵니다.'
  ],
  '只保存分轨引用，不拆分或修改音频文件；保留 CUE 和源文件以便重新导入。': [
    'Save track references without splitting or changing audio files. Keep the CUE and source files to import again.',
    '音声ファイルは分割・変更せず、トラック参照を保存します。再読み込み用に CUE と音声を保管してください。',
    '오디오 파일을 분할하거나 수정하지 않고 트랙 참조만 저장합니다. 다시 가져오려면 CUE와 원본 파일을 보관하세요.'
  ],
  '第 {0} 轨 · {1}': ['Track {0} · {1}', 'トラック {0} · {1}', '트랙 {0} · {1}'],
  'CUE 分轨 · 第 {0} 轨 · 起点 {1} 秒': [
    'CUE · Track {0} · Starts at {1} s',
    'CUE · トラック {0} · 開始 {1} 秒',
    'CUE · 트랙 {0} · 시작 {1}초'
  ],
  '无法读取 CUE 或其音频文件，请检查位置与访问权限。': [
    'Cannot read the CUE or its audio files. Check their locations and access permissions.',
    'CUE または音声を読めません。場所とアクセス権を確認してください。',
    'CUE 또는 오디오 파일을 읽을 수 없습니다. 위치와 접근 권한을 확인하세요.'
  ],
  'CUE 文件超过 1 MiB，无法导入。': [
    'The CUE exceeds 1 MiB and cannot be imported.',
    'CUE が 1 MiB を超えているため読み込めません。',
    'CUE가 1 MiB를 초과하여 가져올 수 없습니다.'
  ],
  'CUE 文件位置必须为绝对路径。': [
    'The CUE location must be an absolute path.',
    'CUE の場所には絶対パスが必要です。',
    'CUE 위치는 절대 경로여야 합니다.'
  ],
  'CUE 只支持本地音频文件，不支持数据光盘映像。': [
    'CUE supports local audio files; data disc images are unsupported.',
    'CUE はローカル音声に対応し、データディスクイメージには対応しません。',
    'CUE는 로컬 오디오를 지원하며 데이터 디스크 이미지는 지원하지 않습니다.'
  ],
  'CUE 音频文件路径无效。': [
    'Invalid CUE audio file path.',
    'CUE 音声パスが無効です。',
    'CUE 오디오 경로가 잘못되었습니다.'
  ],
  'CUE 音频格式或重复 FILE 段不受支持。': [
    'Unsupported CUE audio format or repeated FILE section.',
    'CUE の音声形式または重複 FILE セクションに対応していません。',
    'CUE 오디오 형식 또는 반복된 FILE 구간을 지원하지 않습니다.'
  ],
  'CUE 曲目编号无效、重复或包含非音频曲目。': [
    'Invalid or duplicate CUE track number, or a non-audio track.',
    'CUE の番号が無効・重複しているか、音声以外のトラックがあります。',
    'CUE 번호가 잘못되거나 중복되었거나 오디오가 아닌 트랙이 있습니다.'
  ],
  'CUE INDEX 时间格式无效。': [
    'Invalid CUE INDEX time.',
    'CUE INDEX 時刻が無効です。',
    'CUE INDEX 시간이 잘못되었습니다.'
  ],
  'CUE 曲目包含重复 INDEX 01。': [
    'The CUE track has duplicate INDEX 01 entries.',
    'CUE トラックに INDEX 01 が重複しています。',
    'CUE 트랙에 INDEX 01이 중복되었습니다.'
  ],
  'CUE 中没有音频分轨。': [
    'The CUE contains no audio tracks.',
    'CUE に音声トラックがありません。',
    'CUE에 오디오 트랙이 없습니다.'
  ],
  'CUE 缺少 INDEX 01，或同文件分轨时间未递增。': [
    'Missing INDEX 01 or non-increasing track positions in one file.',
    'INDEX 01 がないか、同じファイルのトラック時刻が昇順ではありません。',
    'INDEX 01이 없거나 같은 파일의 트랙 시간이 증가하지 않습니다.'
  ],
  'CUE 文本编码无效，请转换为 UTF-8。': [
    'Invalid CUE text encoding. Convert it to UTF-8.',
    'CUE の文字コードが無効です。UTF-8 に変換してください。',
    'CUE 문자 인코딩이 잘못되었습니다. UTF-8로 변환하세요.'
  ],
  'CUE 引用的音频文件不存在或无法读取。': [
    'A CUE audio file is missing or unreadable.',
    'CUE の参照する音声が見つからないか、読めません。',
    'CUE가 참조하는 오디오 파일이 없거나 읽을 수 없습니다.'
  ],
  'CUE 分轨引用无效。': [
    'Invalid CUE track reference.',
    'CUE トラック参照が無効です。',
    'CUE 트랙 참조가 잘못되었습니다.'
  ],
  'CUE 分轨时间超出音频文件范围，请检查 CUE 与音频是否匹配。': [
    'CUE positions exceed the audio length. Check that the files match.',
    'CUE 時刻が音声の長さを超えています。ファイルの組み合わせを確認してください。',
    'CUE 시간이 오디오 길이를 초과합니다. 파일이 일치하는지 확인하세요.'
  ],
  'CUE 分轨仅支持本地音频文件。': [
    'CUE tracks require local audio files.',
    'CUE トラックにはローカル音声が必要です。',
    'CUE 트랙에는 로컬 오디오 파일이 필요합니다.'
  ],
  'CUE 分轨仅引用整轨音频，请使用歌单中的移除功能。': [
    'CUE tracks reference a whole audio file. Remove the track from its playlist.',
    'CUE は音声全体を参照します。歌単のトラック削除を使用してください。',
    'CUE 트랙은 전체 오디오를 참조합니다. 재생목록에서 트랙을 제거하세요.'
  ],
  'CUE 分轨信息由 CUE 文件提供，不能修改整轨音频。': [
    'CUE track details come from the CUE file. The whole audio file cannot be edited here.',
    'CUE トラック情報は CUE ファイルが提供します。音声全体はここでは編集できません。',
    'CUE 트랙 정보는 CUE 파일에서 제공됩니다. 여기서 전체 오디오를 수정할 수 없습니다.'
  ],
  'CUE 分轨不能写入整轨歌词，可在歌词来源中关联歌曲。': [
    'CUE tracks cannot overwrite whole-file lyrics. Link a track in lyric sources.',
    'CUE は音声全体の歌詞を上書きできません。歌詞ソースで曲を関連付けてください。',
    'CUE 트랙은 전체 파일의 가사를 덮어쓸 수 없습니다. 가사 소스에서 곡을 연결하세요.'
  ],
  '整轨音频正在作为 CUE 分轨使用，请先切换歌曲后再删除。': [
    'This file is in use by a CUE track. Switch tracks before deleting it.',
    'この音声は CUE トラックで使用中です。曲を切り替えてから削除してください。',
    '이 파일은 CUE 트랙에서 사용 중입니다. 곡을 바꾼 후 삭제하세요.'
  ],
};
