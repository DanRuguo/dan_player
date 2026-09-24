const catalogNetworkProxy = <String, List<String>>{
  '无法设置联网音频代理（BASS 错误码 {0}）。': [
    'Could not configure the online audio proxy (BASS error {0}).',
    'オンライン音声のプロキシを設定できませんでした（BASS エラー {0}）。',
    '온라인 오디오 프록시를 설정할 수 없습니다(BASS 오류 {0}).'
  ],
  '无法设置联网音频超时（BASS 错误码 {0}）。': [
    'Could not configure the online audio timeout (BASS error {0}).',
    'オンライン音声のタイムアウトを設定できませんでした（BASS エラー {0}）。',
    '온라인 오디오 제한 시간을 설정할 수 없습니다(BASS 오류 {0}).'
  ],
  '网络代理': ['Network proxy', 'ネットワークプロキシ', '네트워크 프록시'],
  '网络代理模式': ['Network proxy mode', 'ネットワークプロキシのモード', '네트워크 프록시 모드'],
  '播放器的联网请求使用此设置；外部浏览器仍使用浏览器自己的网络设置。': [
    'The player uses this setting for network requests; external browsers use their own network settings.',
    'プレーヤーの通信にはこの設定を使用します。外部ブラウザーはブラウザー自身のネットワーク設定を使用します。',
    '플레이어의 네트워크 요청에 이 설정을 사용합니다. 외부 브라우저는 자체 네트워크 설정을 사용합니다.'
  ],
  '系统代理': ['System proxy', 'システムプロキシ', '시스템 프록시'],
  '直连': ['Direct connection', '直接接続', '직접 연결'],
  '自定义 HTTP 代理': ['Custom HTTP proxy', 'カスタム HTTP プロキシ', '사용자 지정 HTTP 프록시'],
  '使用 Windows 当前静态代理，未配置时直连；自动代理脚本请改用自定义 HTTP 代理。': [
    'Use the current Windows static proxy, or connect directly if none is set. For an automatic proxy script, choose a custom HTTP proxy.',
    '現在の Windows 静的プロキシを使用し、未設定なら直接接続します。自動プロキシスクリプトの場合はカスタム HTTP プロキシを選んでください。',
    '현재 Windows 정적 프록시를 사용하며 설정이 없으면 직접 연결합니다. 자동 프록시 스크립트는 사용자 지정 HTTP 프록시를 선택하세요.'
  ],
  '播放器直接连接，不经过系统或自定义代理。': [
    'Connect directly without the system or custom proxy.',
    'システムプロキシやカスタムプロキシを使わずに直接接続します。',
    '시스템 또는 사용자 지정 프록시를 거치지 않고 직접 연결합니다.'
  ],
  '填写代理主机或完整 HTTP 链接和端口，例如 127.0.0.1 与 7890。': [
    'Enter a proxy host or full HTTP URL and port, such as 127.0.0.1 and 7890.',
    'プロキシのホストまたは完全な HTTP URL とポートを入力します（例：127.0.0.1 と 7890）。',
    '프록시 호스트 또는 전체 HTTP URL과 포트를 입력하세요(예: 127.0.0.1 및 7890).'
  ],
  '代理地址或链接': ['Proxy address or URL', 'プロキシのアドレスまたは URL', '프록시 주소 또는 URL'],
  '代理端口': ['Proxy port', 'プロキシのポート', '프록시 포트'],
  '地址已包含端口时，端口输入框可留空。': [
    'Leave the port field empty if the address already includes one.',
    'アドレスにポートが含まれる場合、ポート欄は空欄にできます。',
    '주소에 포트가 포함되어 있으면 포트 입력란을 비워 둘 수 있습니다.'
  ],
  '请输入有效的 HTTP 代理地址和端口。': [
    'Enter a valid HTTP proxy address and port.',
    '有効な HTTP プロキシのアドレスとポートを入力してください。',
    '올바른 HTTP 프록시 주소와 포트를 입력하세요.'
  ],
  '测试 GitHub 连接': [
    'Test GitHub connection',
    'GitHub への接続をテスト',
    'GitHub 연결 테스트'
  ],
  '保存并应用': ['Save and apply', '保存して適用', '저장하고 적용'],
  '代理设置已应用并保存。': [
    'Proxy settings applied and saved.',
    'プロキシ設定を適用して保存しました。',
    '프록시 설정을 적용하고 저장했습니다.'
  ],
  '代理设置已在本次运行应用，但保存失败；请重试。': [
    'Proxy settings are active for this session, but could not be saved. Please retry.',
    'このセッションにはプロキシ設定を適用しましたが、保存できませんでした。再試行してください。',
    '이번 실행에는 프록시 설정이 적용되었지만 저장하지 못했습니다. 다시 시도하세요.'
  ],
  'GitHub 连接成功（HTTP {0}，{1} 毫秒）。': [
    'GitHub connected (HTTP {0}, {1} ms).',
    'GitHub に接続しました（HTTP {0}、{1} ミリ秒）。',
    'GitHub 연결 성공(HTTP {0}, {1}밀리초).'
  ],
  '已连接 GitHub，但接口返回 HTTP {0}（{1} 毫秒）。': [
    'Connected to GitHub, but its API returned HTTP {0} ({1} ms).',
    'GitHub に接続しましたが、API は HTTP {0} を返しました（{1} ミリ秒）。',
    'GitHub에 연결했지만 API에서 HTTP {0}을(를) 반환했습니다({1}밀리초).'
  ],
  'GitHub 连接失败（HTTP {0}，{1} 毫秒）。': [
    'GitHub connection failed (HTTP {0}, {1} ms).',
    'GitHub への接続に失敗しました（HTTP {0}、{1} ミリ秒）。',
    'GitHub 연결 실패(HTTP {0}, {1}밀리초).'
  ],
  'GitHub 连接失败或超时（{0} 毫秒）。': [
    'GitHub connection failed or timed out ({0} ms).',
    'GitHub への接続に失敗したかタイムアウトしました（{0} ミリ秒）。',
    'GitHub 연결에 실패했거나 시간이 초과되었습니다({0}밀리초).'
  ],
  'GitHub 连接测试失败，请检查代理设置后重试。': [
    'GitHub connection test failed. Check the proxy settings and retry.',
    'GitHub への接続テストに失敗しました。プロキシ設定を確認して再試行してください。',
    'GitHub 연결 테스트에 실패했습니다. 프록시 설정을 확인한 뒤 다시 시도하세요.'
  ],
  '自动代理脚本暂不能用于应用内 HTTP 请求；请使用自定义代理。原生在线播放和 FFmpeg 可继续跟随 Windows 代理。': [
    'Automatic proxy scripts are not yet supported for in-app HTTP requests. Use a custom proxy. Native online playback and FFmpeg can still use the Windows proxy.',
    '自動プロキシスクリプトはアプリ内の HTTP 通信にまだ対応していません。カスタムプロキシを使用してください。ネイティブのオンライン再生と FFmpeg は引き続き Windows のプロキシを使用できます。',
    '자동 프록시 스크립트는 앱 내 HTTP 요청에서 아직 지원되지 않습니다. 사용자 지정 프록시를 사용하세요. 네이티브 온라인 재생과 FFmpeg는 계속 Windows 프록시를 사용할 수 있습니다.'
  ],
};
