const Map<String, List<String>> catalogLoudnessAnalysis = {
  '响度与峰值': ['Loudness and peaks', 'ラウドネスとピーク', '음량·피크'],
  '响度与峰值分析': ['Analyze loudness and peaks', 'ラウドネスとピークを解析', '음량 및 피크 분석'],
  '分析当前 CUE 分轨': ['Analyze this CUE track', '現在の CUE 分割曲を解析', '현재 CUE 분할 곡 분석'],
  '分析整首源文件': ['Analyze the full source track', '元ファイルの曲全体を解析', '원본 곡 전체 분석'],
  '测量原始音频，不含播放器音量、均衡器或变速处理。': [
    'Measures the source audio before player volume, equalization or playback speed changes.',
    '元の音声を測定します。プレイヤーの音量、イコライザー、再生速度の変更は含みません。',
    '원본 오디오를 측정합니다. 플레이어 음량, 이퀄라이저 또는 재생 속도 조절은 포함하지 않습니다.'
  ],
  '正在检查音频工具…': ['Checking audio tools…', '音声ツールを確認中…', '오디오 도구 확인 중…'],
  '安装音频工具': ['Install audio tools', '音声ツールをインストール', '오디오 도구 설치'],
  '响度分析复用 FFmpeg 组件，不改写歌曲。可手动安装，或按需下载现有组件。': [
    'Loudness analysis uses the existing FFmpeg tools without rewriting tracks. Install them manually or download them when needed.',
    '既存の FFmpeg コンポーネントを使い、曲を書き換えずに解析します。手動でインストールするか、必要に応じてダウンロードできます。',
    '기존 FFmpeg 구성 요소로 곡을 변경하지 않고 음량을 분석합니다. 직접 설치하거나 필요할 때 다운로드할 수 있습니다.'
  ],
  '正在分析响度…': ['Analyzing loudness…', 'ラウドネスを解析中…', '음량 분석 중…'],
  '正在分析响度：{0}%': [
    'Analyzing loudness: {0}%',
    'ラウドネスを解析中：{0}%',
    '음량 분석 중: {0}%'
  ],
  '整体响度': ['Integrated loudness', '統合ラウドネス', '통합 음량'],
  '响度范围': ['Loudness range', 'ラウドネス範囲', '음량 범위'],
  '样本峰值': ['Sample peak', 'サンプルピーク', '샘플 피크'],
  '真峰值': ['True peak', 'トゥルーピーク', '트루 피크'],
  '已分析时长': ['Analyzed duration', '解析した時間', '분석한 길이'],
  '{0} 秒': ['{0} seconds', '{0} 秒', '{0}초'],
  '参考目标响度': ['Reference target loudness', '参考の目標ラウドネス', '참고 목표 음량'],
  '峰值受限的参考增益': ['Peak-limited gain estimate', 'ピークを制限した参考ゲイン', '피크 제한 참고 게인'],
  '仅作静态增益参考，按 −1 dBTP 留出峰值余量；不会自动调整音量或写入标签。': [
    'A static gain estimate with headroom to −1 dBTP. It does not adjust volume automatically or write tags.',
    '−1 dBTP のピーク余裕を確保した静的ゲインの参考値です。音量の自動調整やタグへの書き込みは行いません。',
    '−1 dBTP까지 피크 여유를 둔 정적 게인 참고값입니다. 음량을 자동 조절하거나 태그를 기록하지 않습니다.'
  ],
  '真峰值达到或超过 0 dBTP，请留意采样间峰值。': [
    'True peak reaches or exceeds 0 dBTP. Watch for peaks between samples.',
    'トゥルーピークが 0 dBTP 以上です。サンプル間のピークに注意してください。',
    '트루 피크가 0 dBTP 이상입니다. 샘플 사이의 피크에 주의하세요.'
  ],
  '音频过短、静音或低于响度门限，无法可靠估算整体响度增益。': [
    'The audio is too short, silent or below the loudness gate. Integrated loudness gain cannot be estimated reliably.',
    '音声が短すぎるか、無音またはラウドネスのしきい値未満のため、統合ラウドネスのゲインを十分な精度で推定できません。',
    '오디오가 너무 짧거나 무음이거나 음량 임계값보다 낮아 통합 음량 게인을 정확하게 추정할 수 없습니다.'
  ],
  '低于响度门限': ['Below loudness gate', 'ラウドネスのしきい値未満', '음량 임계값 미만'],
  '静音': ['Silence', '無音', '무음'],
  '无法估算': ['Cannot estimate', '推定できません', '추정할 수 없음'],
  '复制结果': ['Copy result', '結果をコピー', '결과 복사'],
  '分析结果已复制': ['Analysis result copied', '解析結果をコピーしました', '분석 결과가 복사되었습니다'],
  '无法复制分析结果，请重试': [
    'Could not copy the analysis result. Try again',
    '解析結果をコピーできませんでした。再試行してください',
    '분석 결과를 복사할 수 없습니다. 다시 시도해 주세요'
  ],
  '取消分析': ['Cancel analysis', '解析をキャンセル', '분석 취소'],
  '开始分析': ['Start analysis', '解析を開始', '분석 시작'],
  '重新分析': ['Analyze again', '再解析', '다시 분석'],
  '已取消响度分析': [
    'Loudness analysis cancelled',
    'ラウドネス解析をキャンセルしました',
    '음량 분석이 취소되었습니다'
  ],
  '无法读取完整的响度分析结果': [
    'Could not read the complete loudness analysis result',
    'ラウドネス解析の結果を最後まで読み取れませんでした',
    '음량 분석 결과를 끝까지 읽을 수 없습니다'
  ],
  '响度分析仅支持本地歌曲': [
    'Loudness analysis supports local tracks only',
    'ラウドネス解析はローカルの曲のみ対応しています',
    '음량 분석은 로컬 곡만 지원합니다'
  ],
  '歌曲范围无效': ['Invalid track range', '曲の範囲が無効です', '곡 범위가 유효하지 않습니다'],
  '已有响度分析正在进行，请稍后重试': [
    'A loudness analysis is already running. Try again later',
    '別のラウドネス解析が進行中です。しばらくしてから再試行してください',
    '이미 음량 분석이 진행 중입니다. 잠시 후 다시 시도해 주세요'
  ],
  '无法读取本地音频文件': [
    'Could not read the local audio file',
    'ローカル音声ファイルを読み取れませんでした',
    '로컬 오디오 파일을 읽을 수 없습니다'
  ],
  '请先安装或修复音频工具': [
    'Install or repair the audio tools first',
    '先に音声ツールをインストールまたは修復してください',
    '먼저 오디오 도구를 설치하거나 복구해 주세요'
  ],
  '响度分析超时，请重试': [
    'Loudness analysis timed out. Try again',
    'ラウドネス解析がタイムアウトしました。再試行してください',
    '음량 분석 시간이 초과되었습니다. 다시 시도해 주세요'
  ],
  '无法分析此音频文件，请检查文件是否完整': [
    'Could not analyze this audio file. Check that the file is complete',
    'この音声ファイルを解析できませんでした。ファイルが完全か確認してください',
    '이 오디오 파일을 분석할 수 없습니다. 파일이 완전한지 확인해 주세요'
  ],
  '歌曲范围超出音频文件，请检查分轨信息': [
    'The track range exceeds the audio file. Check the CUE track information',
    '曲の範囲が音声ファイルを超えています。CUE 分割情報を確認してください',
    '곡 범위가 오디오 파일을 벗어납니다. CUE 분할 정보를 확인해 주세요'
  ],
  '分析期间源文件已改变，请重新分析': [
    'The source file changed during analysis. Analyze it again',
    '解析中に元のファイルが変更されました。もう一度解析してください',
    '분석 중 원본 파일이 변경되었습니다. 다시 분석해 주세요'
  ],
};
