const Map<String, List<String>> catalogRendering = {
  '水滴折射': ['Water drop refraction', '水滴の屈折', '물방울 굴절'],
  '动态 GIF 封面': ['Animated GIF covers', 'GIF ジャケットのアニメーション', 'GIF 표지 애니메이션'],
  '播放已导入的 GIF 封面；减少动画或关闭封面动画时显示首帧。': [
    'Animate imported GIF covers. Show the first frame when motion is reduced or artwork animation is off.',
    '読み込んだ GIF ジャケットを再生します。動きを減らす設定やジャケットのアニメーションがオフの場合は最初のフレームを表示します。',
    '가져온 GIF 표지를 재생합니다. 동작 줄이기 또는 표지 애니메이션이 꺼져 있으면 첫 프레임을 표시합니다.'
  ],
  '封面轮廓辉光': ['Cover contour glow', 'ジャケットの輪郭の輝き', '표지 윤곽 빛 효과'],
  '播放页大封面随鼠标局部折射并亮起细线；与分类流光共用交互反馈动画开关，减少动画时停用。': [
    'Refract the large player cover and light up fine contours near the pointer. Shares Interaction feedback with category glow; disabled with reduced motion.',
    '再生画面の大きなジャケットで、ポインター付近が屈折し細い輪郭が光ります。分類画面の光と同じ操作フィードバック設定を使い、動きを減らす設定では無効になります。',
    '재생 화면의 큰 표지에서 포인터 근처가 굴절되고 가는 윤곽이 빛납니다. 분류 화면의 빛 효과와 조작 피드백 설정을 공유하며, 동작 줄이기에서는 꺼집니다.'
  ],
  '频谱样式': ['Spectrum style', 'スペクトラムのスタイル', '스펙트럼 스타일'],
  '圆头音柱': ['Rounded bars', '丸いバー', '둥근 막대'],
  '像素音柱': ['Pixel bars', 'ピクセルバー', '픽셀 막대'],
  '样式同时用于播放条上方与封面四周。': [
    'Use this style above the progress bar and around the cover.',
    'シークバーの上とジャケットの周囲に同じスタイルを使います。',
    '진행 막대 위와 표지 둘레에 같은 스타일을 사용합니다.'
  ],
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
  "交互时跟随屏幕，交互结束后动画最高 48 FPS；静止时不持续绘制。": [
    "Follows the display during interaction, then limits animations to 48 FPS. No continuous rendering when idle.",
    "操作中はディスプレイに合わせ、操作後のアニメーションは最大 48 FPS。静止中は連続描画しません。",
    "조작 중에는 디스플레이에 맞추고 이후 애니메이션은 최대 48 FPS로 제한합니다. 정지 상태에서는 계속 그리지 않습니다."
  ],
  "动画按所选目标刷新；跨屏时自动受所在屏幕限制。实际帧率也取决于系统负载。": [
    "Targets the selected animation frame rate, limited by the current display when moving between screens. Actual frame rate also depends on system load.",
    "選択したフレームレートを目標に描画し、画面間の移動時は移動先の上限に合わせます。実際のフレームレートはシステム負荷にも依存します。",
    "선택한 프레임률을 목표로 하며 화면 이동 시 해당 화면 상한에 맞춥니다. 실제 프레임률은 시스템 부하에도 영향을 받습니다."
  ],
  "频谱音柱数量": ["Spectrum bar count", "スペクトラムのバー数", "스펙트럼 막대 수"],
  '频谱显示位置': ['Spectrum placement', 'スペクトラムの位置', '스펙트럼 위치'],
  '播放条上方': ['Above progress bar', 'シークバーの上', '진행 막대 위'],
  '封面四周': ['Around cover', 'ジャケットの周囲', '표지 둘레'],
  '音柱可显示在播放条上方或封面四周；关闭后保留进度条。': [
    'Show spectrum bars above the progress bar or around the cover. Turning this off keeps the progress bar.',
    'スペクトラムをシークバーの上またはジャケットの周囲に表示します。オフにしてもシークバーは残ります。',
    '스펙트럼을 진행 막대 위나 표지 둘레에 표시합니다. 꺼도 진행 막대는 유지됩니다.'
  ],
  '四周音柱会根据封面留白调整高度；窄窗口未显示封面时，改在播放条上方显示。': [
    'Bars adapt to the space around the cover. When a narrow window hides the cover, they appear above the progress bar.',
    '周囲の余白に合わせてバーの高さを調整します。狭いウィンドウでジャケットが非表示の場合は、シークバーの上に表示します。',
    '표지 주변 여백에 맞춰 막대 높이를 조절합니다. 좁은 창에서 표지가 보이지 않으면 진행 막대 위에 표시합니다.'
  ],
  "低／中／高档最多显示 36／72／112 根音柱，实际数量随可用空间调整。档位越高通常越耗 CPU；降低档位时音柱变宽。": [
    "Low / Medium / High show up to 36 / 72 / 112 bars, depending on available space. Higher levels typically use more CPU power. Lower levels use wider bars.",
    "少なめ／標準／多めは最大 36／72／112 本で、実際の本数は表示領域によって変わります。段階が高いほど通常は CPU の負荷が増えます。下げるとバーが太くなります。",
    "낮음 / 중간 / 높음은 최대 36 / 72 / 112개이며 실제 개수는 사용 가능한 공간에 따라 달라집니다. 단계가 높을수록 일반적으로 CPU 부하가 증가합니다. 낮추면 막대가 굵어집니다."
  ],
  '低': ['Low', '少なめ', '낮음'],
  '中': ['Medium', '標準', '중간'],
  '高': ['High', '多め', '높음'],
};
