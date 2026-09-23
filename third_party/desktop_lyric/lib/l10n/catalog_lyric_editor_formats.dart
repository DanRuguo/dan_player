const catalogLyricEditorFormats = <String, List<String>>{
  "LRC · 逐句": ["LRC · Line timing", "LRC · 行単位", "LRC · 줄 타이밍"],
  "增强 LRC · 逐字": [
    "Enhanced LRC · Word timing",
    "拡張 LRC · 単語単位",
    "확장 LRC · 단어 타이밍"
  ],
  "QRC · 逐字": ["QRC · Word timing", "QRC · 単語単位", "QRC · 단어 타이밍"],
  "KRC · 逐字": ["KRC · Word timing", "KRC · 単語単位", "KRC · 단어 타이밍"],
  "YRC · 逐字": ["YRC · Word timing", "YRC · 単語単位", "YRC · 단어 타이밍"],
  "纯文本": ["Plain text", "プレーンテキスト", "일반 텍스트"],
  "播放器无损副本": ["Lossless player copy", "プレーヤーの無損失コピー", "플레이어 무손실 사본"],
  "选择歌词编辑格式": ["Choose lyric format", "歌詞の編集形式を選択", "가사 편집 형식 선택"],
  "不含时间轴，适合只编写歌词文字。": [
    "Text only, without timing.",
    "タイムラインなしで歌詞の文字のみを編集。",
    "타이밍 없이 가사 텍스트만 편집합니다."
  ],
  "逐句时间轴；翻译和注音分别编辑。": [
    "Line timing with separate translation and pronunciation.",
    "行単位のタイムライン。翻訳・読みを個別に編集。",
    "줄 타이밍과 번역·발음을 따로 편집합니다."
  ],
  "保留全部逐字时间、翻译和注音，适合无损保存与交换。": [
    "Preserves all word timing, translation and pronunciation for lossless exchange.",
    "単語の時刻・翻訳・読みをすべて保持して保存・交換。",
    "단어 타이밍·번역·발음을 모두 보존하여 저장·교환합니다."
  ],
  "逐字时间轴；支持原文、翻译和注音。": [
    "Word timing with original text, translation and pronunciation.",
    "単語単位のタイムライン。原文・翻訳・読みを編集。",
    "단어 타이밍과 원문·번역·발음을 편집합니다."
  ],
  "转换歌词格式？": ["Convert lyric format?", "歌詞形式を変換しますか？", "가사 형식을 변환할까요?"],
  "转换可能丢失逐字时间或辅助内容；纯文本转时间轴需要手动校时。原始版本仍保留。": [
    "Conversion may lose word timing or auxiliary text. Plain text needs manual timing. The original version is retained.",
    "変換で単語の時刻や補助テキストが失われる場合があります。テキストの時刻は手動調整が必要です。元の版は保持されます。",
    "변환 시 단어 타이밍이나 보조 텍스트가 손실될 수 있습니다. 일반 텍스트의 타이밍은 직접 맞춰야 합니다. 원본은 보존됩니다."
  ],
  "保留完整内容": ["Keep all data", "すべての内容を保持", "모든 내용 유지"],
  "返回选择格式": ["Back to format selection", "形式の選択に戻る", "형식 선택으로 돌아가기"],
  "转换": ["Convert", "変換", "변환"],
  "导入歌词": ["Import lyrics", "歌詞をインポート", "가사 가져오기"],
  "歌词文件": ["Lyric files", "歌詞ファイル", "가사 파일"],
  "替换编辑中的内容？": [
    "Replace the current draft?",
    "編集中の内容を置き換えますか？",
    "편집 중인 내용을 바꿀까요?"
  ],
  "替换": ["Replace", "置き換え", "바꾸기"],
  "导出歌词": ["Export lyrics", "歌詞をエクスポート", "가사 내보내기"],
  "请选择对应格式的歌词文件": [
    "Choose a lyric file with the selected extension.",
    "選択した形式の拡張子を指定してください。",
    "선택한 형식의 확장자를 지정하세요."
  ],
  "以下文件将写入，已有内容保留备份；翻译和注音使用独立 LRC 文件。\n{0}": [
    "These files will be written; existing files are backed up. Translation and pronunciation use separate LRC files.\n{0}",
    "以下のファイルを書き込み、既存の内容はバックアップします。翻訳・読みは別の LRC ファイルに保存します。\n{0}",
    "아래 파일을 저장하며 기존 내용은 백업합니다. 번역·발음은 별도 LRC 파일로 저장합니다.\n{0}"
  ],
  "保存应用内修订并锁定，保留原始歌词。": [
    "Save and lock an in-app revision; keep the original lyrics.",
    "アプリ内の修正版を保存・固定し、元の歌詞を保持します。",
    "앱 내 수정본을 저장·잠그고 원본 가사는 보존합니다."
  ],
  "原文": ["Original", "原文", "원문"],
  "翻译": ["Translation", "翻訳", "번역"],
  "注音": ["Pronunciation", "読み", "발음"],
  "预览": ["Preview", "プレビュー", "미리 보기"],
  "翻译和注音使用 LRC 时间戳，与原文行的开始时间一致。": [
    "Use LRC timestamps matching the start of each original line.",
    "原文の行の開始時刻に合わせた LRC タイムスタンプを使用します。",
    "원문 줄의 시작 시각과 일치하는 LRC 타임스탬프를 사용하세요."
  ],
  "格式示例（时间可手动修改）": [
    "Format example (timing is editable)",
    "形式例（時刻は手動で編集可能）",
    "형식 예시 (타이밍 직접 편집 가능)"
  ],
  "时间不能为负数": ["Time cannot be negative.", "時刻は負数にできません。", "시간은 음수일 수 없습니다."],
  "歌词文件过大": [
    "The lyric file is too large.",
    "歌詞ファイルが大きすぎます。",
    "가사 파일이 너무 큽니다."
  ],
  "无法识别歌词格式": [
    "Unrecognized lyric format.",
    "歌詞形式を認識できません。",
    "가사 형식을 인식할 수 없습니다."
  ],
  "纯文本格式不支持辅助时间轴": [
    "Plain text does not support auxiliary timelines.",
    "プレーンテキストは補助タイムラインに対応しません。",
    "일반 텍스트는 보조 타임라인을 지원하지 않습니다."
  ],
  "没有识别到有效歌词": [
    "No valid lyrics found.",
    "有効な歌詞が見つかりません。",
    "유효한 가사를 찾지 못했습니다."
  ],
  "歌词行格式无效": [
    "Invalid lyric line format.",
    "歌詞行の形式が無効です。",
    "가사 줄 형식이 올바르지 않습니다."
  ],
  "逐字歌词需要结束时间": [
    "Word-timed lyrics need an end timestamp.",
    "単語単位の歌詞には終了時刻が必要です。",
    "단어별 가사에는 종료 시각이 필요합니다."
  ],
  "翻译或注音时间未匹配原文": [
    "Translation or pronunciation timing does not match an original line.",
    "翻訳または読みの時刻が原文と一致しません。",
    "번역 또는 발음의 시간이 원문과 일치하지 않습니다."
  ],
  "结束时间不能早于开始时间": [
    "End time cannot precede start time.",
    "終了時刻は開始時刻より前にできません。",
    "종료 시각은 시작 시각보다 빠를 수 없습니다."
  ],
  "逐字时间超出所在行范围": [
    "Word timing is out of order or outside its line.",
    "単語の時刻が逆順か、行の範囲外です。",
    "단어 시간이 역순이거나 줄 범위를 벗어났습니다."
  ],
  "设置当前行时间": ["Set line time", "行の時刻を設定", "줄 시간 설정"],
  "设置所选文字时间": ["Time selected text", "選択した文字の時刻を設定", "선택한 텍스트 시간 설정"],
  "设置歌词时间": ["Set lyric timing", "歌詞の時刻を設定", "가사 시간 설정"],
  "单位为毫秒，使用歌曲时间轴。逐字内容必须位于该行的起止时间内。": [
    "Times are in milliseconds on the song timeline. Words must stay within their line’s time range.",
    "単位はミリ秒で、曲のタイムラインに対応します。単語の時刻は行の範囲内に設定してください。",
    "단위는 밀리초이며 곡의 타임라인을 사용합니다. 단어 시간은 줄의 시간 범위 안에 있어야 합니다."
  ],
  "开始时间": ["Start time", "開始時刻", "시작 시간"],
  "结束时间": ["End time", "終了時刻", "종료 시간"],
  "请输入有效起止时间（0 至 86400000 毫秒）": [
    "Enter valid start and end times (0–86400000 ms).",
    "有効な開始・終了時刻を入力してください（0～86400000 ミリ秒）。",
    "유효한 시작·종료 시간을 입력하세요 (0~86400000 ms)."
  ],
  "请选择不含时间标记的文字": [
    "Select text without timing markers.",
    "時刻マーカーを含まない文字を選択してください。",
    "시간 표식이 없는 텍스트를 선택하세요."
  ],
  "请先设置当前行时间，再选择该行的文字": [
    "Set the line time first, then select text in that line.",
    "先に行の時刻を設定し、その行の文字を選択してください。",
    "먼저 줄 시간을 설정한 후 해당 줄의 텍스트를 선택하세요."
  ],
  "预览最多显示 100 行，每行展示前 80 个时间片段；保存包含全部内容。": [
    "Preview shows up to 100 lines and 80 timed segments per line. Saving includes everything.",
    "プレビューは最大 100 行、各行の先頭 80 区間を表示します。保存時は全内容を含みます。",
    "미리 보기는 최대 100줄, 줄마다 처음 80개 시간 구간을 표시합니다. 저장 시 모든 내용이 포함됩니다."
  ],
  "保存为编辑副本；只有手动选用后才替换播放歌词。": [
    "Save an edited copy; playback changes only when you select it.",
    "編集コピーを保存します。再生に使う歌詞は手動で選ぶまで変わりません。",
    "편집 사본을 저장합니다. 직접 선택해야 재생 가사가 바뀝니다."
  ],
  "编辑副本已保存，手动选用后才用于播放": [
    "Edited copy saved. Select it manually to use it for playback.",
    "編集コピーを保存しました。手動で選ぶと再生に使用されます。",
    "편집 사본이 저장되었습니다. 직접 선택하면 재생에 사용됩니다."
  ],
  "保存编辑副本": ["Save edited copy", "編集コピーを保存", "편집 사본 저장"],
  "没有已保存的编辑副本": [
    "No saved edited copy.",
    "保存された編集コピーがありません。",
    "저장된 편집 사본이 없습니다."
  ],
  "使用编辑的本地歌词": ["Use edited local lyrics", "編集したローカル歌詞を使用", "편집한 로컬 가사 사용"],
  "使用已保存的完整编辑副本，保留逐字时间、翻译和注音。": [
    "Use the saved copy with word timing, translation and pronunciation.",
    "単語の時刻・翻訳・読みを保持した保存済みコピーを使用します。",
    "단어 타이밍·번역·발음이 보존된 사본을 사용합니다."
  ],
  "播放编辑预览": ["Play edited preview", "編集内容を再生プレビュー", "편집 내용 재생 미리 보기"],
  "逐句试听": ["Preview this line", "この行を試聴", "이 줄 미리 듣기"],
  "临时试听编辑内容，不改变歌曲的歌词来源。": [
    "Preview edited lyrics temporarily without changing the song’s lyric source.",
    "編集中の歌詞を一時的に試聴します。曲の歌詞ソースは変更しません。",
    "편집 내용을 임시로 미리 듣습니다. 곡의 가사 소스는 바뀌지 않습니다."
  ],
  "重新试听": ["Replay preview", "もう一度試聴", "다시 미리 듣기"],
  '载入示例': ['Load example', 'サンプルを読み込む', '예제 불러오기'],
  '选择格式 → 编辑内容 → 试听检查 → 保存副本': [
    'Choose format → Edit → Preview → Save copy',
    '形式を選択 → 編集 → 試聴 → コピーを保存',
    '형식 선택 → 편집 → 미리 듣기 → 사본 저장'
  ],
  '选择格式 → 编辑内容 → 保存副本': [
    'Choose format → Edit → Save copy',
    '形式を選択 → 編集 → コピーを保存',
    '형식 선택 → 편집 → 사본 저장'
  ],
  '安装试听组件': ['Install preview tools', '試聴コンポーネントをインストール', '미리 듣기 구성 요소 설치'],
  '试听复用 FFmpeg 组件，不会改写歌曲。可以手动安装，或从 GitHub 下载约 70 MB 的组件。': [
    'Preview uses the FFmpeg tools without modifying your songs. Install them manually or download about 70 MB from GitHub.',
    '試聴には FFmpeg を使用し、曲は変更しません。手動でインストールするか、GitHub から約 70 MB のコンポーネントをダウンロードできます。',
    '미리 듣기는 FFmpeg를 사용하며 곡을 수정하지 않습니다. 직접 설치하거나 GitHub에서 약 70 MB의 구성 요소를 받을 수 있습니다.'
  ],
  'QRC · 逐字（文本）': [
    'QRC · Word timing (text)',
    'QRC · 単語単位（テキスト）',
    'QRC · 단어 타이밍 (텍스트)'
  ],
  '歌词行时间必须顺序排列': [
    'Lyric lines must be ordered by time.',
    '歌詞行は時刻順に並べてください。',
    '가사 줄은 시간순으로 정렬해야 합니다.'
  ],
};
