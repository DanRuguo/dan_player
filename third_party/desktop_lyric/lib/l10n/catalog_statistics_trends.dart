const Map<String, List<String>> catalogStatisticsTrends = {
  '最长连续收听：{0}': [
    'Longest uninterrupted listening: {0}',
    '最長連続リスニング：{0}',
    '최장 연속 청취: {0}'
  ],
  '按最近24小时已记录的连续收听片段计算；暂停或缺失的间隔不连接、不补算。': [
    'Uses recorded uninterrupted intervals in the last 24 hours. Pauses and missing intervals are not joined or filled in.',
    '過去24時間に記録された連続リスニング区間で計算します。一時停止や記録のない間隔は結合・補完しません。',
    '최근 24시간에 기록된 연속 청취 구간으로 계산합니다. 일시정지하거나 기록이 없는 간격은 연결하거나 보충하지 않습니다.'
  ],
  '按严格一周': ['Calendar week', '暦週（月〜日）', '달력 기준 주'],
  '前期收听': ['Previous period', '前期のリスニング', '이전 기간 청취'],
  '两期对比': ['Compare both periods', '両期間を比較', '두 기간 비교'],
  '周二': ['Tue', '火', '화'],
  '周四': ['Thu', '木', '목'],
  '周六': ['Sat', '土', '토'],
  '周日': ['Sun', '日', '일'],
  '未来日期，按 0 占位': ['Future date; shown as 0', '未来の日付：0で仮表示', '미래 날짜: 0으로 표시'],
  '当天未结束，仅计截至展示时间的记录': [
    'Day unfinished; records up to the display capture only',
    '当日は未終了：表示時点までの記録のみ',
    '오늘은 아직 진행 중: 표시 시점까지의 기록만 포함'
  ],
  '缺失记录，按 0 显示': ['Missing record; shown as 0', '記録なし：0と表示', '누락 기록: 0으로 표시'],
  '按周一至周日与上一周对照；今天尚未结束，未来日期和缺失记录按 0 占位，增减为暂时结果。': [
    'Compares Monday through Sunday with last week. Today is unfinished; future dates and missing records show 0. Changes are provisional.',
    '月曜から日曜を先週と比較します。今日は未終了で、未来の日付と記録のない日は0で仮表示します。増減は暫定値です。',
    '월요일부터 일요일을 지난주와 비교합니다. 오늘은 진행 중이며 미래 날짜와 누락 기록은 0으로 표시합니다. 증감은 잠정값입니다.'
  ],
  '收听趋势对比': ['Listening trends', 'リスニング傾向の比較', '청취 추세 비교'],
  '近 {0} 天': ['Last {0} days', '過去 {0} 日間', '최근 {0}일'],
  '本期收听': ['Listening in this period', '今期のリスニング時間', '이번 기간 청취 시간'],
  '相比前期': ['Change from previous period', '前期からの変化', '이전 기간 대비 변화'],
  '活跃日期': ['Active dates', '聴いた日数', '청취한 날짜'],
  '{0} / {1} 天': ['{0} / {1} days', '{0} / {1} 日', '{0} / {1}일'],
  '前期 {0} 天': ['Previous period: {0} days', '前期：{0} 日', '이전 기간: {0}일'],
  '本期（实线）': ['This period (solid)', '今期（実線）', '이번 기간 (실선)'],
  '前期（虚线）': ['Previous period (dashed)', '前期（破線）', '이전 기간 (점선)'],
  '前期无收听记录，不计算百分比。': [
    'No listening was recorded in the previous period; no percentage is calculated.',
    '前期のリスニング記録がないため、変化率は計算しません。',
    '이전 기간에 청취 기록이 없어 백분율을 계산하지 않습니다.',
  ],
  '每日最高 {0}': ['Daily maximum: {0}', '1 日の最大：{0}', '하루 최대: {0}'],
  '逐日对照': ['Daily comparison', '日ごとの比較', '날짜별 비교'],
  '悬停或点按查看日期；聚焦图表后可用方向键、Home 和 End。': [
    'Hover or tap to inspect a date. Focus the chart to use arrow keys, Home and End.',
    'ホバーまたはタップで日付を確認できます。グラフにフォーカスして矢印キー、Home、End でも移動できます。',
    '마우스를 올리거나 눌러 날짜를 확인하세요. 차트에 초점을 맞추면 방향키, Home, End로 이동할 수 있습니다.',
  ],
  '比较已结束的日历日期，不含今天；缺失日期按 0 显示，不代表此前已完整记录。': [
    'Compares finished calendar dates and excludes today. Missing dates display as 0; this does not imply complete earlier recording.',
    '終了した暦日を比較し、今日は含めません。記録のない日は 0 と表示しますが、過去がすべて記録済みという意味ではありません。',
    '오늘을 제외한 완료된 날짜를 비교합니다. 기록이 없는 날은 0으로 표시하며, 이전 기록이 모두 수집되었다는 뜻은 아닙니다.',
  ],
};
