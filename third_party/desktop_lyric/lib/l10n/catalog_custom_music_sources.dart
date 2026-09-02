/// Multi-source settings. Order: English, Japanese, Korean.
const Map<String, List<String>> catalogCustomMusicSources = {
  '内置歌源': ['Built-in sources', '内蔵音源', '내장 음원'],
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
  '导入': ['Import', '読み込む', '가져오기'],
  '导出': ['Export', '書き出す', '내보내기'],
  '添加歌源': ['Add source', '音源を追加', '음원 추가'],
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
  '通用能力协议：按服务实际支持的内容选择；歌曲信息和封面随搜索结果返回。': [
    'General capability protocol: select only what the service supports; track details and covers accompany search results.',
    '汎用能力プロトコル：サービスが実際に対応する項目を選択します。曲情報とカバーは検索結果に含まれます。',
    '범용 기능 프로토콜입니다. 서비스가 실제로 지원하는 항목만 선택하며 곡 정보와 표지는 검색 결과에 포함됩니다.'
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
  '歌源配置已导出；文件不包含密钥': [
    'Source configurations exported; the file contains no secrets',
    '音源設定を書き出しました。ファイルに秘密情報は含まれません',
    '음원 설정을 내보냈습니다. 파일에는 비밀 정보가 없습니다'
  ],
  '导出歌源配置失败': [
    'Could not export source configurations',
    '音源設定を書き出せませんでした',
    '음원 설정을 내보내지 못했습니다'
  ],
};
