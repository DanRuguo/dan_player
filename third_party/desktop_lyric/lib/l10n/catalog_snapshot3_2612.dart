// Snapshot 26.1.2-snapshot.3 UI catalog (zh keys -> [en, ja, ko]).
const Map<String, List<String>> catalogSnapshot32612 = {
  '结束前淡出音量': [
    'Fade out volume before stopping',
    '停止前に音量をフェードアウト',
    '종료 전 볼륨 서서히 줄이기',
  ],
  '倒计时可延长、缩短、暂停或继续，也可选择到时播完本曲再停，并默认在结束前 5 秒平滑淡出音量（暂停后自动恢复原音量）。按数量、播完本曲与队尾目标一次只保留一种；新设目标前先关闭 A-B 和单曲循环。已有目标被循环阻挡时，队列会提示原因，关闭循环即可继续前进。倒计时真正触发停止后，队列目标也会清除。':
      [
    'Countdowns can be extended, shortened, paused, resumed, or set to finish the current track, and smoothly fade out volume over the final 5 seconds by default (restoring your volume once paused). Only one of track count, finish-current, or end-of-queue stays active at a time; turn off A-B loop and single repeat before setting a new target. If repeat blocks an existing target, the queue explains why and resumes once repeat is turned off. When a countdown actually triggers a stop, the queue target is also cleared.',
    'カウントダウンは延長・短縮・一時停止・再開や、現在の曲が終わってから停止する設定ができ、標準で終了前の5秒間に音量をなめらかにフェードアウトします（一時停止後に元の音量へ戻ります）。曲数指定・現在の曲終了後・キュー末尾停止は同時に1つだけ有効になり、新しく設定する前に A-B リピートと1曲リピートをオフにしてください。リピートで既存目標がブロックされるとキューに理由が表示され、リピート解除後に再開します。カウントダウンが実際に停止を実行するとキュー目標も解除されます。',
    '카운트다운은 연장·단축·일시정지·재개하거나 현재 곡이 끝난 뒤 정지하도록 설정할 수 있으며, 기본값으로 종료 전 5초 동안 볼륨을 부드럽게 페이드 아웃합니다(일시정지 후 원래 볼륨으로 자동 복원). 곡 수 지정·현재 곡 종료 후·대기열 끝 정지는 한 번에 하나만 유지되며, 새 목표를 설정하기 전에 A-B 반복과 한 곡 반복을 꺼 주세요. 반복으로 기존 목표가 막히면 대기열에 사유가 표시되고 반복을 끄면 다시 진행됩니다. 카운트다운이 실제로 정지를 실행하면 대기열 목표도 함께 해제됩니다.',
  ],
};
