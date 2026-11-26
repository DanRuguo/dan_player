// Snapshot 26.1.2-snapshot.4 UI catalog (zh keys -> [en, ja, ko]).
const Map<String, List<String>> catalogSnapshot42612 = {
  '显示英语音标': [
    'Show English IPA phonetics',
    '英語の発音記号を表示',
    '영어 발음기호 표시',
  ],
  '当前无法加载英语音标词典，请稍后重试': [
    'Unable to load the English phonetic dictionary right now. Please try again later.',
    '英語の発音辞書を読み込めませんでした。しばらくしてからもう一度お試しください。',
    '현재 영어 발음 사전을 불러올 수 없습니다. 잠시 후 다시 시도해 주세요.',
  ],
  '歌词过长，无法一次生成英语音标': [
    'Lyrics are too long to generate English phonetics at once',
    '歌詞が長すぎるため、一度に英語の発音記号を生成できません',
    '가사가 너무 길어 한 번에 영어 발음기호를 생성할 수 없습니다',
  ],
  '自动生成英语音标': [
    'Automatically generate English phonetics',
    '英語の発音記号を自動生成',
    '영어 발음기호 자동 생성',
  ],
  '离线匹配英语单词音标并显示在歌词上方，支持词形变化与常见缩写；保留已有注音和原歌词。': [
    'Matches English word IPA phonetics offline above lyrics, including inflections and common contractions, while preserving original lyrics and existing annotations.',
    'オフライン辞書で英単語の発音記号（IPA）を歌詞の上に表示します。語形変化や一般的な短縮形に対応し、元の歌詞や既存のルビはそのまま保持します。',
    '오프라인 사전으로 영어 단어의 발음기호(IPA)를 가사 위에 표시합니다. 어형 변화와 자주 쓰는 축약형을 지원하며 원본 가사와 기존 루비는 그대로 유지합니다.',
  ],
  '英语音标样式': [
    'English phonetic style',
    '英語発音記号のスタイル',
    '영어 발음기호 스타일',
  ],
  '切换音标显示边框样式，切换后立即生效且无需重新生成缓存。': [
    'Switch the framing style of IPA phonetics; changes take effect immediately without regenerating cached entries.',
    '発音記号の括弧スタイルを切り替えます。キャッシュを再生成せず即座に反映されます。',
    '발음기호의 괄호 표시 스타일을 전환하며 캐시를 다시 생성하지 않고 즉시 적용됩니다.',
  ],
  '纯音标': [
    'Plain IPA',
    '記号のみ',
    '기호만',
  ],
  '斜线 /…/': [
    'Slashes /…/',
    'スラッシュ /…/',
    '슬래시 /…/',
  ],
  '方括号 […]': [
    'Brackets […]',
    '角括弧 […]',
    '대괄호 […]',
  ],
  '批量生成英语音标': [
    'Batch generate English phonetics',
    '英語発音記号を一括生成',
    '영어 발음기호 일괄 생성',
  ],
  '仅处理播放器已缓存的歌词，完全离线匹配英语单词音标，不修改原歌词和已有注音。': [
    'Processes only lyrics already cached by the player completely offline, without modifying source lyrics or existing annotations.',
    'プレーヤーにキャッシュ済みの歌詞のみを対象に完全オフラインで英語発音記号を生成し、元の歌詞や既存の注音は変更しません。',
    '플레이어에 캐시된 가사만 대상으로 완전 오프라인에서 영어 발음기호를 생성하며 원본 가사와 기존 발음 표기는 변경하지 않습니다.',
  ],
  '开始后扫描已缓存歌词；离线批量生成，可随时取消。': [
    'Scans cached lyrics when started; generates offline in batch and can be cancelled anytime.',
    '開始するとキャッシュ済み歌詞を走査し、オフラインで一括生成します。いつでもキャンセルできます。',
    '시작하면 캐시된 가사를 스캔하여 오프라인으로 일괄 생성하며 언제든 취소할 수 있습니다.',
  ],
  '正在取消音标生成…': [
    'Cancelling phonetic generation…',
    '発音記号の生成をキャンセルしています…',
    '발음기호 생성을 취소하는 중…',
  ],
  '正在批量生成英语音标…': [
    'Generating English phonetics in batch…',
    '英語発音記号を一括生成しています…',
    '영어 발음기호를 일괄 생성하는 중…',
  ],
  '已取消，已生成的音标缓存会保留。': [
    'Cancelled. Already generated phonetic cache entries are kept.',
    'キャンセルしました。生成済みの発音記号キャッシュは保持されます。',
    '취소되었습니다. 이미 생성된 발음기호 캐시는 유지됩니다.',
  ],
  '批量生成英语音标完成': [
    'Batch English phonetic generation complete',
    '英語発音記号の一括生成が完了しました',
    '영어 발음기호 일괄 생성 완료',
  ],
  '打开批量生成英语音标': [
    'Open batch English phonetic generator',
    '英語発音記号の一括生成を開く',
    '영어 발음기호 일괄 생성 열기',
  ],
  '阅读工具中“显示日语假名”下方可勾选“显示英语音标”，使用内置离线词典在英语单词上方显示国际音标（IPA），可与日语假名同句并存；设置中可切换纯音标、斜线或方括号样式，也可离线批量生成已缓存歌词的英语音标。内嵌纯文本歌词（USLT／UNSYNCEDLYRICS）在无同步歌词时也会自动识别显示。':
      [
    'Enable "Show English IPA phonetics" right below "Show Japanese readings" in Reading Tools to display offline International Phonetic Alphabet (IPA) annotations above English words, coexisting seamlessly with Japanese furigana on bilingual lines. In Settings, you can switch between plain, slash, or bracket styles and batch-generate phonetics offline for cached lyrics. Embedded unsynced lyrics (USLT / UNSYNCEDLYRICS) are also automatically recognized when synced lyrics are absent.',
    '読書ツールの「日本語の読み仮名を表示」の下にある「英語の発音記号を表示」をオンにすると、内蔵オフライン辞書で英単語の上に国際音声記号（IPA）を表示でき、日本語のふりがなと同じ行で共存します。設定では記号のみ・スラッシュ・角括弧のスタイル切り替えや、キャッシュ済み歌詞のオフライン一括生成が可能です。同期歌詞がない場合は埋め込みプレーン歌詞（USLT／UNSYNCEDLYRICS）も自動認識して表示します。',
    '읽기 도구의 "일본어 후리가나 표시" 아래에서 "영어 발음기호 표시"를 켜면 내장 오프라인 사전으로 영어 단어 위에 국제음성기호(IPA)를 표시하며 일본어 후리가나와 한 줄에서 함께 표시됩니다. 설정에서 기호만·슬래시·대괄호 스타일을 전환하거나 캐시된 가사의 발음기호를 오프라인으로 일괄 생성할 수 있습니다. 싱크 가사가 없을 때는 내장 일반 텍스트 가사(USLT／UNSYNCEDLYRICS)도 자동으로 인식해 표시합니다.',
  ],
  'IPA': [
    'IPA',
    'IPA',
    'IPA',
  ],
  '触控与点击音效': [
    'Touch & click sound',
    'タッチ・クリック効果音',
    '터치 및 클릭 효과음',
  ],
  '点击按钮与列表项时播放轻柔的 Android 默认触控音效；点击空白区域不发声，WASAPI 独占输出时自动静音。': [
    'Plays a subtle default Android touch sound when tapping buttons and list items; empty areas stay silent, and WASAPI exclusive output automatically mutes UI clicks.',
    'ボタンやリスト項目をタップしたときに穏やかな Android 標準タッチ音を再生します。余白のクリックでは鳴らず、WASAPI 排他出力時は自動的にミュートされます。',
    '버튼과 목록 항목을 탭할 때 부드러운 Android 기본 터치 효과음을 재생합니다. 빈 영역 클릭 시에는 소리가 나지 않으며 WASAPI 단독 출력 시 자동으로 음소거됩니다.',
  ],
  '点击音效': [
    'Click sound',
    'クリック音',
    '클릭음',
  ],
  'Android': [
    'Android',
    'Android',
    'Android',
  ],
};
