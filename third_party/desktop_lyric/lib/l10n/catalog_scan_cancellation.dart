const catalogScanCancellation = <String, List<String>>{
  '正在扫描曲库': ['Scanning the library', 'ライブラリをスキャン中', '라이브러리 검색 중'],
  '正在取消扫描': ['Cancelling the scan', 'スキャンを中止中', '검색 취소 중'],
  '正在提交曲库': ['Saving the library', 'ライブラリを保存中', '라이브러리 저장 중'],
  '扫描已取消': ['Scan cancelled', 'スキャンを中止しました', '검색 취소됨'],
  '曲库刷新完成': ['Library refresh complete', 'ライブラリの更新が完了しました', '라이브러리 새로고침 완료'],
  '曲库刷新失败': ['Library refresh failed', 'ライブラリの更新に失敗しました', '라이브러리 새로고침 실패'],
  '可取消扫描；关闭此窗口后继续在后台处理。': [
    'You can cancel the scan. Closing this window lets it continue in the background.',
    'スキャンは中止できます。このウィンドウを閉じるとバックグラウンドで続行します。',
    '검색을 취소할 수 있습니다. 이 창을 닫으면 백그라운드에서 계속 진행합니다.',
  ],
  '正在等待当前读取安全结束，原曲库仍保留。': [
    'Waiting for the current read to finish safely. Your existing library is preserved.',
    '現在の読み取りが安全に終わるのを待っています。既存のライブラリは保持されます。',
    '현재 읽기 작업이 안전하게 끝나기를 기다립니다. 기존 라이브러리는 유지됩니다.',
  ],
  '正在保存完整索引并同步曲库，此阶段不能取消。': [
    'Saving the complete index and syncing the library. This stage cannot be cancelled.',
    '完全な索引を保存し、ライブラリを同期しています。この段階では中止できません。',
    '완전한 색인을 저장하고 라이브러리를 동기화합니다. 이 단계는 취소할 수 없습니다.',
  ],
  '原曲库未改变，可随时重新扫描。': [
    'Your library has not changed. You can scan again at any time.',
    '既存のライブラリは変更されていません。いつでも再スキャンできます。',
    '기존 라이브러리는 변경되지 않았습니다. 언제든 다시 검색할 수 있습니다.',
  ],
  '{0} 首歌曲保留原信息，下次刷新会重试。': [
    '{0} songs kept their previous information. The next refresh will retry.',
    '{0}曲は以前の情報を保持しています。次回の更新で再試行します。',
    '{0}곡의 기존 정보를 유지했습니다. 다음 새로고침에서 다시 시도합니다.',
  ],
  '未完成的刷新已结束，请查看提示后重试。': [
    'The refresh ended before completion. Review the message and try again.',
    '更新は完了せずに終了しました。メッセージを確認して再試行してください。',
    '새로고침이 완료되지 못하고 종료되었습니다. 메시지를 확인한 후 다시 시도하세요.',
  ],
  '取消扫描': ['Cancel scan', 'スキャンを中止', '검색 취소'],
  '转入后台': ['Continue in background', 'バックグラウンドで続行', '백그라운드에서 계속'],
  '查看扫描进度': ['View scan progress', 'スキャンの進行状況', '검색 진행 상황 보기'],
  '扫描已取消，原曲库未改变': [
    'Scan cancelled. Your library has not changed.',
    'スキャンを中止しました。ライブラリは変更されていません。',
    '검색을 취소했습니다. 라이브러리는 변경되지 않았습니다.'
  ],
  '已取消扫描，正在使用上次曲库。': [
    'Scan cancelled. Using the previous library.',
    'スキャンを中止し、前回のライブラリを使用しています。',
    '검색을 취소했습니다. 이전 라이브러리를 사용합니다.'
  ],
};
