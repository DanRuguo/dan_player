const Map<String, List<String>> catalogSmartRandom = {
  '歌曲名称': ['Track title', '曲名', '곡 이름'],
  '歌手': ['Artist', 'アーティスト', '아티스트'],
  '随机抽取': ['Random sample', 'ランダム抽出', '무작위 추출'],
  '换一批': ['New batch', '別の組を抽出', '다시 뽑기'],
  '随机抽取 N 首；留空打乱全部结果': [
    'Sample N tracks; leave blank to shuffle all matches',
    'N 曲をランダム抽出。空欄なら全結果をシャッフル',
    'N곡을 무작위로 추출합니다. 비우면 모든 결과를 섞습니다',
  ],
  '每批按歌曲身份不重复抽取；不同批次可能重合。保存智能规则后，下次打开会重新抽样；加入普通歌单保留当前批次。': [
    'Each batch contains distinct tracks; batches may overlap. Saved smart rules sample again when reopened. Adding to a regular playlist keeps this batch.',
    '同じ曲は一組に一度だけ入り、別の組には再び入る場合があります。スマートルールを保存すると次回開く際に再抽出します。通常のプレイリストには現在の組を保存します。',
    '한 번에 같은 곡을 중복 추출하지 않지만, 다른 묶음에는 다시 포함될 수 있습니다. 스마트 규칙을 저장하면 다음에 열 때 새로 추출합니다. 일반 재생목록에는 현재 묶음을 저장합니다.',
  ],
};
