// Snapshot 3 user-facing labels. Media text is never translated.
const catalogSnapshot3 = <String, List<String>>{
  "应用": ["Apply", "適用", "적용"],
  "歌曲": ["Songs", "楽曲", "곡"],
  "播放时防止自动休眠": ["Prevent sleep during playback", "再生中の自動スリープを防止", "재생 중 자동 절전 방지"],
  "播放时保持电脑唤醒；暂停后恢复自动休眠。屏幕仍可熄灭。": ["Keep the computer awake while playing; allow sleep when paused. The display can still turn off.", "再生中は自動スリープを防ぎ、一時停止すると解除します。画面は通常どおり消灯します。", "재생 중에는 컴퓨터를 깨워 두고 일시 정지하면 자동 절전을 허용합니다. 화면은 꺼질 수 있습니다."],
  "已关闭 · 使用系统休眠设置": ["Off · Using system sleep settings", "オフ · システムのスリープ設定を使用", "꺼짐 · 시스템 절전 설정 사용"],
  "已开启 · 等待播放": ["On · Waiting for playback", "オン · 再生待ち", "켜짐 · 재생 대기 중"],
  "已开启 · 播放中，防休眠已生效": ["On · Sleep prevention active during playback", "オン · 再生中のスリープ防止が有効", "켜짐 · 재생 중 절전 방지 적용됨"],
  "未生效 · 请重新切换开关": ["Not active · Turn the switch off and on to retry", "未適用 · スイッチを切り替えて再試行", "적용 안 됨 · 스위치를 껐다 켜서 다시 시도하세요"],
  "下次启动恢复队列与播放位置，保持暂停。": ["Restore the queue and playback position on next launch, paused.", "次回起動時にキューと再生位置を復元し、一時停止にします。", "다음 실행 시 대기열과 재생 위치를 일시 정지 상태로 복원합니다."],
  "下次启动不恢复上次播放队列。": ["Do not restore the previous queue on next launch.", "次回起動時に前回のキューを復元しません。", "다음 실행 시 이전 대기열을 복원하지 않습니다."],
  "设置保存失败，本次会话仍保留当前选择": ["Settings could not be saved. The current selection remains active for this session.", "設定を保存できませんでした。今回の選択は終了まで保持されます。", "설정을 저장하지 못했습니다. 현재 선택은 이번 실행 동안 유지됩니다."],

  "个人整理": ["Personal library", "個人ライブラリ", "개인 라이브러리"],
  "开始日期": ["Start date", "開始日", "시작 날짜"],
  "结束日期": ["End date", "終了日", "종료 날짜"],
  "日历选择": ["Choose from calendar", "カレンダーで選択", "달력에서 선택"],
  "输入日期": ["Enter date", "日付を入力", "날짜 입력"],
  "没有符合条件的歌曲": ["No matching songs", "条件に一致する曲がありません", "조건에 맞는 곡이 없습니다"],
  "电源请求失败": ["Power request failed", "電源要求に失敗しました", "전원 요청 실패"],
  "LRC 时间轴": ["LRC timestamps", "LRC タイムスタンプ", "LRC 타임스탬프"],
  "个人整理与最近添加": [
    "Personal library and recent additions",
    "個人ライブラリと最近の追加",
    "개인 라이브러리 및 최근 추가"
  ],
  "个人评分与标签": ["Personal ratings and tags", "個人の評価とタグ", "개인 평점 및 태그"],
  "书签超出当前有效时长": [
    "Bookmark exceeds the current duration",
    "ブックマークが現在の再生時間を超えています",
    "북마크가 현재 재생 시간을 초과합니다"
  ],
  "仅删除这份歌单恢复记录，不删除音乐文件。": [
    "Only this recovery record will be deleted. Music files are kept.",
    "この復元記録のみ削除します。音楽ファイルは残ります。",
    "이 복원 기록만 삭제합니다. 음악 파일은 유지됩니다."
  ],
  "仅影响此歌单。窄窗口自动使用紧凑布局。": [
    "Applies only to this playlist. Narrow windows use a compact layout.",
    "このプレイリストのみに適用します。狭いウィンドウでは簡易表示になります。",
    "이 재생목록에만 적용됩니다. 좁은 창에서는 간결하게 표시합니다."
  ],
  "仅恢复播放器内的歌单，不恢复已删除的音乐文件。": [
    "Restores the playlist, not deleted music files.",
    "プレイリストを復元します。削除済みの音楽ファイルは復元しません。",
    "재생목록을 복원합니다. 삭제된 음악 파일은 복원하지 않습니다."
  ],
  "仅补充缺少的出现次数": [
    "Add only missing occurrences",
    "不足している出現回数のみ追加",
    "부족한 등장 횟수만 추가"
  ],
  "从书签播放": ["Play from bookmark", "ブックマークから再生", "북마크부터 재생"],
  "任一满足": ["Match any", "いずれかに一致", "하나라도 일치"],
  "全部满足": ["Match all", "すべてに一致", "모두 일치"],
  "保存失败，未提交项可重试": [
    "Save failed. Uncommitted items can be retried.",
    "保存に失敗しました。未保存の項目を再試行できます。",
    "저장 실패. 저장되지 않은 항목은 재시도할 수 있습니다."
  ],
  "保存失败，草稿已保留": [
    "Save failed. Your draft is retained.",
    "保存に失敗しました。下書きは保持されています。",
    "저장 실패. 초안이 유지됩니다."
  ],
  "保存当前收听会话": [
    "Save current listening session",
    "現在の再生セッションを保存",
    "현재 재생 세션 저장"
  ],
  "保存当前调节": ["Save current adjustments", "現在の調整を保存", "현재 조정 저장"],
  "保留原歌曲偏移": [
    "Keep the existing lyric offset",
    "既存の歌詞オフセットを保持",
    "기존 가사 오프셋 유지"
  ],
  "保留当前": ["Keep current", "現在の設定を保持", "현재 설정 유지"],
  "修改个人标签": ["Edit personal tags", "個人タグを編集", "개인 태그 편집"],
  "修改评分": ["Edit rating", "評価を編集", "평점 편집"],
  "修订冲突或歌词已受保护，未覆盖": [
    "Revision conflict or protected lyrics; not overwritten",
    "リビジョンの競合または保護された歌詞のため、上書きしていません",
    "버전 충돌 또는 보호된 가사로 덮어쓰지 않았습니다"
  ],
  "停止后续提交": ["Stop remaining saves", "残りの保存を停止", "남은 저장 중지"],
  "允许屏幕正常熄灭；不阻止手动休眠。": [
    "Allows the display to sleep and manual system sleep.",
    "画面の自動消灯と手動のスリープは許可します。",
    "화면 자동 꺼짐 및 수동 절전은 허용합니다."
  ],
  "全库书签": ["All bookmarks", "すべてのブックマーク", "모든 북마크"],
  "全部": ["All", "すべて", "전체"],
  "全部评分": ["Any rating", "すべての評価", "모든 평점"],
  "共 {0} 首歌曲": ["{0} tracks", "全 {0} 曲", "총 {0}곡"],
  "关闭后全部追加，保留现有顺序。": [
    "When off, append all entries and keep existing order.",
    "オフの場合はすべて追加し、既存の順序を保持します。",
    "끄면 모든 항목을 추가하고 기존 순서를 유지합니다."
  ],
  "创建时间不可用": ["Creation time unavailable", "作成日時を取得できません", "생성 시간을 사용할 수 없음"],
  "删除所选": ["Delete selected", "選択項目を削除", "선택 항목 삭제"],
  "变更预览": ["Preview changes", "変更のプレビュー", "변경 미리보기"],
  "只保存到播放器资料，不修改音乐文件。未勾选的字段保持不变。": [
    "Saved in player data only. Music files and unchecked fields remain unchanged.",
    "プレーヤーのデータにのみ保存します。音楽ファイルと未選択の項目は変更しません。",
    "플레이어 데이터에만 저장합니다. 음악 파일과 선택하지 않은 필드는 유지됩니다."
  ],
  "可用 {0} 项，暂不可用 {1} 项": [
    "{0} available, {1} unavailable",
    "利用可能 {0} 件、利用不可 {1} 件",
    "사용 가능 {0}개, 사용 불가 {1}개"
  ],
  "同名歌单保留并更名，不覆盖现有歌单。": [
    "Name conflicts are renamed; existing playlists are kept.",
    "同名のプレイリストは名前を変更し、既存のものは保持します。",
    "이름이 중복되면 이름을 변경하며 기존 재생목록은 유지합니다."
  ],
  "同名预设将创建副本。": [
    "A duplicate name creates a copy.",
    "同名の場合はコピーを作成します。",
    "같은 이름이 있으면 복사본을 만듭니다."
  ],
  "回收站为空": ["Recycle bin is empty", "ごみ箱は空です", "휴지통이 비어 있습니다"],
  "定位": ["Go to", "移動", "이동"],
  "实际播放时防止自动休眠": [
    "Prevent automatic sleep during playback",
    "再生中の自動スリープを防止",
    "재생 중 자동 절전 방지"
  ],
  "导入 EQ 预设": ["Import EQ preset", "EQ プリセットをインポート", "EQ 프리셋 가져오기"],
  "导入 JSON": ["Import JSON", "JSON をインポート", "JSON 가져오기"],
  "导入目标": ["Import destination", "インポート先", "가져오기 대상"],
  "导出 EQ 预设": ["Export EQ preset", "EQ プリセットをエクスポート", "EQ 프리셋 내보내기"],
  "导出 JSON": ["Export JSON", "JSON をエクスポート", "JSON 내보내기"],
  "将替换当前队列，恢复后保持暂停。": [
    "Replaces the current queue and restores it paused.",
    "現在のキューを置き換え、一時停止状態で復元します。",
    "현재 대기열을 교체하고 일시정지 상태로 복원합니다."
  ],
  "已保存并锁定": ["Saved and locked", "保存して固定済み", "저장 및 잠금 완료"],
  "已完成 {0} 轮": ["{0} rounds completed", "{0} 回完了", "{0}회 완료"],
  "已跳过：受保护歌词或不支持的来源／CUE": [
    "Skipped: protected lyrics or unsupported source / CUE",
    "スキップ：保護された歌詞、未対応のソースまたは CUE",
    "건너뜀: 보호된 가사 또는 지원하지 않는 소스 / CUE"
  ],
  "总次数（留空无限）": [
    "Total rounds (blank for unlimited)",
    "合計回数（空欄で無制限）",
    "총 횟수 (비워 두면 무제한)"
  ],
  "恢复": ["Restore", "復元", "복원"],
  "恢复为暂停": ["Restore paused", "一時停止で復元", "일시정지로 복원"],
  "恢复全局设置": ["Reset to global settings", "全体設定に戻す", "전역 설정으로 재설정"],
  "恢复到根级": ["Restore at root", "ルートに復元", "최상위에 복원"],
  "恢复原设置": ["Restore original settings", "元の設定に戻す", "원래 설정 복원"],
  "恢复收听会话": ["Restore listening session", "再生セッションを復元", "재생 세션 복원"],
  "批量关联本地歌词": ["Link local lyrics in bulk", "ローカル歌詞を一括関連付け", "로컬 가사 일괄 연결"],
  "按文件同基名匹配；保留受保护歌词，保存为应用内副本并锁定。": [
    "Match file basenames. Keep protected lyrics; save and lock an in-app copy.",
    "同じベース名で照合します。保護された歌詞は保持し、アプリ内のコピーを保存して固定します。",
    "파일의 기본 이름으로 일치시킵니다. 보호된 가사는 유지하고 앱 내부 사본을 저장하여 잠급니다."
  ],
  "排除": ["Exclude", "除外", "제외"],
  "搜索书签或歌曲": ["Search bookmarks or tracks", "ブックマークや曲を検索", "북마크 또는 곡 검색"],
  "收听会话": ["Listening sessions", "再生セッション", "재생 세션"],
  "文件创建时间（兜底）": [
    "File creation time (fallback)",
    "ファイル作成日時（代替）",
    "파일 생성 시간 (대체값)"
  ],
  "无同基名候选": ["No matching basename", "同じベース名の候補なし", "일치하는 기본 이름 없음"],
  "暂不可用": ["Unavailable", "利用不可", "사용 불가"],
  "暂不可用 {0} 项：保留引用": [
    "{0} unavailable entries: references retained",
    "利用不可 {0} 件：参照を保持",
    "사용 불가 {0}개: 참조 유지"
  ],
  "暂不可用／需要重新关联": [
    "Unavailable / relinking needed",
    "利用不可／再関連付けが必要",
    "사용 불가 / 다시 연결 필요"
  ],
  "最近 {0} 天": ["Last {0} days", "過去 {0} 日間", "최근 {0}일"],
  "未评分": ["Unrated", "未評価", "평점 없음"],
  "条件": ["Condition", "条件", "조건"],
  "条件组": ["Condition group", "条件グループ", "조건 그룹"],
  "歌单回收站": ["Playlist recycle bin", "プレイリストのごみ箱", "재생목록 휴지통"],
  "此歌单的视图与列": [
    "View and columns for this playlist",
    "このプレイリストの表示と列",
    "이 재생목록의 보기 및 열"
  ],
  "永久移除": ["Remove permanently", "完全に削除", "영구 삭제"],
  "添加标签（逗号分隔）": [
    "Add tags (comma-separated)",
    "タグを追加（カンマ区切り）",
    "태그 추가 (쉼표로 구분)"
  ],
  "现有 {0} 项，将新增 {1} 项": [
    "{0} existing entries; {1} to add",
    "既存 {0} 件、追加 {1} 件",
    "기존 {0}개, 추가 예정 {1}개"
  ],
  "用户 EQ 预设": ["User EQ presets", "ユーザー EQ プリセット", "사용자 EQ 프리셋"],
  "用户预设": ["User presets", "ユーザープリセット", "사용자 프리셋"],
  "相对跳转以确认时的当前位置计算，暂停状态保持不变。": [
    "Relative seeks use the position at confirmation. Paused playback stays paused.",
    "相対移動は確定時の位置を基準にします。一時停止状態は維持します。",
    "상대 이동은 확인 시점의 위치를 기준으로 합니다. 일시정지 상태는 유지됩니다."
  ],
  "确认": ["Confirm", "確認", "확인"],
  "确认关联": ["Confirm links", "関連付けを確認", "연결 확인"],
  "移除标签（逗号分隔）": [
    "Remove tags (comma-separated)",
    "タグを削除（カンマ区切り）",
    "태그 제거 (쉼표로 구분)"
  ],
  "筛选个人标签": ["Filter personal tags", "個人タグで絞り込み", "개인 태그 필터"],
  "精确定位": ["Precise seek", "時間を指定して移動", "정밀 위치 이동"],
  "纯文本，无时间轴": [
    "Plain text, no timestamps",
    "タイムスタンプなしのテキスト",
    "타임스탬프 없는 일반 텍스트"
  ],
  "自选区间": ["Custom date range", "期間を指定", "기간 지정"],
  "轮间间隔（0–10 秒）": [
    "Interval between rounds (0–10 s)",
    "繰り返しの間隔（0～10 秒）",
    "반복 간격 (0~10초)"
  ],
  "选择本地歌词目录": ["Choose local lyrics folder", "ローカル歌詞フォルダーを選択", "로컬 가사 폴더 선택"],
  "重命名为输入名称": ["Rename to entered name", "入力した名前に変更", "입력한 이름으로 변경"],
  "预设名称": ["Preset name", "プリセット名", "프리셋 이름"],
  "评分至少": ["Minimum rating", "最低評価", "최소 평점"],
  "个人标签包含": ["Personal tag contains", "個人タグに含む", "개인 태그 포함"],
  "首次入库不早于": ["First added on or after", "初回追加日が次の日以降", "최초 추가일이 다음 날짜 이후"],
  "首次入库不晚于": ["First added on or before", "初回追加日が次の日以前", "최초 추가일이 다음 날짜 이전"],
  "属于普通歌单": ["In ordinary playlist", "通常のプレイリストに含む", "일반 재생목록에 포함"],
  "评分": ["Rating", "評価", "평점"],
  "个人标签": ["Personal tags", "個人タグ", "개인 태그"],
  "首次入库": ["First added", "初回追加", "최초 추가"],
  "未请求": ["Not requested", "未要求", "요청하지 않음"],
  "已生效": ["Active", "有効", "적용됨"],
  "练习次数已完成，已暂停": [
    "Practice completed; playback paused",
    "練習が完了し、一時停止しました",
    "연습 완료, 재생 일시정지"
  ],
  "轨号": ["Track number", "トラック番号", "트랙 번호"],
  "个人评分": ["Personal rating", "個人評価", "개인 평점"],
  "请输入 2–999": ["Enter 2–999", "2～999 を入力してください", "2~999를 입력하세요"],
  "请输入 0–10 秒": ["Enter 0–10 seconds", "0～10 秒を入力してください", "0~10초를 입력하세요"],
  "匹配详情": ["Match details", "一致の詳細", "일치 상세 정보"],
  "满足": ["Matched", "一致", "일치"],
  "不满足": ["Not matched", "不一致", "불일치"],
  "未知（不作为满足）": [
    "Unknown (not a match)",
    "不明（一致として扱いません）",
    "알 수 없음 (일치로 취급하지 않음)"
  ],
  "结果同时受基础筛选、听歌记录、条件组和结果上限影响。": [
    "Results also depend on basic filters, listening history, condition groups and the result limit.",
    "結果には基本条件、再生履歴、条件グループ、件数の上限も適用されます。",
    "결과에는 기본 필터, 청취 기록, 조건 그룹 및 결과 제한도 적용됩니다."
  ],
  "搜索歌曲": ["Search tracks", "曲を検索", "곡 검색"],
  "已列入结果": ["Included in results", "結果に含まれています", "결과에 포함됨"],
  "未列入结果": ["Not included in results", "結果に含まれていません", "결과에 포함되지 않음"],
  "关键词": ["Keywords", "キーワード", "키워드"],
  "恢复歌单": ["Restore playlist", "プレイリストを復元", "재생목록 복원"],
  "永久移除回收记录": [
    "Permanently remove recovery record",
    "復元記録を完全に削除",
    "복원 기록 영구 삭제"
  ],
  "EQ 或输出已由其他入口更改，请重新打开对比": [
    "EQ or output was changed elsewhere. Reopen comparison.",
    "EQ または出力が別の操作で変更されました。比較を開き直してください。",
    "다른 곳에서 EQ 또는 출력이 변경되었습니다. 비교를 다시 여세요"
  ],
  '10 频段 · {0} 至 {1} dB': [
    '10 bands · {0} to {1} dB',
    '10 バンド · {0}～{1} dB',
    '10 밴드 · {0}~{1} dB'
  ],
};
