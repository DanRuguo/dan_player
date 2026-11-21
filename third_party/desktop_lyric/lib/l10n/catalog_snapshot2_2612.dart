// Snapshot 26.1.2-snapshot.2 UI catalog (zh keys -> [en, ja, ko]).
const Map<String, List<String>> catalogSnapshot22612 = {
  '点击页头的定位图标时，目标曲目行会短暂以主题色高亮脉冲提示位置；专辑、艺术家与分类详情页顶部同时显示合集总时长。': [
    'Clicking the locate icon in the header briefly pulses the target track row in the theme accent color; album, artist, and category detail headers also show the collection total duration.',
    'ヘッダーの現在曲へ移動アイコンをクリックすると対象曲の行がテーマカラーで一時的にハイライト表示されます。アルバム・アーティスト・カテゴリ詳細ページのヘッダーには合計再生時間も表示されます。',
    '상단의 현재 곡으로 이동 아이콘을 누르면 대상 곡 행이 테마 강조색으로 잠시 빛나 위치를 알려 주며, 앨범·아티스트·카테고리 상세 페이지 상단에 전체 재생 시간도 함께 표시됩니다.',
  ],
  '回放增益除标准 ReplayGain 标签外，还兼容 Opus R128 增益标签、MP4 自由格式标签（含 iTunes 命名空间与大小写变体）及 ID3v2.4 RVA2 帧；本地封面补充识别同目录同名曲目封面、artwork/coverart/frontcover 等常用命名以及 Windows 媒体播放器大图。':
      [
    'ReplayGain now also supports Opus R128 gain tags, MP4 freeform tags (including iTunes namespace and uppercase/lowercase variants), and ID3v2.4 RVA2 frames; local cover fallback also recognizes exact track-stem sidecar images, common names like artwork/coverart/frontcover, and Windows Media Player large artwork.',
    'リプレイゲインは標準タグに加え、Opus R128 ゲインタグ、MP4 フリーフォームタグ（iTunes 名前空間や大文字・小文字の表記揺れを含む）、ID3v2.4 RVA2 フレームにも対応します。ローカルジャケット検出も曲ファイルと同名の画像や artwork・coverart・frontcover、Windows Media Player の大サイズ画像を追加で認識します。',
    '리플레이게인은 표준 태그 외에도 Opus R128 게인 태그, MP4 자유 형식 태그(iTunes 네임스페이스 및 대소문자 변형 포함), ID3v2.4 RVA2 프레임을 지원합니다. 로컬 커버 탐색도 곡 파일과 같은 이름의 이미지, artwork·coverart·frontcover 같은 일반 파일명 및 Windows Media Player 대형 커버를 추가로 인식합니다.',
  ],
  '已开启任务栏歌词，桌面歌词与任务栏歌词互斥；此处外观设置会保留，打开桌面歌词时会自动切换。': [
    'Taskbar lyrics are currently enabled, and desktop lyrics are mutually exclusive with them; your appearance settings here are kept and will apply automatically if you open desktop lyrics.',
    '現在タスクバー歌詞が有効です。デスクトップ歌詞とタスクバー歌詞は排他的ですが、ここでの外観設定は保持され、デスクトップ歌詞を開くと自動的に切り替わります。',
    '현재 작업 표시줄 가사가 켜져 있으며 데스크톱 가사와 동시에 사용할 수 없습니다. 이곳의 모양 설정은 유지되며 데스크톱 가사를 열면 자동으로 전환됩니다.',
  ],
  '当前已开启 WASAPI 独占输出，交叉淡入淡出将改用连续输出；此处选择会保留，切回共享输出后生效。': [
    'WASAPI exclusive output is currently enabled, so crossfade falls back to gapless continuity; your selection is preserved and takes effect again in shared output.',
    '現在 WASAPI 排他出力が有効なため、クロスフェードはギャップレス再生に切り替わります。ここでの選択は保持され、共有出力に戻すと再び有効になります。',
    '현재 WASAPI 단독 출력이 켜져 있어 크로스페이드는 갭리스 연속 출력으로 동작합니다. 이 선택은 유지되며 공유 출력으로 돌아가면 다시 적용됩니다.',
  ],
  '已选择交叉淡入淡出；开启 WASAPI 独占输出后将改用连续输出，关闭独占后恢复淡入淡出。': [
    'Crossfade is selected; while WASAPI exclusive output is enabled, playback uses gapless continuity and resumes crossfade once exclusive mode is turned off.',
    'クロスフェードが選択されています。WASAPI 排他出力を有効にするとギャップレス再生に切り替わり、排他出力をオフにするとクロスフェードに戻ります。',
    '크로스페이드가 선택되어 있습니다. WASAPI 단독 출력을 켜면 갭리스 연속 출력으로 전환되며, 단독 출력을 끄면 크로스페이드로 복원됩니다.',
  ],
  '当前已关闭“交互反馈动画”，封面轮廓辉光与折射暂时停用；此处开关会保留，重新开启后恢复。': [
    'Interaction feedback motion is currently off, so cover contour glow and refraction are paused; this toggle stays saved and resumes when feedback motion is turned back on.',
    '現在「操作フィードバックアニメーション」がオフのため、ジャケット輪郭の輝きと屈折は一時停止しています。この設定は保持され、再度オンにすると復帰します。',
    '현재 "상호작용 피드백 애니메이션"이 꺼져 있어 커버 윤곽 빛과 굴절 효과가 잠시 중지되었습니다. 이 설정은 유지되며 다시 켜면 복원됩니다.',
  ],
  '当前已关闭“主题与封面渐变”，动态 GIF 封面暂时显示首帧；此处开关会保留，重新开启后恢复。': [
    'Theme and cover transitions are currently off, so animated GIF covers display their first frame; this toggle stays saved and resumes when that motion is turned back on.',
    '現在「テーマとジャケットのグラデーション」がオフのため、アニメーション GIF ジャケットは先頭フレームのみ表示されます。この設定は保持され、再度オンにすると復帰します。',
    '현재 "테마 및 커버 전환"이 꺼져 있어 애니메이션 GIF 커버가 첫 프레임만 표시합니다. 이 설정은 유지되며 다시 켜면 복원됩니다.',
  ],
  '悬停桌面歌词操作栏可一键“显示主窗口”回到播放器，横排与竖排方向也在“桌面歌词显示”和“歌词体验”设置间实时同步。': [
    'Hover over the desktop lyrics toolbar to click "Show main window" and jump straight back to the player; horizontal/vertical orientation also stays synced between Desktop Lyrics Display and Lyric Experience settings.',
    'デスクトップ歌詞の操作バーにカーソルを合わせると「メインウィンドウを表示」からワンクリックで本体に戻れます。横書き・縦書きの向きも「デスクトップ歌詞の表示」と「歌詞体験」設定の間でリアルタイムに同期されます。',
    '데스크톱 가사 도구 모음에 마우스를 올리면 "메인 창 표시" 버튼으로 바로 플레이어로 돌아갈 수 있으며, 가로/세로 방향도 "데스크톱 가사 표시"와 "가사 경험" 설정 간에 실시간으로 동기화됩니다.',
  ],
  '开启 WASAPI 独占输出或跳过头尾静音时，歌曲过渡设置会实时提示实际生效方式并保留您的原选择，关闭冲突选项后自动恢复。': [
    'When WASAPI exclusive output or silence skipping is enabled, Track Transitions shows a live hint of the active behavior while keeping your choice saved so it resumes automatically once the conflicting option is turned off.',
    'WASAPI 排他出力または無音スキップが有効な場合、曲の切り替え設定には実際の動作がリアルタイム表示され、元の選択は保持されて競合オプションをオフにすると自動的に復元されます。',
    'WASAPI 단독 출력이나 앞뒤 무음 건너뛰기가 켜져 있을 때 곡 전환 설정은 실제 적용 방식을 실시간으로 안내하며 원래 선택을 유지해 충돌 옵션을 끄면 자동으로 복원됩니다.',
  ],
  '分隔符': ['Separator', '区切り文字', '구분자'],
  '侧边栏': ['Sidebar', 'サイドバー', '사이드바'],
  '热键': ['Hotkeys', 'ホットキー', '단축키'],
  '断点续播': ['Resume playback', 'レジューム再生', '이어 듣기'],
  '防止休眠': ['Prevent sleep', 'スリープ防止', '절전 방지'],
  '自动扫描': ['Auto scan', '自動スキャン', '자동 스캔'],
  '版本号': ['Version', 'バージョン', '버전'],
};
