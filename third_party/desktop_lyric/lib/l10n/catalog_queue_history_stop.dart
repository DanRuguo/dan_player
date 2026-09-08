const Map<String, List<String>> catalogQueueHistoryStop = {
  '撤销队列整理 · Ctrl+Z': [
    'Undo queue edit · Ctrl+Z',
    'キュー編集を元に戻す · Ctrl+Z',
    '대기열 편집 실행 취소 · Ctrl+Z'
  ],
  '重做队列整理 · Ctrl+Y / Ctrl+Shift+Z': [
    'Redo queue edit · Ctrl+Y / Ctrl+Shift+Z',
    'キュー編集をやり直す · Ctrl+Y / Ctrl+Shift+Z',
    '대기열 편집 다시 실행 · Ctrl+Y / Ctrl+Shift+Z'
  ],
  '播完此条后停止': ['Stop after this queue entry', 'この項目の再生後に停止', '이 항목 재생 후 중지'],
  '播完设置时这轮队列后停止': [
    'Stop after the current queue round',
    '設定時のキューの末尾で停止',
    '설정 시점의 대기열 끝에서 중지'
  ],
  '取消停止目标': ['Cancel stop target', '停止対象を解除', '중지 대상 취소'],
  '停止目标：{0}': ['Stop after: {0}', '停止対象：{0}', '중지 대상: {0}'],
  '请先关闭 A-B 循环，再设置停止目标': [
    'Turn off A-B repeat before setting a stop target',
    '停止対象を設定するには A-B リピートを解除してください',
    '중지 대상을 설정하려면 A-B 반복을 꺼 주세요'
  ],
  '请先关闭单曲循环，再设置停止目标': [
    'Turn off repeat-one before setting a stop target',
    '停止対象を設定するには1曲リピートを解除してください',
    '중지 대상을 설정하려면 한 곡 반복을 꺼 주세요'
  ],
  '停止目标已保留；请关闭 A-B 循环以继续前进': [
    'Stop target kept; turn off A-B repeat to advance',
    '停止対象を保持しました。先に進むには A-B リピートを解除してください',
    '중지 대상을 유지했습니다. 계속 진행하려면 A-B 반복을 꺼 주세요'
  ],
  '停止目标已保留；请关闭单曲循环以继续前进': [
    'Stop target kept; turn off repeat-one to advance',
    '停止対象を保持しました。先に進むには1曲リピートを解除してください',
    '중지 대상을 유지했습니다. 계속 진행하려면 한 곡 반복을 꺼 주세요'
  ],
  '停止目标已被移除，本次停止已取消': [
    'Stop target removed; this stop was cancelled',
    '対象が削除されたため、今回の停止を解除しました',
    '대상이 제거되어 이번 중지를 취소했습니다'
  ],
  '播放来源已替换，本次停止已取消': [
    'Playback source replaced; this stop was cancelled',
    '再生元が変更されたため、今回の停止を解除しました',
    '재생 소스가 바뀌어 이번 중지를 취소했습니다'
  ],
  '已手动越过停止目标，本次停止已取消': [
    'Skipped past the target; this stop was cancelled',
    '停止対象を手動で飛ばしたため、今回の停止を解除しました',
    '중지 대상을 수동으로 건너뛰어 이번 중지를 취소했습니다'
  ],
  '停止目标播放失败，本次停止已取消': [
    'Target could not play; this stop was cancelled',
    '対象を再生できなかったため、今回の停止を解除しました',
    '대상을 재생하지 못해 이번 중지를 취소했습니다'
  ],
  '睡眠定时已到，本次停止目标已取消': [
    'Sleep timer expired; the stop target was cancelled',
    'スリープタイマーが満了したため、停止対象を解除しました',
    '취침 타이머가 끝나 중지 대상을 취소했습니다'
  ],
  '已取消本次停止目标': ['Stop target cancelled', '今回の停止対象を解除しました', '이번 중지 대상을 취소했습니다'],
  '已播完停止目标，本次停止已完成': [
    'Target finished; playback stopped',
    '停止対象の再生が完了しました',
    '중지 대상 재생을 마쳤습니다'
  ],
  '队列过大，当前操作不能撤销或重做': [
    'Queue too large to retain undo or redo for this edit',
    'キューが大きすぎるため、この操作は元に戻す・やり直しができません',
    '대기열이 너무 커서 이 작업을 취소하거나 다시 실행할 수 없습니다'
  ],
  '文件已删除，队列历史已清空': [
    'File deleted; queue history cleared',
    'ファイル削除によりキュー履歴を消去しました',
    '파일이 삭제되어 대기열 기록을 지웠습니다'
  ],
  '已切换播放出现项，队列历史已清空': [
    'Playback entry changed; queue history cleared',
    '再生項目の切り替えによりキュー履歴を消去しました',
    '재생 항목이 바뀌어 대기열 기록을 지웠습니다'
  ],
  '播放队列已替换，队列历史已清空': [
    'Queue replaced; history cleared',
    'キューの置換により履歴を消去しました',
    '대기열이 교체되어 기록을 지웠습니다'
  ],
  '随机顺序已改变，队列历史已清空': [
    'Shuffle order changed; queue history cleared',
    'シャッフル順の変更によりキュー履歴を消去しました',
    '무작위 순서가 바뀌어 대기열 기록을 지웠습니다'
  ],
  '播放上下文已改变，队列历史已清空': [
    'Playback context changed; queue history cleared',
    '再生状態の変更によりキュー履歴を消去しました',
    '재생 상태가 바뀌어 대기열 기록을 지웠습니다'
  ],
  '没有可重做的队列操作': [
    'No queue edit to redo',
    'やり直せるキュー操作はありません',
    '다시 실행할 대기열 작업이 없습니다'
  ],
  '没有可撤销的队列操作': [
    'No queue edit to undo',
    '元に戻せるキュー操作はありません',
    '취소할 대기열 작업이 없습니다'
  ],
  '歌词位置超出歌曲时长': [
    'Lyric position is outside the track duration',
    '歌詞の位置が曲の長さを超えています',
    '가사 위치가 곡 길이를 벗어났습니다'
  ],
};
