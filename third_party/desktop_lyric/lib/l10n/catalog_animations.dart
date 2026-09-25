const catalogAnimations = <String, List<String>>{
  '播放时图标旋转': ['Rotate logo during playback', '再生中にアイコンを回転', '재생 중 아이콘 회전'],
  '歌曲播放时，左上角播放器图标缓慢旋转；暂停或隐藏时停止。': [
    'The top-left player icon rotates slowly during playback and stops when paused or hidden.',
    '再生中は左上のアイコンがゆっくり回転し、一時停止中や非表示時は止まります。',
    '재생 중 왼쪽 위 아이콘이 천천히 회전하며 일시 정지하거나 창을 숨기면 멈춥니다.'
  ],
  '动画管理': ['Animation controls', 'アニメーション管理', '애니메이션 관리'],
  '单项开关只控制对应动画；全部开关还会同步调整频谱、背景动效与低频律动、歌词回弹。播放、点击、拖动和实时进度不受影响。': [
    'Individual switches control only their animations. Enable/Disable all also changes the spectra, background motion and bass response, and lyric bounce. Playback, clicks, dragging and live progress remain available.',
    '個別のスイッチは対応するアニメーションだけを変更します。「すべて」はスペクトラム、背景の動きと低音連動、歌詞のバウンドも切り替えます。再生、クリック、ドラッグ、再生位置の更新には影響しません。',
    '개별 스위치는 해당 애니메이션만 제어합니다. 전체 켜기/끄기는 스펙트럼, 배경 움직임과 저음 반응, 가사 탄성 효과도 함께 바꿉니다. 재생, 클릭, 드래그와 실시간 진행에는 영향을 주지 않습니다.'
  ],
  '全部开启': ['Enable all', 'すべてオン', '모두 켜기'],
  '全部关闭': ['Disable all', 'すべてオフ', '모두 끄기'],
  '开屏动画': ['Startup animation', '起動アニメーション', '시작 애니메이션'],
  '启动时的品牌展示与淡入淡出。': [
    'Brand presentation and fades at startup.',
    '起動時のブランド表示とフェード。',
    '시작 시 브랜드 표시와 페이드 효과입니다.'
  ],
  '下一首动画': ['Play-next animation', '次に再生のアニメーション', '다음 재생 애니메이션'],
  '添加下一首时，封面飞向播放队列。': [
    'The cover flies to the queue when adding a track to play next.',
    '次に再生へ追加すると、ジャケットがキューへ移動します。',
    '다음 재생에 추가할 때 표지가 재생 대기열로 이동합니다.'
  ],
  '封面追踪': ['Cover tracking', 'ジャケットの追従', '표지 추적'],
  '切换视图或进入详情时，封面追踪与卡片渐显。': [
    'Cover tracking and card fades when switching views or opening details.',
    '表示の切り替えや詳細を開く際のジャケット追従とカードのフェード。',
    '보기 전환 또는 상세 화면 진입 시 표지 추적과 카드 페이드입니다.'
  ],
  '页面浮现': ['Item entrances', '項目の出現', '항목 등장'],
  '页面项目首次出现时渐显、上浮或展开。': [
    'Items fade, rise or expand when they first appear.',
    '項目が初めて現れる際にフェード、上昇、拡大します。',
    '항목이 처음 나타날 때 페이드, 상승 또는 확대됩니다.'
  ],
  '页面切换': ['Page transitions', 'ページ切り替え', '페이지 전환'],
  '页面、内容区与引导步骤之间的过渡。': [
    'Transitions between pages, content sections and onboarding steps.',
    'ページ、コンテンツ、初回ガイドのステップ間の切り替え。',
    '페이지, 콘텐츠 영역 및 시작 안내 단계 사이의 전환입니다.'
  ],
  '布局与文字动画': ['Layout & text motion', '配置と文字の動き', '배치 및 텍스트 애니메이션'],
  '封面尺寸、排序、自动填充、标题显隐及长文本滚动。': [
    'Cover size, sorting, auto-fill, title visibility and scrolling long text.',
    'ジャケットサイズ、並べ替え、自動配置、タイトル表示、長い文字列のスクロール。',
    '표지 크기, 정렬, 자동 채우기, 제목 표시 및 긴 텍스트 스크롤입니다.'
  ],
  '歌词动画': ['Lyric motion', '歌詞アニメーション', '가사 애니메이션'],
  '逐词渐亮、长音浮动、左右错速与行跟随；关闭后仍更新当前歌词。': [
    'Word highlighting, sustained-note lift, staggered line motion and line following. Current lyrics still update when disabled.',
    '単語のハイライト、ロングトーンの浮き上がり、左右の時間差と行の追従。オフでも現在の歌詞は更新されます。',
    '단어별 강조, 긴 음의 떠오름, 좌우 시간차와 행 따라가기입니다. 꺼도 현재 가사는 갱신됩니다.'
  ],
  '交互反馈动画': ['Interaction feedback', '操作フィードバック', '상호작용 피드백'],
  '悬停光效、水波纹、按钮和控件的状态过渡。': [
    'Hover glow, ripples and button/control state transitions.',
    'ホバーの光、波紋、ボタンやコントロールの状態変化。',
    '마우스 발광, 물결 효과 및 버튼과 컨트롤의 상태 전환입니다.'
  ],
  '主题与封面渐变': ['Theme & artwork fades', 'テーマと画像のフェード', '테마 및 표지 페이드'],
  '主题、语言和封面更新时的渐变过渡。': [
    'Fades when the theme, language or artwork changes.',
    'テーマ、言語、ジャケット更新時のフェード。',
    '테마, 언어 또는 표지 변경 시 페이드 효과입니다.'
  ],
};
