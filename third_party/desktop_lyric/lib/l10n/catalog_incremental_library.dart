const catalogIncrementalLibrary = <String, List<String>>{
  '曲库操作正在进行，请等待刷新或歌曲信息保存完成后重试': [
    'A library operation is in progress. Wait for the refresh or song information save to finish, then try again.',
    'ライブラリを処理中です。更新または曲情報の保存が完了してから再試行してください。',
    '라이브러리 작업이 진행 중입니다. 새로고침 또는 곡 정보 저장이 완료된 후 다시 시도하세요.',
  ],
  '音乐库已刷新，{0}首暂时保留原信息或文件名，下次刷新会重试': [
    'Library refreshed. {0} songs kept their previous information or filename; the next refresh will retry.',
    'ライブラリを更新しました。{0}曲は以前の情報またはファイル名を保持し、次回の更新で再試行します。',
    '라이브러리를 새로고쳤습니다. {0}곡은 이전 정보 또는 파일 이름을 유지하며, 다음 새로고침 때 다시 시도합니다.',
  ],
  '索引已更新，但界面同步未完成，请重新打开应用': [
    'The index was updated, but the interface could not finish syncing. Please reopen the app.',
    '索引は更新されましたが、画面の同期を完了できませんでした。アプリを開き直してください。',
    '색인은 업데이트되었지만 화면 동기화가 완료되지 않았습니다. 앱을 다시 열어 주세요.',
  ],
  '增量刷新': ['Incremental refresh', '差分を更新', '변경 사항 새로고침'],
  '增量刷新只读取新增或改动歌曲；完整刷新重新读取全部歌曲信息': [
    'Incremental refresh reads new or changed songs; full refresh rereads all song information.',
    '差分更新では追加・変更された曲だけを読み取り、完全更新では全曲の情報を再取得します。',
    '변경 사항 새로고침은 추가·변경된 곡만 읽고, 전체 새로고침은 모든 곡 정보를 다시 읽습니다.',
  ],
  '按路径、大小和修改时间检查；旧索引首次可能需要补读，内容变化但大小和时间均未变时请使用完整刷新': [
    'Checks paths, sizes and modification times. Older indexes may need an initial reread. Use full refresh if content changed without a size or timestamp change.',
    'パス・サイズ・更新日時を確認します。古い索引は初回の再読込が必要な場合があります。サイズと日時を変えずに内容を編集した場合は完全更新してください。',
    '경로, 크기, 수정 시간을 확인합니다. 이전 색인은 처음에 다시 읽어야 할 수 있습니다. 크기와 시간이 그대로인 채 내용이 바뀌었다면 전체 새로고침을 사용하세요.',
  ],
  '刷新未完成，原曲库仍保留，请检查文件夹访问权限后重试': [
    'Refresh did not complete. The existing library is retained. Check folder access and try again.',
    '更新を完了できませんでした。既存のライブラリは保持されています。フォルダーへのアクセスを確認して再試行してください。',
    '새로고침을 완료하지 못했습니다. 기존 라이브러리는 유지됩니다. 폴더 접근 권한을 확인한 후 다시 시도하세요.',
  ],
};
