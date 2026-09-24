const Map<String, List<String>> catalogTapLyricEditor = {
  "你想如何编辑歌词😋？": [
    "How would you like to edit lyrics? 😋",
    "歌詞をどう編集しますか？😋",
    "가사를 어떻게 편집할까요? 😋"
  ],
  "快捷点按": ["Tap to time", "タップで時刻を付ける", "눌러서 타이밍 지정"],
  "传统码字": ["Text editor", "テキストで編集", "텍스트로 편집"],
  "听歌点按，逐步制作逐句和逐字歌词。": [
    "Listen and tap to time lines, then words.",
    "曲を聴きながらタップして行・単語の時刻を付けます。",
    "음악을 들으며 눌러 행과 단어의 타이밍을 지정합니다."
  ],
  "选择格式，直接编辑歌词代码。": [
    "Choose a format and edit lyric markup directly.",
    "形式を選び、歌詞のコードを直接編集します。",
    "형식을 선택하고 가사 코드를 직접 편집합니다."
  ],
  "操作失败，请重试。": [
    "The operation failed. Please try again.",
    "操作に失敗しました。再試行してください。",
    "작업에 실패했습니다. 다시 시도해 주세요."
  ],
  "点按进度已保存，可下次继续。": [
    "Timing progress saved. You can resume later.",
    "作業を保存しました。後で再開できます。",
    "진행 상황을 저장했습니다. 나중에 이어서 할 수 있습니다."
  ],
  "没有已保存的点按进度。": [
    "No saved timing progress for this song.",
    "この曲の保存済み作業はありません。",
    "이 곡에 저장된 진행 상황이 없습니다."
  ],
  "歌曲时长与进度不符，请重新编辑。": [
    "The song duration no longer matches this progress. Please start again.",
    "曲の長さが保存した作業と一致しません。最初から編集してください。",
    "곡 길이가 저장된 진행 상황과 다릅니다. 다시 편집해 주세요."
  ],
  "音乐已到句尾，请重录本句；未完成的字不会自动确认。": [
    "The line has ended. Retry this line; unfinished words are not confirmed automatically.",
    "行末に達しました。この行をやり直してください。未完了の単語は自動確定されません。",
    "행 끝에 도달했습니다. 이 행을 다시 기록하세요. 미완료 단어는 자동 확정되지 않습니다."
  ],
  "歌曲已结束，但歌词尚未完成。请检查歌词文本与歌曲版本是否一致，或本句打点是否有误。": [
    "The song has ended with unfinished lyrics. Check that the text matches this song version, or retry the line timing.",
    "曲が終了しましたが、未完了の歌詞があります。歌詞と曲のバージョンが一致するか、行の時刻に誤りがないか確認してください。",
    "곡이 끝났지만 미완료 가사가 있습니다. 가사와 곡 버전이 일치하는지, 행 타이밍이 잘못되었는지 확인하세요."
  ],
  "退出快捷点按？": ["Leave tap timing?", "タップ編集を終了しますか？", "점찍기 편집을 종료할까요?"],
  "不保存退出会丢失本次全部进度，包括纯文本歌词。上次手动保存的进度仍保留。": [
    "Leaving without saving loses this session, including the plain text. Your last manually saved progress is kept.",
    "保存せずに終了するとテキストを含む今回の作業が失われます。前回手動保存した作業は残ります。",
    "저장하지 않고 종료하면 일반 텍스트를 포함한 이번 작업이 사라집니다. 마지막으로 직접 저장한 진행 상황은 유지됩니다."
  ],
  "不保存退出": ["Leave without saving", "保存せずに終了", "저장하지 않고 종료"],
  "保存进度并退出": ["Save progress and leave", "作業を保存して終了", "진행 상황 저장 후 종료"],
  "每行：歌词正文|翻译|注音；缺翻译时用正文||注音。": [
    "Each line: lyrics|translation|pronunciation. Without translation: lyrics||pronunciation.",
    "各行：歌詞|翻訳|読み。翻訳がない場合：歌詞||読み。",
    "각 행: 가사|번역|발음. 번역이 없으면 가사||발음."
  ],
  "正文含有分隔符时，增加两侧空格数；输入的分隔符必须与下方示例一致。": [
    "If your text contains the separator, add spaces on both sides. Use exactly the separator shown below.",
    "本文に区切り文字がある場合は両側の空白を増やし、下の例と同じ区切りを入力してください。",
    "본문에 구분자가 있으면 양쪽 공백 수를 늘리세요. 아래 예시와 정확히 같은 구분자를 입력하세요."
  ],
  "分隔符空格数": ["Separator spaces per side", "区切りの片側の空白数", "구분자 한쪽 공백 수"],
  "纯文本歌词": ["Plain-text lyrics", "歌詞テキスト", "일반 텍스트 가사"],
  "联网填入纯文本": [
    "Fetch lyrics as plain text",
    "オンライン歌詞をテキスト化",
    "온라인 가사를 텍스트로 가져오기"
  ],
  "加载上次进度": ["Resume saved progress", "保存した作業を再開", "저장한 진행 상황 불러오기"],
  "保存纯文本歌词": ["Save plain-text lyrics", "テキスト歌詞を保存", "일반 텍스트 가사 저장"],
  "继续编写逐句歌词": ["Continue to line timing", "行の時刻付けへ進む", "행 타이밍 지정으로 계속"],
  "第 {0} / {1} 行": ["Line {0} of {1}", "{0} / {1} 行", "{0} / {1}행"],
  "开始本句 · Enter": ["Start line · Enter", "行の開始 · Enter", "행 시작 · Enter"],
  "结束本句 · Enter": ["End line · Enter", "行の終了 · Enter", "행 끝 · Enter"],
  "试听检查：满意后继续；不满意只重录当前行。": [
    "Review the timing. Accept to continue, or retry just this line.",
    "試聴して確認します。よければ次へ、やり直す場合はこの行だけ再録します。",
    "타이밍을 확인하세요. 만족하면 계속하고, 아니면 현재 행만 다시 기록합니다."
  ],
  "空格播放或暂停；Enter 或点按强调的字，记录该字结束。": [
    "Space plays or pauses. Enter or tap the highlighted word to mark its end.",
    "Spaceで再生・一時停止。Enterまたは強調された文字をタップして終わりを記録します。",
    "Space로 재생·일시 정지합니다. Enter 또는 강조된 글자를 눌러 끝을 기록하세요."
  ],
  "空格播放或暂停；Enter 标记本句开始，再按一次标记结束。": [
    "Space plays or pauses. Enter marks the line start; press again to mark its end.",
    "Spaceで再生・一時停止。Enterで行の開始、もう一度で終了を記録します。",
    "Space로 재생·일시 정지합니다. Enter로 행 시작을 기록하고 다시 눌러 끝을 기록하세요."
  ],
  "暂停 · 空格": ["Pause · Space", "一時停止 · Space", "일시 정지 · Space"],
  "播放 · 空格": ["Play · Space", "再生 · Space", "재생 · Space"],
  "不满意，重录本句": ["Retry this line", "この行をやり直す", "이 행 다시 기록"],
  "重录本句": ["Retry line", "行をやり直す", "행 다시 기록"],
  "满意，继续": ["Accept and continue", "確定して次へ", "확정 후 계속"],
  "逐字打点完成": ["Word timing complete", "単語の時刻付け完了", "단어 타이밍 지정 완료"],
  "逐句打点完成": ["Line timing complete", "行の時刻付け完了", "행 타이밍 지정 완료"],
  "LRC 兼容广但不能完整保留句尾和逐字时间；增强 LRC、QRC、KRC、YRC 支持逐字。播放器无损副本保留全部时间、翻译和注音。": [
    "LRC is widely supported but cannot preserve all line ends and word timing. Enhanced LRC, QRC, KRC and YRC support word timing. The lossless player copy preserves all timing, translations and pronunciation.",
    "LRCは広く対応されていますが行末や単語の時刻を完全には保持できません。拡張LRC・QRC・KRC・YRCは単語の時刻に対応します。プレーヤーの無損失コピーは全時刻・翻訳・読みを保持します。",
    "LRC는 호환성이 높지만 행 끝과 단어 타이밍을 모두 보존하지 못합니다. 확장 LRC, QRC, KRC, YRC는 단어 타이밍을 지원합니다. 플레이어 무손실 사본은 모든 시간, 번역, 발음을 보존합니다."
  ],
  "QRC 为文本，KRC 为压缩格式，YRC 常见于网易。其他播放器对翻译与注音的支持不同，导出会保留辅助文件。": [
    "QRC here is text; KRC is compressed; YRC is common on NetEase. Translation and pronunciation support varies by player; export keeps companion files.",
    "ここでのQRCはテキスト、KRCは圧縮形式、YRCはNetEaseで使われます。翻訳・読みへの対応はプレーヤーごとに異なり、書き出しでは補助ファイルも保存します。",
    "여기서 QRC는 텍스트, KRC는 압축 형식이며 YRC는 NetEase에서 흔히 쓰입니다. 번역·발음 지원은 플레이어마다 다르며 내보낼 때 보조 파일도 보존합니다."
  ],
  "暂不支持独立的对唱角色和重叠声部；可在正文注明演唱者。": [
    "Separate duet roles and overlapping vocal parts are not supported yet. You can label singers in the lyric text.",
    "独立したデュエット役割や重なる声部には未対応です。歌詞本文に歌い手を記載できます。",
    "별도 듀엣 역할과 겹치는 보컬 파트는 아직 지원하지 않습니다. 가사 본문에 가수를 표시할 수 있습니다."
  ],
  "选择格式并保存歌词": ["Choose format and save", "形式を選んで歌詞を保存", "형식 선택 후 가사 저장"],
  "继续编写逐字歌词": ["Continue to word timing", "単語の時刻付けへ進む", "단어 타이밍 지정으로 계속"],
  "保存当前进度": ["Save current progress", "現在の作業を保存", "현재 진행 상황 저장"],
  "无法读取点按进度": [
    "Cannot read saved timing progress",
    "保存した作業を読み込めません",
    "저장된 진행 상황을 읽을 수 없습니다"
  ],
  "请检查分隔符：每行最多为正文、翻译、注音三栏。": [
    "Check the separator: each line allows only lyrics, translation and pronunciation.",
    "区切りを確認してください。各行は歌詞・翻訳・読みの3列までです。",
    "구분자를 확인하세요. 각 행에는 가사, 번역, 발음 3개 열만 허용됩니다."
  ],
  "返回修改文本": ["Edit the text again", "テキストを修正", "텍스트 다시 편집"],
  "返回修改会清除本次打点，但保留纯文本。建议先保存当前进度。": [
    "This clears the current timing but keeps the text. Consider saving your progress first.",
    "戻ると今回の時刻が消去され、テキストは残ります。先に作業を保存することをおすすめします。",
    "돌아가면 현재 타이밍은 삭제되고 텍스트는 유지됩니다. 먼저 진행 상황을 저장하는 것이 좋습니다."
  ]
};
