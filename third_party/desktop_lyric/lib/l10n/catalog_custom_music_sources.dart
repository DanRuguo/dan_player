/// Multi-source settings. Order: English, Japanese, Korean.
const Map<String, List<String>> catalogCustomMusicSources = {
  '测试未完成，请检查配置后重试': [
    'The test did not finish. Check the configuration and retry.',
    'テストを完了できませんでした。設定を確認して再試行してください。',
    '테스트를 완료하지 못했습니다. 설정을 확인한 후 다시 시도하세요.'
  ],
  '请填写歌曲名': ['Enter a track title', '曲名を入力してください', '곡 제목을 입력하세요'],
  '测试歌源能力': ['Test source capabilities', '音源の能力をテスト', '음원 기능 테스트'],
  '歌曲名（必填）': ['Track title (required)', '曲名（必須）', '곡 제목(필수)'],
  '艺术家（可选）': ['Artist (optional)', 'アーティスト（任意）', '아티스트(선택 사항)'],
  '专辑（可选）': ['Album (optional)', 'アルバム（任意）', '앨범(선택 사항)'],
  '向此 API 发送查询信息与匹配歌曲标识，仅读取少量响应；不实际播放、不下载整首歌曲。': [
    'Sends the query and matched track IDs to this API and reads small response samples; it does not play or download complete tracks.',
    '検索情報と一致した曲の ID をこの API に送信し、応答の一部だけを読み取ります。実際の再生や曲全体のダウンロードは行いません。',
    '이 API에 검색 정보와 일치하는 곡 ID를 전송하고 응답 일부만 읽습니다. 실제 재생이나 전체 곡 다운로드는 하지 않습니다.'
  ],
  '未找到样本不代表永久不支持；应用结果只补充成功项，不移除已有能力。': [
    'No sample does not mean permanently unsupported. Applying results adds successful capabilities without removing existing ones.',
    'サンプルが見つからなくても永続的な非対応を意味しません。結果の適用では成功した能力だけを追加し、既存の能力は削除しません。',
    '샘플이 없다고 영구적으로 지원하지 않는 것은 아닙니다. 결과를 적용하면 성공한 기능만 추가되며 기존 기능은 제거되지 않습니다.'
  ],
  '等待测试': ['Waiting', '待機中', '대기 중'],
  '尚未测试': ['Not tested', '未テスト', '테스트 전'],
  '本轮耗时 {0} 秒': ['Elapsed: {0} seconds', '所要時間：{0} 秒', '소요 시간: {0}초'],
  '测试样本：{0}': ['Test sample: {0}', 'テストサンプル：{0}', '테스트 샘플: {0}'],
  '停止测试': ['Stop test', 'テストを停止', '테스트 중지'],
  '开始测试': ['Start test', 'テストを開始', '테스트 시작'],
  '应用已测得能力': ['Apply detected capabilities', '検出した能力を適用', '확인된 기능 적용'],
  '未找到样本': ['No sample', 'サンプルなし', '샘플 없음'],
  '未支持': ['Unsupported', '非対応', '미지원'],
  '需登录': ['Login needed', 'ログインが必要', '로그인 필요'],
  '超时': ['Timed out', 'タイムアウト', '시간 초과'],
  '失败': ['Failed', '失敗', '실패'],
  '已取消': ['Cancelled', 'キャンセル済み', '취소됨'],
  '当前协议或配置未提供此项接口': [
    'The current protocol or configuration does not provide this endpoint',
    '現在のプロトコルまたは設定では、この接続先が提供されていません',
    '현재 프로토콜 또는 설정에서 이 인터페이스를 제공하지 않습니다'
  ],
  '当前协议未提供此项接口': [
    'The current protocol does not provide this endpoint',
    '現在のプロトコルでは、この接続先が提供されていません',
    '현재 프로토콜에서 이 인터페이스를 제공하지 않습니다'
  ],
  '来源要求登录或有效凭据': [
    'The source requires login or valid credentials',
    '音源にはログインまたは有効な認証情報が必要です',
    '음원에 로그인 또는 유효한 인증 정보가 필요합니다'
  ],
  '未找到可用于此项测试的歌曲样本': [
    'No track sample was found for this test',
    'このテストに使える曲のサンプルが見つかりませんでした',
    '이 테스트에 사용할 곡 샘플을 찾지 못했습니다'
  ],
  '已取得歌曲搜索结果': [
    'Track search results received',
    '曲の検索結果を取得しました',
    '곡 검색 결과를 받았습니다'
  ],
  '样本包含歌曲信息': [
    'The sample contains track details',
    'サンプルに曲情報が含まれています',
    '샘플에 곡 정보가 포함되어 있습니다'
  ],
  '此样本未提供额外歌曲信息': [
    'This sample has no additional track details',
    'このサンプルには追加の曲情報がありません',
    '이 샘플에는 추가 곡 정보가 없습니다'
  ],
  '已验证封面图片响应': [
    'Cover image response verified',
    'カバー画像の応答を確認しました',
    '표지 이미지 응답을 확인했습니다'
  ],
  '已取得歌词内容': ['Lyric content received', '歌詞を取得しました', '가사를 받았습니다'],
  '此样本没有可用歌词': [
    'This sample has no usable lyrics',
    'このサンプルには利用可能な歌詞がありません',
    '이 샘플에는 사용할 수 있는 가사가 없습니다'
  ],
  '此样本没有公开评论': [
    'This sample has no public comments',
    'このサンプルには公開コメントがありません',
    '이 샘플에는 공개 댓글이 없습니다'
  ],
  '已取得公开评论': ['Public comments received', '公開コメントを取得しました', '공개 댓글을 받았습니다'],
  '已验证公开下载响应，未下载整首歌曲': [
    'Public download response verified; the full track was not downloaded',
    '公開ダウンロードの応答を確認しました。曲全体はダウンロードしていません',
    '공개 다운로드 응답을 확인했으며 전체 곡은 다운로드하지 않았습니다'
  ],
  '已验证音频响应，未实际播放': [
    'Audio response verified without playback',
    '再生せずに音声の応答を確認しました',
    '실제 재생 없이 오디오 응답을 확인했습니다'
  ],
  '来源明确禁止下载此样本': [
    'The source explicitly blocks downloading this sample',
    '音源はこのサンプルのダウンロードを明示的に禁止しています',
    '음원에서 이 샘플의 다운로드를 명시적으로 금지했습니다'
  ],
  '此样本未开放播放': [
    'Playback is not available for this sample',
    'このサンプルは再生できません',
    '이 샘플은 재생할 수 없습니다'
  ],
  '请求超时，可稍后重试': [
    'The request timed out; try again later',
    'リクエストがタイムアウトしました。しばらくしてから再試行してください',
    '요청 시간이 초과되었습니다. 잠시 후 다시 시도하세요'
  ],
  '响应无效或连接失败，可检查配置后重试': [
    'Invalid response or connection failure; check the configuration and retry',
    '応答が無効か接続に失敗しました。設定を確認して再試行してください',
    '응답이 잘못되었거나 연결에 실패했습니다. 설정을 확인한 후 다시 시도하세요'
  ],
  '补充歌曲信息失败，可重选候选后重试。': [
    'Could not load additional track details. Select a candidate again and retry.',
    '曲の追加情報を取得できませんでした。候補を選び直して再試行してください。',
    '추가 곡 정보를 불러오지 못했습니다. 후보를 다시 선택한 후 재시도하세요.'
  ],
  '读取歌曲信息…': ['Loading track details…', '曲情報を読み込み中…', '곡 정보 불러오는 중…'],
  '该自定义歌源当前未提供所需能力': [
    'This custom source does not currently provide the required capability',
    'このカスタム音源は現在、必要な能力を提供していません',
    '이 사용자 지정 음원은 현재 필요한 기능을 제공하지 않습니다'
  ],
  '对应的自定义歌源已被移除': [
    'The corresponding custom source has been removed',
    '対応するカスタム音源は削除されました',
    '해당 사용자 지정 음원이 삭제되었습니다'
  ],
  '平台直连与公开 API': [
    'Direct platform sources and public APIs',
    '直接接続と公開 API',
    '플랫폼 직접 연결 및 공개 API'
  ],
  '名称、接口和能力由播放器维护。平台域名不代表官方开放接口、下载授权或长期可用承诺。': [
    'Names, endpoints, and capabilities are maintained by the player. Platform domains do not imply an official public API, download authorization, or guaranteed availability.',
    '名前、接続先、能力はプレーヤーが管理します。プラットフォームのドメインは公式公開 API、ダウンロード許可、継続的な利用可能性を意味しません。',
    '이름, 인터페이스 및 기능은 플레이어에서 관리합니다. 플랫폼 도메인이 공식 공개 API, 다운로드 허가 또는 지속적인 제공을 뜻하지는 않습니다.'
  ],
  '按标注能力启用联网请求。关闭不会删除收藏、歌单或队列；已有平台歌曲的播放不受搜索开关影响。': [
    'Enable online requests for the listed capabilities. Disabling does not delete favorites, playlists, or the queue; search switches do not interrupt saved platform tracks.',
    '表示された能力のオンラインリクエストを有効にします。無効にしてもお気に入り、プレイリスト、キューは削除されず、検索スイッチは保存済みの曲の再生に影響しません。',
    '표시된 기능의 온라인 요청을 활성화합니다. 꺼도 즐겨찾기, 재생목록 또는 대기열은 삭제되지 않으며 검색 스위치는 저장된 플랫폼 곡의 재생에 영향을 주지 않습니다.'
  ],
  '此类来源均已停用': [
    'All sources in this group are disabled',
    'このグループの音源はすべて無効です',
    '이 그룹의 음원이 모두 비활성화되었습니다'
  ],
  '已启用 {0} 个此类来源；各项按已标注能力参与联网请求。': [
    '{0} sources enabled in this group; each is used for its listed capabilities.',
    'このグループでは {0} 件の音源が有効です。それぞれ表示された能力で利用します。',
    '이 그룹의 음원 {0}개가 활성화되었습니다. 각 음원은 표시된 기능에 사용됩니다.'
  ],
  '参与歌词匹配': ['Used for lyric matching', '歌詞の照合に使用', '가사 검색에 사용'],
  '不参与歌词匹配': ['Not used for lyric matching', '歌詞の照合に使用しない', '가사 검색에 사용하지 않음'],
  '通过 LRCLIB 公开 API 匹配歌词；不提供歌曲播放或下载。': [
    'Matches lyrics through the LRCLIB public API; it does not provide track playback or downloads.',
    'LRCLIB の公開 API で歌詞を照合します。曲の再生やダウンロードは提供しません。',
    'LRCLIB 공개 API로 가사를 검색하며 곡 재생이나 다운로드는 제공하지 않습니다.'
  ],
  '音乐服务要求登录或拒绝访问此歌曲': [
    'The music service requires login or denied access to this track',
    '音楽サービスでログインが必要か、この曲へのアクセスが拒否されました',
    '음악 서비스에서 로그인이 필요하거나 이 곡에 대한 접근을 거부했습니다'
  ],
  '平台直连源': ['Direct platform sources', 'プラットフォーム直接接続', '플랫폼 직접 연결 음원'],
  '未启用平台直连源': [
    'No direct platform sources enabled',
    '直接接続の音源は有効になっていません',
    '활성화된 플랫폼 직접 연결 음원이 없습니다'
  ],
  '已启用 {0} 个平台直连源；新搜索会同时查询已启用的来源。': [
    '{0} direct platform sources enabled; new searches query all enabled sources.',
    '直接接続の音源が {0} 件有効です。新しい検索では有効な音源を同時に検索します。',
    '플랫폼 직접 연결 음원 {0}개가 활성화되었습니다. 새 검색은 활성화된 모든 음원을 조회합니다.'
  ],
  '通过平台域名接口连接；不代表官方开放接口、授权或长期可用承诺。名称、接口和能力由播放器维护。': [
    'Connects through platform-domain endpoints; this does not imply an official public API, authorization, or guaranteed availability. Names, endpoints, and capabilities are maintained by the player.',
    'プラットフォームのドメインへ直接接続します。公式公開 API、利用許諾、継続的な利用可能性を意味しません。名前、接続先、能力はプレーヤーが管理します。',
    '플랫폼 도메인의 인터페이스로 연결합니다. 공식 공개 API, 이용 허가 또는 지속적인 제공을 뜻하지 않습니다. 이름, 인터페이스 및 기능은 플레이어에서 관리합니다.'
  ],
  '接口域名（只读）：{0}': [
    'Endpoint domains (read-only): {0}',
    '接続先ドメイン（読み取り専用）：{0}',
    '인터페이스 도메인(읽기 전용): {0}'
  ],
  '下载按接口实际返回执行，需登录或受限时会提示。': [
    'Downloads follow the endpoint response; login requirements or restrictions are shown when encountered.',
    'ダウンロードは接続先の応答に従います。ログインが必要な場合や制限がある場合は通知します。',
    '다운로드는 인터페이스의 실제 응답에 따릅니다. 로그인이 필요하거나 제한이 있으면 안내합니다.'
  ],
  '歌词候选与歌曲搜索分开匹配；酷狗歌曲搜索、播放和下载可通过第三方源预设配置。': [
    'Lyric candidates are matched separately from track searches. Kugou search, playback, and downloads can be configured through its third-party preset.',
    '歌詞候補と曲検索は別々に照合します。酷狗の曲検索、再生、ダウンロードはサードパーティー音源のプリセットで設定できます。',
    '가사 후보와 곡 검색은 별도로 검색합니다. 쿠거우 곡 검색, 재생 및 다운로드는 타사 음원 프리셋에서 설정할 수 있습니다.'
  ],
  '第三方源': ['Third-party sources', 'サードパーティー音源', '타사 음원'],
  '内置预设和自行添加的服务都可编辑、启用、停用或删除。搜索与播放解析分开进行。': [
    'Built-in presets and your own services can all be edited, enabled, disabled, or deleted. Search and playback resolution are separate.',
    '内蔵プリセットと追加したサービスは、いずれも編集、有効化、無効化、削除できます。検索と再生アドレスの解決は別々に行います。',
    '내장 프리셋과 직접 추가한 서비스 모두 편집, 활성화, 비활성화 및 삭제할 수 있습니다. 검색과 재생 주소 확인은 별도로 진행합니다.'
  ],
  '能力以接口实际返回为准；需要登录或受限时会提示，不绕过登录、付费或 DRM。': [
    'Capabilities depend on actual endpoint responses. Login requirements or restrictions are reported; login, payment, and DRM are not bypassed.',
    '能力は接続先の実際の応答に従います。ログインや利用制限がある場合は通知し、ログイン、支払い、DRM は回避しません。',
    '기능은 인터페이스의 실제 응답에 따릅니다. 로그인 요구나 제한은 안내하며 로그인, 결제 또는 DRM을 우회하지 않습니다.'
  ],
  '添加内置预设': ['Add built-in preset', '内蔵プリセットを追加', '내장 프리셋 추가'],
  '预设添加后可自由编辑；不会覆盖现有的同名或同 ID 配置。': [
    'Presets are editable after adding and do not overwrite existing configurations with the same name or ID.',
    '追加したプリセットは自由に編集できます。同じ名前や ID の既存設定は上書きしません。',
    '추가한 프리셋은 자유롭게 편집할 수 있으며 같은 이름이나 ID의 기존 설정을 덮어쓰지 않습니다.'
  ],
  '可恢复内置预设，或添加歌词 API、通用协议和你自行部署的服务。': [
    'Restore a built-in preset, or add a lyric API, a general provider, or a service you host.',
    '内蔵プリセットを復元するか、歌詞 API、汎用プロトコル、自分で運用するサービスを追加できます。',
    '내장 프리셋을 복원하거나 가사 API, 범용 프로토콜 및 직접 배포한 서비스를 추가할 수 있습니다.'
  ],
  '歌词 API': ['Lyric API', '歌詞 API', '가사 API'],
  '酷狗接口': ['Kugou endpoints', '酷狗インターフェース', '쿠거우 인터페이스'],
  '歌词接口：接收歌曲信息并返回歌词；可更换协议以配置其他能力。': [
    'Lyric endpoint: accepts track information and returns lyrics. Change the protocol to configure other capabilities.',
    '歌詞インターフェース：曲情報を受け取り、歌詞を返します。その他の能力を設定するにはプロトコルを変更してください。',
    '가사 인터페이스는 곡 정보를 받아 가사를 반환합니다. 다른 기능을 설정하려면 프로토콜을 변경하세요.'
  ],
  '自托管兼容接口：能力按服务实际返回执行。': [
    'Self-hosted compatible interface; capabilities follow the service responses.',
    'セルフホスト互換インターフェースです。能力はサービスの実際の応答に従います。',
    '직접 호스팅하는 호환 인터페이스이며 기능은 서비스의 실제 응답에 따릅니다.'
  ],
  '酷狗兼容接口：可分别配置搜索、歌曲信息、封面、歌词、播放和下载地址。': [
    'Kugou-compatible endpoints: configure search, track details, covers, lyrics, playback, and download URLs separately.',
    '酷狗互換インターフェース：検索、曲情報、カバー、歌詞、再生、ダウンロードの接続先を個別に設定できます。',
    '쿠거우 호환 인터페이스입니다. 검색, 곡 정보, 표지, 가사, 재생 및 다운로드 주소를 따로 설정할 수 있습니다.'
  ],
  '歌曲信息和封面留空时使用搜索结果；封面地址应返回图片。': [
    'Blank track-detail and cover endpoints use the search results; a cover endpoint should return an image.',
    '曲情報とカバーの接続先が空欄の場合は検索結果を使います。カバーの接続先は画像を返す必要があります。',
    '곡 정보와 표지 주소를 비워 두면 검색 결과를 사용합니다. 표지 주소는 이미지를 반환해야 합니다.'
  ],
  '独立接口地址（可选）': [
    'Separate endpoint URLs (optional)',
    '個別の接続先 URL（任意）',
    '개별 인터페이스 주소(선택 사항)'
  ],
  '单独填写的地址优先使用；相对路径以服务地址为起点。': [
    'Explicit endpoint URLs take priority; relative paths start from the service URL.',
    '個別に指定した接続先を優先します。相対パスはサービス URL を基準にします。',
    '따로 입력한 주소를 우선 사용하며 상대 경로는 서비스 URL을 기준으로 합니다.'
  ],
  '接口地址无效，请使用 http(s) 地址或相对路径。': [
    'Invalid endpoint URL. Use an HTTP(S) URL or a relative path.',
    '接続先 URL が無効です。HTTP(S) URL または相対パスを指定してください。',
    '인터페이스 주소가 올바르지 않습니다. HTTP(S) 주소 또는 상대 경로를 사용하세요.'
  ],
  '内置歌源': ['Built-in sources', '内蔵音源', '내장 음원'],
  '未启用内置歌源': [
    'No built-in sources enabled',
    '内蔵音源は有効になっていません',
    '활성화된 내장 음원이 없습니다'
  ],
  '歌词候选': ['Lyric candidates', '歌詞候補', '가사 후보'],
  '匹配歌词时会按候选结果供你选择；歌词来源不等于完整歌曲播放源。': [
    'When matching lyrics, you can choose from the candidates; a lyric source is not necessarily a full playback source.',
    '歌詞の照合時に候補から選択できます。歌詞ソースは完全な再生音源とは限りません。',
    '가사를 찾을 때 후보 중에서 선택할 수 있습니다. 가사 소스가 완전한 재생 음원을 뜻하지는 않습니다.'
  ],
  '酷狗音乐目前仅作为歌词候选；完整播放与下载不会通过不稳定的公开接口直接内置。': [
    'Kugou is currently a lyric candidate only; full playback and downloads are not built in through unstable public endpoints.',
    '酷狗音楽は現在、歌詞候補としてのみ利用します。不安定な公開エンドポイントによる完全な再生やダウンロードは内蔵しません。',
    '쿠거우 음악은 현재 가사 후보로만 사용합니다. 불안정한 공개 엔드포인트를 통한 전체 재생과 다운로드는 내장하지 않습니다.'
  ],
  '自定义歌源 API': ['Custom source APIs', 'カスタム音源 API', '사용자 지정 음원 API'],
  '自定义歌源': ['Custom source', 'カスタム音源', '사용자 지정 음원'],
  '可同时保留多个服务；搜索只返回候选，播放时再解析地址。': [
    'Keep multiple services at once; search returns candidates and playback URLs are resolved only when needed.',
    '複数のサービスを同時に保持できます。検索は候補のみを返し、再生時にアドレスを解決します。',
    '여러 서비스를 동시에 보관할 수 있습니다. 검색은 후보만 반환하고 재생할 때 주소를 확인합니다.'
  ],
  '能力声明不代表永久可用或获得下载授权。不会绕过登录、付费或 DRM；搜索信息会发送到已启用的服务。': [
    'Declared capabilities do not guarantee permanent availability or download permission. Login, payment and DRM are not bypassed; search details are sent to enabled services.',
    '能力の宣言は永続的な利用やダウンロード許可を保証しません。ログイン、支払い、DRM を回避せず、検索情報は有効なサービスへ送信されます。',
    '기능 표시는 영구 사용이나 다운로드 권한을 보장하지 않습니다. 로그인, 결제 또는 DRM을 우회하지 않으며 검색 정보는 활성화된 서비스로 전송됩니다.'
  ],
  '能力声明不代表永久可用或获得下载授权。不会绕过登录、付费或 DRM；搜索会向已启用的服务发送关键词，点击测试会发送固定测试词。': [
    'Declared capabilities do not guarantee permanent availability or download permission. Login, payment and DRM are not bypassed; searches send keywords to enabled services, and Test sends a fixed test query.',
    '能力の宣言は永続的な利用やダウンロード許可を保証しません。ログイン、支払い、DRM を回避せず、検索語は有効なサービスへ、テスト時は固定のテスト語が送信されます。',
    '기능 표시는 영구 사용이나 다운로드 권한을 보장하지 않습니다. 로그인, 결제 또는 DRM을 우회하지 않으며 검색어는 활성화된 서비스로, 테스트 시에는 고정된 테스트 검색어가 전송됩니다.'
  ],
  '停用或删除后立即停止该来源的新请求；已保存的收藏、歌单和歌曲信息不会删除。': [
    'Disabling or deleting a source immediately stops new requests to it; saved favorites, playlists and track information are not deleted.',
    '無効化または削除すると、その音源への新しいリクエストはすぐに停止します。保存済みのお気に入り、プレイリスト、曲情報は削除されません。',
    '음원을 비활성화하거나 삭제하면 해당 음원으로의 새 요청이 즉시 중지됩니다. 저장된 즐겨찾기, 재생목록 및 곡 정보는 삭제되지 않습니다.'
  ],
  '搜索会发送关键词；歌词、评论和播放/下载解析会向所选来源发送来源歌曲 ID 或必要的歌曲信息。': [
    'Search sends keywords; lyrics, comments, and playback or download resolution send the source track ID or necessary track information to the selected source.',
    '検索ではキーワードが送信されます。歌詞、コメント、再生またはダウンロードの解決では、取得元の曲 ID または必要な曲情報が選択した音源に送信されます。',
    '검색은 검색어를 전송합니다. 가사, 댓글, 재생 또는 다운로드 확인은 선택한 음원에 출처 곡 ID 또는 필요한 곡 정보를 전송합니다.'
  ],
  '导入': ['Import', '読み込む', '가져오기'],
  '导出': ['Export', '書き出す', '내보내기'],
  '添加歌源': ['Add source', '音源を追加', '음원 추가'],
  '测试': ['Test', 'テスト', '테스트'],
  '该歌源需在实际歌曲上测试': [
    'Test this source with an actual track',
    'この音源は実際の曲でテストしてください',
    '이 음원은 실제 곡으로 테스트해야 합니다'
  ],
  '搜索接口连接正常；其他能力需使用实际歌曲验证': [
    'The search endpoint is working; test other capabilities with an actual track',
    '検索エンドポイントは正常です。その他の能力は実際の曲で確認してください',
    '검색 엔드포인트가 정상입니다. 다른 기능은 실제 곡으로 확인하세요'
  ],
  '歌源测试失败：{0}': [
    'Source test failed: {0}',
    '音源のテストに失敗しました：{0}',
    '음원 테스트 실패: {0}'
  ],
  '网络请求失败': ['Network request failed', 'ネットワーク要求に失敗しました', '네트워크 요청 실패'],
  '连接超时': ['Connection timed out', '接続がタイムアウトしました', '연결 시간이 초과되었습니다'],
  '凭据尚未配置': [
    'Credentials are not configured',
    '認証情報が設定されていません',
    '인증 정보가 설정되지 않았습니다'
  ],
  '歌源配置尚不可用': [
    'The source configuration is not ready',
    '音源設定はまだ利用できません',
    '음원 설정을 아직 사용할 수 없습니다'
  ],
  '测试已取消': ['Test cancelled', 'テストをキャンセルしました', '테스트가 취소되었습니다'],
  '接口返回 HTTP {0}': [
    'The endpoint returned HTTP {0}',
    'エンドポイントが HTTP {0} を返しました',
    '엔드포인트가 HTTP {0}을 반환했습니다'
  ],
  '接口响应格式不可识别': [
    'The endpoint response format is not recognized',
    'エンドポイントの応答形式を認識できません',
    '엔드포인트 응답 형식을 인식할 수 없습니다'
  ],
  '编辑': ['Edit', '編集', '편집'],
  '尚未添加自定义歌源': [
    'No custom sources added',
    'カスタム音源はまだありません',
    '추가한 사용자 지정 음원이 없습니다'
  ],
  '可添加 Dan Player 通用协议、旧版歌词接口或你自行部署的兼容服务。': [
    'Add a Dan Player general provider, a legacy lyric endpoint, or a compatible service you host.',
    'Dan Player 汎用プロトコル、従来の歌詞エンドポイント、または自分で運用する互換サービスを追加できます。',
    'Dan Player 범용 프로토콜, 기존 가사 엔드포인트 또는 직접 배포한 호환 서비스를 추가할 수 있습니다.'
  ],
  '添加自定义歌源': ['Add custom source', 'カスタム音源を追加', '사용자 지정 음원 추가'],
  '编辑自定义歌源': ['Edit custom source', 'カスタム音源を編集', '사용자 지정 음원 편집'],
  '删除自定义歌源': ['Delete custom source', 'カスタム音源を削除', '사용자 지정 음원 삭제'],
  '导入的歌词 API': ['Imported lyric API', '読み込んだ歌詞 API', '가져온 가사 API'],
  '仅决定本地歌词与在线候选的优先顺序': [
    'Only sets the priority between local lyrics and online candidates',
    'ローカル歌詞とオンライン候補の優先順位だけを設定します',
    '로컬 가사와 온라인 후보의 우선순위만 정합니다'
  ],
  '只删除“{0}”的配置，不会删除收藏、歌单或歌曲。': [
    'Only the “{0}” configuration will be deleted. Favorites, playlists and tracks are not affected.',
    '「{0}」の設定だけを削除します。お気に入り、プレイリスト、曲は削除されません。',
    '“{0}” 설정만 삭제합니다. 즐겨찾기, 재생목록 및 곡은 삭제되지 않습니다.'
  ],
  '名称': ['Name', '名前', '이름'],
  '协议': ['Protocol', 'プロトコル', '프로토콜'],
  '服务地址': ['Service URL', 'サービス URL', '서비스 URL'],
  '歌词接口地址': ['Lyric endpoint URL', '歌詞エンドポイント URL', '가사 엔드포인트 URL'],
  '能力': ['Capabilities', '能力', '기능'],
  'Dan Player 通用 v1': [
    'Dan Player General v1',
    'Dan Player 汎用 v1',
    'Dan Player 범용 v1'
  ],
  '旧版歌词 API': ['Legacy lyric API', '従来の歌詞 API', '기존 가사 API'],
  'go-music-api（自托管）': [
    'go-music-api (self-hosted)',
    'go-music-api（セルフホスト）',
    'go-music-api(직접 호스팅)'
  ],
  '通用能力协议：按服务实际支持的内容选择，可分别填写接口地址。': [
    'General capability protocol: select what the service supports and configure endpoint URLs separately.',
    '汎用能力プロトコル：サービスが実際に対応する項目を選び、接続先を個別に設定できます。',
    '범용 기능 프로토콜입니다. 서비스가 실제로 지원하는 항목을 선택하고 인터페이스 주소를 따로 설정할 수 있습니다.'
  ],
  '编辑器默认让所选能力共用服务地址；导入配置可保留各能力的独立端点。': [
    'The editor uses one service URL for selected capabilities by default; imported configurations can retain separate endpoints.',
    'エディターでは選択した能力に同じサービス URL を既定で使用します。読み込んだ設定では能力ごとのエンドポイントを保持できます。',
    '편집기는 선택한 기능에 하나의 서비스 URL을 기본으로 사용합니다. 가져온 설정은 기능별 엔드포인트를 유지할 수 있습니다.'
  ],
  '兼容原有歌词接口，仅提供歌词候选。': [
    'Compatible with the previous lyric endpoint; provides lyric candidates only.',
    '従来の歌詞エンドポイントと互換性があり、歌詞候補のみを提供します。',
    '기존 가사 엔드포인트와 호환되며 가사 후보만 제공합니다.'
  ],
  '自托管兼容预设：搜索、歌曲信息、封面、歌词、播放解析与授权下载。': [
    'Self-hosted compatible preset: search, track details, covers, lyrics, playback resolution and authorized downloads.',
    'セルフホスト互換プリセット：検索、曲情報、カバー、歌詞、再生解決、許可されたダウンロード。',
    '직접 호스팅 호환 프리셋: 검색, 곡 정보, 표지, 가사, 재생 확인 및 허가된 다운로드.'
  ],
  '此预设需要你自行部署兼容服务；Dan Player 不代为提供服务器或平台凭据。': [
    'This preset requires a compatible service that you deploy. Dan Player does not provide a server or platform credentials.',
    'このプリセットには、自分で運用する互換サービスが必要です。Dan Player はサーバーやプラットフォーム認証情報を提供しません。',
    '이 프리셋은 직접 배포한 호환 서비스가 필요합니다. Dan Player는 서버나 플랫폼 인증 정보를 제공하지 않습니다.'
  ],
  '搜索': ['Search', '検索', '검색'],
  '歌曲信息（随搜索）': ['Track details (with search)', '曲情報（検索結果）', '곡 정보(검색 결과)'],
  '封面（随搜索）': ['Cover (with search)', 'カバー（検索結果）', '표지(검색 결과)'],
  '歌词': ['Lyrics', '歌詞', '가사'],
  '评论': ['Comments', 'コメント', '댓글'],
  '播放解析': ['Playback URL', '再生解決', '재생 확인'],
  '下载': ['Download', 'ダウンロード', '다운로드'],
  '请输入名称': ['Enter a name', '名前を入力してください', '이름을 입력하세요'],
  '至少选择一项能力': [
    'Select at least one capability',
    '能力を 1 つ以上選択してください',
    '기능을 하나 이상 선택하세요'
  ],
  '该配置无法保存，请检查名称和地址': [
    'This configuration cannot be saved. Check its name and URL.',
    'この設定は保存できません。名前と URL を確認してください。',
    '이 설정을 저장할 수 없습니다. 이름과 URL을 확인하세요.'
  ],
  '保存自定义歌源失败；当前修改仍对本次会话生效。': [
    'Could not save custom sources; the current changes still apply to this session.',
    'カスタム音源を保存できませんでした。現在の変更はこのセッションでは引き続き有効です。',
    '사용자 지정 음원을 저장하지 못했습니다. 현재 변경 사항은 이번 세션에는 계속 적용됩니다.'
  ],
  '最多可保存 {0} 个自定义歌源': [
    'You can save up to {0} custom sources',
    'カスタム音源は最大 {0} 件まで保存できます',
    '사용자 지정 음원은 최대 {0}개까지 저장할 수 있습니다'
  ],
  '导入自定义歌源': ['Import custom sources', 'カスタム音源を読み込む', '사용자 지정 음원 가져오기'],
  '导出自定义歌源': ['Export custom sources', 'カスタム音源を書き出す', '사용자 지정 음원 내보내기'],
  'Dan Player 歌源配置': [
    'Dan Player source configuration',
    'Dan Player 音源設定',
    'Dan Player 음원 설정'
  ],
  '文件中没有可用的歌源配置': [
    'The file contains no usable source configurations',
    'ファイルに利用可能な音源設定がありません',
    '파일에 사용할 수 있는 음원 설정이 없습니다'
  ],
  '发现重复配置': [
    'Duplicate configurations found',
    '重複する設定が見つかりました',
    '중복 설정을 찾았습니다'
  ],
  '有 {0} 个配置 ID 已存在。你可以更新这些配置并添加其余项目，或只添加全新的项目。': [
    '{0} configuration IDs already exist. Update those and add the remaining items, or add only entirely new items.',
    '{0} 件の設定 ID がすでに存在します。それらを更新して残りを追加するか、新しい項目だけを追加できます。',
    '설정 ID {0}개가 이미 있습니다. 해당 설정을 업데이트하고 나머지를 추가하거나 완전히 새로운 항목만 추가할 수 있습니다.'
  ],
  '仅添加新项': ['Add new only', '新規項目のみ追加', '새 항목만 추가'],
  '合并并更新': ['Merge and update', '統合して更新', '병합 및 업데이트'],
  '已导入 {0} 个新配置，更新 {1} 个配置': [
    'Imported {0} new configurations and updated {1}',
    '新しい設定を {0} 件読み込み、{1} 件を更新しました',
    '새 설정 {0}개를 가져오고 {1}개를 업데이트했습니다'
  ],
  '已导入 {0} 个新配置，更新 {1} 个配置；{2} 个配置因达到上限未导入': [
    'Imported {0} new configurations and updated {1}; {2} were not imported because the limit was reached',
    '新しい設定を {0} 件読み込み、{1} 件を更新しました。上限に達したため {2} 件は読み込まれませんでした',
    '새 설정 {0}개를 가져오고 {1}개를 업데이트했습니다. 상한에 도달해 {2}개는 가져오지 않았습니다'
  ],
  '导入失败，请选择有效的 Dan Player 歌源配置': [
    'Import failed. Choose a valid Dan Player source configuration.',
    '読み込みに失敗しました。有効な Dan Player 音源設定を選択してください。',
    '가져오지 못했습니다. 올바른 Dan Player 음원 설정을 선택하세요.'
  ],
  '歌源配置已导出；请勿在地址或公开请求头中填写密钥': [
    'Source configurations exported; do not put secrets in URLs or public request headers',
    '音源設定を書き出しました。URL や公開リクエストヘッダーに秘密情報を入れないでください',
    '음원 설정을 내보냈습니다. URL이나 공개 요청 헤더에 비밀 정보를 입력하지 마세요'
  ],
  '封面获取失败。可取消勾选“封面”后继续填入文字信息。': [
    'Could not load the cover. Clear “Cover” to continue with text metadata.',
    'カバーを取得できませんでした。「カバー」を外すと文字情報だけを入力できます。',
    '표지를 불러오지 못했습니다. “표지” 선택을 해제하면 텍스트 정보만 계속 입력할 수 있습니다.',
  ],
  '请勿在地址或公开请求头中填写密钥。': [
    'Do not put secrets in URLs or public request headers.',
    'URL や公開リクエストヘッダーに秘密情報を入れないでください。',
    'URL이나 공개 요청 헤더에 비밀 정보를 입력하지 마세요.'
  ],
  '导出歌源配置失败': [
    'Could not export source configurations',
    '音源設定を書き出せませんでした',
    '음원 설정을 내보내지 못했습니다'
  ],
  '复制完整联网标识': ['Copy full online ID', '完全なオンライン ID をコピー', '전체 온라인 ID 복사'],
  '已复制联网标识': ['Online ID copied', 'オンライン ID をコピーしました', '온라인 ID를 복사했습니다'],
  '来源未授权': [
    'Source has not authorized downloads',
    '音源からダウンロードが許可されていません',
    '음원에서 다운로드를 허용하지 않았습니다'
  ],
  '该歌源明确标记这首歌曲不可下载': [
    'The source explicitly marks this track as unavailable for download',
    'この音源では、この曲はダウンロード不可と明示されています',
    '이 음원은 해당 곡을 다운로드할 수 없다고 명시했습니다'
  ],
  '该歌源没有明确授权下载这首歌曲': [
    'The source has not explicitly authorized this track for download',
    'この曲のダウンロードは音源から明示的に許可されていません',
    '음원에서 해당 곡의 다운로드를 명시적으로 허용하지 않았습니다'
  ],
  '该联网音乐来源当前不支持下载': [
    'This online music source currently does not support downloads',
    'このオンライン音源は現在ダウンロードに対応していません',
    '이 온라인 음원은 현재 다운로드를 지원하지 않습니다'
  ],
  '联网请求已取消': [
    'Online request cancelled',
    'オンラインリクエストをキャンセルしました',
    '온라인 요청이 취소되었습니다'
  ],
  '联网请求超时，请稍后重试': [
    'The online request timed out. Try again later.',
    'オンラインリクエストがタイムアウトしました。しばらくしてから再試行してください。',
    '온라인 요청 시간이 초과되었습니다. 잠시 후 다시 시도하세요.'
  ],
  '联网失败，请检查网络连接': [
    'The online request failed. Check your network connection.',
    'オンライン接続に失敗しました。ネットワーク接続を確認してください。',
    '온라인 요청에 실패했습니다. 네트워크 연결을 확인하세요.'
  ],
  '歌源凭据尚未配置': [
    'Source credentials are not configured',
    '音源の認証情報が設定されていません',
    '음원 인증 정보가 설정되지 않았습니다'
  ],
  '该联网音乐来源当前不可用': [
    'This online music source is currently unavailable',
    'このオンライン音源は現在利用できません',
    '이 온라인 음원을 현재 사용할 수 없습니다'
  ],
  '音乐服务返回的数据无效或过大': [
    'The music service returned invalid or oversized data',
    '音楽サービスが無効または大きすぎるデータを返しました',
    '음악 서비스에서 잘못되었거나 너무 큰 데이터를 반환했습니다'
  ],
  '音乐服务拒绝了请求': [
    'The music service rejected the request',
    '音楽サービスがリクエストを拒否しました',
    '음악 서비스에서 요청을 거부했습니다'
  ],
  '联网操作失败，请稍后重试': [
    'The online operation failed. Try again later.',
    'オンライン操作に失敗しました。しばらくしてから再試行してください。',
    '온라인 작업에 실패했습니다. 잠시 후 다시 시도하세요.'
  ],
  '对应的自定义歌源已移除、停用或无法提供封面': [
    'The corresponding custom source was removed, disabled, or cannot provide covers',
    '対応するカスタム音源が削除、無効化されたか、カバーを提供できません',
    '해당 사용자 지정 음원이 삭제되었거나 비활성화되었거나 표지를 제공할 수 없습니다'
  ],
  '封面来源没有提供安全且有效的图片地址': [
    'The cover source did not provide a safe, valid image URL',
    'カバーの取得元から安全で有効な画像 URL が提供されませんでした',
    '표지 출처에서 안전하고 올바른 이미지 URL을 제공하지 않았습니다'
  ],
  '自定义歌源已停用或封面地址不再安全': [
    'The custom source was disabled or the cover URL is no longer safe',
    'カスタム音源が無効化されたか、カバー URL が安全ではなくなりました',
    '사용자 지정 음원이 비활성화되었거나 표지 URL이 더 이상 안전하지 않습니다'
  ],
  '内置歌词来源不可用；仍可选择上方的自定义歌源。': [
    'Built-in lyric sources are unavailable; you can still choose a custom source above.',
    '内蔵の歌詞ソースは利用できません。上のカスタム音源は引き続き選択できます。',
    '내장 가사 출처를 사용할 수 없지만 위의 사용자 지정 음원은 계속 선택할 수 있습니다.'
  ],
  '搜索超时，请重试。': [
    'Search timed out. Try again.',
    '検索がタイムアウトしました。再試行してください。',
    '검색 시간이 초과되었습니다. 다시 시도하세요.'
  ],
  '联网失败，请检查网络。': [
    'The network request failed. Check your connection.',
    'ネットワーク接続に失敗しました。接続を確認してください。',
    '네트워크 요청에 실패했습니다. 연결을 확인하세요.'
  ],
  '返回的数据无法解析，请重试。': [
    'The returned data could not be parsed. Try again.',
    '返されたデータを解析できませんでした。再試行してください。',
    '반환된 데이터를 해석할 수 없습니다. 다시 시도하세요.'
  ],
};
