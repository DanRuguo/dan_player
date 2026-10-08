// Read-only directory and metadata storage views; original tags stay intact.
const catalogDirectoryStorage = <String, List<String>>{
  '缓存与播放器数据': ['Cache & player data', 'キャッシュとプレイヤーデータ', '캐시 및 플레이어 데이터'],
  '播放器目录': ['Player directory', 'プレイヤーフォルダー', '플레이어 폴더'],
  '播放器组件目录占用': [
    'Player component storage',
    'プレイヤー構成ファイルの使用量',
    '플레이어 구성 요소 사용량'
  ],
  '播放器目录内的实际文件字节；不包含外部音乐、用户数据或外部工具。链接不跟随，首次选择或手动刷新时读取。': [
    'Actual file bytes inside the player directory; external music, user data and tools are excluded. Links are not followed. Read on first selection or manual refresh.',
    'プレイヤーフォルダー内の実際のファイルサイズです。外部の音楽、ユーザーデータ、ツールは含みません。リンク先はたどらず、初回選択時または手動更新時に読み取ります。',
    '플레이어 폴더 안의 실제 파일 크기입니다. 외부 음악, 사용자 데이터 및 도구는 제외합니다. 링크를 따라가지 않으며 처음 선택하거나 수동 새로 고침할 때 읽습니다.'
  ],
  '主程序': ['Main application', 'メインプログラム', '주 프로그램'],
  'Flutter引擎与运行库': [
    'Flutter engine & runtime',
    'Flutterエンジンとランタイム',
    'Flutter 엔진 및 런타임'
  ],
  '字体': ['Fonts', 'フォント', '글꼴'],
  '界面资源': ['Interface assets', '画面リソース', '화면 리소스'],
  'BASS音频组件': ['BASS audio components', 'BASSオーディオ構成要素', 'BASS 오디오 구성 요소'],
  'FFmpeg工具': ['FFmpeg tools', 'FFmpegツール', 'FFmpeg 도구'],
  '更新与安装辅助': ['Update & installation helpers', '更新とインストール補助', '업데이트 및 설치 보조'],
  '说明与许可证': ['Documentation & licenses', '説明とライセンス', '문서 및 라이선스'],
  '其他文件': ['Other files', 'その他のファイル', '기타 파일'],
  '占用空间分组': ['Group storage usage', '使用量の分類', '저장 공간 분류'],
  '未标注专辑': ['Unassigned album', 'アルバム未設定', '앨범 미지정'],
  '未标注艺术家': ['Unassigned artist', 'アーティスト未設定', '아티스트 미지정'],
  '暂无可统计的文件': ['No files to summarize', '集計できるファイルはありません', '집계할 파일이 없습니다'],
  '汇总全部已核实文件；同名专辑按艺术家区分，合作艺术家按完整署名统计。': [
    'Totals include all verified files. Albums with the same name are separated by artist; collaborations use the full artist credit.',
    '確認済みの全ファイルを集計します。同名アルバムはアーティスト別に区別し、共演者は完全な名義で集計します。',
    '확인된 모든 파일을 합산합니다. 이름이 같은 앨범은 아티스트별로 구분하며 공동 작업은 전체 아티스트 표기를 사용합니다.'
  ],
};
