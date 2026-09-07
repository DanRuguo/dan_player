const Map<String, List<String>> catalogReplayGain = {
  'ReplayGain 音量均衡': [
    'ReplayGain volume leveling',
    'ReplayGain 音量調整',
    'ReplayGain 음량 조정'
  ],
  '读取歌曲已有的响度标签，不修改音乐文件；没有标签时保持原音量。': [
    'Uses existing loudness tags without changing music files. Untagged tracks keep their original volume.',
    '既存の音量タグを使用し、音楽ファイルは変更しません。タグがない曲は元の音量を保ちます。',
    '기존 음량 태그를 사용하며 음악 파일은 변경하지 않습니다. 태그가 없으면 원래 음량을 유지합니다.'
  ],
  '曲目均衡': ['Track gain', 'トラック単位', '트랙별 조정'],
  '专辑均衡': ['Album gain', 'アルバム単位', '앨범별 조정'],
  '曲目模式平衡歌曲之间的音量；专辑模式保留专辑内部的强弱关系，缺少专辑标签时使用曲目标签。': [
    'Track mode balances volume between songs. Album mode preserves relative levels within an album and falls back to track tags when album tags are absent.',
    'トラックモードは曲間の音量を調整します。アルバムモードは曲同士の強弱を保ち、アルバムタグがない場合はトラックタグを使います。',
    '트랙 모드는 곡 사이의 음량을 조정합니다. 앨범 모드는 앨범 내 상대 음량을 유지하며 앨범 태그가 없으면 트랙 태그를 사용합니다.'
  ],
  '依据标签峰值限制增益': [
    'Limit gain using tagged peaks',
    'タグのピーク値で増幅を制限',
    '태그 피크값으로 증폭 제한'
  ],
  '无峰值标签时不额外放大；此选项不限制均衡器等其他处理产生的峰值。': [
    'Without peak tags, no extra amplification is applied. This does not limit peaks introduced by the equalizer or other processing.',
    'ピークタグがない場合は追加増幅しません。イコライザーなど別の処理によるピークは制限しません。',
    '피크 태그가 없으면 추가로 증폭하지 않습니다. 이퀄라이저 등 다른 처리에서 발생한 피크는 제한하지 않습니다.'
  ],
  '音量均衡暂时无法应用，原设置已保留。': [
    'Volume leveling could not be applied. Previous settings are retained.',
    '音量調整を適用できませんでした。以前の設定を保持しています。',
    '음량 조정을 적용할 수 없습니다. 이전 설정을 유지합니다.'
  ],
};
