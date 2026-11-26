// Snapshot 26.1.2-snapshot.8 UI catalog (zh keys -> [en, ja, ko]).
const Map<String, List<String>> catalogSnapshot82612 = {
  // Report Issue dialog & 15-day timestamped logs
  '请在此粘贴已复制的完整诊断报告。': [
    'Paste the full diagnostic report from your clipboard here.',
    'クリップボードにコピーした診断レポートをここに貼り付けてください。',
    '클립보드에 복사한 전체 진단 보고서를 여기에 붙여 넣으세요.',
  ],
  '功能异常': [
    'Bug report',
    '不具合',
    '오류 제보',
  ],
  '播放与音频': [
    'Playback & audio',
    '再生・オーディオ',
    '재생 및 오디오',
  ],
  '歌词与联网': [
    'Lyrics & online',
    '歌詞・オンライン',
    '가사 및 온라인',
  ],
  '界面与动画': [
    'UI & motion',
    '画面・アニメーション',
    '인터페이스 및 애니메이션',
  ],
  '功能建议': [
    'Feature request',
    '機能提案',
    '기능 제안',
  ],
  '汇总环境摘要与带时间戳的运行日志；日志文件保留 15 天后自动清理。': [
    'Collects an environment summary and timestamped runtime logs; log files are automatically deleted after 15 days.',
    '環境概要とタイムスタンプ付き実行ログをまとめます。ログファイルは 15 日経過後に自動削除されます。',
    '환경 요약과 타임스탬프가 포함된 실행 로그를 수집하며, 로그 파일은 15일 후 자동으로 삭제됩니다.',
  ],
  '近 15 天日志：{0} 条': [
    'Last 15 days: {0} entries',
    '直近 15 日のログ：{0} 件',
    '최근 15일 로그: {0}개',
  ],
  '警告/错误：{0}': [
    'Warnings/Errors: {0}',
    '警告／エラー：{0}',
    '경고/오류: {0}',
  ],
  '日志目录': [
    'Log folder',
    'ログフォルダー',
    '로그 폴더',
  ],
  '打开日志目录': [
    'Open log folder',
    'ログフォルダーを開く',
    '로그 폴더 열기',
  ],
  '问题描述': [
    'Issue description',
    '問題の説明',
    '문제 설명',
  ],
  '（未填写补充说明）': [
    '(No additional description provided)',
    '（補足説明は未入力です）',
    '(추가 설명이 입력되지 않았습니다)',
  ],
  '运行环境': [
    'Runtime environment',
    '実行環境',
    '실행 환경',
  ],
  '运行日志': [
    'Runtime logs',
    '実行ログ',
    '실행 로그',
  ],
  '（暂无日志记录）': [
    '(No log entries recorded)',
    '（ログ記録はありません）',
    '(기록된 로그가 없습니다)',
  ],
  '注：因浏览器链接长度限制，此处仅附带最新日志片段；完整报告已自动复制到剪贴板。': [
    'Note: Only the latest log excerpt is attached here due to browser URL length limits; the full report has been copied to your clipboard.',
    '注：ブラウザー URL 長の制限により最新のログ抜粋のみ添付しています。完全なレポートはクリップボードにコピーされました。',
    '참고: 브라우저 URL 길이 제한으로 최신 로그 일부만 포함되었으며, 전체 보고서는 클립보드에 자동 복사되었습니다.',
  ],
  '已复制完整诊断报告': [
    'Copied full diagnostic report',
    '完全な診断レポートをコピーしました',
    '전체 진단 보고서를 복사했습니다',
  ],
  '当前没有可复制的日志': [
    'No logs available to copy',
    'コピーできるログがありません',
    '복사할 로그가 없습니다',
  ],
  '已复制运行日志': [
    'Copied runtime logs',
    '実行ログをコピーしました',
    '실행 로그를 복사했습니다',
  ],
  '运行日志已清空': [
    'Runtime logs cleared',
    '実行ログを消去しました',
    '실행 로그를 비웠습니다',
  ],
  '请先填写问题标题': [
    'Please enter an issue title first',
    '先に問題のタイトルを入力してください',
    '먼저 문제 제목을 입력해 주세요',
  ],
  '未能打开浏览器，完整诊断报告已复制到剪贴板': [
    'Could not open browser; full diagnostic report copied to clipboard',
    'ブラウザーを開けなかったため、完全な診断レポートをクリップボードにコピーしました',
    '브라우저를 열지 못해 전체 진단 보고서를 클립보드에 복사했습니다',
  ],
  '已打开 GitHub 问题页，完整日志报告已复制到剪贴板': [
    'Opened GitHub issue page; full log report copied to clipboard',
    'GitHub の Issue ページを開き、完全なログレポートをクリップボードにコピーしました',
    'GitHub 이슈 페이지를 열었으며 전체 로그 보고서를 클립보드에 복사했습니다',
  ],
  '隐藏个人路径': [
    'Redact personal paths',
    '個人パスを伏せる',
    '개인 경로 가리기',
  ],
  '附带运行日志': [
    'Attach runtime logs',
    '実行ログを添付',
    '실행 로그 첨부',
  ],
  '问题标题': [
    'Issue title',
    '問題のタイトル',
    '문제 제목',
  ],
  '简要概括遇到的问题或建议': [
    'Briefly summarize the problem or suggestion',
    '発生した問題や提案を簡潔に入力してください',
    '발생한 문제나 제안을 간략히 요약해 주세요',
  ],
  '复现步骤与补充说明': [
    'Steps to reproduce & details',
    '再現手順と補足説明',
    '재현 단계 및 추가 설명',
  ],
  '可填写触发步骤、预期表现与实际现象（选填）': [
    'Optional steps to trigger, expected behavior, and actual behavior',
    '再現手順、期待される動作、実際の現象を記入できます（任意）',
    '발생 단계, 예상 동작 및 실제 현상을 입력할 수 있습니다(선택)',
  ],
  '15 天自动删除 · {0} 条': [
    '15-day auto-clean · {0} entries',
    '15 日で自動削除 · {0} 件',
    '15일 자동 삭제 · {0}개',
  ],
  '恢复自动同步': [
    'Resume live sync',
    '自動同期に戻す',
    '자동 동기화 복원',
  ],
  '刷新并清理过期日志': [
    'Refresh & prune expired logs',
    '更新して期限切れログを整理',
    '새로고침 및 만료된 로그 정리',
  ],
  '复制日志': [
    'Copy logs',
    'ログをコピー',
    '로그 복사',
  ],
  '清空日志': [
    'Clear logs',
    'ログを消去',
    '로그 비우기',
  ],
  '日志筛选': [
    'Log filter',
    'ログの絞り込み',
    '로그 필터',
  ],
  '近 15 天': [
    'Last 15 days',
    '直近 15 日',
    '최근 15일',
  ],
  '本次启动': [
    'Current session',
    '今回の起動',
    '이번 실행',
  ],
  '警告与错误': [
    'Warnings & errors',
    '警告とエラー',
    '경고 및 오류',
  ],
  '近 15 天未记录到警告或错误日志': [
    'No warnings or errors recorded in the last 15 days',
    '直近 15 日間に警告やエラーログは記録されていません',
    '최근 15일 동안 기록된 경고 또는 오류 로그가 없습니다',
  ],
  '当前暂无运行日志记录': [
    'No runtime logs recorded yet',
    '現在、実行ログの記録はありません',
    '현재 기록된 실행 로그가 없습니다',
  ],
  '你可以随意审阅或删减日志内容。': [
    'You may freely review or trim the log contents before submitting.',
    '送信前にログの内容を自由に確認・編集できます。',
    '제출하기 전에 로그 내용을 자유롭게 검토하거나 편집할 수 있습니다.',
  ],
  '每条日志均记录本地时间戳，提交前可直接编辑；超过 15 天的历史日志文件会自动删除。': [
    'Every log entry includes a local timestamp and can be edited before submission; log files older than 15 days are deleted automatically.',
    '各ログにはローカルのタイムスタンプが記録され、送信前に直接編集できます。15 日を超えた古いログファイルは自動削除されます。',
    '모든 로그에는 로컬 타임스탬프가 기록되며 제출 전 직접 편집할 수 있습니다. 15일이 지난 이전 로그 파일은 자동으로 삭제됩니다.',
  ],
  '生成环境摘要与近 15 天时间戳运行日志，提交前可审阅或脱敏': [
    'Generates an environment summary and 15-day timestamped logs for review and redaction',
    '環境概要と直近 15 日のタイムスタンプ付きログを生成し、送信前に確認・匿名化できます',
    '환경 요약과 최근 15일 타임스탬프 실행 로그를 생성하며 제출 전 검토하거나 비식별화할 수 있습니다',
  ],
  '复制完整报告': [
    'Copy full report',
    '完全なレポートをコピー',
    '전체 보고서 복사',
  ],
  '前往 GitHub 提交': [
    'Submit on GitHub',
    'GitHub で送信',
    'GitHub에서 제출',
  ],
  '诊断报告': [
    'Diagnostic report',
    '診断レポート',
    '진단 보고서',
  ],
  '反馈': [
    'Feedback',
    'フィードバック',
    '피드백',
  ],
  'Bug': [
    'Bug',
    'バグ',
    '버그',
  ],
  '问题反馈与运行日志': [
    'Issue reporting & runtime logs',
    '問題報告と実行ログ',
    '문제 보고 및 실행 로그',
  ],
  '在“设置 → 更新与关于 → 报告问题”点击“创建问题”打开反馈弹窗，选择问题分类并填写标题与复现说明，可一键复制完整诊断报告或跳转 GitHub 提交。默认开启“隐藏个人路径”，自动将系统用户名与应用资料根目录脱敏。':
      [
    'In "Settings → Updates & about → Report an issue", click "Create issue" to open the feedback dialog, choose a category, enter a title and steps, and either copy the full diagnostic report or open GitHub. "Redact personal paths" is enabled by default to mask your OS username and app-data root.',
    '「設定 → 更新とこのアプリについて → 問題を報告」で「問題を作成」を押すと報告ダイアログが開き、分類やタイトル・再現手順を入力して完全な診断レポートのコピーや GitHub への送信が行えます。「個人パスを伏せる」が既定で有効になり、OS ユーザー名やデータフォルダーを自動的にマスクします。',
    '"설정 → 업데이트 및 정보 → 문제 보고"에서 "문제 생성"을 누르면 피드백 창이 열리며, 분류와 제목·재현 단계를 입력해 전체 진단 보고서를 복사하거나 GitHub로 이동해 제출할 수 있습니다. "개인 경로 가리기"가 기본으로 켜져 있어 시스템 사용자 이름과 앱 데이터 루트를 자동으로 가립니다.',
  ],
  '每条运行日志均记录本地毫秒级时间戳，支持按“近 15 天”“本次启动”与“警告与错误”筛选；按日保存的日志文件在满 15 天后自动删除，且不会混入个人资料备份包。':
      [
    'Every runtime log entry records a local millisecond timestamp and can be filtered by "Last 15 days", "Current session", or "Warnings & errors". Daily log files are deleted automatically after 15 days and excluded from personal backup archives.',
    '各実行ログにはミリ秒単位のローカル時刻が記録され、「直近 15 日」「今回の起動」「警告とエラー」で絞り込めます。日別ログファイルは 15 日経過後に自動削除され、個人データのバックアップには含まれません。',
    '모든 실행 로그에는 밀리초 단위의 로컬 타임스탬프가 기록되며 "최근 15일", "이번 실행", "경고 및 오류"로 필터링할 수 있습니다. 일별 로그 파일은 15일이 지나면 자동으로 삭제되며 개인 백업 파일에는 포함되지 않습니다.',
  ],
  '打开报告问题设置': [
    'Open issue reporting settings',
    '問題報告の設定を開く',
    '문제 보고 설정 열기',
  ],

  // Equalizer new presets & UX fixes
  '电子': [
    'Electronic',
    'エレクトロニック',
    '일렉트로닉',
  ],
  '原声': [
    'Acoustic',
    'アコースティック',
    '어쿠스틱',
  ],
  '通勤': [
    'Commute',
    '通勤・外出',
    '출퇴근',
  ],
  '尚未保存用户 EQ 预设': [
    'No saved user EQ presets yet',
    '保存済みのユーザー EQ プリセットはありません',
    '저장된 사용자 EQ 프리셋이 없습니다',
  ],
  '请先在上方输入新的预设名称': [
    'Enter a new preset name above first',
    '先に上で新しいプリセット名を入力してください',
    '먼저 위쪽에 새 프리셋 이름을 입력해 주세요',
  ],

  // Search history header & clear all
  '最近搜索': [
    'Recent searches',
    '最近の検索',
    '최근 검색',
  ],
  '清空': [
    'Clear',
    '消去',
    '비우기',
  ],

  // Snapshot 8 optional components (`tool` install & re-verification)
  '正在复检已安装字典…': [
    'Re-verifying installed dictionary…',
    'インストール済み辞書を再検証しています…',
    '설치된 사전을 다시 검증하는 중…',
  ],
  '正在复检并安装组件…': [
    'Installing and re-verifying component…',
    'コンポーネントをインストールして再検証しています…',
    '구성 요소를 설치하고 다시 검증하는 중…',
  ],
  '试听复用精简版 FFmpeg 音频组件，不会改写原歌曲。可自动从 GitHub 下载约 5.2 MB 组件到 tool 目录并复检，或手动安装。':
      [
    'Audio preview reuses the slimmed FFmpeg audio module without modifying source songs. Download the ~5.2 MB package from GitHub into the tool folder with automatic verification, or install manually.',
    '試聴は軽量版 FFmpeg 音声コンポーネントを利用し、元の曲ファイルを書き換えません。GitHub から約 5.2 MB のパッケージを tool フォルダーへ取得して自動再検証するか、手動で導入できます。',
    '미리 듣기는 경량 FFmpeg 오디오 구성 요소를 사용하며 원본 곡을 수정하지 않습니다. GitHub에서 약 5.2 MB 패키지를 tool 폴더에 받아 자동 재검증하거나 수동으로 설치할 수 있습니다.',
  ],
  '音频裁剪需要 FFmpeg、FFprobe 和 FFplay。可从 GitHub 下载约 5.2 MB 的精简音频组件到 tool 目录并自动复检，将遵循播放器的网络代理设置。':
      [
    'Audio trimming requires FFmpeg, FFprobe, and FFplay. Download the ~5.2 MB slimmed audio module from GitHub into the tool folder with automatic re-verification, honoring the player proxy settings.',
    '音声トリミングには FFmpeg・FFprobe・FFplay が必要です。プレーヤーのプロキシ設定に従って GitHub から約 5.2 MB の軽量音声コンポーネントを tool フォルダーへダウンロードし、自動で再検証します。',
    '오디오 자르기에는 FFmpeg, FFprobe, FFplay가 필요합니다. 플레이어의 네트워크 프록시 설정을 따라 GitHub에서 약 5.2 MB 경량 오디오 구성 요소를 tool 폴더로 다운로드하고 자동 재검증합니다.',
  ],
  '也可以从发布页或官网下载组件，将可执行文件及配套 DLL 解压到以下目录，然后点击“我已安装好”。': [
    'You can also download the component from the release page or official site, extract the executables and companion DLLs into the folder below, and click "I have installed it".',
    'リリースページや公式サイトから取得し、実行ファイルと付属 DLL を次のフォルダーへ展開してから「インストール済み」をクリックすることもできます。',
    '릴리스 페이지나 공식 사이트에서 구성 요소를 내려받아 실행 파일과 동반 DLL을 아래 폴더에 압축 해제한 뒤 "설치 완료"를 눌러도 됩니다.',
  ],
};
