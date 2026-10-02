const Map<String, List<String>> catalogReplaygainGain = {
  '读取已有响度标签，不修改音乐文件；无标签补偿默认关闭。': [
    'Use existing loudness tags without changing music files. Untagged gain defaults to zero.',
    '既存の音量タグを使い、音楽ファイルは変更しません。タグなし補正は初期値 0 です。',
    '기존 음량 태그를 사용하며 음악 파일은 바꾸지 않습니다. 태그 없는 곡의 보정은 기본 0입니다.'
  ],
  'ReplayGain 预增益': [
    'ReplayGain preamp',
    'ReplayGain プリアンプ',
    'ReplayGain 프리앰프'
  ],
  '无标签补偿': ['Untagged gain', 'タグなし補正', '태그 없는 곡 보정'],
  '预增益叠加标签增益或无标签补偿；补偿只用于没有可用增益标签的歌曲。关闭 ReplayGain 时均不生效。': [
    'Preamp adds to tag gain or untagged gain. Untagged gain applies only without a usable gain tag. Both are inactive with ReplayGain off.',
    'プリアンプはタグのゲインまたはタグなし補正に加算されます。補正は有効なゲインタグがない曲だけに適用されます。ReplayGain がオフの場合、どちらも無効です。',
    '프리앰프는 태그 게인이나 태그 없는 곡 보정에 더해집니다. 보정은 유효한 게인 태그가 없는 곡에만 적용됩니다. ReplayGain을 끄면 둘 다 적용되지 않습니다.'
  ],
  '自定义增益…': ['Custom gain…', 'ゲイン入力…', '게인 직접 입력…'],
  '增益（dB）': ['Gain (dB)', 'ゲイン（dB）', '게인 (dB)'],
  '请输入 {0} 到 {1} 之间的增益（dB）': [
    'Enter a gain from {0} to {1} dB',
    '{0}～{1} dB のゲインを入力してください',
    '{0}~{1} dB의 게인을 입력하세요'
  ],
  '独占不代表 Bit-perfect 已验证。结束位置来自后端媒体边界，未检测硬件缓冲排空。削波保护只约束组合后的 ReplayGain 增益，后续 EQ 和变速仍可能改变样本；源文件响度可从歌曲菜单单独分析，不能代替全链路削波测量。':
      [
    'Exclusive output does not verify bit-perfect playback. End position is the backend media boundary; hardware buffer drain is unmeasured. Peak protection covers only combined ReplayGain gain. Later EQ and tempo processing can still change samples. Source loudness analysis is available separately in the song menu and cannot measure clipping across the full output chain.',
    '排他出力でもビットパーフェクトは未検証です。終了位置はバックエンドの境界で、ハードウェアバッファの排出は未測定です。ピーク保護は合算した ReplayGain ゲインのみを制限し、その後の EQ や速度処理はサンプルを変える場合があります。曲メニューの音源ラウドネス分析は別機能で、出力経路全体のクリッピング測定の代わりにはなりません。',
    '독점 출력이 비트 퍼펙트 재생을 검증하는 것은 아닙니다. 종료 위치는 백엔드의 미디어 경계이며 하드웨어 버퍼 소진은 측정하지 않았습니다. 피크 보호는 합산한 ReplayGain 게인만 제한합니다. 이후 EQ와 속도 처리는 샘플을 바꿀 수 있습니다. 곡 메뉴의 음원 라우드니스 분석은 별도 기능이며 전체 출력 경로의 클리핑 측정을 대신하지 않습니다.'
  ],
};
