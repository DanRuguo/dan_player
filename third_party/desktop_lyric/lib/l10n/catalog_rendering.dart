const Map<String, List<String>> catalogRendering = {
  '不可见时暂停视觉更新': [
    'Pause visual updates when hidden',
    '非表示時に表示の更新を一時停止',
    '보이지 않을 때 시각적 업데이트 일시 중지',
  ],
  '暂停隐藏窗口和已打开但不可见页面的歌词视觉、频谱与背景动效；不影响播放。关闭后继续更新已挂载视图，可能增加后台开销。': [
    'Pause lyric visuals, the spectrum and background motion in hidden windows and previously opened pages that are no longer visible. Playback is unaffected. Turning this off keeps mounted views updating and may increase background activity.',
    '非表示のウィンドウや、開いた後に見えなくなったページの歌詞表示・スペクトラム・背景アニメーションを一時停止します。再生には影響しません。オフにすると、読み込み済みの表示は更新を続けるため、バックグラウンドの負荷が増える場合があります。',
    '숨겨진 창과 이미 열었지만 현재 보이지 않는 페이지의 가사 표시, 스펙트럼 및 배경 움직임을 일시 중지합니다. 재생에는 영향을 주지 않습니다. 끄면 이미 로드된 화면이 계속 업데이트되어 백그라운드 작업량이 늘어날 수 있습니다.',
  ],
  "界面刷新率": ["Interface frame rate", "画面のフレームレート", "화면 프레임률"],
  "只控制界面绘制，不改变屏幕设置或音频播放速度。": [
    "Controls interface rendering only, without changing display settings or audio speed.",
    "画面描画のみを制御します。ディスプレイ設定や音声の再生速度は変わりません。",
    "화면 그리기만 제어하며 디스플레이 설정이나 오디오 재생 속도는 변경하지 않습니다."
  ],
  "跟随屏幕": ["Follow display", "画面に合わせる", "화면에 맞춤"],
  "自适应刷新": ["Adaptive", "自動調整", "자동 조절"],
  "固定刷新率": ["Fixed frame rate", "固定フレームレート", "고정 프레임률"],
  "当前窗口上限：{0} FPS": [
    "Current window limit: {0} FPS",
    "現在のウィンドウの上限：{0} FPS",
    "현재 창 상한: {0} FPS"
  ],
  "有画面变化时跟随屏幕刷新，静止时不持续绘制。": [
    "Follows the display when visuals change. No continuous rendering when idle.",
    "画面が変化するときはディスプレイに合わせ、静止中は連続描画しません。",
    "화면이 변할 때 디스플레이에 맞추며 정지 상태에서는 계속 그리지 않습니다."
  ],
  "交互时跟随屏幕，交互结束后动画最高 60 FPS；静止时不持续绘制。": [
    "Follows the display during interaction, then limits animations to 60 FPS. No continuous rendering when idle.",
    "操作中はディスプレイに合わせ、操作後のアニメーションは最大 60 FPS。静止中は連続描画しません。",
    "조작 중에는 디스플레이에 맞추고 이후 애니메이션은 최대 60 FPS로 제한합니다. 정지 상태에서는 계속 그리지 않습니다."
  ],
  "动画按所选目标刷新；跨屏时自动受所在屏幕限制。实际帧率也取决于系统负载。": [
    "Targets the selected animation frame rate, limited by the current display when moving between screens. Actual frame rate also depends on system load.",
    "選択したフレームレートを目標に描画し、画面間の移動時は移動先の上限に合わせます。実際のフレームレートはシステム負荷にも依存します。",
    "선택한 프레임률을 목표로 하며 화면 이동 시 해당 화면 상한에 맞춥니다. 실제 프레임률은 시스템 부하에도 영향을 받습니다."
  ],
  "频谱音柱数量": ["Spectrum bar count", "スペクトラムのバー数", "스펙트럼 막대 수"],
  "低／中／高档最多显示 36／72／112 根音柱，实际数量随窗口宽度调整。档位越高通常越耗 CPU；降低档位时音柱变宽，整体宽度不变。": [
    "Low / Medium / High show up to 36 / 72 / 112 bars, depending on window width. Higher levels typically use more CPU power. Lower levels use wider bars across the same total width.",
    "少なめ／標準／多めは最大 36／72／112 本で、実際の本数はウィンドウの幅によって変わります。段階が高いほど通常は CPU の消費電力が増えます。下げると全体の幅を保ったままバーが太くなります。",
    "낮음 / 중간 / 높음은 최대 36 / 72 / 112개이며 실제 개수는 창 너비에 따라 달라집니다. 단계가 높을수록 일반적으로 CPU 소비 전력이 증가합니다. 낮추면 전체 너비는 유지되고 막대가 굵어집니다."
  ],
  '低': ['Low', '少なめ', '낮음'],
  '中': ['Medium', '標準', '중간'],
  '高': ['High', '多め', '높음'],
};
