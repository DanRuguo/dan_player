const Map<String, List<String>> catalogUpdates = {
  '正在验证安装器…': ['Verifying installer…', 'インストーラーを検証中…', '설치 프로그램 검증 중…'],
  '正在退出…': ['Exiting…', '終了中…', '종료 중…'],
  '更新服务器返回 HTTP {0}。': [
    'The update server returned HTTP {0}.',
    '更新サーバーが HTTP {0} を返しました。',
    '업데이트 서버가 HTTP {0}을 반환했습니다.'
  ],
  '校验服务器返回 HTTP {0}。': [
    'The checksum server returned HTTP {0}.',
    '検証サーバーが HTTP {0} を返しました。',
    '검증 서버가 HTTP {0}을 반환했습니다.'
  ],
  '重试退出': ['Retry exit', '終了を再試行', '종료 다시 시도'],
  '下载文件未通过再次校验，请重新下载。': [
    'The downloaded file failed revalidation. Please download it again.',
    'ダウンロードしたファイルの再検証に失敗しました。再ダウンロードしてください。',
    '다운로드한 파일의 재검증에 실패했습니다. 다시 다운로드하세요.'
  ],
  '重新下载': ['Download again', '再ダウンロード', '다시 다운로드'],
  '安装器已启动，但播放器未能完成退出。请手动退出播放器以继续更新。': [
    'The installer started, but the player could not finish exiting. Quit the player manually to continue.',
    'インストーラーは起動しましたが、プレーヤーを終了できませんでした。手動で終了して更新を続行してください。',
    '설치 프로그램이 시작되었지만 플레이어가 종료되지 않았습니다. 계속하려면 플레이어를 직접 종료하세요.'
  ],
  'Windows 未确认安装器的可信签名或发布者一致性，已阻止自动安装。播放器保持打开；可查看安装包后自行决定是否手动安装。不会自动修改系统信任设置。':
      [
    'Windows could not confirm a trusted signature or matching publisher. Automatic installation was blocked and the player remains open. Inspect the package before deciding whether to install manually. System trust settings will not be changed automatically.',
    'Windows が信頼できる署名または公開者の一致を確認できないため、自動インストールをブロックしました。プレーヤーは開いたままです。パッケージを確認してから手動でインストールするか判断してください。システムの信頼設定は自動変更しません。',
    'Windows에서 신뢰할 수 있는 서명 또는 일치하는 게시자를 확인하지 못해 자동 설치를 차단했습니다. 플레이어는 열린 상태입니다. 패키지를 확인한 후 직접 설치할지 결정하세요. 시스템 신뢰 설정은 자동으로 변경하지 않습니다.'
  ],
  '安装包内容或版本校验失败，已阻止自动安装。请重新下载，不要运行此文件。': [
    'Package content or version verification failed. Automatic installation was blocked. Download it again; do not run this file.',
    'パッケージの内容またはバージョンの検証に失敗したため、自動インストールをブロックしました。このファイルは実行せず、再ダウンロードしてください。',
    '패키지 내용 또는 버전 검증에 실패하여 자동 설치를 차단했습니다. 이 파일을 실행하지 말고 다시 다운로드하세요.'
  ],
  '安装器未及时确认已准备好，播放器不会退出。请检查安装器窗口，或关闭安装器后重试。': [
    'The installer did not confirm readiness in time, so the player will stay open. Check the installer window, or close it and retry.',
    'インストーラーの準備完了を時間内に確認できなかったため、プレーヤーは終了しません。インストーラーのウィンドウを確認するか、閉じてから再試行してください。',
    '설치 프로그램이 준비 완료를 제시간에 확인하지 않아 플레이어를 종료하지 않습니다. 설치 프로그램 창을 확인하거나 닫은 후 다시 시도하세요.'
  ],
  '所选通道暂无新版本': [
    'No newer version in the selected channel',
    '選択したチャンネルに新しいバージョンはありません',
    '선택한 채널에 새 버전이 없습니다'
  ],
  '发现预览版 {0}': [
    'Preview {0} is available',
    'プレビュー版 {0} が利用できます',
    '미리 보기 버전 {0} 사용 가능'
  ],
  '自动检查更新（每天最多一次）': [
    'Check for updates automatically (at most once a day)',
    '更新を自動確認（1日最大1回）',
    '자동 업데이트 확인 (하루 최대 한 번)'
  ],
  '接收预览版更新': ['Receive preview updates', 'プレビュー版の更新を受け取る', '미리 보기 업데이트 받기'],
  '预览版可能不稳定；仅提醒，每次下载都需确认。': [
    'Previews may be unstable. Notifications only; every download requires confirmation.',
    'プレビュー版は不安定な場合があります。通知のみ行い、ダウンロードは毎回確認します。',
    '미리 보기 버전은 불안정할 수 있습니다. 알림만 제공하며 다운로드할 때마다 확인이 필요합니다.'
  ],
  '更新偏好保存失败，请重试': [
    'Could not save update preferences. Please retry.',
    '更新設定を保存できませんでした。再試行してください。',
    '업데이트 설정을 저장하지 못했습니다. 다시 시도하세요.'
  ],
  '下载预览更新？': [
    'Download this preview update?',
    'プレビュー版の更新をダウンロードしますか？',
    '미리 보기 업데이트를 다운로드할까요?'
  ],
  '下载更新？': ['Download this update?', '更新をダウンロードしますか？', '업데이트를 다운로드할까요?'],
  '将下载预览版 {0} 的完整安装器。预览版可能存在问题；下载不会立即安装或中断播放。': [
    'The full installer for preview {0} will be downloaded. Previews may contain issues. Downloading will not install it or interrupt playback.',
    'プレビュー版 {0} の完全なインストーラーをダウンロードします。不具合が含まれる場合があります。ダウンロードだけではインストールや再生の中断は行いません。',
    '미리 보기 {0}의 전체 설치 프로그램을 다운로드합니다. 문제가 있을 수 있으며, 다운로드만으로 설치하거나 재생을 중단하지 않습니다.'
  ],
  '将下载稳定版 {0} 的完整安装器。下载不会立即安装或中断播放。': [
    'The full installer for stable version {0} will be downloaded. Downloading will not install it or interrupt playback.',
    '安定版 {0} の完全なインストーラーをダウンロードします。ダウンロードだけではインストールや再生の中断は行いません。',
    '안정 버전 {0}의 전체 설치 프로그램을 다운로드합니다. 다운로드만으로 설치하거나 재생을 중단하지 않습니다.'
  ],
  '确认下载': ['Confirm download', 'ダウンロードを確認', '다운로드 확인'],
  '重启并更新？': ['Restart and update?', '再起動して更新しますか？', '다시 시작하고 업데이트할까요?'],
  '重启并更新': ['Restart and update', '再起動して更新', '다시 시작 및 업데이트'],
  '播放器将保存当前设置与播放状态、停止播放并退出。安装器会等待退出后在原位置更新并重新打开播放器；音乐和歌单会保留。': [
    'The player will save its settings and playback state, stop playback, and exit. The installer will wait for it to close, update the existing installation, and reopen the player. Music and playlists will be kept.',
    '設定と再生状態を保存して再生を停止し、プレーヤーを終了します。インストーラーは終了を待って現在の場所に更新を適用し、プレーヤーを再起動します。音楽とプレイリストは保持されます。',
    '현재 설정과 재생 상태를 저장하고 재생을 중단한 뒤 종료합니다. 설치 프로그램이 종료를 기다린 후 기존 위치에 업데이트하고 플레이어를 다시 엽니다. 음악과 재생목록은 유지됩니다.'
  ],
  '无法启动更新。播放器仍保持打开；请重试或在资源管理器中手动运行安装器。': [
    'Could not start the update. The player remains open. Retry or run the installer manually from File Explorer.',
    '更新を開始できませんでした。プレーヤーは開いたままです。再試行するか、エクスプローラーからインストーラーを手動で実行してください。',
    '업데이트를 시작하지 못했습니다. 플레이어는 열린 상태입니다. 다시 시도하거나 파일 탐색기에서 설치 프로그램을 직접 실행하세요.'
  ],
  '预览版 {0}{1}': ['Preview {0}{1}', 'プレビュー版 {0}{1}', '미리 보기 {0}{1}'],
  '这是预览版，可能存在问题；请选择是否下载。': [
    'This is a preview and may contain issues. Choose whether to download it.',
    'これはプレビュー版のため、不具合が含まれる場合があります。ダウンロードするか選択してください。',
    '미리 보기 버전에는 문제가 있을 수 있습니다. 다운로드할지 선택하세요.'
  ],
  '下载完成，SHA-256 校验通过。可选择重启并更新，或稍后手动安装。': [
    'Download complete; SHA-256 verified. Restart and update, or install manually later.',
    'ダウンロードが完了し、SHA-256 検証に成功しました。再起動して更新するか、後で手動でインストールできます。',
    '다운로드 완료, SHA-256 검증 통과. 다시 시작하여 업데이트하거나 나중에 직접 설치할 수 있습니다.'
  ],
  '当前版本号格式无效，无法安全比较更新。': [
    'The current version is invalid; updates cannot be compared safely.',
    '現在のバージョン番号が無効なため、更新を安全に比較できません。',
    '현재 버전 번호가 유효하지 않아 업데이트를 안전하게 비교할 수 없습니다.'
  ],
  '检查更新超时，请检查网络连接后重试。': [
    'Update check timed out. Check your connection and retry.',
    '更新の確認がタイムアウトしました。接続を確認して再試行してください。',
    '업데이트 확인 시간이 초과되었습니다. 연결을 확인하고 다시 시도하세요.'
  ],
  '无法连接 GitHub，请检查网络连接后重试。': [
    'Could not connect to GitHub. Check your connection and retry.',
    'GitHub に接続できません。接続を確認して再試行してください。',
    'GitHub에 연결할 수 없습니다. 연결을 확인하고 다시 시도하세요.'
  ],
  'GitHub 更新服务暂时不可用，请稍后重试。': [
    'GitHub updates are temporarily unavailable. Please try again later.',
    'GitHub の更新サービスを利用できません。後で再試行してください。',
    'GitHub 업데이트 서비스를 일시적으로 사용할 수 없습니다. 나중에 다시 시도하세요.'
  ],
  '此版本没有可识别的 Windows 安装包，请前往发布页获取。': [
    'No recognized Windows installer is attached. Visit the release page.',
    '認識できる Windows インストーラーがありません。リリースページを開いてください。',
    '인식 가능한 Windows 설치 프로그램이 없습니다. 릴리스 페이지를 방문하세요.'
  ],
  '更新包地址不是受信任的 GitHub HTTPS 地址。': [
    'The update URL is not a trusted GitHub HTTPS address.',
    '更新パッケージの URL が信頼できる GitHub HTTPS アドレスではありません。',
    '업데이트 주소가 신뢰할 수 있는 GitHub HTTPS 주소가 아닙니다.'
  ],
  '更新包文件名无效。': [
    'The update filename is invalid.',
    '更新パッケージのファイル名が無効です。',
    '업데이트 파일 이름이 유효하지 않습니다.'
  ],
  '校验文件地址无效，已停止更新。': [
    'The checksum URL is invalid. The update was stopped.',
    '検証ファイルの URL が無効なため、更新を中止しました。',
    '검증 파일 주소가 유효하지 않아 업데이트를 중단했습니다.'
  ],
  '发布者提供的 SHA-256 校验文件无法识别，已停止更新。': [
    'The publisher’s SHA-256 file is not recognized. The update was stopped.',
    '公開者の SHA-256 ファイルを認識できないため、更新を中止しました。',
    '게시자의 SHA-256 파일을 인식할 수 없어 업데이트를 중단했습니다.'
  ],
  '更新包 SHA-256 校验失败，文件可能不完整或已被篡改。': [
    'SHA-256 verification failed. The update may be incomplete or altered.',
    'SHA-256 検証に失敗しました。ファイルが不完全か、改変されている可能性があります。',
    'SHA-256 검증에 실패했습니다. 파일이 불완전하거나 변조되었을 수 있습니다.'
  ],
  '已取消下载。': ['Download cancelled.', 'ダウンロードをキャンセルしました。', '다운로드가 취소되었습니다.'],
  '下载更新超时，请检查网络后重试。': [
    'Update download timed out. Check your connection and retry.',
    '更新のダウンロードがタイムアウトしました。接続を確認して再試行してください。',
    '업데이트 다운로드 시간이 초과되었습니다. 연결을 확인하고 다시 시도하세요.'
  ],
  '下载更新时网络连接中断，请重试。': [
    'The connection was interrupted during download. Please retry.',
    'ダウンロード中に接続が切れました。再試行してください。',
    '다운로드 중 연결이 끊겼습니다. 다시 시도하세요.'
  ],
  '更新包下载失败，请稍后重试。': [
    'The update download failed. Please retry later.',
    '更新パッケージをダウンロードできませんでした。後で再試行してください。',
    '업데이트 다운로드에 실패했습니다. 나중에 다시 시도하세요.'
  ],
  '更新服务器返回了空文件，已停止更新。': [
    'The server returned an empty file. The update was stopped.',
    'サーバーが空のファイルを返したため、更新を中止しました。',
    '서버에서 빈 파일을 반환하여 업데이트를 중단했습니다.'
  ],
  '更新包大小与发布信息不一致，文件可能未下载完整。': [
    'The update size does not match the release. The download may be incomplete.',
    '更新パッケージのサイズがリリース情報と異なります。ダウンロードが不完全な可能性があります。',
    '업데이트 크기가 릴리스 정보와 다릅니다. 다운로드가 완료되지 않았을 수 있습니다.'
  ],
  'SHA-256 校验文件异常过大。': [
    'The SHA-256 file is unexpectedly large.',
    'SHA-256 ファイルが異常に大きいため処理できません。',
    'SHA-256 파일이 비정상적으로 큽니다.'
  ],
  '更新服务器尝试使用非安全 HTTPS 地址，已停止下载。': [
    'The update server requested an unsafe address. Download stopped.',
    '更新サーバーが安全でないアドレスを要求したため、ダウンロードを中止しました。',
    '업데이트 서버가 안전하지 않은 주소를 요청하여 다운로드를 중단했습니다.'
  ],
  '更新服务器返回了无效的重定向。': [
    'The update server returned an invalid redirect.',
    '更新サーバーからのリダイレクトが無効です。',
    '업데이트 서버가 잘못된 리디렉션을 반환했습니다.'
  ],
  '更新服务器重定向次数过多，已停止下载。': [
    'Too many update server redirects. Download stopped.',
    '更新サーバーのリダイレクトが多すぎるため、ダウンロードを中止しました。',
    '업데이트 서버의 리디렉션이 너무 많아 다운로드를 중단했습니다.'
  ],
};
