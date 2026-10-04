const catalogProcessResources = <String, List<String>>{
  '播放器资源监控': ['Player resources', 'リソース監視', '플레이어 리소스'],
  '启用资源监控': ['Enable monitor', '監視を有効化', '모니터 사용'],
  '在侧栏下方显示': ['Show at the bottom of the sidebar', 'サイドバー下部に表示', '사이드바 하단에 표시'],
  '在歌词页左上角显示': [
    'Show at the top left of lyrics',
    '歌詞画面の左上に表示',
    '가사 화면 왼쪽 위에 표시'
  ],
  '仅统计当前播放器进程；只在已开启的显示位置可见时采样，隐藏窗口后停止。': [
    'Only this player process is measured. Sampling runs while an enabled view is visible and stops when the window is hidden.',
    'このプレーヤーのプロセスのみ計測します。有効な表示位置が見える間だけ計測し、ウィンドウを隠すと停止します。',
    '현재 플레이어 프로세스만 측정합니다. 켜 둔 표시 위치가 보일 때만 측정하며 창을 숨기면 중지합니다.'
  ],
  '各处共用显示方式与刷新间隔；侧栏和歌词页的 RAM 百分比为播放器工作集占物理内存的比例。': [
    'All views share the display mode and interval. Sidebar and lyrics RAM percentages show the player’s working set as a share of physical memory.',
    '表示方法と更新間隔は共通です。サイドバーと歌詞画面の RAM は、物理メモリに対するプレーヤーのワーキングセットの割合です。',
    '모든 위치가 표시 방식과 갱신 간격을 공유합니다. 사이드바와 가사 화면의 RAM 비율은 전체 물리 메모리 대비 플레이어 작업 집합입니다.'
  ],
  '仅统计当前播放器进程；离开此区域或隐藏窗口时停止采样。': [
    'Only this player process is measured. Sampling stops when this section or the window is hidden.',
    'このプレーヤーのプロセスのみ計測します。この領域やウィンドウを非表示にすると停止します。',
    '현재 플레이어 프로세스만 측정합니다. 이 영역이나 창을 숨기면 측정을 중지합니다.'
  ],
  '刷新间隔': ['Refresh interval', '更新間隔', '새로 고침 간격'],
  '每 {0} 秒': ['Every {0} s', '{0} 秒ごと', '{0}초마다'],
  '显示方式': ['Display', '表示方法', '표시 방식'],
  '数字': ['Numbers', '数値', '숫자'],
  '折线': ['Line', '折れ線', '꺾은선'],
  '条形': ['Bars', 'バー', '막대'],
  'CPU': ['CPU', 'CPU', 'CPU'],
  'GPU': ['GPU', 'GPU', 'GPU'],
  'RAM': ['RAM', 'RAM', 'RAM'],
  '内存': ['Memory', 'メモリ', '메모리'],
  '等待采样': ['Waiting for sample', '計測待ち', '측정 대기 중'],
  '不可用': ['Unavailable', '利用不可', '사용 불가'],
  'CPU 为全部逻辑核心的占用比例；GPU 为本进程最忙引擎；内存为工作集，包含共享页。': [
    'CPU is a share of all logical cores; GPU is this process’s busiest engine; memory is its working set, including shared pages.',
    'CPU は全論理コアに対する使用率、GPU は本プロセスの最も忙しいエンジン、メモリは共有ページを含むワーキングセットです。',
    'CPU는 전체 논리 코어 대비 사용률, GPU는 이 프로세스에서 가장 바쁜 엔진, 메모리는 공유 페이지를 포함한 작업 집합입니다.'
  ],
  '近 {0} 次采样': ['Last {0} samples', '直近 {0} 回の計測', '최근 {0}회 측정'],
  '内存条形以最近采样的最大工作集为参照，不代表系统内存用量。': [
    'Memory bars use the highest recent working set as their scale, not total system memory.',
    'メモリバーの基準は直近の最大ワーキングセットで、システムメモリ全体の使用率ではありません。',
    '메모리 막대는 최근 최대 작업 집합을 기준으로 하며 시스템 전체 메모리 사용률이 아닙니다.'
  ],
};
