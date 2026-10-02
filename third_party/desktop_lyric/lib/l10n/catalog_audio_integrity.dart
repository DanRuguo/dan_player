const catalogAudioIntegrity = <String, List<String>>{
  '音频文件校验': ['Audio file check', '音声ファイル検査', '오디오 파일 검사'],
  '字节': ['bytes', 'バイト', '바이트'],
  '源文件': ['Source file', '元ファイル', '원본 파일'],
  '已解码时长': ['Decoded duration', 'デコード時間', '디코딩된 길이'],
  '校验 CUE 对应的整份源文件': [
    'Check the whole source file behind this CUE track',
    'CUE 曲の元ファイル全体を検査',
    'CUE 곡의 전체 원본 파일 검사'
  ],
  '校验整份源文件的首个音轨': [
    'Check the first audio stream of the whole file',
    'ファイル全体の最初の音声トラックを検査',
    '전체 파일의 첫 오디오 트랙 검사'
  ],
  '按需读取文件并完整解码，检测可识别的编码错误；同时计算 SHA-256，不改写歌曲。': [
    'Read and fully decode the file on demand to detect recognised encoding errors, and calculate SHA-256 without changing the song.',
    '必要時にファイル全体を読み取り、デコードで検出可能なエラーと SHA-256 を調べます。曲は変更しません。',
    '필요할 때 파일을 끝까지 읽고 디코딩하여 인식 가능한 인코딩 오류와 SHA-256을 확인합니다. 곡 파일은 변경하지 않습니다.'
  ],
  '文件校验复用现有 FFmpeg 组件，可手动安装或按需下载。': [
    'File checks use the existing FFmpeg component. Install it manually or download it on demand.',
    '既存の FFmpeg を使います。手動インストールまたは必要時にダウンロードできます。',
    '기존 FFmpeg 구성 요소를 사용합니다. 직접 설치하거나 필요할 때 다운로드할 수 있습니다.'
  ],
  '正在计算文件校验值…': ['Calculating file checksum…', 'チェックサムを計算中…', '파일 체크섬 계산 중…'],
  '正在检查音频解码…': ['Checking audio decoding…', '音声デコードを検査中…', '오디오 디코딩 검사 중…'],
  '解码检查通过': ['Decoding check passed', 'デコード検査に合格', '디코딩 검사 통과'],
  '校验值用于核对文件副本；解码检查不代表已与原始文件比对。': [
    'Use the checksum to compare file copies. Passing the decoding check does not mean the file has been compared with an original.',
    'チェックサムはコピーの比較に使えます。デコード検査の合格は原本との照合を意味しません。',
    '체크섬으로 파일 복사본을 비교할 수 있습니다. 디코딩 검사 통과는 원본과 대조했다는 뜻이 아닙니다.'
  ],
  '文件校验结果已复制': ['File check results copied', '検査結果をコピーしました', '파일 검사 결과 복사 완료'],
  '无法复制校验结果，请重试': [
    'Could not copy the results. Please retry.',
    '検査結果をコピーできません。再試行してください。',
    '검사 결과를 복사하지 못했습니다. 다시 시도하세요.'
  ],
  '取消校验': ['Cancel check', '検査を中止', '검사 취소'],
  '开始校验': ['Start check', '検査を開始', '검사 시작'],
  '重新校验': ['Check again', '再検査', '다시 검사'],
  '文件校验超时，请重试': [
    'File check timed out. Please retry.',
    '検査がタイムアウトしました。再試行してください。',
    '파일 검사 시간이 초과되었습니다. 다시 시도하세요.'
  ],
  '文件校验仅支持本地音频': [
    'File checks support local audio only',
    'ローカル音声ファイルのみ検査できます',
    '로컬 오디오 파일만 검사할 수 있습니다'
  ],
  '已有文件校验正在进行，请稍后重试': [
    'A file check is already running. Please try again later.',
    '検査が実行中です。後で再試行してください。',
    '파일 검사가 진행 중입니다. 나중에 다시 시도하세요.'
  ],
  '未解码出有效音频，无法完成文件校验': [
    'No valid audio was decoded; the file check could not finish.',
    '有効な音声をデコードできず、検査を完了できません。',
    '유효한 오디오가 디코딩되지 않아 검사를 완료할 수 없습니다.'
  ],
  '校验期间源文件已改变，请重新校验': [
    'The source file changed during the check. Check it again.',
    '検査中に元ファイルが変更されました。再検査してください。',
    '검사 중 원본 파일이 변경되었습니다. 다시 검사하세요.'
  ],
  '已取消文件校验': ['File check cancelled', 'ファイル検査を中止しました', '파일 검사 취소됨'],
  '解码检查未通过，请检查文件或编码格式': [
    'Decoding check failed. Check the file or its encoding format.',
    'デコード検査に失敗しました。ファイルや形式を確認してください。',
    '디코딩 검사에 실패했습니다. 파일이나 인코딩 형식을 확인하세요.'
  ],
};
